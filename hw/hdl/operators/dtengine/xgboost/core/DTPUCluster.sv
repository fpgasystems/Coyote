
import DTEngine_Types::*;


module DTPUCluster (
		input   wire  							      clk,
		input   wire 							      rst_n,

		input   wire  [DATA_BUS_WIDTH-1:0]            data_line_in,
		input   wire  								  data_line_in_valid,
		input   wire  								  data_line_in_last,
		input   wire  								  data_line_in_ctrl,
		input   wire  [1:0]	    					  data_line_in_mode,
		input   wire  [NUM_PUS_PER_CLUSTER_BITS-1:0]  data_line_in_pu,
		output  reg 								  data_line_in_ready,


		output  wire  [NUM_PUS_PER_CLUSTER*16-1:0]    partial_tree_node_index_out,
		output  wire                                  partial_tree_node_index_out_valid,

		output  wire  [DATA_PRECISION-1:0]            partial_aggregation_out,
		output  wire                                  partial_aggregation_out_valid,
		input   wire                                  partial_aggregation_out_ready,

		output  reg    [31:0] 						  tuples_received, 
		output  reg    [31:0] 						  lines_received,
		output  reg    [31:0] 						  tuples_res_out,
		output  reg    [31:0] 						  tree_res_out, 
		output  reg    [31:0] 						  reduce_tree_outs, 
		output  reg    [31:0] 						  reduce_tree_outs_valids

	);


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Signals Declarations             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

wire  [DATA_BUS_WIDTH-1:0]                 data_line_array[NUM_PUS_PER_CLUSTER:0];
wire  					                   data_line_valid_array[NUM_PUS_PER_CLUSTER:0];
wire  					                   data_line_last_array[NUM_PUS_PER_CLUSTER:0];
wire  					                   data_line_ready_array[NUM_PUS_PER_CLUSTER:0];
wire  					                   data_line_ctrl_array[NUM_PUS_PER_CLUSTER:0];
wire  [1:0]		   	                       data_line_mode_array[NUM_PUS_PER_CLUSTER:0];
wire  [NUM_PUS_PER_CLUSTER_BITS-1:0]       data_line_pu_array[NUM_PUS_PER_CLUSTER:0];

wire  [15:0]                               pu_tree_node_index_out[NUM_PUS_PER_CLUSTER-1:0];
wire   									   pu_tree_node_index_out_valid[NUM_PUS_PER_CLUSTER-1:0];
 
wire  [DATA_PRECISION-1:0]                 pu_tree_leaf_out[NUM_PUS_PER_CLUSTER-1:0];
wire 									   pu_tree_leaf_out_valid[NUM_PUS_PER_CLUSTER-1:0];
wire 									   pu_tree_leaf_out_last[NUM_PUS_PER_CLUSTER-1:0];
wire 									   pu_tree_leaf_out_ready[NUM_PUS_PER_CLUSTER-1:0];


wire  [DATA_PRECISION-1:0]                 aggregation_out;
wire 									   aggregation_out_valid;
wire 									   leaves_aggreg_result_fifo_full;
wire 									   aggregation_out_ready;

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////          Generate DTPU Instances            /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

always @(posedge clk) begin
	if (~rst_n) begin
		// reset
		data_line_in_ready <= 1'b0;

		tuples_received <= 0;
		lines_received  <= 0;
		tuples_res_out <= 0;
		tree_res_out <= 0;
		reduce_tree_outs <= 0;
		reduce_tree_outs_valids <= 0;
	end
	else begin
		data_line_in_ready <= data_line_ready_array[0];

		if(data_line_in_valid & data_line_in_last) begin
			tuples_received <= tuples_received + 1'b1;
		end

		if(data_line_in_valid) begin
			lines_received <= lines_received + 1'b1;
		end

		if(pu_tree_leaf_out_valid[0] & pu_tree_leaf_out_last[0]) begin
			tuples_res_out <= tuples_res_out + 1'b1;
		end
		if(pu_tree_leaf_out_valid[0]) begin
			tree_res_out <= tree_res_out + 1'b1;
		end

		if(aggregation_out_valid & aggregation_out_ready) begin
			reduce_tree_outs <= reduce_tree_outs + 1'b1;
		end

		if(aggregation_out_valid) begin
			reduce_tree_outs_valids <= reduce_tree_outs_valids + 1'b1;
		end
		
	end
