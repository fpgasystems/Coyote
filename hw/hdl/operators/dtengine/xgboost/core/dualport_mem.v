


module DualPortMem #(
    parameter DATA_WIDTH          = 32,
    parameter ADDR_WIDTH          = 8,
    parameter WORD_WIDTH          = 16,
    parameter LINE_ADDR_WIDTH     = 3,
    parameter NUM_PIPELINE_LEVELS = 1
) (
    input  wire                                     clk,
    input  wire                                     rst_n,
    input  wire                                     we,
    input  wire                                     re,
    input  wire [ADDR_WIDTH+LINE_ADDR_WIDTH-1:0]    raddr,
    input  wire [ADDR_WIDTH-1:0]                    waddr,  
    input  wire [DATA_WIDTH-1:0]                    din,
    output wire [WORD_WIDTH-1:0]                    dout,
    output wire                                     valid_out
);

reg                         re_p[NUM_PIPELINE_LEVELS+1];
wire  [DATA_WIDTH-1:0]       dline;
reg  [LINE_ADDR_WIDTH-1:0]  raddr_d1;



Qdualport_mem   Qdualport_mem_inst (
    .clock ( clk ),
    .data ( din ),
    .rdaddress ( raddr[LINE_ADDR_WIDTH+ADDR_WIDTH-1:LINE_ADDR_WIDTH] ),
    .rden ( re ),
    .wraddress ( waddr ),
    .wren ( we ),
    .q ( dline )
    );


always @(posedge clk) begin
    raddr_d1 <= raddr[LINE_ADDR_WIDTH-1:0];
end

//------------------------ Out MUX Pipelines ------------------------//
// pipeline re i = 0,
always @(posedge clk) begin
    if(~rst_n) begin
        re_p[0] <= 0;
    end 
    else begin
        re_p[0] <= re;
    end
end

genvar i;
// pipeline re i = 1 to NUM_PIPELINE_LEVELS+1, 
generate for (i = 1; i < NUM_PIPELINE_LEVELS+1; i=i+1) begin: PipelineOutMux
    always @(posedge clk) begin
        if(~rst_n) begin
            re_p[i] <= 0;
        end 
        else begin
            re_p[i] <= re_p[i-1];
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
    
    .din            (dline),
    .addr           (raddr_d1),
    .dout           (dout)
);

assign  valid_out = re_p[NUM_PIPELINE_LEVELS];
			
endmodule

