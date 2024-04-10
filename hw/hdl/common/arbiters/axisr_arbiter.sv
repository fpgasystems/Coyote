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
  * EVEN IF ADVISED OF THE POSSIBILITY OF    SUCH DAMAGE.
  */


`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * @brief  Meta RR arbitration 
 *
 * Round-robin arbitration for generic axis.
 *
 * @param N_ID         Number of arbitrations
 * @param DATA_BITS     Number of arbitrated data bits
 */
module axisr_arbiter #(
    parameter integer                           N_ID = N_REGIONS,
    parameter integer                           DATA_BITS = AXI_DATA_BITS,
    parameter integer                           ID_BITS = AXI_ID_BITS
) (
	input  logic    					        aclk,    
	input  logic    					        aresetn,

	// User logic
    output logic [N_ID-1:0]                     tready_snk,
    input  logic [N_ID-1:0]                     tvalid_snk,
    input  logic [N_ID-1:0][DATA_BITS-1:0]      tdata_snk,
    input  logic [N_ID-1:0][DATA_BITS/8-1:0]    tkeep_snk,
    input  logic [N_ID-1:0]                     tlast_snk,
    input  logic [N_ID-1:0][ID_BITS-1:0]        tid_snk,

    input  logic                                tready_src,
    output logic                                tvalid_src,
    output logic [DATA_BITS-1:0]                tdata_src,
    output logic [DATA_BITS/8-1:0]              tkeep_src,
    output logic                                tlast_src,
    output logic [ID_BITS-1:0]                  tid_src
);

localparam integer N_ID_BITS = clog2s(N_ID);

// Internal
logic [N_ID_BITS-1:0] rr_reg = 0;
logic [N_ID_BITS-1:0] id;

// --------------------------------------------------------------------------------
// RR
// --------------------------------------------------------------------------------
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		rr_reg <= 0;
	end else begin
        if(tvalid_src & tready_src) begin 
            rr_reg <= rr_reg + 1;
            if(rr_reg >= N_ID-1)
                rr_reg <= 0;
        end
	end
end

// DP
always_comb begin
    tready_snk = 0;
    tvalid_src = 1'b0;
    id = 0;

    for(int i = 0; i < N_ID; i++) begin
        if(i+rr_reg >= N_ID) begin
            if(tvalid_snk[i+rr_reg-N_ID]) begin
                tvalid_src = tvalid_snk[i+rr_reg-N_ID];
                id = i+rr_reg-N_ID;
                break;
            end
        end
        else begin
            if(tvalid_snk[i+rr_reg]) begin
                tvalid_src = tvalid_snk[i+rr_reg];
                id = i+rr_reg;
                break;
            end
        end
    end

    tready_snk[id] = tready_src;
    tdata_src = tdata_snk[id];
    tkeep_src = tkeep_snk[id];
    tlast_src = tlast_snk[id];
    tid_src = tid_snk[id];
end

endmodule