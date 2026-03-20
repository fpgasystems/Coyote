// Full dataset it1 — standalone ro_1536 (N_RO=1536)
// Stream passthrough (recv[0] -> send[0]) + ring_osc_array (N_RO=1536).
// Passthrough keeps the app Coyote-compatible; ROs dominate the resource footprint.

// Stream passthrough
always_comb begin
    axis_host_send[0].tdata  = axis_host_recv[0].tdata;
    axis_host_send[0].tkeep  = axis_host_recv[0].tkeep;
    axis_host_send[0].tlast  = axis_host_recv[0].tlast;
    axis_host_send[0].tvalid = axis_host_recv[0].tvalid;
    axis_host_recv[0].tready = axis_host_send[0].tready;
end

// Unused streams / control signals
always_comb axis_host_recv[1].tie_off_s();
always_comb axis_host_send[1].tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb notify.tie_off_m();
always_comb axi_ctrl.tie_off_s();

// --- Standalone ring oscillator array (N_RO=1536) ---
(* DONT_TOUCH = "TRUE" *) wire [1535:0] ro_out;
ring_osc_array #(.N_RO(1536)) inst_ro_array (
    .signal_in  (axis_host_recv[0].tvalid),
    .signal_out (ro_out)
);
