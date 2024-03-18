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


// `default_nettype none
import kmeansTypes::*;

module fetch_engine
(
    input wire clk,    // Clock
    input wire rst_n,  // Asynchronous reset active low
    input wire                                   start_operator,

    input RuntimeParam 							 rp,
    // TX RD
    output wire  [57:0]                          um_tx_rd_addr,
    output reg   [7:0]                           um_tx_rd_tag,
    output reg                           		 um_tx_rd_valid,
    input  wire                                  um_tx_rd_ready,

    // RX RD
    input  wire [7:0]                             um_rx_rd_tag,
    input  wire [511:0]                           um_rx_data,
    input  wire                                   um_rx_rd_valid,
    output reg									  um_rx_rd_ready,

    //output to kmeans module
    output wire [511:0] 						tuple_cl,
    output wire 								tuple_cl_valid,
    output wire 								tuple_cl_last,
    input wire 									tuple_cl_ready,

    output wire [511:0]							centroid_cl,
    output wire 								centroid_cl_valid,
    output wire 								centroid_cl_last,
    input wire 									centroid_cl_ready,


    output reg [1:0][31:0]						fetch_engine_debug_cnt

);

	RuntimeParam 						rp_reg;
	reg 								rst_n_reg;	
	reg 								start_operator_reg;

	wire  	req_sent, req_received;
	reg 	potential_overflow;
	reg [31:0] inflight_cnt;

	wire 								rx_fifo_valid;
	wire [511:0]				 		rx_fifo_dout;
	wire								rx_fifo_re;
	wire 								rx_fifo_full;
	wire 								rx_fifo_almostfull;
	wire [BUFFER_DEPTH_BITS-1:0]		rx_fifo_count;

	always @ (posedge clk) begin
		rp_reg <= rp;
		rst_n_reg <= rst_n;
		start_operator_reg <= start_operator;
	end


	//generate the read address
	rd_addr_gen rd_addr_gen (
		.clk               (clk),
		.rst_n         	   (rst_n_reg),
		.start_operator    (start_operator_reg),
		.um_tx_rd_addr     (um_tx_rd_addr),
		.um_tx_rd_tag      (um_tx_rd_tag),
		.um_tx_rd_valid    (um_tx_rd_valid),
		.um_tx_rd_ready    (um_tx_rd_ready),
		.potential_overflow(potential_overflow),
		.rp                (rp_reg));

	quick_fifo #(.FIFO_WIDTH(512),
	.FIFO_DEPTH_BITS(BUFFER_DEPTH_BITS))
	rx_fifo
	(
		.clk       (clk),
		.reset_n   (rst_n_reg),
		.we        (um_rx_rd_ready & um_rx_rd_valid),
		.din       (um_rx_data),
		.re        (rx_fifo_re),
		.valid     (rx_fifo_valid),
		.dout      (rx_fifo_dout),
		.count     (rx_fifo_count),
		.empty     (),
		.full      (rx_fifo_full),
		.almostfull(rx_fifo_almostfull)	);

	assign um_rx_rd_ready = ~rx_fifo_full;

	fetch_engine_output_lane output_lane(
		.clk              (clk),
		.rst_n            (rst_n_reg),
		.start_operator   (start_operator_reg),
		.rx_fifo_valid    (rx_fifo_valid),
		.rx_fifo_dout     (rx_fifo_dout),
		.rx_fifo_re       (rx_fifo_re),
		.rp               (rp_reg),
		.tuple_cl         (tuple_cl),
		.tuple_cl_valid   (tuple_cl_valid),
		.tuple_cl_last    (tuple_cl_last),
		.tuple_cl_ready   (tuple_cl_ready),
		.centroid_cl      (centroid_cl),
		.centroid_cl_valid(centroid_cl_valid),
		.centroid_cl_last (centroid_cl_last),
		.centroid_cl_ready(centroid_cl_ready)
		);


	//flow control to avoid overflow
	assign req_sent = um_tx_rd_ready & um_tx_rd_valid;
	assign req_received = um_rx_rd_ready & um_rx_rd_valid;

	always @ (posedge clk) begin
		if(~rst_n_reg ) begin
			inflight_cnt <= '0;
			potential_overflow <= '0;
		end
		else begin 
			if(req_sent & !req_received) begin
				inflight_cnt <= inflight_cnt + 1'b1;
			end
			else if((!req_sent & req_received) & (inflight_cnt>0)) begin
				inflight_cnt <= inflight_cnt - 1'b1;
			end

			potential_overflow <= ((inflight_cnt + rx_fifo_count )< 2**(BUFFER_DEPTH_BITS-1)) ? 0: 1;
		end
	end


	//debug counters
	reg [31:0]	tuple_cl_cnt, centroid_cl_cnt;
	reg [31:0] 	cl_rec_cnt, cl_req_cnt;

	always @ (posedge clk) begin
		if(start_operator_reg ) begin
			tuple_cl_cnt <= '0;
			centroid_cl_cnt <= '0;
			cl_req_cnt <= '0;
			cl_rec_cnt <= '0;
		end
		else begin
			if(tuple_cl_valid & tuple_cl_ready) begin
				tuple_cl_cnt <= tuple_cl_cnt + 1'b1;
			end
			if(centroid_cl_valid & centroid_cl_ready) begin
				centroid_cl_cnt <= centroid_cl_cnt + 1'b1;
			end
			if(um_rx_rd_ready & um_rx_rd_valid) begin
				cl_rec_cnt <= cl_rec_cnt + 1'b1;
			end
			if(um_tx_rd_valid & um_tx_rd_ready) begin
				cl_req_cnt <= cl_req_cnt + 1'b1;
			end
		end
	end

	always @ (posedge clk) begin
		fetch_engine_debug_cnt[0] <= tuple_cl_cnt;
		fetch_engine_debug_cnt[1] <= centroid_cl_cnt;
	end





endmodule
// `default_nettype wire
