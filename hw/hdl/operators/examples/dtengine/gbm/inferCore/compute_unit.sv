

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


module compute_unit #(parameter CU_ID = 0 )
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

		output  reg   [511:0]                         data_line_out,
		output  reg   								  data_line_out_valid,
		output  reg   [2:0] 						  data_line_out_last_valid_pos, 
		output  reg                                   data_line_out_ctrl,
        output  reg   								  data_line_out_last,
		output  reg     	    					  data_line_out_prog,
		output  reg   [NUM_PUS_PER_CLUSTER_BITS-1:0]  data_line_out_pu,
		output  reg   [NUM_DTPU_CLUSTERS_BITS-1:0]    data_line_out_cu,

		output  wire  [DATA_PRECISION-1:0]            tuple_result_out,
		output  wire                                  tuple_result_out_valid,
		input   wire                                  tuple_result_out_ready

	);


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Signals Declarations             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
wire  [DATA_LINE_WIDTH-1:0]                line_rate_convertor_data_out;
wire  					                   line_rate_convertor_out_valid;
wire  					                   line_rate_convertor_out_last;
wire  					                   line_rate_convertor_out_ctrl;
wire  					                   line_rate_convertor_out_prog;
wire     		   	                       line_rate_convertor_out_ready;
wire  [NUM_PUS_PER_CLUSTER_BITS-1:0]       line_rate_convertor_out_pu;


wire  [DATA_LINE_WIDTH-1:0]                data_line_array[NUM_PUS_PER_CLUSTER:0];
wire  					                   data_line_valid_array[NUM_PUS_PER_CLUSTER:0];
wire  					                   data_line_last_array[NUM_PUS_PER_CLUSTER:0];
wire  					                   data_line_ready_array[NUM_PUS_PER_CLUSTER:0];
wire  					                   data_line_ctrl_array[NUM_PUS_PER_CLUSTER:0];
wire     		   	                       data_line_prog_array[NUM_PUS_PER_CLUSTER:0];
wire  [NUM_PUS_PER_CLUSTER_BITS-1:0]       data_line_pu_array[NUM_PUS_PER_CLUSTER:0];

wire  [DATA_PRECISION-1:0]                 pu_tree_leaf_out[NUM_PUS_PER_CLUSTER-1:0];
wire 									   pu_tree_leaf_out_valid[NUM_PUS_PER_CLUSTER-1:0];
wire 									   pu_tree_leaf_out_last[NUM_PUS_PER_CLUSTER-1:0];

wire  [31:0]							   fp_in_vector[31:0];
wire 									   fp_in_vector_valid[31:0];
wire 									   fp_in_vector_last[31:0];
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Pipeline to next CU              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

always @(posedge clk) begin
	// info
	data_line_out                <= data_line_in;
	data_line_out_pu             <= data_line_in_pu;
	data_line_out_last_valid_pos <= data_line_in_last_valid_pos;
	data_line_out_cu             <= data_line_in_cu;
	data_line_out_last           <= data_line_in_last;

	// valids
	if(~rst_n) begin
		data_line_out_valid <= 1'b0;
		data_line_out_ctrl  <= 1'b0;
		data_line_out_prog  <= 1'b0;
	end
	else begin 
		data_line_out_valid <= data_line_in_valid;
		data_line_out_ctrl  <= data_line_in_ctrl;
		data_line_out_prog  <= data_line_in_prog;
	end
end
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Line Rate Convertor              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

