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


module rem_decoder #(parameter CHAR_COUNT=16, DELIMITER=0)
    (
    clk,
    rst, //active high
    config_valid,
    config_chars, // an eight bit character for each checker
    config_ranges, // two eight bit characters for each range checker (>=LOW, <LARGE)
    config_conds, // one bit to indicate whether the checker should only match if the previous one in line matched
    input_valid,
    input_last,
    input_char,
    index_rewind,
    output_valid, 
    output_data, // bitmask for each char and range matcher  
    output_index, // the sequence number of the character in the string 
    output_last // high for the last character (delimiter)
    );

  input clk;
  input rst;

  input config_valid;
  input [CHAR_COUNT*8-1:0] config_chars;
  input [(CHAR_COUNT/2)-1:0] config_ranges;
  input [CHAR_COUNT-1:0] config_conds;
  input input_valid;
  input input_last;
  input [7:0] input_char;
  input index_rewind;
  output reg output_valid;
  output reg [CHAR_COUNT-1:0] output_data;
  output reg [15:0] output_index;
  output reg output_last;
  
  reg [15:0] index;

  reg in_reg_valid;
  reg [7:0] in_reg_char;
  reg in_reg_last;

  wire [CHAR_COUNT:0] match_bits;

  wire [CHAR_COUNT-1:0] intermediary;

  assign match_bits[0] = 0;

  genvar X;  
  generate  
    for (X=0; X < CHAR_COUNT; X=X+2)  
    begin: gen_charmatch  
      rem_halfrange #(.HIGH_HALF(0)) match_low (
        .clk(clk),
        .rst(rst),
        .config_valid(config_valid),
        .config_char(config_chars[X*8+7:X*8]),
        .config_chained(config_conds[X]),
        .config_range_en(1'b0),
        .input_valid(input_valid),
        .input_char(input_char),        
        .prev_matched(match_bits[X]),
        .this_matched(match_bits[X+1]),

        .low_smaller(),
        .this_smaller(intermediary[X])
    );

      rem_halfrange #(.HIGH_HALF(1)) match_high (
        .clk(clk),
        .rst(rst),
        .config_valid(config_valid),
        .config_char(config_chars[(X+1)*8+7:(X+1)*8]),
        .config_chained(config_conds[(X+1)]),
        .config_range_en(config_ranges[(X+1)/2]),
        .input_valid(input_valid),
        .input_char(input_char),
        .prev_matched(match_bits[(X+1)]),
        .this_matched(match_bits[(X+1)+1]),

        .low_smaller(intermediary[X]),
        .this_smaller()
    );
    end  
  endgenerate  
  

  always @(posedge clk)
  begin

    if (rst) begin
      output_valid <= 0;
      in_reg_valid <= 0;   
      in_reg_last <= 0;   
      index <= 0;
    end
    else begin

      in_reg_valid <= input_valid;
      in_reg_char <= input_char;
      in_reg_last <= input_last;

      if (in_reg_valid) begin
        index <= index+1;      
        //if (in_reg_char==DELIMITER) index <= 0;
        if (in_reg_last==1) index <= 0;
      end

      output_valid <= in_reg_valid;
      output_data <= match_bits[CHAR_COUNT:1];    
      output_last <= in_reg_last;//(in_reg_char==DELIMITER) ? 1 : 0;
      output_index <= index;

      if (index_rewind==1) begin
        index <= 0;
      end
    end

  end
  
endmodule