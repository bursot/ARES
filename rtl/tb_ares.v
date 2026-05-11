// ARES Core — Testbench
`timescale 1ns/1ps

module tb_ares;

    reg clk, rst_n;
    localparam [63:0] MEM_BASE = 64'h80000000;
    integer cycle_count;
    integer j;
    integer i;

    // Load program words first, then expand into 64-bit memory rows.
    reg [31:0] mem_words [0:65535];
    reg [63:0] mem [0:32767];
    reg        mem_parity [0:32767];

    // Memory interface
    wire [63:0] imem_addr, dmem_addr, dmem_wdata;
    reg  [63:0] imem_addr_phys;
    reg  [63:0] dmem_addr_phys;
    wire [63:0] imem_offset = imem_addr_phys - MEM_BASE;
    wire [63:0] dmem_offset = dmem_addr_phys - MEM_BASE;
    wire [14:0] imem_qidx = imem_offset[17:3];
    wire [14:0] dmem_qidx = dmem_offset[17:3];
    wire        dmem_we;
    wire [2:0]  dmem_funct3;
    wire [31:0] imem_data;
    wire [31:0] imem_data_raw;
    wire [63:0] dmem_rdata;
    reg  [63:0] dmem_rdata_raw;
    reg         imem_fault_r;
    reg  [63:0] imem_fault_cause_r;
    reg  [63:0] imem_fault_tval_r;
    reg         dmem_page_fault_r;
    reg  [63:0] dmem_page_fault_cause_r;
    reg  [63:0] dmem_page_fault_tval_r;
    wire        dmem_page_fault = dmem_page_fault_r;
    wire [63:0] dmem_page_fault_cause = dmem_page_fault_cause_r;
    wire [63:0] dmem_page_fault_tval = dmem_page_fault_tval_r;
    reg         itlb_valid;
    reg  [63:0] itlb_satp;
    reg  [26:0] itlb_vpn;
    reg  [1:0]  itlb_priv;
    reg         itlb_sum;
    reg  [63:0] itlb_phys_page;
    reg         itlb_fault;
    reg  [63:0] itlb_fault_cause;
    reg  [63:0] itlb_fault_tval;
    reg         dtlb_valid;
    reg  [63:0] dtlb_satp;
    reg  [26:0] dtlb_vpn;
    reg  [1:0]  dtlb_priv;
    reg         dtlb_sum;
    reg  [1:0]  dtlb_access;
    reg  [63:0] dtlb_phys_page;
    reg         dtlb_fault;
    reg  [63:0] dtlb_fault_cause;
    reg  [63:0] dtlb_fault_tval;
    reg         itlb_fill;
    reg  [63:0] itlb_fill_satp;
    reg  [26:0] itlb_fill_vpn;
    reg  [1:0]  itlb_fill_priv;
    reg         itlb_fill_sum;
    reg  [63:0] itlb_fill_phys_page;
    reg         itlb_fill_fault;
    reg  [63:0] itlb_fill_fault_cause;
    reg  [63:0] itlb_fill_fault_tval;
    reg         dtlb_fill;
    reg  [63:0] dtlb_fill_satp;
    reg  [26:0] dtlb_fill_vpn;
    reg  [1:0]  dtlb_fill_priv;
    reg         dtlb_fill_sum;
    reg  [1:0]  dtlb_fill_access;
    reg  [63:0] dtlb_fill_phys_page;
    reg         dtlb_fill_fault;
    reg  [63:0] dtlb_fill_fault_cause;
    reg  [63:0] dtlb_fill_fault_tval;
    wire        ares_fault_event;
    wire [3:0]  ares_fault_code;
    wire [63:0] ares_fault_info;
    wire        irq_msip;
    wire        irq_mtip;
    wire        irq_meip;

    localparam [1:0] ACCESS_FETCH = 2'd0;
    localparam [1:0] ACCESS_LOAD  = 2'd1;
    localparam [1:0] ACCESS_STORE = 2'd2;
    localparam [63:0] CAUSE_FETCH_ACCESS_FAULT = 64'd1;
    localparam [63:0] CAUSE_LOAD_ACCESS_FAULT  = 64'd5;
    localparam [63:0] CAUSE_STORE_ACCESS_FAULT = 64'd7;

    assign imem_data_raw = imem_addr_phys[2] ? mem[imem_qidx][63:32] : mem[imem_qidx][31:0];

    function [14:0] mem_row_index;
        input [63:0] addr;
        reg [63:0] offset;
        begin
            offset = addr - MEM_BASE;
            mem_row_index = offset[17:3];
        end
    endfunction

    function [7:0] mem_read_byte;
        input [63:0] addr;
        reg [14:0] row_idx;
        reg [5:0]  bit_idx;
        reg [63:0] row_data;
        begin
            row_idx = mem_row_index(addr);
            bit_idx = {addr[2:0], 3'b000};
            row_data = mem[row_idx] >> bit_idx;
            mem_read_byte = row_data[7:0];
        end
    endfunction

    function [31:0] mem_read_word;
        input [63:0] addr;
        begin
            mem_read_word = {
                mem_read_byte(addr + 64'd3),
                mem_read_byte(addr + 64'd2),
                mem_read_byte(addr + 64'd1),
                mem_read_byte(addr)
            };
        end
    endfunction

    function [63:0] mem_read_dword;
        input [63:0] addr;
        reg [14:0] row_idx;
        begin
            row_idx = mem_row_index(addr);
            mem_read_dword = mem[row_idx];
        end
    endfunction

    task mem_write_byte;
        input [63:0] addr;
        input [7:0]  value;
        reg [14:0] row_idx;
        reg [5:0]  bit_idx;
        begin
            row_idx = mem_row_index(addr);
            bit_idx = {addr[2:0], 3'b000};
            mem[row_idx] = (mem[row_idx] & ~(64'hff << bit_idx)) |
                           ({56'h0, value} << bit_idx);
        end
    endtask

    task automatic pmp_check;
        input  [63:0] paddr;
        input  [3:0]  access_size;
        input  [1:0]  access_type;
        input  [1:0]  eff_priv;
        input  [63:0] fault_tval_in;
        output        fault;
        output [63:0] cause;
        output [63:0] tval;
        reg [7:0]  pmpcfg0;
        reg [1:0]  pmp_a;
        reg [63:0] pmpaddr0;
        reg [63:0] range_start;
        reg [63:0] range_end;
        reg [63:0] last_byte;
        reg [63:0] low_mask;
        reg [63:0] region_size;
        reg        fully_matched;
        reg        allowed;
        integer trailing_ones;
        begin
            fault = 1'b0;
            cause = 64'h0;
            tval = 64'h0;
            pmpcfg0 = dut.u_csr.pmpcfg0[7:0];
            pmp_a = pmpcfg0[4:3];

            if (pmp_a != 2'b00) begin
                pmpaddr0 = dut.u_csr.pmpaddr0;
                range_start = 64'h0;
                range_end = 64'h0;
                case (pmp_a)
                    2'b01: begin
                        range_start = 64'h0;
                        range_end = pmpaddr0 << 2;
                    end
                    2'b10: begin
                        range_start = pmpaddr0 << 2;
                        range_end = (pmpaddr0 << 2) + 64'd4;
                    end
                    default: begin
                        trailing_ones = 0;
                        while ((trailing_ones < 63) && pmpaddr0[trailing_ones]) begin
                            trailing_ones = trailing_ones + 1;
                        end
                        if (trailing_ones >= 63)
                            low_mask = ~64'h0;
                        else
                            low_mask = (64'h1 << (trailing_ones + 1)) - 64'h1;
                        if (trailing_ones >= 61)
                            region_size = ~64'h0;
                        else
                            region_size = 64'h1 << (trailing_ones + 3);
                        range_start = (pmpaddr0 & ~low_mask) << 2;
                        if ((region_size == ~64'h0) || (range_start > (~64'h0 - region_size)))
                            range_end = ~64'h0;
                        else
                            range_end = range_start + region_size;
                    end
                endcase

                last_byte = paddr + {60'h0, access_size} - 64'd1;
                fully_matched = (last_byte >= paddr) &&
                                (paddr >= range_start) &&
                                (last_byte < range_end);

                if (!fully_matched) begin
                    if (eff_priv != 2'b11) begin
                        fault = 1'b1;
                        cause = (access_type == ACCESS_FETCH) ? CAUSE_FETCH_ACCESS_FAULT :
                                (access_type == ACCESS_LOAD)  ? CAUSE_LOAD_ACCESS_FAULT :
                                                                CAUSE_STORE_ACCESS_FAULT;
                        tval = fault_tval_in;
                    end
                end else if ((eff_priv == 2'b11) && !pmpcfg0[7]) begin
                    fault = 1'b0;
                end else begin
                    allowed = (access_type == ACCESS_FETCH) ? pmpcfg0[2] :
                              (access_type == ACCESS_LOAD)  ? pmpcfg0[0] :
                                                              pmpcfg0[1];
                    if (!allowed) begin
                        fault = 1'b1;
                        cause = (access_type == ACCESS_FETCH) ? CAUSE_FETCH_ACCESS_FAULT :
                                (access_type == ACCESS_LOAD)  ? CAUSE_LOAD_ACCESS_FAULT :
                                                                CAUSE_STORE_ACCESS_FAULT;
                        tval = fault_tval_in;
                    end
                end
            end
        end
    endtask

    task automatic translate_addr;
        input  [63:0] vaddr;
        input  [1:0]  access_type;
        input  [3:0]  access_size;
        output [63:0] paddr;
        output        fault;
        output [63:0] cause;
        output [63:0] tval;
        reg done;
        reg [1:0] eff_priv;
        reg [63:0] satp_reg;
        reg [63:0] root_table;
        reg [63:0] table_addr;
        reg [63:0] pte_addr;
        reg [63:0] pte;
        reg [43:0] pte_ppn;
        reg [63:0] page_mask;
        reg [63:0] page_base;
        reg [8:0] vpn2;
        reg [8:0] vpn1;
        reg [8:0] vpn0;
        reg pmp_fault;
        reg [63:0] pmp_cause;
        reg [63:0] pmp_tval;
        integer level;
        begin
            paddr = vaddr;
            fault = 1'b0;
            cause = 64'h0;
            tval  = 64'h0;
            done  = 1'b0;
            eff_priv = dut.u_csr.current_priv;
            if ((access_type != ACCESS_FETCH) &&
                (dut.u_csr.current_priv == 2'b11) &&
                dut.u_csr.mstatus_mprv)
                eff_priv = dut.u_csr.mstatus_mpp;

            satp_reg = dut.u_csr.satp;
            if ((satp_reg[63:60] != 4'h8) || (eff_priv == 2'b11)) begin
                pmp_check(vaddr, access_size, access_type, eff_priv, vaddr,
                          pmp_fault, pmp_cause, pmp_tval);
                if (pmp_fault) begin
                    fault = 1'b1;
                    cause = pmp_cause;
                    tval = pmp_tval;
                end
                done = 1'b1;
            end
            else if (vaddr[63:39] != {25{vaddr[38]}}) begin
                fault = 1'b1;
                cause = (access_type == ACCESS_FETCH) ? 64'd12 :
                        (access_type == ACCESS_LOAD)  ? 64'd13 : 64'd15;
                tval = vaddr;
                done = 1'b1;
            end

            vpn2 = vaddr[38:30];
            vpn1 = vaddr[29:21];
            vpn0 = vaddr[20:12];
            root_table = {8'h00, satp_reg[43:0], 12'h000};
            table_addr = root_table;

            for (level = 2; level >= 0; level = level - 1) begin
                if (!done) begin
                    case (level)
                        2: pte_addr = table_addr + {52'h0, vpn2, 3'b000};
                        1: pte_addr = table_addr + {52'h0, vpn1, 3'b000};
                        default: pte_addr = table_addr + {52'h0, vpn0, 3'b000};
                    endcase
                    pmp_check(pte_addr, 4'd8, ACCESS_LOAD, 2'b01, vaddr,
                              pmp_fault, pmp_cause, pmp_tval);
                    if (pmp_fault) begin
                        fault = 1'b1;
                        cause = (access_type == ACCESS_FETCH) ? CAUSE_FETCH_ACCESS_FAULT :
                                (access_type == ACCESS_LOAD)  ? CAUSE_LOAD_ACCESS_FAULT :
                                                                CAUSE_STORE_ACCESS_FAULT;
                        tval = vaddr;
                        done = 1'b1;
                    end else begin
                        pte = mem_read_dword(pte_addr);
                    end
                    if (!done && (!pte[0] || (!pte[1] && pte[2]))) begin
                        fault = 1'b1;
                        cause = (access_type == ACCESS_FETCH) ? 64'd12 :
                                (access_type == ACCESS_LOAD)  ? 64'd13 : 64'd15;
                        tval = vaddr;
                        done = 1'b1;
                    end else if (!done && !pte[1] && !pte[3]) begin
                        if (level == 0) begin
                            fault = 1'b1;
                            cause = (access_type == ACCESS_FETCH) ? 64'd12 :
                                    (access_type == ACCESS_LOAD)  ? 64'd13 : 64'd15;
                            tval = vaddr;
                            done = 1'b1;
                        end else begin
                            table_addr = {8'h00, pte[53:10], 12'h000};
                        end
                    end else if (!done) begin
                        pte_ppn = pte[53:10];
                        if ((level == 2 && pte_ppn[17:0] != 18'h0) ||
                            (level == 1 && pte_ppn[8:0]  != 9'h0)) begin
                            fault = 1'b1;
                            cause = (access_type == ACCESS_FETCH) ? 64'd12 :
                                    (access_type == ACCESS_LOAD)  ? 64'd13 : 64'd15;
                            tval = vaddr;
                            done = 1'b1;
                        end else begin
                            if (access_type == ACCESS_FETCH) begin
                                if (!pte[3] ||
                                    ((eff_priv == 2'b01) && pte[4]) ||
                                    ((eff_priv == 2'b00) && !pte[4]) ||
                                    !pte[6]) begin
                                    fault = 1'b1;
                                    cause = 64'd12;
                                    tval = vaddr;
                                    done = 1'b1;
                                end
                            end else if (access_type == ACCESS_LOAD) begin
                                if (!(pte[1] || (dut.u_csr.mstatus_mxr && pte[3])) ||
                                    ((eff_priv == 2'b01) && pte[4] && !dut.u_csr.mstatus_sum) ||
                                    ((eff_priv == 2'b00) && !pte[4]) ||
                                    !pte[6]) begin
                                    fault = 1'b1;
                                    cause = 64'd13;
                                    tval = vaddr;
                                    done = 1'b1;
                                end
                            end else begin
                                if (!pte[2] ||
                                    ((eff_priv == 2'b01) && pte[4] && !dut.u_csr.mstatus_sum) ||
                                    ((eff_priv == 2'b00) && !pte[4]) ||
                                    !pte[6] || !pte[7]) begin
                                    fault = 1'b1;
                                    cause = 64'd15;
                                    tval = vaddr;
                                    done = 1'b1;
                                end
                            end

                            if (!done) begin
                                case (level)
                                    2: page_mask = 64'h0000_0000_3fff_ffff;
                                    1: page_mask = 64'h0000_0000_001f_ffff;
                                    default: page_mask = 64'h0000_0000_0000_0fff;
                                endcase
                                page_base = {8'h00, pte_ppn, 12'h000};
                                paddr = (page_base & ~page_mask) | (vaddr & page_mask);
                                pmp_check(paddr, access_size, access_type, eff_priv, vaddr,
                                          pmp_fault, pmp_cause, pmp_tval);
                                if (pmp_fault) begin
                                    fault = 1'b1;
                                    cause = pmp_cause;
                                    tval = pmp_tval;
                                end
                                done = 1'b1;
                            end
                        end
                    end
                end
            end
        end
    endtask

    always @(*) begin
        itlb_fill = 1'b0;
        itlb_fill_satp = dut.u_csr.satp;
        itlb_fill_vpn = imem_addr[38:12];
        itlb_fill_priv = dut.u_csr.current_priv;
        itlb_fill_sum = dut.u_csr.mstatus_sum;
        itlb_fill_phys_page = 64'h0;
        itlb_fill_fault = 1'b0;
        itlb_fill_fault_cause = 64'h0;
        itlb_fill_fault_tval = 64'h0;
        if (itlb_valid &&
            (itlb_satp == dut.u_csr.satp) &&
            (itlb_vpn == imem_addr[38:12]) &&
            (itlb_priv == dut.u_csr.current_priv) &&
            (itlb_sum == dut.u_csr.mstatus_sum)) begin
            imem_addr_phys = itlb_phys_page | {52'h0, imem_addr[11:0]};
            imem_fault_r = itlb_fault;
            imem_fault_cause_r = itlb_fault_cause;
            imem_fault_tval_r = itlb_fault_tval;
            if (!imem_fault_r) begin
                pmp_check(imem_addr_phys, 4'd4, ACCESS_FETCH, dut.u_csr.current_priv, imem_addr,
                          imem_fault_r, imem_fault_cause_r, imem_fault_tval_r);
            end
        end else begin
            translate_addr(imem_addr, ACCESS_FETCH, 4'd4, imem_addr_phys,
                           imem_fault_r, imem_fault_cause_r, imem_fault_tval_r);
            if (!imem_fault_r || (imem_fault_cause_r == 64'd12)) begin
                itlb_fill = 1'b1;
                itlb_fill_phys_page = imem_addr_phys & ~64'hfff;
                itlb_fill_fault = imem_fault_r;
                itlb_fill_fault_cause = imem_fault_cause_r;
                itlb_fill_fault_tval = imem_fault_tval_r;
            end
        end
    end

    always @(*) begin
        dtlb_fill = 1'b0;
        if ((dut.ex_mem_mem_read || dut.ex_mem_atomic_en) || dmem_we) begin
            translate_addr(
                dmem_addr,
                (dmem_we || dut.ex_mem_mem_write || dut.ex_mem_atomic_en) ? ACCESS_STORE : ACCESS_LOAD,
                (dut.ex_mem_atomic_en || (dmem_funct3 == 3'b011)) ? 4'd8 :
                (((dmem_funct3 == 3'b001) || (dmem_funct3 == 3'b101)) ? 4'd2 :
                 (((dmem_funct3 == 3'b000) || (dmem_funct3 == 3'b100)) ? 4'd1 : 4'd4)),
                dmem_addr_phys,
                dmem_page_fault_r,
                dmem_page_fault_cause_r,
                dmem_page_fault_tval_r
            );
        end else begin
            dmem_addr_phys = dmem_addr;
            dmem_page_fault_r = 1'b0;
            dmem_page_fault_cause_r = 64'h0;
            dmem_page_fault_tval_r = 64'h0;
        end
    end

    always @(dmem_addr_phys or mem[dmem_qidx] or mem[dmem_qidx + 15'd1]) begin
        dmem_rdata_raw = {
            mem_read_byte(dmem_addr_phys + 64'd7),
            mem_read_byte(dmem_addr_phys + 64'd6),
            mem_read_byte(dmem_addr_phys + 64'd5),
            mem_read_byte(dmem_addr_phys + 64'd4),
            mem_read_byte(dmem_addr_phys + 64'd3),
            mem_read_byte(dmem_addr_phys + 64'd2),
            mem_read_byte(dmem_addr_phys + 64'd1),
            mem_read_byte(dmem_addr_phys)
        };
    end

    integer fault_kind;
    integer fault_reg_idx;
    integer fault_cycle;
    reg [63:0] fault_addr;
    reg [63:0] fault_mask;
    reg has_fault_addr;
    reg fault_fired;
    reg fault_reported;
    integer irq_kind;
    integer irq_cycle;
    reg irq_pending;
    reg [63:0] irq_pc;
    reg has_irq_pc;
    reg imem_parity_seen;
    reg dmem_parity_seen;
    integer store_byte_idx;
    reg [3:0] store_byte_count;
    reg [14:0] store_row0_idx;
    reg [14:0] store_row1_idx;
    reg [63:0] store_row0_next;
    reg [63:0] store_row1_next;
    reg [63:0] store_byte_addr;
    reg [7:0]  store_byte_value;
    reg        store_row1_dirty;
    wire dmem_fault_eligible = dut.ex_mem_mem_read || dut.ex_mem_atomic_en;
    wire fault_imem_match = has_fault_addr ? (imem_addr == fault_addr) : 1'b1;
    wire fault_dmem_match = has_fault_addr ? (dmem_addr_phys == fault_addr) : 1'b1;
    wire fault_imem_fire = rst_n && (fault_kind == 1) && !fault_fired && fault_imem_match;
    wire fault_dmem_fire = rst_n && (fault_kind == 2) && !fault_fired &&
                           dmem_fault_eligible && !dmem_we && fault_dmem_match;
    wire fault_rf_fire = rst_n && (fault_kind == 3) && !fault_fired && (cycle_count == fault_cycle);
    wire dmem_crosses_row = ((dmem_addr_phys[2:0] + ((dmem_funct3 == 3'h3) ? 4'd8 :
                                                 (dmem_funct3 == 3'h2) ? 4'd4 :
                                                 (dmem_funct3 == 3'h1) ? 4'd2 : 4'd1)) > 4'd8);
    wire imem_parity_mismatch = rst_n && ((^mem[imem_qidx]) != mem_parity[imem_qidx]);
    wire dmem_row0_parity_mismatch = dmem_fault_eligible && ((^mem[dmem_qidx]) != mem_parity[dmem_qidx]);
    wire dmem_row1_parity_mismatch = dmem_fault_eligible && dmem_crosses_row &&
                                     ((^mem[dmem_qidx + 15'd1]) != mem_parity[dmem_qidx + 15'd1]);
    wire dmem_parity_mismatch = rst_n && !dmem_we && !dmem_page_fault &&
                                (dmem_row0_parity_mismatch || dmem_row1_parity_mismatch);
    wire imem_parity_event = imem_parity_mismatch && !imem_parity_seen;
    wire dmem_parity_event = dmem_parity_mismatch && !dmem_parity_seen;

    assign imem_data = fault_imem_fire ? (imem_data_raw ^ fault_mask[31:0]) : imem_data_raw;
    assign dmem_rdata = fault_dmem_fire ? (dmem_rdata_raw ^ fault_mask) : dmem_rdata_raw;
    assign ares_fault_event = fault_imem_fire || fault_dmem_fire || imem_parity_event || dmem_parity_event;
    assign ares_fault_code = fault_imem_fire ? 4'd1 :
                             fault_dmem_fire ? 4'd2 :
                             imem_parity_event ? 4'd4 :
                             dmem_parity_event ? 4'd5 : 4'd0;
    assign ares_fault_info = fault_imem_fire ? imem_addr :
                             fault_dmem_fire ? dmem_addr :
                             imem_parity_event ? imem_addr :
                             dmem_parity_event ? dmem_addr : 64'h0;
    assign irq_msip = irq_pending && (irq_kind == 1);
    assign irq_mtip = irq_pending && (irq_kind == 2);
    assign irq_meip = irq_pending && (irq_kind == 3);

    function [63:0] merge_store_byte;
        input [63:0] old_row;
        input [2:0]  byte_lane;
        input [7:0]  value;
        reg [5:0] bit_idx;
        begin
            bit_idx = {byte_lane, 3'b000};
            merge_store_byte = (old_row & ~(64'hff << bit_idx)) |
                               ({56'h0, value} << bit_idx);
        end
    endfunction

    always @(posedge clk) begin
        if (dmem_we && !dmem_page_fault) begin
            store_row0_idx = dmem_qidx;
            store_row1_idx = dmem_qidx + 15'd1;
            store_row0_next = mem[store_row0_idx];
            store_row1_next = mem[store_row1_idx];
            store_row1_dirty = 1'b0;
            case (dmem_funct3)
                3'h0: store_byte_count = 4'd1;
                3'h1: store_byte_count = 4'd2;
                3'h2: store_byte_count = 4'd4;
                3'h3: store_byte_count = 4'd8;
                default: store_byte_count = 4'd0;
            endcase
            for (store_byte_idx = 0; store_byte_idx < 8; store_byte_idx = store_byte_idx + 1) begin
                if (store_byte_idx < store_byte_count) begin
                    store_byte_addr = dmem_addr_phys + {61'h0, store_byte_idx[2:0]};
                    store_byte_value = dmem_wdata[store_byte_idx*8 +: 8];
                    if (mem_row_index(store_byte_addr) == store_row0_idx)
                        store_row0_next = merge_store_byte(
                            store_row0_next,
                            store_byte_addr[2:0],
                            store_byte_value
                        );
                    else begin
                        store_row1_next = merge_store_byte(
                            store_row1_next,
                            store_byte_addr[2:0],
                            store_byte_value
                        );
                        store_row1_dirty = 1'b1;
                    end
                end
            end
            mem[store_row0_idx] <= store_row0_next;
            mem_parity[store_row0_idx] <= ^store_row0_next;
            if (store_row1_dirty) begin
                mem[store_row1_idx] <= store_row1_next;
                mem_parity[store_row1_idx] <= ^store_row1_next;
            end
        end
    end

    ares_core dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .imem_addr  (imem_addr),
        .imem_data  (imem_data),
        .imem_page_fault(imem_fault_r),
        .imem_page_fault_cause(imem_fault_cause_r),
        .imem_page_fault_tval(imem_fault_tval_r),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_we    (dmem_we),
        .dmem_funct3(dmem_funct3),
        .dmem_rdata (dmem_rdata),
        .dmem_page_fault(dmem_page_fault),
        .dmem_page_fault_cause(dmem_page_fault_cause),
        .dmem_page_fault_tval(dmem_page_fault_tval),
        .ares_fault_event(ares_fault_event),
        .ares_fault_code (ares_fault_code),
        .ares_fault_info (ares_fault_info),
        .rf_parity_fault_inject_en(fault_rf_fire && (fault_reg_idx > 0) && (fault_reg_idx < 32)),
        .rf_parity_fault_idx(fault_reg_idx[4:0]),
        .irq_msip    (irq_msip),
        .irq_mtip    (irq_mtip),
        .irq_meip    (irq_meip)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Initialize memory arrays to zero.
    initial begin
        for (j = 0; j < 65536; j = j + 1)
            mem_words[j] = 32'h0;
        for (j = 0; j < 32768; j = j + 1) begin
            mem[j] = 64'h0;
            mem_parity[j] = 1'b0;
        end
        itlb_valid = 1'b0;
        dtlb_valid = 1'b0;
    end

    reg [31:0] test_status;
    integer tohost_idx;
    reg has_tohost_idx;
    reg [31:0] tohost_word;
    reg trace_en;
    reg state_dump_en;

    task dump_arch_state;
        integer reg_idx;
        begin
            $display("STATE kind=rtl");
            for (reg_idx = 0; reg_idx < 32; reg_idx = reg_idx + 1)
                $display("STATE reg x%0d=%h", reg_idx, dut.u_id.regfile[reg_idx]);
            $display("STATE csr mstatus=%h", dut.u_csr.mstatus_rd);
            $display("STATE csr mtvec=%h", dut.u_csr.mtvec);
            $display("STATE csr mscratch=%h", dut.u_csr.mscratch);
            $display("STATE csr mepc=%h", dut.u_csr.mepc);
            $display("STATE csr mcause=%h", dut.u_csr.mcause);
            $display("STATE csr mtval=%h", dut.u_csr.mtval);
            $display("STATE csr mie=%h", dut.u_csr.mie_reg);
            $display("STATE csr mip=%h", dut.u_csr.mip_rd);
            $display("STATE csr medeleg=%h", dut.u_csr.medeleg);
            $display("STATE csr mideleg=%h", dut.u_csr.mideleg);
            $display("STATE csr sstatus=%h", dut.u_csr.sstatus_rd);
            $display("STATE csr stvec=%h", dut.u_csr.stvec);
            $display("STATE csr sscratch=%h", dut.u_csr.sscratch);
            $display("STATE csr sepc=%h", dut.u_csr.sepc);
            $display("STATE csr scause=%h", dut.u_csr.scause);
            $display("STATE csr stval=%h", dut.u_csr.stval);
            $display("STATE csr sie=%h", dut.u_csr.sie_rd);
            $display("STATE csr sip=%h", dut.u_csr.sip_rd);
            $display("STATE csr pmpcfg0=%h", dut.u_csr.pmpcfg0);
            $display("STATE csr pmpaddr0=%h", dut.u_csr.pmpaddr0);
            $display("STATE csr ares_status=%h", dut.u_csr.ares_status);
            $display("STATE csr ares_fault_count=%h", dut.u_csr.ares_fault_count);
            $display("STATE csr ares_fault_info=%h", dut.u_csr.ares_fault_info_reg);
            $display("STATE csr priv=%h", {62'h0, dut.u_csr.current_priv});
            $display("STATE tohost=%h", {32'h0, tohost_word});
            $display("STATE cycle=%h", cycle_count);
            $display("STATE end");
        end
    endtask

    // ECALL signal from EX stage - 2 cycle delay for WB to commit
    reg ecall_seen_d1, ecall_seen_d2;
    wire tlb_invalidate = dut.csr_en && (dut.csr_addr == 12'h180) ||
                          ((dut.id_ex_opcode == 7'h73) && (dut.id_ex_funct3 == 3'h0) &&
                           (dut.id_ex_imm[11:0] == 12'h120));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ecall_seen_d1 <= 1'b0;
            ecall_seen_d2 <= 1'b0;
            test_status   <= 32'h0;
            fault_fired      <= 1'b0;
            irq_pending      <= 1'b0;
            imem_parity_seen <= 1'b0;
            dmem_parity_seen <= 1'b0;
            itlb_valid       <= 1'b0;
            dtlb_valid       <= 1'b0;
        end else begin
            ecall_seen_d1 <= dut.ecall_en;
            ecall_seen_d2 <= ecall_seen_d1;
            if (tlb_invalidate) begin
                itlb_valid <= 1'b0;
                dtlb_valid <= 1'b0;
            end else begin
                if (itlb_fill) begin
                    itlb_valid <= 1'b1;
                    itlb_satp <= itlb_fill_satp;
                    itlb_vpn <= itlb_fill_vpn;
                    itlb_priv <= itlb_fill_priv;
                    itlb_sum <= itlb_fill_sum;
                    itlb_phys_page <= itlb_fill_phys_page;
                    itlb_fault <= itlb_fill_fault;
                    itlb_fault_cause <= itlb_fill_fault_cause;
                    itlb_fault_tval <= itlb_fill_fault_tval;
                end
                if (dtlb_fill) begin
                    dtlb_valid <= 1'b1;
                    dtlb_satp <= dtlb_fill_satp;
                    dtlb_vpn <= dtlb_fill_vpn;
                    dtlb_priv <= dtlb_fill_priv;
                    dtlb_sum <= dtlb_fill_sum;
                    dtlb_access <= dtlb_fill_access;
                    dtlb_phys_page <= dtlb_fill_phys_page;
                    dtlb_fault <= dtlb_fill_fault;
                    dtlb_fault_cause <= dtlb_fill_fault_cause;
                    dtlb_fault_tval <= dtlb_fill_fault_tval;
                end
            end
            if (!irq_pending && (irq_kind != 0) &&
                ((has_irq_pc && (imem_addr == irq_pc)) ||
                 (!has_irq_pc && (cycle_count == irq_cycle))))
                irq_pending <= 1'b1;
            if (fault_imem_fire || fault_dmem_fire || fault_rf_fire) begin
                fault_fired      <= 1'b1;
            end
            if (imem_parity_event)
                imem_parity_seen <= 1'b1;
            if (dmem_parity_event)
                dmem_parity_seen <= 1'b1;
            if (ecall_seen_d2 && dut.u_id.regfile[17] == 64'd93) begin
                if (dut.u_id.regfile[10] == 64'h0)
                    test_status <= 32'h1;
                else
                    test_status <= dut.u_id.regfile[10][31:0];
            end
        end
    end

    initial begin
        has_tohost_idx = $value$plusargs("tohost_idx=%d", tohost_idx);
        trace_en = $test$plusargs("trace");
        state_dump_en = $test$plusargs("state_dump");
        if (!$value$plusargs("fault_kind=%d", fault_kind))
            fault_kind = 0;
        if (!$value$plusargs("fault_reg=%d", fault_reg_idx))
            fault_reg_idx = 1;
        if (!$value$plusargs("fault_cycle=%d", fault_cycle))
            fault_cycle = 20;
        if (!$value$plusargs("irq_kind=%d", irq_kind))
            irq_kind = 0;
        if (!$value$plusargs("irq_cycle=%d", irq_cycle))
            irq_cycle = 20;
        has_irq_pc = $value$plusargs("irq_pc=%h", irq_pc);
        has_fault_addr = $value$plusargs("fault_addr=%h", fault_addr);
        if (!$value$plusargs("fault_mask=%h", fault_mask))
            fault_mask = 64'h1;
        fault_reported = 1'b0;
        $readmemh("program.hex", mem_words);
        for (i = 0; i < 32768; i = i + 1) begin
            mem[i] = {mem_words[i*2 + 1], mem_words[i*2]};
            mem_parity[i] = ^{mem_words[i*2 + 1], mem_words[i*2]};
        end
        if ((fault_kind == 4 || fault_kind == 5) && has_fault_addr)
            mem_parity[mem_row_index(fault_addr)] = ~mem_parity[mem_row_index(fault_addr)];
        rst_n = 0;
        cycle_count = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;

        repeat(500000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (trace_en && cycle_count <= 400) begin
                $display(
                    "TRACE c=%0d pc=%h if=%h id_pc=%h ex_pc=%h trap=%b cause=%0d mret=%b irq=%b mtvec=%h mepc=%h mcause=%h ares=%h gp=%h a1=%h a2=%h a4=%h",
                    cycle_count,
                    dut.u_if.pc,
                    dut.if_id_instr,
                    dut.if_id_pc,
                    dut.id_ex_pc,
                    dut.trap_en,
                    dut.trap_cause,
                    dut.mret_en,
                    irq_pending,
                    dut.tvec_base,
                    dut.mret_pc,
                    dut.u_csr.mcause,
                    dut.u_csr.ares_status,
                    dut.u_id.regfile[3],
                    dut.u_id.regfile[11],
                    dut.u_id.regfile[12],
                    dut.u_id.regfile[14]
                );
            end
            if (!fault_reported && dut.u_csr.ares_fault_count != 0) begin
                $display(
                    "ARES_FAULT code=%0d info=%h status=%h count=%0d",
                    dut.u_csr.ares_last_fault_code,
                    dut.u_csr.ares_fault_info_reg,
                    dut.u_csr.ares_status,
                    dut.u_csr.ares_fault_count
                );
                fault_reported = 1'b1;
            end
            if (has_tohost_idx)
                tohost_word = mem_read_word(MEM_BASE + {30'h0, tohost_idx[31:0], 2'b00});
            else
                tohost_word = 32'h0;
            if (has_tohost_idx && tohost_word != 0) begin
                if (state_dump_en)
                    dump_arch_state();
                if (tohost_word == 1)
                    $display("PASS after %0d cycles", cycle_count);
                else
                    $display("FAIL [tohost=%0d] after %0d cycles", tohost_word >> 1, cycle_count);
                $finish;
            end
            // ECALL completion works even when .tohost moves because .text.init grows.
            if (!has_tohost_idx && test_status != 0) begin
                if (state_dump_en)
                    dump_arch_state();
                if (test_status == 1)
                    $display("PASS after %0d cycles", cycle_count);
                else
                    $display("FAIL [tohost=%0d] after %0d cycles", test_status >> 1, cycle_count);
                $finish;
            end
            // ECALL detection: one cycle after ECALL in EX stage
            // regfile reflects committed values by then
            // Guard: skip early ECALLs in reset_vector (before cycle 200)
            if (!has_tohost_idx && ecall_seen_d2 && cycle_count > 200 && dut.u_id.regfile[17] == 64'd93) begin
                if (state_dump_en)
                    dump_arch_state();
                if (dut.u_id.regfile[10] == 64'h0)
                    $display("PASS after %0d cycles", cycle_count);
                else
                    $display("FAIL [gp=%0d] after %0d cycles",
                        dut.u_id.regfile[3] >> 1, cycle_count);
                $finish;
            end
        end
        if (state_dump_en)
            dump_arch_state();
        $display("TIMEOUT after %0d cycles", cycle_count);
        $finish;
    end

    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("ares.vcd");
            $dumpvars(0, tb_ares);
        end
    end

endmodule
