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

`ifndef AXIS_ECI_PKT_TO_VC_2VC_SV
`define AXIS_ECI_PKT_TO_VC_2VC_SV

module axis_eci_pkt_to_vc_2vc #(
parameter WORD_WIDTH = 64,

// Dont modify parameters below 
parameter PKT_SIZE = 17,
// PKT_SIZE can vary from 0 to PKT_SIZE ( PKT_SIZE + 1  elements), additional bit might be needed
parameter PKT_SIZE_WIDTH = $clog2(PKT_SIZE) + ( (PKT_SIZE % 2 ) == 0 ),

parameter VC_SIZE = 7,
// VC_SIZE can vary from 0 to VC_SIZE ( VC_SIZE + 1  elements), additional bit might be needed
parameter VC_SIZE_WIDTH = $clog2(VC_SIZE) + ( (VC_SIZE % 2 ) == 0 )
) (
    input logic 			                    aclk,
    input logic 			                    aresetn,

    // ECI packet inputs 
    input logic [PKT_SIZE-1:0][WORD_WIDTH-1:0]  eci_pkt_i,
    input logic [PKT_SIZE_WIDTH-1:0] 	        eci_pkt_size_i,
    input logic 			                    eci_pkt_valid_i,
    output logic 			                    eci_pkt_ready_o,

    // VC packet output
    output logic [VC_SIZE-1:0][WORD_WIDTH-1:0]  vc_pkt_o,
    output logic [VC_SIZE_WIDTH-1:0] 	        vc_pkt_size_o,
    output logic 			                    vc_pkt_valid_o,
    input  logic 			                    vc_pkt_ready_i
);

logic [4:0] cnt_C;
logic [4:0] diff;

logic [VC_SIZE-1:0][WORD_WIDTH-1:0] vc_pkt_tmp;
logic [VC_SIZE_WIDTH-1:0] vc_pkt_size_tmp;
logic vc_pkt_valid_tmp;
logic vc_pkt_ready_tmp;

// REG
always_ff @( posedge aclk ) begin : REG
    if(~aresetn) begin
        cnt_C <= 0;
    end    
    else begin
        if(eci_pkt_valid_i & vc_pkt_ready_tmp) begin
            if(eci_pkt_size_i <= (cnt_C + VC_SIZE))
                cnt_C <= 0;
            else
                cnt_C <= cnt_C + VC_SIZE;
        end
    end
end

// DP
always_comb begin
    vc_pkt_valid_tmp = 1'b0;
    eci_pkt_ready_o = 1'b0;

    if(eci_pkt_valid_i & vc_pkt_ready_tmp) begin
        vc_pkt_valid_tmp = 1'b1;
        if(eci_pkt_size_i <= (cnt_C + VC_SIZE)) begin
            eci_pkt_ready_o = 1'b1;
        end
    end
end

always_comb begin
    vc_pkt_tmp = 0;
    for(logic[4:0] i = 0; i < VC_SIZE; i++) begin
        if(cnt_C + i < eci_pkt_size_i) begin
            vc_pkt_tmp[i] = eci_pkt_i[cnt_C + i]; 
        end
    end

    diff = eci_pkt_size_i - cnt_C;
    if(diff > VC_SIZE)
        vc_pkt_size_tmp = VC_SIZE;
    else
        vc_pkt_size_tmp = diff[2:0];
end

// Slice
axis_reg_array_vc #(
    .N_STAGES(2)
) inst_reg_vc (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axis_tvalid(vc_pkt_valid_tmp),
    .s_axis_tready(vc_pkt_ready_tmp),
    .s_axis_tdata(vc_pkt_tmp),
    .s_axis_tuser(vc_pkt_size_tmp),
    .m_axis_tvalid(vc_pkt_valid_o),
    .m_axis_tready(vc_pkt_ready_i),
    .m_axis_tdata(vc_pkt_o),
    .m_axis_tuser(vc_pkt_size_o)
);
/*
ila_eci_to_vc inst_ila_eci_to_vc (
    .clk(aclk),
    .probe0(eci_pkt_valid_i),
    .probe1(eci_pkt_ready_o),
    .probe2(eci_pkt_size_i), // 5
    .probe3(vc_pkt_valid_o), 
    .probe4(vc_pkt_ready_i), 
    .probe5(vc_pkt_size_o), // 3
    .probe6(cnt_C), // 5
    .probe7(diff), // 5
    .probe8(vc_pkt_valid_tmp),
    .probe9(vc_pkt_ready_tmp),
    .probe10(vc_pkt_size_tmp) // 3
    );
*/
endmodule // axis_eci_pkt_to_vc

`endif
