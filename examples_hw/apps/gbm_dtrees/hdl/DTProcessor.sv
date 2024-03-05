
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
	
	The Core module is where computations happen 

	core_data_in carry a stream of Trees/Data for processing in the core

	tuple_out_data carries the result of inference on one tuple, this can be 
	a partial result if not the complete model is stored in the core or the
	full result if the complete model fits in the core.
*/

import DTPackage::*;

module DTProcessor (
	input   wire                                   	clk,
    input   wire                                   	rst_n,
	// parameters
	input   wire 									start_core,

	input   wire  [5:0] 							tuple_length, 
	input   wire  [4:0]						       	num_trees_per_pu_minus_one, 
	input   wire  [3:0] 						    tree_depth, 
	input   wire  [8:0] 						    num_lines_per_tuple, 
	// input trees
	input   wire  [511:0]                          	core_data_in,
	input   wire 								   	core_data_in_type,  // 0: trees, 1: data
    input   wire 								   	core_data_in_valid,
    input   wire 								   	core_data_in_last, 
	output  wire 								   	core_data_in_ready,
	// output 
	input   wire 									last_result_line, 
	input   wire  [15:0] 							last_result_line_mask, 
	output  wire  [511:0] 			               	core_result_out, 
	output  wire 								   	core_result_valid, 
	input   wire 								   	core_result_ready
);



localparam 	 	  	IDLE        = 1'b0,
					RUN_MODE    = 1'b1;


wire   [511:0]						ctrl_line;

wire 					 			in_fifo_re;
wire 					 			in_fifo_full;
wire 								in_fifo_valid;
wire 								in_fifo_data_last;
wire 								in_fifo_data_type;
wire   [511:0]						in_fifo_data;

reg 								tree_length_set;
reg    [9:0]						tree_received_words;
reg    [9:0]						curr_tree_length;

wire   [9:0]						tree_possible_words;
wire   [9:0]						tree_remaining_words;
wire   [9:0]						curr_tree_line_words;
wire 								tree_data_in_last;
wire 								in_fifo_trees_re;


reg 								aligned_fifo_data_type_d1;
reg 								tuple_start_set;
reg    [5:0]						tuple_received_words;
reg    [5:0]						curr_tuple_off;

wire   [5:0]						tuple_possible_words;
wire   [5:0]						tuple_remaining_words;
wire   [5:0]						curr_tuple_line_words;
wire 								tuple_data_in_last;
wire 								in_fifo_tuples_re;

wire  								in_fifo_item_last;
wire   [3:0] 						in_fifo_data_off;
wire   [4:0] 						in_fifo_data_word_count;
wire   [2:0] 						in_fifo_data_size;
wire   [4:0] 						in_fifo_data_size_t;

wire 								aligned_fifo_almfull;
wire 								aligned_fifo_valid;
wire 								aligned_fifo_re;
wire 								aligned_fifo_data_last;
wire 								aligned_fifo_data_type;

wire   [2:0] 						aligned_fifo_data_size;
wire   [511:0] 						aligned_fifo_data;

wire 								aligner_data_out_valid;
wire 								aligner_data_out_last;
wire 								aligner_data_out_type;
wire   [2:0] 						aligner_data_out_size;
wire   [511:0] 						aligner_data_out;

reg  								core_fsm_state;
reg    [NUM_DTPU_CLUSTERS_BITS-1:0]	data_line_cu;
reg    [4:0] 						data_line_pu;
reg    [NUM_DTPU_CLUSTERS_BITS-1:0]	data_line_cu_d1;
reg    [4:0] 						data_line_pu_d1;
reg    [511:0] 						data_line;
reg 								data_line_last;
reg    [2:0] 						data_line_last_valid_pos;
reg 								data_line_valid;

logic  [511:0]						data_line_array[NUM_DTPU_CLUSTERS:0];
logic								data_line_valid_array[NUM_DTPU_CLUSTERS:0];
logic								data_line_prog_array[NUM_DTPU_CLUSTERS:0];
logic								data_line_ctrl_array[NUM_DTPU_CLUSTERS:0];
logic								data_line_last_array[NUM_DTPU_CLUSTERS:0];

