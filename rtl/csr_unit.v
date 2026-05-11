// =============================================================================
// ARES — Adaptive Radiation-hardened Execution System
// Module  : csr_unit.v
// Purpose : Privilege-state CSR file with M/S/U trap control and return logic.
//
// Supported CSRs
//   0x300  mstatus    Machine status register
//   0x301  misa       ISA and extensions (RO)
//   0x302  medeleg    Machine exception delegation
//   0x303  mideleg    Machine interrupt delegation
//   0x304  mie        Machine interrupt enable
//   0x305  mtvec      Trap-handler base address
//   0x340  mscratch   Scratch for trap handlers
//   0x341  mepc       Exception program counter
//   0x342  mcause     Trap cause
//   0x343  mtval      Bad address / instruction
//   0x344  mip        Machine interrupt pending (RO)
//   0x3A0  pmpcfg0    PMP config
//   0x3B0  pmpaddr0   PMP address
//   0x744  mnstatus   Non-standard   (stub RAZ/WI)
//   0x7C0  ares_status      ARES sticky fault status
//   0x7C1  ares_fault_count ARES fault counter
//   0x7C2  ares_fault_info  ARES last fault metadata
//   0x7C3  ares_control     ARES telemetry control
//   0xF11  mvendorid  Vendor ID (RO)
//   0xF12  marchid    Architecture ID (RO)
//   0xF13  mimpid     Implementation ID (RO)
//   0xF14  mhartid    Hart ID (RO = 0)
//   0x100  sstatus    Supervisor status
//   0x104  sie        Supervisor interrupt enable
//   0x105  stvec      Supervisor trap vector
//   0x106  scounteren Supervisor counter enable
//   0x140  sscratch   Supervisor scratch
//   0x141  sepc       Supervisor exception PC
//   0x142  scause     Supervisor trap cause
//   0x143  stval      Supervisor trap value
//   0x144  sip        Supervisor interrupt pending
//   0x180  satp       Address translation (stub)
//   0x306  mcounteren Machine counter enable
// =============================================================================

