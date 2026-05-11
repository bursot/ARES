`timescale 1ns/1ps

module csr_unit_formal;
    localparam [1:0] PRV_U = 2'b00;
    localparam [1:0] PRV_S = 2'b01;
    localparam [1:0] PRV_M = 2'b11;

    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;
    reg past_valid = 1'b0;

    (* anyseq *) reg        csr_en;
    (* anyseq *) reg [11:0] csr_addr;
    (* anyseq *) reg [2:0]  csr_op;
    (* anyseq *) reg [63:0] csr_wdata;
    (* anyseq *) reg [4:0]  csr_uimm;
    (* anyseq *) reg        trap_en;
    (* anyseq *) reg [63:0] trap_pc;
    (* anyseq *) reg [63:0] trap_cause;
    (* anyseq *) reg [63:0] trap_tval;
    (* anyseq *) reg        irq_msip;
    (* anyseq *) reg        irq_mtip;
    (* anyseq *) reg        irq_meip;
    (* anyseq *) reg [63:0] interrupt_pc;
    (* anyseq *) reg        mret_en;
    (* anyseq *) reg        sret_en;
    (* anyseq *) reg        ares_fault_event;
    (* anyseq *) reg [3:0]  ares_fault_code;
    (* anyseq *) reg [63:0] ares_fault_info;

    wire [63:0] csr_rdata;
    wire [63:0] mret_pc;
    wire [63:0] sret_pc;
    wire [63:0] tvec_base;
    wire        trap_redirect;
    wire [1:0]  current_priv;
    wire        mstatus_tsr;
    wire        mstatus_tvm;

    csr_unit dut (
        .clk(clk),
        .rst_n(rst_n),
        .csr_en(csr_en),
        .csr_addr(csr_addr),
        .csr_op(csr_op),
        .csr_wdata(csr_wdata),
        .csr_uimm(csr_uimm),
        .csr_rdata(csr_rdata),
        .trap_en(trap_en),
        .trap_pc(trap_pc),
        .trap_cause(trap_cause),
        .trap_tval(trap_tval),
        .irq_msip(irq_msip),
        .irq_mtip(irq_mtip),
        .irq_meip(irq_meip),
        .interrupt_pc(interrupt_pc),
        .mret_en(mret_en),
        .sret_en(sret_en),
        .mret_pc(mret_pc),
        .sret_pc(sret_pc),
        .ares_fault_event(ares_fault_event),
        .ares_fault_code(ares_fault_code),
        .ares_fault_info(ares_fault_info),
        .tvec_base(tvec_base),
        .trap_redirect(trap_redirect),
        .current_priv(current_priv),
        .mstatus_tsr(mstatus_tsr),
        .mstatus_tvm(mstatus_tvm)
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
            assume(!csr_en);
            assume(!trap_en);
            assume(!mret_en);
            assume(!sret_en);
            assume(!ares_fault_event);
        end

        assume(!(trap_en && csr_en));
        assume(!(trap_en && mret_en));
        assume(!(trap_en && sret_en));
        assume(!(csr_en && mret_en));
        assume(!(csr_en && sret_en));
        assume(!(mret_en && sret_en));

        if (csr_en)
            assume(csr_op == 3'h1 || csr_op == 3'h2 || csr_op == 3'h3 ||
                   csr_op == 3'h5 || csr_op == 3'h6 || csr_op == 3'h7);
        if (trap_en)
            assume(trap_pc[0] == 1'b0);
        assume(interrupt_pc[0] == 1'b0);
        if (mret_en)
            assume(current_priv == PRV_M);
        if (sret_en)
            assume(current_priv == PRV_S && !mstatus_tsr);

        assert(mret_pc[0] == 1'b0);
        assert(sret_pc[0] == 1'b0);
        assert(tvec_base[1:0] == 2'b00);
        case (csr_addr)
            12'h141: assert(csr_rdata == sret_pc);
            12'h341: assert(csr_rdata == mret_pc);
            default: ;
        endcase
    end
endmodule
