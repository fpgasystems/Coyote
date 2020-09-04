
import DTEngine_Types::*;

/*
    PU Constraits: 
    - MAX NUMBER OF TREE NODES IN TOTAL IT CAN HANDLE:  8192: 2^13
    - MAX NUMBER OF FEATURES PER TUPLE IT CAN HANDLE:   4096: 2^12
    - MAX NUMBER OF TREE DEPTH IT CAN HANDLE: Hybrid    -> log2(8192/NUM_TREES) Levels on FPGA + rest on CPU, 
                                              FPGA Only -> log2(8192/NUM_TREES) Levels including LEAFS.
    

*/

module DTPU #(parameter PU_ID                    = 0
	          )(

		input   wire  								 clk,
		input   wire 							     rst_n,

		input   wire  [DATA_BUS_WIDTH-1:0]           data_line_in,
		input   wire  								 data_line_in_valid,
		input   wire  								 data_line_in_last,
		input   wire  								 data_line_in_ctrl,
		input   wire  [1:0]	    					 data_line_in_mode,
		input   wire  [NUM_PUS_PER_CLUSTER_BITS-1:0] data_line_in_pu,
		output  reg 								 data_line_in_ready,

		output  reg   [DATA_BUS_WIDTH-1:0]           data_line_out,
		output  reg   								 data_line_out_valid,
		output  reg                                  data_line_out_ctrl,
        output  reg   								 data_line_out_last,
		output  reg   [1:0]	    					 data_line_out_prog,
		output  reg   [NUM_PUS_PER_CLUSTER_BITS-1:0] data_line_out_pu,

		output  reg   [15:0]                         pu_tree_node_index_out,
		output  reg                                  pu_tree_node_index_out_valid,

		output  wire  [DATA_PRECISION-1:0]           pu_tree_leaf_out,
		output  wire                                 pu_tree_leaf_out_valid,
		output  wire                                 pu_tree_leaf_out_last

	);



////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               Local Parameters              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////



localparam  MAX_NUMBER_OF_TREES_BITS        = 4;
localparam  MAX_TREE_DEPTH_BITS      		= 4;

localparam  MAX_NUM_TUPLE_FEATURES_BITS 	= 11;
localparam  MAX_NUM_TREE_NODES_BITS     	= 13;
localparam  NODE_WORD_OFFSET_BITS       	= 2;           
localparam  NUM_WORDS_PER_LINE          	= 4;
localparam  NODE_FEATURE_INDEX_WIDTH    	= 16;

localparam  MEM_OUTPUT_PIPELINE_DEPTH   = 2;
localparam  INDEXES_PER_LINE_BITS       = (DATA_BUS_WIDTH == 256)? 4 : 
                                          (DATA_BUS_WIDTH == 128)? 3 : 2;


localparam  FINDEX_OFFSET_BITS          = MAX_NUM_TREE_NODES_BITS     - INDEXES_PER_LINE_BITS; 
localparam  TUPLE_OFFSET_BITS           = MAX_NUM_TUPLE_FEATURES_BITS - NODE_WORD_OFFSET_BITS; // Feature memory max depth is 512
localparam  TREE_OFFSET_BITS            = MAX_NUM_TREE_NODES_BITS     - NODE_WORD_OFFSET_BITS; // Weights memory max depth is 1024

localparam  READ_TNODE_LATENCY          = 1+MEM_OUTPUT_PIPELINE_DEPTH;
localparam  READ_FEATURE_LATENCY        = 1+MEM_OUTPUT_PIPELINE_DEPTH;

localparam  INSTRUCTION_DELAY           = 3+7 - PU_ID;       // PU pipeline depth-1 - PU_ID
localparam  INSTRUCTION_DELAY_NEGATIVE  = -1*(3+7 - PU_ID);       // PU pipeline depth-1 - PU_ID

localparam  INSTRUCTION_WIDTH     = TREE_OFFSET_BITS + TREE_OFFSET_BITS + TUPLE_OFFSET_BITS + 1 +  1;

localparam  NUM_TREES_PER_PU_BITS = MAX_NUMBER_OF_TREES_BITS;
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Signals Declarations             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

wire 									TWM_reb;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     TWM_res_raddr;
wire                                    TWM_wen;
wire                                    TWM_rea;
wire                                    TWM_res_valid;
wire                                    TWM_weight_valid;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     TWM_weight_wraddr;
wire  [DATA_BUS_WIDTH-1:0]            TWM_wr_data;
wire  [DATA_PRECISION-1:0]             TWM_res_data;
wire  [DATA_PRECISION-1:0]             TWM_weight_data;

