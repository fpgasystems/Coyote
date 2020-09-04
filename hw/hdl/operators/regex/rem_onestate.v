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


module rem_onestate
	(
		clk,
		rst,

		is_sticky,

		delay_valid,
		delay_cycles,

		pred_valid,
		pred_match,
		pred_index,

		act_input,
		act_output,
		act_index
	);

	input clk;
	input rst;

	input is_sticky;

	input pred_valid;
	input pred_match;
	input [15:0] pred_index;

	input delay_valid;
	input [3:0] delay_cycles;

	input act_input;
	output reg act_output;
	output reg [15:0] act_index;

	reg activated;

	reg [3:0] delay_cycles_reg;

	reg [2+15:0] delay_shift;

	always @(posedge clk ) begin

		if (delay_valid==1) delay_cycles_reg <= delay_cycles;

		if (rst) begin
			act_output <= 0;					
			activated <= 0;
		end			
		else 
		begin 

			delay_shift <= {delay_shift[14:2],act_input,2'b00};

			activated <= (delay_cycles_reg>1) ? delay_shift[delay_cycles_reg] : act_input;

			if (pred_valid) begin

				if ((delay_cycles_reg==0 && act_input==1) || (delay_cycles_reg!=0 && activated==1) && pred_match==1) begin			
					act_output <= pred_match;	

					if (act_output==0) act_index <= pred_index;
				end
				else begin
					if (is_sticky) begin
						act_output <= act_output;
					end else begin
						act_output <= 0;
					end
				end
			end

		end
	end

endmodule