import lynxTypes::*;

module regex_req (
    input  logic        aclk,
    input  logic        aresetn,

    // RDMA
    metaIntf.s          rdma_rq,

    // Host
    reqIntf.m           bpss_rd_req,

    // Sequence
    metaIntf.m          params,

    // Config
    metaIntf.m          cnfg
);

// -- DP
always_comb begin: DP
    // Receive queue
    rdma_rq.ready = 1'b0;

    // RD host
    bpss_rd_req.valid = 1'b0;
    bpss_rd_req.data = 0;
    bpss_rd_req.data.vaddr = rdma_rq.data[];
    bpss_rd_req.data.len = rdma_rq.data[]; 
    bpss_rd_req.data.pid = rdma_rq.data[];
    bpss_rd_req.data.ctl = 1'b1;

    // Params
    params.valid = 1'b0;
    params.data = {rdma_rq.data[], rdma_rq.data[], rdma_rq.data[]};

    // Config intf
    cnfg.valid = 1'b0;
    cnfg.data = rdma_rq.data;

    // DP fsm
    if(rdma_rq.valid) begin
        if(rdma_rq.data[REGEX_CMD_TYPE]) begin
            if(cnfg.ready) begin
                rdma_rq.ready = 1'b1;
                cnfg.valid = 1'b1;
            end
        end
        else begin
            if(bpss_rd_req.ready & params.ready) begin
                rdma_rq.ready = 1'b1;
                params.valid = 1'b1;
                bpss_rd_req.valid = 1'b1;
            end
        end
    end

end

endmodule