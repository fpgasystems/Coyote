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

module user_seq_rd (

    metaIntf.s                          s_seq_rd,

    // Data host
    AXI4SR.s                            s_host_sink_axis,
    AXI4SR.m                            m_host_sink_axis [N_STRM_AXI],

    input  logic    					aclk,    
	input  logic    					aresetn
);

localparam integer BEAT_LOG_BITS = $clog2(AXI_NET_BITS/8);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

logic [LEN_BITS-BEAT_LOG_BITS:0] cnt_C, cnt_N;

queue_meta #(
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que (
    .s_meta(s_seq_rd),
    .m_meta(seq_rd),
    .aclk(aclk),
    .aresetn(aresetn)
)

// REG
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;
    end
    else begin
        state_C <= state_N;
        cnt_C <= cnt_N;
    end
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = (seq_rd.valid) ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = tr_done ? (seq_rd.valid ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// DP
always_comb begin: DP
    cnt_N = cnt_C;

    tr_done = (cnt_C == 0) && (s_host_sink_axis.tvalid & s_host_sink_axis.tready);

    case(state_C)
        ST_IDLE: begin
            if(seq_rd.valid) begin
                seq_rd.ready = 1'b1;
                cnt_N = (seq_rd.data.len[BEAT_LOG_BITS-1:0] != 0) ? seq_rd.data.len[LEN_BITS-1:BEAT_LOG_BITS] : seq_rd.data.len[LEN_BITS-1:BEAT_LOG_BITS] - 1;
            end
        end

        ST_MUX: begin
            if(tr_done) begin
                
            end
        end

    endcase

end



endmodule