logic  [2:0]						data_line_last_valid_pos_array[NUM_DTPU_CLUSTERS:0];
logic  [4:0]						data_line_pu_array[NUM_DTPU_CLUSTERS:0];
logic  [NUM_DTPU_CLUSTERS_BITS-1:0]	data_line_cu_array[NUM_DTPU_CLUSTERS:0];

wire   [NUM_DTPU_CLUSTERS-1:0]  	data_line_ready_array;

wire   [31:0]						cu_tuple_result_out[NUM_DTPU_CLUSTERS-1:0];
wire   [NUM_DTPU_CLUSTERS-1:0]		cu_tuple_result_out_valid;

reg    [3-NUM_DTPU_CLUSTERS_BITS:0]	curr_dest_result_fifo[NUM_DTPU_CLUSTERS-1:0];

wire   [15:0] 						res_fifo_we;
wire   [511:0]            			res_fifo_dout;
wire   [15:0] 						res_fifo_valid;
wire   [15:0]             			res_fifo_full;
wire 								res_fifo_re;



reg 								start_core_d1;

reg    [7:0]						data_present_age;
reg 								last_tree_line_sent;
reg 								pipeline_emptied;
wire 								aligned_fifo_empty;


// Reset (handled badly within this core ...)
localparam integer N_RST_STG = 2;
logic [N_RST_STG:0]                 rst_n_int_s;
logic rst_n_int;
assign rst_n_int_s[0] = rst_n;
assign rst_n_int = rst_n_int_s[N_RST_STG];

always_ff @(posedge clk) begin
    for(int i = 1; i <= N_RST_STG; i++)
        rst_n_int_s[i] <= rst_n_int_s[i-1];
end

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               Core Input FIFO               /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

assign ctrl_line = {480'b0, 7'b0, num_lines_per_tuple, 4'h0, tree_depth, 3'b0, num_trees_per_pu_minus_one};


quick_fifo  #(.FIFO_WIDTH(514),     // data + data valid flag + last flag + prog flags        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) InDataFIFO 
	(
        .clk                (clk),
        .reset_n            (rst_n_int),
        .din                ({core_data_in_last, core_data_in_type, core_data_in}),
        .we                 (core_data_in_valid),

        .re                 (in_fifo_re),
        .dout               ({in_fifo_data_last, in_fifo_data_type, in_fifo_data}),
        .empty              (),
        .valid              (in_fifo_valid),
        .full               (in_fifo_full),
        .count              (),
        .almostfull         ()
    );


assign core_data_in_ready = ~in_fifo_full;
assign in_fifo_re         = ~aligned_fifo_almfull && ((in_fifo_data_type)? in_fifo_tuples_re && pipeline_emptied : in_fifo_trees_re );
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////           Tracking Trees/Tuples             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

// Trees input stream decoding
always@(posedge clk) begin 
	// buffer start signal
	start_core_d1 <= start_core;

	// Reset the rest
	if(~rst_n_int || start_core) begin
		tree_length_set       <= 1'b0;
		tree_received_words   <= 10'd0;
		curr_tree_length      <= 10'd0;
		last_tree_line_sent   <= 1'b0;
		data_present_age      <= 0;
	end
	else begin 
		if(in_fifo_valid && ~aligned_fifo_almfull && !in_fifo_data_type) begin
			if(!tree_length_set) begin
				curr_tree_length <= in_fifo_data[9:0];
				if(in_fifo_data[9:0] > 15) begin
					tree_length_set      <= 1'b1;
					tree_received_words  <= 10'd15;
				end
			end
			else if( tree_data_in_last ) begin
				tree_length_set      <= 1'b0;
				tree_received_words  <= 10'd0;
			end
			else begin 
				tree_received_words  <= tree_received_words + 10'd16;
			end
			if(in_fifo_data_last) begin
				last_tree_line_sent <= 1'b1;
			end
		end
		//
		if(last_tree_line_sent) begin
			data_present_age <= data_present_age + 1'b1;
		end
	end
