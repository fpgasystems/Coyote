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

`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * @brief Convert the PL-NVMe Root Complex AXI master into Coyote host DMA.
 *
 * The PL-NVMe block design sends BD-local [0, 8 TiB) to axi_nvme_host.  This
 * host window is an identity map (HOST_ROUTE_BASE is zero), so the address is
 * submitted to the host-facing QDMA path unchanged.
 *
 * Each direction keeps up to N_RD_OUTSTANDING/N_WR_OUTSTANDING AXI bursts in
 * flight.  Every accepted burst is issued immediately as one host DMA request,
 * so the host round trip of a burst overlaps with the bursts that follow it.
 * Requests, data and responses all stay in AXI address order:
 *  - Host read data returns in request order, so R beats are forwarded as they
 *    arrive and do not wait for the DMA completion.
 *  - A write response is returned only after the burst's data was forwarded and
 *    its DMA completion arrived.  The Root Complex issues all writes with one
 *    AXI ID. The PL CQ router fences completion-queue publication on these
 *    real responses, even though CQ uses an independent SmartConnect.
 *    Host data therefore reaches QDMA before its completion becomes visible.
 * The Root Complex currently emits full-width, aligned INCR bursts; unsupported
 * AXI requests are completed with DECERR and are not submitted to host DMA.
 */
module nvme_axi_host_bridge #(
    parameter logic [63:0] HOST_ROUTE_BASE  = 64'h0000_0000_0000_0000,
    parameter logic [63:0] HOST_ROUTE_SIZE  = 64'h0000_0800_0000_0000,
    // Queue depths (at least 2); also the outstanding burst limit per direction
    parameter integer      N_RD_OUTSTANDING = 32,
    parameter integer      N_WR_OUTSTANDING = 32
) (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        enable,

    AXI4.s              s_axi,

    dmaIntf.m           m_host_dma_rd_req,
    dmaIntf.m           m_host_dma_wr_req,
    AXI4S.s             s_axis_host_rd,
    AXI4S.m             m_axis_host_wr
);

    localparam integer AXI_BYTES      = AXI_DATA_BITS / 8;
    localparam integer AXI_BYTE_BITS  = $clog2(AXI_BYTES);
    localparam logic [2:0] FULL_SIZE  = 3'(AXI_BYTE_BITS);
    localparam integer WR_CNT_BITS    = $clog2(N_WR_OUTSTANDING + 1);

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam logic [1:0] AXI_RESP_DECERR = 2'b11;
    localparam logic [1:0] AXI_BURST_INCR  = 2'b01;

    function automatic logic [LEN_BITS-1:0] burst_bytes(
        input logic [7:0] axi_len
    );
        logic [LEN_BITS-1:0] beats;
        begin
            beats = {{(LEN_BITS-8){1'b0}}, axi_len} + 1'b1;
            burst_bytes = beats << AXI_BYTE_BITS;
        end
    endfunction

    // The host window is a power of two aligned to its size, so membership
    // is a mask compare. A burst that starts inside the window also ends
    // inside it: an AXI INCR burst never crosses a 4-KiB boundary, and the
    // window ends on one.
    function automatic logic request_supported(
        input logic [63:0] addr,
        input logic [2:0]  axi_size,
        input logic [1:0]  axi_burst
    );
        begin
            request_supported =
                (axi_burst == AXI_BURST_INCR) &&
                (axi_size == FULL_SIZE) &&
                (addr[AXI_BYTE_BITS-1:0] == '0) &&
                ((addr & ~(HOST_ROUTE_SIZE - 64'd1)) == HOST_ROUTE_BASE);
        end
    endfunction

    function automatic logic [PADDR_BITS-1:0] host_paddr(
        input logic [63:0] tagged_addr
    );
        logic [63:0] decoded_addr;
        begin
            // The window is aligned to its size, so removing the base keeps
            // the offset bits (identity for the current zero-based window).
            decoded_addr = tagged_addr & (HOST_ROUTE_SIZE - 64'd1);
            host_paddr = decoded_addr[PADDR_BITS-1:0];
        end
    endfunction

    function automatic dma_req_t host_req(
        input logic [63:0] tagged_addr,
        input logic [7:0]  axi_len
    );
        begin
            host_req = '0;
            host_req.paddr = host_paddr(tagged_addr);
            host_req.len = burst_bytes(axi_len);
            host_req.last = 1'b1;
        end
    endfunction

    // One accepted AXI burst, queued in address order
    typedef struct packed {
        logic [AXI_ID_BITS-1:0] id;
        logic                   decerr;     // Unsupported, completed locally
        logic [7:0]             len;        // AXI beats - 1
    } burst_t;

    // Write response of a burst whose data has been accepted
    typedef struct packed {
        logic [AXI_ID_BITS-1:0] id;
        logic [1:0]             resp;
        logic                   host;       // Waits for its DMA completion
    } wr_resp_t;

    // ================-----------------------------------------------------------------
    // READ
    // ================-----------------------------------------------------------------
    logic       ar_fire;
    logic       ar_host;
    dma_req_t   rd_req;
    logic       rd_req_rdy;

    logic       rd_burst_rdy;
    logic       rd_burst_val;
    logic       rd_burst_pop;
    burst_t     rd_burst_in;
    burst_t     rd_burst;

    logic [7:0] rd_beat_C, rd_beat_N;

    // A read burst stays queued until its last R beat, so the queue depth is the
    // outstanding read limit.
    assign s_axi.arready = enable && rd_burst_rdy && rd_req_rdy;
    assign ar_fire = s_axi.arvalid && s_axi.arready;
    assign ar_host = request_supported(
        s_axi.araddr, s_axi.arsize, s_axi.arburst);

    assign rd_req = host_req(s_axi.araddr, s_axi.arlen);
    assign rd_burst_in.id = s_axi.arid;
    assign rd_burst_in.decerr = !ar_host;
    assign rd_burst_in.len = s_axi.arlen;

    queue_stream #(
        .QTYPE(dma_req_t),
        .QDEPTH(N_RD_OUTSTANDING)
    ) inst_rd_req_queue (
        .aclk    (aclk),
        .aresetn (aresetn),
        .val_snk (ar_fire && ar_host),
        .rdy_snk (rd_req_rdy),
        .data_snk(rd_req),
        .val_src (m_host_dma_rd_req.valid),
        .rdy_src (m_host_dma_rd_req.ready),
        .data_src(m_host_dma_rd_req.req)
    );

    queue_stream #(
        .QTYPE(burst_t),
        .QDEPTH(N_RD_OUTSTANDING)
    ) inst_rd_burst_queue (
        .aclk    (aclk),
        .aresetn (aresetn),
        .val_snk (ar_fire),
        .rdy_snk (rd_burst_rdy),
        .data_snk(rd_burst_in),
        .val_src (rd_burst_val),
        .rdy_src (rd_burst_pop),
        .data_src(rd_burst)
    );

    // R beats belong to the oldest burst: host data in request order, or a
    // local DECERR. The DMA read completion is not needed for ordering.
    always_comb begin
        rd_beat_N = rd_beat_C;
        rd_burst_pop = 1'b0;

        s_axi.rid = rd_burst.id;
        s_axi.rlast = rd_burst_val && (rd_beat_C == rd_burst.len);
        s_axi.rresp = rd_burst.decerr ? AXI_RESP_DECERR : AXI_RESP_OKAY;
        s_axi.rdata = rd_burst.decerr ? '0 : s_axis_host_rd.tdata;
        s_axi.rvalid = rd_burst_val &&
                       (rd_burst.decerr || s_axis_host_rd.tvalid);
        s_axis_host_rd.tready = rd_burst_val && !rd_burst.decerr &&
                                s_axi.rready;

        if (s_axi.rvalid && s_axi.rready) begin
            if (s_axi.rlast) begin
                rd_beat_N = '0;
                rd_burst_pop = 1'b1;
            end else begin
                rd_beat_N = rd_beat_C + 1'b1;
            end
        end
    end

    // ================-----------------------------------------------------------------
    // WRITE
    // ================-----------------------------------------------------------------
    logic                   aw_fire;
    logic                   aw_host;
    dma_req_t               wr_req;
    logic                   wr_req_rdy;

    logic                   wr_burst_rdy;
    logic                   wr_burst_val;
    logic                   wr_burst_pop;
    burst_t                 wr_burst_in;
    burst_t                 wr_burst;

    logic                   wr_resp_rdy;
    logic                   wr_resp_val;
    logic                   wr_resp_push;
    wr_resp_t               wr_resp_in;
    wr_resp_t               wr_resp;

    logic                   w_err;
    logic                   b_fire;

    logic [7:0]             wr_beat_C, wr_beat_N;
    logic                   wr_err_C, wr_err_N;
    logic [WR_CNT_BITS-1:0] wr_cnt_C, wr_cnt_N;     // AW accepted, B pending
    logic [WR_CNT_BITS-1:0] wr_done_C, wr_done_N;   // Unpaired DMA completions

    // A write is outstanding from its AW until its B response.
    assign s_axi.awready = enable &&
                           (wr_cnt_C != WR_CNT_BITS'(N_WR_OUTSTANDING)) &&
                           wr_burst_rdy && wr_req_rdy;
    assign aw_fire = s_axi.awvalid && s_axi.awready;
    assign aw_host = request_supported(
        s_axi.awaddr, s_axi.awsize, s_axi.awburst);

    assign wr_req = host_req(s_axi.awaddr, s_axi.awlen);
    assign wr_burst_in.id = s_axi.awid;
    assign wr_burst_in.decerr = !aw_host;
    assign wr_burst_in.len = s_axi.awlen;

    queue_stream #(
        .QTYPE(dma_req_t),
        .QDEPTH(N_WR_OUTSTANDING)
    ) inst_wr_req_queue (
        .aclk    (aclk),
        .aresetn (aresetn),
        .val_snk (aw_fire && aw_host),
        .rdy_snk (wr_req_rdy),
        .data_snk(wr_req),
        .val_src (m_host_dma_wr_req.valid),
        .rdy_src (m_host_dma_wr_req.ready),
        .data_src(m_host_dma_wr_req.req)
    );

    queue_stream #(
        .QTYPE(burst_t),
        .QDEPTH(N_WR_OUTSTANDING)
    ) inst_wr_burst_queue (
        .aclk    (aclk),
        .aresetn (aresetn),
        .val_snk (aw_fire),
        .rdy_snk (wr_burst_rdy),
        .data_snk(wr_burst_in),
        .val_src (wr_burst_val),
        .rdy_src (wr_burst_pop),
        .data_src(wr_burst)
    );

    queue_stream #(
        .QTYPE(wr_resp_t),
        .QDEPTH(N_WR_OUTSTANDING)
    ) inst_wr_resp_queue (
        .aclk    (aclk),
        .aresetn (aresetn),
        .val_snk (wr_resp_push),
        .rdy_snk (wr_resp_rdy),
        .data_snk(wr_resp_in),
        .val_src (wr_resp_val),
        .rdy_src (b_fire),
        .data_src(wr_resp)
    );

    // W beats belong to the oldest burst. Host data is forwarded to the DMA
    // stream; unsupported bursts are consumed locally without DMA. A valid
    // Root-Complex transfer is full-width and uses all byte lanes, so malformed
    // AXI is reported after it has been drained.
    assign w_err = (s_axi.wlast != (wr_beat_C == wr_burst.len)) ||
                   (!wr_burst.decerr && (s_axi.wstrb != {AXI_BYTES{1'b1}}));

    always_comb begin
        wr_beat_N = wr_beat_C;
        wr_err_N = wr_err_C;
        wr_burst_pop = 1'b0;
        wr_resp_push = 1'b0;

        m_axis_host_wr.tdata = s_axi.wdata;
        m_axis_host_wr.tkeep = s_axi.wstrb;
        m_axis_host_wr.tlast = (wr_beat_C == wr_burst.len);
        m_axis_host_wr.tvalid = wr_burst_val && !wr_burst.decerr &&
                                wr_resp_rdy && s_axi.wvalid;
        s_axi.wready = wr_burst_val && wr_resp_rdy &&
                       (wr_burst.decerr || m_axis_host_wr.tready);

        wr_resp_in.id = wr_burst.id;
        wr_resp_in.host = !wr_burst.decerr;
        wr_resp_in.resp = wr_burst.decerr ? AXI_RESP_DECERR :
                          ((wr_err_C || w_err) ? AXI_RESP_SLVERR :
                                                 AXI_RESP_OKAY);

        if (s_axi.wvalid && s_axi.wready) begin
            if (wr_beat_C == wr_burst.len) begin
                wr_beat_N = '0;
                wr_err_N = 1'b0;
                wr_burst_pop = 1'b1;
                wr_resp_push = 1'b1;
            end else begin
                wr_beat_N = wr_beat_C + 1'b1;
                wr_err_N = wr_err_C || w_err;
            end
        end
    end

    // A host burst's B waits for its DMA completion. Completions arrive in
    // request order, so they are counted and paired with host bursts in order.
    assign s_axi.bid = wr_resp.id;
    assign s_axi.bresp = wr_resp.resp;
    assign s_axi.bvalid = wr_resp_val && (!wr_resp.host || (wr_done_C != '0));
    assign b_fire = s_axi.bvalid && s_axi.bready;

    always_comb begin
        wr_cnt_N = wr_cnt_C;
        if (aw_fire && !b_fire)
            wr_cnt_N = wr_cnt_C + 1'b1;
        else if (!aw_fire && b_fire)
            wr_cnt_N = wr_cnt_C - 1'b1;

        wr_done_N = wr_done_C;
        if (m_host_dma_wr_req.rsp.done && !(b_fire && wr_resp.host))
            wr_done_N = wr_done_C + 1'b1;
        else if (!m_host_dma_wr_req.rsp.done && b_fire && wr_resp.host)
            wr_done_N = wr_done_C - 1'b1;
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            rd_beat_C <= '0;

            wr_beat_C <= '0;
            wr_err_C <= 1'b0;
            wr_cnt_C <= '0;
            wr_done_C <= '0;
        end else begin
            rd_beat_C <= rd_beat_N;

            wr_beat_C <= wr_beat_N;
            wr_err_C <= wr_err_N;
            wr_cnt_C <= wr_cnt_N;
            wr_done_C <= wr_done_N;
        end
    end

`ifndef SYNTHESIS
    initial assert ((HOST_ROUTE_SIZE & (HOST_ROUTE_SIZE - 64'd1)) == 64'd0 &&
                    HOST_ROUTE_SIZE >= 64'd4096 &&
                    (HOST_ROUTE_BASE & (HOST_ROUTE_SIZE - 64'd1)) == 64'd0)
        else $fatal(1, "nvme_axi_host_bridge: host window must be a power of two >= 4 KiB, aligned to its size");
    // The mask compare relies on AXI bursts never crossing 4 KiB.
    always @(posedge aclk)
        if (aresetn) begin
            if (ar_fire && ar_host)
                assert ({5'd0, s_axi.araddr[11:0]} + 17'(burst_bytes(s_axi.arlen)) <= 17'd4096)
                    else $error("nvme_axi_host_bridge: read burst crosses 4 KiB");
            if (aw_fire && aw_host)
                assert ({5'd0, s_axi.awaddr[11:0]} + 17'(burst_bytes(s_axi.awlen)) <= 17'd4096)
                    else $error("nvme_axi_host_bridge: write burst crosses 4 KiB");
        end
`endif

endmodule
