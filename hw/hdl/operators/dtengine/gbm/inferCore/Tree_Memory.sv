
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


 

module Tree_Memory #(
    parameter DATA_WIDTH          = 32,
    parameter ADDR_WIDTH          = 10
)  (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     we,
    input  wire                     rea,
    input  wire                     reb,
    input  wire [ADDR_WIDTH-1:0]    addr_port_b,
    input  wire [ADDR_WIDTH-1:0]    addr_port_a,  
    input  wire [DATA_WIDTH-1:0]    din,
    output reg  [DATA_WIDTH-1:0]    dout1,
    output reg                      valid_out1,
    output reg  [31:0]              dout2,
    output reg                      valid_out2
);


// Port A
reg  						rea_d1;
reg     	    			addr_port_a_d1;

wire 	[31:0]				dout_a_1;
wire 	[31:0]				dout_a_2;

wire    [9:0] 				addr_a_1;
wire    [9:0] 				addr_a_2;

// Port B
reg  						reb_d1;
reg              			addr_port_b_d1;

wire 	[31:0]				dout_b_1;
wire 	[31:0]				dout_b_2;



bram_1_in_2_out  bram1in2out_inst_1 (
    .clk ( clk ),
    .da ( din[31:0] ),
    .ena (rea || we),
    .addra ( addr_a_1 ),
    .wea ( we ),
    .qa ( dout_a_1 ),

    .enb   (reb),
    .db    ( 0 ),
    .addrb ( addr_port_b[10:1] ),
    .web ( 1'b0 ),
    .qb ( dout_b_1 )
    );
    
 bram_1_in_2_out   bram1in2out_inst_2 (
        .clk ( clk ),
        .da ( din[63:32] ),
        .ena (rea || we),
        .addra ( addr_a_2 ),
        .wea ( we ),
        .qa ( dout_a_2 ),

        .enb   (reb),
        .db    ( 0 ),
        .addrb ( addr_port_b[10:1] ),
        .web ( 1'b0 ),
        .qb ( dout_b_2 )
        );
    
            
    
/*bram_1_in_2_out bram1in2out_inst_1 (
	.address_a ( addr_a_1 ),
	.address_b ( addr_port_b[10:2] ),
	.clock     ( clk ),
	.data_a    ( din[31:0] ),
	.data_b    ( 0 ),
	.wren_a    ( we ),
	.wren_b    ( 1'b0 ),
	.q_a       ( dout_a_1 ),
	.q_b       ( dout_b_1 )
	);

bram_1_in_2_out bram1in2out_inst_2 (
	.address_a ( addr_a_2 ),
	.address_b ( addr_port_b[10:2] ),
	.clock     ( clk ),
	.data_a    ( din[63:32] ),
	.data_b    ( 0 ),
	.wren_a    ( we ),
	.wren_b    ( 1'b0 ),
	.q_a       ( dout_a_2 ),
	.q_b       ( dout_b_2 )
	);

bram_1_in_2_out bram1in2out_inst_3 (
	.address_a ( addr_a_3 ),
	.address_b ( addr_port_b[10:2] ),
	.clock     ( clk ),
	.data_a    ( din[95:64] ),
	.data_b    ( 0 ),
	.wren_a    ( we ),
	.wren_b    ( 1'b0 ),
	.q_a       ( dout_a_3 ),
	.q_b       ( dout_b_3 )
	);

bram_1_in_2_out bram1in2out_inst_4 (
	.address_a ( addr_a_4 ),
	.address_b ( addr_port_b[10:2] ),
	.clock     ( clk ),
	.data_a    ( din[127:96] ),
	.data_b    ( 0 ),
	.wren_a    ( we ),
	.wren_b    ( 1'b0 ),
	.q_a       ( dout_a_4 ),
	.q_b       ( dout_b_4 )
	);
*/
//------------------------ Port A ---------------------------//
// rd_addr_a
assign addr_a_1 = (we || (addr_port_a[0] == 1'b0))? addr_port_a[10:1] : addr_port_a[10:1] + 1'b1;
assign addr_a_2 = addr_port_a[10:1];
//
always @(posedge clk) begin
	addr_port_a_d1 <= addr_port_a[0];

	if(~rst_n) begin
	    valid_out1     <= 1'b0;
	    rea_d1         <= 1'b0;
	end
	else begin 
		rea_d1         <= rea;
		valid_out1     <= rea_d1;
	end
	//
	case (addr_port_a_d1)
        1'b0:    dout1 <= {dout_a_2, dout_a_1};
       	1'b1:    dout1 <= {dout_a_1, dout_a_2};
        default: dout1 <= 64'b0;
    endcase
end
//----------------------- Port B ----------------------------//
always @(posedge clk) begin

	addr_port_b_d1 <= addr_port_b[0];

	if(~rst_n) begin
		reb_d1         <= 1'b0;
	    valid_out2     <= 1'b0;
	end
	else begin 
		reb_d1         <= reb;
		valid_out2     <= reb_d1;
	end
	//
	if (addr_port_b_d1) begin
		dout2 <= dout_b_2;
	end
	else begin 
		dout2 <= dout_b_1;
	end
end



endmodule // Mem1in2out
