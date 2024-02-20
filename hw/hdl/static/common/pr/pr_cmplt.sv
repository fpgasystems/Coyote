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

module pr_cmplt (
    input  logic                pclk,
    input  logic                presetn,
    input  logic                aclk,

    input  logic                pr_val,
    input  logic                pr_last,
    output logic                eos,
    input  logic [31:0]         eos_time
);

// -- FSM
typedef enum logic[1:0]  {ST_IDLE, ST_WAIT, ST_DONE} state_t;
logic [1:0] state_C, state_N;
logic [31:0] cnt_C, cnt_N;

logic eos_p;
logic [31:0] eos_time_p;

// REG
always_ff @( posedge pclk ) begin : PREG
    if(presetn==1'b0) begin
        state_C <= ST_IDLE;
        cnt_C <= 'X;
    end
    else begin
        state_C <= state_N;
        cnt_C <= cnt_N;
    end
end

// NSL
always_comb begin
    state_N = state_C;

    case (state_C)
        ST_IDLE:
            state_N = pr_val & pr_last ? ST_WAIT : ST_IDLE;

        ST_WAIT:
            state_N = (cnt_C == eos_time_p) ? ST_DONE : ST_WAIT;

        ST_DONE:
            state_N = ST_IDLE;

    endcase
end

// DP
always_comb begin
    cnt_N = cnt_C;

    case (state_C)
        ST_IDLE: begin
            cnt_N = 0;
        end

        ST_WAIT: begin
            cnt_N = cnt_C + 1;
        end

    endcase
end

assign eos_p = (state_C == ST_DONE);

// Ccross
xpm_cdc_single #(
   .DEST_SYNC_FF(4),   // DECIMAL; range: 2-10
   .INIT_SYNC_FF(0),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
   .SIM_ASSERT_CHK(0), // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
   .SRC_INPUT_REG(1)   // DECIMAL; 0=do not register input, 1=register input
)
xpm_cdc_single_inst (
   .dest_out(eos), // 1-bit output: src_in synchronized to the destination clock domain. This output is
                        // registered.

   .dest_clk(aclk), // 1-bit input: Clock signal for the destination clock domain.
   .src_clk(pclk),   // 1-bit input: optional; required when SRC_INPUT_REG = 1
   .src_in(eos_p)      // 1-bit input: Input signal to be synchronized to dest_clk domain.
);

xpm_cdc_array_single #(
   .DEST_SYNC_FF(4),   // DECIMAL; range: 2-10
   .INIT_SYNC_FF(0),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
   .SIM_ASSERT_CHK(0), // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
   .SRC_INPUT_REG(1),  // DECIMAL; 0=do not register input, 1=register input
   .WIDTH(32)           // DECIMAL; range: 1-1024
)
xpm_cdc_array_single_inst (
   .dest_out(eos_time_p), // WIDTH-bit output: src_in synchronized to the destination clock domain. This
                        // output is registered.

   .dest_clk(pclk), // 1-bit input: Clock signal for the destination clock domain.
   .src_clk(aclk),   // 1-bit input: optional; required when SRC_INPUT_REG = 1
   .src_in(eos_time)      // WIDTH-bit input: Input single-bit array to be synchronized to destination clock
                        // domain. It is assumed that each bit of the array is unrelated to the others. This
                        // is reflected in the constraints applied to this macro. To transfer a binary value
                        // losslessly across the two clock domains, use the XPM_CDC_GRAY macro instead.
);

endmodule