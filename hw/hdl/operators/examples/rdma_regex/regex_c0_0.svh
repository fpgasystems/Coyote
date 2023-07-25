//
// Regex
//

// Tie-off
always_comb axi_ctrl.tie_off_s();

// UL
localparam integer PARAMS_BITS = VADDR_BITS + LEN_BITS + RDMA_QPN_BITS;

// Write - RDMA
`AXIS_ASSIGN(axis_rdma_sink, axis_host_0_src)
`REQ_ASSIGN(wr_req_rdma, bpss_wr_req)

// Read - Regex
metaIntf #(.DATA_BITS(PARAMS_BITS)) params_sink ();
metaIntf #(.DATA_BITS(PARAMS_BITS)) params_src ();

metaIntf #(.DATA_BITS(AXI_DATA_BITS)) cnfg ();

// Request handler
regex_req inst_regex_req (
    .aclk(aclk),
    .aresetn(aresetn),
    .rdma_rq(rdma_0_rq),
    .bpss_rd_req(bpss_rd_req),
    .params(params_sink),
    .cnfg(cnfg)
);

// Data handler
regex_data inst_regex_data (
    .aclk(aclk),
    .aresetn(aresetn),
    .axis_sink(axis_host_0_sink),
    .axis_src(axis_rdma_src),
    .rdma_sq(rdma_0_sq),
    .params(params_src),
    .cnfg(cnfg)
);

// Sequence
queue_meta inst_seq (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(params_sink),
    .m_meta(params_src)
);