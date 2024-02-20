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

import eci_cmd_defs::*;

import lynxTypes::*;

/**
 * R mux
 */
module reorder_mux_r (
    input  logic                            aclk,
    input  logic                            aresetn,

    input  logic [1:0][ECI_DATA_BITS-1:0]   axi_out_rdata,
    input  logic [1:0]                      axi_out_rvalid,
    output logic [1:0]                      axi_out_rready,

    output logic [ECI_DATA_BITS-1:0]        axi_in_rdata,
    output logic [ECI_ID_BITS-1:0]          axi_in_rid,
    output logic                            axi_in_rlast,
    output logic [1:0]                      axi_in_rresp,
    output logic                            axi_in_rvalid,
    input  logic                            axi_in_rready,

    metaIntf.s                              mux_r
);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

// -- Internal regs
logic [7:0] cnt_C, cnt_N;
logic mib_C, mib_N;

// -- Internal signals
logic tr_done; 
/*
ila_rd inst_ila_rd (
    .clk(aclk),
    .probe0(axi_out_rdata[0][63:0]), // 64
    .probe1(axi_out_rvalid[0]),
    .probe2(axi_out_rready[0]),
    .probe3(axi_out_rdata[1][63:0]), // 64
    .probe4(axi_out_rvalid[1]),
    .probe5(axi_out_rready[1]),
    .probe6(axi_in_rdata[63:0]), // 64
    .probe7(axi_in_rvalid),
    .probe8(axi_in_rready),
    .probe9(axi_in_rlast)
);
*/
// ----------------------------------------------------------------------------------------------------------------------- 
// Mux 
// ----------------------------------------------------------------------------------------------------------------------- 

always_comb begin
    for(int i = 0; i < 2; i++) begin
        if(state_C == ST_MUX)
          axi_out_rready[i] = (mib_C == i) ? axi_in_rready : 1'b0;   
        else 
          axi_out_rready[i] = 1'b0;
    end

    if(state_C == ST_MUX) begin
        axi_in_rvalid = axi_out_rvalid[mib_C];
    end
    else begin
        axi_in_rvalid = 1'b0;
    end
        
    axi_in_rdata = axi_out_rdata[mib_C];
    axi_in_rlast = (cnt_C == 0);
    axi_in_rid = 0;
    axi_in_rresp = 0;
end

// ----------------------------------------------------------------------------------------------------------------------- 
// FSM
// ----------------------------------------------------------------------------------------------------------------------- 
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;
    cnt_C <= 'X;
    mib_C <= 'X;
end
else
    state_C <= state_N;
    cnt_C <= cnt_N;
    mib_C <= mib_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = mux_r.valid ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = tr_done ? (mux_r.valid ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// -- DP
always_comb begin : DP
  cnt_N = cnt_C;
  mib_N = mib_C;

  // Transfer done
  tr_done = (cnt_C == 0) && (axi_in_rvalid & axi_in_rready);

  // Memory subsystem
  mux_r.ready = 1'b0;

  case(state_C)
    ST_IDLE: begin
      if(mux_r.valid) begin
        mux_r.ready = 1'b1;
        cnt_N = mux_r.data[1+:8];   
        mib_N = mux_r.data[0];
      end   
    end

    ST_MUX: begin
      if(tr_done) begin
        if(mux_r.valid) begin
            mux_r.ready = 1'b1;
            cnt_N = mux_r.data[1+:8];   
            mib_N = mux_r.data[0];
        end 
      end 
      else begin
        cnt_N = (axi_in_rvalid & axi_in_rready) ? cnt_C - 1 : cnt_C;
        mib_N = (axi_in_rvalid & axi_in_rready) ? mib_C ^ 1'b1 : mib_C;
      end
    end

  endcase
end

/*
ila_mux_reorder_rd inst_ila_rd_mux (
    .clk(aclk),
    .probe0(state_C), 
    .probe1(cnt_C), // 8
    .probe2(mib_C), 
    .probe3(tr_done),
    .probe4(mux_r.valid),
    .probe5(mux_r.ready),
    .probe6(axi_out_rvalid[0]),
    .probe7(axi_out_rready[0]),
    .probe8(axi_out_rvalid[1]),
    .probe9(axi_out_rready[1]),
    .probe10(axi_in_rvalid),
    .probe11(axi_in_rready),
    .probe12(axi_in_rlast)
);
*/

endmodule