reg   [TREE_OFFSET_BITS-1: 0]           tree_prog_addr;
reg   [NUM_TREES_PER_PU_BITS-1:0]       local_num_trees;

wire 								    TFI_wen;
wire 								    TFI_ren;
wire 								    TFI_rd_data_valid;

reg   [FINDEX_OFFSET_BITS-1:0]          TFI_wr_addr;
wire  [DATA_BUS_WIDTH-1:0]            TFI_wr_data;

wire  [MAX_NUM_TREE_NODES_BITS-1:0]     TFI_rd_addr;
wire  [NODE_FEATURE_INDEX_WIDTH-1:0]    TFI_rd_data;

wire 								    features_wen;
wire 								    features_ren;
wire 								    features_rd_data_valid;

reg   [TUPLE_OFFSET_BITS-1:0]           features_wr_addr;
wire  [DATA_BUS_WIDTH-1:0]            features_wr_data;

wire  [MAX_NUM_TUPLE_FEATURES_BITS-1:0] features_rd_addr;
wire  [DATA_PRECISION-1:0]             features_rd_data; 

reg   [TUPLE_OFFSET_BITS-1:0]           tuple_offset; 
reg 									tuple_valid;
reg 									tuple_offset_set;  

reg   [MAX_NUMBER_OF_TREES_BITS-1:0]    num_trees_per_pu_minus_one;
reg 								    PartialTrees;
reg   [MAX_TREE_DEPTH_BITS-1:0]         LastLevelIndex;
reg   [TREE_OFFSET_BITS-1:0]            num_lines_per_tree_weights;
reg   [TREE_OFFSET_BITS-1:0]            num_lines_per_tree_findex;

wire  									delayed_instruction_we;
wire  									delayed_instruction_re;
wire  									delayed_instruction_valid_f;
wire  [TUPLE_OFFSET_BITS+19:0]    delayed_instruction_i;
wire  [TUPLE_OFFSET_BITS+19:0]   delayed_instruction_o;
reg   [3:0]                             instr_delay_cycles;
reg  								    tuple_instruction_valid;
reg   [TREE_OFFSET_BITS-1:0]            curr_tree_w_offset;
reg   [TREE_OFFSET_BITS-1:0]            curr_tree_f_offset;
reg   [MAX_NUMBER_OF_TREES_BITS-1:0]    curr_tree_index;
wire 								    last_tree;
wire 								    instr_NOP;
wire 								    tuple_instruction_we;
wire 								    tuple_instruction_re;
wire 								    tuple_instruction_valid_f;
wire  [INSTRUCTION_WIDTH-1:0]           tuple_instruction;

wire  [TREE_OFFSET_BITS-1:0]            tree_w_offset_s1;
wire  [TREE_OFFSET_BITS-1:0]            tree_w_offset_d1;
wire  [TREE_OFFSET_BITS-1:0]            tree_f_offset_s1;
wire  [TREE_OFFSET_BITS-1:0]            tree_f_offset_d1;

wire  [MAX_NUM_TREE_NODES_BITS-1:0]     tree_node_offset_s1;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     tree_w_node_addr_s1;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     tree_f_node_addr_s1;

wire  [MAX_NUM_TREE_NODES_BITS-1:0]     next_tree_node_offset_s1;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     next_tree_w_node_addr_s1;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     next_tree_f_node_addr_s1;

wire  [MAX_NUM_TREE_NODES_BITS-1:0]     next_tree_node_offset_d1;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     next_tree_w_node_addr_d1;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     next_tree_f_node_addr_d1;

wire  [TUPLE_OFFSET_BITS-1:0]           tuple_offset_s1;
wire  [TUPLE_OFFSET_BITS-1:0]           tuple_offset_d1;

wire  								    tree_instr_NOP_s1;
wire  								    last_tree_s1;
wire  [MAX_TREE_DEPTH_BITS-1:0]         tree_node_level_s1;
wire  								    tree_instr_NOP_d1;
wire  								    last_tree_d1;
wire  [MAX_TREE_DEPTH_BITS-1:0]         tree_node_level_d1;

wire 								    tree_node_ren;

wire  [DATA_PRECISION-1:0]             weight_data_d2;
wire  [2:0]                             feature_index_data_d2;
wire 									tree_node_rd_stage_valid;
wire 									feature_rd_stage_valid;

wire  								    tree_instr_NOP_d2;
wire  								    last_tree_d2;
wire  [MAX_TREE_DEPTH_BITS-1:0]         tree_node_level_d2;

