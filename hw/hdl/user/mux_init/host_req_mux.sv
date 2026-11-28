/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
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

`include "lynx_macros.svh"

import lynxTypes::*;

/**
 * @brief Host request mux
 *
 * Splits the host requests into local reads and writes per stream (host and card) and remote
 * requests. The shell queues the host requests in one command queue per stream (see cnfg_slave),
 * so a request that waits for the credits of its stream cannot block the requests of another stream.
 * A remote write also reads its data locally; that local read is merged into the reads of its stream.
 */
module host_req_mux (
    // HOST, one command queue per stream
`ifdef EN_STRM
    metaIntf.s                          host_sq_host,
    metaIntf.m                          host_local_rd_host,
    metaIntf.m                          host_local_wr_host,
`endif
`ifdef EN_MEM
    metaIntf.s                          host_sq_card,
    metaIntf.m                          host_local_rd_card,
    metaIntf.m                          host_local_wr_card,
`endif
`ifdef EN_NET
    metaIntf.s                          host_sq_remote,
    metaIntf.m                          host_remote_rd,
    metaIntf.m                          host_remote_wr,
`endif

    input  logic    					aclk,    
	input  logic    					aresetn
);

// ----------------------------------------------------------------------------------------
// Local requests
// ----------------------------------------------------------------------------------------
`ifdef EN_STRM
metaIntf #(.STYPE(req_t)) host_local_rd_host_int (.*);

host_req_mux_local inst_local_host (
    .host_sq(host_sq_host),
    .host_local_rd(host_local_rd_host_int),
    .host_local_wr(host_local_wr_host),
    .aclk(aclk),
    .aresetn(aresetn)
);
`endif

`ifdef EN_MEM
metaIntf #(.STYPE(req_t)) host_local_rd_card_int (.*);

host_req_mux_local inst_local_card (
    .host_sq(host_sq_card),
    .host_local_rd(host_local_rd_card_int),
    .host_local_wr(host_local_wr_card),
    .aclk(aclk),
    .aresetn(aresetn)
);
`endif

`ifdef EN_NET
// ----------------------------------------------------------------------------------------
// Remote requests
// ----------------------------------------------------------------------------------------
metaIntf #(.STYPE(dreq_t)) host_sq_remote_int (.*);
metaIntf #(.STYPE(req_t))  remote_local_rd_int (.*);
metaIntf #(.STYPE(req_t))  remote_local_rd (.*);
metaIntf #(.STYPE(dreq_t)) host_remote_rd_int (.*);
metaIntf #(.STYPE(dreq_t)) host_remote_wr_int (.*);

logic remote_wr_picked_up;
logic local_rd_picked_up;

// Sink reg
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_sq_remote (.aclk(aclk), .aresetn(aresetn), .s_meta(host_sq_remote), .m_meta(host_sq_remote_int));

always_comb begin
    host_sq_remote_int.ready = 1'b0;

    remote_local_rd_int.valid = 1'b0;
    host_remote_rd_int.valid = 1'b0;
    host_remote_wr_int.valid = 1'b0;

    remote_local_rd_int.data = host_sq_remote_int.data.req_1;
    remote_local_rd_int.data.actv = 1'b1;

    host_remote_rd_int.data = host_sq_remote_int.data;
    host_remote_rd_int.data.req_1.actv = 1'b1;
    host_remote_rd_int.data.req_2.actv = 1'b0;
    host_remote_wr_int.data = host_sq_remote_int.data;
    host_remote_wr_int.data.req_1.actv = 1'b0;
    host_remote_wr_int.data.req_2.actv = 1'b1;

    if(host_sq_remote_int.valid) begin
        if(host_sq_remote_int.data.req_1.actv) begin // rd, remote
            host_sq_remote_int.ready = host_remote_rd_int.ready;

            host_remote_rd_int.valid = 1'b1;
        end
        else if(host_sq_remote_int.data.req_2.actv) begin // wr, remote; reads its data locally
            host_sq_remote_int.ready = host_remote_wr_int.ready & remote_local_rd_int.ready;
            
            host_remote_wr_int.valid = !remote_wr_picked_up;
            remote_local_rd_int.valid = !local_rd_picked_up;
        end
    end
end

