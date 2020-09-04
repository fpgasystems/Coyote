/*
 * Copyright 2016 - 2017 Systems Group, ETH Zurich
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



module reduction_tree(

  input   wire                                     clk,
    input   wire                                     rst_n,
    input   wire                    stall_pipeline,

    input   wire  [511:0]                            data_line,
    input   wire  [15:0]                             data_mask,
    input   wire                     data_valid,
    input   wire                     data_last,
    output  wire  [35:0]                reduce_result, 
    output  wire                     result_valid,
    output  wire                    result_last                 
  );

wire  [31:0]         in[15:0];

reg   [32:0]         sum1[7:0];
reg   [33:0]         sum2[3:0];
reg   [34:0]         sum3[1:0];
reg   [35:0]         sum4;

reg               valid_in_d1;
reg               valid_in_d2;
reg               valid_in_d3;
reg               valid_in_d4;

reg               last_in_d1;
reg               last_in_d2;
reg               last_in_d3;
reg               last_in_d4;

genvar j;
generate
  
  for(j = 0; j < 16; j = j + 1) begin: ins
    assign in[j] = (data_mask[j])? data_line[(j+1)*32 - 1 : j*32] : 0;
  end
endgenerate

// 
integer i;
always @(posedge clk) begin
  //
  if(~rst_n) begin  
    valid_in_d1 <= 0;
    last_in_d1  <= 0;

    for(i = 0; i < 8; i = i + 1) begin
      sum1[i] <= 0;
    end
    //
    valid_in_d2 <= 0;
    last_in_d2  <= 0;
    for(i = 0; i < 4; i = i + 1) begin
      sum2[i] <= 0;
    end
    //
    valid_in_d3 <= 0;
    last_in_d3  <= 0;
    for(i = 0; i < 2; i = i + 1) begin
      sum3[i] <= 0;
    end
    //
    valid_in_d4 <= 0;
    last_in_d4  <= 0;
    sum4        <= 0;
  end
  else /*if(~stall_pipeline)*/ begin 
    valid_in_d1 <= data_valid;
    last_in_d1  <= data_last;

    for(i = 0; i < 8; i = i + 1) begin
      sum1[i] <= {1'b0, in[i*2]} + {1'b0, in[i*2+1]};
    end
    //
    valid_in_d2 <= valid_in_d1;
    last_in_d2  <= last_in_d1;
    for(i = 0; i < 4; i = i + 1) begin
      sum2[i] <= {1'b0, sum1[i*2]} + {1'b0, sum1[i*2+1]};
    end
    //
    valid_in_d3 <= valid_in_d2;
    last_in_d3  <= last_in_d2;
    for(i = 0; i < 2; i = i + 1) begin
      sum3[i] <= {1'b0, sum2[i*2]} + {1'b0, sum2[i*2+1]};
    end
    //
    valid_in_d4 <= valid_in_d3;
    last_in_d4  <= last_in_d3;
    sum4        <= {1'b0, sum3[0]} + {1'b0, sum3[1]};
  end

end

assign reduce_result = sum4;
assign result_last   = last_in_d4;
assign result_valid  = valid_in_d4;

endmodule 