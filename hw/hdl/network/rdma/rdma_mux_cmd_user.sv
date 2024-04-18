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
 * @brief   RDMA WR verb multiplexer
 *
 * Multiplexing of the RDMA write commands in front of user logic
 * Splits SENDs and WRITEs
 */
module rdma_mux_cmd_user (
    input  logic            aclk,
    input  logic            aresetn,
    
    metaIntf.s              s_req,
    AXI4SR.s                s_axis_wr,
    metaIntf.m              m_req_wr,
    AXI4SR.m                m_axis_wr,
    metaIntf.m              m_req_rq,
    AXI4SR.m                m_axis_rq
);

logic [1:0] ready_src;
logic [1:0] valid_src;
logic ready_snk;
logic valid_snk;
req_t [1:0] request_src;
req_t request_snk;

logic seq_snk_valid;
logic seq_snk_ready;
logic seq_src_valid;
logic seq_src_ready;

logic host_snk;
logic host_next;
logic [LEN_BITS-1:0] len_snk;
logic [LEN_BITS-1:0] len_next;
logic [PID_BITS-1:0] pid_snk;
logic [PID_BITS-1:0] pid_next;

metaIntf #(.STYPE(req_t)) req_wr ();
metaIntf #(.STYPE(req_t)) req_rq ();
// metaIntf #(.STYPE(req_t)) req_que [2] (); FIXME: why is this failing only here?

// --------------------------------------------------------------------------------
// -- I/O !!! interface 
// --------------------------------------------------------------------------------
assign req_rq.valid = valid_src[0];
assign ready_src[0] = req_rq.ready;
assign req_rq.data = request_src[0];   

assign req_wr.valid = valid_src[1];
assign ready_src[1] = req_wr.ready;
assign req_wr.data = request_src[1];   

assign valid_snk = s_req.valid;
assign s_req.ready = ready_snk;
assign request_snk = s_req.data;

assign len_snk = s_req.data.len[LEN_BITS-1:0];
assign host_snk = s_req.data.host;
assign vfid_snk = s_req.data.vfid;
assign pid_snk = s_req.data.pid;

// --------------------------------------------------------------------------------
// -- Mux command
// --------------------------------------------------------------------------------
always_comb begin
    seq_snk_valid = seq_snk_ready & ready_src[host_snk] & valid_snk;
    ready_snk = seq_snk_ready & ready_src[host_snk];
end

for(genvar i = 0; i < 2; i++) begin
    assign valid_src[i] = (host_snk == i) ? seq_snk_valid : 1'b0;
    assign request_src[i] = request_snk;
end

