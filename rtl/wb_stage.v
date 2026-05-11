// ARES Core — WB Stage (Write Back)
// Selects the value to write back to the register file.
// Either the ALU result or the loaded memory data.
// Actual write happens in id_stage.v (register file lives there).

`timescale 1ns/1ps

module wb_stage (
    // From MEM/WB pipeline register
    input  wire [63:0] mem_wb_alu_result,
    input  wire [63:0] mem_wb_data,
    input  wire        mem_wb_mem_to_reg,
    input  wire        mem_wb_reg_write,
    input  wire [4:0]  mem_wb_rd,

    // Outputs to register file (in id_stage)
    output wire [63:0] wb_data,
    output wire        wb_reg_write,
    output wire [4:0]  wb_rd
);

    // Select: load result or ALU result
    assign wb_data      = mem_wb_mem_to_reg ? mem_wb_data : mem_wb_alu_result;
    assign wb_reg_write = mem_wb_reg_write;
    assign wb_rd        = mem_wb_rd;

endmodule