wire  [TUPLE_OFFSET_BITS-1:0]           tuple_offset_d2;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     next_tree_node_offset_d2;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     next_tree_w_node_addr_d2;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     next_tree_f_node_addr_d2;
wire  [TREE_OFFSET_BITS-1:0]            tree_f_offset_d2;
wire  [TREE_OFFSET_BITS-1:0]            tree_w_offset_d2;

wire 									isFeatureMissing;
wire 									isFeatureSmaller;
wire 									isRightChild;
wire 									isMissingRight;
wire 									isNextNodeLeaf;
wire 									isLastLevel;
wire 									goToOutput;
wire 									goToOutput_d3;

wire 									incrementNodeOffset;
wire 									incrementNodeOffset_d3;
wire                                    comparison_stage_valid;

wire  [TUPLE_OFFSET_BITS-1:0]           tuple_offset_d3;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     next_tree_node_offset_d3;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     next_tree_w_node_addr_d3;
wire  [MAX_NUM_TREE_NODES_BITS-1:0]     next_tree_f_node_addr_d3;
wire  [TREE_OFFSET_BITS-1:0]            tree_f_offset_d3;
wire  [TREE_OFFSET_BITS-1:0]            tree_w_offset_d3;

wire  								    tree_instr_NOP_d3;
wire  								    last_tree_d3;
wire  [MAX_TREE_DEPTH_BITS-1:0]         tree_node_level_d3;

reg  									tree_instruction_valid;
reg  									tree_output_valid;
reg  									tree_instruction_type_NOP;
reg  									tree_instruction_type_EMPTY;
reg  									tree_instruction_last_flag;

reg   [TREE_OFFSET_BITS-1:0]            tree_instruction_tree_w_offset;
reg   [TREE_OFFSET_BITS-1:0]            tree_instruction_tree_f_offset;

reg   [MAX_NUM_TREE_NODES_BITS-1:0]     tree_instruction_node_w_addr;
reg   [MAX_NUM_TREE_NODES_BITS-1:0]     tree_instruction_node_f_addr;

reg   [TUPLE_OFFSET_BITS-1:0]           tree_instruction_tuple_offset;
reg   [MAX_NUM_TREE_NODES_BITS-1:0]     tree_instruction_node_offset;

reg   [MAX_TREE_DEPTH_BITS-1:0]         tree_instruction_node_level;

reg   [31:0]                            MissingFeatureValue;

wire 									TupleInstrctionFIFO_full;

reg   [9:0] 							features_mem_count;
reg   [9:0] 							tuple_numlines;

wire  									delayed_instruction_fifo_almostfull;
wire  									delayed_instruction_fifo_full;

reg   [31:0] 							num_tuples_received;

reg   [19:0] 							time_stamp;
wire  [20:0] 							time_stamp_diff;
wire  									tuple_old_enough;
reg   									tuple_old_enough_set;

wire                                    pu_tree_leaf_zero;
wire                                    tree_instr_EMPTY_s1;
wire                                    tree_instr_EMPTY_d1;
wire                                    tree_instr_EMPTY_d2;
wire                                    tree_instr_EMPTY_d3;

wire 									curr_feature_done;
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////                Memory Banks                 /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////


//----------------------------- Tree Nodes Weight memory ------------------------------//
Mem1in2out #( .DATA_WIDTH(DATA_BUS_WIDTH),
              .ADDR_WIDTH(TREE_OFFSET_BITS),
              .LINE_ADDR_WIDTH(NODE_WORD_OFFSET_BITS), 
              .WORD_WIDTH(DATA_PRECISION),
              .NUM_PIPELINE_LEVELS(MEM_OUTPUT_PIPELINE_DEPTH) )  
WeightsMem(

    .clk         (clk),
    .rst_n       (rst_n),
    .we          (TWM_wen),
    .rea         (TWM_rea),
    .reb         (TWM_reb),
    .raddr       (TWM_res_raddr),
    .wraddr      (TWM_weight_wraddr),  
    .din         (TWM_wr_data),
    .dout1       (TWM_weight_data),
    .valid_out1  (TWM_weight_valid),
    .dout2       (TWM_res_data),
    .valid_out2  (TWM_res_valid)
);


assign TWM_wen     = ~data_line_in_mode[0] & data_line_in_mode[1] & (data_line_in_pu == PU_ID);
assign TWM_wr_data = data_line_in;

