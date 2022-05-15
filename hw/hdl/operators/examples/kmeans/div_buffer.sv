`default_nettype none
import kmeansTypes::*;

module div_buffer 
(
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	//interface with divider
	input wire [MAX_DIM_WIDTH-1:0] 		div_dout,
	input wire 							div_dout_valid,
	input wire 							div_dout_last_dim,
	input wire 							div_dout_last,
	

	//input wire 							update_ready, //assume update and wr_engine will not be over flowed 
	output reg [MAX_DIM_WIDTH-1:0] 	update,
	output reg 						update_valid,
	output reg 						update_last,
	output reg 						update_last_dim
);

	logic div_buffer_re, div_buffer_valid;
	logic div_buffer_we; 
	logic [MAX_DIM_WIDTH+1:0] div_buffer_data_din;
	logic [MAX_DIM_WIDTH+1:0] div_buffer_data_dout;
	reg	  rst_n_reg;

	always @ (posedge clk) begin
		rst_n_reg <= rst_n;
		if(~rst_n_reg) begin
			update_valid <= 1'b0;
			update_last <= 1'b0;
			update_last_dim <= 1'b0;
		end
		else begin
			update <= div_buffer_data_dout[MAX_DIM_WIDTH-1:0];
			update_last <= div_buffer_data_dout[MAX_DIM_WIDTH];
			update_last_dim <= div_buffer_data_dout[MAX_DIM_WIDTH+1];
			update_valid <= /*update_ready &*/ div_buffer_valid;
		end
	end




	quick_fifo #(.FIFO_WIDTH(MAX_DIM_WIDTH+2), .FIFO_DEPTH_BITS(9))
	div_buffer
	(	
	.clk,
	.reset_n(rst_n_reg),
	.we(div_buffer_we),
	.din(div_buffer_data_din),
	.re(div_buffer_re),
	.valid(div_buffer_valid),
	.dout(div_buffer_data_dout),
	.count(),
	.empty(),
	.full(),
	.almostfull()
	); 

	assign div_buffer_we = div_dout_valid ;
	assign div_buffer_data_din = {div_dout_last_dim,div_dout_last,div_dout};
	assign div_buffer_re = /*update_ready &*/ div_buffer_valid;

endmodule
`default_nettype wire
