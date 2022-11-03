
/*
 * Copyright 2019 - 2020 Systems Group, ETH Zurich
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

module Data_Memory #(
    parameter DATA_WIDTH          = 32,
    parameter ADDR_WIDTH          = 8
) (
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           we,
    input  wire                           re,
    input  wire [ADDR_WIDTH-1:0]          raddr,
    input  wire [ADDR_WIDTH-2:0]          waddr,  
    input  wire [DATA_WIDTH-1:0]          din,
    output reg  [31:0]                    dout,
    output reg                            valid_out
);

wire  [DATA_WIDTH-1:0]      dline;
reg                         raddr_d1;
reg                         re_d1;



dual_port_mem  Dualport_mem_inst (
    .clk   ( clk ),
    .da    ( din ),
    .wea   ( we), 
    .ena   ( we),
    .addra ( waddr ),

    .web   (1'b0),
    .addrb ( raddr[ADDR_WIDTH-1:1] ),
    .enb   ( re ),
    .qb    ( dline )
    );


always @(posedge clk) begin
    raddr_d1  <= raddr[0];
    re_d1     <= re;
    dout      <= (raddr_d1)? dline[63:32] : dline[31:0];

    if(~rst_n) begin
        valid_out <= 1'b0;
    end
    else begin 
        valid_out <= re_d1;
    end
end
			
endmodule

