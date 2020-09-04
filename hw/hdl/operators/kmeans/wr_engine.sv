import kmeansTypes::*;

module wr_engine (
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	input RuntimeParam 						rp,
	//memory interface
	input 	wire 							start_operator,

	output  reg  [57:0]                   	um_tx_wr_addr,
    output  reg  [7:0]                    	um_tx_wr_tag,
    output  reg                           	um_tx_wr_valid,
    output  reg  [511:0]                  	um_tx_data,
    input   wire                           	um_tx_wr_ready,

    output wire 							um_done,

    //kmeans module update interface
    input wire [512-1:0] 					update,
	input wire 								update_valid,
	input wire 								update_last,
	
	//debug counter
	output wire [31:0] 						wr_engine_debug_cnt
	
);


/////////////////////////////---To avoid timeing--//////////////////////////////////
reg [511:0] 	update_reg, update_reg2;
reg 						update_valid_reg, update_valid_reg2;
reg 						update_last_reg, update_last_reg2;
reg 						rst_n_reg;
reg 						start_operator_reg1,start_operator_reg2;

always @ (posedge clk) begin
	rst_n_reg <= rst_n;
	start_operator_reg1 <= start_operator;
	start_operator_reg2 <= start_operator_reg1;
	if(~rst_n_reg) begin
		update_valid_reg <= '0;
	end
	else begin
		//if(wr_engine_ready) begin
			update_reg <= update;
			update_reg2 <= update_reg;

			update_valid_reg <= update_valid;
			update_valid_reg2 <= update_valid_reg;

			update_last_reg <= update_last;
			update_last_reg2 <= update_last_reg;

		//end
	end
end

////////////////////////////////////////////////////////////////////////////////////////


wire 								wr_fifo_valid;
wire [512 : 0]				 		wr_fifo_dout;
wire								wr_fifo_re;
wire 								wr_fifo_full;

wire [511:0]						wr_data;
wire 								wr_last;
reg [57:0]							wr_addr_offset;
reg [31:0]							iteration_cnt;
reg 								running_kmeans;
reg 								done;

quick_fifo #(.FIFO_WIDTH(512+1),
	.FIFO_DEPTH_BITS(BUFFER_DEPTH_BITS-3))
	wr_fifo
	(
		.clk       (clk),
		.reset_n   (rst_n_reg),
		.we        (~wr_fifo_full & update_valid_reg2),
		.din       ({update_last_reg2,update_reg2}),
		.re        (wr_fifo_re),
		.valid     (wr_fifo_valid),
		.dout      (wr_fifo_dout),
		.count     (),
		.empty     (),
		.full      (wr_fifo_full),
		.almostfull()	);

assign wr_data = wr_fifo_dout[511:0];
assign wr_last = wr_fifo_dout[512];
assign wr_fifo_re = wr_fifo_valid & um_tx_wr_ready;


always @ (posedge clk) begin
	if(~rst_n_reg) begin
		um_tx_wr_valid <= 1'b0;
	end
	else begin
		if(um_tx_wr_ready) begin
			um_tx_data <= wr_data;
			um_tx_wr_valid <= wr_fifo_valid;
			um_tx_wr_addr <= rp.addr_result + wr_addr_offset;
		end
		um_tx_wr_tag <= '0;
	end
end



assign um_done = done;

always @ (posedge clk) begin
	if(~rst_n_reg) begin
		wr_addr_offset <= '0;
		iteration_cnt <= '0;
		running_kmeans <= 0;
		done <= '0;
	end
	else begin
		if(um_done) begin
			wr_addr_offset <= '0;
		end
		else if(wr_fifo_valid & um_tx_wr_ready) begin
			wr_addr_offset <= wr_addr_offset + 1'b1;
		end

		if(um_done) begin
			iteration_cnt <= '0;
		end
		else if(wr_last & wr_fifo_valid & um_tx_wr_ready) begin
			iteration_cnt <= iteration_cnt + 1'b1;
		end

		if(start_operator_reg2) begin
			running_kmeans <= 1'b1;
		end
		else if(um_done) begin
			running_kmeans <= 1'b0;
		end

		//set the done signal, um_done is set one cycle after the last cl is sent
		if(done) begin
			done <= 1'b0;
		end
		else if(running_kmeans & (iteration_cnt == rp.num_iteration-1) & wr_last & um_tx_wr_ready & wr_fifo_valid ) begin
			done <= 1'b1;
		end
	end
end

//debug counter
reg [31:0] output_cl_cnt;
always @ (posedge clk) begin 
	if(start_operator_reg2) begin
		output_cl_cnt <= '0;
	end
	else begin
		if(um_tx_wr_ready & um_tx_wr_valid) begin
			output_cl_cnt <= output_cl_cnt + 1'b1;
		end
	end
end

assign wr_engine_debug_cnt = output_cl_cnt;

`define LOG_NULL
//////////////////////////////////////////////////////////////////////////////////////////////////////
//---------------------------------log file print--------------------------------------------------//
////////////////////////////////////////////////////////////////////////////////////////////////////
`ifdef LOG_FILE
  int file;
  reg file_finished;
  initial begin
    file = $fopen("/home/harpdev/doppiodb/fpga/operators/k_means_v2/sim_log/wr_engine.txt","w");

    if(file) begin 
      $display("wr_engine file open successfully\n");
      $display("output to divider",);
    end
    else 
      $display("Failed to open wr_engine file\n"); 
  end

  always @ (posedge clk) begin
    if(~rst_n_reg) begin

    end
    else begin
    	if(um_tx_wr_ready & um_tx_wr_valid) begin
			$fwrite(file,"%d ", um_tx_data[31:0]);
			$fwrite(file,"%d ", um_tx_data[63:32]);
			$fwrite(file,"%d ", um_tx_data[95:64]);
			$fwrite(file,"%d ", um_tx_data[127:96]);
			$fwrite(file,"%d ", um_tx_data[159:128]);
			$fwrite(file,"%d ", um_tx_data[191:160]);
			$fwrite(file,"%d ", um_tx_data[223:192]);
			$fwrite(file,"%d ", um_tx_data[255:224]);
			$fwrite(file,"%d ", um_tx_data[287:256]);
			$fwrite(file,"%d ", um_tx_data[319:288]);
			$fwrite(file,"%d ", um_tx_data[351:320]);
			$fwrite(file,"%d ", um_tx_data[383:352]);
			$fwrite(file,"%d ", um_tx_data[415:384]);
			$fwrite(file,"%d ", um_tx_data[447:416]);
			$fwrite(file,"%d ", um_tx_data[479:448]);
			$fwrite(file,"%d ", um_tx_data[511:480]);

    		$fwrite(file,"\n\n\n");
    	end
    end
  end
 `endif
////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////

endmodule