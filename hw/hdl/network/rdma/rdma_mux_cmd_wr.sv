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
 * @brief   RDMA WR multiplexer
 *
 * Multiplexing of the RDMA write commands and data
 */
module rdma_mux_cmd_wr (
    input  logic            aclk,
    input  logic            aresetn,
    
    metaIntf.s              s_req,
    metaIntf.m              m_req [N_REGIONS],
    AXI4S.s                 s_axis_wr,
    AXI4SR.m                m_axis_wr [N_REGIONS]
);

logic [N_REGIONS-1:0] ready_src;
logic [N_REGIONS-1:0] valid_src;
logic ready_snk;
logic valid_snk;
req_t [N_REGIONS-1:0] request_src;
req_t request_snk;

logic seq_snk_valid;
logic seq_snk_ready;
logic seq_src_valid;
logic seq_src_ready;


logic [PID_BITS-1:0] pid_snk;
logic [PID_BITS-1:0] pid_next;
logic [N_REGIONS_BITS-1:0] vfid_snk;
logic [N_REGIONS_BITS-1:0] vfid_next;
logic [LEN_BITS-1:0] len_snk;
logic [LEN_BITS-1:0] len_next;
logic host_snk;
logic ctl_snk;
logic ctl_next;

metaIntf #(.STYPE(req_t)) req_que [N_REGIONS] ();

// --------------------------------------------------------------------------------
// I/O !!! interface 
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign req_que[i].valid = valid_src[i];
    assign ready_src[i] = req_que[i].ready;
    assign req_que[i].data = request_src[i];  

    meta_queue #(.DATA_BITS($bits(req_t))) inst_meta_que (.aclk(aclk), .aresetn(aresetn), .s_meta(req_que[i]), .m_meta(m_req[i])); 
end

assign valid_snk = s_req.valid;
assign s_req.ready = ready_snk;

assign request_snk = s_req.data;
assign pid_snk = s_req.data.pid;
assign vfid_snk = s_req.data.vfid;
assign len_snk = s_req.data.len[LEN_BITS-1:0];
assign host_snk = s_req.data.host;
assign ctl_snk = s_req.data.ctl;

// --------------------------------------------------------------------------------
// Mux command
// --------------------------------------------------------------------------------
always_comb begin
    seq_snk_valid = seq_snk_ready & ready_src[vfid_snk] & valid_snk;
    ready_snk = seq_snk_ready & ready_src[vfid_snk];
end

for(genvar i = 0; i < N_REGIONS; i++) begin
    assign valid_src[i] = (vfid_snk == i) ? seq_snk_valid : 1'b0;
    assign request_src[i] = request_snk;
end

