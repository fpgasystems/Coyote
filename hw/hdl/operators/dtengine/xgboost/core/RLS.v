
import DTEngine_Types::*;

module RLS #(parameter  DATA_WIDTH      = 8,
	         parameter  DATA_WIDTH_BITS = 3) 
	( 
	input  wire                            clk,
	input  wire                            rst_n,
	input  wire                            shift_enable,
	input  wire  [DATA_WIDTH-1:0]          data_in,
	input  wire  [DATA_WIDTH_BITS-1:0]     shift_count,

	output wire  [DATA_WIDTH-1:0]          data_out
   );

reg  [DATA_WIDTH-1:0]   shifted_data;

assign data_out = shifted_data;

generate
	if(NUM_DTPU_CLUSTERS == 8) begin
		always @(posedge clk) begin
			if(shift_enable) begin 
				case (shift_count)
					3'b001: begin 
						shifted_data[0]              <= data_in[DATA_WIDTH-1];
						shifted_data[DATA_WIDTH-1:1] <= data_in[DATA_WIDTH-2:0];
					end
					3'b010: begin 
						shifted_data[1:0]            <= data_in[DATA_WIDTH-1:DATA_WIDTH-2];
						shifted_data[DATA_WIDTH-1:2] <= data_in[DATA_WIDTH-3:0];
					end
					3'b100: begin 
						shifted_data[3:0]            <= data_in[DATA_WIDTH-1:DATA_WIDTH-4];
						shifted_data[DATA_WIDTH-1:4] <= data_in[DATA_WIDTH-5:0];
					end
					default: begin 
						shifted_data <= data_in;
					end
				endcase
			end
			else begin 
				shifted_data <= data_in;
			end
		end
	end 
	else begin
		always @(posedge clk) begin
			if(shift_enable) begin 
				case (shift_count)
					2'b01: begin 
						shifted_data[0]              <= data_in[DATA_WIDTH-1];
						shifted_data[DATA_WIDTH-1:1] <= data_in[DATA_WIDTH-2:0];
					end
					2'b10: begin 
						shifted_data[1:0]            <= data_in[DATA_WIDTH-1:DATA_WIDTH-2];
						shifted_data[DATA_WIDTH-1:2] <= data_in[DATA_WIDTH-3:0];
					end
					default: begin 
						shifted_data <= data_in;
					end
				endcase
			end
			else begin 
				shifted_data <= data_in;
			end
		end
	end 
	
endgenerate
	

endmodule