import lynxTypes::*;

module rotate (
    input  logic            aclk,
    input  logic            aresetn,

    AXI4SR.s                 axis_in,
    AXI4SR.m                 axis_out
);

localparam integer N_INTS = AXI_DATA_BITS / 32;

for(genvar i = 0; i < N_INTS; i++) begin
    assign axis_out.tdata[i*32+:8]      = axis_in.tdata[i*32+24+:8];
    assign axis_out.tdata[i*32+8+:8]    = axis_in.tdata[i*32+:8];
    assign axis_out.tdata[i*32+16+:8]   = axis_in.tdata[i*32+8+:8];
    assign axis_out.tdata[i*32+24+:8]   = axis_in.tdata[i*32+16+:8];
end

always_comb begin
    axis_out.tvalid = axis_in.tvalid;
    axis_out.tkeep  = axis_in.tkeep;
    axis_out.tid    = axis_in.tid;
    axis_out.tlast  = axis_in.tlast;

    axis_in.tready  = axis_out.tready;
end

endmodule