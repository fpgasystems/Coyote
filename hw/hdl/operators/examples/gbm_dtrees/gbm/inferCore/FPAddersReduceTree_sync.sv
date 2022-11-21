
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
 

module FPAddersReduceTree_sync #(parameter NUM_FP_POINTS    = 8,
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
//////////////////////////////            Signals Declarations             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

wire   [33:0]				   tree_data_il1[27:0];
wire   [33:0]				   tree_data_ol1[13:0];

wire   [33:0]				   tree_data_il2[13:0];
wire   [33:0]				   tree_data_ol2[6:0];

wire   [33:0]				   tree_data_il3[6:0];
wire   [33:0]				   tree_data_ol3[3:0];

wire   [33:0]				   tree_data_il4[3:0];
wire   [33:0]				   tree_data_ol4[1:0];

wire   [33:0]				   tree_data_il5[1:0];
wire   [33:0]				   tree_data_ol5;

reg    [31:0] 				   tree_out;

wire 						   fp_in_valid_delayed;
wire  						   fp_in_last_delayed;

genvar i;
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               FP Adders Tree                /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Level 0: introduce delay on even words

generate for (i = 0; i < 28; i=i+1) begin : Level0
	if(i%2 == 0) begin
		delay #(.DATA_WIDTH(34),
	    		.DELAY_CYCLES(1) 
			   ) level0_regs
			   (
	    			.clk              (clk),
	    			.rst_n            (rst_n),
	    			.data_in          ({1'b0, {|(fp_in_vector[i])}, fp_in_vector[i]}),   // 
	    			.data_in_valid    (1'b0),
	    			.data_out         (tree_data_il1[i]),
	    			.data_out_valid   ()
			   );
	end
	else begin 
		assign tree_data_il1[i] = {1'b0, {|(fp_in_vector[i])}, fp_in_vector[i] };
	end
end
endgenerate

// Level 1: Adders
generate for (i = 0; i < 28; i = i + 2) begin:treeLevel1

	FPAdder_8_23_uid2_l3 fpadder_l1
	(
				.clk          (clk),
				.rst          (~rst_n),
				.seq_stall    (1'b0),
				.X            (tree_data_il1[i]),
				.Y            (tree_data_il1[i+1]),
				.R            (tree_data_ol1[i/2])
	);
 	
 	if(i%4 == 0) begin
		delay #(.DATA_WIDTH(34),
	    		.DELAY_CYCLES(2) 
			   ) level1_regs
			   (
	    			.clk              (clk),
	    			.rst_n            (rst_n),
	    			.data_in          (tree_data_ol1[i/2]),   // 
	    			.data_in_valid    (1'b0),
	    			.data_out         (tree_data_il2[i/2]),
	    			.data_out_valid   ()
			   );
	end
	else begin 
		assign tree_data_il2[i/2] = tree_data_ol1[i/2];
	end
end
endgenerate

// Level 2: Adders
generate for (i = 0; i < 14; i = i + 2) begin:treeLevel2

	FPAdder_8_23_uid2_l3 fpadder_l2
	(
				.clk          (clk),
				.rst          (~rst_n),
				.seq_stall    (1'b0),
				.X            (tree_data_il2[i]),
				.Y            (tree_data_il2[i+1]),
				.R            (tree_data_ol2[i/2])
	);
 	
 	if((i%4 == 0) && (i < 12)) begin
		delay #(.DATA_WIDTH(34),
	    		.DELAY_CYCLES(4) 
			   ) level2_regs
			   (
	    			.clk              (clk),
	    			.rst_n            (rst_n),
	    			.data_in          (tree_data_ol2[i/2]),   // 
	    			.data_in_valid    (1'b0),
	    			.data_out         (tree_data_il3[i/2]),
	    			.data_out_valid   ()
			   );
	end
	else begin 
		assign tree_data_il3[i/2] = tree_data_ol2[i/2];
	end
end
endgenerate
// Level 3: Adders
generate for (i = 0; i < 7; i = i + 2) begin:treeLevel3
if(i < 6) begin
	FPAdder_8_23_uid2_l3 fpadder_l3
	(
				.clk          (clk),
				.rst          (~rst_n),
				.seq_stall    (1'b0),
				.X            (tree_data_il3[i]),
				.Y            (tree_data_il3[i+1]),
				.R            (tree_data_ol3[i/2])
	);
 	
 	if(i%4 == 0) begin
		delay #(.DATA_WIDTH(34),
	    		.DELAY_CYCLES( (i == 0)?8:1) 
			   ) level3_regs
			   (
	    			.clk              (clk),
	    			.rst_n            (rst_n),
	    			.data_in          (tree_data_ol3[i/2]),   // 
	    			.data_in_valid    (1'b0),
	    			.data_out         (tree_data_il4[i/2]),
	    			.data_out_valid   ()
			   );
	end
	else begin 
		assign tree_data_il4[i/2] = tree_data_ol3[i/2];
	end
end 
else begin 
	assign tree_data_il4[i/2] = tree_data_il3[i];
end
end
endgenerate

// Level 4: Adders
generate for (i = 0; i < 4; i = i + 2) begin:treeLevel4

	FPAdder_8_23_uid2_l3 fpadder_l4
	(
				.clk          (clk),
				.rst          (~rst_n),
				.seq_stall    (1'b0),
				.X            (tree_data_il4[i]),
				.Y            (tree_data_il4[i+1]),
				.R            (tree_data_ol4[i/2])
	);
 	
 	if(i%4 == 0) begin
		delay #(.DATA_WIDTH(34),
	    		.DELAY_CYCLES(9) 
			   ) level4_regs
			   (
	    			.clk              (clk),
	    			.rst_n            (rst_n),
	    			.data_in          (tree_data_ol4[i/2]),   // 
	    			.data_in_valid    (1'b0),
	    			.data_out         (tree_data_il5[i/2]),
	    			.data_out_valid   ()
			   );
	end
	else begin 
		assign tree_data_il5[i/2] = tree_data_ol4[i/2];
	end
end
endgenerate

// Level 5: Adders

	FPAdder_8_23_uid2_l3 fpadder_l5
	(
				.clk          (clk),
				.rst          (~rst_n),
				.seq_stall    (1'b0),
				.X            (tree_data_il5[0]),
				.Y            (tree_data_il5[1]),
				.R            (tree_data_ol5)
	);

// delay valid and last
delay #(.DATA_WIDTH(1),
	    .DELAY_CYCLES(FP_ADDER_LATENCY*5 + 1 + 24) 
	) fpadder_delay(

	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          (fp_in_vector_last[0]),   // 
	    .data_in_valid    (fp_in_vector_valid[0]),
	    .data_out         (fp_in_last_delayed),
	    .data_out_valid   (fp_in_valid_delayed)
	);

// assign tree output 
always@(posedge clk) begin 
	tree_out <= (tree_data_ol5[33:32] == 2'b00)? 0 : tree_data_ol5[31:0];
end

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               FP Aggregator                 /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

FPAggregator #(.FP_ADDER_LATENCY(3)) 

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

