

module delay #(parameter DATA_WIDTH   = 32,
	           parameter DELAY_CYCLES = 4 
	          ) (

	        input  wire                       clk,
	        input  wire                       rst_n,
	        input  wire  [DATA_WIDTH-1:0]     data_in,
	        input  wire                       data_in_valid,
	        output wire  [DATA_WIDTH-1:0]     data_out,
	        output wire                       data_out_valid
	       );


reg [DATA_WIDTH-1:0]       data_array[DELAY_CYCLES];
reg                        data_array_valid[DELAY_CYCLES];


always @(posedge clk) begin
	// Valid Bit
	if(~rst_n) begin
		data_array_valid[0] <= 0;
	end 
	else begin
		data_array_valid[0] <= data_in_valid;
	end
    // Data word
	data_array[0] <= data_in;
end


genvar i;
generate for (i = 1; i < DELAY_CYCLES; i = i +1) begin: delayPipe
	always @(posedge clk) begin
		// Valid Bit
		if(~rst_n) begin
		 	data_array_valid[i] <= 0;
		end 
		else begin
		 	data_array_valid[i] <= data_array_valid[i-1];
		end
        // Data word
		data_array[i] <= data_array[i-1];
	end
end
endgenerate

assign data_out       = data_array[DELAY_CYCLES-1];
assign data_out_valid = data_array_valid[DELAY_CYCLES-1];

endmodule // delay
