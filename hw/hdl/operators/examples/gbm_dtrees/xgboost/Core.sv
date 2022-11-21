
/*
	
	The Core module is where computations happen 

	core_data_in carry a stream of Trees/Data for processing in the core

	tuple_out_data carries the result of inference on one tuple, this can be 
	a partial result if not the complete model is stored in the core or the
	full result if the complete model fits in the core.

*/


import DTEngine_Types::*;


module Core (
	input   wire                                   clk,
    input   wire                                   rst_n,
    input   wire								   start_core,

    input   CoreDataIn                             core_data_in,
    input   wire 								   core_data_in_valid,
	output  wire 								   core_data_in_ready,

	// parameters
	input   wire  [NUM_DTPU_CLUSTERS-1:0]          prog_schedule, 
	input   wire  [NUM_DTPU_CLUSTERS-1:0]          proc_schedule, 

	input   wire  [31:0]                           missing_value, 
	input   wire  [15:0]                           tree_feature_index_numcls, 
	input   wire  [15:0]                           tree_weights_numcls, 
	input   wire  [15:0]                           tuple_numcls, 
	input   wire  [3 :0]                           num_levels_per_tree_minus_one, 
	input   wire  [7 :0]                           num_trees_per_pu_minus_one, 
	input   wire  [3 :0]  						   num_clusters_per_tuple,
	input   wire  [3 :0]                      	   num_clusters_per_tuple_minus_one,

	// output 
	output  wire  [DATA_PRECISION-1:0] 			   tuple_out_data, 
	output  wire 								   tuple_out_data_valid, 
	input   wire 								   tuple_out_data_ready,
	//
	output  reg   [31:0]						   data_lines, 
	output  reg   [31:0]						   prog_lines,
	output  reg   [31:0]						   num_out_tuples,

	output  reg   [31:0]						   aggreg_tuples_in,
	output  reg   [31:0]						   aggreg_part_res_in,

	output  reg   [1:0]                            core_state, 
	output  reg 								   started, 
	output  reg   [31:0]                           tuples_passed, 

	output  reg   [31:0] 						   cluster_out_valids, 

	output  wire  [31:0] 						   cluster_tuples_received[NUM_DTPU_CLUSTERS-1:0], 
	output  wire  [31:0] 						   cluster_lines_received[NUM_DTPU_CLUSTERS-1:0],
	output  wire  [31:0] 						   cluster_tuples_res_out[NUM_DTPU_CLUSTERS-1:0],
	output  wire  [31:0] 						   cluster_tree_res_out[NUM_DTPU_CLUSTERS-1:0], 
	output  wire  [31:0] 						   cluster_reduce_tree_outs[NUM_DTPU_CLUSTERS-1:0], 
	output  wire  [31:0] 						   cluster_reduce_tree_outs_valids[NUM_DTPU_CLUSTERS-1:0]

);



localparam DATA_LINE_DISTR_LEVELS = (NUM_DTPU_CLUSTERS == 8)? 3 : 
                                    (NUM_DTPU_CLUSTERS == 4)? 2 : 1;


localparam [1:0]  	IDLE         = 2'b00,
					PROG_MODE    = 2'b01,
					PROCESS_MODE = 2'b10,
					ENGINE_DONE  = 2'b11;


reg 	[1:0]  							core_fsm_state;
reg 	     					   		init_w;
reg 		  					   		init_idx;
reg 		  							init_p;

wire 									InDataFIFO_re;
wire 									InDataFIFO_empty;
wire 									InDataFIFO_valid_out;
wire 									InDataFIFO_full;
CoreDataIn 							    InDataFIFO_dout;

reg 								   	shift_enable;
reg     [NUM_DTPU_CLUSTERS_BITS-1:0]  	shift_count;
reg     [NUM_DTPU_CLUSTERS-1:0]       	schedule_to_shift;
wire    [NUM_DTPU_CLUSTERS-1:0]       	shifted_schedule;

