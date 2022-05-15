`timescale 1ns / 1ps

`include "axi_macros.svh"
`include "lynx_macros.svh"

import lynxTypes::*;

/**
 * User logic
 * 
 */
module design_user_logic_0 (
    // AXI4L CONTROL
    // Slave control. Utilize this interface for any kind of CSR implementation.
    AXI4L.s                     axi_ctrl,

    // AXI4S HOST
    AXI4S.m                    axis_card_src,
    AXI4S.s                    axis_card_sink,

    // AXI4S RDMA
    AXI4S.m                     axis_rdma_src,
    AXI4S.s                     axis_rdma_sink,

    // FV
    rdmaIntf.s                  fv_sink,
    rdmaIntf.m                  fv_src,

    // Requests
    reqIntf.m                   bpss_rd_req,
    reqIntf.m                   bpss_rd_req,

    // RDMA
    reqIntf.s                   rd_req_rdma,
    reqIntf.s                   wr_req_rdma,

    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn
);

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
//always_comb axis_rdma_src.tie_off_m();
//always_comb axis_rdma_sink.tie_off_s();
//always_comb axis_card_src.tie_off_m();
//always_comb axis_card_sink.tie_off_s();
//always_comb fv_sink.tie_off_s();
//always_comb fv_src.tie_off_m();
//always_comb bpss_rd_req.tie_off_m();
//always_comb bpss_rd_req.tie_off_m();
always_comb rd_req_rdma.tie_off_s();
//always_comb wr_req_rdma.tie_off_s();

/* -- USER LOGIC -------------------------------------------------------- */

localparam integer QP_BITS = 24;
localparam integer PARAMS_BITS = VADDR_BITS + LEN_BITS + QP_BITS;

// Write - RDMA
`AXIS_ASSIGN(axis_rdma_sink, axis_card_src)
`REQ_ASSIGN(wr_req_rdma, bpss_rd_req)

// Read - Farview
metaIntf #(.DATA_BITS(PARAMS_BITS)) params_sink ();
metaIntf #(.DATA_BITS(PARAMS_BITS)) params_src ();

metaIntf #(.DATA_BITS(AXI_DATA_BITS)) cnfg ();

// Request handler
regex_req inst_regex_req (
    .aclk(aclk),
    .aresetn(aresetn),
    .fv_sink(fv_sink),
    .bpss_rd_req(bpss_rd_req),
    .params(params_sink),
    .cnfg(cnfg)
);

// Data handler
regex_data inst_regex_data (
    .aclk(aclk),
    .aresetn(aresetn),
    .axis_card_sink(axis_card_sink),
    .axis_rdma_src(axis_rdma_src),
    .fv_src(fv_src),
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

//create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.2 -module_name fifo_generator_512_shallow_sync
//set_property -dict [list CONFIG.Component_Name {fifo_generator_512_shallow_sync} CONFIG.INTERFACE_TYPE {AXI_STREAM} CONFIG.Reset_Type {Asynchronous_Reset} CONFIG.Full_Flags_Reset_Value {1} CONFIG.TDATA_NUM_BYTES {64} CONFIG.TSTRB_WIDTH {64} CONFIG.TKEEP_WIDTH {64} CONFIG.FIFO_Implementation_wach {Common_Clock_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_wach {15} CONFIG.Empty_Threshold_Assert_Value_wach {14} CONFIG.FIFO_Implementation_wrch {Common_Clock_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_wrch {15} CONFIG.Empty_Threshold_Assert_Value_wrch {14} CONFIG.FIFO_Implementation_rach {Common_Clock_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_rach {15} CONFIG.Empty_Threshold_Assert_Value_rach {14} CONFIG.Programmable_Full_Type_axis {Single_Programmable_Full_Threshold_Constant} CONFIG.Full_Threshold_Assert_Value_axis {126} CONFIG.Enable_Safety_Circuit {true}] [get_ips fifo_generator_512_shallow_sync]

//create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.2 -module_name fifo_generator_1byte_sync
//set_property -dict [list CONFIG.Component_Name {fifo_generator_1byte_sync} CONFIG.INTERFACE_TYPE {AXI_STREAM} CONFIG.Reset_Type {Asynchronous_Reset} CONFIG.Full_Flags_Reset_Value {1} CONFIG.TUSER_WIDTH {0} CONFIG.FIFO_Implementation_wach {Common_Clock_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_wach {15} CONFIG.Empty_Threshold_Assert_Value_wach {14} CONFIG.FIFO_Implementation_wrch {Common_Clock_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_wrch {15} CONFIG.Empty_Threshold_Assert_Value_wrch {14} CONFIG.FIFO_Implementation_rach {Common_Clock_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_rach {15} CONFIG.Empty_Threshold_Assert_Value_rach {14} CONFIG.Enable_Safety_Circuit {true}] [get_ips fifo_generator_1byte_sync]

//create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_512_1kD
//set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {1024} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_data_fifo_512_1kD}] [get_ips axis_data_fifo_512_1kD]

endmodule