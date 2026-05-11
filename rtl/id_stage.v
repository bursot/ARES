// ARES Core — ID Stage (Instruction Decode)
// Decodes the instruction and reads the register file.
// Also generates all control signals for downstream stages.

`timescale 1ns/1ps

module id_stage (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    // From IF/ID pipeline register
    input  wire [63:0] if_id_pc,
    input  wire [31:0] if_id_instr,

    // Writeback port (from WB stage)
    input  wire        wb_reg_write,
    input  wire [4:0]  wb_rd,
    input  wire [63:0] wb_data,
    input  wire        rf_parity_fault_inject_en,
    input  wire [4:0]  rf_parity_fault_idx,

    // ARES resilience telemetry
    output wire        ares_rf_fault_event,
    output wire [63:0] ares_rf_fault_info,

    // Outputs to ID/EX pipeline register
    output reg  [63:0] id_ex_pc,
    output reg  [63:0] id_ex_rs1_data,
    output reg  [63:0] id_ex_rs2_data,
    output reg  [63:0] id_ex_imm,
    output reg  [4:0]  id_ex_rs1,
    output reg  [4:0]  id_ex_rs2,
    output reg  [4:0]  id_ex_rd,
    output reg  [6:0]  id_ex_opcode,
    output reg  [2:0]  id_ex_funct3,
    output reg  [6:0]  id_ex_funct7,

    // Control signals
    output reg         id_ex_reg_write,
    output reg         id_ex_mem_read,
    output reg         id_ex_mem_write,
    output reg         id_ex_mem_to_reg,
    output reg         id_ex_branch,
    output reg         id_ex_jump
);

    // Register file — 32 x 64-bit
    reg [63:0] regfile [0:31];
    reg        regfile_parity [0:31];

    // Decode fields
    wire [6:0] opcode = if_id_instr[6:0];
    wire [4:0] rd     = if_id_instr[11:7];
    wire [2:0] funct3 = if_id_instr[14:12];
    wire [4:0] rs1    = if_id_instr[19:15];
    wire [4:0] rs2    = if_id_instr[24:20];
    wire [6:0] funct7 = if_id_instr[31:25];
    wire [4:0] atomic_funct5 = if_id_instr[31:27];
    wire is_atomic = (opcode == 7'h2F);
    wire is_lr = is_atomic && (atomic_funct5 == 5'b00010) && (rs2 == 5'h0);
    wire is_sc = is_atomic && (atomic_funct5 == 5'b00011);
    wire is_amo = is_atomic && !is_lr && !is_sc;

    // Immediate generation
    wire [63:0] imm_i = {{52{if_id_instr[31]}}, if_id_instr[31:20]};
    wire [63:0] imm_s = {{52{if_id_instr[31]}}, if_id_instr[31:25], if_id_instr[11:7]};
    wire [63:0] imm_b = {{51{if_id_instr[31]}}, if_id_instr[31], if_id_instr[7],
                         if_id_instr[30:25], if_id_instr[11:8], 1'b0};
    wire [63:0] imm_u = {{32{if_id_instr[31]}}, if_id_instr[31:12], 12'b0};
    wire [63:0] imm_j = {{43{if_id_instr[31]}}, if_id_instr[31], if_id_instr[19:12],
                         if_id_instr[20], if_id_instr[30:21], 1'b0};

    // Select immediate based on opcode
    reg [63:0] imm;
    always @(*) begin
        case (opcode)
            7'h03, 7'h13, 7'h1B, 7'h67: imm = imm_i; // Load, ALU-I, ALU-IW, JALR
            7'h73:                        imm = imm_i; // CSR: bits[31:20] = CSR address
            7'h23:                        imm = imm_s; // Store
            7'h63:                        imm = imm_b; // Branch
            7'h37, 7'h17:                 imm = imm_u; // LUI, AUIPC
            7'h6F:                        imm = imm_j; // JAL
            default:                      imm = 64'h0;
        endcase
    end

    // Control signal decode
    wire reg_write  = (opcode == 7'h33) || (opcode == 7'h3B) ||
                      (opcode == 7'h13) || (opcode == 7'h1B) ||
                      (opcode == 7'h03) || (opcode == 7'h37) ||
                      (opcode == 7'h17) || (opcode == 7'h67) ||
                      (opcode == 7'h6F) || is_atomic ||
                      (opcode == 7'h73 && funct3 != 3'h0); // CSR reads write rd
    wire mem_read   = (opcode == 7'h03) || is_lr || is_sc || is_amo;
    wire mem_write  = (opcode == 7'h23) || is_sc || is_amo;
    wire mem_to_reg = (opcode == 7'h03) || is_lr || is_amo;
    wire branch     = (opcode == 7'h63);
    wire jump       = (opcode == 7'h6F) || (opcode == 7'h67);

    // Register read (with writeback forwarding for WB hazard)
    wire [63:0] rs1_data = (wb_reg_write && wb_rd == rs1 && rs1 != 0) ? wb_data : regfile[rs1];
    wire [63:0] rs2_data = (wb_reg_write && wb_rd == rs2 && rs2 != 0) ? wb_data : regfile[rs2];
    wire rs1_parity_ok = (rs1 == 5'h0) || ((^regfile[rs1]) == regfile_parity[rs1]);
    wire rs2_parity_ok = (rs2 == 5'h0) || ((^regfile[rs2]) == regfile_parity[rs2]);

    reg [4:0] first_bad_reg;
    reg any_regfile_parity_error;
    integer parity_idx;
    always @(*) begin
        first_bad_reg = 5'h0;
        any_regfile_parity_error = 1'b0;
        for (parity_idx = 1; parity_idx < 32; parity_idx = parity_idx + 1) begin
            if (!any_regfile_parity_error && ((^regfile[parity_idx]) != regfile_parity[parity_idx])) begin
                any_regfile_parity_error = 1'b1;
                first_bad_reg = parity_idx[4:0];
            end
        end
    end

    reg regfile_parity_error_seen;
    assign ares_rf_fault_event = any_regfile_parity_error && !regfile_parity_error_seen;
    assign ares_rf_fault_info = {
        48'h0,
        6'h0,
        first_bad_reg,
        2'b00,
        !rs2_parity_ok,
        !rs1_parity_ok,
        any_regfile_parity_error
    };

    // Writeback — write on rising edge
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                regfile[i] <= 64'h0;
                regfile_parity[i] <= 1'b0;
            end
            regfile_parity_error_seen <= 1'b0;
        end else begin
            if (wb_reg_write && wb_rd != 0) begin
                regfile[wb_rd] <= wb_data;
                regfile_parity[wb_rd] <= ^wb_data;
            end
            if (rf_parity_fault_inject_en && rf_parity_fault_idx != 0) begin
                if (wb_reg_write && (wb_rd == rf_parity_fault_idx) && (wb_rd != 0))
                    regfile_parity[rf_parity_fault_idx] <= ~(^wb_data);
                else
                    regfile_parity[rf_parity_fault_idx] <= ~regfile_parity[rf_parity_fault_idx];
            end
            regfile_parity_error_seen <= any_regfile_parity_error;
        end
    end

    // Pipeline register update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_pc       <= 64'h0;
            id_ex_rs1_data <= 64'h0;
            id_ex_rs2_data <= 64'h0;
            id_ex_imm      <= 64'h0;
            id_ex_rs1      <= 5'h0;
            id_ex_rs2      <= 5'h0;
            id_ex_rd       <= 5'h0;
            id_ex_opcode   <= 7'h13; // NOP
            id_ex_funct3   <= 3'h0;
            id_ex_funct7   <= 7'h0;
            id_ex_reg_write  <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_mem_to_reg <= 1'b0;
            id_ex_branch     <= 1'b0;
            id_ex_jump       <= 1'b0;
        end else if (flush) begin
            id_ex_pc       <= 64'h0;
            id_ex_rs1_data <= 64'h0;
            id_ex_rs2_data <= 64'h0;
            id_ex_imm      <= 64'h0;
            id_ex_rs1      <= 5'h0;
            id_ex_rs2      <= 5'h0;
            id_ex_rd       <= 5'h0;
            id_ex_opcode   <= 7'h13; // NOP
            id_ex_funct3   <= 3'h0;
            id_ex_funct7   <= 7'h0;
            id_ex_reg_write  <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_mem_to_reg <= 1'b0;
            id_ex_branch     <= 1'b0;
            id_ex_jump       <= 1'b0;
        end else if (stall) begin
            id_ex_pc       <= 64'h0;
            id_ex_rs1_data <= 64'h0;
            id_ex_rs2_data <= 64'h0;
            id_ex_imm      <= 64'h0;
            id_ex_rs1      <= 5'h0;
            id_ex_rs2      <= 5'h0;
            id_ex_rd       <= 5'h0;
            id_ex_opcode   <= 7'h13; // NOP
            id_ex_funct3   <= 3'h0;
            id_ex_funct7   <= 7'h0;
            id_ex_reg_write  <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_mem_to_reg <= 1'b0;
            id_ex_branch     <= 1'b0;
            id_ex_jump       <= 1'b0;
        end else begin
            id_ex_pc       <= if_id_pc;
            id_ex_rs1_data <= rs1_data;
            id_ex_rs2_data <= rs2_data;
            id_ex_imm      <= imm;
            id_ex_rs1      <= rs1;
            id_ex_rs2      <= rs2;
            id_ex_rd       <= rd;
            id_ex_opcode   <= opcode;
            id_ex_funct3   <= funct3;
            id_ex_funct7   <= funct7;
            id_ex_reg_write  <= reg_write;
            id_ex_mem_read   <= mem_read;
            id_ex_mem_write  <= mem_write;
            id_ex_mem_to_reg <= mem_to_reg;
            id_ex_branch     <= branch;
            id_ex_jump       <= jump;
        end
    end

`ifdef FORMAL
    reg f_past_valid;
    integer f_idx;
    always @(posedge clk) begin
        f_past_valid <= 1'b1;

        assert(regfile[0] == 64'h0);
        assert(regfile_parity[0] == 1'b0);
        for (f_idx = 1; f_idx < 32; f_idx = f_idx + 1) begin
            assert((^regfile[f_idx]) == regfile_parity[f_idx]);
        end

        if (f_past_valid && !$past(rst_n)) begin
            for (f_idx = 0; f_idx < 32; f_idx = f_idx + 1) begin
                assert(regfile[f_idx] == 64'h0);
                assert(regfile_parity[f_idx] == 1'b0);
            end
        end

        if (f_past_valid && $past(rst_n) && ($past(flush) || $past(stall))) begin
            assert(id_ex_opcode == 7'h13);
            assert(id_ex_reg_write == 1'b0);
            assert(id_ex_mem_read == 1'b0);
            assert(id_ex_mem_write == 1'b0);
            assert(id_ex_mem_to_reg == 1'b0);
            assert(id_ex_branch == 1'b0);
            assert(id_ex_jump == 1'b0);
        end
    end
`endif

endmodule
