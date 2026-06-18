// nodbg variant of A03_multitenancy_aes — ILA (ila_aes) removed
// NPAR=2 (reduced from 4 for pblock budget, proven in pilot).
// Added stream[1] tie-offs for N_STRM_AXI=2 shell.
// ILA from original example 03 preserved.

import lynxTypes::*;

/////////////////////////////////////////////////////////
//               CONTROL REGISTERS                    //
///////////////////////////////////////////////////////
logic key_valid;
logic [AXI_DATA_BITS:0] key;

aes_axi_ctrl_parser inst_aes_axi_ctrl_parser (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_ctrl(axi_ctrl),

    .key(key),
    .key_valid(key_valid)
);

/////////////////////////////////////////////////////////
//               ENCRYPTION MODULE                    //
///////////////////////////////////////////////////////

aes_top #(
    .NPAR(2)
) inst_aes_top (
    .clk(aclk),
    .reset_n(aresetn),
    .stall(~axis_host_send[0].tready),

    .key_in(key),
    .keyVal_in(key_valid),
    .keyVal_out(),

    .data_in(axis_host_recv[0].tdata),
    .dVal_in(axis_host_recv[0].tvalid),
    .keep_in(axis_host_recv[0].tkeep),
    .last_in(axis_host_recv[0].tlast),
    .id_in(axis_host_recv[0].tid),

    .data_out(axis_host_send[0].tdata),
    .dVal_out(axis_host_send[0].tvalid),
    .keep_out(axis_host_send[0].tkeep),
    .last_out(axis_host_send[0].tlast),
    .id_out(axis_host_send[0].tid)
);

assign axis_host_recv[0].tready = axis_host_send[0].tready;

// Tie-off unused signals to avoid synthesis problems
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb axis_host_recv[1].tie_off_s();
always_comb axis_host_send[1].tie_off_m();

