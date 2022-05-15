
import kmeansTypes::*;

module Formatter (
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	input wire [NUM_CLUSTER_BITS:0] 		num_cluster,// the actual number of cluster that will be used 
	input wire [MAX_DEPTH_BITS:0] 			data_dim, //input the actual dimension of the data

	//interface to fetch engine
    input wire [511:0] 						tuple_cl,
    input wire 								tuple_cl_valid,

    input wire [511:0]						centroid_cl, //not in bit-weaving format
    input wire 								centroid_cl_valid,

    output wire								centroid_cl_ready,

    //interface to pipeline
    output wire [32-1:0]						centroid,
    output wire 								centroid_valid,
	output wire 								last_dim_of_all_centroid,
    output wire  								last_dim_of_one_centroid,

    //interface to pipelines
    output reg [NUM_PIPELINE-1:0][32-1:0]			tuple,
    output reg 										tuple_valid,
	output reg 										last_dim_of_one_tuple,

	//debug counters
	output wire [2:0] [31:0]				formatter_debug_cnt	
	
);


reg 	rst_n_reg;
wire 	c_lane_ready;

always @ (posedge clk) begin
	rst_n_reg <= rst_n;
end

assign centroid_cl_ready = c_lane_ready;

//--------------------split the centroid cache line---------------------//


c_lane_splitter c_lane_splitter
(
	.clk                 (clk),
	.rst_n               (rst_n_reg),
	.num_cluster         (num_cluster),
	.data_dim            (data_dim),
	.centroid_cl         (centroid_cl),
	.centroid_cl_valid   (centroid_cl_valid),
	.c_lane_ready        (c_lane_ready),
	.centroid      		 (centroid),
	.centroid_valid 	 (centroid_valid),
	.last_dim_of_all_centroid(last_dim_of_all_centroid),
	.last_dim_of_one_centroid(last_dim_of_one_centroid)	);


//----------------------distribute the tuples----------------------//

reg [MAX_DEPTH_BITS:0] data_dim_cnt;
reg [NUM_PIPELINE_BITS:0] pipe_index;

always @ (posedge clk) begin
	if(~rst_n_reg) begin
		data_dim_cnt <= '0;
		pipe_index <= '0;
	end
	else begin
		if(tuple_cl_valid) begin
			data_dim_cnt <= data_dim_cnt + 16; //assume the data dimension is multiple of 16
			if(data_dim_cnt + 16 >= data_dim) begin
				data_dim_cnt <= '0;
				pipe_index <= pipe_index + 1'b1;
				if(pipe_index == NUM_PIPELINE-1) begin
					pipe_index <= '0;
				end
			end
		end
	end
end

wire [NUM_PIPELINE-1:0] tuple_fifo_we, tuple_fifo_re, tuple_fifo_valid, tuple_fifo_empty, tuple_fifo_full, tuple_almost_full;
wire [NUM_PIPELINE-1:0][512-1:0] tuple_fifo_dout, tuple_fifo_din;
reg [NUM_PIPELINE_BITS:0] multiplex_cnt;
reg [MAX_DEPTH_BITS:0] sent_dim_cnt;

generate
	for (genvar n = 0; n < NUM_PIPELINE; n++) begin: pipe_buffer

		assign tuple_fifo_we[n] = tuple_cl_valid & (pipe_index == n);
		assign tuple_fifo_din[n] = tuple_cl;
		assign tuple_fifo_re[n] = (&tuple_fifo_valid) & (multiplex_cnt == 15);

		quick_fifo #(.FIFO_WIDTH(512), .FIFO_DEPTH_BITS(BUFFER_DEPTH_BITS))
		tuple_fifo
		(	
		.clk,
		.reset_n(rst_n_reg),
		.we(tuple_fifo_we[n]),
		.din(tuple_fifo_din[n]),
		.re(tuple_fifo_re[n]),
		.valid(tuple_fifo_valid[n]),
		.dout(tuple_fifo_dout[n]), //contains the data and the terminate bit
		.count(),
		.empty(tuple_fifo_empty[n]),
		.full(tuple_fifo_full[n]),
		.almostfull(tuple_almost_full[n])
			); 

	end
endgenerate
	
always @ (posedge clk) begin
	if(~rst_n_reg) begin
		multiplex_cnt <= '0;
		sent_dim_cnt <= '0;
	end
	else begin
		if(&tuple_fifo_valid) begin
			multiplex_cnt <= multiplex_cnt + 1'b1;
			sent_dim_cnt <= sent_dim_cnt + 1'b1;
			if(multiplex_cnt == 15) begin
				multiplex_cnt <= '0;
			end
			if(sent_dim_cnt == (data_dim -1)) begin
				sent_dim_cnt <= '0;
			end
		end
	end
end

//-----------------------output path----------------//
generate
	for (genvar i = 0; i < NUM_PIPELINE; i++) begin: formatter_output
		always @ (posedge clk) begin
			tuple[i] <= tuple_fifo_dout[i][multiplex_cnt*MAX_DIM_WIDTH +: MAX_DIM_WIDTH];
		end
	end
endgenerate

always @ (posedge clk) begin
	tuple_valid <= &tuple_fifo_valid;
	last_dim_of_one_tuple <= (&tuple_fifo_valid) & (sent_dim_cnt == (data_dim -1));
end


endmodule
