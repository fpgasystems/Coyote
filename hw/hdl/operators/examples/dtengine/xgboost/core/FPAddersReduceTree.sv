

module FPAddersReduceTree #(parameter NUM_FP_POINTS    = 8,
						    parameter FP_ADDER_LATENCY = 2) 
   (
		input   wire 						clk,
		input   wire 						rst_n,

		input   wire [31:0]					fp_in_vector[NUM_FP_POINTS-1:0],
		input   wire 						fp_in_vector_valid[NUM_FP_POINTS-1:0],
		input   wire 						fp_in_vector_last[NUM_FP_POINTS-1:0],
		output  reg 						fp_in_vector_ready[NUM_FP_POINTS-1:0],

		output  wire [31:0]				    reduce_out,
		output  wire 					    reduce_out_valid,
		input   wire  						reduce_out_ready
	);


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               Local Parameters              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

localparam NUM_TREE_LEVELS = (NUM_FP_POINTS == 16)? 4 :
                             (NUM_FP_POINTS ==  8)? 3 :
                             (NUM_FP_POINTS ==  4)? 2 : 1;


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Signals Declarations             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

wire   [33:0]                  tree_data[NUM_TREE_LEVELS:0][(NUM_FP_POINTS>>1)-1:0][1:0];
wire   [31:0] 				   tree_out;
reg    [31:0] 				   tree_out_d1;

wire 						   fp_in_valid_delayed;
wire  						   fp_in_last_delayed;

wire 						   fp_in_ready;

wire 				tree_aggregator_in_fifo_valid;
wire 				tree_aggregator_in_fifo_almfull;
wire  [32:0] 		tree_aggregator_in_fifo_dout;

genvar i;
generate
	
	for (i = 0; i < NUM_FP_POINTS; i = i + 1)
	begin:fpInReady

	    always@(posedge clk) begin 
	    	if(~rst_n) begin
	    		fp_in_vector_ready[i] <= 1'b0;
	    	end
	    	else begin 
	    		fp_in_vector_ready[i] <= fp_in_ready;
	    	end
	    end
	end
endgenerate


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               FP Adders Tree                /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// first level of tree adders
generate
	for (i = 0; i < (NUM_FP_POINTS>>1); i = i + 1)
	begin:treeLevel1

	    assign tree_data[0][i][0] = {1'b0, {|(fp_in_vector[i<<1])}, fp_in_vector[i<<1] };
	    assign tree_data[0][i][1] = {1'b0, {|(fp_in_vector[(i<<1)+1])}, fp_in_vector[(i<<1)+1] };
		
		FPAdder_8_23_uid2_l2 fpadder_1_x(
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
				FPAdder_8_23_uid2_l2 fpadder_i_x(
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
	    .DELAY_CYCLES(FP_ADDER_LATENCY*NUM_TREE_LEVELS+1) 
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

/*
quick_fifo  #(.FIFO_WIDTH(32+1),        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(500)
             ) tree_aggregator_in_fifo (
        	.clk                (clk),
        	.reset_n            (rst_n),
        	.din                ({fp_in_last_delayed, tree_out}),
        	.we                 (fp_in_valid_delayed),

        	.re                 (fp_in_ready),
        	.dout               (tree_aggregator_in_fifo_dout),
        	.empty              (),
        	.valid              (tree_aggregator_in_fifo_valid),
        	.full               (),
        	.count              (),
        	.almostfull         (tree_aggregator_in_fifo_almfull)
    	);

*/

always@(posedge clk) begin 
	if(~rst_n) begin
	   	tree_out_d1 <= 1'b0;
	end
	else begin 
	   tree_out_d1 <= tree_out;
	end
end


FPAggregator #(.FP_ADDER_LATENCY(FP_ADDER_LATENCY)) 

 tree_aggregator(

		.clk                (clk),
		.rst_n              (rst_n),

		.fp_in              (tree_out),
		.fp_in_valid        (fp_in_valid_delayed),
		.fp_in_last         (fp_in_last_delayed),
		.fp_in_ready        (fp_in_ready),

		.aggreg_out         (reduce_out),
		.aggreg_out_valid   (reduce_out_valid),
		.aggreg_out_ready   (reduce_out_ready)
	);






endmodule

