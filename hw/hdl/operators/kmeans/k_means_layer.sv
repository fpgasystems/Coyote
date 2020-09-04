import kmeansTypes::*;

module k_means_layer #(parameter CLUSTER_ID = 0)(
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	input wire [MAX_DEPTH_BITS:0] 			data_dim_minus_1, 
	input wire [NUM_CLUSTER_BITS:0] 		num_cluster_minus_1,


	//interface with previous kmeans layer
    input wire [32-1:0]						centroid_i,
    input wire 								centroid_valid_i,
    input wire 								last_dim_of_one_centroid_i,
    input wire 								last_dim_of_all_centroid_i,

    //interface with next kmeans layer
    output reg [32-1:0]						centroid_o,
    output reg 								centroid_valid_o,
    output reg 								last_dim_of_one_centroid_o,
    output reg 								last_dim_of_all_centroid_o,

    //input interface with previous k-means layer
    input wire [NUM_PIPELINE-1:0][32-1:0]			tuple_i,
    input wire 										tuple_valid_i,
    input wire 										last_dim_of_one_tuple_i,

    //output interface with next kmeans layer
    //tuple bits stream through each layer
    output reg [NUM_PIPELINE-1:0][32-1:0]			tuple_o,
    output wire 									tuple_valid_o,
    output wire 									last_dim_of_one_tuple_o,

    //---------------previous assignment result---//
	input wire [NUM_PIPELINE-1:0]									min_dist_valid_i,
	input wire  [63:0] 												min_dist_i[NUM_PIPELINE-1:0], 
	input wire [NUM_PIPELINE-1:0][NUM_CLUSTER_BITS:0] 				cluster_i, 
	
	//--------------current assignment result--------//
	output wire [NUM_PIPELINE-1:0]									min_dist_valid_o,
	output wire  [63:0] 											min_dist_o[NUM_PIPELINE-1:0],
	output wire [NUM_PIPELINE-1:0][NUM_CLUSTER_BITS:0] 				cluster_o


	
);

reg 							rst_n_reg;


reg [MAX_DEPTH_BITS-1:0] 	raddr;
reg [MAX_DEPTH_BITS-1:0]	waddr;
wire [32-1:0] 				centroid_from_bram;
wire 						write_en;
reg 						enable;
wire 						read_en;

reg [NUM_CLUSTER_BITS:0] 	cluster_cnt;

//stores the centroid chunk
dual_port_ram #(.DATA_WIDTH(32), .ADDR_WIDTH(MAX_DEPTH_BITS))
	processor_mem
	(
	.clk  (clk),
	.we   (write_en),
	.re   (1'b1),
	.raddr(raddr),
	.waddr(waddr),
	.din  (centroid_i),
	.dout (centroid_from_bram)
		);	

//write only when cluster cnt equals
assign write_en = centroid_valid_i & (cluster_cnt == CLUSTER_ID); 
//read only when last bit of number of bank of dimensions
assign read_en = tuple_valid_i ;

//bram read and write address calculation
always_ff @(posedge clk) begin : proc_addr
	rst_n_reg <= rst_n;
	if (~rst_n_reg) begin
		waddr <= '0;
		cluster_cnt <= '0;
		raddr <= '0;
		enable <= 1'b0;
	end
	else begin
		if(centroid_valid_i) begin
			if(last_dim_of_one_centroid_i) begin
				cluster_cnt <= cluster_cnt + 1'b1;
				if(last_dim_of_all_centroid_i) begin
					cluster_cnt <= '0;
				end
			end
		end

		if (write_en) begin
			waddr <= waddr + 1'b1;
			if ( last_dim_of_one_centroid_i) begin
				waddr <= '0;
			end
		end

		if(read_en) begin
			raddr <= raddr + 1'b1;
			if( last_dim_of_one_tuple_i) begin
				raddr <= '0;
			end
		end

		enable <= (CLUSTER_ID <= num_cluster_minus_1);
	end
end

//-----------------------------One cycle later-------------------------------//
//-------------------bram centroid valid one cycle after the read----------------//

reg [NUM_PIPELINE-1:0][32-1:0]				tuple_reg;
reg 										tuple_valid_reg;
reg 										last_dim_of_one_tuple_reg;

always @ (posedge clk) begin

	tuple_reg <= tuple_i;
	tuple_valid_reg <= tuple_valid_i;
	last_dim_of_one_tuple_reg <= last_dim_of_one_tuple_i;

	//register the updated centroid and forward to next layer
	centroid_o <= centroid_i;
	centroid_valid_o <= centroid_valid_i;
	last_dim_of_all_centroid_o <= last_dim_of_all_centroid_i;
	last_dim_of_one_centroid_o <= last_dim_of_one_centroid_i;
end

//forward the tuple bit streams to next layer
assign tuple_o = tuple_reg;
assign tuple_valid_o = tuple_valid_reg;
assign last_dim_of_one_tuple_o = last_dim_of_one_tuple_reg;


//-------------------------One cycle later---------------------------------//
//----------------------register the bram centroid one cycle---------------//
reg [32-1:0] 								centroid_from_bram_reg;
reg [NUM_PIPELINE-1:0][32-1:0]				tuple_reg2;
reg 										tuple_valid_reg2;
reg 										last_dim_of_one_tuple_reg2;
always @ (posedge clk) begin
	if(~rst_n_reg) begin
		tuple_valid_reg2 <= '0;
	end
	else begin
		centroid_from_bram_reg <= centroid_from_bram;


		tuple_reg2 <= tuple_reg;
		tuple_valid_reg2 <= tuple_valid_reg;
		last_dim_of_one_tuple_reg2 <= last_dim_of_one_tuple_reg;
	end
end

genvar i;
generate
	for (i = 0; i < NUM_PIPELINE; i++) begin: PARALLEL_DP
			dist_processor #(.INDEX_PROCESSOR(CLUSTER_ID)) dist_processor
			(
				.clk               (clk),
				.rst_n             (rst_n),
				.enable            (enable),
				.data_valid_i      (tuple_valid_reg2),
				.data_i            (tuple_reg2[i]),
				.data_last_dim     (last_dim_of_one_tuple_reg2),
				.centroid_i        (centroid_from_bram_reg),
				.min_dist_valid_i  (min_dist_valid_i[i]),
				.min_dist_i        (min_dist_i[i]),
				.cluster_i         (cluster_i[i]),
				.min_dist_valid_o  (min_dist_valid_o[i]),
				.min_dist_o        (min_dist_o[i]),
				.cluster_o         (cluster_o[i])
			);
	end
endgenerate





endmodule // k_means_layer