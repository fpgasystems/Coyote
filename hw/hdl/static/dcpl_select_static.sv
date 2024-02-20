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
