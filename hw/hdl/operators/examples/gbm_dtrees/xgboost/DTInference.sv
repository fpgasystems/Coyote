
/*
     The PCIe RX unit receives data/ trees to local core and other cores in the FPGA network
     it has a list of all devices addresses, and number of trees (numcls )per core

     While receiving trees it count lines and determine for which device to send them, or it broadcast 
     them to all devices if configured to do that.

     While receiving data it either broadcast the data to all devices if configured that way. Or, it 
     distribute batches of data to each device one after the other.

     Modes of Operation:

     - Tree ensemble spread over all the FPGAs and a tuple is broadcasted to all FPGAs 
       Partial results are forwarded from an FPGA to another and aggregate results.

       We batch at least 4 results together so we send full 128-bit line 

     - Tree Ensemble fits in one FPGA and we partition tuples between FPGAs. 
       For ordering and schedling reasons, we batch every 4 consecutive tuples to one FPGA
       so results from one FPGA are in order. 
*/


import DTEngine_Types::*;

module DTInference (
	input  wire                         clk,    // Clock
	input  wire                         rst_n,  // Asynchronous reset active low

	input   wire 						start_core,

	input   wire  [15:0] 				tuple_numcls, 
	input   wire  [15:0] 				tree_weights_numcls_minus_one;        
	input   wire  [15:0] 				tree_feature_index_numcls_minus_one;
	input   wire  [4:0]					num_trees_per_pu_minus_one, 
	input   wire  [3:0] 				tree_depth, 
	input   wire  [8-1:0]       	    prog_schedule, 
    input   wire  [8-1:0]       	    proc_schedule,
	// input trees
	input   wire  [511:0]               core_in,
	input   wire  [1  :0] 				core_in_type,  // 01: trees weights, 00: feature indexes, 10: data
    input   wire 						core_in_valid,
    input   wire 						core_in_last, 
	output  wire 						core_in_ready,
	// output 
	output  reg   [511:0] 			    core_result_out, 
	output  wire  						core_result_valid, 
	input   wire 						core_result_ready
	);



////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Signals Declarations             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

wire 									start_core;                           // Triggers the operator

//wire  [3 :0]  							num_clusters_per_tuple;               // Number of Clusters store the complete model
//wire  [3 :0]                      		num_clusters_per_tuple_minus_one;     

// Core
CoreDataIn                            	core_data_in;
wire 								   	core_data_in_valid;
wire 								   	core_data_in_ready;

// ResultsCombiner
wire   [31:0]  			                local_core_result; 
wire 									local_core_result_valid; 
wire 									local_core_result_ready; 

reg    [31:0] 							core_result_out_array[15:0];
reg 									res_line_valid;
reg    [3:0] 							curr_out_word;

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////                 Engine Core                 /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

assign core_data_in.data       = core_in;
assign core_data_in.data_valid = core_in_type[1];
assign core_data_in.last       = core_in_last;
assign core_data_in.prog_mode  = core_in_type[0];
assign core_data_in_valid      = core_in_valid;

assign core_in_ready           = core_data_in_ready;


Core engine_core(
	.clk                                (clk),
    .rst_n                              (rst_n),
    .start_core                         (start_core),

    .core_data_in                       (core_data_in),
    .core_data_in_valid                 (core_data_in_valid),
	.core_data_in_ready                 (core_data_in_ready),

	// parameters
	.prog_schedule                      (prog_schedule), 
	.proc_schedule                      (proc_schedule), 

	.missing_value                      (0), 
	.tree_feature_index_numcls          (tree_feature_index_numcls_minus_one), 
	.tree_weights_numcls                (tree_weights_numcls_minus_one), 
	.tuple_numcls                       (tuple_numcls), 
	.num_levels_per_tree_minus_one      (tree_depth), 
	.num_trees_per_pu_minus_one         (num_trees_per_pu_minus_one), 
	.num_clusters_per_tuple             (NUM_DTPU_CLUSTERS),
	.num_clusters_per_tuple_minus_one   (NUM_DTPU_CLUSTERS-1),

	// output 
	.tuple_out_data                     (local_core_result), 
	.tuple_out_data_valid               (local_core_result_valid), 
	.tuple_out_data_ready               (local_core_result_ready), 
    
    .data_lines                         (), 
    .prog_lines                         (),
    .num_out_tuples                     (),
    .aggreg_tuples_in                   (),
    .aggreg_part_res_in                 (),
    .core_state                         (), 
    .started                            (), 
    .tuples_passed                      (), 
    .cluster_out_valids 				(),

    .cluster_tuples_received 			(),
	.cluster_lines_received 			(),
	.cluster_tuples_res_out 			(),
	.cluster_tree_res_out 				(), 	
	.cluster_reduce_tree_outs 			(), 
	.cluster_reduce_tree_outs_valids    ()
);

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               PCIe Transmitter              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

assign local_core_result_ready = core_result_ready || (curr_out_word != 4'h0);

always@(posedge clk) begin 
	if(~rst_n || start_core) begin
		curr_out_word  <= 4'h0;
		res_line_valid <= 1'b0;
	end
	else begin 
		// counter
		if(local_core_result_valid) begin
			if(curr_out_word == 4'h0) begin
				if(core_result_ready) begin
					curr_out_word <= curr_out_word + 1'b1;
				end
			end
			else begin 
				curr_out_word <= curr_out_word + 1'b1;
			end
		end

		//
		if(res_line_valid) begin
			if(core_result_ready) begin
				res_line_valid <= 1'b0;
			end
		end
		else if( (curr_out_word == 4'hF) && local_core_result_valid) begin
			res_line_valid <= 1'b1;
		end
	end

	// Fill in output data line
	if((curr_out_word != 4'h0) || core_result_ready) begin
		core_result_out_array[curr_out_word] <= local_core_result;
	end
end

//
always@(*) begin 
	for(i = 0; i < 16; i=i+1) begin
		core_result_out[i*32+32-1:i*32] = core_result_out_array[i];
	end
end

assign core_result_valid = res_line_valid;


endmodule

