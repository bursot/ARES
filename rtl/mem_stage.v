// ARES Core — MEM Stage (Memory Access)
// Handles load and store operations to data memory.

`timescale 1ns/1ps

module mem_stage (
    input  wire        clk,
    input  wire        rst_n,

    // From EX/MEM pipeline register
    input  wire [63:0] ex_mem_pc,
    input  wire [63:0] ex_mem_alu_result,
    input  wire [63:0] ex_mem_rs2_data,
    input  wire [4:0]  ex_mem_rd,
    input  wire        ex_mem_reg_write,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire        ex_mem_mem_read,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire        ex_mem_mem_write,
    input  wire        ex_mem_mem_to_reg,
    input  wire [2:0]  ex_mem_funct3,
    input  wire        ex_mem_atomic_en,
    input  wire        ex_mem_atomic_is_lr,
    input  wire        ex_mem_atomic_is_sc,
    input  wire [4:0]  ex_mem_atomic_funct5,

    // Data memory interface
    output wire [63:0] dmem_addr,
    output wire [63:0] dmem_wdata,
    output wire        dmem_we,
    output wire [2:0]  dmem_funct3,
    input  wire [63:0] dmem_rdata,
    input  wire        dmem_page_fault,
    input  wire [63:0] dmem_page_fault_cause,
    input  wire [63:0] dmem_page_fault_tval,

    // Trap output to CSR unit
    output wire        mem_trap_en,
    output wire [63:0] mem_trap_pc,
    output wire [63:0] mem_trap_cause,
    output wire [63:0] mem_trap_tval,

    // Outputs to MEM/WB pipeline register
    output reg  [63:0] mem_wb_data,
    output reg  [4:0]  mem_wb_rd,
    output reg         mem_wb_reg_write,
    output reg         mem_wb_mem_to_reg,
    output reg  [63:0] mem_wb_alu_result
);

    reg        reservation_valid;
    reg [63:0] reservation_addr;
    wire atomic_is_word = (ex_mem_funct3 == 3'h2);
    wire atomic_sc_success = reservation_valid && (reservation_addr == ex_mem_alu_result);

    reg [63:0] atomic_wdata;
    reg        atomic_we;
    reg [31:0] atomic_wdata_w;
    wire signed [31:0] atomic_old_w_signed = dmem_rdata[31:0];
    wire signed [31:0] atomic_rs2_w_signed = ex_mem_rs2_data[31:0];
    wire signed [63:0] atomic_old_d_signed = dmem_rdata;
    wire signed [63:0] atomic_rs2_d_signed = ex_mem_rs2_data;

    always @(*) begin
        atomic_wdata = ex_mem_rs2_data;
        atomic_wdata_w = ex_mem_rs2_data[31:0];
        atomic_we = 1'b0;
        if (ex_mem_atomic_en) begin
            if (ex_mem_atomic_is_sc) begin
                atomic_we = atomic_sc_success;
            end else if (!ex_mem_atomic_is_lr) begin
                atomic_we = 1'b1;
                if (atomic_is_word) begin
                    case (ex_mem_atomic_funct5)
                        5'b00001: atomic_wdata_w = ex_mem_rs2_data[31:0]; // amoswap.w
                        5'b00000: atomic_wdata_w = dmem_rdata[31:0] + ex_mem_rs2_data[31:0]; // amoadd.w
                        5'b00100: atomic_wdata_w = dmem_rdata[31:0] ^ ex_mem_rs2_data[31:0]; // amoxor.w
                        5'b01100: atomic_wdata_w = dmem_rdata[31:0] & ex_mem_rs2_data[31:0]; // amoand.w
                        5'b01000: atomic_wdata_w = dmem_rdata[31:0] | ex_mem_rs2_data[31:0]; // amoor.w
                        5'b10000: atomic_wdata_w = (atomic_old_w_signed < atomic_rs2_w_signed) ? dmem_rdata[31:0] : ex_mem_rs2_data[31:0];
                        5'b10100: atomic_wdata_w = (atomic_old_w_signed > atomic_rs2_w_signed) ? dmem_rdata[31:0] : ex_mem_rs2_data[31:0];
                        5'b11000: atomic_wdata_w = (dmem_rdata[31:0] < ex_mem_rs2_data[31:0]) ? dmem_rdata[31:0] : ex_mem_rs2_data[31:0];
                        5'b11100: atomic_wdata_w = (dmem_rdata[31:0] > ex_mem_rs2_data[31:0]) ? dmem_rdata[31:0] : ex_mem_rs2_data[31:0];
                        default: atomic_wdata_w = ex_mem_rs2_data[31:0];
                    endcase
                    atomic_wdata = {32'h0, atomic_wdata_w};
                end else begin
                    case (ex_mem_atomic_funct5)
                        5'b00001: atomic_wdata = ex_mem_rs2_data; // amoswap.d
                        5'b00000: atomic_wdata = dmem_rdata + ex_mem_rs2_data; // amoadd.d
                        5'b00100: atomic_wdata = dmem_rdata ^ ex_mem_rs2_data; // amoxor.d
                        5'b01100: atomic_wdata = dmem_rdata & ex_mem_rs2_data; // amoand.d
                        5'b01000: atomic_wdata = dmem_rdata | ex_mem_rs2_data; // amoor.d
                        5'b10000: atomic_wdata = (atomic_old_d_signed < atomic_rs2_d_signed) ? dmem_rdata : ex_mem_rs2_data;
                        5'b10100: atomic_wdata = (atomic_old_d_signed > atomic_rs2_d_signed) ? dmem_rdata : ex_mem_rs2_data;
                        5'b11000: atomic_wdata = (dmem_rdata < ex_mem_rs2_data) ? dmem_rdata : ex_mem_rs2_data;
                        5'b11100: atomic_wdata = (dmem_rdata > ex_mem_rs2_data) ? dmem_rdata : ex_mem_rs2_data;
                        default: atomic_wdata = ex_mem_rs2_data;
                    endcase
                end
            end
        end
    end

    // Drive data memory signals combinationally
    assign dmem_addr   = ex_mem_alu_result;
    assign dmem_wdata  = ex_mem_atomic_en ? atomic_wdata : ex_mem_rs2_data;
    assign dmem_we     = ex_mem_atomic_en ? atomic_we : ex_mem_mem_write;
    assign dmem_funct3 = ex_mem_funct3;
    assign mem_trap_en = dmem_page_fault && (ex_mem_mem_read || ex_mem_mem_write || ex_mem_atomic_en);
    assign mem_trap_pc = ex_mem_pc;
    assign mem_trap_cause = dmem_page_fault_cause;
    assign mem_trap_tval = dmem_page_fault_tval;

    // Load data with sign/zero extension
    reg [63:0] load_data;
    always @(*) begin
        case (ex_mem_funct3)
            3'h0: load_data = {{56{dmem_rdata[7]}},  dmem_rdata[7:0]};   // LB
            3'h1: load_data = {{48{dmem_rdata[15]}}, dmem_rdata[15:0]};  // LH
            3'h2: load_data = {{32{dmem_rdata[31]}}, dmem_rdata[31:0]};  // LW
            3'h3: load_data = dmem_rdata;                                  // LD
            3'h4: load_data = {56'h0, dmem_rdata[7:0]};                   // LBU
            3'h5: load_data = {48'h0, dmem_rdata[15:0]};                  // LHU
            3'h6: load_data = {32'h0, dmem_rdata[31:0]};                  // LWU
            default: load_data = 64'h0;
        endcase
    end

    // MEM/WB pipeline register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_data       <= 64'h0;
            mem_wb_rd         <= 5'h0;
            mem_wb_reg_write  <= 1'b0;
            mem_wb_mem_to_reg <= 1'b0;
            mem_wb_alu_result <= 64'h0;
            reservation_valid <= 1'b0;
            reservation_addr  <= 64'h0;
        end else begin
            if (mem_trap_en) begin
                mem_wb_data       <= 64'h0;
                mem_wb_rd         <= 5'h0;
                mem_wb_reg_write  <= 1'b0;
                mem_wb_mem_to_reg <= 1'b0;
                mem_wb_alu_result <= 64'h0;
                reservation_valid <= 1'b0;
                reservation_addr  <= 64'h0;
            end else begin
                mem_wb_data       <= load_data;
                mem_wb_rd         <= ex_mem_rd;
                mem_wb_reg_write  <= ex_mem_reg_write;
                mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
                mem_wb_alu_result <= (ex_mem_atomic_en && ex_mem_atomic_is_sc) ? {63'h0, !atomic_sc_success} :
                                     ex_mem_alu_result;
                if (ex_mem_atomic_en) begin
                    if (ex_mem_atomic_is_lr) begin
                        reservation_valid <= 1'b1;
                        reservation_addr  <= ex_mem_alu_result;
                    end else begin
                        reservation_valid <= 1'b0;
                        reservation_addr  <= 64'h0;
                    end
                end else if (ex_mem_mem_write) begin
                    reservation_valid <= 1'b0;
                    reservation_addr  <= 64'h0;
                end
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;

        assert(mem_trap_en == (dmem_page_fault && (ex_mem_mem_read || ex_mem_mem_write || ex_mem_atomic_en)));
        assert(mem_trap_pc == ex_mem_pc);
        assert(mem_trap_cause == dmem_page_fault_cause);
        assert(mem_trap_tval == dmem_page_fault_tval);
        assert(dmem_addr == ex_mem_alu_result);
        assert(dmem_funct3 == ex_mem_funct3);
        if (!ex_mem_atomic_en) begin
            assert(dmem_wdata == ex_mem_rs2_data);
            assert(dmem_we == ex_mem_mem_write);
        end else begin
            assert(dmem_wdata == atomic_wdata);
            assert(dmem_we == atomic_we);
        end

        case (ex_mem_funct3)
            3'h0: assert(load_data == {{56{dmem_rdata[7]}},  dmem_rdata[7:0]});
            3'h1: assert(load_data == {{48{dmem_rdata[15]}}, dmem_rdata[15:0]});
            3'h2: assert(load_data == {{32{dmem_rdata[31]}}, dmem_rdata[31:0]});
            3'h3: assert(load_data == dmem_rdata);
            3'h4: assert(load_data == {56'h0, dmem_rdata[7:0]});
            3'h5: assert(load_data == {48'h0, dmem_rdata[15:0]});
            3'h6: assert(load_data == {32'h0, dmem_rdata[31:0]});
            default: assert(load_data == 64'h0);
        endcase

        if (f_past_valid && !$past(rst_n)) begin
            assert(mem_wb_data == 64'h0);
            assert(mem_wb_rd == 5'h0);
            assert(mem_wb_reg_write == 1'b0);
            assert(mem_wb_mem_to_reg == 1'b0);
            assert(mem_wb_alu_result == 64'h0);
            assert(reservation_valid == 1'b0);
            assert(reservation_addr == 64'h0);
        end

        if (f_past_valid && $past(rst_n) && $past(mem_trap_en)) begin
            assert(mem_wb_data == 64'h0);
            assert(mem_wb_rd == 5'h0);
            assert(mem_wb_reg_write == 1'b0);
            assert(mem_wb_mem_to_reg == 1'b0);
            assert(mem_wb_alu_result == 64'h0);
            assert(reservation_valid == 1'b0);
            assert(reservation_addr == 64'h0);
        end

    end
`endif

endmodule
