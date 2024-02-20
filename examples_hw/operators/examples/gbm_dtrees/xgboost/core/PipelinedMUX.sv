

module PipelinedMUX #(
    parameter DATA_WIDTH          = 32,
    parameter ADDR_WIDTH          = 3,
    parameter WORD_WIDTH          = 32,
    parameter NUM_PIPELINE_LEVELS = 1
)(
	input  wire                        clk,    // Clock
	input  wire                        rst_n,  // Asynchronous reset active low
	
	input  wire [DATA_WIDTH-1:0]       din,
	input  wire [ADDR_WIDTH-1:0]       addr,
    output wire [WORD_WIDTH-1:0]       dout
);



localparam NUM_WORDS_PER_LINE = DATA_WIDTH / WORD_WIDTH;

localparam NUM_BITS_PER_LEVEL     = ADDR_WIDTH / NUM_PIPELINE_LEVELS;
localparam NOT_SIMILAR_LEVELS     = ADDR_WIDTH % NUM_PIPELINE_LEVELS;

wire [WORD_WIDTH-1:0]       dline_Array[NUM_WORDS_PER_LINE-1:0];
reg  [ADDR_WIDTH-1:0]       addr_d[NUM_PIPELINE_LEVELS-1:0];

genvar i,j,w;

generate
	always @(*) begin
		addr_d[0] = addr;
	end

	for (i = 1; i < NUM_PIPELINE_LEVELS; i = i + 1)
	begin:addr_pipeline
		always @(posedge clk) begin
			if (~rst_n) begin
				// reset
				addr_d[i] <= 0;
			end
			else begin
				addr_d[i] <= addr_d[i-1];
			end
		end
	end
endgenerate
generate 
for (i = 0; i < NUM_WORDS_PER_LINE; i=i+1) begin: VectorToArray
	assign dline_Array[i] = din[i*WORD_WIDTH+WORD_WIDTH-1:i*WORD_WIDTH];
end
endgenerate

generate 
	// One Pipeline Level, i.e. register output only.
	if(NUM_PIPELINE_LEVELS == 1) begin: pipeLevs 
		//-------------------------------------------------------------------------------------//
		reg  [WORD_WIDTH-1:0]       dword_out;

		always @(posedge clk) begin
			dword_out <= dline_Array[ addr_d[0][ADDR_WIDTH-1:0] ];
		end

		assign dout = dword_out;
		//-------------------------------------------------------------------------------------//
	end
	else if(NOT_SIMILAR_LEVELS == 0) begin
		//-------------------------------------------------------------------------------------//
		reg  [WORD_WIDTH-1:0]           levArray[NUM_PIPELINE_LEVELS+1:0][(NUM_WORDS_PER_LINE >> NUM_BITS_PER_LEVEL)-1:0][(2**NUM_BITS_PER_LEVEL)-1:0];

		for (i = 0; i < NUM_WORDS_PER_LINE; i=i+(2**NUM_BITS_PER_LEVEL)) begin: L1
			for (w = 0; w < (2**NUM_BITS_PER_LEVEL); w=w+1) begin: L2
				always @(*) begin
					levArray[0][i>>NUM_BITS_PER_LEVEL][w] = din[(i+w)*WORD_WIDTH+WORD_WIDTH-1:(i+w)*WORD_WIDTH];
				end
			end
		end
        //
		for (i = 0; i < NUM_PIPELINE_LEVELS; i=i+1) begin:L3 
			for (j = 0; j < (NUM_WORDS_PER_LINE >> ((i+1)*NUM_BITS_PER_LEVEL)); j=j+1) begin:L4
				always @(posedge clk) begin
					levArray[i+1][j>>NUM_BITS_PER_LEVEL][j] <= levArray[i][j][ addr_d[i][i*NUM_BITS_PER_LEVEL+NUM_BITS_PER_LEVEL-1:i*NUM_BITS_PER_LEVEL] ];
				end
			end
		end

		assign dout = levArray[NUM_PIPELINE_LEVELS][0][0];
		//-------------------------------------------------------------------------------------//
	end
	else if(ADDR_WIDTH == 4) begin  // This means Pipeline level = 3

		reg  [WORD_WIDTH-1:0]  lev1Array[3:0][3:0];
		reg  [WORD_WIDTH-1:0]  lev2Array[1:0][1:0];
		reg  [WORD_WIDTH-1:0]  lev3Array[1:0];
		reg  [WORD_WIDTH-1:0]  dword_out;

		for (i = 0; i < NUM_WORDS_PER_LINE; i=i+4) begin:L5
			for (w = 0; w < 4; w=w+1) begin:L6
				always @(*) begin
					lev1Array[i>>2][w] = din[(i+w)*WORD_WIDTH+WORD_WIDTH-1:(i+w)*WORD_WIDTH];
				end 
			end
		end
        // Level 1 Muxes
		for (j = 0; j < 4; j=j+1) begin:L7
			always @(posedge clk) begin
				lev2Array[j>>1][j%2] <= lev1Array[j][ addr_d[0][1:0] ];
			end
		end
		// Level 2 Muxes
		for (j = 0; j < 2; j=j+1) begin:L8
			always @(posedge clk) begin
				lev3Array[j] <= lev2Array[j][ addr_d[1][2] ];
			end
		end
		// Level 3 Muxes
		always @(posedge clk) begin
			dword_out <= lev3Array[ addr_d[2][3] ];
		end

		assign dout = dword_out;
	end
	else if(ADDR_WIDTH == 3) begin  // This means Pipeline level = 2
		wire [WORD_WIDTH-1:0]  lev1Array[1:0][3:0];
		reg  [WORD_WIDTH-1:0]  lev2Array[1:0];
		reg  [WORD_WIDTH-1:0]  dword_out;

		for (i = 0; i < NUM_WORDS_PER_LINE; i=i+4) begin:L9
			for (w = 0; w < 4; w=w+1) begin:L10
				assign lev1Array[i>>2][w] = din[(i+w)*WORD_WIDTH+WORD_WIDTH-1:(i+w)*WORD_WIDTH];
			end
		end
		// Level 1 Muxes
		for (j = 0; j < 2; j=j+1) begin:L11
			always @(posedge clk) begin
				lev2Array[j] <= lev1Array[j][ addr_d[0][1:0] ];
			end
		end
		// Level 2 Muxes
		always @(posedge clk) begin
			dword_out <= lev2Array[ addr_d[1][2] ];
		end

		assign dout = dword_out;

	end
endgenerate





endmodule