reg 									data_line_distr_valid[DATA_LINE_DISTR_LEVELS:0][(2**DATA_LINE_DISTR_LEVELS)-1:0];
reg 									data_line_distr_last[DATA_LINE_DISTR_LEVELS:0][(2**DATA_LINE_DISTR_LEVELS)-1:0];
reg 									data_line_distr_ctrl[DATA_LINE_DISTR_LEVELS:0][(2**DATA_LINE_DISTR_LEVELS)-1:0];
reg 	[1:0]							data_line_distr_mode[DATA_LINE_DISTR_LEVELS:0][(2**DATA_LINE_DISTR_LEVELS)-1:0];
reg     [NUM_DTPU_CLUSTERS-1:0]     	data_line_distr_en[DATA_LINE_DISTR_LEVELS:0][(2**DATA_LINE_DISTR_LEVELS)-1:0];
reg 	[2:0]							curr_pu;
reg     [2:0]                       	data_line_distr_pu[DATA_LINE_DISTR_LEVELS:0][(2**DATA_LINE_DISTR_LEVELS)-1:0];
reg     [2:0]                       	num_trees_sent_to_cluster;
reg     [DATA_BUS_WIDTH-1:0] 			data_line_distr[DATA_LINE_DISTR_LEVELS:0][(2**DATA_LINE_DISTR_LEVELS)-1:0];

wire									data_line_valid_array[NUM_DTPU_CLUSTERS-1:0];
wire									data_line_last_array[NUM_DTPU_CLUSTERS-1:0];
wire									data_line_ctrl_array[NUM_DTPU_CLUSTERS-1:0];
wire	[1:0]							data_line_mode_array[NUM_DTPU_CLUSTERS-1:0];
wire    [2:0]                       	data_line_pu_array[NUM_DTPU_CLUSTERS-1:0];
wire    [NUM_DTPU_CLUSTERS-1:0]    		data_line_en_array[NUM_DTPU_CLUSTERS-1:0];
wire    [DATA_BUS_WIDTH-1:0] 			data_line_array[NUM_DTPU_CLUSTERS-1:0];
wire									data_line_ready_array[NUM_DTPU_CLUSTERS-1:0];

wire    [DATA_PRECISION-1:0]            partial_aggregation_out[NUM_DTPU_CLUSTERS-1:0];
wire                                  	partial_aggregation_out_valid[NUM_DTPU_CLUSTERS-1:0];
wire                                  	partial_aggregation_out_ready[NUM_DTPU_CLUSTERS-1:0];

wire    [NUM_DTPU_CLUSTERS-1:0] 	   	clusters_ready;
wire    								target_clusters_ready;

wire   	[NUM_DTPU_CLUSTERS_BITS-1:0]    curr_cluster;
wire 							 	    curr_cluster_valid;

reg    	[31:0]                    		partial_leaf_aggreg_value;
reg    		                     		partial_leaf_aggreg_value_valid;
reg    		                     		partial_leaf_aggreg_value_last;
reg    	[NUM_DTPU_CLUSTERS_BITS-1:0]    tuple_cluster_offset;
reg    	[NUM_DTPU_CLUSTERS_BITS-1:0]    tuple_cluster_base;
wire                                	aggregator_ready;

reg 									start_core_d1;
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Core State Machine               /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
always@(posedge clk) begin 
	if(~rst_n) begin
		start_core_d1 <= 0;
	end
	else begin 
		start_core_d1 <= start_core;
	end
end
always@(posedge clk) begin
	if(~rst_n | start_core) begin
		core_fsm_state          <= IDLE;
		init_w                  <= 0;
		init_idx                <= 0;
		init_p                  <= 0;

		data_lines              <= 0;
		prog_lines              <= 0;

		aggreg_tuples_in   <= 0;
		aggreg_part_res_in <= 0;

		cluster_out_valids <= 0;

		num_out_tuples <= 0;

		core_state <= IDLE;

		started  <= 0;
	end 
	else begin

		core_state <= core_fsm_state;
		//
		if(InDataFIFO_valid_out & InDataFIFO_dout.data_valid & InDataFIFO_re) begin
			data_lines <= data_lines + 1'b1;
		end

		if(InDataFIFO_valid_out & ~InDataFIFO_dout.data_valid & InDataFIFO_re) begin
			prog_lines <= prog_lines + 1'b1;
		end

		if(tuple_out_data_valid & tuple_out_data_ready) begin
			num_out_tuples <= num_out_tuples + 1'b1;
		end

		if(partial_leaf_aggreg_value_valid & aggregator_ready & partial_leaf_aggreg_value_last) begin
			aggreg_tuples_in <= aggreg_tuples_in + 1'b1;
		end

		if(partial_leaf_aggreg_value_valid & aggregator_ready) begin
			aggreg_part_res_in <= aggreg_part_res_in + 1'b1;
		end

		if(partial_aggregation_out_valid[0]) begin
			cluster_out_valids <= cluster_out_valids + 1'b1;
		end

		case (core_fsm_state)
			IDLE: begin 

				started <= 0;

				if( start_core ) begin 
					core_fsm_state      <= PROG_MODE;
					started <= 1'b1;
				end

				init_w                  <= 0;
				init_idx                <= 0;
				init_p                  <= 0;
			end
			PROG_MODE: begin 
			    // Programming mode is done when all trees are written to their destination PU
				if(InDataFIFO_valid_out & InDataFIFO_dout.data_valid) begin 
					core_fsm_state <= PROCESS_MODE;
					init_p         <= 1'b1;
				end
				else if(InDataFIFO_valid_out) begin
					init_w   <= init_w   | InDataFIFO_dout.prog_mode;
					init_idx <= init_idx | ~InDataFIFO_dout.prog_mode;
				end
			end
			PROCESS_MODE: begin 
				
			end
		endcase
	end
