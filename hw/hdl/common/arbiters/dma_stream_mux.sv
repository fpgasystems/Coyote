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
 * @brief Interface-independent implementation of a shared DMA/stream channel.
 *
 * Read and write descriptors are arbitrated independently. Descriptor order is
 * retained so returned read data and outgoing write data remain associated with
 * the client that issued each descriptor.
 */
module dma_stream_mux_core #(
    parameter integer N_CLIENTS = 2,
    parameter integer DATA_BITS = AXI_DATA_BITS,
    parameter integer QUEUE_DEPTH = N_OUTSTANDING_REGION
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    input  logic [N_CLIENTS-1:0]            s_client_rd_req_valid,
    input  dma_req_t [N_CLIENTS-1:0]        s_client_rd_req,
    output logic [N_CLIENTS-1:0]            m_client_rd_req_ready,
    output dma_rsp_t [N_CLIENTS-1:0]        m_client_rd_rsp,
    output logic                            m_shared_rd_req_valid,
    output dma_req_t                        m_shared_rd_req,
    input  logic                            s_shared_rd_req_ready,
    input  dma_rsp_t                        s_shared_rd_rsp,

    input  logic                            s_shared_rd_data_valid,
    input  logic [DATA_BITS-1:0]            s_shared_rd_data,
    input  logic [DATA_BITS/8-1:0]          s_shared_rd_keep,
    input  logic                            s_shared_rd_last,
    output logic                            m_shared_rd_ready,
    output logic [N_CLIENTS-1:0]            m_client_rd_data_valid,
    output logic [N_CLIENTS-1:0][DATA_BITS-1:0]
                                            m_client_rd_data,
    output logic [N_CLIENTS-1:0][DATA_BITS/8-1:0]
                                            m_client_rd_keep,
    output logic [N_CLIENTS-1:0]            m_client_rd_last,
    input  logic [N_CLIENTS-1:0]            s_client_rd_ready,

    input  logic [N_CLIENTS-1:0]            s_client_wr_req_valid,
    input  dma_req_t [N_CLIENTS-1:0]        s_client_wr_req,
    output logic [N_CLIENTS-1:0]            m_client_wr_req_ready,
    output dma_rsp_t [N_CLIENTS-1:0]        m_client_wr_rsp,
    output logic                            m_shared_wr_req_valid,
    output dma_req_t                        m_shared_wr_req,
    input  logic                            s_shared_wr_req_ready,
    input  dma_rsp_t                        s_shared_wr_rsp,

    input  logic [N_CLIENTS-1:0]            s_client_wr_data_valid,
    input  logic [N_CLIENTS-1:0][DATA_BITS-1:0]
                                            s_client_wr_data,
    input  logic [N_CLIENTS-1:0][DATA_BITS/8-1:0]
                                            s_client_wr_keep,
    output logic [N_CLIENTS-1:0]            m_client_wr_ready,
    output logic                            m_shared_wr_data_valid,
    output logic [DATA_BITS-1:0]            m_shared_wr_data,
    output logic [DATA_BITS/8-1:0]          m_shared_wr_keep,
    output logic                            m_shared_wr_last,
    input  logic                            s_shared_wr_ready
);

    localparam integer CLIENT_BITS = clog2s(N_CLIENTS);
    localparam integer DATA_BEAT_LOG_BITS = $clog2(DATA_BITS / 8);
    localparam integer BEAT_COUNT_BITS = LEN_BITS - DATA_BEAT_LOG_BITS;

    logic rd_route_valid;
    logic rd_route_ready;
    logic [CLIENT_BITS-1:0] rd_route_client;
    logic [BEAT_COUNT_BITS-1:0] rd_route_beats;
    logic rd_route_last;

    logic wr_route_valid;
    logic wr_route_ready;
    logic [CLIENT_BITS-1:0] wr_route_client;
    logic [BEAT_COUNT_BITS-1:0] wr_route_beats;
    // Write-side TLAST is generated from the descriptor length; the logical
    // request-last flag only applies to completion signalling downstream.
    logic wr_route_last_unused;

    logic rd_active_C, rd_active_N;
    logic [CLIENT_BITS-1:0] rd_client_C, rd_client_N;
    logic [BEAT_COUNT_BITS-1:0] rd_beats_C, rd_beats_N;
    logic rd_last_C, rd_last_N;

    logic wr_active_C, wr_active_N;
    logic [CLIENT_BITS-1:0] wr_client_C, wr_client_N;
    logic [BEAT_COUNT_BITS-1:0] wr_beats_C, wr_beats_N;

    dma_stream_request_mux #(
        .N_CLIENTS (N_CLIENTS),
        .DATA_BITS (DATA_BITS),
        .QUEUE_DEPTH(QUEUE_DEPTH)
    ) inst_read_request_mux (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_client_valid(s_client_rd_req_valid),
        .s_client_req  (s_client_rd_req),
        .m_client_ready(m_client_rd_req_ready),
        .m_client_rsp  (m_client_rd_rsp),
        .m_shared_valid(m_shared_rd_req_valid),
        .m_shared_req  (m_shared_rd_req),
        .s_shared_ready(s_shared_rd_req_ready),
        .s_shared_rsp  (s_shared_rd_rsp),
        .m_route_valid (rd_route_valid),
        .m_route_ready (rd_route_ready),
        .m_route_client(rd_route_client),
        .m_route_beats (rd_route_beats),
        .m_route_last  (rd_route_last)
    );

    dma_stream_request_mux #(
        .N_CLIENTS (N_CLIENTS),
        .DATA_BITS (DATA_BITS),
        .QUEUE_DEPTH(QUEUE_DEPTH)
    ) inst_write_request_mux (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_client_valid(s_client_wr_req_valid),
        .s_client_req  (s_client_wr_req),
        .m_client_ready(m_client_wr_req_ready),
        .m_client_rsp  (m_client_wr_rsp),
        .m_shared_valid(m_shared_wr_req_valid),
        .m_shared_req  (m_shared_wr_req),
        .s_shared_ready(s_shared_wr_req_ready),
        .s_shared_rsp  (s_shared_wr_rsp),
        .m_route_valid (wr_route_valid),
        .m_route_ready (wr_route_ready),
        .m_route_client(wr_route_client),
        .m_route_beats (wr_route_beats),
        .m_route_last  (wr_route_last_unused)
    );

    always_comb begin
        rd_active_N = rd_active_C;
        rd_client_N = rd_client_C;
        rd_beats_N = rd_beats_C;
        rd_last_N = rd_last_C;

        wr_active_N = wr_active_C;
        wr_client_N = wr_client_C;
        wr_beats_N = wr_beats_C;

        rd_route_ready = 1'b0;
        wr_route_ready = 1'b0;

        m_shared_rd_ready = 1'b0;
        m_client_rd_data_valid = '0;
        m_client_rd_data = '0;
        m_client_rd_keep = '0;
        m_client_rd_last = '0;

        m_client_wr_ready = '0;
        m_shared_wr_data_valid = 1'b0;
        m_shared_wr_data = '0;
        m_shared_wr_keep = '0;
        m_shared_wr_last = 1'b0;

        if (!rd_active_C) begin
            if (rd_route_valid) begin
                rd_route_ready = 1'b1;
                rd_active_N = 1'b1;
                rd_client_N = rd_route_client;
                rd_beats_N = rd_route_beats;
                rd_last_N = rd_route_last;
            end
        end else begin
            m_client_rd_data_valid[rd_client_C] = s_shared_rd_data_valid;
            m_client_rd_data[rd_client_C] = s_shared_rd_data;
            m_client_rd_keep[rd_client_C] = s_shared_rd_keep;
            m_client_rd_last[rd_client_C] = s_shared_rd_last && rd_last_C;
            m_shared_rd_ready = s_client_rd_ready[rd_client_C];

            if (s_shared_rd_data_valid && m_shared_rd_ready) begin
                if (rd_beats_C == 0)
                    rd_active_N = 1'b0;
                else
                    rd_beats_N = rd_beats_C - 1'b1;
            end
        end

        if (!wr_active_C) begin
            if (wr_route_valid) begin
                wr_route_ready = 1'b1;
                wr_active_N = 1'b1;
                wr_client_N = wr_route_client;
                wr_beats_N = wr_route_beats;
            end
        end else begin
            m_shared_wr_data_valid = s_client_wr_data_valid[wr_client_C];
            m_shared_wr_data = s_client_wr_data[wr_client_C];
            m_shared_wr_keep = s_client_wr_keep[wr_client_C];
            m_shared_wr_last = (wr_beats_C == 0);
            m_client_wr_ready[wr_client_C] = s_shared_wr_ready;

            if (m_shared_wr_data_valid && s_shared_wr_ready) begin
                if (wr_beats_C == 0)
                    wr_active_N = 1'b0;
                else
                    wr_beats_N = wr_beats_C - 1'b1;
            end
        end
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            rd_active_C <= 1'b0;
            rd_client_C <= '0;
            rd_beats_C <= '0;
            rd_last_C <= 1'b0;

            wr_active_C <= 1'b0;
            wr_client_C <= '0;
            wr_beats_C <= '0;
        end else begin
            rd_active_C <= rd_active_N;
            rd_client_C <= rd_client_N;
            rd_beats_C <= rd_beats_N;
            rd_last_C <= rd_last_N;

            wr_active_C <= wr_active_N;
            wr_client_C <= wr_client_N;
            wr_beats_C <= wr_beats_N;
        end
    end

