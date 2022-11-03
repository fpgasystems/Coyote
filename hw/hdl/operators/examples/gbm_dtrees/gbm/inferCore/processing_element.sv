
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

/*
    
*/
module processing_element #(parameter PE_ID = 0 )
		(
		input   wire  								  clk,
		input   wire 							      rst_n,

		input   wire  [DATA_LINE_WIDTH-1:0]           data_line_in,
		input   wire  								  data_line_in_valid,
		input   wire  								  data_line_in_last,
		input   wire  								  data_line_in_ctrl,
		input   wire            					  data_line_in_prog,
		input   wire  [NUM_PUS_PER_CLUSTER_BITS-1:0]  data_line_in_pu,
		output  reg 								  data_line_in_ready,

		output  reg   [DATA_LINE_WIDTH-1:0]           data_line_out,
		output  reg   								  data_line_out_valid,
		output  reg                                   data_line_out_ctrl,
        output  reg   								  data_line_out_last,
		output  reg     	    					  data_line_out_prog,
		output  reg   [NUM_PUS_PER_CLUSTER_BITS-1:0]  data_line_out_pu,

		output  reg   [DATA_PRECISION-1:0]            pu_tree_leaf_out,
		output  reg                                   pu_tree_leaf_out_valid,
		output  reg                                   pu_tree_leaf_out_last
	);

localparam  INSTRUCTION_DELAY           = NUM_PUS_PER_CLUSTER - PE_ID - 1;       // PU pipeline depth-1 - PU_ID
localparam  TREE_MODE = 1'b0;
localparam  DATA_MODE = 1'b1;
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Signals Declarations             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////


TreeInstruction_t 					dp_tree_instruction;
wire 								dp_tree_instruction_valid;
wire 								dp_tree_instruction_ready;

wire 								dp_data_mem_ren;
wire 	[31:0] 						dp_data_mem_feature;
wire 	[TUPLE_OFFSET_BITS:0]		dp_data_mem_rd_addr;

// tree memory read port A
wire    [TREE_OFFSET_BITS:0]        dp_tree_mem_rd_addr_a;
wire                                dp_tree_mem_ren_a;
TreeNode_t                          dp_tree_node_basic;  
wire    [63:0]                      dp_tree_node_basic_vec;

// tree memory read port B
wire    [TREE_OFFSET_BITS:0]        dp_tree_mem_rd_addr_b; 
wire                                dp_tree_mem_ren_b;
wire    [31:0]                      dp_node_large_bitset; 

// result output
wire    [31:0] 						dp_tree_eval_result; 
wire                                dp_tree_eval_last;
wire 								dp_tree_eval_result_valid;


reg     [1:0]       				curr_tree_id;
reg     [8:0]       				curr_tuple_offset;
reg     [9:0]       				time_stamp;
reg 								tuple_old_enough_set;

wire  								tuple_instr_fifo_ready;
wire 								tuple_instr_fifo_valid;
wire    [9:0]						tuple_instr_fifo_dout;
wire 								tuple_instr_re;
wire 								tuple_old_enough;


wire 								curr_feature_done;
reg    	[9:0] 						features_mem_count;
reg    	[8:0] 						features_wr_addr;

reg     [2:0]         				local_num_trees;
reg     [2:0]						local_num_trees_minus_one;
reg     [TREE_OFFSET_BITS-1:0]      received_tree_lines;
reg     [TREE_OFFSET_BITS-1:0]      tree_prog_addr;
reg     [TREE_OFFSET_BITS-1:0]      tree_offsets[3:0];
wire    [TREE_OFFSET_BITS  :0]      tree_mem_addr_a;

reg     [4:0]						num_trees_per_pu_minus_one;
reg     [3:0] 						tree_depth;
reg     [8:0] 						num_lines_per_tuple;

reg     [7:0] 					 	tree_addra[5:0];
reg     [7:0] 					 	tree_addrb[5:0];

reg     [2:0]                       rd_a_count;
reg     [2:0]                       rd_b_count;

reg 					first_word_correct;
reg     [63:0]				first_word;
reg   					pe_state;

reg  	[63:0]     					tree_mem_out_a;
reg  	[31:0]     					data_mem_out_a;
reg 								tree_out_a_set;
reg 								data_out_a_set;
wire 								dp_tree_valid_out1;
wire 								dp_data_mem_feature_valid; 
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////           PU Programming Logic              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

