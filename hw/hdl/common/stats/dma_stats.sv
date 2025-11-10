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

`include "axi_macros.svh"

module dma_stats (
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