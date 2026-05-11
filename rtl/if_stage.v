// ARES Core — IF Stage (Instruction Fetch)
// Fetches one instruction per cycle from memory.
// On a taken branch or jump, the PC is redirected and
// the fetch-stage bubble is inserted automatically by
// the pipeline registers in ares_core.v.

`timescale 1ns/1ps

module if_stage (
    input  wire        clk,
    input  wire        rst_n,       // active-low reset

    // Pipeline control
    input  wire        stall,       // hold PC and output registers
    input  wire        flush,       // insert NOP (branch misprediction)

    // Branch/jump redirect from EX stage
    input  wire        redirect_en,
    input  wire [63:0] redirect_pc,

    // Instruction memory interface (combinational read)
    output wire [63:0] imem_addr,
    input  wire [31:0] imem_data,

    // Output to IF/ID pipeline register
    output reg  [63:0] if_id_pc,
    output reg  [31:0] if_id_instr
);

    // Program Counter
    reg [63:0] pc;

    // Drive instruction memory address
    assign imem_addr = pc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc          <= 64'h80000000;  // RISC-V standard reset vector
            if_id_pc    <= 64'h0;
            if_id_instr <= 32'h00000013; // NOP (addi x0, x0, 0)
        end
        else if (flush) begin
            // Branch taken: kill the instruction in flight
            if_id_pc    <= 64'h0;
            if_id_instr <= 32'h00000013; // NOP
            pc          <= redirect_pc;
        end
        else if (!stall) begin
            if_id_pc    <= pc;        // pc before increment = fetch address
            if_id_instr <= imem_data;
            pc          <= redirect_en ? redirect_pc : pc + 64'h4;
        end
        // stall: hold everything, do nothing
    end

endmodule
