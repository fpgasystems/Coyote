
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

/*
	PE Datapath flow:

	- Read Tree Node: This stage consumes either the input tree instruction or the next node instruction.
	                  This stage issues a read address to tree memory and delays all the necessary information 
	                  for the tree memory delay. By the end of the stage, the tree node basic and extra part are 
	                  available in addition to the delayed information.

	- Read feature:   Use the feature index in the tree node to compute the feature address and read it from 
	                  the data memory. Then, we delay the current node instruction and obtained tree node info.

	- Read Split Set: In this stage, we compute the address for large bitset word to read from
	                  tree memory, If there is no large split bitset then the tree memory output is ignored.
	                  In addition, the early tree evaluation occurs. In parallel, we use the feature value to select 
	                  from the small bitset, we use it also to compare to the split value, and we use the feature value
	                  to check if it is outside the boundaries of the large bitset. In addition, If node_nop flag is zero,
	                  then the node_res_val is not used, hence we store W2 of the tree node in its place to save resources.
	                  In addition, we check if the feature value is NaN or not. 
	- Evaluate Node:  At this stage we have all the necessary information to process a node. 
	                  Then based on the operation type the evaluation happens. 
	  Pick A branch:  In this stage, based on the node evaluation result then we compute next node 
	                  to evaluate, or pick result if no children on the next branch and set NOP if we 
	                  are not at the last level. In this branch, also if we at the last level, then we 
	                  output the result if the tree is not empty.
*/

import DTPackage::*;

module pe_datapath (
	
	input   wire  								clk,
	input   wire 							    rst_n,

	input   wire  [MAX_TREE_DEPTH_BITS-1:0]     tree_depth, 

	// tree instruction
	input TreeInstruction_t                     tree_instruction, 
	input  wire  								tree_instruction_valid, 
	output wire 								tree_instruction_ready, 

	// data memory read port
	output wire   [TUPLE_OFFSET_BITS:0]         data_mem_rd_addr, 
	output wire                                 data_mem_ren,
	input  wire   [31:0]   						data_mem_feature, 

	// tree memory read port A
	output wire   [TREE_OFFSET_BITS:0]          tree_mem_rd_addr_a, 
	output wire                                 tree_mem_ren_a,
	input  TreeNode_t                           tree_node_basic,  

	// tree memory read port B
	output wire   [TREE_OFFSET_BITS:0]          tree_mem_rd_addr_b, 
	output wire                                 tree_mem_ren_b,
	input  wire   [31:0]                        node_large_bitset, 

	// result output
	output wire   [31:0] 						tree_eval_result, 
	output wire                                 tree_eval_last, 
	output wire 								tree_eval_result_valid
);




NodeInstruction_t         					next_node_instr;
wire 										next_node_instr_valid;

NodeInstruction_t         					curr_node_instr_s1;
wire 										curr_node_instr_valid_s1;
NodeInstruction_t         					curr_node_instr_s2;
wire 										curr_node_instr_valid_s2;
NodeInstruction_t         					curr_node_instr_s3;
NodeInstruction_t         					curr_node_instr_s3_1;
wire 										curr_node_instr_valid_s3;
NodeInstruction_t         					curr_node_instr_s4;
NodeInstruction_t         					curr_node_instr_s4_1;
wire 										curr_node_instr_valid_s4;
NodeInstruction_t         					curr_node_instr_s5;
NodeInstruction_t 							curr_node_instr_s5_1;
wire 										curr_node_instr_valid_s5;

wire   [31:0] 								small_bitset;
wire 										is_Feature_NaN;
wire 										small_bitset_eval;
wire 										split_value_eval;
wire 										feature_data_outside_bitset;

wire 										is_Feature_NaN_s4;
wire 										small_bitset_eval_s4;
wire 										split_value_eval_s4;
wire 										feature_data_outside_bitset_s4;
wire   [4:0]     							feature_data_s4;

wire 										is_Feature_NaN_s5;

