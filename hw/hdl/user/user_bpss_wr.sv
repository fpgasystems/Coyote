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

module user_bpss_wr #(
    parameter integer                   N_CPID = 2
) (
    input  logic    					aclk,    
	input  logic    					aresetn,

	// Bypass
    metaIntf.s                          s_req [N_CPID],
    metaIntf.m                          m_req,

    AXI4SR.s                            s_axis [N_CPID],
    AXI4SR.m                            m_axis
);

AXI4SR axis_s0 [N_CPID] ();
logic [N_CPID-1:0] wxfer;
metaIntf #(.STYPE(req_t)) prsd_req [N_CPID] ();
metaIntf #(.STYPE(req_t)) cred_req [N_CPID] ();

// Credits
for(genvar i = 0; i < N_CPID; i++) begin
    tlb_parser inst_parser_wr (.aclk(aclk), .aresetn(aresetn), .s_req(s_req[i]), .m_req(prsd_req[i]));
    user_credits_wr inst_credits_wr (.aclk(aclk), .aresetn(aresetn), .s_req(prsd_req[i]),  .m_req(cred_req[i]), .wxfer(wxfer[i]));
    user_queue_credits_wr inst_queue_wr (.aclk(aclk), .aresetn(aresetn), .s_axis(s_axis[i]),  .m_axis(axis_s0[i]), .wxfer(wxfer[i]));
end

// Mux
metaIntf #(.STYPE()) mux_wr ();

user_mux_wr #(.N_CPID(N_CPID)) inst_mux_wr (.aclk(aclk), .aresetn(aresetn), .mux(mux_wr), .s_axis(axis_s0),  .m_axis(m_axis));
user_arbiter #(.N_CPID(N_CPID)) inst_arb_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(cred_req), .m_meta(m_req),  .mux(mux_wr)); );
    
endmodule