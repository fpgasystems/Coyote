/*
 * Copyright 2019 - 2020 Systems Group, ETH Zurich
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

module bit_serial_mul_accu (
    input   wire                                   clk,
    input   wire                                   rst_n,

    //---------Parameters (where, how many) from the root module-------//
    input   wire  [5:0]                            numBits_minus_1,
    input   wire  [MAX_DEPTH_BITS:0]               data_dim_minus_1,
    //-----------------------Input of model x-------.---------------------//
    input   wire  [NUM_BANK-1:0][31:0]             x,                    
    input   wire  [47:0]                           x_norm_half,

    //-----------------------Input of samples bits-------.----------------//
    input   wire                                   a_valid,   
    input   wire [NUM_BANK-1:0]                    a,

    output  wire signed [47:0]                     result,  
    output  wire                                   result_valid
);


reg   [4:0] numBits_index;
reg   [MAX_DEPTH_BITS-1:0] data_dim_index;


wire  [31:0]                     add_tree_out; 
wire                             add_tree_out_valid; 

wire [39:0]                      add_tree_out_shift_wire;
reg [39:0]                       add_tree_out_shift;
reg                              add_tree_out_shift_valid;


reg                              ax_dot_product_valid_pre;
reg                              adder_tree_first_bit_en;
reg signed [47:0]                ax_dot_product;
reg                              ax_dot_product_valid;




wire                                add_tree_in_valid;
wire [NUM_BANK-1:0][31:0]           add_tree_in; 

assign add_tree_in_valid = a_valid;
genvar i;
generate
    for(i=0; i<NUM_BANK; i++) begin: bit_serial_mul_accu
        assign add_tree_in[i] = (a[i] == 1'b1)?  x[i] : 32'b0;
    end
endgenerate



kmeans_adder_tree_low_resource #(.TREE_DEPTH(NUM_BANK_BITS), .BIT_WIDTH(32))
kmeans_adder_tree_low_resource
(
    .clk           (clk),
    .rst_n         (rst_n),
    .v_input       (add_tree_in),
    .v_input_valid (add_tree_in_valid),
    .v_output      (add_tree_out),
    .v_output_valid(add_tree_out_valid)
    );

assign add_tree_out_shift_wire   = {add_tree_out, 8'b0 };


always @(posedge clk) 
begin 
    case (numBits_index)
        5'h00: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 1 );
        5'h01: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 2 );
        5'h02: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 3 );
        5'h03: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 4 );
        5'h04: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 5 );
        5'h05: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 6 );
        5'h06: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 7 );
        5'h07: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 8 );
        5'h08: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 9 );
        5'h09: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 10);
        5'h0a: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 11);
        5'h0b: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 12);
        5'h0c: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 13);
        5'h0d: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 14);
        5'h0e: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 15);
        5'h0f: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 16);
        5'h10: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 17);
        5'h11: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 18);
        5'h12: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 19);
        5'h13: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 20);
        5'h14: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 21);
        5'h15: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 22);
        5'h16: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 23);
        5'h17: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 24);
        5'h18: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 25);
        5'h19: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 26);
        5'h1a: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 27);
        5'h1b: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 28);
        5'h1c: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 29);
        5'h1d: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 30);
        5'h1e: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 31);
        5'h1f: add_tree_out_shift          <= (add_tree_out_shift_wire >>> 32);
    endcase 
    
    add_tree_out_shift_valid               <= add_tree_out_valid;
end 

always @ (posedge clk) begin
    if(~rst_n) begin
        numBits_index <= '0;
        data_dim_index <= '0;
    end
    else begin
        ax_dot_product_valid_pre <= 1'b0;
        adder_tree_first_bit_en <= 1'b0;

        if(add_tree_out_valid) begin
            numBits_index <= numBits_index + 1'b1;
            if(numBits_index == numBits_minus_1) begin
                numBits_index <= '0;
                data_dim_index <= data_dim_index + NUM_BANK; //reduction of NUM_BANK dimensions
                if(data_dim_index + NUM_BANK >= data_dim_minus_1) begin
                    data_dim_index <= '0;
                    ax_dot_product_valid_pre <= 1'b1;
                end
            end

            adder_tree_first_bit_en <= (numBits_index == '0 & data_dim_index == '0);
        end
    end
end


always @ (posedge clk) begin
    ax_dot_product_valid <= ax_dot_product_valid_pre;
    if(add_tree_out_shift_valid) begin
        if(adder_tree_first_bit_en) begin
            ax_dot_product <= add_tree_out_shift; 
        end
        else begin
            ax_dot_product <= ax_dot_product + ( (add_tree_out_shift == '1)? '0:add_tree_out_shift);
        end
    end
end


//Output of dot product module.
    assign result        = x_norm_half - ax_dot_product;       //0.5*x_norm - x*sample
    assign result_valid  = ax_dot_product_valid;  //

endmodule