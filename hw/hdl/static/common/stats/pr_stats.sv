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

`include "axi_macros.svh"

module pr_stats (
    input  logic                            aclk,
    input  logic                            aresetn,

    input  logic                            dma_rd_req,
    input  logic                            dma_rd_done,
    input  logic                            axis_rd,
    input  logic                            dma_wr_req,
    input  logic                            dma_wr_done,
    input  logic                            axis_wr,
    
    output xdma_stat_t                      xdma_stats
);

// Counters
logic[31:0] bpss_c2h_req_counter; 
logic[31:0] bpss_h2c_req_counter; 
logic[31:0] bpss_c2h_cmpl_counter; 
logic[31:0] bpss_h2c_cmpl_counter; 
logic[31:0] bpss_c2h_axis_counter; 
logic[31:0] bpss_h2c_axis_counter; 

xdma_stat_t[XDMA_STATS_DELAY-1:0] xdma_stats_tmp; // Slice

assign xdma_stats_tmp[0].bpss_h2c_req_counter = bpss_h2c_req_counter;
assign xdma_stats_tmp[0].bpss_c2h_req_counter = bpss_c2h_req_counter;
assign xdma_stats_tmp[0].bpss_h2c_cmpl_counter = bpss_h2c_cmpl_counter;
assign xdma_stats_tmp[0].bpss_c2h_cmpl_counter = bpss_c2h_cmpl_counter;
assign xdma_stats_tmp[0].bpss_h2c_axis_counter = bpss_h2c_axis_counter;
assign xdma_stats_tmp[0].bpss_c2h_axis_counter = bpss_c2h_axis_counter;

assign xdma_stats = xdma_stats_tmp[XDMA_STATS_DELAY-1];

always @(posedge aclk) begin
    if(~aresetn) begin
        bpss_h2c_req_counter <= '0;
        bpss_c2h_req_counter <= '0;
        bpss_h2c_cmpl_counter <= '0;
        bpss_c2h_cmpl_counter <= '0;
        bpss_h2c_axis_counter <= '0;
        bpss_c2h_axis_counter <= '0;
    end
    else begin
        for(int i = 1; i < XDMA_STATS_DELAY; i++) begin
            xdma_stats_tmp[i] <= xdma_stats_tmp[i-1];
        end

        if (dma_rd_req) begin
            bpss_h2c_req_counter <= bpss_h2c_req_counter + 1;
        end
        if (dma_wr_req) begin
            bpss_c2h_req_counter <= bpss_c2h_req_counter + 1;
        end
        if (dma_rd_done) begin
            bpss_h2c_cmpl_counter <= bpss_h2c_cmpl_counter + 1;
        end
        if (dma_wr_done) begin
            bpss_c2h_cmpl_counter <= bpss_c2h_cmpl_counter + 1;
        end
        if (axis_rd) begin
            bpss_h2c_axis_counter <= bpss_h2c_axis_counter + 1;
        end
        if (axis_wr) begin
            bpss_c2h_axis_counter <= bpss_c2h_axis_counter + 1;
        end
    end
end


endmodule