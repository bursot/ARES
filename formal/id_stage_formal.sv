`timescale 1ns/1ps

module id_stage_formal;
    wire [6:0] opcode = if_id_instr[6:0];
    wire [2:0] funct3 = if_id_instr[14:12];

    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;
    reg past_valid = 1'b0;

    (* anyseq *) reg        stall;
    (* anyseq *) reg        flush;
    (* anyseq *) reg [63:0] if_id_pc;
    (* anyseq *) reg [31:0] if_id_instr;
    (* anyseq *) reg        wb_reg_write;
    (* anyseq *) reg [4:0]  wb_rd;
    (* anyseq *) reg [63:0] wb_data;

    wire        ares_rf_fault_event;
    wire [63:0] ares_rf_fault_info;
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

    id_stage dut (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),
        .flush(flush),
        .if_id_pc(if_id_pc),
        .if_id_instr(if_id_instr),
        .wb_reg_write(wb_reg_write),
        .wb_rd(wb_rd),
        .wb_data(wb_data),
        .rf_parity_fault_inject_en(1'b0),
        .rf_parity_fault_idx(5'h0),
        .ares_rf_fault_event(ares_rf_fault_event),
        .ares_rf_fault_info(ares_rf_fault_info),
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
        .id_ex_jump(id_ex_jump)
    );

    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) begin
            assume(!rst_n);
        end else begin
            if ($past(rst_n))
                assume(rst_n);
        end

        if (!rst_n) begin
            assume(!stall);
            assume(!flush);
            assume(!wb_reg_write);
        end

        assume(!(stall && flush));

        if (past_valid && !$past(rst_n)) begin
            assert(id_ex_opcode == 7'h13);
            assert(id_ex_reg_write == 1'b0);
            assert(id_ex_mem_read == 1'b0);
            assert(id_ex_mem_write == 1'b0);
            assert(id_ex_mem_to_reg == 1'b0);
            assert(id_ex_branch == 1'b0);
            assert(id_ex_jump == 1'b0);
        end

        assert(!(id_ex_branch && id_ex_jump));
        assert(!id_ex_mem_to_reg || id_ex_mem_read);
    end
endmodule
