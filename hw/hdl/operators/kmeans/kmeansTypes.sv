package kmeansTypes;


parameter NUM_CLUSTER_BITS = 3;
parameter NUM_CLUSTER = 2**NUM_CLUSTER_BITS;
// parameter NUM_CLUSTER = 8;
parameter MAX_DEPTH_BITS = 9;
parameter MAX_DIM_DEPTH = 2**MAX_DEPTH_BITS;
parameter MAX_DIM_WIDTH = 32;
parameter BUFFER_DEPTH_BITS = 9;


parameter NUM_PIPELINE_BITS =4;
parameter NUM_PIPELINE = 2**NUM_PIPELINE_BITS;
// parameter NUM_BANK_BITS = 4;
// parameter NUM_BANK = 2**NUM_BANK_BITS;					


typedef struct packed
{
	logic [15:0] 							num_iteration;	
	logic [63:0] 							data_set_size;
	logic [MAX_DEPTH_BITS:0] 				data_dim;
	logic [31:0] 							num_cl_tuple;
	logic [57:0] 							addr_center;
	logic [57:0] 							addr_data;
	logic [57:0] 							addr_result;
	logic [31:0] 							num_cl_centroid;
	// logic [7:0]								precision;
	logic [31:0]							num_cluster;
} RuntimeParam;

endpackage



