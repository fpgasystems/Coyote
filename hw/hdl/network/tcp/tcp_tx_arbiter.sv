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
 * @brief   TCP TX multiplexer
 *
 */
module tcp_tx_arbiter (
    input  logic                        aclk,
    input  logic                        aresetn,
    
    metaIntf.s                          rx_meta,
    metaIntf.m                          m_rx_meta [N_REGIONS],
    AXI4S.s                             axis_rx_data,
    AXI4S.m                             m_rx_data [N_REGIONS],

    output logic [N_REGIONS-1:0]        m_wr_rdy
);

logic [N_REGIONS-1:0] ready_src;
logic [N_REGIONS-1:0] valid_src;
logic ready_snk;
logic valid_snk;
req_t [N_REGIONS-1:0] request_src;
tcp_meta_r_t request_snk;

logic seq_snk_valid;
logic seq_snk_ready;
logic seq_src_valid;
logic seq_src_ready;


logic [N_REGIONS_BITS-1:0] vfid_snk;
logic [N_REGIONS_BITS-1:0] vfid_next;
logic [LEN_BITS-1:0] len_snk;
logic [LEN_BITS-1:0] len_next;
logic host_snk;
logic last_snk;
logic last_next;

metaIntf #(.STYPE(req_t)) req_que [N_REGIONS] ();

// --------------------------------------------------------------------------------
// I/O !!! interface 
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign req_que[i].valid = valid_src[i];
    assign ready_src[i] = req_que[i].ready;
    assign req_que[i].data = request_src[i];  

    meta_queue #(.DATA_BITS($bits(req_t))) inst_meta_que (.aclk(aclk), .aresetn(aresetn), .s_meta(req_que[i]), .m_meta(m_rx_meta[i])); 
end

assign valid_snk = rx_meta.valid;
assign rx_meta.ready = ready_snk;
assign request_snk = rx_meta.data;

assign vfid_snk = rx_meta.data.vfid;
assign len_snk = rx_meta.data.len[LEN_BITS-1:0];

// --------------------------------------------------------------------------------
// Mux command
// --------------------------------------------------------------------------------
always_comb begin
    seq_snk_valid = seq_snk_ready & ready_src[vfid_snk] & valid_snk;
    ready_snk = seq_snk_ready & ready_src[vfid_snk];
end

for(genvar i = 0; i < N_REGIONS; i++) begin
    assign valid_src[i] = (vfid_snk == i) ? seq_snk_valid : 1'b0;
    
    assign request_src[i].vfid = request_snk.vfid;
    assign request_src[i].pid = request_snk.pid;
    assign request_src[i].dest = request_snk.dest;
    assign request_src[i].len = request_snk.len;

    assign request_src[i].opcode = TCP_OPCODE;
    assign request_src[i].mode = 1'b0;
    assign request_src[i].rdma = 1'b0;
    assign request_src[i].remote = 1'b1;
    assign request_src[i].last = 1'b1;
    assign request_src[i].strm = STRM_CARD;
    assign request_src[i].vaddr = 0;
    assign request_src[i].actv = 1'b1;
    assign request_src[i].host = 1'b0;
    assign request_src[i].offs = 0;
    assign request_src[i].rsrvd = 0;
end

queue_stream #(
    .QTYPE(logic [N_REGIONS_BITS+LEN_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_snk (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(seq_snk_valid),
    .rdy_snk(seq_snk_ready),
    .data_snk({vfid_snk, len_snk}),
    .val_src(seq_src_valid),
    .rdy_src(seq_src_ready),
    .data_src({vfid_next, len_next})
);

// --------------------------------------------------------------------------------
// Mux data
// --------------------------------------------------------------------------------

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

logic [N_REGIONS_BITS-1:0] vfid_C, vfid_N;
logic [LEN_BITS-BEAT_LOG_BITS:0] cnt_C, cnt_N;

logic tr_done;
logic tmp_tlast;

logic [AXI_NET_BITS-1:0] s_axis_wr_tdata;
logic [AXI_NET_BITS/8-1:0] s_axis_wr_tkeep;
logic s_axis_wr_tlast;
logic s_axis_wr_tvalid;
logic s_axis_wr_tready;

logic [N_REGIONS-1:0][AXI_NET_BITS-1:0] m_axis_wr_tdata;
logic [N_REGIONS-1:0][AXI_NET_BITS/8-1:0] m_axis_wr_tkeep;
logic [N_REGIONS-1:0] m_axis_wr_tlast;
logic [N_REGIONS-1:0] m_axis_wr_tvalid;
logic [N_REGIONS-1:0] m_axis_wr_tready;

logic [N_REGIONS-1:0][31:0] used;

// --------------------------------------------------------------------------------
// I/O !!! interface 
// --------------------------------------------------------------------------------

for(genvar i = 0; i < N_REGIONS; i++) begin 
    axis_data_fifo_512_used inst_data_que (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(m_axis_wr_tvalid[i]),
        .s_axis_tready(m_axis_wr_tready[i]),
        .s_axis_tdata(m_axis_wr_tdata[i]),
        .s_axis_tkeep(m_axis_wr_tkeep[i]),
        .s_axis_tlast(m_axis_wr_tlast[i]),
        .m_axis_tvalid(m_rx_data[i].tvalid),
        .m_axis_tready(m_rx_data[i].tready),
        .m_axis_tdata(m_rx_data[i].tdata),
        .m_axis_tkeep(m_rx_data[i].tkeep),
        .m_axis_tlast(m_rx_data[i].tlast),
        .axis_wr_data_count(used[i])
    );

    assign m_wr_rdy[i] = used[i] <= RDMA_WR_NET_THRS; 
end

assign s_axis_wr_tvalid = axis_rx_data.tvalid;
assign s_axis_wr_tdata  = axis_rx_data.tdata;
assign s_axis_wr_tkeep  = axis_rx_data.tkeep;
assign s_axis_wr_tlast  = axis_rx_data.tlast;
assign axis_rx_data.tready = s_axis_wr_tready;

// REG
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;
    end
    else begin
        state_C <= state_N;
        cnt_C <= cnt_N;
        vfid_C <= vfid_N;
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
    vfid_N = vfid_C;

    // Transfer done
    tr_done = (cnt_C == 0) && (s_axis_wr_tvalid & s_axis_wr_tready);

    seq_src_ready = 1'b0;

    // Last gen
    tmp_tlast = 1'b0;

    case(state_C)
        ST_IDLE: begin
            if(seq_src_valid) begin
                seq_src_ready = 1'b1;
                vfid_N = vfid_next;
                cnt_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
            end
        end
            
        ST_MUX: begin
            if(tr_done) begin
                cnt_N = 0;
                if(seq_src_valid) begin
                    seq_src_ready = 1'b1;
                    vfid_N = vfid_next;
                    cnt_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
                end
            end
            else begin
                cnt_N = (s_axis_wr_tvalid & s_axis_wr_tready) ? cnt_C - 1 : cnt_C;
            end

            tmp_tlast = (cnt_C == 0) ? 1'b1 : 1'b0;
        end
    
    endcase
end

// Mux
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign m_axis_wr_tvalid[i] = (state_C == ST_MUX) ? ((i == vfid_C) ? s_axis_wr_tvalid : 1'b0) : 1'b0;
    assign m_axis_wr_tdata[i] = s_axis_wr_tdata;
    assign m_axis_wr_tkeep[i] = s_axis_wr_tkeep;
    assign m_axis_wr_tlast[i] = tmp_tlast;
end

assign s_axis_wr_tready = (state_C == ST_MUX) ? m_axis_wr_tready[vfid_C] : 1'b0;

endmodule
