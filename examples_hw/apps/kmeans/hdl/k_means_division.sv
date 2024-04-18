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

`default_nettype none
import kmeansTypes::*;

module k_means_division 
(
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	input wire 						start_operator,

	input wire [63:0] 				div_sum,
	input wire [63:0] 				div_count,
	input wire 						div_valid,
	input wire 						div_last_dim,
	input wire 						div_last,
	
	output wire 					div_dout_last_dim,
	output wire 					div_dout_last,
	output reg [MAX_DIM_WIDTH-1:0] 	div_dout, //the center data for updating the cluster in dist processors
	output wire 					div_dout_valid, //when high, means up_center_o valids, goes to div_dout stage in the higher hierarchy
	
	//debug counter
	output reg [31:0]				k_means_division_debug_cnt
);

	localparam LPM_WIDTHN = 40;
	localparam LPM_PIPELINE = 40;

	reg 			rst_delay_n;
	wire [LPM_WIDTHN-1:0] 	divider_quotient;
	logic [63:0] 	divider_denummer;
	//shift registers
	reg[LPM_PIPELINE:0] 		div_valid_sr;
	reg[LPM_PIPELINE:0] 		div_last_dim_sr;
	reg[LPM_PIPELINE:0] 		div_last_sr;



	always_ff @(posedge clk)begin
		rst_delay_n <= rst_n;
	end


	always_comb begin : proc_denumer
		if(div_valid && (div_count==0)) begin
			divider_denummer = 1;
		end
		else begin
			divider_denummer = div_count;
		end
	end

/*
	lpm_divide #(
	.lpm_widthn(LPM_WIDTHN), // 40
	.lpm_widthd(32),
	.lpm_pipeline(LPM_PIPELINE), // 40
	.lpm_nrepresentation("UNSIGNED"),
	.lpm_drepresentation("UNSIGNED")
	// .LPM_NREPRESENTATION("unsigned"),
	// .LPM_DREPRESENTATION("unsigned")
	)
	divider
	(
	.clock(clk),
	.clken(1'b1),
	.aclr(1'b0),
	.quotient(divider_quotient),
	.numer(div_sum[LPM_WIDTHN-1:0]),
	.denom(divider_denummer[31:0]),
	.remain()
		);
*/
    logic [71:0] tmp;
	div_gen_0 inst_div_gen (
	   .aclk(clk),
	   .s_axis_divisor_tvalid(1'b1),
	   .s_axis_divisor_tdata(divider_denummer[31:0]),
	   .s_axis_dividend_tvalid(1'b1),
	   .s_axis_dividend_tdata(div_sum[LPM_WIDTHN-1:0]),
	   .m_axis_dout_tvalid(),
       .m_axis_dout_tdata(tmp)
	);
    assign divider_quotient = tmp[32+:40];

	assign div_dout_valid = div_valid_sr[0];
	assign div_dout_last_dim = div_last_dim_sr[0];
	assign div_dout_last = div_last_sr[0];
	always @(posedge clk) begin
		div_dout <= divider_quotient[31:0];
		if (~rst_delay_n) begin
			div_valid_sr <= 0;
			div_last_dim_sr <= 0;
			div_last_sr <= 0;
		end
		else begin
			div_valid_sr <= {div_valid, div_valid_sr[LPM_PIPELINE:1]};
			div_last_dim_sr <= {div_last_dim, div_last_dim_sr[LPM_PIPELINE:1]};
			div_last_sr <= {div_last, div_last_sr[LPM_PIPELINE:1]};
		end
	end	



	//debug counters
	reg [31:0] division_output_cnt;
	always @ (posedge clk) begin
		if(start_operator) begin
			division_output_cnt <= '0;
		end
		else if(div_dout_valid) begin
			division_output_cnt <= division_output_cnt + 1'b1;
		end

		k_means_division_debug_cnt <= division_output_cnt;
	end




endmodule
`default_nettype wire
