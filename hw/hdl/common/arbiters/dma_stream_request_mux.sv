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
 * @brief Arbitrate DMA descriptors and remember their data/completion owner.
 *
 * This is the interface-independent request half of dma_stream_mux. Descriptor
 * requests are selected round-robin. Separate FIFOs retain the selected client
 * for the descriptor's AXI4-Stream payload and its dmaIntf completion pulse.
 */
module dma_stream_request_mux #(
    parameter integer N_CLIENTS = 2,
    parameter integer DATA_BITS = AXI_DATA_BITS,
    parameter integer QUEUE_DEPTH = N_OUTSTANDING_REGION
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    input  logic [N_CLIENTS-1:0]            s_client_valid,
    input  dma_req_t [N_CLIENTS-1:0]        s_client_req,
    output logic [N_CLIENTS-1:0]            m_client_ready,
    output dma_rsp_t [N_CLIENTS-1:0]        m_client_rsp,

    output logic                            m_shared_valid,
    output dma_req_t                        m_shared_req,
    input  logic                            s_shared_ready,
    input  dma_rsp_t                        s_shared_rsp,

    output logic                            m_route_valid,
    input  logic                            m_route_ready,
    output logic [clog2s(N_CLIENTS)-1:0]    m_route_client,
    output logic [LEN_BITS-$clog2(DATA_BITS/8)-1:0]
                                            m_route_beats,
    output logic                            m_route_last
);

    localparam integer CLIENT_BITS = clog2s(N_CLIENTS);
    localparam integer DATA_BEAT_LOG_BITS = $clog2(DATA_BITS / 8);
    localparam integer BEAT_COUNT_BITS = LEN_BITS - DATA_BEAT_LOG_BITS;
    localparam integer ROUTE_BITS = 1 + CLIENT_BITS + BEAT_COUNT_BITS;

    logic [CLIENT_BITS-1:0] rr_client_C;
    logic [CLIENT_BITS-1:0] selected_client;
    logic                   selected_valid;
    integer                 candidate_client;

    logic data_queue_ready;
    logic done_queue_ready;
    logic descriptor_fire;

    logic [ROUTE_BITS-1:0] route_in;
    logic [ROUTE_BITS-1:0] route_out;
    logic                  done_valid;
    logic [CLIENT_BITS-1:0] done_client;

    logic [BEAT_COUNT_BITS-1:0] selected_beats;

    function automatic logic [BEAT_COUNT_BITS-1:0] beats_minus_one(
        input logic [LEN_BITS-1:0] byte_length
    );
        if (byte_length == 0)
            beats_minus_one = '0;
        else
            beats_minus_one = BEAT_COUNT_BITS'(
                (byte_length - 1'b1) >> DATA_BEAT_LOG_BITS);
    endfunction

    always_comb begin
        selected_client = rr_client_C;
        selected_valid = 1'b0;
        candidate_client = int'(rr_client_C);

        for (int offset = 0; offset < N_CLIENTS; offset++) begin
            candidate_client = int'(rr_client_C) + offset;
            if (candidate_client >= N_CLIENTS)
                candidate_client = candidate_client - N_CLIENTS;

            if (!selected_valid && s_client_valid[candidate_client]) begin
                selected_client = CLIENT_BITS'(candidate_client);
                selected_valid = 1'b1;
            end
        end

        m_client_ready = '0;
        m_client_rsp = '0;

        m_shared_req = selected_valid ? s_client_req[selected_client] : '0;
        m_shared_valid = selected_valid && data_queue_ready &&
                         done_queue_ready;

        if (selected_valid) begin
            m_client_ready[selected_client] = s_shared_ready &&
                                                data_queue_ready &&
                                                done_queue_ready;
        end

        if (done_valid && s_shared_rsp.done)
            m_client_rsp[done_client].done = 1'b1;
    end

    assign descriptor_fire = m_shared_valid && s_shared_ready;
    assign selected_beats = beats_minus_one(
        s_client_req[selected_client].len);
    assign route_in = {
        s_client_req[selected_client].last,
        selected_client,
        selected_beats
    };

    assign {
        m_route_last,
        m_route_client,
        m_route_beats
    } = route_out;

    queue_stream #(
        .QTYPE(logic [ROUTE_BITS-1:0]),
        .QDEPTH(QUEUE_DEPTH)
    ) inst_data_route_queue (
        .aclk    (aclk),
        .aresetn (aresetn),
        .val_snk (descriptor_fire),
        .rdy_snk (data_queue_ready),
        .data_snk(route_in),
        .val_src (m_route_valid),
        .rdy_src (m_route_ready),
        .data_src(route_out)
    );

    queue_stream #(
        .QTYPE(logic [CLIENT_BITS-1:0]),
        .QDEPTH(QUEUE_DEPTH)
    ) inst_completion_route_queue (
        .aclk    (aclk),
        .aresetn (aresetn),
        .val_snk (descriptor_fire),
        .rdy_snk (done_queue_ready),
        .data_snk(selected_client),
        .val_src (done_valid),
        .rdy_src (s_shared_rsp.done),
        .data_src(done_client)
    );

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            rr_client_C <= '0;
        end else if (descriptor_fire) begin
            if (selected_client == CLIENT_BITS'(N_CLIENTS - 1))
                rr_client_C <= '0;
            else
                rr_client_C <= selected_client + 1'b1;
        end
    end

endmodule