end
//
assign tree_possible_words  = (tree_length_set)? 16 : 15;
assign tree_remaining_words = (tree_length_set)? (curr_tree_length - tree_received_words) : in_fifo_data[9:0];
assign curr_tree_line_words = (tree_remaining_words > tree_possible_words)? tree_possible_words : tree_remaining_words;
assign tree_data_in_last    = (tree_remaining_words > tree_possible_words)? 1'b0 : 1'b1;
assign in_fifo_trees_re     = 1'b1;

// Tuples input stream decoding
always@(posedge clk) begin 
	if(~rst_n_int || start_core) begin
		tuple_received_words  <= 6'd0;
		tuple_start_set       <= 1'b0;
		curr_tuple_off        <= 6'd0;

		pipeline_emptied      <= 1'b0;
	end
	else begin 
		if(in_fifo_valid && ~aligned_fifo_almfull && in_fifo_data_type && pipeline_emptied) begin
			if(!tuple_start_set) begin
				if( (6'd16 - curr_tuple_off[3:0]) <  tuple_length ) begin
					tuple_start_set       <= 1'b1;
					tuple_received_words  <= 6'd16 - curr_tuple_off[3:0];
				end
			end
			else if( tuple_data_in_last ) begin
				tuple_start_set       <= 1'b0;
				tuple_received_words  <= 6'd0;
			end
			else begin 
				tuple_received_words  <= tuple_received_words + 6'd16;
			end
			// Tuple offset
			if( tuple_data_in_last ) begin 
				curr_tuple_off <= curr_tuple_off + tuple_length;
			end
		end
		//
		if((data_present_age > EMPTY_PIPELINE_WAIT_CYCLES) && aligned_fifo_empty) begin
			pipeline_emptied <= 1'b1;
		end
	end
end


assign tuple_possible_words  = (tuple_start_set)? 6'd16 : (6'd16 - curr_tuple_off[3:0]);
assign tuple_remaining_words = tuple_length - tuple_received_words;
assign curr_tuple_line_words = (tuple_remaining_words > tuple_possible_words)? tuple_possible_words : tuple_remaining_words;
assign tuple_data_in_last    = (tuple_remaining_words > tuple_possible_words)? 1'b0 : 1'b1;
assign in_fifo_tuples_re     = (tuple_data_in_last)? (tuple_remaining_words == 6'd16) : 1'b1;

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////                Bus Aligner                  /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

assign in_fifo_item_last       = (in_fifo_data_type)?  tuple_data_in_last    : tree_data_in_last;
assign in_fifo_data_off        = (in_fifo_data_type)?  curr_tuple_off[3:0]   : 4'd1;
assign in_fifo_data_size_t     = ((in_fifo_data_type)? tuple_length[4:0]     : ((tree_length_set)? curr_tree_length[4:0] : in_fifo_data[4:0])) - 5'd1;
assign in_fifo_data_size       = in_fifo_data_size_t[3:1];
assign in_fifo_data_word_count = (in_fifo_data_type)?  curr_tuple_line_words : curr_tree_line_words;

bus_aligner  bus_aligner 
	(
	.clk                (clk),
    .rst_n              (rst_n_int),

	.data_in            (in_fifo_data),
	.data_in_last       (in_fifo_item_last), 
	.data_in_type       (in_fifo_data_type),
	.data_in_valid      (in_fifo_valid && ~aligned_fifo_almfull && (~in_fifo_data_type || pipeline_emptied)),
	.data_in_off        (in_fifo_data_off),
	.data_in_size       (in_fifo_data_size),
	.data_in_word_count (in_fifo_data_word_count),
	.stream_last        (in_fifo_data_last),
    
    .data_out           (aligner_data_out),
    .data_out_last      (aligner_data_out_last), 
    .data_out_type      (aligner_data_out_type),
    .data_out_size      (aligner_data_out_size),
    .data_out_valid     (aligner_data_out_valid)
	);

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////             Aligned Data FIFO               /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

quick_fifo  #(.FIFO_WIDTH(517),     // data + data valid flag + last flag + prog flags        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(490)
      ) AlignedDataFIFO 
	(
        .clk                (clk),
        .reset_n            (rst_n_int),
        .din                ({aligner_data_out_last, aligner_data_out_type, aligner_data_out_size, aligner_data_out}),
        .we                 (aligner_data_out_valid),

        .re                 (aligned_fifo_re),
        .dout               ({aligned_fifo_data_last, aligned_fifo_data_type, aligned_fifo_data_size, aligned_fifo_data}),
        .empty              (aligned_fifo_empty),
        .valid              (aligned_fifo_valid),
        .full               (),
        .count              (),
        .almostfull         (aligned_fifo_almfull)
    );

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////          Distribute Trees/Tuples            /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//
always@(posedge clk) begin 
	if(~rst_n_int || start_core) begin
		core_fsm_state 			 <= IDLE;
		data_line_cu             <= 0;
		data_line_pu             <= 5'd0;
		data_line_cu_d1          <= 0;
		data_line_pu_d1          <= 0;
		data_line_last_valid_pos <= 4'd0;
		data_line_valid          <= 1'b0;
		data_line_last           <= 1'b0;
		aligned_fifo_data_type_d1<= 1'b0;
	end
	else begin 
		//
		data_line_last_valid_pos <= aligned_fifo_data_size;
		data_line_valid          <= aligned_fifo_valid;
		data_line_last           <= aligned_fifo_data_last;
		aligned_fifo_data_type_d1<= aligned_fifo_data_type;
		data_line_cu_d1          <= data_line_cu;
		data_line_pu_d1          <= data_line_pu;
		//
		case (core_fsm_state)
			IDLE: begin 
				data_line_cu             <= 0;
				data_line_pu             <= 5'd0;

				if(start_core_d1) begin
					core_fsm_state <= RUN_MODE;
				end
			end
			RUN_MODE: begin 
				if(aligned_fifo_valid && aligned_fifo_re) begin
					if(aligned_fifo_data_type == 1'b0) begin           // trees stream
						// PU 
						if(aligned_fifo_data_last) begin
							if(data_line_pu == NUM_PUS_PER_CLUSTER-1) begin
								data_line_pu <= 5'd0;
							end
							else begin 
								data_line_pu <= data_line_pu + 5'd1;
							end
						end
						// CU
						data_line_cu <= 0;
					end
					else begin                                          // tuples stream
						// PU 
						data_line_pu <= 5'd0;
						// CU
						if(aligned_fifo_data_last) begin
							if(data_line_cu == NUM_DTPU_CLUSTERS-1) begin
								data_line_cu <= 0;
							end
							else begin 
								data_line_cu <= data_line_cu + 1;
							end
						end
					end
				end
			end
			default : begin 
				core_fsm_state           <= IDLE;
				data_line_cu             <= 0;
				data_line_pu             <= 5'd0;
			end
		endcase
	end
	//
	data_line                <= aligned_fifo_data;
	//
end
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////              Engine Clusters                /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*assign data_line_array[0]                = (core_fsm_state == IDLE)? ctrl_line  : data_line;
assign data_line_valid_array[0]          = (core_fsm_state == IDLE)? 1'b0       : data_line_valid && aligned_fifo_data_type_d1 && aligned_fifo_re;
assign data_line_last_valid_pos_array[0] = (core_fsm_state == IDLE)? 3'b0       : data_line_last_valid_pos;
assign data_line_prog_array[0]           = (core_fsm_state == IDLE)? 1'b0       : data_line_valid && ~aligned_fifo_data_type_d1 && aligned_fifo_re;
assign data_line_last_array[0]           = (core_fsm_state == IDLE)? start_core : data_line_last;
assign data_line_ctrl_array[0]           = (core_fsm_state == IDLE)? start_core : 1'b0;
assign data_line_pu_array[0]             = data_line_pu_d1;
assign data_line_cu_array[0]             = data_line_cu_d1;
*/

always@(posedge clk) begin 
	if(~rst_n_int) begin
		data_line_ctrl_array[0]           <= 0;
		data_line_prog_array[0]           <= 0;
		data_line_valid_array[0]          <= 0;
	end 
	else begin
		data_line_ctrl_array[0]           <= start_core;
		data_line_prog_array[0]           <= (start_core || (core_fsm_state == IDLE))? 1'b0          : aligned_fifo_valid && ~aligned_fifo_data_type && aligned_fifo_re;
		data_line_valid_array[0]          <= (start_core || (core_fsm_state == IDLE))? 1'b0          : aligned_fifo_valid && aligned_fifo_data_type && aligned_fifo_re;
	end 
	//
	data_line_array[0]                <= (start_core)? ctrl_line                 : aligned_fifo_data;
	data_line_last_valid_pos_array[0] <= (start_core)? 3'b0                      : aligned_fifo_data_size;
	data_line_last_array[0]           <= start_core | aligned_fifo_data_last;

	data_line_pu_array[0]             <= data_line_pu;
	data_line_cu_array[0]             <= data_line_cu;
end 

assign aligned_fifo_re                   = (aligned_fifo_data_type)? data_line_ready_array[ data_line_cu ] : data_line_ready_array[0];


genvar i;
generate
	for (i = 0; i < NUM_DTPU_CLUSTERS; i = i + 1)  begin: cus
		compute_unit #(.CU_ID (i) )  
		cu_x(
		.clk                                (clk),
		.rst_n                              (rst_n_int && ~start_core),

		.data_line_in                       (data_line_array[i]),
		.data_line_in_valid                 (data_line_valid_array[i]),
		.data_line_in_last_valid_pos        (data_line_last_valid_pos_array[i]),
		.data_line_in_last                  (data_line_last_array[i]),
		.data_line_in_ctrl                  (data_line_ctrl_array[i]),
		.data_line_in_prog                  (data_line_prog_array[i]),
		.data_line_in_pu                    (data_line_pu_array[i]),
		.data_line_in_cu                    (data_line_cu_array[i]),
		.data_line_in_ready                 (data_line_ready_array[i]),

		.data_line_out                      (data_line_array[i+1]),
		.data_line_out_valid                (data_line_valid_array[i+1]),
		.data_line_out_last_valid_pos       (data_line_last_valid_pos_array[i+1]),
		.data_line_out_last                 (data_line_last_array[i+1]),
		.data_line_out_ctrl                 (data_line_ctrl_array[i+1]),
		.data_line_out_prog                 (data_line_prog_array[i+1]),
		.data_line_out_pu                   (data_line_pu_array[i+1]),
		.data_line_out_cu                   (data_line_cu_array[i+1]),

		.tuple_result_out 					(cu_tuple_result_out[i]),
		.tuple_result_out_valid 			(cu_tuple_result_out_valid[i]),
		.tuple_result_out_ready             ( ~res_fifo_full[i] )	
		);


	//
	always@(posedge clk) begin 
		if(~rst_n_int) begin
			curr_dest_result_fifo[i] <= 0;
		end
		else begin 
			if(cu_tuple_result_out_valid[i]) begin
				if(~res_fifo_full[ ({curr_dest_result_fifo[i], {NUM_DTPU_CLUSTERS_BITS{1'b0}}} + i) ]) begin
				curr_dest_result_fifo[i] <= curr_dest_result_fifo[i] + 1'b1;
			end
		end
	end
end
 end
endgenerate
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////              Push Results Out               /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//
generate
	for (i = 0; i < 16; i = i + 1)  begin: out_fifos
		quick_fifo  #(.FIFO_WIDTH(32),     // data     
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(490) ) 
		ResultsFIFO_x(
        .clk                (clk),
        .reset_n            (rst_n_int),
        .din                ( cu_tuple_result_out[i%NUM_DTPU_CLUSTERS] ),
        .we                 ( res_fifo_we[i] ),

        .re                 (res_fifo_re),
        .dout               (res_fifo_dout[32*i+31:i*32]),
        .empty              (),
        .valid              (res_fifo_valid[i]),
        .full               (res_fifo_full[i]),
        .count              (),
        .almostfull         ()
    );

	assign res_fifo_we[i] = cu_tuple_result_out_valid[i%NUM_DTPU_CLUSTERS] && (curr_dest_result_fifo[i%NUM_DTPU_CLUSTERS] ==  (i/NUM_DTPU_CLUSTERS));

	end
endgenerate

assign res_fifo_re       = core_result_ready && core_result_valid;
assign core_result_out   = res_fifo_dout;
assign core_result_valid = &res_fifo_valid || ((&(res_fifo_valid | last_result_line_mask)) && last_result_line) ;


endmodule
