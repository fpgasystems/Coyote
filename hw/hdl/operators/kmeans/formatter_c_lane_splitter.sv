import kmeansTypes::*;

//split the 512 bit cacheline to chunks
module c_lane_splitter (
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	input wire [NUM_CLUSTER_BITS:0] 		num_cluster,// the actual number of cluster that will be used 
	input wire [MAX_DEPTH_BITS:0] 			data_dim, //input the actual dimension of the data

	//interface to fetch engine
	input wire [511:0]						centroid_cl,
    input wire 								centroid_cl_valid,

    output wire 							c_lane_ready,

    //interface to next module
    // input wire 								next_module_ready,

    output reg [32-1:0]						centroid, //32b*NUM_BANK
    output reg 								centroid_valid,
    output reg 								last_dim_of_all_centroid,
    output reg 								last_dim_of_one_centroid
	
);


wire 								c_fifo_valid;
wire [511 : 0]				 		c_fifo_dout;
wire								c_fifo_re;
wire 								c_fifo_full;
wire 								c_fifo_almostfull;

reg [31:0] 							sel_cnt;
reg [31:0]							sent_cnt;
reg [16:0]							dim_cnt;

wire is_last_dim_of_all, is_cl_last, is_last_dim_of_one;

reg [31:0] 							total_send_amount;


localparam SPLIT_RATIO = 16; //number of splits of each cacheline

//buffer the initial centroid cacheline
quick_fifo #(.FIFO_WIDTH(512),
	.FIFO_DEPTH_BITS(BUFFER_DEPTH_BITS-3),
    .FIFO_ALMOSTFULL_THRESHOLD(2**(BUFFER_DEPTH_BITS-3) -8))
	c_fifo
	(
		.clk       (clk),
		.reset_n   (rst_n),
		.we        (~c_fifo_full & centroid_cl_valid),
		.din       (centroid_cl),
		.re        (c_fifo_re),
		.valid     (c_fifo_valid),
		.dout      (c_fifo_dout),
		.count     (),
		.empty     (),
		.full      (c_fifo_full),
		.almostfull(c_fifo_almostfull)	);

//last of the feature of all the initial centroids
assign is_last_dim_of_all = (sent_cnt == (total_send_amount-1)) &  c_fifo_valid;
//last chunk of the cacheline
assign is_cl_last = (sel_cnt == SPLIT_RATIO -1) & c_fifo_valid;
assign is_last_dim_of_one = (dim_cnt == data_dim-1) & c_fifo_valid;

assign c_lane_ready = ~c_fifo_almostfull;
assign c_fifo_re = is_last_dim_of_all | is_cl_last;


always @ (posedge clk) begin
	if(~rst_n) begin
		sel_cnt <= '0;
		sent_cnt <= '0;
		dim_cnt <= '0;
		total_send_amount <= '0;
	end
	else begin
		total_send_amount <= num_cluster*data_dim; 

		//counter to set the last bit
		if(is_last_dim_of_all ) begin
			sent_cnt <= '0;
		end
		else if( c_fifo_valid) begin
			sent_cnt <= sent_cnt + 1'b1;
		end

		//counter to select portion of the cacheline 
		if(is_cl_last | is_last_dim_of_all) begin
			sel_cnt <= '0;
		end
		else if( c_fifo_valid) begin
			sel_cnt <= sel_cnt + 1'b1;
		end

		//counter to set the last chunk of one centroid flag
		if(is_last_dim_of_one) begin
			dim_cnt <= '0;
		end
		else if(c_fifo_valid) begin
			dim_cnt <= dim_cnt + 1'b1;
		end

	end
end


always @ (posedge clk) begin
	if(~rst_n) begin
		centroid_valid <= 1'b0;
	end
	else begin
		centroid_valid <= c_fifo_valid;
		centroid <= c_fifo_dout[(32)*sel_cnt +: (32)];
		last_dim_of_all_centroid <= is_last_dim_of_all;
		last_dim_of_one_centroid <= is_last_dim_of_one;
	end
end

//////////////////////////////////////////////////////////////////////////////////////////////////////
//---------------------------------log file print--------------------------------------------------//
////////////////////////////////////////////////////////////////////////////////////////////////////
`define LOG_NULL
`ifdef LOG_FILE
	int file;
	reg file_finished;
	initial begin
		file = $fopen("/home/harpdev/doppiodb/fpga/operators/k_means_v2/sim_log/formatter_c_lane.txt","w");
		if(file) 
			$display("formatter_c_lane file open successfully\n");
		else 
			$display("Failed to open formatter_c_lane file\n");	
	end

	always @ (posedge clk) begin
		if(~rst_n) begin
			file_finished <= 1'b0;
		end
		else begin
			if(centroid_valid) begin
				
				$fwrite(file,"%d ", centroid);
				
				if(last_dim_of_one_centroid) begin
					$fwrite(file,"\n");
				end
				if(last_dim_of_all_centroid) begin
					$fwrite(file,"\n\n");
				end
			end

		end
	end
`endif
////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////


endmodule