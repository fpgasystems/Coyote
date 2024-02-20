/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * @brief   RDMA retrans multiplexer
 *
 */
module rdma_mux_retrans (
    input  logic            aclk,
    input  logic            aresetn,
    
    metaIntf.s              s_req_net,
    metaIntf.m              m_req_user,
    AXI4S.s                 s_axis_user,
    AXI4S.m                 m_axis_net,

    metaIntf.m              m_req_ddr_rd,
    metaIntf.m              m_req_ddr_wr,
    AXI4S.s                 s_axis_ddr,
    AXI4S.m                 m_axis_ddr
);

logic seq_snk_valid;
logic seq_snk_ready;
logic seq_src_valid;
logic seq_src_ready;

logic [LEN_BITS-1:0] len_snk;
logic [LEN_BITS-1:0] len_next;
logic actv_snk;
logic actv_next;

metaIntf #(.STYPE(req_t)) req_user ();
metaIntf #(.STYPE(logic[MEM_CMD_BITS-1:0])) req_ddr_rd ();
metaIntf #(.STYPE(logic[MEM_CMD_BITS-1:0])) req_ddr_wr ();

// --------------------------------------------------------------------------------
// I/O !!! interface 
// --------------------------------------------------------------------------------
meta_queue #(.DATA_BITS($bits(req_t))) inst_meta_user_q (.aclk(aclk), .aresetn(aresetn), .s_meta(req_user), .m_meta(m_req_user));
meta_queue #(.DATA_BITS(MEM_CMD_BITS)) inst_meta_ddr_rd_q (.aclk(aclk), .aresetn(aresetn), .s_meta(req_ddr_rd), .m_meta(m_req_ddr_rd));
meta_queue #(.DATA_BITS(MEM_CMD_BITS)) inst_meta_ddr_wr_q (.aclk(aclk), .aresetn(aresetn), .s_meta(req_ddr_wr), .m_meta(m_req_ddr_wr));


assign len_snk = s_req_net.data.len[LEN_BITS-1:0];
assign actv_snk = s_req_net.data.actv;

// --------------------------------------------------------------------------------
// Mux command
// --------------------------------------------------------------------------------
always_comb begin
    if(actv_snk) begin
        // User
        seq_snk_valid = seq_snk_ready & req_user.ready & req_ddr_wr.ready & s_req_net.valid;
        req_user.valid = seq_snk_valid;
        req_ddr_rd.valid = 1'b0;
        req_ddr_wr.valid = seq_snk_valid;


        s_req_net.ready = seq_snk_ready & req_user.ready & req_ddr_wr.ready;
    end
    else begin
        // Retrans
        seq_snk_valid = seq_snk_ready & req_ddr_rd.ready & s_req_net.valid;
        req_user.valid = 1'b0;
        req_ddr_rd.valid = seq_snk_valid;
        req_ddr_wr.valid = 1'b0;

        s_req_net.ready = seq_snk_ready & req_ddr_rd.ready;
    end
end

always_comb begin
    req_ddr_rd.data = 0;
    req_ddr_rd.data[0+:64] = s_req_net.data.offs << $clog2(PMTU_BYTES);
    req_ddr_rd.data[64+:32] = s_req_net.data.len;

    req_ddr_wr.data = 0;
    req_ddr_wr.data[0+:64] = s_req_net.data.offs << $clog2(PMTU_BYTES);
    req_ddr_wr.data[64+:32] = s_req_net.data.len;

    req_user.data = s_req_net.data;
end