always @(posedge clk) begin
	if(~rst_n) begin
		tree_prog_addr    <= 0;
		local_num_trees   <= 0;
	end 
	else if(TWM_wen) begin
		tree_prog_addr    <= tree_prog_addr + 1'b1;

		if(data_line_in_last) begin 
			local_num_trees <= local_num_trees + 1'b1;
		end
	end
end

//------------------------ Tree Nodes Feature indexes memory --------------------------//
DualPortMem #( .DATA_WIDTH(DATA_BUS_WIDTH),
               .ADDR_WIDTH(FINDEX_OFFSET_BITS),
               .WORD_WIDTH(NODE_FEATURE_INDEX_WIDTH),
               .LINE_ADDR_WIDTH(INDEXES_PER_LINE_BITS),
               .NUM_PIPELINE_LEVELS(MEM_OUTPUT_PIPELINE_DEPTH) ) 
TreeFeatureIndex_Mem(

    .clk        (clk),
    .rst_n      (rst_n),
    .we         (TFI_wen),
    .re         (TFI_ren),
    .raddr      (TFI_rd_addr),
    .waddr      (TFI_wr_addr),  
    .din        (TFI_wr_data),
    .dout       (TFI_rd_data),
    .valid_out  (TFI_rd_data_valid)
);

assign TFI_ren     = tree_node_ren;
assign TFI_rd_addr = tree_f_node_addr_s1;

assign TFI_wen     = ~data_line_in_mode[0] & ~data_line_in_mode[1] & (data_line_in_pu == PU_ID);
assign TFI_wr_data = data_line_in;


always @(posedge clk) begin
	if(~rst_n) begin
		TFI_wr_addr       <= 0;
	end 
	else if(TFI_wen) begin
		TFI_wr_addr       <= TFI_wr_addr + 1'b1;
	end
end
//--------------------------- Input tuple features memory -----------------------------//

/* We write to the features memory when flags indicate 
   incoming data is tuples and nor programming data
*/
DualPortMem #( .DATA_WIDTH(DATA_BUS_WIDTH),
               .ADDR_WIDTH(TUPLE_OFFSET_BITS),
               .WORD_WIDTH(DATA_PRECISION),
               .LINE_ADDR_WIDTH(NODE_WORD_OFFSET_BITS),
               .NUM_PIPELINE_LEVELS(MEM_OUTPUT_PIPELINE_DEPTH) ) 
SamplesFeatures_Mem(

    .clk        (clk),
    .rst_n      (rst_n),
    .we         (features_wen),
    .re         (features_ren),
    .raddr      (features_rd_addr),
    .waddr      (features_wr_addr),  
    .din        (features_wr_data),
    .dout       (features_rd_data),
    .valid_out  (features_rd_data_valid)
);


always @(posedge clk) begin
	if(~rst_n) begin
		features_wr_addr <= 9'b0;
		tuple_offset     <= 0;
		tuple_offset_set <= 0;
		//tuple_valid      <= 0;
	end 
	else begin
		if(~tuple_offset_set) begin 
			tuple_offset     <= features_wr_addr;
		end
		if(features_wen) begin
			features_wr_addr <= features_wr_addr + 1'b1;
			tuple_offset_set <= ~data_line_in_last;
		end
		//tuple_valid <= features_wen & data_line_in_last; 
	end
end

assign features_wen      = data_line_in_valid;
assign features_wr_data  = data_line_in;
assign curr_feature_done = last_tree_d3 & goToOutput_d3 & comparison_stage_valid;

always @(posedge clk) begin
	if (~rst_n) begin
		// reset
		data_line_in_ready <= 1'b0;
		features_mem_count <= 0;
	end
	else begin
		data_line_in_ready <= (features_mem_count < (512-FEATURES_DISTR_DELAY)) & ~delayed_instruction_fifo_almostfull;

		if(features_wen & curr_feature_done) begin
			features_mem_count <= features_mem_count + 1'b1 - tuple_numlines;
		end
		else if(features_wen) begin
			features_mem_count <= features_mem_count + 1'b1;
		end
		else if (curr_feature_done) begin
			features_mem_count <= features_mem_count - tuple_numlines;
		end
	end
end

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////           PU Programming Logic              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

