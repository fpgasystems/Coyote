import lynxTypes::*;

module queue_meta #(
    parameter QDEPTH = 8
) (
    input  logic        aclk,
    input  logic        aresetn,

    metaIntf.s          sink,
    metaIntf.m          src
);

logic val_rd;
logic rdy_rd;

fifo #(
    .DATA_BITS($bits(sink.data)),
    .FIFO_SIZE(QDEPTH)
) inst_fifo (
    .aclk       (aclk),
    .aresetn    (aresetn),
    .rd         (val_rd),
    .wr         (sink.valid),
    .ready_rd   (rdy_rd),
    .ready_wr   (sink.ready),
    .data_in    (sink.data),
    .data_out   (src.data)
);

assign src.valid = rdy_rd;
assign val_rd = src.valid & src.ready;

endmodule