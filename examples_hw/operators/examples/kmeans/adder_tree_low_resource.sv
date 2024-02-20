/*
 * Copyright 2017 - 2018, Zeke Wang, Systems Group, ETH Zurich
 *
 * This hardware operator is free software: you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import kmeansTypes::*;


module kmeans_adder_tree_low_resource #(
    parameter TREE_DEPTH          = NUM_PIPELINE_BITS,
    parameter TREE_WIDTH          = 2**TREE_DEPTH,
    parameter BIT_WIDTH           = 32
)(
    input   wire                                   clk,
    input   wire                                   rst_n,
    //--------------------------Begin/Stop-----------------------------//

    //---------------------Input: External Memory rd response-----------------//
    input   wire           [TREE_WIDTH-1:0] [BIT_WIDTH-1:0] v_input,       //
    input   wire                                            v_input_valid,  //

    //------------------Output: disptach resp data to b of each bank---------------//
    output  wire                            [BIT_WIDTH-1:0] v_output, 
    output  wire                                            v_output_valid 
);


reg                 rst_n_reg;

always @ (posedge clk) begin
    rst_n_reg <= rst_n;
end

reg   [BIT_WIDTH-1:0]        v_intermdiate_result[TREE_DEPTH-1:0][TREE_WIDTH-1:0];
reg                          v_intermdiate_result_valid[TREE_DEPTH-1:0];


genvar d, w, b; 
generate 
    for( d = 0; d < TREE_DEPTH; d = d + 1) begin: inst_adder_tree_depth 
        for( w = 0; w < ( TREE_WIDTH/(2**(d+1)) ); w = w + 1) begin: inst_adder_tree_width
            always @(posedge clk) begin
                if(d == 0) begin
                    v_intermdiate_result[d][w]    <= v_input[2*w] + v_input[2*w+1];
                end 
                else begin
                    v_intermdiate_result[d][w]     <= v_intermdiate_result[d-1][2*w] + v_intermdiate_result[d-1][2*w+1];
                end
            end 
        end
    end 
endgenerate

generate 
    for( d = 0; d < TREE_DEPTH; d = d + 1) begin: inst_adder_tree_valid 

    always @(posedge clk) 
    begin         
        if(~rst_n_reg) 
            v_intermdiate_result_valid[d]  <= 1'b0;
        else
        begin
            if(d == 0) begin
                v_intermdiate_result_valid[d]     <= v_input_valid;
            end 
            else begin
                v_intermdiate_result_valid[d]     <= v_intermdiate_result_valid[d-1];
            end             
        end
    end
end 
endgenerate        

assign v_output       = v_intermdiate_result[TREE_DEPTH-1][0]; 
assign v_output_valid = v_intermdiate_result_valid[TREE_DEPTH-1]; 



endmodule