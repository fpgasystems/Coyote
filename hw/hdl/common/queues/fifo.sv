`timescale 1ns / 1ps

import lynxTypes::*;

module fifo #(
	parameter integer DATA_BITS = 64,
	parameter integer FIFO_SIZE = 8
) (
	input  logic 					aclk,
	input  logic 					aresetn,

	input  logic 					rd,
	input  logic 					wr,

	output logic					ready_rd,
	output logic 					ready_wr,

	input  logic [DATA_BITS-1:0] 	data_in,
	output logic [DATA_BITS-1:0]	data_out
);

// Constants
localparam integer PNTR_BITS = $clog2(FIFO_SIZE);

// Internal registers
logic [PNTR_BITS-1:0] wr_pntr;
logic [PNTR_BITS-1:0] rd_pntr;
logic [PNTR_BITS:0] n_entries;

logic isFull;
logic isEmpty;

logic [FIFO_SIZE-1:0][DATA_BITS-1:0] data;

// FIFO flags
assign isFull = (n_entries == FIFO_SIZE);
assign isEmpty = (n_entries == 0);

genvar i;

always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		 n_entries <= 0;
		 data <= 0;
	end else begin
		 // Number of entries
		 if (rd && !isEmpty && (!wr || isFull))
		 	n_entries <= n_entries - 1;
		 else if (wr && !isFull && (!rd || isEmpty))
		 	n_entries <= n_entries + 1;
		 // Data
		 if(wr && !isFull)
		 	data[wr_pntr] <= data_in;
	end
end

always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		rd_pntr <= 0;
		wr_pntr <= 0;
	end else begin
		// Write pointer
		if(wr && !isFull) begin
			if(wr_pntr == (FIFO_SIZE-1))
				wr_pntr <= 0;
			else
				wr_pntr <= wr_pntr + 1;
		end
		// Read pointer
		if(rd && !isEmpty) begin
			if(rd_pntr == (FIFO_SIZE-1))
				rd_pntr <= 0;
			else 
				rd_pntr <= rd_pntr + 1;
		end
	end
end

// Output
assign ready_rd = ~isEmpty;
assign ready_wr = ~isFull;

assign data_out = data[rd_pntr];

endmodule // fifo