TreeNode_t 									tree_node_basic_s3;
TreeNode_t 									tree_node_basic_s4;
TreeNode_t 									tree_node_basic_s5;

reg 										go_right;
reg 										node_eval;

wire    [10:0] 								left_child_offset_1;
wire    [10:0] 								left_child_offset_2;

wire    [10:0] 								right_child_offset;

wire    [10:0] 								next_node_address;
wire    [MAX_TREE_DEPTH_BITS-1:0]           next_node_level;

wire 										next_node_nop;
wire    [10:0] 								next_child_offset;
wire    [10:0]								result_offset;
wire 										next_node_leaf;

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               Read Node Stage               /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
*/
always @(*) begin 
	if(next_node_instr_valid) begin
		curr_node_instr_s1 = next_node_instr;
	end
	else begin 
		curr_node_instr_s1 = '{node_address: {tree_instruction.tree_offset, 1'b0}, 
						       tuple_offset: tree_instruction.tuple_offset, 
						       node_level  : 3'b000, 
						       empty_tree  : tree_instruction.empty_tree, 
						       node_nop    : 1'b0, 
						       last_tree   : tree_instruction.last_tree, 
						       leaf_node   : 1'b0,
						       node_res_val: 32'b0   
						      };
	end
end

assign curr_node_instr_valid_s1 = next_node_instr_valid | tree_instruction_valid;

assign tree_instruction_ready   = !next_node_instr_valid;

// Send read requests to tree memory
assign tree_mem_rd_addr_a = curr_node_instr_s1.node_address;
assign tree_mem_ren_a     = curr_node_instr_valid_s1;

// Pipeline to next stage
delay #(.DATA_WIDTH( $bits(NodeInstruction_t)),
	    .DELAY_CYCLES(TREE_MEM_READ_LATENCY) 
	) ReadNodeStageDelay(
	    .clk              ( clk ),
	    .rst_n            ( rst_n ),
	    .data_in          ( curr_node_instr_s1 ),   // 
	    .data_in_valid    ( curr_node_instr_valid_s1 ),
	    .data_out         ( curr_node_instr_s2 ),
	    .data_out_valid   ( curr_node_instr_valid_s2 )
	);

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////             Read Feature Stage              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
    This stage reads the feature data corresponding to current tree node.
