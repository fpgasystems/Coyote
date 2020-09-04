import lynxTypes::*;

module queue_stream #(
    parameter type QTYPE = logic[63:0],
    parameter QDEPTH = 8
) (
    input  logic        aclk,
    input  logic        aresetn,

    input  logic        val_snk,
    output logic        rdy_snk,
    input  QTYPE        data_snk,

    output logic        val_src,
    input  logic        rdy_src,
    output QTYPE        data_src
);

logic val_rd;
logic rdy_rd;

fifo #(
    .DATA_BITS($bits(QTYPE)),
    .FIFO_SIZE(QDEPTH)
) inst_fifo (
    .aclk       (aclk),
    .aresetn    (aresetn),
    .rd         (val_rd),
    .wr         (val_snk),
    .ready_rd   (rdy_rd),
    .ready_wr   (rdy_snk),
    .data_in    (data_snk),
    .data_out   (data_src)
);

assign val_src = rdy_rd;
assign val_rd = val_src & rdy_src;

endmodule