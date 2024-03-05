/**
 * VFPGA TOP
 *
 * Tie up all signals to the user kernels
 * Still to this day, interfaces are not supported by Vivado packager ...
 * This means verilog style port connections are needed.
 * 
 */

import lynxTypes::*;

`META_ASSIGN(rq_rd, sq_rd)
`META_ASSIGN(rq_wr, sq_wr)

`AXISR_ASSIGN(axis_rdma_resp[0], axis_host_send[0])
`AXISR_ASSIGN(axis_host_resp[0], axis_rdma_send[0])

`AXISR_ASSIGN(axis_rdma_resp[1], axis_card_send[0])
`AXISR_ASSIGN(axis_card_resp[0], axis_rdma_send[1])

// Tie-off unused
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();