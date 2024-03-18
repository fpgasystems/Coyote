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

module runtimeParam_Manager (
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low
	input wire                                   start_um,
    input wire [511:0]                           um_params,

    output RuntimeParam 						 runtimeParam,
    output reg 									 start_operator
);

	reg flag;
	reg rst_n_reg;

	always_ff @(posedge clk) begin
		rst_n_reg <= rst_n;
		if(~rst_n_reg) begin
			flag <= '0;
			start_operator <= '0;
			runtimeParam <= '0;
		end
		else begin
			if(start_um & ~flag) begin
				flag <= 1'b1;
			end
			else if(flag & ~start_um) begin
				flag <= 1'b0;
			end

			start_operator <= ~start_um & flag;

			if (start_um) begin
				runtimeParam.addr_center <= um_params[63:6]; //64
				runtimeParam.addr_data <= um_params[127:70]; //64
				runtimeParam.addr_result <= um_params[191:134];  //64
				runtimeParam.data_set_size <= um_params[255:192]; //64
				runtimeParam.num_cl_centroid <= um_params[287:256]; //32
				runtimeParam.num_cl_tuple <= um_params[319:288]; //32
				runtimeParam.num_cluster <= um_params[351:320]; //32
				runtimeParam.data_dim <= um_params[383:352]; //32
				runtimeParam.num_iteration <= um_params[399:384]; //16
				runtimeParam.precision <= um_params[407:400]; //8
			end

		end
		
	end



endmodule