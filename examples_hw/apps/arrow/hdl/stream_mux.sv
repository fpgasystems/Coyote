

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"


module stream_mux(
    input logic aresetn,
    input logic server,         // set for server operation
    input logic local_only,     // set for local serialization

    AXI4SR.s host_in,
    AXI4SR.s rdma_in,

    AXI4SR.m host_out,
    AXI4SR.m rdma_out
);

    always_comb begin
        if (aresetn) begin
            if (server) begin
                host_out.tvalid  = rdma_in.tvalid;
                host_out.tlast   = rdma_in.tlast;
                host_out.tid     = rdma_in.tid;
                host_out.tkeep   = rdma_in.tkeep;
                host_out.tdata   = rdma_in.tdata;

                rdma_in.tready   = host_out.tready;

                rdma_out.tvalid  = 0;
                rdma_out.tlast   = 0;
                rdma_out.tid     = 0;
                rdma_out.tkeep   = 0;
                rdma_out.tdata   = 0;

                host_in.tready   = 0;
            end
            else begin
                if (local_only) begin
                    host_out.tvalid  = host_in.tvalid;
                    host_out.tlast   = host_in.tlast;
                    host_out.tid     = host_in.tid;
                    host_out.tkeep   = host_in.tkeep;
                    host_out.tdata   = host_in.tdata;

                    host_in.tready   = host_out.tready;

                    rdma_out.tvalid  = 0;
                    rdma_out.tlast   = 0;
                    rdma_out.tid     = 0;
                    rdma_out.tkeep   = 0;
                    rdma_out.tdata   = 0;

                    rdma_in.tready   = 0;
                end
                else begin
                    rdma_out.tvalid  = host_in.tvalid;
                    rdma_out.tlast   = host_in.tlast;
                    rdma_out.tid     = host_in.tid;
                    rdma_out.tkeep   = host_in.tkeep;
                    rdma_out.tdata   = host_in.tdata;

                    host_in.tready   = rdma_out.tready;

                    host_out.tvalid  = 0;
                    host_out.tlast   = 0;
                    host_out.tid     = 0;
                    host_out.tkeep   = 0;
                    host_out.tdata   = 0;

                    rdma_in.tready   = 0;
                end
            end
        end
        else begin
            host_out.tvalid = 0;
            host_out.tlast = 0;
            host_out.tid = 0;
            host_out.tkeep = 0;
            host_out.tdata = 0;

            rdma_out.tvalid = 0;
            rdma_out.tlast = 0;
            rdma_out.tid = 0;
            rdma_out.tkeep = 0;
            rdma_out.tdata = 0;

            host_in.tready = 0;
            rdma_in.tready = 0;
        end
    end

endmodule
