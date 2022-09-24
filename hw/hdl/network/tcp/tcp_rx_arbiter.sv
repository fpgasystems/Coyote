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
 * @brief   RX arbitration
 * 
 * Arbitrates RX lines.
 *
 */
module tcp_rx_arbiter (
    input  logic 								    aclk,
	input  logic 								    aresetn,

    metaIntf.s                                      s_rd_pkg [N_REGIONS],
    metaIntf.m                                      m_rd_pkg,

    metaIntf.s                                      s_rx_meta,
    metaIntf.m                                      m_rx_meta [N_REGIONS],

    AXI4S.s                                         s_axis_rx,
    AXI4SR.m                                        m_axis_rx [N_REGIONS]
);

`ifdef MULT_REGIONS

// Arb
// --------------------------------------------------------------------------------
logic [N_REGIONS_BITS-1:0] vfid_int;
logic [PID_BITS-1:0] pid_int;
metaIntf #(.STYPE(tcp_rd_pkg_t)) rd_pkg ();
metaIntf #(.STYPE(logic[N_REGIONS_BITS+TCP_LEN_BITS-1:0])) seq_snk ();
metaIntf #(.STYPE(logic[N_REGIONS_BITS+TCP_LEN_BITS-1:0])) seq_src ();

metaIntf #(.STYPE(logic[N_REGIONS_BITS-1:0])) seq_snk_meta ();
metaIntf #(.STYPE(logic[N_REGIONS_BITS-1:0])) seq_src_meta ();

meta_arbiter #(.DATA_BITS($bits(tcp_rd_pkg_t))) inst_meta_arbiter (
  .aclk(aclk),
  .aresetn(aresetn),
  .s_meta(s_rd_pkg),
  .m_meta(rd_pkg),
  .id_out(vfid_int)
);

assign pid_int = rd_pkg.data.pid;

// --------------------------------------------------------------------------------
// Mux
// --------------------------------------------------------------------------------
always_comb begin
    seq_snk.valid = seq_snk.ready & seq_snk_meta.ready & m_rd_pkg.ready & rd_pkg.valid;
    seq_snk_meta.valid = seq_snk.ready & seq_snk_meta.ready & m_rd_pkg.ready & rd_pkg.valid;
    rd_pkg.ready = seq_snk.ready & seq_snk_meta.ready & m_rd_pkg.ready;
end
assign seq_snk.data = {vfid_int, rd_pkg.data.len};
assign seq_snk_meta.data = vfid_int;

assign m_rd_pkg.valid = seq_snk.valid & seq_snk.ready;
assign m_rd_pkg.data = rd_pkg.data;

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
logic [PID_BITS-1:0] pid_C, pid_N;

logic tr_done;

AXI4SR axis_rx [N_REGIONS] ();

for(genvar i = 0; i < N_REGIONS; i++) begin 
    axisr_data_fifo_512 inst_data_que (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(axis_rx.tvalid[i]),
        .s_axis_tready(axis_rx.tready[i]),
        .s_axis_tdata(axis_rx.tdata[i]),
        .s_axis_tkeep(axis_rx.tkeep[i]),
        .s_axis_tid  (axis_rx.tid[i]),
        .s_axis_tlast(axis_rx.tlast[i]),
        .m_axis_tvalid(m_axis_rx[i].tvalid),
        .m_axis_tready(m_axis_rx[i].tready),
        .m_axis_tdata(m_axis_rx[i].tdata),
        .m_axis_tkeep(m_axis_rx[i].tkeep),
        .m_axis_tid  (m_axis_rx[i].tid),
        .m_axis_tlast(m_axis_rx[i].tlast)
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
    pid_C <= pid_N;
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
    pid_N = pid_C;
    vfid_N = vfid_C;
    n_beats_N = n_beats_C;

    // Transfer done
    tr_done = (cnt_C == n_beats_C) && (s_axis_rx.tvalid & s_axis_rx.tready);

    seq_src.valid = 1'b0;

    case(state_C)
        ST_IDLE: begin
            cnt_N = 0;
            if(seq_src.ready) begin
                seq_src.valid = 1'b1;
                pid_N = seq_src.data[TCP_LEN_BITS+N_REGIONS_BITS+:PID_BITS];
                vfid_N = seq_src.data[TCP_LEN_BITS+:N_REGIONS_BITS];
                n_beats_N = (seq_src.data[BEAT_LOG_BITS-1:0] != 0) ? seq_src.data[TCP_LEN_BITS-1:BEAT_LOG_BITS] : seq_src.data[TCP_LEN_BITS-1:BEAT_LOG_BITS] - 1;
            end
        end
            
        ST_MUX: begin
            if(tr_done) begin
                cnt_N = 0;
                if(seq_src.ready) begin
                    seq_src.valid = 1'b1;
                    pid_N = seq_src.data[TCP_LEN_BITS+N_REGIONS_BITS+:PID_BITS];
                    vfid_N = seq_src.data[TCP_LEN_BITS+:N_REGIONS_BITS];
                    n_beats_N = (seq_src.data[BEAT_LOG_BITS-1:0] != 0) ? seq_src.data[TCP_LEN_BITS-1:BEAT_LOG_BITS] : seq_src.data[TCP_LEN_BITS-1:BEAT_LOG_BITS] - 1;
                end
            end
            else begin
                cnt_N = (s_axis_rx.tvalid & s_axis_rx.tready) ? cnt_C + 1 : cnt_C;
            end
        end
    
    endcase
end

// Mux
for(genvar i = 0; i < N_REGIONS; i++) begin
  assign axis_rx[i].tvalid = (state_C == ST_MUX) ? s_axis_rx.tvalid : 1'b0;
  assign axis_rx[i].tdata = s_axis_rx.tdata;
  assign axis_rx[i].tkeep = s_axis_rx.tkeep;
  assign axis_rx[i].tid   = pid_C;
  assign axis_rx[i].tlast = s_axis_rx.tlast;
end

assign s_axis_rx.tready = (state_C == ST_MUX) ? axis_rx[vfid_C].tready : 1'b0;

// --------------------------------------------------------------------------------
// Mux meta
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_REGIONS; i++) begin
  assign m_rx_meta[i].valid = (i == seq_src_meta.data) ? s_rx_meta.valid : 1'b0;
  assign m_rx_meta[i].data = s_rx_meta.data;
end
assign s_rx_meta.ready = m_rx_meta[seq_src_meta.data];
assign seq_src_meta.valid = s_rx_meta.valid & s_rx_meta.ready;

`else

`META_ASSIGN(s_rd_pkg[0], m_rd_pkg)
`META_ASSIGN(s_rx_meta, m_rx_meta[0])
// TODO: Loop pid
`AXISR_ASSIGN_FIRST(s_axis_rx, m_axis_rx[0], 0) 

`endif

endmodule