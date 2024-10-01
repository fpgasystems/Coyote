/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

`timescale 1ns / 1ps

`define DBG_IBV

import lynxTypes::*;

/**
 * @brief   RoCE instantiation
 *
 * RoCE stack
 */
module roce_stack (
    input  logic                nclk,
    input  logic                nresetn,

    // Network interface
    AXI4S.s                     s_axis_rx,
    AXI4S.m                     m_axis_tx,

    // Control
    metaIntf.s                  s_rdma_qp_interface,
    metaIntf.s                  s_rdma_conn_interface,

    // User command
    metaIntf.s                  s_rdma_sq,
    metaIntf.m                  m_rdma_ack,

    // Memory
    metaIntf.m                  m_rdma_rd_req,
    metaIntf.m                  m_rdma_wr_req,
    AXI4S.s                     s_axis_rdma_rd_req,
    AXI4S.s                     s_axis_rdma_rd_rsp,
    AXI4S.m                     m_axis_rdma_wr,

    // IP
    input  logic [31:0]         local_ip_address,

    // Memory
    metaIntf.m                  m_rdma_mem_rd_cmd,
    metaIntf.m                  m_rdma_mem_wr_cmd,
    metaIntf.s                  s_rdma_mem_rd_sts,
    metaIntf.s                  s_rdma_mem_wr_sts,
    AXI4S.s                     s_axis_rdma_mem_rd,
    AXI4S.m                     m_axis_rdma_mem_wr,

    // Debug
    output logic                ibv_rx_pkg_count_valid,
    output logic [31:0]         ibv_rx_pkg_count_data,    
    output logic                ibv_tx_pkg_count_valid,
    output logic [31:0]         ibv_tx_pkg_count_data,    
    output logic                crc_drop_pkg_count_valid,
    output logic [31:0]         crc_drop_pkg_count_data,
    output logic                psn_drop_pkg_count_valid,
    output logic [31:0]         psn_drop_pkg_count_data,
    output logic                retrans_count_valid,
    output logic [31:0]         retrans_count_data
);

//
// SQ
//

metaIntf #(.STYPE(dreq_t)) rdma_sq ();
logic [RDMA_REQ_BITS-1:0] rdma_sq_data;

