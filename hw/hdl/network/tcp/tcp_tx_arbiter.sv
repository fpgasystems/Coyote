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
 * @brief   TX arbitration
 * 
 * Arbitrates TX lines.
 *
 */
module tcp_tx_arbiter (
    input  logic 									aclk,
	  input  logic 									aresetn,

    metaIntf.s                                      s_tx_meta [N_REGIONS],
    metaIntf.m                                      m_tx_meta,

    metaIntf.s                                      s_tx_stat,
    metaIntf.m                                      m_tx_stat [N_REGIONS],

    AXI4SR.s                                        s_axis_tx [N_REGIONS],
    AXI4S.m                                         m_axis_tx
);

`ifdef MULT_REGIONS

// --------------------------------------------------------------------------------
// Arb
// --------------------------------------------------------------------------------
logic [N_REGIONS_BITS-1:0] vfid_int;
metaIntf #(.STYPE(tcp_tx_meta_t)) tx_meta ();
metaIntf #(.STYPE(logic[N_REGIONS_BITS+TCP_LEN_BITS-1:0])) seq_snk ();
metaIntf #(.STYPE(logic[N_REGIONS_BITS+TCP_LEN_BITS-1:0])) seq_src ();

metaIntf #(.STYPE(logic[N_REGIONS_BITS-1:0])) seq_snk_meta ();
metaIntf #(.STYPE(logic[N_REGIONS_BITS-1:0])) seq_src_meta ();

meta_arbiter #(.DATA_BITS($bits(tcp_tx_meta_t))) inst_meta_arbiter (
  .aclk(aclk),
  .aresetn(aresetn),
  .s_meta(s_tx_meta),
  .m_meta(tx_meta),
  .id_out(vfid_int)
);

// --------------------------------------------------------------------------------
// Mux
// --------------------------------------------------------------------------------
always_comb begin
    seq_snk.valid = seq_snk.ready & seq_snk_meta.ready & m_tx_meta.ready & tx_meta.valid;
    seq_snk_meta.valid = seq_snk.ready & seq_snk_meta.ready & m_tx_meta.ready & tx_meta.valid;
    tx_meta.ready = seq_snk.ready & seq_snk_meta.ready & m_tx_meta.ready;
end
assign seq_snk.data = {vfid_int, tx_meta.data.len};
assign seq_snk_meta.data = vfid_int;

assign m_tx_meta.valid = seq_snk_valid & seq_snk_ready;
assign m_tx_meta.data = tx_meta.data;

queue #(
    .QTYPE(logic [N_REGIONS_BITS+TCP_LEN_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_snk (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(seq_snk.valid),
    .rdy_snk(seq_snk.ready),
    .data_snk(seq_snk.data),
    .val_src(seq_src.valid),
    .rdy_src(seq_src.ready),
    .data_src(seq_src.data)
);

queue #(
    .QTYPE(logic [N_REGIONS_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_snk_meta (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(seq_snk_meta.valid),
    .rdy_snk(seq_snk_meta.ready),
    .data_snk(seq_snk_meta.data),
    .val_src(seq_src_meta.valid),
    .rdy_src(seq_src_meta.ready),
    .data_src(seq_src_meta.data)
);

// --------------------------------------------------------------------------------
// Mux data
// --------------------------------------------------------------------------------
localparam integer BEAT_LOG_BITS = $clog2(AXI_NET_BITS/8);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

logic [N_REGIONS_BITS-1:0] vfid_C, vfid_N;
logic [TCP_LEN_BITS-BEAT_LOG_BITS:0] cnt_C, cnt_N;
logic [TCP_LEN_BITS-BEAT_LOG_BITS:0] n_beats_C, n_beats_N;

logic tr_done;

AXI4S axis_tx [N_REGIONS] ();

for(genvar i = 0; i < N_REGIONS; i++) begin 
    axis_data_fifo_512 inst_data_que (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_axis_tx.tvalid[i]),
        .s_axis_tready(s_axis_tx.tready[i]),
        .s_axis_tdata(s_axis_tx.tdata[i]),
        .s_axis_tkeep(s_axis_tx.tkeep[i]),
        .s_axis_tlast(s_axis_tx.tlast[i]),
        .m_axis_tvalid(axis_tx[i].tvalid),
        .m_axis_tready(axis_tx[i].tready),
        .m_axis_tdata(axis_tx[i].tdata),
        .m_axis_tkeep(axis_tx[i].tkeep),
        .m_axis_tlast(axis_tx[i].tlast)
    );
end

// REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;
end
else
	  state_C <= state_N;
    cnt_C <= cnt_N;
    vfid_C <= vfid_N;
    n_beats_C <= n_beats_N;
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = (seq_src.ready) ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = tr_done ? (seq_src.ready ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// DP
always_comb begin: DP
    cnt_N = cnt_C;
    vfid_N = vfid_C;
    n_beats_N = n_beats_C;

    // Transfer done
    tr_done = (cnt_C == n_beats_C) && (m_axis_tx.tvalid & m_axis_tx.tready);

    seq_src.valid = 1'b0;

    case(state_C)
        ST_IDLE: begin
            cnt_N = 0;
            if(seq_src.ready) begin
                seq_src.valid = 1'b1;
                vfid_N = seq_src.data[TCP_LEN_BITS+:N_REGIONS_BITS];
                n_beats_N = (seq_src.data[BEAT_LOG_BITS-1:0] != 0) ? seq_src.data[TCP_LEN_BITS-1:BEAT_LOG_BITS] : seq_src.data[TCP_LEN_BITS-1:BEAT_LOG_BITS] - 1;
            end
        end
            
        ST_MUX: begin
            if(tr_done) begin
                cnt_N = 0;
                if(seq_src.ready) begin
                    seq_src.valid = 1'b1;
                    vfid_N = seq_src.data[TCP_LEN_BITS+:N_REGIONS_BITS];
                    n_beats_N = (seq_src.data[BEAT_LOG_BITS-1:0] != 0) ? seq_src.data[TCP_LEN_BITS-1:BEAT_LOG_BITS] : seq_src.data[TCP_LEN_BITS-1:BEAT_LOG_BITS] - 1;
                end
            end
            else begin
                cnt_N = (m_axis_tx.tvalid & m_axis_tx.tready) ? cnt_C + 1 : cnt_C;
            end
        end
    
    endcase
end

// Mux
assign m_axis_tx.tvalid = (state_C == ST_MUX) ? axis_tx[vfid_C].tvalid : 1'b0;
assign m_axis_tx.tdata = axis_tx[vfid_C].tdata;
assign m_axis_tx.tkeep = axis_tx[vfid_C].tkeep;
assign m_axis_tx.tlast = axis_tx[vfid_C].tlast;

for(genvar i = 0; i < N_REGIONS; i++) begin
  assign axis_tx[i].tready = (state_C == ST_MUX) ? m_axis_tx.tready : 1'b0;
end

// --------------------------------------------------------------------------------
// Mux meta
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_REGIONS; i++) begin
  assign m_tx_stat[i].valid = (i == seq_src_meta.data) ? s_tx_stat.valid : 1'b0;
  assign m_tx_stat[i].data = s_tx_stat.data;
end
assign s_tx_stat.ready = m_tx_stat[seq_src_meta.data];
assign seq_src_meta.valid = s_tx_stat.valid & s_tx_stat.ready;

`else

`META_ASSIGN(s_tx_meta[0], m_tx_meta)
`META_ASSIGN(s_tx_stat, m_tx_stat[0])
`AXIS_ASSIGN(s_axis_tx[0], m_axis_tx)

`endif

endmodule