always @(posedge clk) begin
	if(~rst_n) begin
		data_line_out_valid <= 0;  
		data_line_out_last  <= 0;
		data_line_out_ctrl  <= 0;
		data_line_out_prog  <= 0;

 		pe_state   <= TREE_MODE;
	end 
	else begin
		data_line_out_valid <= data_line_in_valid;  
		data_line_out_last  <= data_line_in_last;
		data_line_out_ctrl  <= data_line_in_ctrl;
		data_line_out_prog  <= data_line_in_prog;

   		if(data_line_in_valid | (pe_state == DATA_MODE) ) begin 
			pe_state <= DATA_MODE;
		end 
	end
	//
	data_line_out    <= data_line_in;
	data_line_out_pu <= data_line_in_pu;
end

always @(posedge clk) begin
	if(~rst_n) begin
		num_trees_per_pu_minus_one <= 5'b0;  
		tree_depth	    	       <= 4'b0;
		num_lines_per_tuple        <= 9'b0;
	end 
	else if(data_line_in_ctrl) begin
		num_trees_per_pu_minus_one <= data_line_in[4:0];       
		tree_depth			       <= data_line_in[8+4-1:8];      
		num_lines_per_tuple        <= data_line_in[16+9-1:16];  
	end
end

//assign pu_debug_counters = {local_num_trees, received_tree_lines[8:0], tree_offsets[3][8:0], tree_offsets[2][8:0], tree_offsets[1][8:0], tree_offsets[0][8:0]};
assign pu_debug_counters  = {tree_addrb[5], tree_addrb[4], tree_addrb[3], tree_addrb[2], tree_addrb[1], tree_addrb[0], tree_addra[5], tree_addra[4], tree_addra[3], tree_addra[2], tree_addra[1], tree_addra[0]};
assign pu_debug_counters2 = {tree_mem_out_a[31:0], first_word};
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////                Memory Banks                 /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

genvar j;
generate for ( j = 0; j < 6; j=j+1) begin
	always@(posedge clk) begin 
		if(~rst_n) begin
			tree_addra[j] <= 0;
			tree_addrb[j] <= 0;
		end
		else begin 
			if(dp_tree_mem_ren_a && (rd_a_count == j)) begin
				tree_addra[j] <= tree_mem_addr_a[7:0];
			end

			if(dp_tree_mem_ren_b && (rd_b_count == j)) begin
				tree_addrb[j] <= dp_tree_mem_rd_addr_b[7:0];
			end 
		end
	end
end			
endgenerate

integer i;
always@(posedge clk) begin 
	if(~rst_n) begin
		rd_a_count <= 0;
		rd_b_count <= 0;

		tree_mem_out_a <= 0;
		data_mem_out_a <= 0;
		tree_out_a_set <= 1'b0;
		data_out_a_set <= 1'b0;
		first_word_correct <= 0;
                first_word <= 0;
	end
	else begin 
		if(dp_tree_mem_ren_a && rd_a_count < 6) begin
			rd_a_count <= rd_a_count + 1'b1;
		end

		if(dp_tree_mem_ren_b && rd_b_count < 6) begin
			rd_b_count <= rd_b_count + 1'b1;
		end
		//
		if(dp_tree_valid_out1 && ~tree_out_a_set) begin
			tree_mem_out_a <= dp_tree_node_basic_vec;
			tree_out_a_set <= 1'b1;
		end

		if(dp_data_mem_feature_valid && ~data_out_a_set) begin
			data_mem_out_a <= dp_data_mem_feature;
			data_out_a_set <= 1'b1;
		end

		//
		if((tree_prog_addr == 0) && (data_line_in_prog && (data_line_in_pu == PE_ID) )) begin
                    first_word_correct <= data_line_in[15:0] == 16'h200c;
                    first_word <= data_line_in;
                end
	end
end


//----------------------------- Tree Nodes Weight memory ------------------------------//
Tree_Memory #( .DATA_WIDTH(64),
               .ADDR_WIDTH(11) )  
