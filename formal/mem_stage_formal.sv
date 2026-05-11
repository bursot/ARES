`timescale 1ns/1ps

module mem_stage_formal;
    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;
    reg past_valid = 1'b0;

    (* anyseq *) reg [63:0] ex_mem_pc;
    (* anyseq *) reg [63:0] ex_mem_alu_result;
    (* anyseq *) reg [63:0] ex_mem_rs2_data;
    (* anyseq *) reg [4:0]  ex_mem_rd;
    (* anyseq *) reg        ex_mem_reg_write;
    (* anyseq *) reg        ex_mem_mem_read;
    (* anyseq *) reg        ex_mem_mem_write;
    (* anyseq *) reg        ex_mem_mem_to_reg;
    (* anyseq *) reg [2:0]  ex_mem_funct3;
    (* anyseq *) reg        ex_mem_atomic_en;
    (* anyseq *) reg        ex_mem_atomic_is_lr;
    (* anyseq *) reg        ex_mem_atomic_is_sc;
    (* anyseq *) reg [4:0]  ex_mem_atomic_funct5;
    (* anyseq *) reg [63:0] dmem_rdata;
    (* anyseq *) reg        dmem_page_fault;
    (* anyseq *) reg [63:0] dmem_page_fault_cause;
    (* anyseq *) reg [63:0] dmem_page_fault_tval;

    wire [63:0] dmem_addr;
    wire [63:0] dmem_wdata;
    wire        dmem_we;
    wire [2:0]  dmem_funct3;
    wire        mem_trap_en;
    wire [63:0] mem_trap_pc;
    wire [63:0] mem_trap_cause;
    wire [63:0] mem_trap_tval;
    wire [63:0] mem_wb_data;
    wire [4:0]  mem_wb_rd;
    wire        mem_wb_reg_write;
    wire        mem_wb_mem_to_reg;
    wire [63:0] mem_wb_alu_result;

    mem_stage dut (
        .clk(clk),
        .rst_n(rst_n),
        .ex_mem_pc(ex_mem_pc),
        .ex_mem_alu_result(ex_mem_alu_result),
        .ex_mem_rs2_data(ex_mem_rs2_data),
        .ex_mem_rd(ex_mem_rd),
        .ex_mem_reg_write(ex_mem_reg_write),
        .ex_mem_mem_read(ex_mem_mem_read),
        .ex_mem_mem_write(ex_mem_mem_write),
        .ex_mem_mem_to_reg(ex_mem_mem_to_reg),
        .ex_mem_funct3(ex_mem_funct3),
        .ex_mem_atomic_en(ex_mem_atomic_en),
        .ex_mem_atomic_is_lr(ex_mem_atomic_is_lr),
        .ex_mem_atomic_is_sc(ex_mem_atomic_is_sc),
        .ex_mem_atomic_funct5(ex_mem_atomic_funct5),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we),
        .dmem_funct3(dmem_funct3),
        .dmem_rdata(dmem_rdata),
        .dmem_page_fault(dmem_page_fault),
        .dmem_page_fault_cause(dmem_page_fault_cause),
        .dmem_page_fault_tval(dmem_page_fault_tval),
        .mem_trap_en(mem_trap_en),
        .mem_trap_pc(mem_trap_pc),
        .mem_trap_cause(mem_trap_cause),
        .mem_trap_tval(mem_trap_tval),
        .mem_wb_data(mem_wb_data),
        .mem_wb_rd(mem_wb_rd),
        .mem_wb_reg_write(mem_wb_reg_write),
        .mem_wb_mem_to_reg(mem_wb_mem_to_reg),
        .mem_wb_alu_result(mem_wb_alu_result)
    );

    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) begin
            assume(!rst_n);
        end else begin
            assume(rst_n);
        end
        assume(!ex_mem_atomic_is_lr || ex_mem_atomic_en);
        assume(!ex_mem_atomic_is_sc || ex_mem_atomic_en);
        assume(!(ex_mem_atomic_is_lr && ex_mem_atomic_is_sc));
        assume(!ex_mem_atomic_is_lr || (ex_mem_mem_read && !ex_mem_mem_write));
        assume(!ex_mem_atomic_is_sc || (ex_mem_mem_read && ex_mem_mem_write));

        assert(dmem_addr == ex_mem_alu_result);
        assert(dmem_funct3 == ex_mem_funct3);
        if (!ex_mem_atomic_en) begin
            assert(dmem_wdata == ex_mem_rs2_data);
            assert(dmem_we == ex_mem_mem_write);
        end

    end
endmodule