LineRateConvertor #(.CU_ID (CU_ID) ) 
	bus_convertor(
		.clk                              (clk),
		.rst_n                            (rst_n),

		.data_line_in                     (data_line_in),
		.data_line_in_valid               (data_line_in_valid),
		.data_line_in_last_valid_pos      (data_line_in_last_valid_pos),
		.data_line_in_last                (data_line_in_last),
		.data_line_in_ctrl                (data_line_in_ctrl),
		.data_line_in_prog                (data_line_in_prog),
		.data_line_in_pu                  (data_line_in_pu),
		.data_line_in_cu                  (data_line_in_cu),
		.data_line_in_ready               (data_line_in_ready),


		.data_line_out                    (line_rate_convertor_data_out),
		.data_line_out_valid              (line_rate_convertor_out_valid),
		.data_line_out_ctrl               (line_rate_convertor_out_ctrl),
		.data_line_out_last               (line_rate_convertor_out_last),
		.data_line_out_prog               (line_rate_convertor_out_prog),
		.data_line_out_pu                 (line_rate_convertor_out_pu),
		.data_line_out_ready              (line_rate_convertor_out_ready)
	);


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////          Generate DTPU Instances            /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

// initialize input to first PU
assign data_line_array[0]       = line_rate_convertor_data_out;
assign data_line_valid_array[0] = line_rate_convertor_out_valid;
assign data_line_last_array[0]  = line_rate_convertor_out_last;
assign data_line_ctrl_array[0]  = line_rate_convertor_out_ctrl;
assign data_line_prog_array[0]  = line_rate_convertor_out_prog;
assign data_line_pu_array[0]    = line_rate_convertor_out_pu;

assign line_rate_convertor_out_ready = data_line_ready_array[0];


// generate a cascade of PUs
genvar i;
generate 
    for (i = 0; i < NUM_PUS_PER_CLUSTER; i = i + 1) begin: pus
		processing_element_async #(.PE_ID (i) ) 
		pe_x(
		.clk                              (clk),
		.rst_n                            (rst_n),

		.data_line_in                     (data_line_array[i]),
		.data_line_in_valid               (data_line_valid_array[i]),
		.data_line_in_last                (data_line_last_array[i]),
		.data_line_in_ctrl                (data_line_ctrl_array[i]),
		.data_line_in_prog                (data_line_prog_array[i]),
		.data_line_in_pu                  (data_line_pu_array[i]),
		.data_line_in_ready               (data_line_ready_array[i]),

		.data_line_out                    (data_line_array[i+1]),
		.data_line_out_valid              (data_line_valid_array[i+1]),
		.data_line_out_ctrl               (data_line_ctrl_array[i+1]),
		.data_line_out_last               (data_line_last_array[i+1]),
		.data_line_out_prog               (data_line_prog_array[i+1]),
		.data_line_out_pu                 (data_line_pu_array[i+1]),

		.pu_tree_leaf_out                 (pu_tree_leaf_out[i]),
		.pu_tree_leaf_out_valid           (pu_tree_leaf_out_valid[i]),
		.pu_tree_leaf_out_last            (pu_tree_leaf_out_last[i])
		);
	end
endgenerate
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////         Instance of FPAdders Tree           /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

generate for (i = 0; i < 32; i=i+1) begin
	if( i < NUM_PUS_PER_CLUSTER ) begin
		assign fp_in_vector[i]       = pu_tree_leaf_out[i];
		assign fp_in_vector_valid[i] = pu_tree_leaf_out_valid[i];
		assign fp_in_vector_last[i]  = pu_tree_leaf_out_last[i];
	end
	else begin 
		assign fp_in_vector[i]       = 32'b0;
		assign fp_in_vector_valid[i] = 1'b0;
		assign fp_in_vector_last[i]  = 1'b0;
	end
end
endgenerate

FPAddersReduceTree_sync #(.NUM_FP_POINTS(32)
	) reduce_leaves(
		.clk                (clk),
		.rst_n              (rst_n),

		.fp_in_vector       (fp_in_vector),
		.fp_in_vector_valid (fp_in_vector_valid),
		.fp_in_vector_last  (fp_in_vector_last),

		.reduce_out         (tuple_result_out),
		.reduce_out_valid   (tuple_result_out_valid),
		.reduce_out_ready   (tuple_result_out_ready)
	);


endmodule 












