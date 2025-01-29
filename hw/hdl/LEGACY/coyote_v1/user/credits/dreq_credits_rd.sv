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
 * @brief   Credit based system for the read requests.
 *
 * Prevents region stalls from propagating to the whole system.
 *
 *  @param DATA_BITS        Size of the data bus
 */
module dreq_credits_rd #(
    parameter integer DATA_BITS = AXI_DATA_BITS
) (
    input  logic            aclk,
    input  logic            aresetn,
    
    // Requests
    metaIntf.s              s_req,
    metaIntf.m              m_req,

    // Data read
    input  logic            xfer
);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_READ} state_t;
logic [0:0] state_C, state_N;

// -- Internal regs
logic [7:0] cred_reg_C, cred_reg_N;
logic [BLEN_BITS-1:0] cnt_C, cnt_N;

// -- Internal signals
logic req_sent;
logic req_done;

logic [BLEN_BITS-1:0] rd_len;

metaIntf #(.STYPE(logic[BLEN_BITS-1:0])) req_que_in ();
metaIntf #(.STYPE(logic[BLEN_BITS-1:0])) req_que_out ();

metaIntf #(.STYPE(dreq_t)) m_req_int ();

// -- REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;
    
    cred_reg_C <= 0;
    cnt_C <= 'X;
end
else
    state_C <= state_N;

    cred_reg_C <= cred_reg_N;
    cnt_C <= cnt_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = req_que_out.valid ? ST_READ : ST_IDLE;

        ST_READ:
            state_N = req_done ? (req_que_out.valid ? ST_READ : ST_IDLE) : ST_READ;

	endcase // state_C
end

// -- DP
always_comb begin
  cred_reg_N = cred_reg_C;
  cnt_N =  cnt_C;

  // IO
  s_req.ready = 1'b0;
  
  m_req_int.valid = 1'b0;
  m_req_int.data = s_req.data;

  // Status
  req_sent = s_req.valid && m_req_int.ready && req_que_in.ready && ((cred_reg_C < RDMA_N_RD_OUTSTANDING) || req_done);
  req_done = (cnt_C == 0) && xfer;

  // Outstanding queue
  req_que_in.valid = 1'b0;
  rd_len = (s_req.data.req_1.len - 1) >> BEAT_LOG_BITS;
  req_que_in.data = rd_len;
  req_que_out.ready = 1'b0;

  if(req_sent && !req_done)
      cred_reg_N = cred_reg_C + 1;
  else if(req_done && !req_sent)
      cred_reg_N = cred_reg_C - 1;

  if(req_sent) begin
      s_req.ready = 1'b1;
      m_req_int.valid = 1'b1;
      req_que_in.valid = 1'b1;
  end

  case(state_C)
    ST_IDLE: begin
      if(req_que_out.valid) begin
        req_que_out.ready = 1'b1;
        cnt_N = req_que_out.data[0+:BLEN_BITS];
      end   
    end

    ST_READ: begin
      if(req_done) begin
        if(req_que_out.valid) begin
            req_que_out.ready = 1'b1;
            cnt_N = req_que_out.data[0+:BLEN_BITS];
        end  
      end 
      else begin
        cnt_N = xfer ? cnt_C - 1 : cnt_C;
      end
    end

  endcase
end

// Outstanding
queue_stream #(
  .QTYPE(logic [BLEN_BITS-1:0]),
  .QDEPTH(RDMA_N_RD_OUTSTANDING)
) inst_dque (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(req_que_in.valid),
  .rdy_snk(req_que_in.ready),
  .data_snk(req_que_in.data),
  .val_src(req_que_out.valid),
  .rdy_src(req_que_out.ready),
  .data_src(req_que_out.data)
);

meta_reg #(.DATA_BITS($bits(dreq_t))) inst_out_reg  (.aclk(aclk), .aresetn(aresetn), .s_meta(m_req_int), .m_meta(m_req));

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_DREQ_CREDITS_RD

`endif

endmodule