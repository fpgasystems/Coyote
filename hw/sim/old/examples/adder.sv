import lynxTypes::*;

module adder (
    input  logic        aclk,
    input  logic        aresetn,
    AXI4SR.s            axis_sink,
    AXI4SR.m           axis_src
);

logic [31:0] tmp_sum;

always_comb begin
    axis_src.tvalid = axis_sink.tvalid;
    axis_src.tkeep  = axis_sink.tkeep;
    axis_src.tid    = axis_sink.tid;
    axis_src.tlast  = axis_sink.tlast;

    axis_sink.tready = axis_src.tready;

    tmp_sum = 0;
    for(int i = 0; i < 16; i++) begin
        tmp_sum = tmp_sum + axis_sink.tdata[i*32+:32];
    end

    axis_src.tdata = 0;
    axis_src.tdata[31:0] = tmp_sum;
end
    
endmodule