`timescale 1ns/1ps

module csr_unit (
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // CSR instruction interface  (driven by EX stage)
    // -------------------------------------------------------------------------
    input  wire        csr_en,      // instruction is a CSR op
    input  wire [11:0] csr_addr,    // CSR address field
    input  wire [2:0]  csr_op,      // funct3: 1=RW 2=RS 3=RC 5=RWI 6=RSI 7=RCI
    input  wire [63:0] csr_wdata,   // write data from rs1
    input  wire [4:0]  csr_uimm,    // zero-extended uimm[4:0] for *I variants
    output reg  [63:0] csr_rdata,   // read data (combinational)

    // -------------------------------------------------------------------------
    // Trap interface  (synchronous exceptions)
    // -------------------------------------------------------------------------
    input  wire        trap_en,     // exception this cycle
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [63:0] trap_pc,     // PC of faulting instruction
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [63:0] trap_cause,  // mcause encoding
    input  wire [63:0] trap_tval,   // mtval encoding

    // -------------------------------------------------------------------------
    // Machine interrupt interface
    // -------------------------------------------------------------------------
    input  wire        irq_msip,
    input  wire        irq_mtip,
    input  wire        irq_meip,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [63:0] interrupt_pc,
    /* verilator lint_on UNUSEDSIGNAL */

    // -------------------------------------------------------------------------
    // Return interface
    // -------------------------------------------------------------------------
    input  wire        mret_en,     // MRET instruction
    input  wire        sret_en,     // SRET instruction
    output wire [63:0] mret_pc,     // mepc  (return address)
    output wire [63:0] sret_pc,     // sepc  (return address)

    // -------------------------------------------------------------------------
    // ARES fault telemetry interface
    // -------------------------------------------------------------------------
    input  wire        ares_fault_event,
    input  wire [3:0]  ares_fault_code,
    input  wire [63:0] ares_fault_info,

    // -------------------------------------------------------------------------
    // Trap redirect to IF stage
    // -------------------------------------------------------------------------
    output wire [63:0] tvec_base,   // mtvec[63:2] << 2
    output wire        trap_redirect,
    output wire [1:0]  current_priv,
    output wire        mstatus_tsr,
    output wire        mstatus_tvm
);

    // =========================================================================
    // Identification constants
    // =========================================================================
    localparam [63:0] MVENDORID = 64'h0000_0000_0000_0000;  // non-commercial
    localparam [63:0] MARCHID   = 64'h0000_0000_4152_4553;  // "ARES" ASCII
    localparam [63:0] MIMPID    = 64'h0000_0000_0000_0001;  // version 1
    localparam [63:0] MHARTID   = 64'h0000_0000_0000_0000;  // hart 0
    localparam [63:0] MIP_MSIP  = 64'h0000_0000_0000_0008;
    localparam [63:0] MIP_SSIP  = 64'h0000_0000_0000_0002;
    localparam [63:0] MIP_MTIP  = 64'h0000_0000_0000_0080;
    localparam [63:0] MIP_STIP  = 64'h0000_0000_0000_0020;
    localparam [63:0] MIP_MEIP  = 64'h0000_0000_0000_0800;
    localparam [63:0] MIP_SEIP  = 64'h0000_0000_0000_0200;
    localparam [63:0] MIP_M_MASK = MIP_MSIP | MIP_MTIP | MIP_MEIP;
    localparam [63:0] MIP_S_MASK = MIP_SSIP | MIP_STIP | MIP_SEIP;
    localparam [1:0]  PRV_U = 2'b00;
    localparam [1:0]  PRV_S = 2'b01;
    localparam [1:0]  PRV_M = 2'b11;
    // MXL=2 (RV64), extensions: A(0), I(8), M(12), S(18), U(20)
    localparam [63:0] MISA      = {2'b10, 36'h0, 26'h141101};

    // =========================================================================
    // CSR storage
    // =========================================================================

    // mstatus fields used by the current M/S/U base
    reg [1:0]  priv_mode;
    reg        mstatus_sie;    // bit 1
    reg        mstatus_mie;    // bit  3
    reg        mstatus_spie;   // bit 5
    reg        mstatus_mpie;   // bit  7
    reg        mstatus_spp;    // bit 8
    reg [1:0]  mstatus_mpp;    // bits 12:11
    reg        mstatus_mprv;   // bit 17
    reg        mstatus_sum;    // bit 18
    reg        mstatus_mxr;    // bit 19
    reg        mstatus_tvm_reg; // bit 20
    reg        mstatus_tsr_reg;
    reg [63:0] mtvec;
    reg [63:0] sscratch;
    reg [63:0] mscratch;
    reg [63:0] sepc;
    reg [63:0] mepc;
    reg [63:0] scause;
    reg [63:0] mcause;
    reg [63:0] stval;
    reg [63:0] mtval;
    reg [63:0] satp;
    reg [63:0] scounteren;
    reg [63:0] mcounteren;
    reg [63:0] mie_reg;
    reg [63:0] mip_reg;   // software-writable subset only
    reg [63:0] medeleg;
    reg [63:0] mideleg;
    reg [63:0] stvec;
    reg [63:0] pmpcfg0;
    reg [63:0] pmpaddr0;
    reg        ares_fault_seen;
    reg [3:0]  ares_last_fault_code;
    reg [63:0] ares_fault_count;
    reg [63:0] ares_fault_info_reg;
    reg [63:0] ares_control;

    wire [63:0] ares_status = {
        56'h0,
        ares_last_fault_code,
        3'h0,
        ares_fault_seen
    };

    // Reconstruct full mstatus/sstatus for reads
    wire [63:0] mstatus_rd = 64'h0000_0002_0000_0000 |
                             (mstatus_sie  ? 64'h0000_0000_0000_0002 : 64'h0) |
                             (mstatus_mie  ? 64'h0000_0000_0000_0008 : 64'h0) |
                             (mstatus_spie ? 64'h0000_0000_0000_0020 : 64'h0) |
                             (mstatus_mpie ? 64'h0000_0000_0000_0080 : 64'h0) |
                             (mstatus_spp  ? 64'h0000_0000_0000_0100 : 64'h0) |
                             (mstatus_mprv ? 64'h0000_0000_0002_0000 : 64'h0) |
                             (mstatus_sum  ? 64'h0000_0000_0004_0000 : 64'h0) |
                             (mstatus_mxr  ? 64'h0000_0000_0008_0000 : 64'h0) |
                             (mstatus_tvm_reg ? 64'h0000_0000_0010_0000 : 64'h0) |
                             ({62'h0, mstatus_mpp} << 11);
    wire [63:0] sstatus_mask = 64'h0000_0003_000c_0122;
    wire [63:0] sstatus_rd = mstatus_rd & sstatus_mask;
    wire [63:0] mip_hw = (irq_msip ? MIP_MSIP : 64'h0) |
                         (irq_mtip ? MIP_MTIP : 64'h0) |
                         (irq_meip ? MIP_MEIP : 64'h0);
    wire [63:0] mip_rd = (mip_reg & ~(MIP_M_MASK | MIP_S_MASK)) | mip_hw |
                         (mip_reg & MIP_S_MASK);
    wire [63:0] mie_s_mask = MIP_S_MASK;
    wire [63:0] mip_s_mask = MIP_S_MASK;
    wire [63:0] sie_rd = mie_reg & mie_s_mask;
    wire [63:0] sip_rd = mip_rd & mip_s_mask;
    wire [63:0] pending_machine_interrupts = mie_reg & mip_rd & MIP_M_MASK;
    wire [63:0] pending_supervisor_interrupts = mie_reg & mip_rd & MIP_S_MASK;
    wire [63:0] pending_machine_targets = (priv_mode != PRV_M) ?
                                          (pending_machine_interrupts & ~mideleg) :
                                          pending_machine_interrupts;
    wire [63:0] pending_supervisor_targets = (priv_mode != PRV_M) ?
                                             (pending_supervisor_interrupts & mideleg) :
                                             64'h0;
    wire machine_interrupts_enabled = (priv_mode != PRV_M) || mstatus_mie;
    wire supervisor_interrupts_enabled = (priv_mode == PRV_U) ||
                                         ((priv_mode == PRV_S) && mstatus_sie);
    wire [63:0] pending_interrupts = (machine_interrupts_enabled ? pending_machine_targets : 64'h0) |
                                     (supervisor_interrupts_enabled ? pending_supervisor_targets : 64'h0);
    wire [63:0] interrupt_cause = pending_interrupts[11] ? 64'h8000_0000_0000_000B :
                                  pending_interrupts[9]  ? 64'h8000_0000_0000_0009 :
                                  pending_interrupts[7]  ? 64'h8000_0000_0000_0007 :
                                  pending_interrupts[5]  ? 64'h8000_0000_0000_0005 :
                                  pending_interrupts[3]  ? 64'h8000_0000_0000_0003 :
                                  pending_interrupts[1]  ? 64'h8000_0000_0000_0001 :
                                                           64'h0;
    wire interrupt_to_supervisor = (priv_mode != PRV_M) && interrupt_cause[63] &&
                                   mideleg[interrupt_cause[5:0]];
    wire interrupt_taken = !trap_en && !mret_en && !sret_en && (pending_interrupts != 64'h0);
    wire exception_to_supervisor = (priv_mode != PRV_M) && !trap_cause[63] &&
                                   medeleg[trap_cause[5:0]];
    wire [63:0] trap_vector = (interrupt_taken && interrupt_to_supervisor) ||
                              (trap_en && exception_to_supervisor) ? {stvec[63:2], 2'b00} :
                                                                     {mtvec[63:2], 2'b00};
    wire [1:0] return_priv = mret_en ? mstatus_mpp :
                             mstatus_spp ? PRV_S : PRV_U;

    // =========================================================================
    // Write-data mux: register vs. immediate
    // =========================================================================
    wire is_imm = (csr_op == 3'h5) || (csr_op == 3'h6) || (csr_op == 3'h7);
    wire [63:0] wd = is_imm ? {59'h0, csr_uimm} : csr_wdata;

    // Compute next CSR value according to funct3
    function [63:0] csr_next;
        input [63:0] old;
        input [63:0] w;
        input [2:0]  op;
        begin
            case (op)
                3'h1, 3'h5: csr_next = w;            // CSRRW  / CSRRWI
                3'h2, 3'h6: csr_next = old |  w;     // CSRRS  / CSRRSI
                3'h3, 3'h7: csr_next = old & ~w;     // CSRRC  / CSRRCI
                default:    csr_next = old;
            endcase
        end
    endfunction

    // =========================================================================
    // CSR Read  (combinational)
    // =========================================================================
    always @(*) begin
        case (csr_addr)
            // M-mode core
            12'h300: csr_rdata = mstatus_rd;
            12'h301: csr_rdata = MISA;
            12'h302: csr_rdata = medeleg;
            12'h303: csr_rdata = mideleg;
            12'h304: csr_rdata = mie_reg;
            12'h305: csr_rdata = mtvec;
            12'h340: csr_rdata = mscratch;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'h343: csr_rdata = mtval;
            12'h344: csr_rdata = mip_rd;
            // Supervisor view
            12'h100: csr_rdata = sstatus_rd;
            12'h102: csr_rdata = 64'h0;
            12'h103: csr_rdata = 64'h0;
            12'h104: csr_rdata = sie_rd;
            12'h105: csr_rdata = stvec;
            12'h106: csr_rdata = scounteren;
            12'h140: csr_rdata = sscratch;
            12'h141: csr_rdata = sepc;
            12'h142: csr_rdata = scause;
            12'h143: csr_rdata = stval;
            12'h144: csr_rdata = sip_rd;
            12'h180: csr_rdata = satp;
            12'h306: csr_rdata = mcounteren;
            // PMP / non-standard
            12'h3A0: csr_rdata = pmpcfg0;
            12'h3B0: csr_rdata = pmpaddr0;
            12'h744: csr_rdata = 64'h0;
            12'h7C0: csr_rdata = ares_status;
            12'h7C1: csr_rdata = ares_fault_count;
            12'h7C2: csr_rdata = ares_fault_info_reg;
            12'h7C3: csr_rdata = ares_control;
            // Identification (read-only)
            12'hF11: csr_rdata = MVENDORID;
            12'hF12: csr_rdata = MARCHID;
            12'hF13: csr_rdata = MIMPID;
            12'hF14: csr_rdata = MHARTID;
            default:  csr_rdata = 64'h0;
        endcase
    end

    // mstatus write helper — avoid bit-slicing function return in always block
    /* verilator lint_off UNUSEDSIGNAL */
    wire [63:0] mstatus_next = csr_next(mstatus_rd, wd, csr_op);
    wire [63:0] ares_control_next = csr_next(ares_control, wd, csr_op);
    wire [63:0] mtvec_next = csr_next(mtvec, wd, csr_op);
    wire [63:0] mepc_next = csr_next(mepc, wd, csr_op);
    wire [63:0] sstatus_next = csr_next(sstatus_rd, wd, csr_op);
    wire [63:0] sepc_next = csr_next(sepc, wd, csr_op);
    wire [63:0] stvec_next = csr_next(stvec, wd, csr_op);
    wire [63:0] mie_next = csr_next(mie_reg, wd, csr_op);
    wire [63:0] mip_next = csr_next(mip_reg, wd, csr_op);
    wire [63:0] satp_next = csr_next(satp, wd, csr_op);
    wire [63:0] pmpcfg0_next_raw = csr_next(pmpcfg0, wd, csr_op);
    wire [63:0] pmpcfg0_next = {56'h0,
                                pmpcfg0_next_raw[7],
                                2'b00,
                                pmpcfg0_next_raw[4:3],
                                pmpcfg0_next_raw[0] ? pmpcfg0_next_raw[2:0]
                                                    : {pmpcfg0_next_raw[2], 1'b0, pmpcfg0_next_raw[0]}};
    wire [63:0] sscratch_next = csr_next(sscratch, wd, csr_op);
    wire [63:0] scause_next = csr_next(scause, wd, csr_op);
    wire [63:0] stval_next = csr_next(stval, wd, csr_op);
    wire [63:0] mcounteren_next = csr_next(mcounteren, wd, csr_op);
    wire [63:0] scounteren_next = csr_next(scounteren, wd, csr_op);
    /* verilator lint_on UNUSEDSIGNAL */
    wire [1:0] mstatus_next_mpp = mstatus_next[12:11];
    wire       mstatus_next_spp = mstatus_next[8];
    wire       mstatus_next_spie = mstatus_next[5];
    wire       mstatus_next_sie = mstatus_next[1];
    wire        mstatus_next_mie = mstatus_next[3];
    wire        mstatus_next_mpie = mstatus_next[7];
    wire        mstatus_next_mprv = mstatus_next[17];
    wire        mstatus_next_sum = mstatus_next[18];
    wire        mstatus_next_mxr = mstatus_next[19];
    wire        mstatus_next_tvm = mstatus_next[20];
    wire        mstatus_next_tsr = wd[22] ? 1'b1 : (csr_op == 3'h3 || csr_op == 3'h7) ? 1'b0 : mstatus_tsr_reg;
    wire        ares_control_next_enable = ares_control_next[0];
    wire        ares_control_next_clear = ares_control_next[1];

    // =========================================================================
    // CSR Write + Trap + Return
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            priv_mode     <= PRV_M;
            mstatus_sie   <= 1'b0;
            mstatus_mie  <= 1'b0;
            mstatus_spie <= 1'b0;
            mstatus_mpie <= 1'b1;
            mstatus_spp  <= 1'b0;
            mstatus_mpp  <= PRV_M;
            mstatus_mprv <= 1'b0;
            mstatus_sum  <= 1'b0;
            mstatus_mxr  <= 1'b0;
            mstatus_tvm_reg <= 1'b0;
            mstatus_tsr_reg <= 1'b0;
            mtvec        <= 64'h0;
            sscratch     <= 64'h0;
            mscratch     <= 64'h0;
            sepc         <= 64'h0;
            mepc         <= 64'h0;
            scause       <= 64'h0;
            mcause       <= 64'h0;
            stval        <= 64'h0;
            mtval        <= 64'h0;
            satp         <= 64'h0;
            scounteren   <= 64'h0;
            mcounteren   <= 64'h0;
            mie_reg      <= 64'h0;
            mip_reg      <= 64'h0;
            medeleg      <= 64'h0;
            mideleg      <= 64'h0;
            stvec        <= 64'h0;
            pmpcfg0      <= 64'h0;
            pmpaddr0     <= 64'h0;
        end
        else if (trap_en) begin
            if (exception_to_supervisor) begin
                sepc         <= {trap_pc[63:1], 1'b0};
                scause       <= trap_cause;
                stval        <= trap_tval;
                mstatus_spie <= mstatus_sie;
                mstatus_sie  <= 1'b0;
                mstatus_spp  <= (priv_mode == PRV_S);
                priv_mode    <= PRV_S;
            end else begin
                mepc         <= {trap_pc[63:1], 1'b0};
                mcause       <= trap_cause;
                mtval        <= trap_tval;
                mstatus_mpie <= mstatus_mie;
                mstatus_mie  <= 1'b0;
                mstatus_mpp  <= priv_mode;
                priv_mode    <= PRV_M;
            end
        end
        else if (interrupt_taken) begin
            if (interrupt_to_supervisor) begin
                sepc         <= {interrupt_pc[63:1], 1'b0};
                scause       <= interrupt_cause;
                stval        <= 64'h0;
                mstatus_spie <= mstatus_sie;
                mstatus_sie  <= 1'b0;
                mstatus_spp  <= (priv_mode == PRV_S);
                priv_mode    <= PRV_S;
            end else begin
                mepc         <= {interrupt_pc[63:1], 1'b0};
                mcause       <= interrupt_cause;
                mtval        <= 64'h0;
                mstatus_mpie <= mstatus_mie;
                mstatus_mie  <= 1'b0;
                mstatus_mpp  <= priv_mode;
                priv_mode    <= PRV_M;
            end
        end
        else if (mret_en) begin
            priv_mode    <= return_priv;
            mstatus_mie  <= mstatus_mpie;
            mstatus_mpie <= 1'b1;
            mstatus_mpp  <= PRV_U;
            if (return_priv != PRV_M)
                mstatus_mprv <= 1'b0;
        end
        else if (sret_en) begin
            priv_mode     <= return_priv;
            mstatus_sie   <= mstatus_spie;
            mstatus_spie  <= 1'b1;
            mstatus_spp   <= 1'b0;
            mstatus_mprv  <= 1'b0;
        end
        else if (csr_en) begin
            case (csr_addr)
                12'h300: begin
                    mstatus_sie  <= mstatus_next_sie;
                    mstatus_mie  <= mstatus_next_mie;
                    mstatus_spie <= mstatus_next_spie;
                    mstatus_mpie <= mstatus_next_mpie;
                    mstatus_spp  <= mstatus_next_spp;
                    mstatus_mpp  <= mstatus_next_mpp;
                    mstatus_mprv <= mstatus_next_mprv;
                    mstatus_sum  <= mstatus_next_sum;
                    mstatus_mxr  <= mstatus_next_mxr;
                    mstatus_tvm_reg <= mstatus_next_tvm;
                    mstatus_tsr_reg <= mstatus_next_tsr;
                end
                12'h302: medeleg  <= csr_next(medeleg,  wd, csr_op);
                12'h303: mideleg  <= csr_next(mideleg,  wd, csr_op);
                12'h304: mie_reg  <= mie_next;
                12'h305: mtvec    <= {mtvec_next[63:2], 2'b00};
                12'h306: mcounteren <= mcounteren_next;
                12'h340: mscratch <= csr_next(mscratch, wd, csr_op);
                12'h341: mepc     <= {mepc_next[63:1], 1'b0};
                12'h342: mcause   <= csr_next(mcause,   wd, csr_op);
                12'h343: mtval    <= csr_next(mtval,    wd, csr_op);
                12'h344: mip_reg  <= mip_next;
                12'h100: begin
                    mstatus_sie  <= sstatus_next[1];
                    mstatus_spie <= sstatus_next[5];
                    mstatus_spp  <= sstatus_next[8];
                    mstatus_sum  <= sstatus_next[18];
                    mstatus_mxr  <= sstatus_next[19];
                end
                12'h104: mie_reg  <= (mie_reg & ~MIP_S_MASK) | (csr_next(sie_rd, wd, csr_op) & MIP_S_MASK);
                12'h105: stvec    <= {stvec_next[63:2], 2'b00};
                12'h106: scounteren <= scounteren_next;
                12'h140: sscratch <= sscratch_next;
                12'h141: sepc     <= {sepc_next[63:1], 1'b0};
                12'h142: scause   <= scause_next;
                12'h143: stval    <= stval_next;
                12'h144: mip_reg  <= (mip_reg & ~MIP_S_MASK) | (csr_next(sip_rd, wd, csr_op) & MIP_S_MASK);
                12'h180: satp     <= satp_next;
                12'h3A0: if (!pmpcfg0[7]) pmpcfg0  <= pmpcfg0_next;
                12'h3B0: if (!pmpcfg0[7]) pmpaddr0 <= csr_next(pmpaddr0, wd, csr_op);
                default: ;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ares_fault_seen      <= 1'b0;
            ares_last_fault_code <= 4'h0;
            ares_fault_count     <= 64'h0;
            ares_fault_info_reg  <= 64'h0;
            ares_control         <= 64'h1;
        end
        else begin
            if (csr_en) begin
                case (csr_addr)
                    12'h7C1: ares_fault_count <= csr_next(ares_fault_count, wd, csr_op);
                    12'h7C2: ares_fault_info_reg <= csr_next(ares_fault_info_reg, wd, csr_op);
                    12'h7C3: begin
                        ares_control <= {63'h0, ares_control_next_enable};
                        if (ares_control_next_clear) begin
                            ares_fault_seen      <= 1'b0;
                            ares_last_fault_code <= 4'h0;
                            ares_fault_count     <= 64'h0;
                            ares_fault_info_reg  <= 64'h0;
                        end
                    end
                    default: ;
                endcase
            end

            if (ares_fault_event && ares_control[0]) begin
                ares_fault_seen      <= 1'b1;
                ares_last_fault_code <= ares_fault_code;
                ares_fault_count     <= ares_fault_count + 64'd1;
                ares_fault_info_reg  <= ares_fault_info;
            end
        end
    end

    // =========================================================================
    // Outputs
    // =========================================================================
    assign tvec_base     = trap_vector;
    assign mret_pc       = mepc;
    assign sret_pc       = sepc;
    assign trap_redirect = trap_en || interrupt_taken;
    assign current_priv  = priv_mode;
    assign mstatus_tsr   = mstatus_tsr_reg;
    assign mstatus_tvm   = mstatus_tvm_reg;

`ifdef FORMAL
    reg f_past_valid;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;

        if (f_past_valid && rst_n) begin
            assume(!(trap_en && csr_en));
            assume(!(trap_en && mret_en));
            assume(!(trap_en && sret_en));
            assume(!(csr_en && mret_en));
            assume(!(csr_en && sret_en));
            assume(!(mret_en && sret_en));
            if (csr_en)
                assume(csr_op == 3'h1 || csr_op == 3'h2 || csr_op == 3'h3 ||
                       csr_op == 3'h5 || csr_op == 3'h6 || csr_op == 3'h7);
            if (mret_en)
                assume(priv_mode == PRV_M);
            if (sret_en)
                assume(priv_mode == PRV_S && !mstatus_tsr_reg);
        end

        assert(trap_redirect == (trap_en || interrupt_taken));
        assert(mret_pc == mepc);
        assert(sret_pc == sepc);
        assert(tvec_base == trap_vector);
        assert(current_priv == priv_mode);
        assert(mstatus_tsr == mstatus_tsr_reg);
        assert(mstatus_tvm == mstatus_tvm_reg);
        assert(mstatus_rd[1] == mstatus_sie);
        assert(mstatus_rd[3] == mstatus_mie);
        assert(mstatus_rd[5] == mstatus_spie);
        assert(mstatus_rd[7] == mstatus_mpie);
        assert(mstatus_rd[8] == mstatus_spp);
        assert(mstatus_rd[12:11] == mstatus_mpp);
        assert(mstatus_rd[17] == mstatus_mprv);
        assert(mstatus_rd[18] == mstatus_sum);
        assert(mstatus_rd[19] == mstatus_mxr);
        assert(mstatus_rd[20] == mstatus_tvm_reg);
        assert((mip_rd & MIP_M_MASK) == (mip_hw & MIP_M_MASK));
        assert(ares_status[0] == ares_fault_seen);
        assert(ares_status[7:4] == ares_last_fault_code);
        assert(ares_status[3:1] == 3'h0);
        assert(ares_control[63:1] == 63'h0);
        assert((mepc & 64'h1) == 64'h0);
        assert((sepc & 64'h1) == 64'h0);
        assert((mtvec & 64'h1) == 64'h0);
        assert((stvec & 64'h1) == 64'h0);
        assert(machine_interrupts_enabled == ((priv_mode != PRV_M) || mstatus_mie));
        assert(supervisor_interrupts_enabled == ((priv_mode == PRV_U) ||
                                                ((priv_mode == PRV_S) && mstatus_sie)));
        assert(!trap_en || !interrupt_taken);
        assert(!mret_en || !interrupt_taken);
        assert(!sret_en || !interrupt_taken);
        if (priv_mode == PRV_M && !mstatus_mie)
            assert(pending_interrupts == 64'h0);
        if (priv_mode == PRV_S) begin
            assert((pending_interrupts & pending_machine_targets) == pending_machine_targets);
            if (!mstatus_sie)
                assert((pending_interrupts & pending_supervisor_targets) == 64'h0);
        end
        if (priv_mode == PRV_U)
            assert(pending_interrupts == (pending_machine_targets | pending_supervisor_targets));

        if (!rst_n) begin
            assert(mstatus_rd == 64'h0000_0002_0000_1880);
            assert(mepc == 64'h0);
            assert(sepc == 64'h0);
            assert(mcause == 64'h0);
            assert(scause == 64'h0);
            assert(mtval == 64'h0);
            assert(stval == 64'h0);
            assert(mscratch == 64'h0);
            assert(sscratch == 64'h0);
            assert(ares_control == 64'h1);
            assert(ares_fault_count == 64'h0);
            assert(ares_fault_info_reg == 64'h0);
            assert(mstatus_tvm_reg == 1'b0);
            assert(mstatus_tsr_reg == 1'b0);
        end

    end
`endif

endmodule