always @(posedge clk) begin
	if(~rst_n) begin
		num_trees_per_pu_minus_one <= 0;  
		PartialTrees               <= 0;
		LastLevelIndex             <= 0;
		num_lines_per_tree_weights <= 0;
		num_lines_per_tree_findex  <= 0;
        MissingFeatureValue        <= 0;
	end 
	else if(data_line_in_ctrl) begin
		num_trees_per_pu_minus_one <= data_line_in[MAX_NUMBER_OF_TREES_BITS-1:0];    // First Byte  4 bits: MAX NUMBER OF TREES PER PU = 16  
		PartialTrees               <= data_line_in[8];                               // Second Byte  1 bit : 1 means send partial results, 0 all trees fit on the FPGA
		LastLevelIndex             <= data_line_in[16+MAX_TREE_DEPTH_BITS-1:16];     // Third Byte 4 bits: MAX NUMBER OF LEVELS PER TREE = 12 + 1 LEAF LEVEL
		num_lines_per_tree_weights <= {data_line_in[24+TREE_OFFSET_BITS-2:24]};      // B5B4 10 bits: MAX NUMBER OF LINES PER TREE = 1024 (consume all PU memory)
		num_lines_per_tree_findex  <= {data_line_in[40+TREE_OFFSET_BITS-2:40]};      // B7B6 10 bits: MAX NUMBER OF LINES PER TREE = 1024 (consume all PU memory)
        MissingFeatureValue        <= data_line_in[87: 56];                          // B11B10B9B8
        tuple_numlines             <= data_line_in[103:88]; 						 // B13B12
	end
end

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////           Tuple Instruction FIFO            /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/* Once all features of a tuple are in features memory, we enqueue an instruction to execute all the
   trees in the PU on the current tuple features, the instruction simply include the tuple offset.
   
*/

assign delayed_instruction_we = features_wen & data_line_in_last;
assign delayed_instruction_i  = {time_stamp, tuple_offset};

assign delayed_instruction_re = (tuple_old_enough | tuple_old_enough_set) & (curr_tree_index == num_trees_per_pu_minus_one) & ~TupleInstrctionFIFO_full;

quick_fifo  #(.FIFO_WIDTH(TUPLE_OFFSET_BITS+20),        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) DelayedTupleInstrctionFIFO (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (delayed_instruction_i),
        .we                 (delayed_instruction_we),

        .re                 (delayed_instruction_re),
        .dout               (delayed_instruction_o),
        .empty              (),
        .valid              (delayed_instruction_valid_f),
        .full               (delayed_instruction_fifo_full),
        .count              (),
        .almostfull         (delayed_instruction_fifo_almostfull)
    );

assign time_stamp_diff  = {1'b0, time_stamp} - {1'b0, delayed_instruction_o[TUPLE_OFFSET_BITS+19:TUPLE_OFFSET_BITS]};

assign tuple_old_enough = (time_stamp_diff[20])? (time_stamp_diff <= INSTRUCTION_DELAY_NEGATIVE) : (time_stamp_diff >= INSTRUCTION_DELAY);

always @(posedge clk) begin
	if(~rst_n) begin
		instr_delay_cycles  <= 0;
		num_tuples_received <= 0;
		time_stamp          <= 0;
	end 
	else begin 
		//
		time_stamp <= time_stamp + 1'b1;
		//
		if(delayed_instruction_we) begin 
			num_tuples_received <= num_tuples_received + 1'b1;
		end
		//
		if(delayed_instruction_valid_f) begin
			if((instr_delay_cycles == INSTRUCTION_DELAY) & (curr_tree_index == num_trees_per_pu_minus_one) & ~TupleInstrctionFIFO_full) begin 
				instr_delay_cycles <= 0;
			end
			else if((instr_delay_cycles < INSTRUCTION_DELAY)) begin 
				instr_delay_cycles <= instr_delay_cycles + 1'b1;
			end
		end
	end
end

// issuing a copy of the instruction for each tree
always @(posedge clk) begin
	if(~rst_n) begin
		curr_tree_w_offset      <= 0;
		curr_tree_f_offset      <= 0;
		curr_tree_index         <= 0;
		tuple_old_enough_set    <= 0;
	end 
	else if((tuple_old_enough | tuple_old_enough_set) & delayed_instruction_valid_f) begin
		if(~TupleInstrctionFIFO_full) begin 
			if(curr_tree_index < num_trees_per_pu_minus_one) begin 
				curr_tree_w_offset      <= curr_tree_w_offset + num_lines_per_tree_weights;
				curr_tree_f_offset      <= curr_tree_f_offset + num_lines_per_tree_findex;
				curr_tree_index         <= curr_tree_index  + 1'b1;
				tuple_old_enough_set    <= 1'b1;
			end
			else begin 
				curr_tree_w_offset      <= 0;
				curr_tree_f_offset      <= 0;
				curr_tree_index         <= 0;
				tuple_old_enough_set    <= 1'b0;
			end
		end
	end
	else begin 
		curr_tree_w_offset      <= 0;
		curr_tree_f_offset      <= 0;
		curr_tree_index         <= 0;
		tuple_old_enough_set    <= 1'b0;
	end
