
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
 

module FPAddersReduceTree #(parameter NUM_FP_POINTS    = 8,
						    parameter FP_ADDER_LATENCY = 3) 
   (
		input   wire 						clk,
		input   wire 						rst_n,

		input   wire [31:0]					fp_in_vector[NUM_FP_POINTS-1:0],
		input   wire 						fp_in_vector_valid[NUM_FP_POINTS-1:0],
		input   wire 						fp_in_vector_last[NUM_FP_POINTS-1:0],

		output  wire [31:0]				    reduce_out,
		output  wire 					    reduce_out_valid,
		input   wire  						reduce_out_ready
	);


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               Local Parameters              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

localparam NUM_TREE_LEVELS = (NUM_FP_POINTS <= 2 )? 1 :
							 (NUM_FP_POINTS <= 4 )? 2 :
							 (NUM_FP_POINTS <= 8 )? 3 :
                             (NUM_FP_POINTS <= 16)? 4 :
                             (NUM_FP_POINTS <= 32)? 5 : 6;


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Signals Declarations             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

wire   [33:0]                  tree_data[NUM_TREE_LEVELS:0][(NUM_FP_POINTS>>1)-1:0][1:0];
wire   [31:0] 				   tree_out;

wire 						   fp_in_valid_delayed;
wire  						   fp_in_last_delayed;


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               FP Adders Tree                /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// first level of tree adders
generate
	genvar i;
	for (i = 0; i < (NUM_FP_POINTS>>1); i = i + 1)
	begin:treeLevel1

	    assign tree_data[0][i][0] = {1'b0, {|(fp_in_vector[i<<1])}, fp_in_vector[i<<1] };
	    assign tree_data[0][i][1] = {1'b0, {|(fp_in_vector[(i<<1)+1])}, fp_in_vector[(i<<1)+1] };
		
		FPAdder_8_23_uid2_l3 fpadder_1_x(
				.clk          (clk),
				.rst          (~rst_n),
				.seq_stall    (1'b0),
				.X            (tree_data[0][i][0]),
				.Y            (tree_data[0][i][1]),
				.R            (tree_data[1][i>>1][i%2])
				);
	end
endgenerate

// the rest of levels
generate
	genvar j;
	for (i = 1; i < NUM_TREE_LEVELS; i = i + 1)
	begin:treeLevels
		for (j = 0; j < (NUM_FP_POINTS >> (i+1)); j = j + 1)
			begin:levelAdders
				FPAdder_8_23_uid2_l3 fpadder_i_x(
					.clk          (clk),
					.rst          (~rst_n),
					.seq_stall    (1'b0),
					.X            (tree_data[i][j][0]),
					.Y            (tree_data[i][j][1]),
					.R            (tree_data[i+1][j>>1][j%2])
				);
			end 
	end
endgenerate

// delay valid and last
delay #(.DATA_WIDTH(1),
	    .DELAY_CYCLES(FP_ADDER_LATENCY*NUM_TREE_LEVELS) 
	) fpadder_delay(

	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          (fp_in_vector_last[0]),   // 
	    .data_in_valid    (fp_in_vector_valid[0]),
	    .data_out         (fp_in_last_delayed),
	    .data_out_valid   (fp_in_valid_delayed)
	);

// assign tree output 
assign tree_out = (tree_data[NUM_TREE_LEVELS][0][0][33:32] == 2'b00)? 0 : tree_data[NUM_TREE_LEVELS][0][0][31:0];

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               FP Aggregator                 /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

FPAggregator #(.FP_ADDER_LATENCY(2)) 

 tree_aggregator(

		.clk                (clk),
		.rst_n              (rst_n),

		.fp_in              (tree_out),
		.fp_in_valid        (fp_in_valid_delayed),
		.fp_in_last         (fp_in_last_delayed),
		.fp_in_ready        (),

		.aggreg_out         (reduce_out),
		.aggreg_out_valid   (reduce_out_valid),
		.aggreg_out_ready   (reduce_out_ready)
	);






endmodule

