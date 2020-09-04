
import kmeansTypes::*;


module k_means_accumulation #(parameter PIPELINE_INDEX=0) ( 
	input clk,    // Clock
	input wire rst_n,  
	
	//pipeline processor interface
	input logic 									data_valid_accu_i,
	input logic [32-1:0]							data_accu_i,

	input logic 									min_dist_accu_valid_i,
	input logic [63:0]								min_dist_accu_i,
	input logic [NUM_CLUSTER_BITS:0]				cluster_accu_i,

	input logic 									terminate_accu_i,

	//runtime configration parameters
	input logic [MAX_DEPTH_BITS:0] 					data_dim_accu_i, //input the actual dimension of the data
	input logic [NUM_CLUSTER_BITS:0] 				num_cluster_accu_i, //input the actual number of cluster


	//aggregator interface
	input logic 									agg_ready_i,
	output logic 									accu_finish_o,
	output logic [63:0] 							agg_data_o,
	output logic 									agg_valid_o

	// output wire [NUM_BANK-1:0][MAX_DIM_WIDTH-1:0]	debug_output,
	// output wire 									debug_output_valid

	//output reg [7:0][31:0] 							accu_debug_cnt

);

	//dual port BRAM signal
	logic [64-1:0] bram_din, bram_dout;
	logic [NUM_CLUSTER_BITS+MAX_DEPTH_BITS-1:0] bram_addr_re, bram_addr_wr;
	logic bram_we;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////
//----------------------------------------Accumulation-------------------------------------------------------//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////First cycle////////////////////////////////////////////////

//-------------------------input register----------------------------------//
	//runtime param reg
	logic [MAX_DEPTH_BITS:0] data_dim_accu_DP;
	logic [NUM_CLUSTER_BITS:0] num_cluster_accu_DP;

	//input reg
	logic rst_n_reg, min_dist_accu_valid_DP;
	logic [63:0]min_dist_accu_DP;
	logic [NUM_CLUSTER_BITS:0]cluster_accu_DP;
	// logic [4:0] numBits_minus_1_DP;

	//register input signal
	always_ff @(posedge clk) begin : proc_rst_delay
		rst_n_reg <= rst_n;
		min_dist_accu_DP <= min_dist_accu_i;
		cluster_accu_DP <= cluster_accu_i;
		data_dim_accu_DP <= data_dim_accu_i;
		num_cluster_accu_DP <= num_cluster_accu_i;
		// numBits_minus_1_DP <= numBits_minus_1;
		if (~rst_n_reg) begin
			min_dist_accu_valid_DP <= 1'b0;
		end
		else begin
			min_dist_accu_valid_DP <= min_dist_accu_valid_i;
		end
	end


////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////Second Cycle//////////////////////////////////////////////

