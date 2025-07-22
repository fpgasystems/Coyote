/*
    Copyright (c) 2022 ETH Zurich.
    All rights reserved.

    This file is distributed under the terms in the attached LICENSE file.
    If you do not find this file, copies can be found by writing to:
    ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
*/

module mem #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8
) (
    input  wire                     clk,

    // Write Port
    input  wire                     we, 
    input  wire [ADDR_WIDTH-1:0]    waddr, 
    input  wire [DATA_WIDTH-1:0]    din,

    // Read Port
    input  wire [ADDR_WIDTH-1:0]    raddr,
    output reg  [DATA_WIDTH-1:0]    dout
);


(* ram_extract = "yes", ram_style = "block" *)
reg  [DATA_WIDTH-1:0]         mem_b[0:2**ADDR_WIDTH-1];


always @(posedge clk) begin

    // Write
    if (we) begin 
        mem_b[waddr] <= din;
    end
			
    // Read
    dout  <= mem_b[raddr];
end


			
endmodule

