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

module user_arbiter_top #(
    parameter integer                   N_CPID = 2
) (

    metaIntf.s                          s_seq_rd, // host only
    metaIntf.s                          s_seq_wr,

    // Data host
`ifdef EN_STRM
    AXI4SR.s                            s_host_sink_axis,
    AXI4SR.m                            m_host_sink_axis [N_STRM_AXI],

    AXI4SR.s                            s_host_src_axis [N_STRM_AXI],
    AXI4SR.m                            m_host_src_axis,
`endif

    // Data card
`ifdef EN_MEM
    AXI4SR.s                            s_card_sink_axis [N_CARD_AXI],
    AXI4SR.m                            m_card_sink_axis [N_CARD_AXI],

    AXI4SR.s                            s_card_src_axis [N_CARD_AXI],
    AXI4SR.m                            m_card_src_axis [N_CARD_AXI],
`endif

    input  logic    					aclk,    
	input  logic    					aresetn
);

`ifdef EN_STRM

    queue_meta #(
        .QDEPTH(N_OUTSTANDING)
    ) inst_seq_que_rd (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_meta(s_seq_rd),
        .m_meta(seq_rd)
    );

    queue_meta #(
        .QDEPTH(N_OUTSTANDING)
    ) inst_seq_que_wr (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_meta(s_seq_wr),
        .m_meta(seq_wr)
    );

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
                state_N = (seq_src_ready) ? ST_MUX : ST_IDLE;

            ST_MUX:
                state_N = tr_done ? (seq_src_ready ? ST_MUX : ST_IDLE) : ST_MUX;

        endcase // state_C
    end

`endif

`ifdef EN_MEM

    for(genvar i = 0; i < N_CARD_AXI; i++) begin
        `AXISR_ASSIGN(s_card_axis[i], m_card_axis[i])
    end

`endif

endmodule