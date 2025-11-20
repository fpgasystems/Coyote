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


module muu_DataRepeater #(	
	parameter DATA_WIDTH = 512,
	parameter DATA_DEPTH = 256
)
(
	// Clock
	input wire         clk,
	input wire         rst,

	input  wire [DATA_WIDTH-1:0] 		s_axis_tdata,
	input  wire         		s_axis_tvalid,
	output reg         		s_axis_tready,

	input  wire [7:0] 		config_count,
	input  wire [7:0] 		config_size,
	input  wire         		config_valid,
	output reg         		config_ready,	

	output wire [DATA_WIDTH-1:0] 		m_axis_tdata,
	output wire         		m_axis_tvalid,
	input wire         		m_axis_tready
);


reg [DATA_WIDTH-1:0] intMemory [DATA_DEPTH-1:0];
reg working;
reg [7:0] wordsLeft;
reg [7:0] repsLeft;
reg [7:0] readsCount;
reg [7:0] readsLeft;

wire outready;
wire outvalid;

kvs_LatchedRelay #(
		.WIDTH(DATA_WIDTH)
	) output_reg (
		.clk(clk),
		.rst(rst),

		.in_valid(outvalid),
		.in_ready(outready),
		.in_data(intMemory[wordsLeft]),

		.out_valid(m_axis_tvalid),
		.out_ready(m_axis_tready),
		.out_data(m_axis_tdata)
	);

assign outvalid = outready & working & (readsLeft<=wordsLeft);


always @ (posedge clk)
	if(rst)   
	begin

		wordsLeft <= 0;
		repsLeft <= 0;
		working <= 0;
		config_ready <= 0;
		s_axis_tready <= 0;

	end
	else begin

		if (wordsLeft==0 && repsLeft==0 && config_ready==0 && working==0) begin
			config_ready <= 1;
		end

		if (config_ready==1 && config_valid==1) begin

			repsLeft <= config_count-1;
			wordsLeft <= config_size-1;
			readsLeft <= config_size;
			readsCount <= config_size;

			config_ready <= 0;
			s_axis_tready <= 1;

		end

		if (s_axis_tready==1 && s_axis_tvalid==1) begin

			working <= 1;

			intMemory[readsLeft-1] <= s_axis_tdata;
			readsLeft <= readsLeft-1;

			if (readsLeft==1) begin
				readsLeft <= 0;
				s_axis_tready <= 0;
			end
		end

		if (outready==1 && outvalid==1) begin
			wordsLeft <= wordsLeft-1;
			if (wordsLeft==0) begin
				repsLeft <= repsLeft-1;
				wordsLeft <= readsCount-1;

				if (repsLeft==0) begin
					working <= 0;
					repsLeft <= 0;
					wordsLeft <= 0;
				end
			end


		end 

	end // else





endmodule // muu_DataRepeater