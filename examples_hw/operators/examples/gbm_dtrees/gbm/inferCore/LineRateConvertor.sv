
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
 
import DTPackage::*;


module LineRateConvertor #(parameter CU_ID = 0 )
	(
	input   wire  							      clk,
	input   wire 							      rst_n,

	input   wire  [511:0]                         data_line_in,
	input   wire  								  data_line_in_valid,
	input   wire  [2:0] 						  data_line_in_last_valid_pos, 
	input   wire  								  data_line_in_last,
	input   wire  								  data_line_in_ctrl,
	input   wire     	    					  data_line_in_prog,
	input   wire  [NUM_PUS_PER_CLUSTER_BITS-1:0]  data_line_in_pu,
	input   wire  [NUM_DTPU_CLUSTERS_BITS-1:0]    data_line_in_cu,
	output  wire  								  data_line_in_ready,

	output  reg   [DATA_LINE_WIDTH-1:0]           data_line_out,
	output  reg  								  data_line_out_valid,
	output  reg                                   data_line_out_ctrl,
    output  reg   								  data_line_out_last,
	output  reg     	    					  data_line_out_prog,
	output  reg   [NUM_PUS_PER_CLUSTER_BITS-1:0]  data_line_out_pu,
	input   wire 								  data_line_out_ready
);


wire 									data_line_fifo_we;
wire 									data_line_fifo_almfull;
wire 									data_line_fifo_valid;
wire 									data_line_fifo_re;

wire  [63:0]						 	data_line_array[7:0];

wire  [511:0]                         	data_line_in_fifo_data;
wire  								  	data_line_in_fifo_valid;
wire  [2:0] 						  	data_line_in_fifo_last_valid_pos;
wire  								  	data_line_in_fifo_last;
wire  								  	data_line_in_fifo_ctrl;
wire     	    					  	data_line_in_fifo_prog;
wire  [NUM_PUS_PER_CLUSTER_BITS-1:0]  	data_line_in_fifo_pu;

reg   [2:0]								curr_word;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
assign data_line_fifo_we  = (data_line_in_valid  && (data_line_in_cu == CU_ID)) || data_line_in_ctrl || data_line_in_prog;
assign data_line_in_ready = ~data_line_fifo_almfull;

// Input Line FIFO
quick_fifo  #(.FIFO_WIDTH(512+3+1+1+1+1+5),        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(500)
             ) data_line_fifo (
        	.clk                (clk),
        	.reset_n            (rst_n),
        	.din                ({data_line_in_pu, data_line_in_prog, data_line_in_ctrl, data_line_in_last, data_line_in_valid, data_line_in_last_valid_pos, data_line_in}),
        	.we                 (data_line_fifo_we),

        	.re                 (data_line_fifo_re),
        	.dout               ({data_line_in_fifo_pu, data_line_in_fifo_prog, data_line_in_fifo_ctrl, data_line_in_fifo_last, data_line_in_fifo_valid, data_line_in_fifo_last_valid_pos, data_line_in_fifo_data}),
        	.empty              (),
        	.valid              (data_line_fifo_valid),
        	.full               (),
        	.count              (),
        	.almostfull         (data_line_fifo_almfull)
    	);


// Put the input data line in an array
genvar i;
generate for (i = 0; i < 8; i=i+1) begin
	assign data_line_array[i] = data_line_in_fifo_data[64*i+63:64*i];
end
endgenerate

// Select output 64-bit word
always@(posedge clk) begin 
	data_line_out       <= data_line_array[ curr_word ];
	data_line_out_valid <= data_line_fifo_valid && data_line_in_fifo_valid && data_line_out_ready;
	data_line_out_last  <= data_line_in_fifo_last  && (curr_word == data_line_in_fifo_last_valid_pos);
	data_line_out_ctrl  <= data_line_fifo_valid && data_line_in_fifo_ctrl;
	data_line_out_prog  <= data_line_fifo_valid && data_line_in_fifo_prog;
	data_line_out_pu    <= data_line_in_fifo_pu;
end

// data_line_fifo_re
assign data_line_fifo_re = data_line_out_ready && ( (data_line_in_fifo_last && (curr_word == data_line_in_fifo_last_valid_pos)) || (curr_word == 3'b111)  );

// curr_word calculation
always@(posedge clk) begin 
	if(~rst_n) begin
		curr_word <= 3'b000;
	end
	else begin 
		if(data_line_out_ready && data_line_fifo_valid) begin
			if(data_line_in_fifo_last && (curr_word == data_line_in_fifo_last_valid_pos) ) begin
				curr_word <= 3'b000;
			end
			else if(curr_word == 3'b111) begin
				curr_word <= 3'b000;
			end
			else begin 
				curr_word <= curr_word + 1'b1;
			end
		end
	end
end


endmodule