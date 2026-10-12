/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */


`timescale 1ns/1ps
import lynxTypes::*;

`include "axi_macros.svh"

/**
 * @brief   NVMe CQ controller
 *
 * Single AXI port for all devices; CQE BRAM indexed by {dev_id, CQ ring slot}. The FSM
 * round-robins across devices, polling each device's CQ head for completions.
 */
module nvme_cq_ctrl #(
    parameter int unsigned CQ_ADDR_BITS = 6,
    parameter int unsigned N_NVME_BITS  = lynxTypes::N_NVME_BITS,
    parameter int unsigned READ_LATENCY = 2,
    parameter int unsigned NUM_DEVICES = NVME_NUM_DEVICES
)(
    input  logic        aclk,
    input  logic        aresetn,

    input logic queue_reset,
    input logic [N_NVME_BITS-1:0] queue_reset_dev,
    output logic [15:0] m_sq_head,
    output logic m_cid_in_range,
    metaIntf.m          m_cqe,       // existing nvme_cqe_t
    AXI4.s              s_axi_nvme_cq
);

    localparam int unsigned CQ_DEPTH     = (1 << CQ_ADDR_BITS);
    localparam int unsigned N_NVME       = NUM_DEVICES;
    localparam int unsigned CQ_TOTAL_BITS = CQ_ADDR_BITS + N_NVME_BITS;
    // The AXI controller exposes a fixed 4-KiB aperture per device.
    localparam int unsigned CQ_BYTE_BITS = N_NVME_BITS + 12;

    // AXI BRAM Controller (128-bit, 1 beat = 1 CQE)
    logic               bram_en_a;
    logic               bram_clk_a;
    logic               bram_rst_a;
    logic [127:0]       bram_wrdata_a;
    logic [15:0]        bram_we_a;
    logic [CQ_BYTE_BITS-1:0] bram_addr_a;
    logic [127:0]       bram_rddata_a;

    logic [63:0]                  cq_bram_awaddr;
    logic [1:0]                   cq_bram_awburst;
    logic [3:0]                   cq_bram_awcache;
    logic [AXI_ID_BITS-1:0]       cq_bram_awid;
    logic [7:0]                   cq_bram_awlen;
    logic [0:0]                   cq_bram_awlock;
    logic [2:0]                   cq_bram_awprot;
    logic [3:0]                   cq_bram_awqos;
    logic [3:0]                   cq_bram_awregion;
    logic [2:0]                   cq_bram_awsize;
    logic                         cq_bram_awvalid;
    logic                         cq_bram_awready;

    logic [AXI_DATA_BITS-1:0]     cq_bram_wdata;
    logic [AXI_DATA_BITS/8-1:0]   cq_bram_wstrb;
    logic                         cq_bram_wlast;
    logic                         cq_bram_wvalid;
    logic                         cq_bram_wready;

    logic [1:0]                   cq_bram_bresp;
    logic                         cq_bram_bvalid;
    logic                         cq_bram_bready;
    logic [AXI_ID_BITS-1:0]       cq_bram_bid;

    logic [63:0]                  cq_bram_araddr;
    logic [1:0]                   cq_bram_arburst;
    logic [3:0]                   cq_bram_arcache;
    logic [AXI_ID_BITS-1:0]       cq_bram_arid;
    logic [7:0]                   cq_bram_arlen;
    logic [0:0]                   cq_bram_arlock;
    logic [2:0]                   cq_bram_arprot;
    logic [3:0]                   cq_bram_arqos;
    logic [3:0]                   cq_bram_arregion;
    logic [2:0]                   cq_bram_arsize;
    logic                         cq_bram_arvalid;
    logic                         cq_bram_arready;

    logic [AXI_DATA_BITS-1:0]     cq_bram_rdata;
    logic [1:0]                   cq_bram_rresp;
    logic                         cq_bram_rlast;
    logic                         cq_bram_rvalid;
    logic                         cq_bram_rready;
    logic [AXI_ID_BITS-1:0]       cq_bram_rid;

    `AXI_ASSIGN_I2S(s_axi_nvme_cq, cq_bram)

    nvme_cq_axi_bram_ctrl inst_nvme_cq_bram_ctrl (
        .s_axi_aclk       (aclk),
        .s_axi_aresetn    (aresetn),

        .s_axi_awaddr     (cq_bram_awaddr[CQ_BYTE_BITS-1:0]),
        .s_axi_awlen      (cq_bram_awlen),
        .s_axi_awsize     (cq_bram_awsize),
        .s_axi_awburst    (cq_bram_awburst),
        .s_axi_awlock     (cq_bram_awlock),
        .s_axi_awcache    (cq_bram_awcache),
        .s_axi_awprot     (cq_bram_awprot),
        .s_axi_awvalid    (cq_bram_awvalid),
        .s_axi_awready    (cq_bram_awready),

        .s_axi_wdata      (cq_bram_wdata[127:0]),
        .s_axi_wstrb      (cq_bram_wstrb[15:0]),
        .s_axi_wlast      (cq_bram_wlast),
        .s_axi_wvalid     (cq_bram_wvalid),
        .s_axi_wready     (cq_bram_wready),

        .s_axi_bresp      (cq_bram_bresp),
        .s_axi_bvalid     (cq_bram_bvalid),
        .s_axi_bready     (cq_bram_bready),

        .s_axi_araddr     (cq_bram_araddr[CQ_BYTE_BITS-1:0]),
        .s_axi_arlen      (cq_bram_arlen),
        .s_axi_arsize     (cq_bram_arsize),
        .s_axi_arburst    (cq_bram_arburst),
        .s_axi_arlock     (cq_bram_arlock),
        .s_axi_arcache    (cq_bram_arcache),
        .s_axi_arprot     (cq_bram_arprot),
        .s_axi_arvalid    (cq_bram_arvalid),
        .s_axi_arready    (cq_bram_arready),

        .s_axi_rdata      (cq_bram_rdata[127:0]),
        .s_axi_rresp      (cq_bram_rresp),
        .s_axi_rlast      (cq_bram_rlast),
        .s_axi_rvalid     (cq_bram_rvalid),
        .s_axi_rready     (cq_bram_rready),

        .bram_addr_a      (bram_addr_a),
        .bram_clk_a       (bram_clk_a),
        .bram_wrdata_a    (bram_wrdata_a),
        .bram_rddata_a    (bram_rddata_a),
        .bram_en_a        (bram_en_a),
        .bram_rst_a       (bram_rst_a),
        .bram_we_a        (bram_we_a)
    );

    // Store DW2 (SQHD/SQID) and DW3 (CID/phase/status) at the actual
    // CQ-ring address. Byte masks assemble CQEs split across AXI writes.
    logic cqe_wr_detect;
    logic [31:0] dw3;
    logic [N_NVME_BITS-1:0] wr_dev_id;
    logic [CQ_ADDR_BITS-1:0] wr_slot;
    logic [15:0] wr_cid;
    logic a_en;
    logic [7:0] a_we;
    logic [CQ_TOTAL_BITS-1:0] a_addr, b_addr;
    logic [63:0] a_data_in, a_data_out, b_data_out;
    logic [7:0] cqe_written [N_NVME][CQ_DEPTH];
    logic [CQ_DEPTH-1:0] cqe_valid_bits [N_NVME];

    assign wr_dev_id = bram_addr_a[N_NVME_BITS+11:12];
    assign wr_slot = bram_addr_a[4 +: CQ_ADDR_BITS];
    assign dw3 = bram_wrdata_a[127:96];
    assign wr_cid = dw3[15:0];
    assign cqe_wr_detect = bram_en_a && (|bram_we_a[15:8]);
    assign a_en = cqe_wr_detect && wr_dev_id < N_NVME && !(queue_reset && queue_reset_dev == wr_dev_id);
    assign a_we = bram_we_a[15:8];
    assign a_addr = {wr_dev_id, wr_slot};
    assign a_data_in = bram_wrdata_a[127:64];

    ram_tp_c #(.ADDR_BITS(CQ_TOTAL_BITS), .DATA_BITS(64)) inst_cq_table (
        .clk(aclk), .a_en(a_en), .a_we(a_we), .a_addr(a_addr),
        .a_data_in(a_data_in), .a_data_out(a_data_out),
        .b_en(1'b1), .b_addr(b_addr), .b_data_out(b_data_out)
    );

    // Preserve the historical last-CQE AXI debug readback layout. Full CID
    // and SQHD are available in the expanded ILA probes below.
    logic [63:0] last_cqe_data_r;
    logic [31:0] last_cqe_word;
    always_ff @(posedge aclk) begin
        if (!aresetn)
            last_cqe_data_r <= '0;
        else if (a_en)
            for (int b = 0; b < 8; b++)
                if (a_we[b]) last_cqe_data_r[b*8 +: 8] <= a_data_in[b*8 +: 8];
    end
    assign last_cqe_word = {{(16-CQ_ADDR_BITS){1'b0}},
                           last_cqe_data_r[32 +: CQ_ADDR_BITS], last_cqe_data_r[63:48]};
    assign bram_rddata_a = {4{last_cqe_word}};

    for (genvar d = 0; d < N_NVME; d++) begin : gen_valid
        for (genvar c = 0; c < CQ_DEPTH; c++) begin : gen_slot
            assign cqe_valid_bits[d][c] = &cqe_written[d][c];
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert (NUM_DEVICES >= 1 && NUM_DEVICES <= (1 << N_NVME_BITS));
        assert (READ_LATENCY >= 2) else $fatal(1, "CQ ram_tp_c has two read registers");
        assert (CQ_ADDR_BITS <= 8) else $fatal(1, "CQ must fit the per-device 4 KiB aperture");
    end
`endif

    // Reader FSM types and registers (declared before use)
    typedef enum logic [2:0] {
        ST_NEXT_DEV = 3'd0,
        ST_RD_REQ   = 3'd1,
        ST_RD_WAIT  = 3'd2,
        ST_CHECK    = 3'd3,
        ST_OUT      = 3'd4
    } cq_state_e;

    cq_state_e                state_r, state_n;
    logic [N_NVME_BITS-1:0]   poll_dev_r, poll_dev_n;    // current device being polled
    logic [63:0]              cqe_word_r, cqe_word_n;

    // Per-device state
    logic [CQ_ADDR_BITS-1:0] cq_head_r    [N_NVME];
    logic                    exp_phase_r  [N_NVME];

    // RAM contents need no reset; a slot is eligible only after its required
    // bytes have been written since reset/previous consumption.
    // Constant slot indices keep each byte-mask feedback path local instead
    // of reading the whole bitmap through a device/slot mux before updating.
    for (genvar d = 0; d < N_NVME; d++) begin : gen_written_dev
        for (genvar c = 0; c < CQ_DEPTH; c++) begin : gen_written_slot
            always_ff @(posedge aclk) begin
                if (!aresetn || (queue_reset && queue_reset_dev == N_NVME_BITS'(d)))
                    cqe_written[d][c] <= '0;
                else if (a_en && wr_dev_id == N_NVME_BITS'(d) && wr_slot == CQ_ADDR_BITS'(c))
                    cqe_written[d][c] <= cqe_written[d][c] | a_we;
                else if (m_cqe.valid && m_cqe.ready && poll_dev_r == N_NVME_BITS'(d) &&
                         cq_head_r[d] == CQ_ADDR_BITS'(c))
                    cqe_written[d][c] <= '0;
            end
        end
    end

    // Reader FSM: Round-robin across devices, poll cq_head

    localparam int unsigned CNT_W = (READ_LATENCY <= 1) ? 1 : $clog2(READ_LATENCY);
    logic [CNT_W-1:0]         wait_cnt_r, wait_cnt_n;

    // BRAM read address = {poll_dev, cq_head[poll_dev]}
    assign b_addr = {poll_dev_r, cq_head_r[poll_dev_r]};

    // Output
    always_comb begin
        m_cqe.valid        = (state_r == ST_OUT) &&
                             !(queue_reset && queue_reset_dev == poll_dev_r);
        m_cqe.data         = '0;
        m_cqe.data.dev_id  = poll_dev_r;
        m_cqe.data.cid     = NVME_RSP_CID_BITS'(cqe_word_r[32 +: CQ_ADDR_BITS]);  // zero-extended to 8 bits
        m_cqe.data.status  = cqe_word_r[63:49];
        m_cqe.data.phase   = cqe_word_r[48];
    end

    assign m_sq_head = cqe_word_r[15:0];
    // Do not truncate a malformed full CID into a different, live command.
    assign m_cid_in_range = (cqe_word_r[47:32] < CQ_DEPTH);

    // Sequential
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state_r     <= ST_NEXT_DEV;
            poll_dev_r  <= '0;
            cqe_word_r  <= '0;
            wait_cnt_r  <= '0;
            for (int d = 0; d < N_NVME; d++) begin
                cq_head_r[d]   <= '0;
                exp_phase_r[d] <= 1'b1;
            end
        end else begin
            state_r     <= state_n;
            poll_dev_r  <= poll_dev_n;
            cqe_word_r  <= cqe_word_n;
            wait_cnt_r  <= wait_cnt_n;

            if (queue_reset && queue_reset_dev < N_NVME) begin
                cq_head_r[queue_reset_dev] <= '0;
                exp_phase_r[queue_reset_dev] <= 1'b1;
                if (queue_reset_dev == poll_dev_r) state_r <= ST_NEXT_DEV;
            end

            // Advance physical CQ head on successful output
            if (state_r == ST_OUT && m_cqe.valid && m_cqe.ready) begin
                if (cq_head_r[poll_dev_r] == (CQ_DEPTH-1)) begin
                    cq_head_r[poll_dev_r]   <= '0;
                    exp_phase_r[poll_dev_r] <= ~exp_phase_r[poll_dev_r];
                end else begin
                    cq_head_r[poll_dev_r] <= cq_head_r[poll_dev_r] + 1'b1;
                end
            end
        end
    end

    // Next-state logic
    always_comb begin
        state_n     = state_r;
        poll_dev_n  = poll_dev_r;
        cqe_word_n  = cqe_word_r;
        wait_cnt_n  = wait_cnt_r;

        case (state_r)

            ST_NEXT_DEV: begin
                // Round-robin: try next device
                poll_dev_n = (poll_dev_r == N_NVME_BITS'(N_NVME-1)) ? '0 : poll_dev_r + 1'b1;
                state_n    = ST_RD_REQ;
            end

            ST_RD_REQ: begin
                // Check valid bit for current device's cq_head
                if (cqe_valid_bits[poll_dev_r][cq_head_r[poll_dev_r]]) begin
                    wait_cnt_n = '0;
                    state_n    = (READ_LATENCY == 0) ? ST_CHECK : ST_RD_WAIT;
                end else begin
                    // Nothing ready on this device, try next
                    state_n = ST_NEXT_DEV;
                end
            end

            ST_RD_WAIT: begin
                if (READ_LATENCY <= 1) begin
                    state_n = ST_CHECK;
                end else if (wait_cnt_r == (READ_LATENCY-2)) begin
                    state_n = ST_CHECK;
                end else begin
                    wait_cnt_n = wait_cnt_r + 1'b1;
                end
            end

            ST_CHECK: begin
                cqe_word_n = b_data_out;
                state_n = (b_data_out[48] == exp_phase_r[poll_dev_r]) ? ST_OUT : ST_NEXT_DEV;
            end

            ST_OUT: begin
                if (m_cqe.ready) begin
                    state_n = ST_NEXT_DEV;
                end
            end

            default: state_n = ST_NEXT_DEV;

        endcase
    end

    // ILA Debug
// `define EN_ILA_NVME_CQ_CTRL
`ifdef EN_ILA_NVME_CQ_CTRL
    // Wire for probing current device's cq_head
    logic [CQ_ADDR_BITS-1:0] dbg_cq_head_cur;
    assign dbg_cq_head_cur = cq_head_r[poll_dev_r];

    // Wire for probing current device's valid bits (first 8 bits)
    logic [7:0] dbg_cqe_valid_bits_cur;
    assign dbg_cqe_valid_bits_cur = cqe_valid_bits[poll_dev_r][7:0];

    ila_nvme_cq_ctrl inst_ila_nvme_cq_ctrl (
        .clk    (aclk),
        .probe0 (cqe_wr_detect),                        // 1
        .probe1 (wr_dev_id),                            // N_NVME_BITS (4)
        .probe2 (wr_cid),                               // full SSD CID (16)
        .probe3 (m_cqe.valid),                          // 1
        .probe4 (m_cqe.ready),                          // 1
        .probe5 (m_cqe.data.dev_id),                    // N_NVME_BITS (4)
        .probe6 (m_cqe.data.status),                    // 15
        .probe7 (m_cqe.data.phase),                     // 1
        .probe8 (state_r),                              // 3
        .probe9 (poll_dev_r),                           // N_NVME_BITS (4)
        .probe10(dbg_cq_head_cur),                      // CQ_ADDR_BITS (6)
        .probe11(dbg_cqe_valid_bits_cur),               // 8
        .probe12(b_data_out),                           // DW3:DW2 (64)
        .probe13(cqe_word_r),                           // DW3:DW2 (64)
        .probe14(wr_slot),                              // physical CQ slot (6)
        .probe15(cqe_word_r[47:32]),                    // retired full CID (16)
        .probe16(m_sq_head),                            // SQHD (16)
        .probe17(exp_phase_r[poll_dev_r])               // expected CQ phase (1)
    );
`endif

endmodule