end

assign last_tree = (curr_tree_index == num_trees_per_pu_minus_one);
assign instr_NOP = ~(curr_tree_index < local_num_trees);



quick_fifo  #(.FIFO_WIDTH(INSTRUCTION_WIDTH),        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(16)
      ) TupleInstrctionFIFO (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ( {last_tree, instr_NOP, delayed_instruction_o[TUPLE_OFFSET_BITS-1:0], curr_tree_f_offset, curr_tree_w_offset} ),
        .we                 (tuple_instruction_we),

        .re                 (tuple_instruction_re),
        .dout               (tuple_instruction),
        .empty              (),
        .valid              (tuple_instruction_valid_f),
        .full               (TupleInstrctionFIFO_full),
        .count              (),
        .almostfull         ()
    );


assign tuple_instruction_we = delayed_instruction_valid_f & (tuple_old_enough | tuple_old_enough_set);
assign tuple_instruction_re = ~tree_instruction_valid;
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               Read Node Stage               /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
   This stage execute a tree or tuple instruction: 
   this instruction issues a read request to Weights and Feature Indexes memories.
*/

assign tree_w_offset_s1    = (tree_instruction_valid)? tree_instruction_tree_w_offset  : tuple_instruction[TREE_OFFSET_BITS-1:0];      
assign tree_f_offset_s1    = (tree_instruction_valid)? tree_instruction_tree_f_offset  : tuple_instruction[2*TREE_OFFSET_BITS-1:TREE_OFFSET_BITS];                              // 10-bit tree address
assign tree_node_offset_s1 = (tree_instruction_valid)? tree_instruction_node_offset    : 0;                                                                          // 11 bit node offset
assign tree_w_node_addr_s1 = (tree_instruction_valid)? tree_instruction_node_w_addr    : {tuple_instruction[TREE_OFFSET_BITS-1:0], {(NODE_WORD_OFFSET_BITS){1'b0}}};   // 13 bit node addr
assign tree_f_node_addr_s1 = (tree_instruction_valid)? tree_instruction_node_f_addr    : {tuple_instruction[2*TREE_OFFSET_BITS-2:TREE_OFFSET_BITS], {(NODE_WORD_OFFSET_BITS+1){1'b0}}};   // 13 bit node addr

assign tuple_offset_s1     = (tree_instruction_valid)? tree_instruction_tuple_offset : tuple_instruction[TUPLE_OFFSET_BITS+2*TREE_OFFSET_BITS-1:2*TREE_OFFSET_BITS]; // 9 bits tuple offset
assign tree_instr_NOP_s1   = (tree_instruction_valid)? tree_instruction_type_NOP     : 1'b0;  
assign tree_instr_EMPTY_s1 = (tree_instruction_valid)? tree_instruction_type_EMPTY   : tuple_instruction[TUPLE_OFFSET_BITS + 2*TREE_OFFSET_BITS];                              										   // 1 bit NOP operation flag
assign tree_node_level_s1  = (tree_instruction_valid)? tree_instruction_node_level + 1'b1 : 0;                                                                     // 4 bits Tree Node level

assign last_tree_s1        = (tree_instruction_valid)? tree_instruction_last_flag : tuple_instruction[TUPLE_OFFSET_BITS + 2*TREE_OFFSET_BITS + 1];
  
assign tree_node_ren       = tree_instruction_valid | (tuple_instruction_valid_f);

assign next_tree_w_node_addr_s1   = {tree_w_offset_s1, {(NODE_WORD_OFFSET_BITS){1'b0}}} + {tree_node_offset_s1[MAX_NUM_TREE_NODES_BITS-2:0], 1'b1}; 
assign next_tree_f_node_addr_s1   = {tree_f_offset_s1[TREE_OFFSET_BITS-2:0], {(NODE_WORD_OFFSET_BITS+1){1'b0}}} + {tree_node_offset_s1[MAX_NUM_TREE_NODES_BITS-2:0], 1'b1}; 
assign next_tree_node_offset_s1   = (tree_instr_NOP_s1)? tree_node_offset_s1 : {tree_node_offset_s1[MAX_NUM_TREE_NODES_BITS-2:0], 1'b1};

// Send read requests to Weights and Feature Indexes memories
assign TWM_weight_wraddr = (~data_line_in_mode[0])?  {tree_prog_addr, {(NODE_WORD_OFFSET_BITS){1'b0}}} : tree_w_node_addr_s1;
assign TWM_rea           = tree_node_ren;

assign TFI_rd_addr       = tree_f_node_addr_s1;
assign TFI_ren           = tree_node_ren;

// Pipeline to next stage
delay #(.DATA_WIDTH(3*MAX_NUM_TREE_NODES_BITS+2*TREE_OFFSET_BITS+TUPLE_OFFSET_BITS+1+MAX_TREE_DEPTH_BITS + 1+1),
	    .DELAY_CYCLES(READ_TNODE_LATENCY) 
	) ReadNodeStageDelay(

	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          ( {tree_instr_EMPTY_s1, last_tree_s1, tree_node_level_s1, tree_instr_NOP_s1, /*tuple_UID_s1,*/ tuple_offset_s1, next_tree_f_node_addr_s1, next_tree_w_node_addr_s1, tree_f_offset_s1, tree_w_offset_s1, next_tree_node_offset_s1 } ),   // 
	    .data_in_valid    (tree_node_ren),
	    .data_out         ( {tree_instr_EMPTY_d1, last_tree_d1, tree_node_level_d1, tree_instr_NOP_d1, /*tuple_UID_d1,*/ tuple_offset_d1, next_tree_f_node_addr_d1, next_tree_w_node_addr_d1, tree_f_offset_d1, tree_w_offset_d1, next_tree_node_offset_d1 } ),
	    .data_out_valid   (tree_node_rd_stage_valid)
	);

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////             Read Feature Stage              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
    This stage reads the feature data corresponding to current tree node.
*/

assign features_ren     = tree_node_rd_stage_valid;
assign features_rd_addr = {TFI_rd_data[MAX_NUM_TUPLE_FEATURES_BITS-1:0]} + {tuple_offset_d1, {NODE_WORD_OFFSET_BITS{1'b0}} };

// Pipeline to next stage
delay #(.DATA_WIDTH(3*MAX_NUM_TREE_NODES_BITS+2*TREE_OFFSET_BITS+TUPLE_OFFSET_BITS+1+MAX_TREE_DEPTH_BITS + 1 + DATA_PRECISION+2+1+1),
	    .DELAY_CYCLES(READ_FEATURE_LATENCY) 
	) ReadFeatureStageDelay(

	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          ( {TFI_rd_data[NODE_FEATURE_INDEX_WIDTH-1:NODE_FEATURE_INDEX_WIDTH-3], TWM_weight_data, tree_instr_EMPTY_d1, last_tree_d1, tree_node_level_d1, tree_instr_NOP_d1, tuple_offset_d1, next_tree_f_node_addr_d1, next_tree_w_node_addr_d1, tree_f_offset_d1, tree_w_offset_d1, next_tree_node_offset_d1 } ),   // 
	    .data_in_valid    (features_ren),
	    .data_out         ( {feature_index_data_d2, weight_data_d2, tree_instr_EMPTY_d2, last_tree_d2, tree_node_level_d2, tree_instr_NOP_d2, tuple_offset_d2, next_tree_f_node_addr_d2, next_tree_w_node_addr_d2, tree_f_offset_d2, tree_w_offset_d2, next_tree_node_offset_d2 } ),
	    .data_out_valid   (feature_rd_stage_valid)
	);

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////              Comparison Stage               /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
    In this stage we compare feature and weight values, take a decision to output the tree result
    or continue to next stage
*/

assign isFeatureMissing    = features_rd_data == MissingFeatureValue;

assign isFeatureSmaller    = {~features_rd_data[DATA_PRECISION-1], features_rd_data} < {~weight_data_d2[DATA_PRECISION-1], weight_data_d2};

assign isRightChild        = ~isFeatureSmaller;

assign isMissingRight      = feature_index_data_d2[0];

assign isNextNodeLeaf      = feature_index_data_d2[1];

assign isLastLevel         = tree_node_level_d2 == LastLevelIndex;

assign goToOutput          = isLastLevel;

assign incrementNodeOffset = (isFeatureMissing)? isMissingRight : isRightChild;
// Pipeline to next stage
delay #(.DATA_WIDTH(3*MAX_NUM_TREE_NODES_BITS+2*TREE_OFFSET_BITS+TUPLE_OFFSET_BITS+1+MAX_TREE_DEPTH_BITS+1+1+1+1),
	    .DELAY_CYCLES(1) 
	) ComparisonStageDelay(

	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          ( {goToOutput, incrementNodeOffset, tree_instr_EMPTY_d2, last_tree_d2, tree_node_level_d2, (tree_instr_NOP_d2 | isNextNodeLeaf), tuple_offset_d2, next_tree_f_node_addr_d2, next_tree_w_node_addr_d2, tree_f_offset_d2, tree_w_offset_d2, next_tree_node_offset_d2 } ),   // 
	    .data_in_valid    (feature_rd_stage_valid),
	    .data_out         ( {goToOutput_d3, incrementNodeOffset_d3, tree_instr_EMPTY_d3, last_tree_d3, tree_node_level_d3, tree_instr_NOP_d3, tuple_offset_d3, next_tree_f_node_addr_d3, next_tree_w_node_addr_d3, tree_f_offset_d3, tree_w_offset_d3, next_tree_node_offset_d3 } ),
	    .data_out_valid   (comparison_stage_valid)
	);

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////           Prepare to Next Stage             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
    Set next stage instruction, correct next node offset and addr using comparison stage results
*/

always @(posedge clk) begin
	if(~rst_n) begin
		tree_instruction_valid    <= 0;
		tree_output_valid         <= 0;
	end 
	else begin
		if( comparison_stage_valid ) begin
			tree_instruction_valid <= ~goToOutput_d3;
			tree_output_valid      <= goToOutput_d3;
		end
		else begin 
			tree_instruction_valid    <= 0;
			tree_output_valid         <= 0;
		end
	end 
end

always @(posedge clk) begin
	if( comparison_stage_valid ) begin
		tree_instruction_tuple_offset    <= tuple_offset_d3;
		tree_instruction_node_w_addr     <= next_tree_w_node_addr_d3 + incrementNodeOffset_d3;
		tree_instruction_node_f_addr     <= next_tree_f_node_addr_d3 + incrementNodeOffset_d3;
		tree_instruction_node_offset     <= (tree_instr_NOP_d3)? next_tree_node_offset_d3 : next_tree_node_offset_d3 + incrementNodeOffset_d3;
		tree_instruction_tree_w_offset   <= tree_w_offset_d3;
		tree_instruction_tree_f_offset   <= tree_f_offset_d3;
		tree_instruction_type_NOP        <= tree_instr_NOP_d3;
		tree_instruction_type_EMPTY      <= tree_instr_EMPTY_d3;
		tree_instruction_node_level      <= tree_node_level_d3;
		tree_instruction_last_flag       <= last_tree_d3;
	end
end

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////                 PU Output                   /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
    prepare output of the current PU
*/

assign TWM_res_raddr = tree_instruction_node_w_addr;
assign TWM_reb       = tree_output_valid & ~PartialTrees;

//----------------------------------------- PU Output signals ------------------------------------//
// Tree node index
always @(posedge clk) begin
	if(~rst_n) begin
		pu_tree_node_index_out       <= 0;
		pu_tree_node_index_out_valid <= 0;
	end 
	else begin
		pu_tree_node_index_out       <= next_tree_node_offset_d3;
		pu_tree_node_index_out_valid <= goToOutput_d3 & PartialTrees;
	end
end

delay #(.DATA_WIDTH(1+1),
	    .DELAY_CYCLES(READ_TNODE_LATENCY+1) 
	) PULeafOutputDelay(

	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          ( {tree_instr_EMPTY_d3, last_tree_d3} ),   // 
	    .data_in_valid    (TWM_reb),
	    .data_out         ( {pu_tree_leaf_zero, pu_tree_leaf_out_last} ),
	    .data_out_valid   ()
	);

// Leaf value
assign pu_tree_leaf_out       = (pu_tree_leaf_zero | ~TWM_res_valid)? 0 : TWM_res_data;
assign pu_tree_leaf_out_valid = TWM_res_valid;


//-----------------------------------------------------------------------------------------------//
always @(posedge clk) begin
	
	data_line_out           <= data_line_in;
	data_line_out_last      <= data_line_in_last;
	data_line_out_pu        <= data_line_in_pu;

	if(~rst_n) begin
		data_line_out_valid <= 0;
		data_line_out_prog  <= 0;
		data_line_out_ctrl  <= 0;
	end
	else begin
		data_line_out_valid <= data_line_in_valid;
		data_line_out_prog  <= data_line_in_mode;
		data_line_out_ctrl  <= data_line_in_ctrl;

	end
end



endmodule // DTPU


