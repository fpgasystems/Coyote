import lynxTypes::*;

module queue #(
    parameter type QTYPE = logic[63:0],
    parameter QDEPTH = 8
) (
    input  logic        aclk,
    input  logic        aresetn,

    input  logic        val_snk,
    output logic        rdy_snk,
    input  QTYPE        data_snk,

    input  logic        val_src,
    output logic        rdy_src,
    output QTYPE        data_src
);

fifo #(
    .DATA_BITS($bits(QTYPE)),
    .FIFO_SIZE(QDEPTH)
) inst_fifo (
    .aclk       (aclk),
    .aresetn    (aresetn),
    .rd         (val_src),
    .wr         (val_snk),
    .ready_rd   (rdy_src),
    .ready_wr   (rdy_snk),
    .data_in    (data_snk),
    .data_out   (data_src)
);

endmodule