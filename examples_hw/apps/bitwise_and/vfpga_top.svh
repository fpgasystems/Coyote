/* In this simple example, data from incoming RDMA write will be written to the host with the data shifted left by 8 bits.
In case of an incoming RDMA read request, data from the host memory will be shifted right by 8 bits before being sent to the RDMA interface. */

reg[5:0] count = 6'b000000;
reg reset_ready = 1'b0;

initial begin
    axis_host_recv[0].tready = 1'b0;
    axis_host_recv[1].tready = 1'b1;
end

assign axis_host_send[0].tdata = axis_host_recv[0].tdata & axis_host_recv[1].tdata;
assign axis_host_send[0].tvalid = axis_host_recv[0].tvalid & axis_host_recv[1].tvalid;
assign axis_host_send[0].tkeep = axis_host_recv[0].tkeep & axis_host_recv[1].tkeep;
assign axis_host_send[0].tlast = 1;
assign axis_host_send[0].tid = count;

always_ff @(posedge aclk) begin
        if(axis_host_recv[0].tvalid && axis_host_recv[1].tvalid) begin
            reset_ready <= 1'b1;
            axis_host_recv[0].tready <= 1'b1;
            axis_host_recv[1].tready <= 1'b1;
        end
        else if(reset_ready) begin
            axis_host_recv[0].tready <= 1'b0;
            axis_host_recv[1].tready <= 1'b0;
            reset_ready <= 1'b0;
            count <= count + 1;
        end
end

// Tie-off unused
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb axis_host_send[1].tie_off_m();