queue_stream #(
    .QTYPE(logic [1+LEN_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_snk (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(seq_snk_valid),
    .rdy_snk(seq_snk_ready),
    .data_snk({actv_snk, len_snk}),
    .val_src(seq_src_valid),
    .rdy_src(seq_src_ready),
    .data_src({actv_next, len_next})
);

// --------------------------------------------------------------------------------
// Mux data
// --------------------------------------------------------------------------------

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

logic actv_C, actv_N;
logic [LEN_BITS-BEAT_LOG_BITS:0] cnt_C, cnt_N;

logic tr_done; 

AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_net ();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_ddr_wr ();

// --------------------------------------------------------------------------------
// I/O !!! interface 
// --------------------------------------------------------------------------------

axis_data_fifo_512 inst_data_que_net (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(axis_net.tvalid),
    .s_axis_tready(axis_net.tready),
    .s_axis_tdata (axis_net.tdata),
    .s_axis_tkeep (axis_net.tkeep),
    .s_axis_tlast (axis_net.tlast),
    .m_axis_tvalid(m_axis_net.tvalid),
    .m_axis_tready(m_axis_net.tready),
    .m_axis_tdata (m_axis_net.tdata),
    .m_axis_tkeep (m_axis_net.tkeep),
    .m_axis_tlast (m_axis_net.tlast)
);

axis_data_fifo_512 inst_data_que_ddr (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(axis_ddr_wr.tvalid),
    .s_axis_tready(axis_ddr_wr.tready),
    .s_axis_tdata (axis_ddr_wr.tdata),
    .s_axis_tkeep (axis_ddr_wr.tkeep),
    .s_axis_tlast (axis_ddr_wr.tlast),
    .m_axis_tvalid(m_axis_ddr.tvalid),
    .m_axis_tready(m_axis_ddr.tready),
    .m_axis_tdata (m_axis_ddr.tdata),
    .m_axis_tkeep (m_axis_ddr.tkeep),
    .m_axis_tlast (m_axis_ddr.tlast)
);

// REG
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;
    end
    else begin
        state_C <= state_N;
        cnt_C <= cnt_N;
        actv_C <= actv_N;
    end
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = (seq_src_valid) ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = tr_done ? (seq_src_valid ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// DP
always_comb begin: DP
    cnt_N = cnt_C;
    actv_N = actv_C;
    
    // Transfer done
    tr_done = (cnt_C == 0) && 
        (actv_C ? 
            (s_axis_user.tvalid & s_axis_user.tready) : 
            (s_axis_ddr.tvalid & s_axis_ddr.tready) );

    seq_src_ready = 1'b0;

    case(state_C)
        ST_IDLE: begin
            if(seq_src_valid) begin
                seq_src_ready = 1'b1;
                actv_N = actv_next;
                cnt_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
            end
        end
            
        ST_MUX: begin
            if(tr_done) begin
                cnt_N = 0;
                if(seq_src_valid) begin
                    seq_src_ready = 1'b1;
                    actv_N = actv_next;
                    cnt_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
                end
            end
            else begin
                cnt_N = actv_C ? 
                   ( (s_axis_user.tvalid & s_axis_user.tready ? cnt_C - 1 : cnt_C) ) : 
                   ( (s_axis_ddr.tvalid & s_axis_ddr.tready ? cnt_C - 1 : cnt_C) );
            end
        end

    endcase
end

// Mux
always_comb begin
    if(state_C == ST_MUX) begin
        s_axis_user.tready = actv_C ? axis_net.tready & axis_ddr_wr.tready : 1'b0;
        s_axis_ddr.tready = ~actv_C ? axis_net.tready : 1'b0; 

        axis_net.tvalid = actv_C ? s_axis_user.tvalid & s_axis_user.tready : s_axis_ddr.tvalid;
        axis_ddr_wr.tvalid = actv_C ? s_axis_user.tvalid & s_axis_user.tready : 1'b0;
    end
    else begin
        s_axis_user.tready = 1'b0;
        s_axis_ddr.tready = 1'b0;

        axis_net.tvalid = 1'b0;
        axis_ddr_wr.tvalid = 1'b0;
    end
end

assign axis_net.tdata = actv_C ? s_axis_user.tdata : s_axis_ddr.tdata;
assign axis_net.tkeep = actv_C ? s_axis_user.tkeep : s_axis_ddr.tkeep;
assign axis_net.tlast = actv_C ? s_axis_user.tlast : s_axis_ddr.tlast;

assign axis_ddr_wr.tdata = s_axis_user.tdata;
assign axis_ddr_wr.tkeep = s_axis_user.tkeep;
assign axis_ddr_wr.tlast = s_axis_user.tlast;

endmodule