queue #(
    .QTYPE(logic [1+N_REGIONS_BITS+PID_BITS+LEN_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_snk (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(seq_snk_valid),
    .rdy_snk(seq_snk_ready),
    .data_snk({ctl_snk, vfid_snk, pid_snk, len_snk}),
    .val_src(seq_src_valid),
    .rdy_src(seq_src_ready),
    .data_src({ctl_next, vfid_next, pid_next, len_next})
);

// --------------------------------------------------------------------------------
// Mux data
// --------------------------------------------------------------------------------
localparam integer BEAT_LOG_BITS = $clog2(AXI_NET_BITS/8);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

logic [PID_BITS-1:0] pid_C, pid_N;
logic [N_REGIONS_BITS-1:0] vfid_C, vfid_N;
logic [LEN_BITS-BEAT_LOG_BITS:0] cnt_C, cnt_N;
logic [LEN_BITS-BEAT_LOG_BITS:0] n_beats_C, n_beats_N;
logic ctl_C, ctl_N;

logic tr_done;
logic tmp_tlast;

logic [AXI_NET_BITS-1:0] s_axis_wr_tdata;
logic [AXI_NET_BITS/8-1:0] s_axis_wr_tkeep;
logic s_axis_wr_tlast;
logic s_axis_wr_tvalid;
logic s_axis_wr_tready;

logic [N_REGIONS-1:0][AXI_NET_BITS-1:0] m_axis_wr_tdata;
logic [N_REGIONS-1:0][AXI_NET_BITS/8-1:0] m_axis_wr_tkeep;
logic [N_REGIONS-1:0][PID_BITS-1:0] m_axis_wr_tid;
logic [N_REGIONS-1:0] m_axis_wr_tlast;
logic [N_REGIONS-1:0] m_axis_wr_tvalid;
logic [N_REGIONS-1:0] m_axis_wr_tready;

// --------------------------------------------------------------------------------
// I/O !!! interface 
// --------------------------------------------------------------------------------

for(genvar i = 0; i < N_REGIONS; i++) begin 
    axisr_data_fifo_512 inst_data_que (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(m_axis_wr_tvalid[i]),
        .s_axis_tready(m_axis_wr_tready[i]),
        .s_axis_tdata(m_axis_wr_tdata[i]),
        .s_axis_tkeep(m_axis_wr_tkeep[i]),
        .s_axis_tid(m_axis_wr_tid[i]),
        .s_axis_tlast(m_axis_wr_tlast[i]),
        .m_axis_tvalid(m_axis_wr[i].tvalid),
        .m_axis_tready(m_axis_wr[i].tready),
        .m_axis_tdata(m_axis_wr[i].tdata),
        .m_axis_tkeep(m_axis_wr[i].tkeep),
        .m_axis_tid(m_axis_wr[i].tid),
        .m_axis_tlast(m_axis_wr[i].tlast)
    );
end

assign s_axis_wr_tvalid = s_axis_wr.tvalid;
assign s_axis_wr_tdata  = s_axis_wr.tdata;
assign s_axis_wr_tkeep  = s_axis_wr.tkeep;
assign s_axis_wr_tlast  = s_axis_wr.tlast;
assign s_axis_wr.tready = s_axis_wr_tready;

// REG
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;
    end
    else begin
        state_C <= state_N;
        cnt_C <= cnt_N;
        pid_C <= pid_N;
        vfid_C <= vfid_N;
        n_beats_C <= n_beats_N;
        ctl_C <= ctl_N;
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
    pid_N = pid_C;
    vfid_N = vfid_C;
    n_beats_N = n_beats_C;
    ctl_N = ctl_C;

    // Transfer done
    tr_done = (cnt_C == n_beats_C) && (s_axis_wr_tvalid & s_axis_wr_tready);

    seq_src_valid = 1'b0;

    // Last gen
    tmp_tlast = 1'b0;

    case(state_C)
        ST_IDLE: begin
            cnt_N = 0;
            if(seq_src_ready) begin
                seq_src_valid = 1'b1;
                pid_N = pid_next;
                vfid_N = vfid_next;
                n_beats_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
                ctl_N = ctl_next;
            end
        end
            
        ST_MUX: begin
            if(tr_done) begin
                cnt_N = 0;
                if(seq_src_ready) begin
                    seq_src_valid = 1'b1;
                    pid_N = pid_next;
                    vfid_N = vfid_next;
                    n_beats_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
                    ctl_N = ctl_next;
                end
            end
            else begin
                cnt_N = (s_axis_wr_tvalid & s_axis_wr_tready) ? cnt_C + 1 : cnt_C;
            end

            if(ctl_C) begin
                tmp_tlast = (cnt_C == n_beats_C) ? 1'b1 : 1'b0;
            end
        end
    
    endcase
end

// Mux
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign m_axis_wr_tvalid[i] = (state_C == ST_MUX) ? ((i == vfid_C) ? s_axis_wr_tvalid : 1'b0) : 1'b0;
    assign m_axis_wr_tdata[i] = s_axis_wr_tdata;
    assign m_axis_wr_tkeep[i] = s_axis_wr_tkeep;
    assign m_axis_wr_tid[i] = pid_C;
    assign m_axis_wr_tlast[i] = tmp_tlast;
end

assign s_axis_wr_tready = (state_C == ST_MUX) ? m_axis_wr_tready[vfid_C] : 1'b0;

/*
logic [31:0] cnt_s_req;
logic [31:0] cnt_m_req;
logic [31:0] cnt_req_que;
logic [31:0] cnt_s_axis_wr;
logic [31:0] cnt_m_axis_wr;
logic [31:0] cnt_seq_snk;
logic [31:0] cnt_seq_src;
logic [31:0] cnt_m_axis_wr_que;

always_ff @(posedge aclk) begin
    if(~aresetn) begin
        cnt_s_req <= 0;
        cnt_m_req <= 0;
        cnt_req_que <= 0;
        cnt_s_axis_wr <= 0;
        cnt_m_axis_wr <= 0;
        cnt_seq_snk <= 0;
        cnt_seq_src <= 0;
        cnt_m_axis_wr_que <= 0;
    end
    else begin
        cnt_s_req <= s_req.valid & s_req.ready ? cnt_s_req + 1 : cnt_s_req;
        cnt_m_req <= m_req[0].valid & m_req[0].ready ? cnt_m_req + 1 : cnt_m_req;
        cnt_req_que <= req_que[0].valid & req_que[0].ready ? cnt_req_que + 1 : cnt_req_que;
        cnt_s_axis_wr <= s_axis_wr.tvalid & s_axis_wr.tready ? cnt_s_axis_wr + 1 : cnt_s_axis_wr;
        cnt_m_axis_wr <= m_axis_wr[0].tvalid & m_axis_wr[0].tready ? cnt_m_axis_wr + 1 : cnt_m_axis_wr;
        cnt_seq_snk <= seq_snk_valid & seq_snk_ready ? cnt_seq_snk + 1 : cnt_seq_snk;
        cnt_seq_src <= seq_src_valid & seq_src_ready ? cnt_seq_src + 1 : cnt_seq_src;
        cnt_m_axis_wr_que <= m_axis_wr_tvalid[0] & m_axis_wr_tready[0] ? cnt_m_axis_wr_que + 1 : cnt_m_axis_wr_que;
    end
end

vio_mux inst_vio_mux (
    .clk(aclk),
    .probe_in0(s_req.valid),
    .probe_in1(s_req.ready),
    .probe_in2(m_req[0].valid),
    .probe_in3(m_req[0].ready),
    .probe_in4(req_que[0].valid),
    .probe_in5(req_que[0].ready),
    .probe_in6(cnt_s_req), // 32
    .probe_in7(cnt_m_req), // 32
    .probe_in8(cnt_req_que), // 32
    .probe_in9(s_axis_wr.tvalid),
    .probe_in10(s_axis_wr.tready),
    .probe_in11(s_axis_wr.tlast),
    .probe_in12(cnt_s_axis_wr), // 32
    .probe_in13(m_axis_wr[0].tvalid),
    .probe_in14(m_axis_wr[0].tready),
    .probe_in15(m_axis_wr[0].tlast),
    .probe_in16(cnt_m_axis_wr), // 32
    .probe_in17(seq_snk_valid),
    .probe_in18(seq_snk_ready),
    .probe_in19(cnt_seq_snk), // 32
    .probe_in20(seq_src_valid),
    .probe_in21(seq_src_ready),
    .probe_in22(cnt_seq_src), // 32
    .probe_in23(state_C),
    .probe_in24(m_axis_wr_tvalid[0]),
    .probe_in25(m_axis_wr_tready[0]),
    .probe_in26(m_axis_wr_tlast[0]),
    .probe_in27(cnt_m_axis_wr_que) // 32
);
*/

endmodule
