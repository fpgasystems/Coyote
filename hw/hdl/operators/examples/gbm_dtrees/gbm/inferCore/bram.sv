

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

module bram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8
) (
    input  wire                     clk,
    input  wire                     we,
	input  wire                     re,  
    input  wire [ADDR_WIDTH-1:0]    raddr,
    input  wire [ADDR_WIDTH-1:0]    waddr,  
    input  wire [DATA_WIDTH-1:0]    din,
    output reg  [DATA_WIDTH-1:0]    dout
);


`ifdef VENDOR_XILINX
    (* ram_extract = "yes", ram_style = "block" *)
    reg  [DATA_WIDTH-1:0]         mem[0:2**ADDR_WIDTH-1];
`else
(* ramstyle = "no_rw_check" *) reg  [DATA_WIDTH-1:0] mem[0:2**ADDR_WIDTH-1];
`endif


    always @(posedge clk) begin
        if (we)
            mem[waddr] <= din;
			
        if (re)
			dout <= mem[raddr];
    end
			
endmodule