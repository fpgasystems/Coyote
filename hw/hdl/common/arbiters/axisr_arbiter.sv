/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
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