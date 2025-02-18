/* In this simple example, data from incoming RDMA write will be written to the host with the data shifted left by 8 bits.
In case of an incoming RDMA read request, data from the host memory will be shifted right by 8 bits before being sent to the RDMA interface. */

always_comb begin 

    // Write ops
    sq_wr.valid = rq_wr.valid;
    rq_wr.ready = sq_wr.ready;
    sq_wr.data = rq_wr.data;
    // OW
    sq_wr.data.strm = STRM_HOST;
    sq_wr.data.dest = 0;

    // Read ops
    sq_rd.valid = rq_rd.valid;
    rq_rd.ready = sq_rd.ready;
    sq_rd.data = rq_rd.data;
    // OW
    sq_rd.data.strm = STRM_HOST;
    sq_rd.data.dest = 0;
    
    axis_host_send[0].tdata = axis_rrsp_recv[0].tdata << 8;
    axis_host_send[0].tkeep = axis_rrsp_recv[0].tkeep;
    axis_host_send[0].tlast = axis_rrsp_recv[0].tlast;
    axis_host_send[0].tvalid = axis_rrsp_recv[0].tvalid;
    axis_host_send[0].tid = axis_rrsp_recv[0].tid;
    axis_rrsp_recv[0].tready = axis_host_send[0].tready;

    axis_rrsp_send[0].tdata = axis_host_recv[0].tdata >> 8;
    axis_rrsp_send[0].tkeep = axis_host_recv[0].tkeep;
    axis_rrsp_send[0].tlast = axis_host_recv[0].tlast;
    axis_rrsp_send[0].tvalid = axis_host_recv[0].tvalid;
    axis_rrsp_send[0].tid = axis_host_recv[0].tid;
    axis_host_recv[0].tready = axis_rrsp_send[0].tready;
end

// Tie-off unused
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
