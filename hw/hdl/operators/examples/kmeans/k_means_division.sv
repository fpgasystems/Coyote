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

	localparam LPM_WIDTHN = 48;
	localparam LPM_PIPELINE = 20;

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
	.lpm_widthn(LPM_WIDTHN),
	.lpm_widthd(32),
	.lpm_pipeline(LPM_PIPELINE),
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
	
	logic [95:0] tmp;
	div_gen_0 inst_div_gen (
	   .aclk(clk),
	   .s_axis_divisor_tvalid(1'b1),
	   .s_axis_divisor_tdata(divider_denummer[31:0]),
	   .s_axis_dividend_tvalid(1'b1),
	   .s_axis_dividend_tdata(div_sum[LPM_WIDTHN-1:0]),
	   .m_axis_dout_tvalid(),
       .m_axis_dout_tdata(tmp)
	);
	
	
	assign divider_quotient = tmp[79:48];

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

`define LOG_NULL
//////////////////////////////////////////////////////////////////////////////////////////////////////
//---------------------------------log file print--------------------------------------------------//
////////////////////////////////////////////////////////////////////////////////////////////////////
`ifdef LOG_FILE
  int file;
  reg file_finished;
  initial begin
    file = $fopen("/home/harpdev/doppiodb/fpga/operators/k_means_v2/sim_log/k_means_division.txt","w");

    if(file) begin 
      $display("k_means_division file open successfully\n");
      $fwrite(file,"output to divider\n");
    end
    else 
      $display("Failed to open k_means_division file\n"); 
  end

  always @ (posedge clk) begin
    if(~rst_delay_n) begin

    end
    else begin
    	if(div_dout_valid) begin
    		$fwrite(file,"%d ", div_dout);
    		if(div_dout_last_dim) begin
    			$fwrite(file,"\n");
    		end
    		if(div_dout_last) begin
    			$fwrite(file,"\n\n");
    		end
    	end
    end
  end
`endif
////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////


endmodule
`default_nettype wire
