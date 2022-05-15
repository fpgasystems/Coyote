
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

 

package DTPackage;

parameter   TREE_OFFSET_BITS             = 10;
parameter   TUPLE_OFFSET_BITS            = 9;
parameter   TREE_MEM_WIDTH_BITS          = 1;
parameter   MAX_TREE_DEPTH_BITS          = 4;

parameter   NUM_PUS_PER_CLUSTER_BITS     = 5;
parameter   NUM_PUS_PER_CLUSTER          = 28;
parameter   NUM_DTPU_CLUSTERS 		     = 4;
parameter   NUM_DTPU_CLUSTERS_BITS       = 2;
parameter   NUM_TREES_PER_PU             = 32;
parameter   FEATURES_DISTR_DELAY         = 8;
parameter   DATA_PRECISION               = 32;
parameter   DATA_LINE_WIDTH              = 64;


parameter   TREE_MEM_READ_LATENCY        = 2;
parameter   DATA_MEM_READ_LATENCY        = 2;

parameter   EMPTY_PIPELINE_WAIT_CYCLES   = 128;

parameter   FP_ADDER_LATENCY             = 2;



typedef struct packed {
	bit [TREE_OFFSET_BITS-1:0]     tree_offset;
	bit [TUPLE_OFFSET_BITS-1:0]    tuple_offset;
	bit 						   last_tree;
	bit                            empty_tree;
} TreeInstruction_t;

typedef struct packed {
    bit [TREE_OFFSET_BITS+TREE_MEM_WIDTH_BITS-1:0] node_address;
    bit [TUPLE_OFFSET_BITS-1:0]                    tuple_offset; 
    bit [MAX_TREE_DEPTH_BITS-1:0]                  node_level;
    bit                                            empty_tree;
    bit                                            node_nop;
    bit                                            last_tree;
    bit                                            leaf_node;

    bit [31:0]                                     node_res_val;
} NodeInstruction_t;



typedef struct packed {
	bit  [3:0]    split_dir;
	bit  [7:0]    findex;
	bit           right_child;
	bit           left_child;
	bit  [1:0]    op_type;
} NodeType_t;

typedef struct packed {
	bit       [15:0]   word_1_h;
	bit       [15:0]   word_1_l;
	bit       [15:0]   right_child_offset;
	NodeType_t         node_type;
} TreeNode_t;



endpackage 

