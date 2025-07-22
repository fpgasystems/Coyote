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

module dcpl_select_static #(
    parameter integer                       N_STAGES = 1
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    input  logic                            pr_slct,

    input  logic                            decouple_sw,
    input  logic                            decouple_vio,
    output logic                            decouple,

    input  logic                            eos_resetn_sw,
    input  logic                            eos_resetn_vio,
    output logic                            eos_resetn
);  

    logic [N_STAGES:0] pr_slct_r;
    
    logic [N_STAGES:0] decouple_sw_r;
    logic [N_STAGES:0] decouple_vio_r;
    logic [N_STAGES:0] decouple_out;
    logic decouple_selected;

    logic [N_STAGES:0] eos_resetn_sw_r;
    logic [N_STAGES:0] eos_resetn_vio_r;
    logic [N_STAGES:0] eos_resetn_out;
    logic eos_resetn_selected;

    // I/O
    assign pr_slct_r[0] = pr_slct;
    
    assign decouple_sw_r[0] = decouple_sw;
    assign decouple_vio_r[0] = decouple_vio;
    assign decouple_out[0] = decouple_selected;
    assign decouple = decouple_out[N_STAGES];

    assign eos_resetn_sw_r[0] = eos_resetn_sw;
    assign eos_resetn_vio_r[0] = eos_resetn_vio;
    assign eos_resetn_out[0] = eos_resetn_selected;
    assign eos_resetn = eos_resetn_out[N_STAGES];

    // Reg
    always_ff @(posedge aclk) begin
        if(~aresetn) begin
            for(int i = 1; i <= N_STAGES; i++) begin
                pr_slct_r[i] <= 1'b0;

                decouple_sw_r[i] <= 1'b0;
                decouple_vio_r[i] <= 1'b0;
                decouple_out[i] <= 1'b0;

                eos_resetn_sw_r[i] <= 1'b1;
                eos_resetn_vio_r[i] <= 1'b1;
                eos_resetn_out[i] <= 1'b1;
            end

            decouple_selected <= 1'b0;
            eos_resetn_selected <= 1'b1;
        end
        else begin
            for(int i = 1; i <= N_STAGES; i++) begin
                pr_slct_r[i] <= pr_slct_r[i-1];
                
                decouple_sw_r[i] <= decouple_sw_r[i-1];
                decouple_vio_r[i] <= decouple_vio_r[i-1];         
                decouple_out[i] <= decouple_out[i-1];

                eos_resetn_sw_r[i] <= eos_resetn_sw_r[i-1];
                eos_resetn_vio_r[i] <= eos_resetn_vio_r[i-1];
                eos_resetn_out[i] <= eos_resetn_out[i-1];
            end

            decouple_selected <= pr_slct_r[N_STAGES] ? decouple_vio_r[N_STAGES] : decouple_sw_r[N_STAGES];
            eos_resetn_selected <= pr_slct_r[N_STAGES] ? eos_resetn_vio_r[N_STAGES] : eos_resetn_sw_r[N_STAGES];
        end
    end
    
endmodule