TreeNodes(

    .clk         ( clk ),
    .rst_n       ( rst_n ),
    .we          ( data_line_in_prog && (data_line_in_pu == PE_ID) ),
    .rea         ( dp_tree_mem_ren_a ),
    .reb         ( dp_tree_mem_ren_b ),
    .addr_port_a ( tree_mem_addr_a ),
    .addr_port_b ( dp_tree_mem_rd_addr_b ),  
    .din         ( data_line_in ),
    .dout1       ( dp_tree_node_basic_vec ),
    .valid_out1  ( dp_tree_valid_out1),
    .dout2       ( dp_node_large_bitset ),
    .valid_out2  ()
);
assign dp_tree_node_basic.word_1_h           = dp_tree_node_basic_vec[63:48];
assign dp_tree_node_basic.word_1_l           = dp_tree_node_basic_vec[47:32];
assign dp_tree_node_basic.right_child_offset = dp_tree_node_basic_vec[31:16];
assign dp_tree_node_basic.node_type.op_type  = dp_tree_node_basic_vec[1:0];
assign dp_tree_node_basic.node_type.left_child   = dp_tree_node_basic_vec[2];
assign dp_tree_node_basic.node_type.right_child  = dp_tree_node_basic_vec[3];
assign dp_tree_node_basic.node_type.findex       = dp_tree_node_basic_vec[11:4];
assign dp_tree_node_basic.node_type.split_dir    = dp_tree_node_basic_vec[15:12];


assign tree_mem_addr_a = ( pe_state == TREE_MODE )? {tree_prog_addr, 1'b0} : dp_tree_mem_rd_addr_a;

always @(posedge clk) begin
	//
	if(~rst_n) begin
		tree_prog_addr      <= 0;
		local_num_trees     <= 0;
		received_tree_lines <= 0;

		local_num_trees_minus_one <= 0;

		for (i = 0; i < 4; i++) begin
			tree_offsets[ i ] <= 0;
		end
	end 
	else begin  
		local_num_trees_minus_one <= local_num_trees;
		//
		if(data_line_in_prog && (data_line_in_pu == PE_ID)) begin
			tree_prog_addr      <= tree_prog_addr + 1'b1;
			received_tree_lines <= received_tree_lines + 1'b1;

			if(data_line_in_last && (local_num_trees[1:0] < num_trees_per_pu_minus_one[1:0])) begin 
				tree_offsets[ local_num_trees[1:0] + 1'b1 ] <= received_tree_lines + 1'b1;
				local_num_trees                             <= local_num_trees + 1'b1;
			end
		end	
	end 
end
//--------------------------- Input tuple features memory -----------------------------//
/* We write to the features memory when flags indicate incoming data is tuples and not programming data
*/
Data_Memory #( .DATA_WIDTH(64),
               .ADDR_WIDTH(10) )
SamplesFeatures_Mem(
    .clk        (clk),
    .rst_n      (rst_n),
    .we         (data_line_in_valid),
    .re         (dp_data_mem_ren),
    .raddr      (dp_data_mem_rd_addr),
    .waddr      (features_wr_addr),  
    .din        (data_line_in),
    .dout       (dp_data_mem_feature),
    .valid_out  (dp_data_mem_feature_valid)
);

always @(posedge clk) begin
	if(~rst_n) begin
		features_wr_addr   <= 9'b0;
		features_mem_count <= 0;
	end 
	else begin 
		features_wr_addr   <= features_wr_addr + ((data_line_in_valid)? 9'd1 : 9'd0);
		features_mem_count <= features_mem_count + ((data_line_in_valid)? 9'd1 : 9'd0) - ((curr_feature_done)? num_lines_per_tuple : 9'b0);
	end
end

assign curr_feature_done  = dp_tree_eval_result_valid & dp_tree_eval_last;

assign data_line_in_ready = tuple_instr_fifo_ready & (features_mem_count < (512- PE_ID - 1));
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////           Tuple Instruction FIFO            /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/* Once all features of a tuple are in features memory, we enqueue an instruction to execute all the
   trees in the PU on the current tuple features, the instruction simply include the tuple offset.
*/
RegBasedFIFO  #(.FIFO_WIDTH(10),        
                .FIFO_DEPTH_BITS(2)
      ) tuple_instr_fifo (
        .clk                (clk),
        .rst_n              (rst_n),
        .data_in            ( time_stamp ),
        .data_in_valid      ( data_line_in_valid && data_line_in_last ),
        .data_out_ready     (tuple_instr_re),
        .data_out           (tuple_instr_fifo_dout),
        .data_out_valid     (tuple_instr_fifo_valid),
        .data_in_ready      (tuple_instr_fifo_ready)
    );

assign tuple_instr_re            = dp_tree_instruction_ready && (tuple_old_enough || tuple_old_enough_set) && (curr_tree_id == num_trees_per_pu_minus_one);

assign tuple_old_enough          = tuple_instr_fifo_valid && ((time_stamp <= tuple_instr_fifo_dout) || ((time_stamp - tuple_instr_fifo_dout) > INSTRUCTION_DELAY));

assign dp_tree_instruction_valid = tuple_instr_fifo_valid && (tuple_old_enough || tuple_old_enough_set);

assign dp_tree_instruction       = '{tree_offset:  tree_offsets[curr_tree_id], 
                                     tuple_offset: curr_tuple_offset,
                                     last_tree:    (curr_tree_id == num_trees_per_pu_minus_one),
                                     empty_tree:   (curr_tree_id > local_num_trees)};

