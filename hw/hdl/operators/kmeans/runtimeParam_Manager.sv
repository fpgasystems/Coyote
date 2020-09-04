import kmeansTypes::*;

module runtimeParam_Manager (
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low
	input wire                                   start_um,
    input wire [511:0]                           um_params,

    output RuntimeParam 						 runtimeParam,
    output reg 									 start_operator
);

	reg flag;
	reg rst_n_reg;

	always_ff @(posedge clk) begin
		rst_n_reg <= rst_n;
		if(~rst_n_reg) begin
			flag <= '0;
			start_operator <= '0;
			runtimeParam <= '0;
		end
		else begin
			if(start_um & ~flag) begin
				flag <= 1'b1;
			end
			else if(flag & ~start_um) begin
				flag <= 1'b0;
			end

			start_operator <= ~start_um & flag;

			if (start_um) begin
				runtimeParam.addr_center <= um_params[63:6]; //64
				runtimeParam.addr_data <= um_params[127:70]; //64
				runtimeParam.addr_result <= um_params[191:134];  //64
				runtimeParam.data_set_size <= um_params[255:192]; //64
				runtimeParam.num_cl_centroid <= um_params[287:256]; //32
				runtimeParam.num_cl_tuple <= um_params[319:288]; //32
				runtimeParam.num_cluster <= um_params[351:320]; //32
				runtimeParam.data_dim <= um_params[383:352]; //32
				runtimeParam.num_iteration <= um_params[399:384]; //16
				// runtimeParam.precision <= um_params[407:400]; //8
			end

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
		file = $fopen("/home/harpdev/doppiodb/fpga/operators/k_means_v2/sim_log/runtimeParam.txt","w");
		if(file) 
			$display("RuntimeParam file open successfully\n");
		else 
			$display("Failed to open runtimeParam file\n");	
	end

	always @ (posedge clk) begin
		if(~rst_n) begin
			
			file_finished <= 1'b0;
		end
		else begin

			if(start_um & ~file_finished) begin
				$fwrite(file,"addr_center:%d\n", um_params[63:6]);
				$fwrite(file,"addr_data:%d\n", um_params[127:70]);
				$fwrite(file,"addr_result:%d\n", um_params[191:134]);
				$fwrite(file,"data_set_size:%d\n", um_params[255:192]);
				$fwrite(file,"num_cl_centroid:%d\n", um_params[287:256]);
				$fwrite(file,"num_cl_tuple:%d\n", um_params[319:288]);
				$fwrite(file,"num_cluster:%d\n", um_params[351:320]);
				$fwrite(file,"data_dim:%d\n", um_params[383:352]);
				$fwrite(file,"num_iteration:%d\n", um_params[399:384]);
				// $fwrite(file,"precision:%d\n", um_params[407:400]);

				file_finished <= 1'b1;
			end
			else if(file_finished) begin
				$fclose(file);
			end
		end
	end
`endif
////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////

endmodule