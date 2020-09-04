

module Mem1in2out #(
    parameter DATA_WIDTH          = 32,
    parameter ADDR_WIDTH          = 10,
    parameter LINE_ADDR_WIDTH     = 3,
    parameter WORD_WIDTH          = 32,
    parameter NUM_PIPELINE_LEVELS = 1
)  (
    input  wire                                     clk,
    input  wire                                     rst_n,
    input  wire                                     we,
    input  wire                                     rea,
    input  wire                                     reb,
    input  wire [LINE_ADDR_WIDTH+ADDR_WIDTH-1:0]    raddr,
    input  wire [LINE_ADDR_WIDTH+ADDR_WIDTH-1:0]    wraddr,  
    input  wire [DATA_WIDTH-1:0]                    din,
    output wire [WORD_WIDTH-1:0]                    dout1,
    output wire                                     valid_out1,
    output wire [WORD_WIDTH-1:0]                    dout2,
    output wire                                     valid_out2
);

reg                         rea_p[NUM_PIPELINE_LEVELS+1];
reg                         reb_p[NUM_PIPELINE_LEVELS+1];
wire [DATA_WIDTH-1:0]       dline_a;
wire [DATA_WIDTH-1:0]       dline_b;

reg  [LINE_ADDR_WIDTH-1:0]  raddr_d1;
reg  [LINE_ADDR_WIDTH-1:0]  wraddr_d1;
/*

(* ramstyle = "no_rw_check" *) reg  [DATA_WIDTH-1:0] mem[0:2**ADDR_WIDTH-1];


    always @(posedge clk) begin
        if (we)
            mem[ wraddr[LINE_ADDR_WIDTH+ADDR_WIDTH-1:LINE_ADDR_WIDTH] ] <= din;
			
        if(rea)
        	dline_a <= mem[ wraddr[LINE_ADDR_WIDTH+ADDR_WIDTH-1:LINE_ADDR_WIDTH] ];
        //
        if(reb)
        	dline_b <= mem[ raddr[LINE_ADDR_WIDTH+ADDR_WIDTH-1:LINE_ADDR_WIDTH] ];
    end

*/
bramin1out2 bram1in2out_inst (
	.address_a ( wraddr[LINE_ADDR_WIDTH+ADDR_WIDTH-1:LINE_ADDR_WIDTH] ),
	.address_b ( raddr[LINE_ADDR_WIDTH+ADDR_WIDTH-1:LINE_ADDR_WIDTH] ),
	.clock     ( clk ),
	.data_a    ( din ),
	.data_b    ( 0 ),
	.wren_a    ( we ),
	.wren_b    ( 1'b0 ),
	.q_a       ( dline_a ),
	.q_b       ( dline_b )
	);


//------------------------ Out MUX Pipelines ------------------------//
// pipeline re i = 0,
always @(posedge clk) begin
	if(~rst_n) begin
		rea_p[0] <= 0;
		reb_p[0] <= 0;
	end 
	else begin
		rea_p[0] <= rea;
		reb_p[0] <= reb;
	end

	wraddr_d1 <= wraddr[LINE_ADDR_WIDTH-1:0];
	raddr_d1  <= raddr[LINE_ADDR_WIDTH-1:0];
end

// pipeline re i = 1 to NUM_PIPELINE_LEVELS+1, 
genvar i;
generate for (i = 1; i < NUM_PIPELINE_LEVELS+1; i=i+1) begin: PipelineOutMux
	always @(posedge clk) begin
		if(~rst_n) begin
			rea_p[i] <= 0;
			reb_p[i] <= 0;
		end 
		else begin
			rea_p[i] <= rea_p[i-1];
			reb_p[i] <= reb_p[i-1];
		end
	end
end
endgenerate

PipelinedMUX #(
    .DATA_WIDTH            (DATA_WIDTH),
    .ADDR_WIDTH            (LINE_ADDR_WIDTH),
    .WORD_WIDTH            (WORD_WIDTH),
    .NUM_PIPELINE_LEVELS   (NUM_PIPELINE_LEVELS)
) muxa(
	.clk            (clk),     
	.rst_n          (rst_n),  
	
	.din            (dline_a),
	.addr           (wraddr_d1),
    .dout           (dout1)
);

PipelinedMUX #(
    .DATA_WIDTH            (DATA_WIDTH),
    .ADDR_WIDTH            (LINE_ADDR_WIDTH),
    .WORD_WIDTH            (WORD_WIDTH),
    .NUM_PIPELINE_LEVELS   (NUM_PIPELINE_LEVELS)
) muxb(
	.clk            (clk),     
	.rst_n          (rst_n),  
	
	.din            (dline_b),
	.addr           (raddr_d1),
    .dout           (dout2)
);


assign  valid_out1 = rea_p[NUM_PIPELINE_LEVELS];
assign  valid_out2 = reb_p[NUM_PIPELINE_LEVELS];



endmodule // Mem1in2out