endmodule

/**
 * @brief Coyote-interface facade for dma_stream_mux_core.
 *
 * Keeping interface adaptation separate from the routing core makes the common
 * component straightforward to extend and unit-test without NVMe dependencies.
 */
module dma_stream_mux #(
    parameter integer N_CLIENTS = 2,
    parameter integer DATA_BITS = AXI_DATA_BITS,
    parameter integer QUEUE_DEPTH = N_OUTSTANDING_REGION
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    dmaIntf.s                               s_client_rd_req [N_CLIENTS],
    dmaIntf.m                               m_shared_rd_req,
    AXI4S.s                                 s_shared_rd_data,
    AXI4S.m                                 m_client_rd_data [N_CLIENTS],

    dmaIntf.s                               s_client_wr_req [N_CLIENTS],
    dmaIntf.m                               m_shared_wr_req,
    AXI4S.s                                 s_client_wr_data [N_CLIENTS],
    AXI4S.m                                 m_shared_wr_data
);

    logic [N_CLIENTS-1:0] client_rd_req_valid;
    dma_req_t [N_CLIENTS-1:0] client_rd_req;
    logic [N_CLIENTS-1:0] client_rd_req_ready;
    dma_rsp_t [N_CLIENTS-1:0] client_rd_rsp;

    logic [N_CLIENTS-1:0] client_wr_req_valid;
    dma_req_t [N_CLIENTS-1:0] client_wr_req;
    logic [N_CLIENTS-1:0] client_wr_req_ready;
    dma_rsp_t [N_CLIENTS-1:0] client_wr_rsp;

    logic shared_rd_req_valid;
    dma_req_t shared_rd_req;
    logic shared_rd_req_ready;
    dma_rsp_t shared_rd_rsp;
    logic shared_wr_req_valid;
    dma_req_t shared_wr_req;
    logic shared_wr_req_ready;
    dma_rsp_t shared_wr_rsp;

    logic shared_rd_data_valid;
    logic [DATA_BITS-1:0] shared_rd_data;
    logic [DATA_BITS/8-1:0] shared_rd_keep;
    logic shared_rd_last;
    logic shared_rd_ready;
    logic [N_CLIENTS-1:0] client_rd_data_valid;
    logic [N_CLIENTS-1:0][DATA_BITS-1:0] client_rd_data;
    logic [N_CLIENTS-1:0][DATA_BITS/8-1:0] client_rd_keep;
    logic [N_CLIENTS-1:0] client_rd_last;
    logic [N_CLIENTS-1:0] client_rd_ready;

    logic [N_CLIENTS-1:0] client_wr_data_valid;
    logic [N_CLIENTS-1:0][DATA_BITS-1:0] client_wr_data;
    logic [N_CLIENTS-1:0][DATA_BITS/8-1:0] client_wr_keep;
    logic [N_CLIENTS-1:0] client_wr_ready;
    logic shared_wr_data_valid;
    logic [DATA_BITS-1:0] shared_wr_data;
    logic [DATA_BITS/8-1:0] shared_wr_keep;
    logic shared_wr_last;
    logic shared_wr_ready;

    for (genvar i = 0; i < N_CLIENTS; i++) begin : gen_client_interfaces
        assign client_rd_req_valid[i] = s_client_rd_req[i].valid;
        assign client_rd_req[i] = s_client_rd_req[i].req;
        assign s_client_rd_req[i].ready = client_rd_req_ready[i];
        assign s_client_rd_req[i].rsp = client_rd_rsp[i];

        assign m_client_rd_data[i].tvalid = client_rd_data_valid[i];
        assign m_client_rd_data[i].tdata = client_rd_data[i];
        assign m_client_rd_data[i].tkeep = client_rd_keep[i];
        assign m_client_rd_data[i].tlast = client_rd_last[i];
        assign client_rd_ready[i] = m_client_rd_data[i].tready;

        assign client_wr_req_valid[i] = s_client_wr_req[i].valid;
        assign client_wr_req[i] = s_client_wr_req[i].req;
        assign s_client_wr_req[i].ready = client_wr_req_ready[i];
        assign s_client_wr_req[i].rsp = client_wr_rsp[i];

        assign client_wr_data_valid[i] = s_client_wr_data[i].tvalid;
        assign client_wr_data[i] = s_client_wr_data[i].tdata;
        assign client_wr_keep[i] = s_client_wr_data[i].tkeep;
        assign s_client_wr_data[i].tready = client_wr_ready[i];
    end

    assign m_shared_rd_req.valid = shared_rd_req_valid;
    assign m_shared_rd_req.req = shared_rd_req;
    assign shared_rd_req_ready = m_shared_rd_req.ready;
    assign shared_rd_rsp = m_shared_rd_req.rsp;

    assign shared_rd_data_valid = s_shared_rd_data.tvalid;
    assign shared_rd_data = s_shared_rd_data.tdata;
    assign shared_rd_keep = s_shared_rd_data.tkeep;
    assign shared_rd_last = s_shared_rd_data.tlast;
    assign s_shared_rd_data.tready = shared_rd_ready;

    assign m_shared_wr_req.valid = shared_wr_req_valid;
    assign m_shared_wr_req.req = shared_wr_req;
    assign shared_wr_req_ready = m_shared_wr_req.ready;
    assign shared_wr_rsp = m_shared_wr_req.rsp;

    assign m_shared_wr_data.tvalid = shared_wr_data_valid;
    assign m_shared_wr_data.tdata = shared_wr_data;
    assign m_shared_wr_data.tkeep = shared_wr_keep;
    assign m_shared_wr_data.tlast = shared_wr_last;
    assign shared_wr_ready = m_shared_wr_data.tready;

    dma_stream_mux_core #(
        .N_CLIENTS (N_CLIENTS),
        .DATA_BITS (DATA_BITS),
        .QUEUE_DEPTH(QUEUE_DEPTH)
    ) inst_core (
        .aclk                    (aclk),
        .aresetn                 (aresetn),
        .s_client_rd_req_valid   (client_rd_req_valid),
        .s_client_rd_req         (client_rd_req),
        .m_client_rd_req_ready   (client_rd_req_ready),
        .m_client_rd_rsp         (client_rd_rsp),
        .m_shared_rd_req_valid   (shared_rd_req_valid),
        .m_shared_rd_req         (shared_rd_req),
        .s_shared_rd_req_ready   (shared_rd_req_ready),
        .s_shared_rd_rsp         (shared_rd_rsp),
        .s_shared_rd_data_valid  (shared_rd_data_valid),
        .s_shared_rd_data        (shared_rd_data),
        .s_shared_rd_keep        (shared_rd_keep),
        .s_shared_rd_last        (shared_rd_last),
        .m_shared_rd_ready       (shared_rd_ready),
        .m_client_rd_data_valid  (client_rd_data_valid),
        .m_client_rd_data        (client_rd_data),
        .m_client_rd_keep        (client_rd_keep),
        .m_client_rd_last        (client_rd_last),
        .s_client_rd_ready       (client_rd_ready),
        .s_client_wr_req_valid   (client_wr_req_valid),
        .s_client_wr_req         (client_wr_req),
        .m_client_wr_req_ready   (client_wr_req_ready),
        .m_client_wr_rsp         (client_wr_rsp),
        .m_shared_wr_req_valid   (shared_wr_req_valid),
        .m_shared_wr_req         (shared_wr_req),
        .s_shared_wr_req_ready   (shared_wr_req_ready),
        .s_shared_wr_rsp         (shared_wr_rsp),
        .s_client_wr_data_valid  (client_wr_data_valid),
        .s_client_wr_data        (client_wr_data),
        .s_client_wr_keep        (client_wr_keep),
        .m_client_wr_ready       (client_wr_ready),
        .m_shared_wr_data_valid  (shared_wr_data_valid),
        .m_shared_wr_data        (shared_wr_data),
        .m_shared_wr_keep        (shared_wr_keep),
        .m_shared_wr_last        (shared_wr_last),
        .s_shared_wr_ready       (shared_wr_ready)
    );

endmodule
