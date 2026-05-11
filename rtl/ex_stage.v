// ARES Core — EX Stage (Execute)
// Contains the ALU, forwarding unit, branch resolution,
// and produces the redirect signal for the IF stage.

`timescale 1ns/1ps

module ex_stage (
    input  wire        clk,
    input  wire        rst_n,

    // From ID/EX pipeline register
    input  wire [63:0] id_ex_pc,
    input  wire [63:0] id_ex_rs1_data,
    input  wire [63:0] id_ex_rs2_data,
    input  wire [63:0] id_ex_imm,
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,
    input  wire [4:0]  id_ex_rd,
    input  wire [6:0]  id_ex_opcode,
    input  wire [2:0]  id_ex_funct3,
    input  wire [6:0]  id_ex_funct7,
    input  wire        id_ex_reg_write,
    input  wire        id_ex_mem_read,
    input  wire        id_ex_mem_write,
    input  wire        id_ex_mem_to_reg,
    input  wire        id_ex_branch,
    input  wire        id_ex_jump,

    // Forwarding inputs from EX/MEM and MEM/WB
    input  wire        ex_mem_reg_write,
    input  wire [4:0]  ex_mem_rd,
    input  wire [63:0] ex_mem_alu_result,
    input  wire        mem_wb_reg_write,
    input  wire [4:0]  mem_wb_rd,
    input  wire [63:0] mem_wb_data,

    // Branch/jump redirect to IF
    output wire        redirect_en,
    output wire [63:0] redirect_pc,
    output wire        flush,

    // Stall request (load-use hazard)
    output wire        stall,

    // Kill current EX-stage result when an older trap/interrupt redirects
    input  wire        pipeline_kill,

    // CSR interface (to csr_unit)
    output wire        csr_en,
    output wire [11:0] csr_addr,
    output wire [2:0]  csr_op,
    output wire [63:0] csr_wdata,
    output wire [4:0]  csr_uimm,
    input  wire [63:0] csr_rdata,
    input  wire [1:0]  current_priv,
    input  wire        mstatus_tsr,
    input  wire        mstatus_tvm,
    output wire        mret_en,
    output wire        sret_en,
    output wire        ecall_en,
    output wire        trap_en,
    output wire [63:0] trap_pc,
    output wire [63:0] trap_cause,
    output wire [63:0] trap_tval,

    // Outputs to EX/MEM pipeline register
    output reg  [63:0] ex_mem_alu_result_r,
    output reg  [63:0] ex_mem_pc_r,
    output reg  [63:0] ex_mem_rs2_data,
    output reg  [4:0]  ex_mem_rd_r,
    output reg         ex_mem_reg_write_r,
    output reg         ex_mem_mem_read,
    output reg         ex_mem_mem_write,
    output reg         ex_mem_mem_to_reg,
    output reg  [2:0]  ex_mem_funct3_r,
    output reg         ex_mem_atomic_en,
    output reg         ex_mem_atomic_is_lr,
    output reg         ex_mem_atomic_is_sc,
    output reg  [4:0]  ex_mem_atomic_funct5
);

    // ----------------------------------------------------------------
    // Forwarding Unit
    // Detects when a later instruction needs a result that hasn't
    // been written back yet and selects the forwarded value.
    // ----------------------------------------------------------------
    wire fwd_ex_rs1 = ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs1);
    wire fwd_ex_rs2 = ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs2);
    wire fwd_wb_rs1 = mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs1) && !fwd_ex_rs1;
    wire fwd_wb_rs2 = mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs2) && !fwd_ex_rs2;

    wire [63:0] alu_a = fwd_ex_rs1 ? ex_mem_alu_result :
                        fwd_wb_rs1 ? mem_wb_data        :
                                     id_ex_rs1_data;

    wire [63:0] alu_b_reg = fwd_ex_rs2 ? ex_mem_alu_result :
                            fwd_wb_rs2 ? mem_wb_data        :
                                         id_ex_rs2_data;

    // ALU second operand: register or immediate
    wire use_imm = (id_ex_opcode != 7'h33) && (id_ex_opcode != 7'h3B);
    wire [63:0] alu_b = use_imm ? id_ex_imm : alu_b_reg;

    // ----------------------------------------------------------------
    // Load-Use Hazard Detection
    // If EX/MEM stage has a load (mem_read) and current ID/EX instruction
    // uses that register, stall one cycle.
    // ----------------------------------------------------------------
    assign stall = ex_mem_mem_read &&
                   ((ex_mem_rd == id_ex_rs1) || (ex_mem_rd == id_ex_rs2));

    // ----------------------------------------------------------------
    // Instruction legality
    // ----------------------------------------------------------------
    wire is_fence = (id_ex_opcode == 7'h0F);
    wire is_system = (id_ex_opcode == 7'h73);
    wire is_system_priv = is_system && (id_ex_funct3 == 3'h0);
    wire is_atomic = (id_ex_opcode == 7'h2F);
    wire [4:0] atomic_funct5 = id_ex_funct7[6:2];
    wire atomic_is_lr = is_atomic && (atomic_funct5 == 5'b00010) && (id_ex_rs2 == 5'h0);
    wire atomic_is_sc = is_atomic && (atomic_funct5 == 5'b00011);
    wire valid_slli_imm = (id_ex_funct7[6:1] == 6'b000000);
    wire valid_srli_srai_imm =
        (id_ex_funct7[6:1] == 6'b000000) || (id_ex_funct7[6:1] == 6'b010000);
    wire valid_slliw_imm = (id_ex_funct7 == 7'h00);
    wire valid_srliw_sraiw_imm = (id_ex_funct7 == 7'h00) || (id_ex_funct7 == 7'h20);

    wire valid_r_op =
        ((id_ex_funct3 == 3'h0) && ((id_ex_funct7 == 7'h00) || (id_ex_funct7 == 7'h20))) ||
        ((id_ex_funct3 == 3'h1) &&  (id_ex_funct7 == 7'h00)) ||
        ((id_ex_funct3 == 3'h2) &&  (id_ex_funct7 == 7'h00)) ||
        ((id_ex_funct3 == 3'h3) &&  (id_ex_funct7 == 7'h00)) ||
        ((id_ex_funct3 == 3'h4) &&  (id_ex_funct7 == 7'h00)) ||
        ((id_ex_funct3 == 3'h5) && ((id_ex_funct7 == 7'h00) || (id_ex_funct7 == 7'h20))) ||
        ((id_ex_funct3 == 3'h6) &&  (id_ex_funct7 == 7'h00)) ||
        ((id_ex_funct3 == 3'h7) &&  (id_ex_funct7 == 7'h00)) ||
        (id_ex_funct7 == 7'h01);

    wire valid_i_op =
        (id_ex_funct3 == 3'h0) ||
        (id_ex_funct3 == 3'h2) ||
        (id_ex_funct3 == 3'h3) ||
        (id_ex_funct3 == 3'h4) ||
        (id_ex_funct3 == 3'h6) ||
        (id_ex_funct3 == 3'h7) ||
        ((id_ex_funct3 == 3'h1) && valid_slli_imm) ||
        ((id_ex_funct3 == 3'h5) && valid_srli_srai_imm);

    wire valid_rv64_word_op =
        ((id_ex_funct3 == 3'h0) && ((id_ex_funct7 == 7'h00) || (id_ex_funct7 == 7'h20))) ||
        ((id_ex_funct3 == 3'h1) &&  (id_ex_funct7 == 7'h00)) ||
        ((id_ex_funct3 == 3'h5) && ((id_ex_funct7 == 7'h00) || (id_ex_funct7 == 7'h20))) ||
        ((id_ex_funct7 == 7'h01) &&
         ((id_ex_funct3 == 3'h0) || (id_ex_funct3 == 3'h4) || (id_ex_funct3 == 3'h5) ||
          (id_ex_funct3 == 3'h6) || (id_ex_funct3 == 3'h7)));

    wire valid_rv64_word_imm_op =
        (id_ex_funct3 == 3'h0) ||
        ((id_ex_funct3 == 3'h1) && valid_slliw_imm) ||
        ((id_ex_funct3 == 3'h5) && valid_srliw_sraiw_imm);

    wire valid_load  = (id_ex_funct3 != 3'h7);
    wire valid_store = (id_ex_funct3 == 3'h0) || (id_ex_funct3 == 3'h1) ||
                       (id_ex_funct3 == 3'h2) || (id_ex_funct3 == 3'h3);
    wire valid_branch = (id_ex_funct3 == 3'h0) || (id_ex_funct3 == 3'h1) ||
                        (id_ex_funct3 == 3'h4) || (id_ex_funct3 == 3'h5) ||
                        (id_ex_funct3 == 3'h6) || (id_ex_funct3 == 3'h7);
    wire valid_jalr = (id_ex_funct3 == 3'h0);
    wire valid_csr = is_system && (
        (id_ex_funct3 == 3'h1) || (id_ex_funct3 == 3'h2) || (id_ex_funct3 == 3'h3) ||
        (id_ex_funct3 == 3'h5) || (id_ex_funct3 == 3'h6) || (id_ex_funct3 == 3'h7)
    );
    wire csr_write = valid_csr &&
                     ((id_ex_funct3 == 3'h1) || (id_ex_funct3 == 3'h5) ||
                      (((id_ex_funct3 == 3'h2) || (id_ex_funct3 == 3'h3)) && (id_ex_rs1 != 5'h0)) ||
                      (((id_ex_funct3 == 3'h6) || (id_ex_funct3 == 3'h7)) && (id_ex_rs1 != 5'h0)));
    wire [1:0] csr_priv = id_ex_imm[9:8];
    wire csr_is_ro = (id_ex_imm[11:10] == 2'b11);
    wire csr_priv_fault = valid_csr && (current_priv < csr_priv);
    wire csr_ro_fault = csr_write && csr_is_ro;
    wire valid_atomic_funct5 =
        (atomic_funct5 == 5'b00001) || // amoswap
        (atomic_funct5 == 5'b00000) || // amoadd
        (atomic_funct5 == 5'b00100) || // amoxor
        (atomic_funct5 == 5'b01100) || // amoand
        (atomic_funct5 == 5'b01000) || // amoor
        (atomic_funct5 == 5'b10000) || // amomin
        (atomic_funct5 == 5'b10100) || // amomax
        (atomic_funct5 == 5'b11000) || // amominu
        (atomic_funct5 == 5'b11100) || // amomaxu
        atomic_is_lr || atomic_is_sc;
    wire valid_atomic = is_atomic &&
                        ((id_ex_funct3 == 3'h2) || (id_ex_funct3 == 3'h3)) &&
                        valid_atomic_funct5;

    wire valid_opcode =
        ((id_ex_opcode == 7'h33) && valid_r_op)         ||
        ((id_ex_opcode == 7'h13) && valid_i_op)         ||
        ((id_ex_opcode == 7'h3B) && valid_rv64_word_op) ||
        ((id_ex_opcode == 7'h1B) && valid_rv64_word_imm_op) ||
        ((id_ex_opcode == 7'h03) && valid_load)         ||
        ((id_ex_opcode == 7'h23) && valid_store)        ||
        ((id_ex_opcode == 7'h63) && valid_branch)       ||
        ((id_ex_opcode == 7'h67) && valid_jalr)         ||
        (id_ex_opcode == 7'h37)                         ||
        (id_ex_opcode == 7'h17)                         ||
        (id_ex_opcode == 7'h6F)                         ||
        valid_atomic                                     ||
        is_fence                                        ||
        valid_csr                                       ||
        is_system_priv;

    // ----------------------------------------------------------------
    // ALU
    // ----------------------------------------------------------------
    reg [63:0] alu_result;
    reg [31:0] word_result;
    wire is_word = (id_ex_opcode == 7'h3B) || (id_ex_opcode == 7'h1B);
    wire is_muldiv = ((id_ex_opcode == 7'h33) || (id_ex_opcode == 7'h3B)) && (id_ex_funct7 == 7'h01);
    wire signed [63:0] signed_alu_a = alu_a;
    wire signed [63:0] signed_alu_b = alu_b;
    wire signed [31:0] signed_word_a = alu_a[31:0];
    wire signed [31:0] signed_word_b = alu_b[31:0];

    function automatic [63:0] mulh_signed_signed;
        input signed [63:0] a;
        input signed [63:0] b;
        /* verilator lint_off UNUSEDSIGNAL */
        reg signed [127:0] product;
        /* verilator lint_on UNUSEDSIGNAL */
        begin
            product = a * b;
            mulh_signed_signed = product[127:64];
        end
    endfunction

    function automatic [63:0] mulh_signed_unsigned;
        input signed [63:0] a;
        input [63:0] b;
        /* verilator lint_off UNUSEDSIGNAL */
        reg signed [127:0] product;
        /* verilator lint_on UNUSEDSIGNAL */
        begin
            product = a * $signed({1'b0, b});
            mulh_signed_unsigned = product[127:64];
        end
    endfunction

    function automatic [63:0] mulh_unsigned_unsigned;
        input [63:0] a;
        input [63:0] b;
        /* verilator lint_off UNUSEDSIGNAL */
        reg [127:0] product;
        /* verilator lint_on UNUSEDSIGNAL */
        begin
            product = a * b;
            mulh_unsigned_unsigned = product[127:64];
        end
    endfunction

    always @(*) begin
        word_result = 32'h0;
        case (id_ex_opcode)
            // R-type and I-type ALU
            7'h33, 7'h13, 7'h3B, 7'h1B: begin
                if (is_muldiv) begin
                    if (id_ex_opcode == 7'h3B) begin
                        case (id_ex_funct3)
                            3'h0: word_result = signed_word_a * signed_word_b; // MULW
                            3'h4: begin
                                if (alu_b[31:0] == 32'h0)
                                    word_result = 32'hffff_ffff;
                                else if ((alu_a[31:0] == 32'h8000_0000) && (alu_b[31:0] == 32'hffff_ffff))
                                    word_result = 32'h8000_0000;
                                else
                                    word_result = signed_word_a / signed_word_b;
                            end
                            3'h5: begin
                                if (alu_b[31:0] == 32'h0)
                                    word_result = 32'hffff_ffff;
                                else
                                    word_result = alu_a[31:0] / alu_b[31:0];
                            end
                            3'h6: begin
                                if (alu_b[31:0] == 32'h0)
                                    word_result = alu_a[31:0];
                                else if ((alu_a[31:0] == 32'h8000_0000) && (alu_b[31:0] == 32'hffff_ffff))
                                    word_result = 32'h0;
                                else
                                    word_result = signed_word_a % signed_word_b;
                            end
                            3'h7: begin
                                if (alu_b[31:0] == 32'h0)
                                    word_result = alu_a[31:0];
                                else
                                    word_result = alu_a[31:0] % alu_b[31:0];
                            end
                            default: word_result = 32'h0;
                        endcase
                        alu_result = {{32{word_result[31]}}, word_result};
                    end else begin
                        case (id_ex_funct3)
                            3'h0: alu_result = signed_alu_a * signed_alu_b;           // MUL
                            3'h1: alu_result = mulh_signed_signed(signed_alu_a, signed_alu_b); // MULH
                            3'h2: alu_result = mulh_signed_unsigned(signed_alu_a, alu_b);      // MULHSU
                            3'h3: alu_result = mulh_unsigned_unsigned(alu_a, alu_b);            // MULHU
                            3'h4: begin
                                if (alu_b == 64'h0)
                                    alu_result = 64'hffff_ffff_ffff_ffff;
                                else if ((alu_a == 64'h8000_0000_0000_0000) && (alu_b == 64'hffff_ffff_ffff_ffff))
                                    alu_result = alu_a;
                                else
                                    alu_result = signed_alu_a / signed_alu_b;
                            end
                            3'h5: begin
                                if (alu_b == 64'h0)
                                    alu_result = 64'hffff_ffff_ffff_ffff;
                                else
                                    alu_result = alu_a / alu_b;
                            end
                            3'h6: begin
                                if (alu_b == 64'h0)
                                    alu_result = alu_a;
                                else if ((alu_a == 64'h8000_0000_0000_0000) && (alu_b == 64'hffff_ffff_ffff_ffff))
                                    alu_result = 64'h0;
                                else
                                    alu_result = signed_alu_a % signed_alu_b;
                            end
                            3'h7: begin
                                if (alu_b == 64'h0)
                                    alu_result = alu_a;
                                else
                                    alu_result = alu_a % alu_b;
                            end
                            default: alu_result = 64'h0;
                        endcase
                    end
                end else if (is_word) begin
                    case (id_ex_funct3)
                        3'h0: begin
                            if (id_ex_funct7[5] && (id_ex_opcode == 7'h3B))
                                word_result = alu_a[31:0] - alu_b[31:0];  // SUBW
                            else
                                word_result = alu_a[31:0] + alu_b[31:0];  // ADDW/ADDIW
                        end
                        3'h1: word_result = alu_a[31:0] << alu_b[4:0];     // SLLW/SLLIW
                        3'h5: begin
                            if (id_ex_funct7[5])
                                word_result = $signed(alu_a[31:0]) >>> alu_b[4:0]; // SRAW/SRAIW
                            else
                                word_result = alu_a[31:0] >> alu_b[4:0];            // SRLW/SRLIW
                        end
                        default: word_result = 32'h0;
                    endcase
                    alu_result = {{32{word_result[31]}}, word_result};
                end else begin
                    case (id_ex_funct3)
                        3'h0: begin
                            if (id_ex_opcode == 7'h33 && id_ex_funct7[5])
                                alu_result = alu_a - alu_b;  // SUB
                            else
                                alu_result = alu_a + alu_b;  // ADD/ADDI
                        end
                        3'h1: alu_result = alu_a << alu_b[5:0];                     // SLL
                        3'h2: alu_result = ($signed(alu_a) < $signed(alu_b)) ? 64'h1 : 64'h0; // SLT
                        3'h3: alu_result = (alu_a < alu_b) ? 64'h1 : 64'h0;                   // SLTU
                        3'h4: alu_result = alu_a ^ alu_b;                                      // XOR
                        3'h5: begin
                            if (id_ex_funct7[5])
                                alu_result = $signed(alu_a) >>> alu_b[5:0]; // SRA
                            else
                                alu_result = alu_a >> alu_b[5:0];           // SRL
                        end
                        3'h6: alu_result = alu_a | alu_b;                   // OR
                        3'h7: alu_result = alu_a & alu_b;                   // AND
                        default: alu_result = 64'h0;
                    endcase
                end
            end

            7'h03, 7'h23:  alu_result = alu_a + alu_b;               // Load/Store: address
            7'h2F:         alu_result = alu_a;                       // Atomics: address in rs1
            7'h37:         alu_result = id_ex_imm;                    // LUI
            7'h17:         alu_result = id_ex_pc + id_ex_imm;        // AUIPC
            7'h6F:         alu_result = id_ex_pc + 64'h4;            // JAL: rd = pc+4
            7'h67:         alu_result = id_ex_pc + 64'h4;            // JALR: rd = pc+4
            default:       alu_result = 64'h0;
        endcase
    end

    // ----------------------------------------------------------------
    // Branch resolution
    // ----------------------------------------------------------------
    reg branch_taken;
    always @(*) begin
        case (id_ex_funct3)
            3'h0: branch_taken = (alu_a == alu_b_reg);                       // BEQ
            3'h1: branch_taken = (alu_a != alu_b_reg);                       // BNE
            3'h4: branch_taken = ($signed(alu_a) < $signed(alu_b_reg));      // BLT
            3'h5: branch_taken = ($signed(alu_a) >= $signed(alu_b_reg));     // BGE
            3'h6: branch_taken = (alu_a < alu_b_reg);                        // BLTU
            3'h7: branch_taken = (alu_a >= alu_b_reg);                       // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    wire do_branch = id_ex_branch && branch_taken;
    wire do_jump   = id_ex_jump;

    // Branch target: PC + imm
    // JALR target: (rs1 + imm) & ~1
    wire [63:0] branch_target = id_ex_pc + id_ex_imm;
    wire [63:0] jalr_target   = (alu_a + id_ex_imm) & ~64'h1;
    wire [63:0] jump_target   = (id_ex_opcode == 7'h67) ? jalr_target : branch_target;

    assign redirect_en = do_branch || do_jump;
    assign redirect_pc = jump_target;
    assign flush       = redirect_en;

    // ----------------------------------------------------------------
    // CSR interface outputs (to csr_unit in ares_core)
    // ----------------------------------------------------------------
    assign csr_en    = valid_csr;
    assign csr_addr  = id_ex_imm[11:0];
    assign csr_op    = id_ex_funct3;
    assign csr_wdata = alu_a;
    assign csr_uimm  = id_ex_rs1;
    assign mret_en   = is_system_priv
                       && (id_ex_imm[11:0] == 12'h302);
    assign sret_en   = is_system_priv
                       && (id_ex_imm[11:0] == 12'h102);
    assign ecall_en  = is_system_priv
                       && (id_ex_imm[11:0] == 12'h0);  // ECALL
    wire ebreak_en = is_system_priv && (id_ex_imm[11:0] == 12'h001);
    wire wfi_en = is_system_priv && (id_ex_imm[11:0] == 12'h105);
    wire sfence_vma_en = is_system_priv && (id_ex_imm[11:0] == 12'h120);
    wire satp_access_fault = valid_csr && (id_ex_imm[11:0] == 12'h180) &&
                             (current_priv == 2'b01) && mstatus_tvm;
    wire sfence_vma_fault = sfence_vma_en && (current_priv == 2'b01) && mstatus_tvm;
    wire return_priv_fault = (mret_en && (current_priv != 2'b11)) ||
                             (sret_en && ((current_priv == 2'b00) ||
                                          ((current_priv == 2'b01) && mstatus_tsr)));
    wire misaligned_fetch = (do_branch || do_jump) && jump_target[1];
    wire illegal_instr = !valid_opcode ||
                         csr_priv_fault || csr_ro_fault || satp_access_fault ||
                         sfence_vma_fault || return_priv_fault ||
                         (is_system_priv && !ecall_en && !mret_en && !sret_en &&
                          !ebreak_en && !wfi_en && !sfence_vma_en);

    assign trap_en    = illegal_instr || ecall_en || ebreak_en || misaligned_fetch;
    assign trap_pc    = id_ex_pc;
    assign trap_cause = misaligned_fetch ? 64'd0 :
                        ebreak_en        ? 64'd3 :
                        illegal_instr    ? 64'd2 :
                        (current_priv == 2'b00) ? 64'd8 :
                        (current_priv == 2'b01) ? 64'd9 : 64'd11;
    assign trap_tval  = misaligned_fetch ? jump_target : 64'h0;

    // ----------------------------------------------------------------
    // EX/MEM pipeline register
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_alu_result_r <= 64'h0;
            ex_mem_pc_r         <= 64'h0;
            ex_mem_rs2_data     <= 64'h0;
            ex_mem_rd_r         <= 5'h0;
            ex_mem_reg_write_r  <= 1'b0;
            ex_mem_mem_read     <= 1'b0;
            ex_mem_mem_write    <= 1'b0;
            ex_mem_mem_to_reg   <= 1'b0;
            ex_mem_funct3_r     <= 3'h0;
            ex_mem_atomic_en    <= 1'b0;
            ex_mem_atomic_is_lr <= 1'b0;
            ex_mem_atomic_is_sc <= 1'b0;
            ex_mem_atomic_funct5 <= 5'h0;
        end else if (trap_en || pipeline_kill) begin
            ex_mem_alu_result_r <= 64'h0;
            ex_mem_pc_r         <= 64'h0;
            ex_mem_rs2_data     <= 64'h0;
            ex_mem_rd_r         <= 5'h0;
            ex_mem_reg_write_r  <= 1'b0;
            ex_mem_mem_read     <= 1'b0;
            ex_mem_mem_write    <= 1'b0;
            ex_mem_mem_to_reg   <= 1'b0;
            ex_mem_funct3_r     <= 3'h0;
            ex_mem_atomic_en    <= 1'b0;
            ex_mem_atomic_is_lr <= 1'b0;
            ex_mem_atomic_is_sc <= 1'b0;
            ex_mem_atomic_funct5 <= 5'h0;
        end else begin
            // CSR instructions write csr_rdata to rd, not alu_result
            ex_mem_alu_result_r <= csr_en ? csr_rdata : alu_result;
            ex_mem_pc_r         <= id_ex_pc;
            ex_mem_rs2_data     <= alu_b_reg;
            ex_mem_rd_r         <= id_ex_rd;
            ex_mem_reg_write_r  <= id_ex_reg_write;
            ex_mem_mem_read     <= id_ex_mem_read;
            ex_mem_mem_write    <= id_ex_mem_write;
            ex_mem_mem_to_reg   <= id_ex_mem_to_reg;
            ex_mem_funct3_r     <= id_ex_funct3;
            ex_mem_atomic_en    <= is_atomic;
            ex_mem_atomic_is_lr <= atomic_is_lr;
            ex_mem_atomic_is_sc <= atomic_is_sc;
            ex_mem_atomic_funct5 <= atomic_funct5;
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;

        assert(flush == redirect_en);

        if (f_past_valid && !$past(rst_n)) begin
            assert(ex_mem_pc_r == 64'h0);
            assert(ex_mem_rd_r == 5'h0);
            assert(ex_mem_reg_write_r == 1'b0);
            assert(ex_mem_mem_read == 1'b0);
            assert(ex_mem_mem_write == 1'b0);
            assert(ex_mem_mem_to_reg == 1'b0);
            assert(ex_mem_atomic_en == 1'b0);
            assert(ex_mem_atomic_is_lr == 1'b0);
            assert(ex_mem_atomic_is_sc == 1'b0);
        end

        if (f_past_valid && $past(rst_n) && ($past(trap_en) || $past(pipeline_kill))) begin
            assert(ex_mem_pc_r == 64'h0);
            assert(ex_mem_rd_r == 5'h0);
            assert(ex_mem_reg_write_r == 1'b0);
            assert(ex_mem_mem_read == 1'b0);
            assert(ex_mem_mem_write == 1'b0);
            assert(ex_mem_mem_to_reg == 1'b0);
            assert(ex_mem_atomic_en == 1'b0);
            assert(ex_mem_atomic_is_lr == 1'b0);
            assert(ex_mem_atomic_is_sc == 1'b0);
        end

        if (current_priv == 2'b01 && mstatus_tvm && sfence_vma_en) begin
            assert(illegal_instr);
            assert(trap_en);
            if (!misaligned_fetch && !ebreak_en)
                assert(trap_cause == 64'd2);
        end

        if (current_priv == 2'b01 && mstatus_tvm && valid_csr && (id_ex_imm[11:0] == 12'h180)) begin
            assert(illegal_instr);
            assert(trap_en);
            if (!misaligned_fetch && !ebreak_en)
                assert(trap_cause == 64'd2);
        end

        if (current_priv == 2'b01 && mstatus_tsr && sret_en) begin
            assert(illegal_instr);
            assert(trap_en);
            if (!misaligned_fetch && !ebreak_en)
                assert(trap_cause == 64'd2);
        end
    end
`endif

endmodule
