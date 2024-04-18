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

`timescale 1 ps / 1 ps

import eci_cmd_defs::*;

import lynxTypes::*;

module reorder_buffer_rd #(
    parameter integer                       N_THREADS = 32,
    parameter integer                       N_BURSTED = 2
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    // Input
    input  logic [ECI_ADDR_BITS-1:0]        axi_in_araddr,
    input  logic [7:0]                      axi_in_arlen,
    input  logic                            axi_in_arvalid,
    output logic                            axi_in_arready,
    
    output logic [ECI_DATA_BITS-1:0]        axi_in_rdata,
    output logic                            axi_in_rvalid,
    input  logic                            axi_in_rready,

    // Output
    output logic [ECI_ADDR_BITS-1:0]        axi_out_araddr,
    output logic [ECI_ID_BITS-1:0]          axi_out_arid,
    output logic [7:0]                      axi_out_arlen,
    output logic                            axi_out_arvalid,
    input  logic                            axi_out_arready,
    
    input  logic [ECI_DATA_BITS-1:0]        axi_out_rdata,
    input  logic [ECI_ID_BITS-1:0]          axi_out_rid,
    input  logic                            axi_out_rvalid,
    output logic                            axi_out_rready
);

// ----------------------------------------------------------------------

localparam integer N_THREADS_BITS = $clog2(N_THREADS);
localparam integer KEEP_BITS = ECI_DATA_BITS/8;


// ----------------------------------------------------------------------

// Threads
logic [N_THREADS-1:0] threads_C;
logic [N_THREADS-1:0] valid_C;
logic rvalid_C;
logic [ECI_ID_BITS-1:0] rid_C;

// Pointers
logic [N_THREADS_BITS-1:0] head_C;
logic [N_THREADS_BITS-1:0] tail_C;

// Internal
logic issue_possible;

logic rd_send;
logic rd_recv;

logic stall;

logic [ECI_DATA_BITS/8-1:0] a_keep;
logic [ECI_ID_BITS-1:0] b_addr;
logic [ECI_DATA_BITS-1:0] b_data;

// -- REG
always_ff @( posedge aclk ) begin : REG_PROC
    if(~aresetn) begin
        threads_C <= 0;
        valid_C <= 0;
        head_C <= 0;
        tail_C <= 0;

        rvalid_C <= 1'b0;
        rid_C <= 'X;
    end
    else begin  
        rvalid_C <= 1'b0;

        // Send
        if(rd_send) begin
            head_C <= head_C + (axi_in_arlen + 5'd1);
            for(logic[ECI_ID_BITS-1:0] i = 0; i < N_BURSTED; i++) begin
                if(axi_in_arlen >= i) begin
                    threads_C[head_C + i] <= 1'b1;
                end
            end
        end

        // Receive
        if(rd_recv) begin
            valid_C[axi_out_rid] <= 1'b1;
        end

        // Tail
        if(~stall) begin
            if(valid_C[tail_C] == 1'b1) begin
                threads_C[tail_C] <= 1'b0;
                valid_C[tail_C] <= 1'b0;
                tail_C <= tail_C + 1;

                rvalid_C <= 1'b1;
                rid_C <= tail_C;
            end
        end
        else begin
            rvalid_C <= rvalid_C;
        end

    end
end

// -- DP - issuing
always_comb begin
    issue_possible = 1'b1;

    for(logic[ECI_ID_BITS-1:0] i = 0; i < N_BURSTED; i++) begin
        if(axi_in_arlen >= i) begin
            if(threads_C[head_C + i] == 1'b1) begin
                issue_possible = 1'b0;
            end
        end
    end 
end

// -- DP - read send, drive handshake
always_comb begin
    rd_send = 1'b0;
    axi_in_arready = 1'b0;
    axi_out_arvalid = 1'b0;
    axi_out_arid = head_C;

    // Read
    if(axi_in_arvalid) begin
        if(axi_out_arready && issue_possible) begin
            rd_send = 1'b1;
            axi_in_arready = 1'b1;
            axi_out_arvalid = 1'b1;
        end
    end 
end

// Responses

// -- DP - reponse hshake (axi_out resonse)
always_comb begin
    // Axi out (A port)
    axi_out_rready = 1'b1;
    rd_recv = axi_out_rvalid;

    // Axi in (B port)
    stall = ~axi_in_rready;
    axi_in_rvalid = rvalid_C;
    axi_in_rdata = b_data;
    b_addr = stall ? rid_C : tail_C;
    a_keep = {KEEP_BITS{axi_out_rvalid}};
end

// Reorder buffer
ram_tp_nc #(
    .ADDR_BITS(ECI_ID_BITS),
    .DATA_BITS(ECI_DATA_BITS)
) inst_reorder_buffer_rd (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(a_keep),
    .a_addr(axi_out_rid),
    .a_data_in(axi_out_rdata),
    .a_data_out(),
    .b_en(1'b1),
    .b_addr(b_addr),
    .b_data_out(b_data)
);

// Passthrough
assign axi_out_araddr 	    = axi_in_araddr;		
assign axi_out_arlen		= axi_in_arlen;	

endmodule
