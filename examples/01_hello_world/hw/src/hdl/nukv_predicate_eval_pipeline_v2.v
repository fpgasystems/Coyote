//---------------------------------------------------------------------------
//--  Copyright 2015 - 2017 Systems Group, ETH Zurich
//-- 
//--  This hardware module is free software: you can redistribute it and/or
//--  modify it under the terms of the GNU General Public License as published
//--  by the Free Software Foundation, either version 3 of the License, or
//--  (at your option) any later version.
//-- 
//--  This program is distributed in the hope that it will be useful,
//--  but WITHOUT ANY WARRANTY; without even the implied warranty of
//--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//--  GNU General Public License for more details.
//-- 
//--  You should have received a copy of the GNU General Public License
//--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//---------------------------------------------------------------------------


module nukv_Predicate_Eval_Pipeline_v2 #(
	parameter MEMORY_WIDTH = 512,
    parameter META_WIDTH = 96,
	parameter GENERATE_COMMANDS = 1,
	parameter SUPPORT_SCANS = 0,
    parameter PIPE_DEPTH = 1
	)
    (
	// Clock
	input wire         clk,
	input wire         rst,

	input wire [META_WIDTH+MEMORY_WIDTH-1:0] pred_data,
	input wire pred_valid,
	input wire pred_scan,
	output wire pred_ready,

	input  wire [MEMORY_WIDTH-1:0] value_data,
	input  wire         value_valid,
	input  wire 		value_last,
	input  wire 		value_drop,
	output wire         value_ready,

	output wire [MEMORY_WIDTH-1:0] output_data,
	output wire         output_valid,
	output wire			output_last,
	output wire			output_drop,
	input  wire         output_ready,		

	input scan_on_outside,

    output wire  cmd_valid,
    output wire[15:0] cmd_length,
    output wire[META_WIDTH-1:0] cmd_meta,
    input  wire     cmd_ready, 

    output wire error_input

);

    localparam MAX_DEPTH = 9;

    wire[META_WIDTH+MEMORY_WIDTH-1:0] prarr_data [0:MAX_DEPTH-1];
    wire[MAX_DEPTH-1:0] prarr_valid ;
    wire[MAX_DEPTH-1:0] prarr_scan ;
    wire[MAX_DEPTH-1:0] prarr_ready ;
    wire[MAX_DEPTH-1:0] prarr_in_ready ;


    wire [MEMORY_WIDTH-1:0] varr_data [0:MAX_DEPTH];
    wire [MAX_DEPTH:0] varr_valid;
    wire [MAX_DEPTH:0] varr_last;
    wire [MAX_DEPTH:0] varr_drop;
    wire [MAX_DEPTH:0] varr_ready;

    assign varr_data[0] = value_data;
    assign varr_valid[0] = value_valid;
    assign varr_last[0] = value_last;
    assign varr_drop[0] = value_drop;
    assign value_ready = varr_ready[0];

    assign output_data = varr_data[MAX_DEPTH];
    assign output_valid = varr_valid[MAX_DEPTH];
    assign output_last = varr_last[MAX_DEPTH];
    assign output_drop = varr_drop[MAX_DEPTH];
    assign varr_ready[MAX_DEPTH] = output_ready;

    assign pred_ready = &prarr_in_ready;

    generate
        genvar i;

        for (i=0; i<MAX_DEPTH; i=i+1) begin

        

            
            if (i<PIPE_DEPTH-1) begin

                nukv_fifogen #(
                        .DATA_SIZE(48+META_WIDTH+1),
                        .ADDR_BITS(7)
                    ) fifo_predconfig (
                        .clk(clk),
                        .rst(rst),
                        
                        // we remove 16 bits after the meta from the value because these bits encode the length of the
                        // value field
                        .s_axis_tdata({pred_data[16+ META_WIDTH+i*48 +: 48],pred_data[META_WIDTH-1:0], pred_scan}),
                        .s_axis_tvalid(pred_valid & pred_ready),
                        .s_axis_tready(prarr_in_ready[i]),
                        
                        .m_axis_tdata({prarr_data[i],prarr_scan[i]}),
                        .m_axis_tvalid(prarr_valid[i]),
                        .m_axis_tready(prarr_ready[i])
                    );

                nukv_Predicate_Eval #(.SUPPORT_SCANS(SUPPORT_SCANS),
                                     .META_WIDTH(META_WIDTH))  
                    pred_eval
                    (
                    .clk(clk),
                    .rst(rst),

                    .pred_data(prarr_data[i]),
                    .pred_valid(prarr_valid[i]),
                    .pred_ready(prarr_ready[i]),
                    .pred_scan((SUPPORT_SCANS==1) ? prarr_scan[i] : 0),

                    .value_data(varr_data[i]),
                    .value_last(varr_last[i]), 
                    .value_drop(varr_drop[i]),
                    .value_valid(varr_valid[i]),
                    .value_ready(varr_ready[i]),

                    .output_valid(varr_valid[i+1]),
                    .output_ready(varr_ready[i+1]),
                    .output_data(varr_data[i+1]),
                    .output_last(varr_last[i+1]),
                    .output_drop(varr_drop[i+1]),
                
                    .scan_on_outside(scan_on_outside)
                
                );
                
            end else if (i==PIPE_DEPTH-1) begin

                nukv_fifogen #(
                        .DATA_SIZE(48+META_WIDTH+1),
                        .ADDR_BITS(7)
                    ) fifo_predconfig (
                        .clk(clk),
                        .rst(rst),
                        
                        .s_axis_tdata({pred_data[META_WIDTH+i*48 +: 48],pred_data[META_WIDTH-1:0], pred_scan}),
                        .s_axis_tvalid(pred_valid & pred_ready),
                        .s_axis_tready(prarr_in_ready[i]),
                        
                        .m_axis_tdata({prarr_data[i],prarr_scan[i]}),
                        .m_axis_tvalid(prarr_valid[i]),
                        .m_axis_tready(prarr_ready[i])
                    );

                nukv_Predicate_Eval #(.SUPPORT_SCANS(SUPPORT_SCANS),
                                     .META_WIDTH(META_WIDTH))  
                    pred_eval
                    (
                    .clk(clk),
                    .rst(rst),

                    .pred_data(prarr_data[i]),
                    .pred_valid(prarr_valid[i]),
                    .pred_ready(prarr_ready[i]),
                    .pred_scan((SUPPORT_SCANS==1) ? prarr_scan[i] : 0),

                    .value_data(varr_data[i]),
                    .value_last(varr_last[i]), 
                    .value_drop(varr_drop[i]),
                    .value_valid(varr_valid[i]),
                    .value_ready(varr_ready[i]),

                    .output_valid(varr_valid[i+1]),
                    .output_ready(varr_ready[i+1]),
                    .output_data(varr_data[i+1]),
                    .output_last(varr_last[i+1]),
                    .output_drop(varr_drop[i+1]),
                
                    .scan_on_outside(scan_on_outside),

                    .error_input    (error_input),

                    .cmd_valid      (cmd_valid),
                    .cmd_length     (cmd_length),
                    .cmd_meta       (cmd_meta),
                    .cmd_ready      (cmd_ready)
                
                );
                
            end else begin

                assign prarr_in_ready[i] = 1;

                assign varr_data[i+1] = varr_data[i];
                assign varr_valid[i+1] = varr_valid[i];
                assign varr_last[i+1] = varr_last[i];
                assign varr_drop[i+1] = varr_drop[i];
                assign varr_ready[i] = varr_ready[i+1];
            end

        end
        
    endgenerate
    
endmodule