end

// initialize input to first PU
assign data_line_array[0]       = data_line_in;
assign data_line_valid_array[0] = data_line_in_valid;
assign data_line_last_array[0]  = data_line_in_last;
assign data_line_ctrl_array[0]  = data_line_in_ctrl;
assign data_line_mode_array[0]  = data_line_in_mode;
assign data_line_pu_array[0]    = data_line_in_pu;


// generate a cascade of PUs
genvar i;

generate 
    for (i = 0; i < NUM_PUS_PER_CLUSTER; i = i + 1) begin:pus 
		DTPU #(.PU_ID                      (i)
	          ) pu_x(

		.clk                              (clk),
		.rst_n                            (rst_n),

		.data_line_in                     (data_line_array[i]),
		.data_line_in_valid               (data_line_valid_array[i]),
		.data_line_in_last                (data_line_last_array[i]),
		.data_line_in_ctrl                (data_line_ctrl_array[i]),
		.data_line_in_mode                (data_line_mode_array[i]),
		.data_line_in_pu                  (data_line_pu_array[i]),
		.data_line_in_ready               (data_line_ready_array[i]),

		.data_line_out                    (data_line_array[i+1]),
		.data_line_out_valid              (data_line_valid_array[i+1]),
		.data_line_out_ctrl               (data_line_ctrl_array[i+1]),
		.data_line_out_last               (data_line_last_array[i+1]),
		.data_line_out_prog               (data_line_mode_array[i+1]),
		.data_line_out_pu                 (data_line_pu_array[i+1]),

		.pu_tree_node_index_out           (pu_tree_node_index_out[i]),
		.pu_tree_node_index_out_valid     (pu_tree_node_index_out_valid[i]),

		.pu_tree_leaf_out                 (pu_tree_leaf_out[i]),
		.pu_tree_leaf_out_valid           (pu_tree_leaf_out_valid[i]),
		.pu_tree_leaf_out_last            (pu_tree_leaf_out_last[i])
		);

    
    	//
    	assign partial_tree_node_index_out[16*i+15:i*16] = pu_tree_node_index_out[i];

	end
endgenerate

// as all PUs synchronized to start processing at the same time and do the same amount of processing 
// looking at the valid signal from 1st PU is enough.

assign partial_tree_node_index_out_valid = pu_tree_node_index_out_valid[0];

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////         Instance of FPAdders Tree           /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

FPAddersReduceTree #(.NUM_FP_POINTS(NUM_PUS_PER_CLUSTER)
	) reduce_leaves(
		.clk                (clk),
		.rst_n              (rst_n),

		.fp_in_vector       (pu_tree_leaf_out),
		.fp_in_vector_valid (pu_tree_leaf_out_valid),
		.fp_in_vector_last  (pu_tree_leaf_out_last),
		.fp_in_vector_ready (pu_tree_leaf_out_ready),

		.reduce_out         (aggregation_out),
		.reduce_out_valid   (aggregation_out_valid),
		.reduce_out_ready   (aggregation_out_ready)
	);

assign aggregation_out_ready = ~leaves_aggreg_result_fifo_full;
// putting FPAdders tree output in a FIFO

quick_fifo  #(.FIFO_WIDTH(DATA_PRECISION),        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
            ) leaves_aggreg_result_fifo (
        	.clk                (clk),
        	.reset_n            (rst_n),
        	.din                (aggregation_out),
        	.we                 (aggregation_out_valid),

        	.re                 (partial_aggregation_out_ready),
        	.dout               (partial_aggregation_out),
        	.empty              (),
        	.valid              (partial_aggregation_out_valid),
        	.full               (leaves_aggreg_result_fifo_full),
        	.count              (),
        	.almostfull         ()
    	);

endmodule 












