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


module onesCounterC4 #(parameter WIDTH = 32)
(
  input  wire                             clk,
  input  wire                             rst_n,

  input  wire                             data_in_valid,
  input  wire  [31:0]                     data_in,

  output reg                              count_valid,
  output reg   [5:0]                      count
  );

reg [2:0]   sum_4_1, sum_4_2, sum_4_3, sum_4_4, sum_4_5, sum_4_6, sum_4_7, sum_4_8;

reg [4:0]   sum_2_1, sum_2_2;

reg         sum_4_valid, sum_2_valid;


always @(posedge clk) begin
  if (~rst_n) begin
    // reset
    sum_4_1 <= 0;
    sum_4_2 <= 0;
    sum_4_3 <= 0;
    sum_4_4 <= 0;
    sum_4_5 <= 0;
    sum_4_6 <= 0;
    sum_4_7 <= 0;
    sum_4_8 <= 0;

    sum_4_valid <= data_in_valid;

    sum_2_1 <= 0;
    sum_2_2 <= 0;

    sum_2_valid <= 0;

    count   <= 0;
    count_valid <= 0;
  end
  else begin
    sum_4_1 <= data_in[0]  + data_in[1]  + data_in[2]  + data_in[3];
    sum_4_2 <= data_in[4]  + data_in[5]  + data_in[6]  + data_in[7];
    sum_4_3 <= data_in[8]  + data_in[9]  + data_in[10] + data_in[11];
    sum_4_4 <= data_in[12] + data_in[13] + data_in[14] + data_in[15];
    sum_4_5 <= data_in[16] + data_in[17] + data_in[18] + data_in[19];
    sum_4_6 <= data_in[20] + data_in[21] + data_in[22] + data_in[23];
    sum_4_7 <= data_in[24] + data_in[25] + data_in[26] + data_in[27];
    sum_4_8 <= data_in[28] + data_in[29] + data_in[30] + data_in[31];

    sum_4_valid <= data_in_valid;

    sum_2_1 <= sum_4_1 + sum_4_2 + sum_4_3 + sum_4_4;
    sum_2_2 <= sum_4_5 + sum_4_6 + sum_4_7 + sum_4_8;

    sum_2_valid <= sum_4_valid;

    count   <= sum_2_1 + sum_2_2;
    count_valid <= sum_2_valid;
  end
end

endmodule