// Flags, counters used in issuing tree instructions to the datapath and synchronizing logic with other PEs.
always @(posedge clk) begin
	if(~rst_n) begin
		time_stamp           <= 0;
		tuple_old_enough_set <= 0;
		curr_tuple_offset    <= 0; 
		curr_tree_id         <= 0;
	end 
	else begin 
		// tuple_old_enough_set
		tuple_old_enough_set <= (tuple_instr_re && tuple_instr_fifo_valid)? 1'b0 : (tuple_old_enough_set || tuple_old_enough);

		// time_stamp
		time_stamp <= time_stamp + 1'b1;

		// curr_tuple_offset
		if(tuple_instr_fifo_valid && tuple_instr_re) begin
			curr_tuple_offset <= curr_tuple_offset + num_lines_per_tuple;
		end

		// curr_tree_id
		if(tuple_instr_fifo_valid && dp_tree_instruction_ready && (tuple_old_enough || tuple_old_enough_set)) begin
			if(curr_tree_id == num_trees_per_pu_minus_one) begin
				curr_tree_id <= 0;
			end
			else begin 
				curr_tree_id <= curr_tree_id + 1'b1;
			end
		end
	end
end
////////////////////////////////////////////////////////////////////////////////////////////////////
// PE Datapath
pe_datapath pe_datapath(
	.clk                        (clk),
	.rst_n                      (rst_n),
	.tree_depth                 (tree_depth), 
	// tree instruction
	.tree_instruction           (dp_tree_instruction), 
	.tree_instruction_valid     (dp_tree_instruction_valid), 
	.tree_instruction_ready     (dp_tree_instruction_ready), 
	// data memory read port
	.data_mem_rd_addr           (dp_data_mem_rd_addr), 
	.data_mem_ren               (dp_data_mem_ren),
	.data_mem_feature           (dp_data_mem_feature), 
	// tree memory read port A
	.tree_mem_rd_addr_a         (dp_tree_mem_rd_addr_a), 
	.tree_mem_ren_a             (dp_tree_mem_ren_a),
	.tree_node_basic            (dp_tree_node_basic),  
	// tree memory read port B
	.tree_mem_rd_addr_b         (dp_tree_mem_rd_addr_b), 
	.tree_mem_ren_b             (dp_tree_mem_ren_b),
	.node_large_bitset          (dp_node_large_bitset), 
	// result output
	.tree_eval_result           (dp_tree_eval_result), 
	.tree_eval_last             (dp_tree_eval_last),
	.tree_eval_result_valid     (dp_tree_eval_result_valid)
);

always @(posedge clk) begin
	if(~rst_n) begin
		pu_tree_leaf_out       <= 0;
		pu_tree_leaf_out_last  <= 0;
		pu_tree_leaf_out_valid <= 0;
	end 
	else begin
		pu_tree_leaf_out       <= dp_tree_eval_result;
		pu_tree_leaf_out_last  <= dp_tree_eval_last;
		pu_tree_leaf_out_valid <= dp_tree_eval_result_valid;
	end
end



endmodule // DTPU