//----------------------Cluster FIFO and DATA FIFO------------------//

	//FIFO signal
	logic data_fifo_we, data_fifo_re, data_fifo_valid,data_fifo_empty, data_fifo_almostfull, data_fifo_full;
	logic [MAX_DIM_WIDTH-1:0] data_fifo_dout, data_fifo_din;

	//cluster fifo signals
	logic cluster_fifo_we, cluster_fifo_re, cluster_fifo_valid, cluster_fifo_empty, cluster_fifo_almostfull, cluster_fifo_full;
	logic [NUM_CLUSTER_BITS:0] cluster_fifo_dout;
	reg [MAX_DEPTH_BITS:0] dim_cnt_accu;

	quick_fifo #(.FIFO_WIDTH(MAX_DIM_WIDTH), .FIFO_DEPTH_BITS(BUFFER_DEPTH_BITS), .FIFO_ALMOSTFULL_THRESHOLD(2**(BUFFER_DEPTH_BITS-1)))
	DATA_FIFO
	(
	.clk(clk),
	.reset_n(rst_n_reg),
	.we(data_fifo_we),
	.din(data_fifo_din),
	.re(data_fifo_re),
	.valid(data_fifo_valid),
	.dout(data_fifo_dout),
	.count(),
	.empty(data_fifo_empty),
	.full(data_fifo_full),
	.almostfull(data_fifo_almostfull)
		);



	assign data_fifo_din = data_accu_i;
	assign data_fifo_we = data_valid_accu_i & ~data_fifo_full ; //write in when not update, data valid 
	 
	quick_fifo #(.FIFO_WIDTH(NUM_CLUSTER_BITS+1), .FIFO_DEPTH_BITS(BUFFER_DEPTH_BITS), .FIFO_ALMOSTFULL_THRESHOLD(2**(BUFFER_DEPTH_BITS-1)))
	CLUSTER_FIFO
	(
	.clk       (clk),
	.reset_n   (rst_n_reg),
	.we        (cluster_fifo_we),
	.din       (cluster_accu_DP),
	.re        (cluster_fifo_re),
	.valid     (cluster_fifo_valid),
	.dout      (cluster_fifo_dout),
	.count     (),
	.empty     (cluster_fifo_empty),
	.full      (cluster_fifo_full),
	.almostfull(cluster_fifo_almostfull)	);



	assign cluster_fifo_we = min_dist_accu_valid_DP & ~cluster_fifo_full;
	assign cluster_fifo_re = data_fifo_valid & cluster_fifo_valid & (dim_cnt_accu ==data_dim_accu_DP -1 ) ;

	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			dim_cnt_accu <= '0; 
		end
		else begin
			if(data_fifo_valid & cluster_fifo_valid) begin
				dim_cnt_accu <= dim_cnt_accu + 1'b1;
				if(dim_cnt_accu + 1'b1 == data_dim_accu_DP ) begin
					dim_cnt_accu <= '0;
				end
			end
		end
	end

	//---------------------------accu counter and sse----------------------------------//


	//accumulation counter signals
	logic [NUM_CLUSTER-1:0][63:0] accu_counter;
	logic accu_counter_clr;

	//signals for accumulate the square error
	logic  [63:0] sse;
	logic sse_clr;

	//count the number of sample in each cluster
	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			accu_counter <= '0;
		end
		else begin
			if(accu_counter_clr) begin
				accu_counter <= '0;
			end
			else if(cluster_fifo_re) begin
				accu_counter[cluster_fifo_dout] <= accu_counter[cluster_fifo_dout] + 1'b1;
			end
		end
	end

	//aggregate the sse
	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			sse <= '0;
		end
		else begin
			if(sse_clr) begin
				sse <= '0;
			end
			else if(min_dist_accu_valid_DP) begin
				sse <= sse + min_dist_accu_DP;
			end
		end
	end


	////////////////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////Third cycle//////////////////////////////////////////////////////

	//-------------------------------Accu read addr generation---------------------------------//
	reg [NUM_CLUSTER_BITS+MAX_DEPTH_BITS-1:0] re_addr_accu;
	reg re_addr_accu_valid;
	always @ (posedge clk ) begin
		if(~rst_n_reg) begin
			re_addr_accu <= '0;
			re_addr_accu_valid <= 1'b0;
		end
		else begin 
			re_addr_accu_valid <= data_fifo_valid & cluster_fifo_valid;
			re_addr_accu <=  (cluster_fifo_dout << (MAX_DEPTH_BITS)) + dim_cnt_accu;
		end
	end


	////////////////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////Fourth cycle//////////////////////////////////////////////////////

	//------------------------read the data from bram need one cycle-------------------//
	//---------------------------register the wr addr-------------------------------//
	reg [NUM_CLUSTER_BITS+MAX_DEPTH_BITS-1:0] wr_addr_accu_reg;
	reg re_addr_accu_valid_reg;

	always @ (posedge clk) begin
		re_addr_accu_valid_reg <= re_addr_accu_valid;
		wr_addr_accu_reg <= re_addr_accu;
	end	

	assign data_fifo_re = re_addr_accu_valid_reg;

	////////////////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////Fifth cycle//////////////////////////////////////////////////////

	//----------------------------accumulation-------------------------------------//
	//---------------------------register the wr addr accu and wr_en---------------//

	wire [63:0]  add_operand;
	reg [64-1:0] add_result;
	reg [NUM_CLUSTER_BITS+MAX_DEPTH_BITS-1:0] wr_addr_accu_reg2;
	reg wr_en_accu;

	assign add_operand = {32'b0, data_fifo_dout};

	always @ (posedge clk) begin
		add_result <= add_operand + bram_dout;
	end


	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			wr_en_accu <= 1'b0;
		end
		else begin
			wr_addr_accu_reg2 <= wr_addr_accu_reg;
			wr_en_accu <= re_addr_accu_valid_reg;
		end
	end


///////////////////////////////////////////////////////////////////////////////////////////////////////////////
//----------------------------------------Aggregation-------------------------------------------------------//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////

	//-------------------------------check condition to go to aggregation stage-------------------------//	
	reg terminate_accu_reg, goto_agg, agg_ready_reg;
	//terminate flag
	always @ (posedge clk) begin

		if(~rst_n_reg) begin
			terminate_accu_reg <= 0;
			agg_ready_reg <= 1'b0;
		end
		else begin 
			goto_agg <= 1'b0;
			if(terminate_accu_reg & data_fifo_empty & cluster_fifo_empty) begin
				terminate_accu_reg <= 0;
				goto_agg <= 1'b1;
			end
			else if(terminate_accu_i) begin
				terminate_accu_reg <= terminate_accu_i;
			end

			agg_ready_reg <= agg_ready_i;
		end
	end

 	//-------------------FSM to control the sending sequences of the data---------------------------------//
 	reg accu_finish, is_agg_data_re, is_agg;
	reg [MAX_DEPTH_BITS:0] dim_cnt_agg;
	reg [NUM_CLUSTER_BITS:0] cluster_cnt_agg;
	reg [NUM_CLUSTER_BITS+MAX_DEPTH_BITS-1:0] re_addr_agg, wr_addr_agg;

	typedef enum reg [2:0]{AGG_IDLE, WAIT_AGG, AGG_DATA, WAIT_ONE_CYCLE, WAIT_SECOND_CYCLE,AGG_CLUSTER, AGG_SSE, TERMINATE} agg_state;

	agg_state state;

	always @ (posedge clk) begin

		if(~rst_n_reg) begin
			state <= AGG_IDLE;
			dim_cnt_agg <= '0;
			cluster_cnt_agg <= '0;
			re_addr_agg <= '0;
			wr_addr_agg <= '0;
		end
		else begin
			accu_finish <= 1'b0;
			accu_counter_clr <= 1'b0;

			is_agg_data_re <= 1'b0;
			is_agg <= 1'b0;

			sse_clr <= 1'b0;

			wr_addr_agg <= re_addr_agg;

			case (state)

				AGG_IDLE:begin
					if(goto_agg == 1) begin
						state <= WAIT_AGG;
					end
				end

				WAIT_AGG: begin
					accu_finish <= 1'b1;
					if(agg_ready_reg) begin
						state <= AGG_CLUSTER;
						is_agg <= 1'b1;
					end
				end

				//upon the start of aggregation state, give aggregation_valid signal and increment the addr_offset 
				AGG_DATA: begin
					is_agg_data_re <= 1;
					is_agg <= 1'b1;
					dim_cnt_agg <= dim_cnt_agg + 1'b1;
					if(dim_cnt_agg == data_dim_accu_DP -1 ) begin
						dim_cnt_agg <= '0;
						cluster_cnt_agg <= cluster_cnt_agg + 1'b1;
						if(cluster_cnt_agg == num_cluster_accu_DP-1) begin
							cluster_cnt_agg <= '0;
							state <= WAIT_ONE_CYCLE;
						end
					end

					re_addr_agg <= (cluster_cnt_agg << MAX_DEPTH_BITS) + (dim_cnt_agg);

				end

				//wait one cycle to wait the data is read from memory
				WAIT_ONE_CYCLE: begin 
					is_agg <= 1'b1;
					state <= WAIT_SECOND_CYCLE;
					re_addr_agg <= '0;
				end

				WAIT_SECOND_CYCLE: begin
					state <= AGG_SSE;
					is_agg <= 1'b1;
				end

				AGG_CLUSTER: begin
					is_agg <= 1'b1;
					cluster_cnt_agg <= cluster_cnt_agg + 1'b1;
					if(cluster_cnt_agg == num_cluster_accu_DP-1) begin
						cluster_cnt_agg <= '0;
						state <= AGG_DATA;
					end
				end

				AGG_SSE: begin
					is_agg <= 1'b1;
					state <= TERMINATE; 
				end

				TERMINATE:begin 
					is_agg <= 1'b1;
					state <= AGG_IDLE;
					accu_counter_clr <= 1'b1;
					sse_clr <= 1'b1;
				end
			endcase
		end
	end
	

	//----------------ouput data path-----------------------//
	reg agg_data_re_valid;

	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			agg_valid_o <= 1'b0;
			agg_data_re_valid <= 1'b0;
		end
		else begin
			agg_data_re_valid <= is_agg_data_re; //takes one cycle to read from bram

			agg_data_o <= agg_data_re_valid ? bram_dout : (state == AGG_CLUSTER? accu_counter[cluster_cnt_agg] : (state == AGG_SSE? sse : '0 ) );
			agg_valid_o <= agg_data_re_valid | (state == AGG_CLUSTER) | (state == AGG_SSE);

		end
	end

	assign accu_finish_o = accu_finish;

	

//-------------------------------ACCU BRAM ---------------------------------------//



	dual_port_ram #(.DATA_WIDTH(64), .ADDR_WIDTH(MAX_DEPTH_BITS+NUM_CLUSTER_BITS))
	accu_ram
	(
	.clk  (clk),
	.we   (bram_we),
	.re   (1'b1),
	.raddr(bram_addr_re),
	.waddr(bram_addr_wr),
	.din  (bram_din),
	.dout (bram_dout)
		);


	assign bram_addr_wr = is_agg ? wr_addr_agg : wr_addr_accu_reg2;
	assign bram_din = is_agg? '0: add_result;
	assign bram_addr_re = is_agg? re_addr_agg : re_addr_accu;
	assign bram_we = wr_en_accu | (agg_data_re_valid );


	//------------------------debug counters----------------------------------//

	// reg [31:0] accu_ram_we_cnt;
	// // reg [31:0][7:0] accu_bram_data;
	// reg [31:0] bram_accu_cycle;
	// reg [31:0] back_pressure_cnt;
	// reg [15:0] goto_agg_cnt;
	// reg [15:0] cross_state_cnt;
	// // reg [15:0] accu_bram_cnt_indx;
	// reg [15:0] addr_offset_overflow_cnt;
	// reg [15:0] rdw_check;

	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			// accu_ram_we_cnt <= '0;
			// bram_accu_cycle <= '0;
			// back_pressure_cnt <= '0;
			// goto_agg_cnt <= '0;
			// cross_state_cnt <= '0;
			// accu_bram_cnt_indx <= '0;
			// addr_offset_overflow_cnt <= '0;
			// rdw_check <= '0;
		end
		else begin
			// if(bram_we_accu) begin
			// 	accu_ram_we_cnt <= accu_ram_we_cnt + 1'b1;
			// end

			// if(bram_we_accu & accu_ram_we_cnt<4 & accu_ram_we_cnt>=0) begin //first setosa
			// 	accu_bram_data[accu_bram_cnt_indx] <= bram_din;
			// 	accu_bram_cnt_indx <= accu_bram_cnt_indx+ 1'b1;
			// end
			// else if(bram_we_accu & accu_ram_we_cnt<204 & accu_ram_we_cnt>=192) begin //last 2 setosa and first versicolor
			// 	accu_bram_data[accu_bram_cnt_indx] <= bram_din;
			// 	accu_bram_cnt_indx <= accu_bram_cnt_indx+ 1'b1;
			// end
			// else if(bram_we_accu & accu_ram_we_cnt<404 & accu_ram_we_cnt>=392) begin //last 2 versicolor, first virginica
			// 	accu_bram_data[accu_bram_cnt_indx] <= bram_din;
			// 	accu_bram_cnt_indx <= accu_bram_cnt_indx+ 1'b1;
			// end
			// else if(bram_we_accu & accu_ram_we_cnt<600 & accu_ram_we_cnt>=596) begin
			// 	accu_bram_data[accu_bram_cnt_indx] <= bram_din;
			// 	accu_bram_cnt_indx <= accu_bram_cnt_indx+ 1'b1;
			// end

			// if(addr_offset>=4) begin
			// 	addr_offset_overflow_cnt <= addr_offset_overflow_cnt + 1'b1;
			// end

			// if(bram_we & (bram_addr_re == bram_addr_wr)) begin
			// 	rdw_check <= rdw_check+1'b1;
			// end

			// if(currentState == BRAM_ACCU) begin
			// 	bram_accu_cycle <= bram_accu_cycle + 1'b1;
			// end
			// if(cluster_fifo_almostfull | data_fifo_almostfull ) begin
			// 	back_pressure_cnt <= back_pressure_cnt + 1'b1;
			// end
			// if(goto_agg) begin
			// 	goto_agg_cnt <= goto_agg_cnt + 1'b1;
			// end
			// if((currentState == BRAM_ACCU) & is_agg) begin
			// 	cross_state_cnt <= 1'b1;
			// end
		end

		// accu_debug_cnt[0] = bram_accu_cycle;
		// accu_debug_cnt[1] = accu_ram_we_cnt;
		// accu_debug_cnt[2] = back_pressure_cnt;
		// accu_debug_cnt[3] = {cross_state_cnt, goto_agg_cnt};
		// accu_debug_cnt[0] = {accu_bram_data[3],accu_bram_data[2],accu_bram_data[1],accu_bram_data[0]};
		// accu_debug_cnt[1] = {accu_bram_data[7],accu_bram_data[6],accu_bram_data[5],accu_bram_data[4]};
		// accu_debug_cnt[2] = {accu_bram_data[11],accu_bram_data[10],accu_bram_data[9],accu_bram_data[8]};
		// accu_debug_cnt[3] = {accu_bram_data[15],accu_bram_data[14],accu_bram_data[13],accu_bram_data[12]};
		// accu_debug_cnt[4] = {accu_bram_data[19],accu_bram_data[18],accu_bram_data[17],accu_bram_data[16]};
		// accu_debug_cnt[5] = {accu_bram_data[23],accu_bram_data[22],accu_bram_data[21],accu_bram_data[20]};
		// accu_debug_cnt[6] = {accu_bram_data[27],accu_bram_data[26],accu_bram_data[25],accu_bram_data[24]};
		// accu_debug_cnt[7] = {accu_bram_data[31],accu_bram_data[30],accu_bram_data[29],accu_bram_data[28]};
		

	end

	// reg [31:0] agg_valid_cnt;
 //  	reg [15:0][15:0] sent_agg_data; //don't need to reset 

	// always @ (posedge clk) begin
	// 	if(~rst_n_reg) begin
	// 	  agg_valid_cnt <= '0;
	// 	end
	// 	else begin 
	// 	  if(agg_valid_o) begin
	// 	    agg_valid_cnt <= agg_valid_cnt + 1'b1;
	// 	  end
	// 	  if(agg_valid_o) begin
	// 	     sent_agg_data[agg_valid_cnt] <= agg_data_o[15:0];
	// 	  end

	// 	    accu_debug_cnt[0] <= {sent_agg_data[1], sent_agg_data[0]};
	// 	    accu_debug_cnt[1] <= {sent_agg_data[3], sent_agg_data[2]};
	// 	    accu_debug_cnt[2] <= {sent_agg_data[5], sent_agg_data[4]};
	// 	    accu_debug_cnt[3] <= {sent_agg_data[7], sent_agg_data[6]};
	// 	    accu_debug_cnt[4] <= {sent_agg_data[9], sent_agg_data[8]};
	// 	    accu_debug_cnt[5] <= {sent_agg_data[11], sent_agg_data[10]};
	// 	    accu_debug_cnt[6] <= {sent_agg_data[13], sent_agg_data[12]};
	// 	    accu_debug_cnt[7] <= {sent_agg_data[15], rdw_check};

	// 	end
	// end





// `define LOG_NULL
// //////////////////////////////////////////////////////////////////////////////////////////////////////
// //---------------------------------log file print--------------------------------------------------//
// ////////////////////////////////////////////////////////////////////////////////////////////////////
// `ifdef LOG_FILE
// 	int file;
// 	reg [31:0] is_agg_data_re_dim_cnt_accu, is_agg_data_re_sample_cnt;
// 	initial begin
// 		file = $fopen($sformatf("/home/harpdev/doppiodb/fpga/operators/bit_serial_kmeans/sim_log/k_means_accumulation%d.txt", PIPELINE_INDEX ),"w");

// 		if(file) begin 
// 			$display("k_means_accumulation file open successfully\n");
// 			$fwrite(file,"PIPELINE_INDEX:%d\n", PIPELINE_INDEX);
// 			$fwrite(file,"Data Sum\n");
// 		end
// 		else 
// 			$display("Failed to open k_means_accumulation file\n");	
// 	end

// 	always @ (posedge clk) begin
// 		if(~rst_n) begin
// 			is_agg_data_re_dim_cnt_accu <= '0;
// 			is_agg_data_re_sample_cnt <= '0;
// 		end
// 		else begin
// 			if(is_agg_data_re & (is_agg_data_re_dim_cnt_accu == data_dim_accu_DP-1)) begin
// 				is_agg_data_re_dim_cnt_accu <= '0;
// 			end
// 			else if(is_agg_data_re) begin
// 				is_agg_data_re_dim_cnt_accu <= is_agg_data_re_dim_cnt_accu + 1'b1;
// 			end

// 			if(is_agg_data_re & (is_agg_data_re_dim_cnt_accu == data_dim_accu_DP-1) &(is_agg_data_re_sample_cnt==num_cluster_accu_DP-1)) begin
// 				is_agg_data_re_sample_cnt <= '0;
// 			end
// 			else if(is_agg_data_re & (is_agg_data_re_dim_cnt_accu == data_dim_accu_DP-1)) begin
// 				is_agg_data_re_sample_cnt <= is_agg_data_re_sample_cnt + 1'b1;
// 			end


// 			if (is_agg_data_re &(is_agg_data_re_dim_cnt_accu == data_dim_accu_DP-1) & (is_agg_data_re_sample_cnt==num_cluster_accu_DP-1)) begin
// 				$fwrite(file,"%d\nCluster Cnt\n",bram_dout);
// 			end
// 			else if(is_agg_data_re &(is_agg_data_re_dim_cnt_accu == data_dim_accu_DP-1)) begin
// 				$fwrite(file,"%d\n", bram_dout);
// 			end
// 			else if(is_agg_data_re ) begin
// 				$fwrite(file,"%d ", bram_dout);
// 			end
	
// 			if(is_agg_cluster_re & ~(agg_cnt==num_cluster_accu_DP-1)) begin
// 				$fwrite(file,"%d ",  accu_counter[agg_cnt]);
// 			end
// 			else if(is_agg_cluster_re & (agg_cnt == num_cluster_accu_DP -1)) begin
// 				$fwrite(file,"%d\n", accu_counter[agg_cnt]);
// 			end

// 			if(is_agg_sse_re) begin
// 				$fwrite(file,"\nSSE:%d\n\n\n",sse);
// 			end
// 		end
// 	end
// `endif
////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////


// //////////////////////////////////////////////////////////////////////////////////////////////////////
// //---------------------------------log file_accu print--------------------------------------------------//
// ////////////////////////////////////////////////////////////////////////////////////////////////////
// `ifdef LOG_FILE
// 	int file_accu;
// 	reg [NUM_CLUSTER_BITS:0] cluster_fifo_dout_reg;
// 	initial begin
// 		file_accu = $fopen($sformatf("/home/harpdev/doppiodb/fpga/operators/low_precision_kmeans/sim_log/k_means_accumulation_bram%d.txt", PIPELINE_INDEX ),"w");

// 		if(file_accu) begin 
// 			$display("k_means_accumulation_bram file_accu open successfully\n");
// 			$fwrite(file_accu,"PIPELINE_INDEX:%d\n", PIPELINE_INDEX);
// 		end
// 		else 
// 			$display("Failed to open k_means_accumulation_bram file_accu\n");	
// 	end

// 	always @ (posedge clk) begin
// 		if(~rst_n) begin
// 			cluster_fifo_dout_reg <= '0;
// 		end
// 		else begin
// 			cluster_fifo_dout_reg <= cluster_fifo_dout;

// 			if(~is_agg & bram_we) begin
// 				$fwrite(file_accu,"Data:%d, Cluster%d, Accu:%d, Wr_Addr:%d\n", data_fifo_dout_reg, cluster_fifo_dout_reg, bram_din,bram_addr_wr);
// 			end

// 			if(goto_agg) begin
// 				$fwrite(file_accu,"next iteration\n\n\n");
// 			end
// 		end
// 	end
// `endif
// ////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////




endmodule