always_comb begin
  rdma_sq_data                                                      = 0;
  
  rdma_sq_data[0+:RDMA_OPCODE_BITS]                                 = rdma_sq.data.req_1.opcode;
  rdma_sq_data[32+:RDMA_QPN_BITS]                                   = {{RDMA_QPN_BITS-DEST_BITS-PID_BITS{1'b0}}, rdma_sq.data.req_1.vfid, rdma_sq.data.req_1.pid};
  rdma_sq_data[32+RDMA_QPN_BITS+0+:1]                               = rdma_sq.data.req_1.host;
  rdma_sq_data[32+RDMA_QPN_BITS+1+:1]                               = rdma_sq.data.req_1.last;
  rdma_sq_data[32+RDMA_QPN_BITS+2+:OFFS_BITS]                                 = rdma_sq.data.req_1.offs;
  rdma_sq_data[32+RDMA_QPN_BITS+2+OFFS_BITS+:RDMA_VADDR_BITS]                 = 
    {16'h0000, rdma_sq.data.req_1.vaddr};
  rdma_sq_data[32+RDMA_QPN_BITS+2+OFFS_BITS+RDMA_VADDR_BITS+:RDMA_VADDR_BITS] = 
    {10'h000, rdma_sq.data.req_2.strm, rdma_sq.data.req_1.dest, rdma_sq.data.req_2.vaddr};
  rdma_sq_data[32+RDMA_QPN_BITS+2+OFFS_BITS+2*RDMA_VADDR_BITS+:RDMA_LEN_BITS] = rdma_sq.data.req_1.len;
  rdma_sq_data[32+RDMA_QPN_BITS+2+OFFS_BITS+2*RDMA_VADDR_BITS+RDMA_LEN_BITS+:RDMA_IMM_BITS] = {rdma_sq.data.req_2.offs[3:0], rdma_sq.data.req_2.len};
end

//
// FC and CQ
//

metaIntf #(.STYPE(dack_t)) rdma_ack ();
logic [RDMA_ACK_BITS-1:0] ack_meta_data;

assign rdma_ack.data.ack.opcode = ack_meta_data[0+:OPCODE_BITS];
assign rdma_ack.data.ack.remote = 1'b1;
assign rdma_ack.data.ack.pid  = ack_meta_data[32+:PID_BITS];
assign rdma_ack.data.ack.vfid = ack_meta_data[32+PID_BITS+:DEST_BITS];
assign rdma_ack.data.ack.host = ack_meta_data[32+RDMA_QPN_BITS+:1];
assign rdma_ack.data.ack.dest = ack_meta_data[32+RDMA_QPN_BITS+1+:DEST_BITS];
assign rdma_ack.data.ack.strm = ack_meta_data[32+RDMA_QPN_BITS+1+DEST_BITS+:STRM_BITS];
assign rdma_ack.data.ack.rsrvd = 0;
assign rdma_ack.data.last = ack_meta_data[32+RDMA_QPN_BITS+1+DEST_BITS+STRM_BITS+:1];

rdma_flow inst_rdma_flow (
    .aclk(nclk),
    .aresetn(nresetn),
    .s_req(s_rdma_sq),
    .m_req(rdma_sq),
    .s_ack(rdma_ack),
    .m_ack(m_rdma_ack)
);

// Definition of the AXI-bus from roce-ip to icrc 
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) roce_to_icrc();

// Integrate the ICRC-module on the outgoing datapath 
icrc inst_icrc (
    .m_axis_rx(roce_to_icrc), 
    .m_axis_tx(m_axis_tx), 
    .nclk(nclk), 
    .nresetn(nresetn)
);


// 
// BUFF RQ
//

metaIntf #(.STYPE(req_t)) rdma_rd_req ();
metaIntf #(.STYPE(req_t)) rdma_wr_req ();
logic [RDMA_BASE_REQ_BITS-1:0] rd_cmd_data;
logic [RDMA_BASE_REQ_BITS-1:0] wr_cmd_data;

AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_rdma_rd ();

// RD
assign rdma_rd_req.data.opcode            = rd_cmd_data[0+:OPCODE_BITS];
assign rdma_rd_req.data.mode              = RDMA_MODE_RAW;
assign rdma_rd_req.data.rdma              = 1'b1;
assign rdma_rd_req.data.remote            = 1'b0;

assign rdma_rd_req.data.pid               = rd_cmd_data[32+:PID_BITS];
assign rdma_rd_req.data.vfid              = rd_cmd_data[32+PID_BITS+:DEST_BITS];

assign rdma_rd_req.data.last              = rd_cmd_data[32+RDMA_QPN_BITS+0+:1];
assign rdma_rd_req.data.vaddr             = rd_cmd_data[32+RDMA_QPN_BITS+1+:VADDR_BITS];
assign rdma_rd_req.data.dest              = rd_cmd_data[32+RDMA_QPN_BITS+1+VADDR_BITS+:DEST_BITS];
assign rdma_rd_req.data.strm              = rd_cmd_data[32+RDMA_QPN_BITS+1+VADDR_BITS+DEST_BITS+:STRM_BITS];
assign rdma_rd_req.data.len               = rd_cmd_data[32+RDMA_QPN_BITS+1+VADDR_BITS+DEST_BITS+STRM_BITS+:LEN_BITS];
assign rdma_rd_req.data.actv              = rd_cmd_data[32+RDMA_QPN_BITS+1+VADDR_BITS+DEST_BITS+STRM_BITS+LEN_BITS+0+:1];
assign rdma_rd_req.data.host              = rd_cmd_data[32+RDMA_QPN_BITS+1+VADDR_BITS+DEST_BITS+STRM_BITS+LEN_BITS+1+:1];
assign rdma_rd_req.data.offs              = rd_cmd_data[32+RDMA_QPN_BITS+1+VADDR_BITS+DEST_BITS+STRM_BITS+LEN_BITS+2+:OFFS_BITS];

// WR
assign rdma_wr_req.data.opcode            = wr_cmd_data[0+:OPCODE_BITS];
assign rdma_wr_req.data.mode              = RDMA_MODE_RAW;
assign rdma_wr_req.data.rdma              = 1'b1;
assign rdma_wr_req.data.remote            = 1'b0;

assign rdma_wr_req.data.pid               = wr_cmd_data[32+:PID_BITS];
assign rdma_wr_req.data.vfid              = wr_cmd_data[32+PID_BITS+:DEST_BITS];

assign rdma_wr_req.data.last              = wr_cmd_data[32+RDMA_QPN_BITS+0+:1];
assign rdma_wr_req.data.vaddr             = wr_cmd_data[32+RDMA_QPN_BITS+1+:VADDR_BITS];
assign rdma_wr_req.data.dest              = wr_cmd_data[32+RDMA_QPN_BITS+1+VADDR_BITS+:DEST_BITS];
assign rdma_wr_req.data.strm              = wr_cmd_data[32+RDMA_QPN_BITS+1+VADDR_BITS+DEST_BITS+:STRM_BITS];
assign rdma_wr_req.data.len               = wr_cmd_data[32+RDMA_QPN_BITS+1+VADDR_BITS+DEST_BITS+STRM_BITS+:LEN_BITS];
assign rdma_wr_req.data.actv              = wr_cmd_data[32+RDMA_QPN_BITS+1+VADDR_BITS+DEST_BITS+STRM_BITS+LEN_BITS+0+:1];
assign rdma_wr_req.data.host              = wr_cmd_data[32+RDMA_QPN_BITS+1+VADDR_BITS+DEST_BITS+STRM_BITS+LEN_BITS+1+:1];
assign rdma_wr_req.data.offs              = wr_cmd_data[32+RDMA_QPN_BITS+1+VADDR_BITS+DEST_BITS+STRM_BITS+LEN_BITS+2+:OFFS_BITS];

// Retransmission mux (buffering)
rdma_mux_retrans inst_mux_retrans (
  .aclk(nclk),
  .aresetn(nresetn),

  .s_req_net(rdma_rd_req),
  .m_req_user(m_rdma_rd_req),

  .s_axis_user_req(s_axis_rdma_rd_req),
  .s_axis_user_rsp(s_axis_rdma_rd_rsp),
  .m_axis_net(axis_rdma_rd),
  
  .m_req_ddr_rd(m_rdma_mem_rd_cmd),
  .m_req_ddr_wr(m_rdma_mem_wr_cmd),
  .s_axis_ddr(s_axis_rdma_mem_rd),
  .m_axis_ddr(m_axis_rdma_mem_wr)
);  

assign s_rdma_mem_rd_sts.ready = 1'b1;
assign s_rdma_mem_wr_sts.ready = 1'b1;

assign m_rdma_wr_req.valid = rdma_wr_req.valid;
assign m_rdma_wr_req.data = rdma_wr_req.data;
assign rdma_wr_req.ready = m_rdma_wr_req.ready;

//
// RoCE stack
//


/* ila_rdma inst_ila_rdma (
  .clk(nclk),

  .probe0(s_rdma_sq.valid),
  .probe1(s_rdma_sq.ready),
  .probe2(rdma_sq.valid),
  .probe3(rdma_sq.ready),
  .probe4(s_rdma_sq.data.req_1), // 128
  .probe5(s_rdma_sq.data.req_2), // 128
  .probe6(rdma_ack.valid),
  .probe7(rdma_ack.ready),
  .probe8(rdma_ack.data.ack), // 32
  .probe9(rdma_ack.data.last),
  .probe10(rdma_rd_req.valid),
  .probe11(rdma_rd_req.ready),
  .probe12(rdma_wr_req.valid),
  .probe13(rdma_wr_req.ready),
  .probe14(m_axis_rdma_wr.tvalid),
  .probe15(m_axis_rdma_wr.tready),
  .probe16(m_axis_rdma_wr.tlast),
  .probe17(axis_rdma_rd.tvalid),
  .probe18(axis_rdma_rd.tready),
  .probe19(axis_rdma_rd.tlast),
  .probe20(m_rdma_mem_rd_cmd.valid),
  .probe21(m_rdma_mem_rd_cmd.ready),
  .probe22(m_rdma_mem_rd_cmd.data), // 96
  .probe23(m_rdma_mem_wr_cmd.valid),
  .probe24(m_rdma_mem_wr_cmd.ready),
  .probe25(m_rdma_mem_wr_cmd.data), // 96
  .probe26(s_axis_rdma_mem_rd.tvalid),
  .probe27(s_axis_rdma_mem_rd.tready),
  .probe28(s_axis_rdma_mem_rd.tlast),
  .probe29(m_axis_rdma_mem_wr.tvalid),
  .probe30(m_axis_rdma_mem_wr.tready),
  .probe31(m_axis_rdma_mem_wr.tlast),
  .probe32(s_rdma_qp_interface.valid),
  .probe33(s_rdma_qp_interface.ready),
  .probe34(s_rdma_conn_interface.valid),
  .probe35(s_rdma_conn_interface.ready),
  .probe36(rdma_rd_req.data), // 128
); */ 


metaIntf #(.STYPE(logic[103:0])) m_axis_dbg_0 ();
metaIntf #(.STYPE(logic[103:0])) m_axis_dbg_1 ();
metaIntf #(.STYPE(logic[103:0])) m_axis_dbg_2 ();
assign m_axis_dbg_0.ready = 1'b1;
assign m_axis_dbg_1.ready = 1'b1;
assign m_axis_dbg_2.ready = 1'b1;

rocev2_ip rocev2_inst(
    .ap_clk(nclk), // input aclk
    .ap_rst_n(nresetn), // input aresetn
    
`ifdef VITIS_HLS

    // Debug
`ifdef DBG_IBV
    .m_axis_dbg_0_TVALID(m_axis_dbg_0.valid),
    .m_axis_dbg_0_TREADY(m_axis_dbg_0.ready),
    .m_axis_dbg_0_TDATA(m_axis_dbg_0.data),
    
    .m_axis_dbg_1_TVALID(m_axis_dbg_1.valid),
    .m_axis_dbg_1_TREADY(m_axis_dbg_1.ready),
    .m_axis_dbg_1_TDATA(m_axis_dbg_1.data),
    
    .m_axis_dbg_2_TVALID(m_axis_dbg_2.valid),
    .m_axis_dbg_2_TREADY(m_axis_dbg_2.ready),
    .m_axis_dbg_2_TDATA(m_axis_dbg_2.data),
`endif

    // RX
    .s_axis_rx_data_TVALID(s_axis_rx.tvalid),
    .s_axis_rx_data_TREADY(s_axis_rx.tready),
    .s_axis_rx_data_TDATA(s_axis_rx.tdata),
    .s_axis_rx_data_TKEEP(s_axis_rx.tkeep),
    .s_axis_rx_data_TLAST(s_axis_rx.tlast),
    
    // TX
    .m_axis_tx_data_TVALID(roce_to_icrc.tvalid),
    .m_axis_tx_data_TREADY(roce_to_icrc.tready),
    .m_axis_tx_data_TDATA(roce_to_icrc.tdata),
    .m_axis_tx_data_TKEEP(roce_to_icrc.tkeep),
    .m_axis_tx_data_TLAST(roce_to_icrc.tlast),
    
    // User commands    
    .s_axis_sq_meta_TVALID(rdma_sq.valid),
    .s_axis_sq_meta_TREADY(rdma_sq.ready),
    .s_axis_sq_meta_TDATA(rdma_sq_data), 
    
    // Memory
    // Write commands
    .m_axis_mem_write_cmd_TVALID(rdma_wr_req.valid),
    .m_axis_mem_write_cmd_TREADY(rdma_wr_req.ready),
    //.m_axis_mem_write_cmd_TDATA(m_rdma_wr_req.data),
    .m_axis_mem_write_cmd_TDATA(wr_cmd_data),
    // Read commands
    .m_axis_mem_read_cmd_TVALID(rdma_rd_req.valid),
    .m_axis_mem_read_cmd_TREADY(rdma_rd_req.ready),
    //.m_axis_mem_read_cmd_TDATA(rdma_rd_req.data),
    .m_axis_mem_read_cmd_TDATA(rd_cmd_data),
    // Write data
    .m_axis_mem_write_data_TVALID(m_axis_rdma_wr.tvalid),
    .m_axis_mem_write_data_TREADY(m_axis_rdma_wr.tready),
    .m_axis_mem_write_data_TDATA(m_axis_rdma_wr.tdata),
    .m_axis_mem_write_data_TKEEP(m_axis_rdma_wr.tkeep),
    .m_axis_mem_write_data_TLAST(m_axis_rdma_wr.tlast),
    // Read data
    .s_axis_mem_read_data_TVALID(axis_rdma_rd.tvalid),
    .s_axis_mem_read_data_TREADY(axis_rdma_rd.tready),
    .s_axis_mem_read_data_TDATA(axis_rdma_rd.tdata),
    .s_axis_mem_read_data_TKEEP(axis_rdma_rd.tkeep),
    .s_axis_mem_read_data_TLAST(axis_rdma_rd.tlast),

    // QP intf
    .s_axis_qp_interface_TVALID(s_rdma_qp_interface.valid),
    .s_axis_qp_interface_TREADY(s_rdma_qp_interface.ready),
    .s_axis_qp_interface_TDATA(s_rdma_qp_interface.data),
    .s_axis_qp_conn_interface_TVALID(s_rdma_conn_interface.valid),
    .s_axis_qp_conn_interface_TREADY(s_rdma_conn_interface.ready),
    .s_axis_qp_conn_interface_TDATA(s_rdma_conn_interface.data),

    // ACK
    .m_axis_rx_ack_meta_TVALID(rdma_ack.valid),
    .m_axis_rx_ack_meta_TREADY(rdma_ack.ready),
    .m_axis_rx_ack_meta_TDATA(ack_meta_data),

    // IP
    .local_ip_address({local_ip_address,local_ip_address,local_ip_address,local_ip_address}), //Use IPv4 addr
    
    // DBG
    .regIbvCountRx(ibv_rx_pkg_count_data),
    .regIbvCountRx_ap_vld(ibv_rx_pkg_count_valid),
    .regIbvCountTx(ibv_tx_pkg_count_data),
    .regIbvCountTx_ap_vld(ibv_tx_pkg_count_valid),
    .regCrcDropPkgCount(crc_drop_pkg_count_data),
    .regCrcDropPkgCount_ap_vld(crc_drop_pkg_count_valid),
    .regInvalidPsnDropCount(psn_drop_pkg_count_data),
    .regInvalidPsnDropCount_ap_vld(psn_drop_pkg_count_valid),
    .regRetransCount(retrans_count_data),
    .regRetransCount_ap_vld(retrans_count_valid)
    
`else

    // Debug
`ifdef DBG_IBV
`endif

    // RX
    .s_axis_rx_data_TVALID(s_axis_rx.tvalid),
    .s_axis_rx_data_TREADY(s_axis_rx.tready),
    .s_axis_rx_data_TDATA(s_axis_rx.tdata),
    .s_axis_rx_data_TKEEP(s_axis_rx.tkeep),
    .s_axis_rx_data_TLAST(s_axis_rx.tlast),
    
    // TX
    .m_axis_tx_data_TVALID(roce_to_icrc.tvalid),
    .m_axis_tx_data_TREADY(roce_to_icrc.tready),
    .m_axis_tx_data_TDATA(roce_to_icrc.tdata),
    .m_axis_tx_data_TKEEP(roce_to_icrc.tkeep),
    .m_axis_tx_data_TLAST(roce_to_icrc.tlast),
    
    // User commands    
    .s_axis_sq_meta_V_TVALID(rdma_sq.valid),
    .s_axis_sq_meta_V_TREADY(rdma_sq.ready),
    .s_axis_sq_meta_V_TDATA(rdma_sq_data), 
    
    // Memory
    // Write commands
    .m_axis_mem_write_cmd_V_TVALID(rdma_wr_req.valid),
    .m_axis_mem_write_cmd_V_TREADY(rdma_wr_req.ready),
    //.m_axis_mem_write_cmd_V_TDATA(m_rdma_wr_req.data),
    .m_axis_mem_write_cmd_V_TDATA(wr_cmd_data),
    // Read commands
    .m_axis_mem_read_cmd_V_TVALID(rdma_rd_req.valid),
    .m_axis_mem_read_cmd_V_TREADY(rdma_rd_req.ready),
    //.m_axis_mem_read_cmd_V_TDATA(rdma_rd_req.data),
    .m_axis_mem_read_cmd_V_TDATA(rd_cmd_data),
    // Write data
    .m_axis_mem_write_data_TVALID(m_axis_rdma_wr.tvalid),
    .m_axis_mem_write_data_TREADY(m_axis_rdma_wr.tready),
    .m_axis_mem_write_data_TDATA(m_axis_rdma_wr.tdata),
    .m_axis_mem_write_data_TKEEP(m_axis_rdma_wr.tkeep),
    .m_axis_mem_write_data_TLAST(m_axis_rdma_wr.tlast),
    // Read data
    .s_axis_mem_read_data_TVALID(axis_rdma_rd.tvalid),
    .s_axis_mem_read_data_TREADY(axis_rdma_rd.tready),
    .s_axis_mem_read_data_TDATA(axis_rdma_rd.tdata),
    .s_axis_mem_read_data_TKEEP(axis_rdma_rd.tkeep),
    .s_axis_mem_read_data_TLAST(axis_rdma_rd.tlast),

    // QP intf
    .s_axis_qp_interface_V_TVALID(s_rdma_qp_interface.valid),
    .s_axis_qp_interface_V_TREADY(s_rdma_qp_interface.ready),
    .s_axis_qp_interface_V_TDATA(s_rdma_qp_interface.data),
    .s_axis_qp_conn_interface_V_TVALID(s_rdma_conn_interface.valid),
    .s_axis_qp_conn_interface_V_TREADY(s_rdma_conn_interface.ready),
    .s_axis_qp_conn_interface_V_TDATA(s_rdma_conn_interface.data),

    // ACK
    .m_axis_rx_ack_meta_V_TVALID(rdma_ack.valid),
    .m_axis_rx_ack_meta_V_TREADY(rdma_ack.ready),
    .m_axis_rx_ack_meta_V_TDATA(ack_meta_data),

    // IP
    .local_ip_address_V({local_ip_address,local_ip_address,local_ip_address,local_ip_address}), //Use IPv4 addr

    .regIbvCountRx_V(ibv_rx_pkg_count_data),
    .regIbvCountRx_V_ap_vld(ibv_rx_pkg_count_valid),
    .regIbvCountTx_V(ibv_tx_pkg_count_data),
    .regIbvCountTx_V_ap_vld(ibv_tx_pkg_count_valid),
    .regCrcDropPkgCount_V(crc_drop_pkg_count_data),
    .regCrcDropPkgCount_V_ap_vld(crc_drop_pkg_count_valid),
    .regInvalidPsnDropCount_V(psn_drop_pkg_count_data),
    .regInvalidPsnDropCount_V_ap_vld(psn_drop_pkg_count_valid),
    .regRetransCount_V(retrans_count_data),
    .regRetransCount_V_ap_vld(retrans_count_valid)

`endif
);


endmodule