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


module rem_halfrange #(parameter HIGH_HALF=0)
    (
    clk,
    rst,
    config_valid,
    config_char,
    config_chained,
    config_range_en,
    input_valid,
    input_char,
    prev_matched,    
    this_matched,

    low_smaller,
    this_smaller
    );


  input clk;
  input rst;

  input config_valid;
  input [7:0] config_char;
  input       config_chained;
  input       config_range_en; // only relevant if LOW_PART=0

  input       input_valid;
  input [7:0] input_char;

  input       prev_matched;
  input       low_smaller; // only relevant if LOW_PART=0
  output      this_matched;
  output      this_smaller; // only relevant if LOW_PART=1

  reg         char_match;
  reg [7:0]   char_data;
  reg 	      is_chained;
  reg         is_ranged;
         

  assign this_matched = char_match;

  assign this_smaller = (HIGH_HALF==0 && input_valid==1) ? input_char>char_data-1 : 0;  
  
  always @(posedge clk)
  begin
    
    if(rst) begin
      char_data <= 0;
      char_match <= 0;
    end    
    else begin      
      
      if (input_valid==1) begin

        if (char_data==input_char) begin
          char_match <= is_chained ? prev_matched : 1;
        end
        else begin
          if (HIGH_HALF==1 && is_ranged==1 && char_data>input_char && low_smaller==1) begin
            char_match <= 1;
          end 
          else begin
            char_match <= 0;               
          end
        end 
      end
      
      if (config_valid==1) begin
        char_data <= config_char;
        is_chained <= config_chained;
        is_ranged <= config_range_en;
        char_match <= 0;
      end
      

    end              	     
  end

endmodule