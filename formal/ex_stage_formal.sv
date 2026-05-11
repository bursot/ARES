`timescale 1ns/1ps

module ex_stage_formal;
    localparam [1:0] PRV_U = 2'b00;
    localparam [1:0] PRV_S = 2'b01;
    localparam [1:0] PRV_M = 2'b11;

    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;
    reg past_valid = 1'b0;

    (* anyseq *) reg [63:0] id_ex_pc;
    (* anyseq *) reg [63:0] id_ex_rs1_data;
    (* anyseq *) reg [63:0] id_ex_rs2_data;
    (* anyseq *) reg [63:0] id_ex_imm;
    (* anyseq *) reg [4:0]  id_ex_rs1;
    (* anyseq *) reg [4:0]  id_ex_rs2;
    (* anyseq *) reg [4:0]  id_ex_rd;
    (* anyseq *) reg [6:0]  id_ex_opcode;
    (* anyseq *) reg [2:0]  id_ex_funct3;
    (* anyseq *) reg [6:0]  id_ex_funct7;
    (* anyseq *) reg        id_ex_reg_write;
    (* anyseq *) reg        id_ex_mem_read;
    (* anyseq *) reg        id_ex_mem_write;
    (* anyseq *) reg        id_ex_mem_to_reg;
    (* anyseq *) reg        id_ex_branch;
    (* anyseq *) reg        id_ex_jump;
    (* anyseq *) reg        ex_mem_reg_write;
    (* anyseq *) reg [4:0]  ex_mem_rd;
    (* anyseq *) reg [63:0] ex_mem_alu_result;
    (* anyseq *) reg        mem_wb_reg_write;
    (* anyseq *) reg [4:0]  mem_wb_rd;
    (* anyseq *) reg [63:0] mem_wb_data;
    (* anyseq *) reg [63:0] csr_rdata;
    (* anyseq *) reg [1:0]  current_priv;
    (* anyseq *) reg        mstatus_tsr;
    (* anyseq *) reg        mstatus_tvm;
    (* anyseq *) reg        pipeline_kill;

    wire        redirect_en;
    wire [63:0] redirect_pc;
    wire        flush;
    wire        stall;
    wire        csr_en;
    wire [11:0] csr_addr;
    wire [2:0]  csr_op;
    wire [63:0] csr_wdata;
    wire [4:0]  csr_uimm;
    wire        mret_en;
    wire        sret_en;
    wire        ecall_en;
    wire        trap_en;
    wire [63:0] trap_pc;
    wire [63:0] trap_cause;
    wire [63:0] trap_tval;
    wire [63:0] ex_mem_alu_result_r;
    wire [63:0] ex_mem_pc_r;
    wire [63:0] ex_mem_rs2_data;
    wire [4:0]  ex_mem_rd_r;
    wire        ex_mem_reg_write_r;
    wire        ex_mem_mem_read;
    wire        ex_mem_mem_write;
    wire        ex_mem_mem_to_reg;
    wire [2:0]  ex_mem_funct3_r;
    wire        ex_mem_atomic_en;
    wire        ex_mem_atomic_is_lr;
    wire        ex_mem_atomic_is_sc;
    wire [4:0]  ex_mem_atomic_funct5;

    ex_stage dut (
        .clk(clk),
        .rst_n(rst_n),
        .id_ex_pc(id_ex_pc),
        .id_ex_rs1_data(id_ex_rs1_data),
        .id_ex_rs2_data(id_ex_rs2_data),
        .id_ex_imm(id_ex_imm),
        .id_ex_rs1(id_ex_rs1),
        .id_ex_rs2(id_ex_rs2),
        .id_ex_rd(id_ex_rd),
        .id_ex_opcode(id_ex_opcode),
        .id_ex_funct3(id_ex_funct3),
        .id_ex_funct7(id_ex_funct7),
        .id_ex_reg_write(id_ex_reg_write),
        .id_ex_mem_read(id_ex_mem_read),
        .id_ex_mem_write(id_ex_mem_write),
        .id_ex_mem_to_reg(id_ex_mem_to_reg),
        .id_ex_branch(id_ex_branch),
        .id_ex_jump(id_ex_jump),
        .ex_mem_reg_write(ex_mem_reg_write),
        .ex_mem_rd(ex_mem_rd),
        .ex_mem_alu_result(ex_mem_alu_result),
        .mem_wb_reg_write(mem_wb_reg_write),
        .mem_wb_rd(mem_wb_rd),
        .mem_wb_data(mem_wb_data),
        .redirect_en(redirect_en),
        .redirect_pc(redirect_pc),
        .flush(flush),
        .stall(stall),
        .pipeline_kill(pipeline_kill),
        .csr_en(csr_en),
        .csr_addr(csr_addr),
        .csr_op(csr_op),
        .csr_wdata(csr_wdata),
        .csr_uimm(csr_uimm),
        .csr_rdata(csr_rdata),
        .current_priv(current_priv),
        .mstatus_tsr(mstatus_tsr),
        .mstatus_tvm(mstatus_tvm),
        .mret_en(mret_en),
        .sret_en(sret_en),
        .ecall_en(ecall_en),
        .trap_en(trap_en),
        .trap_pc(trap_pc),
        .trap_cause(trap_cause),
        .trap_tval(trap_tval),
        .ex_mem_alu_result_r(ex_mem_alu_result_r),
        .ex_mem_pc_r(ex_mem_pc_r),
        .ex_mem_rs2_data(ex_mem_rs2_data),
        .ex_mem_rd_r(ex_mem_rd_r),
        .ex_mem_reg_write_r(ex_mem_reg_write_r),
        .ex_mem_mem_read(ex_mem_mem_read),
        .ex_mem_mem_write(ex_mem_mem_write),
        .ex_mem_mem_to_reg(ex_mem_mem_to_reg),
        .ex_mem_funct3_r(ex_mem_funct3_r),
        .ex_mem_atomic_en(ex_mem_atomic_en),
        .ex_mem_atomic_is_lr(ex_mem_atomic_is_lr),
        .ex_mem_atomic_is_sc(ex_mem_atomic_is_sc),
        .ex_mem_atomic_funct5(ex_mem_atomic_funct5)
    );

    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) begin
            assume(!rst_n);
        end else begin
            if ($past(rst_n))
                assume(rst_n);
        end

        assume(current_priv != 2'b10);
        assume(id_ex_pc[0] == 1'b0);

        if (!rst_n) begin
            assume(!id_ex_branch);
            assume(!id_ex_jump);
            assume(!id_ex_mem_read);
            assume(!id_ex_mem_write);
            assume(!id_ex_mem_to_reg);
            assume(!pipeline_kill);
        end

        assume(!(id_ex_branch && id_ex_jump));
        assume(!id_ex_mem_to_reg || id_ex_mem_read);
        assume(!id_ex_mem_read || !id_ex_mem_write);

        if (id_ex_branch)
            assume(id_ex_opcode == 7'h63);
        if (id_ex_jump)
            assume(id_ex_opcode == 7'h6F || id_ex_opcode == 7'h67);
        if (id_ex_mem_read)
            assume(id_ex_opcode == 7'h03);
        if (id_ex_mem_write)
            assume(id_ex_opcode == 7'h23);
        if (id_ex_opcode == 7'h67)
            assume(id_ex_funct3 == 3'h0);
        if (id_ex_opcode == 7'h73 && id_ex_funct3 == 3'h0) begin
            assume(id_ex_imm[11:0] == 12'h000 ||
                   id_ex_imm[11:0] == 12'h001 ||
                   id_ex_imm[11:0] == 12'h102 ||
                   id_ex_imm[11:0] == 12'h105 ||
                   id_ex_imm[11:0] == 12'h120 ||
                   id_ex_imm[11:0] == 12'h302);
            if (id_ex_imm[11:0] == 12'h302)
                assume(current_priv == PRV_M);
            if (id_ex_imm[11:0] == 12'h102)
                assume(current_priv == PRV_S || current_priv == PRV_U);
        end

        assert(flush == redirect_en);
        assert(trap_pc == id_ex_pc);
        assert(csr_addr == id_ex_imm[11:0]);
        assert(csr_op == id_ex_funct3);
        assert(csr_uimm == id_ex_rs1);
        assert(!mret_en || (id_ex_opcode == 7'h73 && id_ex_funct3 == 3'h0 && id_ex_imm[11:0] == 12'h302));
        assert(!sret_en || (id_ex_opcode == 7'h73 && id_ex_funct3 == 3'h0 && id_ex_imm[11:0] == 12'h102));
        assert(!ecall_en || (id_ex_opcode == 7'h73 && id_ex_funct3 == 3'h0 && id_ex_imm[11:0] == 12'h000));

    end
endmodule
