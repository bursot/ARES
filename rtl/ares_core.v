// ARES Core — Top-level pipeline
// Connects IF, ID, EX, MEM, WB stages with shared memory interfaces.

`timescale 1ns/1ps

module ares_core (
    input  wire        clk,
    input  wire        rst_n,

    // Instruction memory interface
    output wire [63:0] imem_addr,
    input  wire [31:0] imem_data,
    input  wire        imem_page_fault,
    input  wire [63:0] imem_page_fault_cause,
    input  wire [63:0] imem_page_fault_tval,

    // Data memory interface
    output wire [63:0] dmem_addr,
    output wire [63:0] dmem_wdata,
    output wire        dmem_we,
    output wire [2:0]  dmem_funct3,
    input  wire [63:0] dmem_rdata,
    input  wire        dmem_page_fault,
    input  wire [63:0] dmem_page_fault_cause,
    input  wire [63:0] dmem_page_fault_tval,

    // ARES external fault telemetry
    input  wire        ares_fault_event,
    input  wire [3:0]  ares_fault_code,
    input  wire [63:0] ares_fault_info,
    input  wire        rf_parity_fault_inject_en,
    input  wire [4:0]  rf_parity_fault_idx,

    // Machine interrupt inputs
    input  wire        irq_msip,
    input  wire        irq_mtip,
    input  wire        irq_meip
);

    // ----------------------------------------------------------------
    // Inter-stage wires
    // ----------------------------------------------------------------

    // IF -> ID
    wire [63:0] if_id_pc;
    wire [31:0] if_id_instr;

    // ID -> EX
    wire [63:0] id_ex_pc;
    wire [63:0] id_ex_rs1_data;
    wire [63:0] id_ex_rs2_data;
    wire [63:0] id_ex_imm;
    wire [4:0]  id_ex_rs1;
    wire [4:0]  id_ex_rs2;
    wire [4:0]  id_ex_rd;
    wire [6:0]  id_ex_opcode;
    wire [2:0]  id_ex_funct3;
    wire [6:0]  id_ex_funct7;
    wire        id_ex_reg_write;
    wire        id_ex_mem_read;
    wire        id_ex_mem_write;
    wire        id_ex_mem_to_reg;
    wire        id_ex_branch;
    wire        id_ex_jump;

    // EX -> MEM
    wire [63:0] ex_mem_alu_result;
    wire [63:0] ex_mem_pc;
    wire [63:0] ex_mem_rs2_data;
    wire [4:0]  ex_mem_rd;
    wire        ex_mem_reg_write;
    wire        ex_mem_mem_read;
    wire        ex_mem_mem_write;
    wire        ex_mem_mem_to_reg;
    wire [2:0]  ex_mem_funct3;
    wire        ex_mem_atomic_en;
    wire        ex_mem_atomic_is_lr;
    wire        ex_mem_atomic_is_sc;
    wire [4:0]  ex_mem_atomic_funct5;

    // MEM -> WB
    wire [63:0] mem_wb_data;
    wire [63:0] mem_wb_alu_result;
    wire [4:0]  mem_wb_rd;
    wire        mem_wb_reg_write;
    wire        mem_wb_mem_to_reg;

    // WB -> ID (register file write)
    wire [63:0] wb_data;
    wire        wb_reg_write;
    wire [4:0]  wb_rd;

    // Control signals
    wire        redirect_en;
    wire [63:0] redirect_pc;
    wire        flush;
    wire        stall;
    wire        ex_stall_unused;

    wire [4:0] if_id_rs1 = if_id_instr[19:15];
    wire [4:0] if_id_rs2 = if_id_instr[24:20];
    assign stall = id_ex_mem_read && (id_ex_rd != 5'h0) &&
                   ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));

    // CSR unit wires
    wire        csr_en;
    wire [11:0] csr_addr;
    wire [2:0]  csr_op;
    wire [63:0] csr_wdata;
    wire [4:0]  csr_uimm;
    wire [63:0] csr_rdata;
    wire        mret_en;
    wire        sret_en;
    /* verilator lint_off UNUSEDSIGNAL */
    wire        ecall_en;
    /* verilator lint_on UNUSEDSIGNAL */
    wire        trap_en;
    wire [63:0] trap_pc;
    wire [63:0] trap_cause;
    wire [63:0] trap_tval;
    wire        if_trap_en = imem_page_fault;
    wire [63:0] if_trap_pc = imem_addr;
    wire [63:0] if_trap_cause = imem_page_fault_cause;
    wire [63:0] if_trap_tval = imem_page_fault_tval;
    wire        mem_trap_en;
    wire [63:0] mem_trap_pc;
    wire [63:0] mem_trap_cause;
    wire [63:0] mem_trap_tval;
    wire        trap_en_combined = mem_trap_en || if_trap_en || trap_en;
    wire [63:0] trap_pc_combined = mem_trap_en ? mem_trap_pc :
                                   if_trap_en  ? if_trap_pc  : trap_pc;
    wire [63:0] trap_cause_combined = mem_trap_en ? mem_trap_cause :
                                      if_trap_en  ? if_trap_cause  : trap_cause;
    wire [63:0] trap_tval_combined = mem_trap_en ? mem_trap_tval :
                                     if_trap_en  ? if_trap_tval  : trap_tval;
    wire [63:0] mret_pc;
    wire [63:0] sret_pc;
    wire [63:0] tvec_base;
    wire        trap_redirect;
    wire [1:0]  current_priv;
    wire        mstatus_tsr;
    wire        mstatus_tvm;
    wire        ares_rf_fault_event;
    wire [63:0] ares_rf_fault_info;
    wire        ares_fault_event_combined = ares_fault_event || ares_rf_fault_event;
    wire [3:0]  ares_fault_code_combined = ares_fault_event ? ares_fault_code :
                                           ares_rf_fault_event ? 4'd3 : 4'd0;
    wire [63:0] ares_fault_context = (ares_fault_code_combined == 4'd1) ? imem_addr :
                                     (ares_fault_code_combined == 4'd2) ? ex_mem_alu_result :
                                     if_id_pc;
    wire [63:0] ares_fault_info_combined = ares_fault_event ? ares_fault_info :
                                           ares_rf_fault_event ? ares_rf_fault_info : 64'h0;
    wire [63:0] interrupt_pc = (if_id_pc != 64'h0) ? if_id_pc : imem_addr;

    // ----------------------------------------------------------------
    // Stage instantiation
    // ----------------------------------------------------------------

    if_stage u_if (
        .clk         (clk),
        .rst_n       (rst_n),
        .stall       (stall),
        .flush       (flush || mret_en || sret_en || trap_redirect),
        .redirect_en (redirect_en || mret_en || sret_en || trap_redirect),
        .redirect_pc (trap_redirect ? tvec_base :
                      mret_en      ? mret_pc   :
                      sret_en      ? sret_pc   : redirect_pc),
        .imem_addr   (imem_addr),
        .imem_data   (imem_data),
        .if_id_pc    (if_id_pc),
        .if_id_instr (if_id_instr)
    );

    id_stage u_id (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall           (stall),
        .flush           (flush || mret_en || sret_en || trap_redirect),
        .if_id_pc        (if_id_pc),
        .if_id_instr     (if_id_instr),
        .wb_reg_write    (wb_reg_write),
        .wb_rd           (wb_rd),
        .wb_data         (wb_data),
        .rf_parity_fault_inject_en(rf_parity_fault_inject_en),
        .rf_parity_fault_idx(rf_parity_fault_idx),
        .ares_rf_fault_event(ares_rf_fault_event),
        .ares_rf_fault_info (ares_rf_fault_info),
        .id_ex_pc        (id_ex_pc),
        .id_ex_rs1_data  (id_ex_rs1_data),
        .id_ex_rs2_data  (id_ex_rs2_data),
        .id_ex_imm       (id_ex_imm),
        .id_ex_rs1       (id_ex_rs1),
        .id_ex_rs2       (id_ex_rs2),
        .id_ex_rd        (id_ex_rd),
        .id_ex_opcode    (id_ex_opcode),
        .id_ex_funct3    (id_ex_funct3),
        .id_ex_funct7    (id_ex_funct7),
        .id_ex_reg_write  (id_ex_reg_write),
        .id_ex_mem_read   (id_ex_mem_read),
        .id_ex_mem_write  (id_ex_mem_write),
        .id_ex_mem_to_reg (id_ex_mem_to_reg),
        .id_ex_branch     (id_ex_branch),
        .id_ex_jump       (id_ex_jump)
    );

    ex_stage u_ex (
        .clk                (clk),
        .rst_n              (rst_n),
        .id_ex_pc           (id_ex_pc),
        .id_ex_rs1_data     (id_ex_rs1_data),
        .id_ex_rs2_data     (id_ex_rs2_data),
        .id_ex_imm          (id_ex_imm),
        .id_ex_rs1          (id_ex_rs1),
        .id_ex_rs2          (id_ex_rs2),
        .id_ex_rd           (id_ex_rd),
        .id_ex_opcode       (id_ex_opcode),
        .id_ex_funct3       (id_ex_funct3),
        .id_ex_funct7       (id_ex_funct7),
        .id_ex_reg_write    (id_ex_reg_write),
        .id_ex_mem_read     (id_ex_mem_read),
        .id_ex_mem_write    (id_ex_mem_write),
        .id_ex_mem_to_reg   (id_ex_mem_to_reg),
        .id_ex_branch       (id_ex_branch),
        .id_ex_jump         (id_ex_jump),
        .ex_mem_reg_write   (ex_mem_reg_write),
        .ex_mem_rd          (ex_mem_rd),
        .ex_mem_alu_result  (ex_mem_alu_result),
        .mem_wb_reg_write   (mem_wb_reg_write),
        .mem_wb_rd          (mem_wb_rd),
        .mem_wb_data        (wb_data),  // use WB mux output, not raw load_data
        .redirect_en        (redirect_en),
        .redirect_pc        (redirect_pc),
        .flush              (flush),
        .stall              (ex_stall_unused),
        .pipeline_kill      (mem_trap_en),
        .csr_en             (csr_en),
        .csr_addr           (csr_addr),
        .csr_op             (csr_op),
        .csr_wdata          (csr_wdata),
        .csr_uimm           (csr_uimm),
        .csr_rdata          (csr_rdata),
        .current_priv       (current_priv),
        .mstatus_tsr        (mstatus_tsr),
        .mstatus_tvm        (mstatus_tvm),
        .mret_en            (mret_en),
        .sret_en            (sret_en),
        .ecall_en           (ecall_en),
        .trap_en            (trap_en),
        .trap_pc            (trap_pc),
        .trap_cause         (trap_cause),
        .trap_tval          (trap_tval),
        .ex_mem_alu_result_r (ex_mem_alu_result),
        .ex_mem_pc_r        (ex_mem_pc),
        .ex_mem_rs2_data    (ex_mem_rs2_data),
        .ex_mem_rd_r        (ex_mem_rd),
        .ex_mem_reg_write_r (ex_mem_reg_write),
        .ex_mem_mem_read    (ex_mem_mem_read),
        .ex_mem_mem_write   (ex_mem_mem_write),
        .ex_mem_mem_to_reg  (ex_mem_mem_to_reg),
        .ex_mem_funct3_r    (ex_mem_funct3),
        .ex_mem_atomic_en   (ex_mem_atomic_en),
        .ex_mem_atomic_is_lr(ex_mem_atomic_is_lr),
        .ex_mem_atomic_is_sc(ex_mem_atomic_is_sc),
        .ex_mem_atomic_funct5(ex_mem_atomic_funct5)
    );

    mem_stage u_mem (
        .clk                (clk),
        .rst_n              (rst_n),
        .ex_mem_pc          (ex_mem_pc),
        .ex_mem_alu_result  (ex_mem_alu_result),
        .ex_mem_rs2_data    (ex_mem_rs2_data),
        .ex_mem_rd          (ex_mem_rd),
        .ex_mem_reg_write   (ex_mem_reg_write),
        .ex_mem_mem_read    (ex_mem_mem_read),
        .ex_mem_mem_write   (ex_mem_mem_write),
        .ex_mem_mem_to_reg  (ex_mem_mem_to_reg),
        .ex_mem_funct3      (ex_mem_funct3),
        .ex_mem_atomic_en   (ex_mem_atomic_en),
        .ex_mem_atomic_is_lr(ex_mem_atomic_is_lr),
        .ex_mem_atomic_is_sc(ex_mem_atomic_is_sc),
        .ex_mem_atomic_funct5(ex_mem_atomic_funct5),
        .dmem_addr          (dmem_addr),
        .dmem_wdata         (dmem_wdata),
        .dmem_we            (dmem_we),
        .dmem_funct3        (dmem_funct3),
        .dmem_rdata         (dmem_rdata),
        .dmem_page_fault    (dmem_page_fault),
        .dmem_page_fault_cause(dmem_page_fault_cause),
        .dmem_page_fault_tval(dmem_page_fault_tval),
        .mem_trap_en        (mem_trap_en),
        .mem_trap_pc        (mem_trap_pc),
        .mem_trap_cause     (mem_trap_cause),
        .mem_trap_tval      (mem_trap_tval),
        .mem_wb_data        (mem_wb_data),
        .mem_wb_rd          (mem_wb_rd),
        .mem_wb_reg_write   (mem_wb_reg_write),
        .mem_wb_mem_to_reg  (mem_wb_mem_to_reg),
        .mem_wb_alu_result  (mem_wb_alu_result)
    );

    wb_stage u_wb (
        .mem_wb_alu_result  (mem_wb_alu_result),
        .mem_wb_data        (mem_wb_data),
        .mem_wb_mem_to_reg  (mem_wb_mem_to_reg),
        .mem_wb_reg_write   (mem_wb_reg_write),
        .mem_wb_rd          (mem_wb_rd),
        .wb_data            (wb_data),
        .wb_reg_write       (wb_reg_write),
        .wb_rd              (wb_rd)
    );

    csr_unit u_csr (
        .clk           (clk),
        .rst_n         (rst_n),
        .csr_en        (csr_en),
        .csr_addr      (csr_addr),
        .csr_op        (csr_op),
        .csr_wdata     (csr_wdata),
        .csr_uimm      (csr_uimm),
        .csr_rdata     (csr_rdata),
        .trap_en       (trap_en_combined),
        .trap_pc       (trap_pc_combined),
        .trap_cause    (trap_cause_combined),
        .trap_tval     (trap_tval_combined),
        .irq_msip      (irq_msip),
        .irq_mtip      (irq_mtip),
        .irq_meip      (irq_meip),
        .interrupt_pc  (interrupt_pc),
        .mret_en       (mret_en),
        .mret_pc       (mret_pc),
        .sret_en       (sret_en),
        .sret_pc       (sret_pc),
        .ares_fault_event(ares_fault_event_combined),
        .ares_fault_code (ares_fault_code_combined),
        .ares_fault_info (ares_fault_info_combined != 64'h0 ? ares_fault_info_combined : ares_fault_context),
        .tvec_base     (tvec_base),
        .trap_redirect (trap_redirect),
        .current_priv  (current_priv),
        .mstatus_tsr   (mstatus_tsr),
        .mstatus_tvm   (mstatus_tvm)
    );

endmodule