queue #(
    .QTYPE(logic [1+PID_BITS+LEN_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_snk (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(seq_snk_valid),
    .rdy_snk(seq_snk_ready),
    .data_snk({host_snk, pid_snk, len_snk}),
    .val_src(seq_src_valid),
    .rdy_src(seq_src_ready),
    .data_src({host_next, pid_next, len_next})
);

// --------------------------------------------------------------------------------
// -- Mux data
// --------------------------------------------------------------------------------
localparam integer BEAT_LOG_BITS = $clog2(AXI_NET_BITS/8);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

logic host_C, host_N;
logic [LEN_BITS-BEAT_LOG_BITS:0] cnt_C, cnt_N;
logic [LEN_BITS-BEAT_LOG_BITS:0] n_beats_C, n_beats_N;

logic tr_done;
logic tmp_tlast;

logic [AXI_NET_BITS-1:0] s_axis_wr_tdata;
logic [AXI_NET_BITS/8-1:0] s_axis_wr_tkeep;
logic [PID_BITS-1:0] s_axis_wr_tid;
logic s_axis_wr_tlast;
logic s_axis_wr_tvalid;
logic s_axis_wr_tready;

logic [1:0][AXI_NET_BITS-1:0] m_axis_wr_tdata;
logic [1:0][AXI_NET_BITS/8-1:0] m_axis_wr_tkeep;
logic [1:0][PID_BITS-1:0] m_axis_wr_tid;
logic [1:0] m_axis_wr_tlast;
logic [1:0] m_axis_wr_tvalid;
logic [1:0] m_axis_wr_tready;

// --------------------------------------------------------------------------------
// -- I/O !!! interface 
// --------------------------------------------------------------------------------

assign s_axis_wr_tvalid = s_axis_wr.tvalid;
assign s_axis_wr_tdata  = s_axis_wr.tdata;
assign s_axis_wr_tkeep  = s_axis_wr.tkeep;
assign s_axis_wr_tid    = s_axis_wr.tid;
assign s_axis_wr_tlast  = s_axis_wr.tlast;
assign s_axis_wr.tready = s_axis_wr_tready;

// REG
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;
    end
    else begin
        state_C <= state_N;
        host_C <= host_N;
        cnt_C <= cnt_N;
        n_beats_C <= n_beats_N;
    end
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = (seq_src_ready) ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = tr_done ? (seq_src_ready ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// DP
always_comb begin: DP
    cnt_N = cnt_C;
    host_N = host_C;
    n_beats_N = n_beats_C;

    // Transfer done
    tr_done = (cnt_C == n_beats_C) && (s_axis_wr_tvalid & s_axis_wr_tready);

    seq_src_valid = 1'b0;

    case(state_C)
        ST_IDLE: begin
            cnt_N = 0;
            if(seq_src_ready) begin
                seq_src_valid = 1'b1;
                host_N = host_next;
                cnt_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
            end
        end
            
        ST_MUX: begin
            if(tr_done) begin
                cnt_N = 0;
                if(seq_src_ready) begin
                    seq_src_valid = 1'b1;
                    host_N = host_next;
                    cnt_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
                end
            end
            else begin
                cnt_N = (s_axis_wr_tvalid & s_axis_wr_tready) ? cnt_C - 1 : cnt_C;
            end
        end
    
    endcase
end

// Mux
for(genvar i = 0; i < 2; i++) begin
    assign m_axis_wr_tvalid[i] = (state_C == ST_MUX) ? ((i == host_C) ? s_axis_wr_tvalid : 1'b0) : 1'b0;
    assign m_axis_wr_tdata[i] = s_axis_wr_tdata;
    assign m_axis_wr_tkeep[i] = s_axis_wr_tkeep;
    assign m_axis_wr_tid[i]   = s_axis_wr_tid;
    assign m_axis_wr_tlast[i] = s_axis_wr_tlast;
end

assign s_axis_wr_tready = (state_C == ST_MUX) ? (host_C ? m_axis_wr_tready[1] : 1'b1) : 1'b0;

// SEND path
meta_queue #(.DATA_BITS($bits(req_t))) inst_meta_rq (.aclk(aclk), .aresetn(aresetn), .s_meta(req_rq), .m_meta(m_req_rq)); 

axisr_data_fifo_512 inst_data_rq (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(m_axis_wr_tvalid[0]),
    .s_axis_tready(m_axis_wr_tready[0]),
    .s_axis_tdata(m_axis_wr_tdata[0]),
    .s_axis_tkeep(m_axis_wr_tkeep[0]),
    .s_axis_tid  (m_axis_wr_tid[0]),
    .s_axis_tlast(m_axis_wr_tlast[0]),
    .m_axis_tvalid(m_axis_rq.tvalid),
    .m_axis_tready(m_axis_rq.tready),
    .m_axis_tdata(m_axis_rq.tdata),
    .m_axis_tkeep(m_axis_rq.tkeep),
    .m_axis_tid  (m_axis_rq.tid),
    .m_axis_tlast(m_axis_rq.tlast)
);

// RDMA path
meta_queue #(.DATA_BITS($bits(req_t))) inst_meta_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(req_wr), .m_meta(m_req_wr)); 

axisr_data_fifo_512 inst_data_wr (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(m_axis_wr_tvalid[1]),
    .s_axis_tready(m_axis_wr_tready[1]),
    .s_axis_tdata(m_axis_wr_tdata[1]),
    .s_axis_tkeep(m_axis_wr_tkeep[1]),
    .s_axis_tid  (m_axis_wr_tid[1]),
    .s_axis_tlast(m_axis_wr_tlast[1]),
    .m_axis_tvalid(m_axis_wr.tvalid),
    .m_axis_tready(m_axis_wr.tready),
    .m_axis_tdata(m_axis_wr.tdata),
    .m_axis_tkeep(m_axis_wr.tkeep),
    .m_axis_tid  (m_axis_wr.tid),
    .m_axis_tlast(m_axis_wr.tlast)
);



endmodule