end



quick_fifo  #(.FIFO_WIDTH($bits(CoreDataIn)),     // data + data valid flag + last flag + prog flags        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) InDataFIFO (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (core_data_in),
        .we                 (core_data_in_valid),

        .re                 (InDataFIFO_re),
        .dout               (InDataFIFO_dout),
        .empty              (InDataFIFO_empty),
        .valid              (InDataFIFO_valid_out),
        .full               (InDataFIFO_full),
        .count              (),
        .almostfull         ()
    );

assign core_data_in_ready = ~InDataFIFO_full;

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////         Distributing Received Data          /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
    We read data from the input FIFO and redistribute it to the clusters. The mapping of 
    trees/tuples to clusters is dictated by "prog_schedule, and "proc_schedule". 
*/

RLS  #(.DATA_WIDTH(NUM_DTPU_CLUSTERS),
	   .DATA_WIDTH_BITS(NUM_DTPU_CLUSTERS_BITS)
	) schedule_shifter(
	.clk            (clk),
	.rst_n          (rst_n & ~start_core),
	.shift_enable   (shift_enable),
	.data_in        (schedule_to_shift),
	.shift_count    (shift_count),
	.data_out       (shifted_schedule)
   );

always @(*) begin
	if(InDataFIFO_valid_out) begin
		if(~InDataFIFO_dout.data_valid) begin
			shift_enable = InDataFIFO_dout.last & (num_trees_sent_to_cluster == NUM_PUS_PER_CLUSTER-1);

			shift_count  = {{(NUM_DTPU_CLUSTERS_BITS-1){1'b0}}, 1'b1};

			if( (init_w & InDataFIFO_dout.prog_mode) | (init_idx & ~InDataFIFO_dout.prog_mode) ) begin 
				schedule_to_shift = shifted_schedule;
			end
			else begin 
				schedule_to_shift = prog_schedule;
			end
		end
		else begin 
			shift_enable = InDataFIFO_dout.last & target_clusters_ready;

			shift_count  = num_clusters_per_tuple[NUM_DTPU_CLUSTERS_BITS-1:0];

			if(init_p) begin
				schedule_to_shift = shifted_schedule;
			end
			else begin
				schedule_to_shift = proc_schedule;
			end
		end
	end
	else begin 
		shift_enable      = 0;
		shift_count       = 0;
		schedule_to_shift = shifted_schedule;
	end
end

// Read & Split lines

always @(posedge clk) begin
	if (~rst_n) begin
		data_line_distr_valid[0][0]  <= 0;
		data_line_distr_last[0][0]   <= 0;
		data_line_distr_ctrl[0][0]   <= 0;
		data_line_distr_mode[0][0]   <= 0;
		data_line_distr_en[0][0]     <= 0;

		data_line_part            <= 0;
		curr_pu 				  <= 0;
		tuples_passed <= 0;
		num_trees_sent_to_cluster <= 0;
	end
	else begin 
		data_line_distr_ctrl[0][0]  <= start_core_d1 & (core_fsm_state == IDLE);

		if (InDataFIFO_valid_out & (target_clusters_ready | ~InDataFIFO_dout.data_valid)) begin

			if(InDataFIFO_dout.last & InDataFIFO_dout.data_valid & data_line_part) begin
				tuples_passed <= tuples_passed + 1'b1;
			end

			data_line_part              <= ~data_line_part;

			data_line_distr_valid[0][0] <= InDataFIFO_dout.data_valid; 
			data_line_distr_last[0][0]  <= InDataFIFO_dout.last && data_line_part;
			data_line_distr_mode[0][0]  <= {InDataFIFO_dout.prog_mode, InDataFIFO_dout.data_valid};
			
			data_line_distr_pu[0][0]    <= curr_pu;
			data_line_distr_en[0][0]    <= schedule_to_shift;

			if(InDataFIFO_dout.last & data_line_part) begin
				curr_pu <= curr_pu + 1'b1;
			end
		
			// if this is programming data then we count how many trees we send to a cluster
			if(~InDataFIFO_dout.data_valid & InDataFIFO_dout.last & data_line_part) begin
				if(num_trees_sent_to_cluster == NUM_PUS_PER_CLUSTER-1) begin 
					num_trees_sent_to_cluster <= 0;
				end
				else begin 
					num_trees_sent_to_cluster <= num_trees_sent_to_cluster + 1'b1;
				end
			end
		end
		else begin
			data_line_distr_valid[0][0] <= 0;
			data_line_distr_last[0][0]  <= 0;
			data_line_distr_mode[0][0]  <= 0;
		end
	end
end

// select which part of the cache line to distribute
always @(posedge clk) begin
	if(core_fsm_state == IDLE) begin 
		data_line_distr[0][0] <= {152'b0, tuple_numcls, missing_value, tree_feature_index_numcls, tree_weights_numcls, {4'b0, num_levels_per_tree_minus_one}, {8'b0}, num_trees_per_pu_minus_one};
	end
	else if( ~data_line_part ) begin
		data_line_distr[0][0] <= InDataFIFO_dout.data[255:0];
	end
	else begin
		data_line_distr[0][0] <= InDataFIFO_dout.data[511:256];
	end
end

assign InDataFIFO_re = data_line_part & ((InDataFIFO_valid_out & ~InDataFIFO_dout.data_valid) | target_clusters_ready);

assign target_clusters_ready = |(clusters_ready & schedule_to_shift);

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////        Data Line Distribution Tree          /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

genvar i, j;
generate
for ( i = 0; i < DATA_LINE_DISTR_LEVELS; i=i+1) begin: DL1
  	for( j = 0; j < (1<<(i+1)); j = j+1) begin:DL2
  		always @(posedge clk) begin
			data_line_distr[i+1][j]       <= data_line_distr[i][j>>1];
		end

		always @(posedge clk) begin
			if(~rst_n) begin
				data_line_distr_valid[i+1][j] <= 0;
				data_line_distr_last[i+1][j]  <= 0;
				data_line_distr_ctrl[i+1][j]  <= 0;
				data_line_distr_mode[i+1][j]  <= 0;
				data_line_distr_pu[i+1][j]    <= 0;
				data_line_distr_en[i+1][j]    <= 0;
			end
			else begin 
				data_line_distr_valid[i+1][j] <= data_line_distr_valid[i][j>>1];
				data_line_distr_last[i+1][j]  <= data_line_distr_last[i][j>>1];
				data_line_distr_ctrl[i+1][j]  <= data_line_distr_ctrl[i][j>>1];
				data_line_distr_mode[i+1][j]  <= data_line_distr_mode[i][j>>1];
				data_line_distr_pu[i+1][j]    <= data_line_distr_pu[i][j>>1];
				data_line_distr_en[i+1][j]    <= data_line_distr_en[i][j>>1];
			end
			
		end
  	end

end
endgenerate

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////              Engine Clusters                /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
generate
	for (i = 0; i < NUM_DTPU_CLUSTERS; i = i + 1)  begin: clusters
		DTPUCluster cluster_x(

		.clk                                (clk),
		.rst_n                              (rst_n),

		.data_line_in                       (data_line_array[i]),
		.data_line_in_valid                 (data_line_valid_array[i]),
		.data_line_in_last                  (data_line_last_array[i]),
		.data_line_in_ctrl                  (data_line_ctrl_array[i]),
		.data_line_in_mode                  (data_line_mode_array[i]),
		.data_line_in_pu                    (data_line_pu_array[i]),
		.data_line_in_ready                 (data_line_ready_array[i]),

		.partial_tree_node_index_out        (),
		.partial_tree_node_index_out_valid  (),

		.partial_aggregation_out            (partial_aggregation_out[i]),
		.partial_aggregation_out_valid      (partial_aggregation_out_valid[i]),	
		.partial_aggregation_out_ready      (partial_aggregation_out_ready[i]),

		.tuples_received 					(cluster_tuples_received[i]),
		.lines_received 					(cluster_lines_received[i]),
		.tuples_res_out 					(cluster_tuples_res_out[i]),
		.tree_res_out 					    (cluster_tree_res_out[i]), 
		.reduce_tree_outs                   (cluster_reduce_tree_outs[i])	
		);

	assign data_line_array[i]       = data_line_distr[DATA_LINE_DISTR_LEVELS][i];
	assign data_line_valid_array[i] = data_line_distr_valid[DATA_LINE_DISTR_LEVELS][i] & data_line_distr_en[DATA_LINE_DISTR_LEVELS][i][i];
	assign data_line_last_array[i]  = data_line_distr_last[DATA_LINE_DISTR_LEVELS][i]  & data_line_distr_en[DATA_LINE_DISTR_LEVELS][i][i];
	assign data_line_ctrl_array[i]  = data_line_distr_ctrl[DATA_LINE_DISTR_LEVELS][i];
	assign data_line_mode_array[i]  = data_line_distr_mode[DATA_LINE_DISTR_LEVELS][i]  & {2{data_line_distr_en[DATA_LINE_DISTR_LEVELS][i][i]}};
	assign data_line_pu_array[i]    = data_line_distr_pu[DATA_LINE_DISTR_LEVELS][i];

	assign partial_aggregation_out_ready[i] = aggregator_ready & (curr_cluster == i);

	assign clusters_ready[i]        = data_line_ready_array[i];
 end
endgenerate


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Tree Leafs Aggregation           /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////


//---------------- Further aggregating leaf values from multiple clusters --------------------//

assign curr_cluster       = tuple_cluster_base + tuple_cluster_offset;

assign curr_cluster_valid = partial_aggregation_out_valid[curr_cluster];

FPAggregator #(.FP_ADDER_LATENCY(FP_ADDER_LATENCY)) 

 cluster_aggregator(

		.clk                (clk),
		.rst_n              (rst_n),

		.fp_in              (partial_leaf_aggreg_value),
		.fp_in_valid        (partial_leaf_aggreg_value_valid),
		.fp_in_last         (partial_leaf_aggreg_value_last),
		.fp_in_ready        (aggregator_ready),

		.aggreg_out         (tuple_out_data),
		.aggreg_out_valid   (tuple_out_data_valid),
		.aggreg_out_ready   (tuple_out_data_ready)
	);

always @(posedge clk) begin
	if(~rst_n) begin
		partial_leaf_aggreg_value       <= 0;
		partial_leaf_aggreg_value_valid <= 0;
		partial_leaf_aggreg_value_last  <= 1'b0;
		tuple_cluster_offset            <= 0;
		tuple_cluster_base              <= 0;
	end 
	else begin

		//---------------------- Select partial aggregation value from a cluster ----------------------------//
		if(aggregator_ready) begin
			partial_leaf_aggreg_value       <= partial_aggregation_out[curr_cluster];
			partial_leaf_aggreg_value_valid <= curr_cluster_valid;
			partial_leaf_aggreg_value_last  <= 1'b0;

			if(curr_cluster_valid) begin
				if(tuple_cluster_offset == (num_clusters_per_tuple_minus_one) ) begin 
					tuple_cluster_offset <= 0;

					if(num_clusters_per_tuple == NUM_DTPU_CLUSTERS) begin 
						tuple_cluster_base   <= 0;
					end
					else begin 
						tuple_cluster_base   <= tuple_cluster_base + num_clusters_per_tuple[NUM_DTPU_CLUSTERS_BITS-1:0];
					end

					partial_leaf_aggreg_value_last <= 1'b1;
				end
				else begin 
					tuple_cluster_offset <= tuple_cluster_offset + 1'b1;
				end
			end
		end
	end
end

endmodule