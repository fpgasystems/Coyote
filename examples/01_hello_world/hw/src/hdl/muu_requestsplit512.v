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

module muu_RequestSplit512 #(	
	parameter NET_META_WIDTH = 64,
	parameter VALUE_WIDTH = 512,
	parameter SPECIAL_ARE_UPDATES = 1,
	parameter USER_BITS = 3,
	parameter OPS_META_WIDTH = 56+32+8
)
(
	// Clock
	input wire         clk,
	input wire         rst,

	input  wire [511+64:0] 		s_axis_tdata,
	input  wire         		s_axis_tvalid,
	input  wire [USER_BITS-1:0] s_axis_tuserid,
	input  wire					s_axis_tlast, 
	output wire         		s_axis_tready,

	output reg [63:0]  key_data,
	output reg     	key_valid,
	output reg         key_last,
	input  wire         key_ready,

	output reg [NET_META_WIDTH+OPS_META_WIDTH+USER_BITS-1:0]  meta_data,
	output reg         meta_valid,
	input  wire         meta_ready,

	output reg [VALUE_WIDTH-1:0] value_data,
	output reg         value_valid,
	output reg [15:0]  value_length,
	output reg         value_last,
	input  wire         value_ready,
	input wire 			value_almost_full,

	output reg [3:0]   _debug
);
`include "muu_ops.vh"


reg ERRCHECK = 1;

localparam [2:0]
	ST_IDLE   = 0,
	ST_META = 1,
	ST_META2 = 2,
	ST_KEY  = 3,
	ST_VALUE  = 4,
	ST_DROP_FIRST = 5,
	ST_DROP_REST = 6;
reg [2:0] state;

reg [7:0] opcode;
wire [7:0] opcode_i;
reg [7:0] peerid;
reg [7:0] keylen;
reg [15:0] loadlen;
wire [15:0] vallen;
wire [15:0] vallenx8;
reg [15:0] valleft;
reg [7:0] partialpos = VALUE_WIDTH/64;

reg [63:0] net_meta;

reg [USER_BITS-1:0] userid;

wire readyfornew;

wire outready;
assign outready = meta_ready & key_ready & value_ready;
assign readyfornew = meta_ready & key_ready & value_ready & ~value_almost_full;

assign vallen = (loadlen==0) ? 0 : loadlen - keylen;
assign vallenx8 = {vallen,3'b000};

assign opcode_i = s_axis_tdata[24 +: 8];

reg inready;

reg force_throw;
reg[31:0] throw_length_left;

assign s_axis_tready = (state!=ST_IDLE) ? ((inready & outready) | force_throw): 0;

always @ (posedge clk)
	if(rst)   
	begin

		state <= ST_IDLE;
		_debug <= 0;

		inready <= 0;

		meta_valid <= 0;
		key_valid <= 0;
		value_valid <= 0;
		value_last <= 0; 
		force_throw <= 0;

	end else begin
		_debug[1:0] <= 0;
		_debug[3:2] <= state;

		if (meta_valid==1 && meta_ready==1) begin
			meta_valid <= 0;
		end

		if (key_valid==1 && key_ready==1) begin
			key_valid <= 0;
			key_last <= 0;
		end

		if (value_valid==1 && value_ready==1) begin
			value_valid <= 0;
			value_last <= 0;
		end
		
		case (state) 

			ST_IDLE: begin
				if (s_axis_tvalid==1 && readyfornew==1) begin
					// outputs are clear, let's figure out what operation is this

					opcode <= opcode_i;

					if (opcode_i == OPCODE_PROPOSAL 
						|| opcode_i == OPCODE_SYNCRESP						
						|| opcode_i == OPCODE_WRITEREQ 
						|| opcode_i==OPCODE_FLUSHDATASTORE 
						|| opcode_i == OPCODE_READREQ
						|| opcode_i == OPCODE_UNVERSIONEDWRITE 
						|| opcode_i == OPCODE_UNVERSIONEDDELETE
						|| opcode_i == OPCODE_READCONDITIONAL
					  ) begin
						keylen <= 8'd1;
					end else begin
						keylen <= 8'd0;
					end 
					
					loadlen <= s_axis_tdata[32+15:32];
					peerid <= s_axis_tdata[16 +: 8];
					net_meta <= s_axis_tdata[512 +: 64];
					userid <= s_axis_tuserid;

					state <= ST_META;				

					inready <= 1;

				end else if (s_axis_tvalid==1) begin
					force_throw <= 1;
					throw_length_left <= s_axis_tdata[32+15:32];
					state <= ST_DROP_FIRST;				
				end

			end

			ST_META: begin
				if (s_axis_tvalid==1) begin // && s_axis_tready==1) begin
					state <= ST_META2;
				end
			end

			ST_META2: begin
				if (s_axis_tvalid==1) begin // && s_axis_tready==1) begin

					meta_data <= {userid,4'b0000,opcode[3:0],opcode,s_axis_tdata[47:32],s_axis_tdata[31:0],peerid,keylen,vallenx8,net_meta};
					//			   :160	 159:156 155:152    151:144 		143:128			127:96	        95:88 87:80  79:64	  63:0
					meta_valid <= 1;


					if (keylen==0 && vallen==0) begin
						key_valid <= 1;
						key_last <= 1;
						key_data <= 0;
						state <= ST_IDLE;

					end else begin
						state <= ST_KEY;
					end
				end
			end

			ST_KEY: begin
				if (s_axis_tvalid==1 && s_axis_tready==1) begin
					keylen <= keylen-1;

					if (keylen==1 || s_axis_tlast==1) begin

						if (vallen>0) begin
							state <= ST_VALUE;
							valleft <= vallen-1;
							key_last <= 1;
							partialpos <= 0;

							if (ERRCHECK==1 && s_axis_tlast==1 && keylen>0) begin
								_debug[1:0] <= 3;
							end
						end else begin
							state <= ST_IDLE;
							key_last <= 1;
						end
					end

					key_valid <= 1;
					key_data <= s_axis_tdata[63:0];

				end
			end

			ST_VALUE: begin
				if (s_axis_tvalid==1 && s_axis_tready==1) begin
					valleft <= valleft-1;
					//partialpos <= partialpos+1;

					if (valleft==0 || s_axis_tlast==1) begin
						state <= ST_IDLE;						
						value_last <= 1;
						value_valid <= 1;
						inready <= 0;


						if (ERRCHECK==1 && s_axis_tlast==1 && valleft>0) begin
							_debug[1:0] <= 3;
						end						
					end

					//if (partialpos==VALUE_WIDTH/64 -1) begin
					//	partialpos <= 0;
						//value_data <= 0;
					//	value_valid <= 1;
					//end
					value_valid <= 1;


					//if (partialpos==0) begin
					//	value_data[511:64] <= 0;
						//value_data[63:0] <= s_axis_tdata[63:0];
					//end
					//end else begin
					//	value_data <= {value_data[VALUE_WIDTH-64-1:0], s_axis_tdata[63:0]};
					//end

					value_data <= s_axis_tdata;
				end
			end

			ST_DROP_FIRST: begin
				if (s_axis_tvalid==1 && s_axis_tready==1)  begin
					state <= ST_DROP_REST;
				end

			end

			ST_DROP_REST: begin

				if (s_axis_tvalid==1 && s_axis_tready==1) begin
					throw_length_left <= throw_length_left-1;					
				end

				if (s_axis_tvalid==1 && s_axis_tready==1 && throw_length_left==0)  begin
					state <= ST_IDLE;
					inready <= 0;
				end

			end



		endcase


	end



endmodule

