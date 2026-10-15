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

import lynxTypes::*;

/**
 * @brief User request mux
 *
 * Splits the user requests into local reads and writes per stream (host and card) and remote
 * requests, so a request that waits for the credits of its stream cannot block the requests of
 * another stream. As in req_mux_stream_1_2, host stream requests go to the host and all other
 * local requests to the card.
 */
module user_req_mux #(
    parameter integer                   ID_REG = 0  
) (
    // USER 
    metaIntf.s                          user_sq_rd,
    metaIntf.s                          user_sq_wr,

    //
`ifdef EN_STRM
    metaIntf.m                          user_local_rd_host,
    metaIntf.m                          user_local_wr_host,
`endif
`ifdef EN_MEM
    metaIntf.m                          user_local_rd_card,
    metaIntf.m                          user_local_wr_card,
`endif
`ifdef EN_NET
    metaIntf.m                          user_remote_rd,
    metaIntf.m                          user_remote_wr,
`endif

    input  logic    					aclk,    
	input  logic    					aresetn
);

// Override
metaIntf #(.STYPE(req_t)) user_sq_rd_or (.*);
metaIntf #(.STYPE(req_t)) user_sq_wr_or (.*);

always_comb begin
    user_sq_rd_or.valid = user_sq_rd.valid;
    user_sq_rd.ready = user_sq_rd_or.ready;
    user_sq_rd_or.data = user_sq_rd.data;
    user_sq_rd_or.data.actv = 1'b1;
    user_sq_rd_or.data.host = 1'b0;
    user_sq_rd_or.data.vfid = ID_REG;

    user_sq_wr_or.valid = user_sq_wr.valid;
    user_sq_wr.ready = user_sq_wr_or.ready;
    user_sq_wr_or.data = user_sq_wr.data;
    user_sq_wr_or.data.actv = 1'b1;
    user_sq_wr_or.data.host = 1'b0;
    user_sq_wr_or.data.vfid = ID_REG;
end

// Internal
metaIntf #(.STYPE(req_t)) user_sq_rd_int (.*);
metaIntf #(.STYPE(req_t)) user_sq_wr_int (.*);

// Sink reg
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_sq_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(user_sq_rd_or), .m_meta(user_sq_rd_int));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_sq_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(user_sq_wr_or), .m_meta(user_sq_wr_int));

// Destination of the requests
logic rd_remote, rd_host;
logic wr_remote, wr_host;

`ifdef EN_NET
assign rd_remote = ~(is_strm_local(user_sq_rd_int.data.strm));
assign wr_remote = ~(is_strm_local(user_sq_wr_int.data.strm));
`else
assign rd_remote = 1'b0;
assign wr_remote = 1'b0;
`endif

`ifdef EN_STRM
`ifdef EN_MEM
assign rd_host = user_sq_rd_int.data.strm == STRM_HOST;
assign wr_host = user_sq_wr_int.data.strm == STRM_HOST;
`else
assign rd_host = 1'b1;
assign wr_host = 1'b1;
`endif
`else
assign rd_host = 1'b0;
assign wr_host = 1'b0;
`endif

logic rd_remote_valid, rd_remote_ready, rd_host_valid, rd_host_ready, rd_card_valid, rd_card_ready;
logic wr_remote_valid, wr_remote_ready, wr_host_valid, wr_host_ready, wr_card_valid, wr_card_ready;

always_comb begin
    rd_remote_valid = user_sq_rd_int.valid &  rd_remote;
    rd_host_valid   = user_sq_rd_int.valid & ~rd_remote &  rd_host;
    rd_card_valid   = user_sq_rd_int.valid & ~rd_remote & ~rd_host;
    user_sq_rd_int.ready = rd_remote ? rd_remote_ready : (rd_host ? rd_host_ready : rd_card_ready);

    wr_remote_valid = user_sq_wr_int.valid &  wr_remote;
    wr_host_valid   = user_sq_wr_int.valid & ~wr_remote &  wr_host;
    wr_card_valid   = user_sq_wr_int.valid & ~wr_remote & ~wr_host;
    user_sq_wr_int.ready = wr_remote ? wr_remote_ready : (wr_host ? wr_host_ready : wr_card_ready);
end

// Local, host
`ifdef EN_STRM
metaIntf #(.STYPE(req_t)) user_local_rd_host_int (.*);
metaIntf #(.STYPE(req_t)) user_local_wr_host_int (.*);

assign user_local_rd_host_int.valid = rd_host_valid;
assign user_local_rd_host_int.data = user_sq_rd_int.data;
assign rd_host_ready = user_local_rd_host_int.ready;

assign user_local_wr_host_int.valid = wr_host_valid;
assign user_local_wr_host_int.data = user_sq_wr_int.data;
assign wr_host_ready = user_local_wr_host_int.ready;

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_rd_host  (.aclk(aclk), .aresetn(aresetn), .s_meta(user_local_rd_host_int), .m_meta(user_local_rd_host));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_wr_host  (.aclk(aclk), .aresetn(aresetn), .s_meta(user_local_wr_host_int), .m_meta(user_local_wr_host));
`else
assign rd_host_ready = 1'b0;
assign wr_host_ready = 1'b0;
`endif

// Local, card
`ifdef EN_MEM
metaIntf #(.STYPE(req_t)) user_local_rd_card_int (.*);
metaIntf #(.STYPE(req_t)) user_local_wr_card_int (.*);

assign user_local_rd_card_int.valid = rd_card_valid;
assign user_local_rd_card_int.data = user_sq_rd_int.data;
assign rd_card_ready = user_local_rd_card_int.ready;

assign user_local_wr_card_int.valid = wr_card_valid;
assign user_local_wr_card_int.data = user_sq_wr_int.data;
assign wr_card_ready = user_local_wr_card_int.ready;

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_rd_card  (.aclk(aclk), .aresetn(aresetn), .s_meta(user_local_rd_card_int), .m_meta(user_local_rd_card));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_wr_card  (.aclk(aclk), .aresetn(aresetn), .s_meta(user_local_wr_card_int), .m_meta(user_local_wr_card));
`else
assign rd_card_ready = 1'b0;
assign wr_card_ready = 1'b0;
`endif

// Remote
`ifdef EN_NET
metaIntf #(.STYPE(dreq_t)) user_remote_rd_int (.*);
metaIntf #(.STYPE(dreq_t)) user_remote_wr_int (.*);

assign user_remote_rd_int.valid = rd_remote_valid;
assign user_remote_rd_int.data.req_1 = user_sq_rd_int.data;
assign user_remote_rd_int.data.req_2 = 0;
assign rd_remote_ready = user_remote_rd_int.ready;

assign user_remote_wr_int.valid = wr_remote_valid;
assign user_remote_wr_int.data.req_1 = 0;
assign user_remote_wr_int.data.req_2 = user_sq_wr_int.data;
assign wr_remote_ready = user_remote_wr_int.ready;

meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_remote_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(user_remote_rd_int), .m_meta(user_remote_rd));
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_remote_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(user_remote_wr_int), .m_meta(user_remote_wr));
`else
assign rd_remote_ready = 1'b0;
assign wr_remote_ready = 1'b0;
`endif
    
endmodule
