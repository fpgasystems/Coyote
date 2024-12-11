

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

`include "custom_types.svh"

module request_mux(
    input logic aclk,
    input logic aresetn,
    input logic select,

    metaIntf.s intf_in_1,
    metaIntf.s intf_in_2,

    metaIntf.m intf_out
);

    wreq_t data_selected;

    // multiplexer
    // Note that the areset line completely zeros this module during reset
    always_comb begin
        // select = 0 => out = in_1, else out = in_2
        intf_out.valid = aresetn ? (select ? intf_in_2.valid : intf_in_1.valid) : 0;
        intf_out.data = aresetn ? data_selected : 0;

        if (select) begin
            data_selected.opcode = intf_in_2.data.opcode;
            data_selected.strm = intf_in_2.data.strm;
            data_selected.mode = intf_in_2.data.mode;
            data_selected.rdma = intf_in_2.data.rdma;
            data_selected.remote = intf_in_2.data.remote;
            data_selected.vfid = intf_in_2.data.vfid;
            data_selected.pid = intf_in_2.data.pid;
            data_selected.dest = intf_in_2.data.dest;
            data_selected.actv = intf_in_2.data.actv;
            data_selected.host = intf_in_2.data.host;
            data_selected.offs = intf_in_2.data.offs;
            data_selected.last = intf_in_2.data.last;
            data_selected.vaddr = intf_in_2.data.vaddr;
            data_selected.len = intf_in_2.data.len;
        end
        else begin
            data_selected.opcode = intf_in_1.data.opcode;
            data_selected.strm = intf_in_1.data.strm;
            data_selected.mode = intf_in_1.data.mode;
            data_selected.rdma = intf_in_1.data.rdma;
            data_selected.remote = intf_in_1.data.remote;
            data_selected.vfid = intf_in_1.data.vfid;
            data_selected.pid = intf_in_1.data.pid;
            data_selected.dest = intf_in_1.data.dest;
            data_selected.actv = intf_in_1.data.actv;
            data_selected.host = intf_in_1.data.host;
            data_selected.offs = intf_in_1.data.offs;
            data_selected.last = intf_in_1.data.last;
            data_selected.vaddr = intf_in_1.data.vaddr;
            data_selected.len = intf_in_1.data.len;
        end

        intf_in_1.ready = ~select & intf_out.ready & aresetn;
        intf_in_2.ready =  select & intf_out.ready & aresetn;
    end

/*
    ila_meta_req inst_req_in_0 (
        .probe0(intf_in_1.data.opcode),
        .probe1(intf_in_1.data.strm),
        .probe2(intf_in_1.data.mode),
        .probe3(intf_in_1.data.rdma),
        .probe4(intf_in_1.data.remote),
        .probe5(intf_in_1.data.vfid),
        .probe6(intf_in_1.data.pid),
        .probe7(intf_in_1.data.dest),
        .probe8(intf_in_1.data.last),
        .probe9(intf_in_1.data.vaddr),
        .probe10(intf_in_1.data.len),
        .probe11(intf_in_1.data.actv),
        .probe12(intf_in_1.data.host),
        .probe13(intf_in_1.data.offs),
        .probe14(intf_in_1.valid),
        .probe15(intf_in_1.ready),
        .clk(aclk)
    );

    ila_meta_req inst_req_in_1 (
        .probe0(intf_in_2.data.opcode),
        .probe1(intf_in_2.data.strm),
        .probe2(intf_in_2.data.mode),
        .probe3(intf_in_2.data.rdma),
        .probe4(intf_in_2.data.remote),
        .probe5(intf_in_2.data.vfid),
        .probe6(intf_in_2.data.pid),
        .probe7(intf_in_2.data.dest),
        .probe8(intf_in_2.data.last),
        .probe9(intf_in_2.data.vaddr),
        .probe10(intf_in_2.data.len),
        .probe11(intf_in_2.data.actv),
        .probe12(intf_in_2.data.host),
        .probe13(intf_in_2.data.offs),
        .probe14(intf_in_2.valid),
        .probe15(intf_in_2.ready),
        .clk(aclk)
    );

    ila_meta_req inst_req_out (
        .probe0(intf_out.data.opcode),
        .probe1(intf_out.data.strm),
        .probe2(intf_out.data.mode),
        .probe3(intf_out.data.rdma),
        .probe4(intf_out.data.remote),
        .probe5(intf_out.data.vfid),
        .probe6(intf_out.data.pid),
        .probe7(intf_out.data.dest),
        .probe8(intf_out.data.last),
        .probe9(intf_out.data.vaddr),
        .probe10(intf_out.data.len),
        .probe11(intf_out.data.actv),
        .probe12(intf_out.data.host),
        .probe13(intf_out.data.offs),
        .probe14(intf_out.valid),
        .probe15(intf_out.ready),
        .clk(aclk)
    );
    //*/

endmodule
