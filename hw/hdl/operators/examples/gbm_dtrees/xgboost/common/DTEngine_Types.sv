
package DTEngine_Types;

parameter   DATA_BUS_WIDTH                  = 512;

parameter   NUM_PUS_PER_CLUSTER_BITS        = 2;
parameter   NUM_PUS_PER_CLUSTER             = 4;
parameter   NUM_DTPU_CLUSTERS 		        = 8;
parameter   NUM_DTPU_CLUSTERS_BITS          = 3;
parameter   NUM_TREES_PER_PU                = 32;

parameter   FEATURES_DISTR_DELAY            = 8;

parameter   DATA_PRECISION                  = 32;
parameter   FIXED_POINT_ARITHMATIC          = ((DATA_PRECISION < 32)? 1 : 0);

parameter   TREE_WEIGHTS_PROG               = 1'b0;
parameter   TREE_FEATURE_INDEX_PROG         = 1'b1;

parameter   WAIT_CYCLES_FOR_LAST_TREE       = 16;
parameter   FP_ADDER_LATENCY                = 2;



// Streams types
parameter  [15:0]     	                    DATA_STREAM        = 1, 
											TREE_WEIGHT_STREAM = 2, 
											TREE_FINDEX_STREAM = 3, 
											RESULTS_STREAM     = 4;




typedef struct packed
{
	logic  [DATA_BUS_WIDTH-1:0]         data;
	logic                               data_valid;
	logic                               last;
	logic                               prog_mode;  //1: weights, 0 feature indexes
} CoreDataIn;




endpackage




