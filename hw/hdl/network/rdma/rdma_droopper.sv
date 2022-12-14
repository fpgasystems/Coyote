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

`include "axi_macros.svh"
`include "lynx_macros.svh"

module net_dropper (
`ifdef NET_DROP
    metaIntf.s              drop,
    input  logic            drop_clear,
`endif

    AXI4S.s                 s_axis,
    AXI4S.m                 m_axis,

    input  wire             aclk,
    input  wire             aresetn
);

// ---------------------------------------------------------------------------------------------------
// Dropper
// ---------------------------------------------------------------------------------------------------

`ifdef NET_DROP

// Queue up drop requests
metaIntf #(.STYPE(logic [31:0])) drop_que ();
meta_queue #(.QDEPTH(32)) inst_queue (.aclk(aclk), .aresetn(aresetn), .s_meta(drop), .m_meta(drop_que));

logic [31:0] cnt_C;
logic drop_curr;

// Dropper
always_ff @(posedge aclk) begin
    if(~aresetn) begin
        cnt_C <= 0;
    end
    else begin
        if(drop_clear) begin
            cnt_C <= 0;
        end
        else begin
            cnt_C <= s_axis.tvalid & s_axis.tready & s_axis.tlast ? cnt_C + 1 : cnt_C;
        end
    end
end

drop_que.ready = ((cnt_C + 1) == drop_que.data) && (s_axis.tvalid & s_axis.tready & s_axis.tlast);
drop_curr = ((cnt_C + 1) == drop_que.data) && drop_que.valid;

assign m_axis.tdata = s_axis.tdata;
assign m_axis.tkeep = s_axis.tkeep;
assign m_axis.tlast = s_axis.tlast;
assign m_axis.tvalid = drop_curr ? 1'b0 : s_axis_tvalid;
assign s_axis.tready = drop_curr ? 1'b1 : m_axis.tready;

`else

`AXIS_ASSIGN(s_axis, m_axis)

`endif

endmodule