*/
assign data_mem_ren     = curr_node_instr_valid_s2 && (tree_node_basic.node_type.findex != 8'hFF);
assign data_mem_rd_addr = {curr_node_instr_s2.tuple_offset, 1'b0} + tree_node_basic.node_type.findex;    // 10-bit address

// Pipeline to next stage
delay #(.DATA_WIDTH($bits(NodeInstruction_t) + $bits(TreeNode_t)),
	    .DELAY_CYCLES(DATA_MEM_READ_LATENCY) 
	) ReadFeatureStageDelay(
	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          ( {curr_node_instr_s2, tree_node_basic} ),   // 
	    .data_in_valid    ( curr_node_instr_valid_s2 ),
	    .data_out         ( {curr_node_instr_s3, tree_node_basic_s3} ),
	    .data_out_valid   ( curr_node_instr_valid_s3 )
	);
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////         Read Split Set/Value Stage          /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
assign tree_mem_rd_addr_b = curr_node_instr_s3.node_address                           + 
							((curr_node_instr_s3.leaf_node)? 0 :
							 (((!tree_node_basic_s3.node_type.left_child)? 1'b1 : 0)  + 
							 ((!tree_node_basic_s3.node_type.right_child)? 1'b1 : 0) + 
							   data_mem_feature[15:5] + 11'b00000010));
assign tree_mem_ren_b     = curr_node_instr_valid_s3;

// Early Node evaluation
assign curr_node_instr_s3_1 = '{ node_address: curr_node_instr_s3.node_address, 
								 tuple_offset: curr_node_instr_s3.tuple_offset, 
						       	 node_level  : curr_node_instr_s3.node_level, 
						         empty_tree  : curr_node_instr_s3.empty_tree, 
						         node_nop    : ((curr_node_instr_s3.node_nop)? 1'b1 : !curr_node_instr_s3.leaf_node && (tree_node_basic_s3.node_type.findex == 8'hFF) ), 
						         last_tree   : curr_node_instr_s3.last_tree, 
						         leaf_node   : curr_node_instr_s3.leaf_node, 
						         node_res_val: ( (curr_node_instr_s3.node_nop)? curr_node_instr_s3.node_res_val : {tree_node_basic_s3.word_1_h, tree_node_basic_s3.word_1_l}) 
						      };

assign small_bitset       = {tree_node_basic_s3.word_1_h, tree_node_basic_s3.word_1_l};

assign is_Feature_NaN     = (data_mem_feature[30:23] == 7'b1111111) && (|data_mem_feature[22:0]);
assign small_bitset_eval  = (data_mem_feature[31:5] == 0)? small_bitset[ data_mem_feature[4:0] ] : 1'b0;
assign split_value_eval   = data_mem_feature < {tree_node_basic_s3.word_1_h, tree_node_basic_s3.word_1_l};

assign feature_data_outside_bitset = (data_mem_feature < tree_node_basic_s3.word_1_h) || 
                                     (data_mem_feature > (tree_node_basic_s3.word_1_h + (tree_node_basic_s3.word_1_l << 5) ) );

// Pipeline to next stage
delay #(.DATA_WIDTH($bits(NodeInstruction_t) + $bits(TreeNode_t) + 5 + 1 + 1 + 1 + 1),
	    .DELAY_CYCLES(TREE_MEM_READ_LATENCY) 
	) ReadSplitSetStageDelay(
	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          ( {curr_node_instr_s3_1, tree_node_basic_s3, data_mem_feature[4:0], small_bitset_eval, split_value_eval, feature_data_outside_bitset, is_Feature_NaN} ),   // 
	    .data_in_valid    ( curr_node_instr_valid_s3 ),
	    .data_out         ( {curr_node_instr_s4, tree_node_basic_s4, feature_data_s4, small_bitset_eval_s4, split_value_eval_s4, feature_data_outside_bitset_s4, is_Feature_NaN_s4} ),
	    .data_out_valid   ( curr_node_instr_valid_s4 )
     );

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////          Node Evaluation Stage              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
*/

always@(posedge clk)begin 
	if(~rst_n) begin
		node_eval <= 1'b0;
	end
	else begin 
		case (tree_node_basic_s4.node_type.op_type) 
			2'b00:    node_eval <= split_value_eval_s4;
			2'b10:    node_eval <= small_bitset_eval_s4;
			2'b11:    node_eval <= (feature_data_outside_bitset_s4)? 1'b0 : node_large_bitset[ feature_data_s4 ];
			default : node_eval <= 1'b0;
		endcase
	end
end

// Early Node evaluation
assign curr_node_instr_s4_1 = '{ node_address: curr_node_instr_s4.node_address, 
								 tuple_offset: curr_node_instr_s4.tuple_offset, 
						       	 node_level  : curr_node_instr_s4.node_level, 
						         empty_tree  : curr_node_instr_s4.empty_tree, 
						         node_nop    : curr_node_instr_s4.node_nop, 
						         last_tree   : curr_node_instr_s4.last_tree, 
						         leaf_node   : curr_node_instr_s4.leaf_node, 
						         node_res_val: ( (curr_node_instr_s4.node_nop || !curr_node_instr_s4.leaf_node)? curr_node_instr_s4.node_res_val : node_large_bitset ) 
						      };

// Pipeline to next stage
delay #(.DATA_WIDTH($bits(NodeInstruction_t) + $bits(TreeNode_t) + 1),
	    .DELAY_CYCLES(1) 
	) EvalNodeStageDelay(
	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          ( {curr_node_instr_s4_1, tree_node_basic_s4, is_Feature_NaN_s4} ),   // 
	    .data_in_valid    ( curr_node_instr_valid_s4 ),
	    .data_out         ( {curr_node_instr_s5, tree_node_basic_s5, is_Feature_NaN_s5} ),
	    .data_out_valid   ( curr_node_instr_valid_s5 )
     );

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////             Pick Branch Stage               /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
*/

always@(*)begin 
	if(tree_node_basic_s5.node_type.split_dir == 4'b0001) begin
		go_right = is_Feature_NaN_s5; 
	end
	else if(tree_node_basic_s5.node_type.split_dir[0] == 1'b0) begin
		if(is_Feature_NaN_s5) begin
			go_right = 1'b0;
		end
		else begin 
			go_right = node_eval;
		end
	end
	else begin 
		if(is_Feature_NaN_s5) begin
			go_right = 1'b1;
		end
		else begin 
			go_right = node_eval;
		end
	end
end

// compute left child offset, 
assign left_child_offset_1 = 11'b00000000010 + ((tree_node_basic_s5.node_type.left_child)?  0 : 1'b1) + ((tree_node_basic_s5.node_type.right_child)? 0 : 1'b1);
assign left_child_offset_2 = left_child_offset_1 + ( (tree_node_basic_s5.node_type.op_type != 3)? 11'd0 : tree_node_basic_s5.word_1_l[10:0]);
// compute right child offset
assign right_child_offset  = left_child_offset_2 + tree_node_basic_s5.right_child_offset[10:0];
assign next_child_offset   = (go_right && tree_node_basic_s5.node_type.left_child)? right_child_offset : left_child_offset_2;

// compute leaf node result offset
assign result_offset   = (go_right)? 11'b00000000010 + ((tree_node_basic_s5.node_type.left_child)?  0 : 1'b1) : 11'b00000000010;
assign next_node_leaf  = (go_right)? !tree_node_basic_s5.node_type.right_child : !tree_node_basic_s5.node_type.left_child;

// Next level node address
assign next_node_address = curr_node_instr_s5.node_address + ( (next_node_leaf)? result_offset : next_child_offset);

assign next_node_level   = (curr_node_instr_s5.node_level == (tree_depth))? (tree_depth) : curr_node_instr_s5.node_level + 1'b1;
assign next_node_nop     = curr_node_instr_s5.node_nop || ((curr_node_instr_s5.node_level < (tree_depth) && curr_node_instr_s5.leaf_node)? 1'b1 : 1'b0);

assign curr_node_instr_s5_1 = '{ node_address: next_node_address, 
								 	   tuple_offset: curr_node_instr_s5.tuple_offset, 
						       	 	   node_level  : next_node_level, 
						               empty_tree  : curr_node_instr_s5.empty_tree, 
						               node_nop    : next_node_nop, 
						               last_tree   : curr_node_instr_s5.last_tree, 
						               leaf_node   : ( curr_node_instr_s5.leaf_node || next_node_leaf),
						               node_res_val: curr_node_instr_s5.node_res_val 
						            };
// Pipeline to next stage
delay #(.DATA_WIDTH( $bits(NodeInstruction_t) ),
	    .DELAY_CYCLES(1) 
	) PickBranchStageDelay(
	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          ( curr_node_instr_s5_1 ),   // 
	    .data_in_valid    ( curr_node_instr_valid_s5 && (curr_node_instr_s5.node_level < (tree_depth)) ),
	    .data_out         ( next_node_instr ),
	    .data_out_valid   ( next_node_instr_valid )
     );


assign tree_eval_result       = (curr_node_instr_s5.empty_tree)? 32'b0 : curr_node_instr_s5.node_res_val;
assign tree_eval_result_valid = curr_node_instr_valid_s5 && (curr_node_instr_s5.node_level == (tree_depth) );
assign tree_eval_last         = curr_node_instr_s5.last_tree;



endmodule