always_ff @ (posedge aclk) begin 
    if(!aresetn) begin
        // Basic case: We assume both signals have been picked up
        remote_wr_picked_up <= 0; 
        local_rd_picked_up <= 0; 
    end else begin 
        // Check for the right case of a local_rd & remote_wr double-action 
        if(host_sq_remote_int.valid && !host_sq_remote_int.data.req_1.actv && host_sq_remote_int.data.req_2.actv) begin
            // In case of synchronicity: Both ready-signals are up, signals where picked up, don't change any settings here:
            if(host_remote_wr_int.ready && remote_local_rd_int.ready) begin
                // Keep signals as they are - in such a case, we don't need to take care specifically
                remote_wr_picked_up <= 0; 
                local_rd_picked_up <= 0;
            end else if(host_remote_wr_int.ready && !remote_local_rd_int.ready) begin
                // Means: Signal has been picked up!
                remote_wr_picked_up <= 1; 
            end else if(!host_remote_wr_int.ready && remote_local_rd_int.ready) begin
                // Signal has been picked up! 
                local_rd_picked_up <= 1; 
            end 
        end 
    end 
end 

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_remote_local_rd  (.aclk(aclk), .aresetn(aresetn), .s_meta(remote_local_rd_int), .m_meta(remote_local_rd));
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_remote_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(host_remote_rd_int), .m_meta(host_remote_rd));
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_remote_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(host_remote_wr_int), .m_meta(host_remote_wr));

// Merge the local read of the remote writes into the reads of its stream
`ifdef EN_STRM
`ifdef EN_MEM
metaIntf #(.STYPE(req_t)) remote_local_rd_host (.*);
metaIntf #(.STYPE(req_t)) remote_local_rd_card (.*);

req_mux_stream_1_2 inst_remote_local_rd_mux (
    .s_req(remote_local_rd),
    .m_req_0(remote_local_rd_host),
    .m_req_1(remote_local_rd_card),
    .aclk(aclk),
    .aresetn(aresetn)
);

req_arb_2_1 inst_arb_local_rd_host (.aclk(aclk), .aresetn(aresetn), .s_req_0(host_local_rd_host_int), .s_req_1(remote_local_rd_host), .m_req(host_local_rd_host));
req_arb_2_1 inst_arb_local_rd_card (.aclk(aclk), .aresetn(aresetn), .s_req_0(host_local_rd_card_int), .s_req_1(remote_local_rd_card), .m_req(host_local_rd_card));
`else
req_arb_2_1 inst_arb_local_rd_host (.aclk(aclk), .aresetn(aresetn), .s_req_0(host_local_rd_host_int), .s_req_1(remote_local_rd), .m_req(host_local_rd_host));
`endif
`else
`ifdef EN_MEM
req_arb_2_1 inst_arb_local_rd_card (.aclk(aclk), .aresetn(aresetn), .s_req_0(host_local_rd_card_int), .s_req_1(remote_local_rd), .m_req(host_local_rd_card));
`else
// Without host or card streams, there is no local read path
assign remote_local_rd.ready = 1'b1;
`endif
`endif

`else
`ifdef EN_STRM
`META_ASSIGN(host_local_rd_host_int, host_local_rd_host)
`endif
`ifdef EN_MEM
`META_ASSIGN(host_local_rd_card_int, host_local_rd_card)
`endif
`endif

endmodule

/**
 * @brief Splits the local requests of one stream's command queue into reads and writes
 *
 * A request with both a read and a write (e.g., a local transfer) is issued once both are accepted.
 */
module host_req_mux_local (
    metaIntf.s                          host_sq,

    metaIntf.m                          host_local_rd,
    metaIntf.m                          host_local_wr,

    input  logic    					aclk,
	input  logic    					aresetn
);

metaIntf #(.STYPE(dreq_t)) host_sq_int (.*);
metaIntf #(.STYPE(req_t))  host_local_rd_int (.*);
metaIntf #(.STYPE(req_t))  host_local_wr_int (.*);

// Sink reg
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_sq  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_sq), .m_meta(host_sq_int));

always_comb begin
    host_sq_int.ready = 1'b0;

    host_local_rd_int.valid = 1'b0;
    host_local_wr_int.valid = 1'b0;

    if(host_sq_int.valid) begin
        if(host_sq_int.data.req_1.actv & host_sq_int.data.req_2.actv) begin
            host_sq_int.ready = host_local_rd_int.ready & host_local_wr_int.ready;
            
            host_local_rd_int.valid = host_sq_int.ready;
            host_local_wr_int.valid = host_sq_int.ready;
        end
        else if(host_sq_int.data.req_1.actv) begin
            host_sq_int.ready = host_local_rd_int.ready;

            host_local_rd_int.valid = 1'b1;
        end
        else if(host_sq_int.data.req_2.actv) begin
            host_sq_int.ready = host_local_wr_int.ready;

            host_local_wr_int.valid = 1'b1;
        end
    end
end

assign host_local_rd_int.data = host_sq_int.data.req_1;
assign host_local_wr_int.data = host_sq_int.data.req_2;

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_rd  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_local_rd_int), .m_meta(host_local_rd));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_wr  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_local_wr_int), .m_meta(host_local_wr));
    
endmodule
