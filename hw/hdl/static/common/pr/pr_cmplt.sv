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