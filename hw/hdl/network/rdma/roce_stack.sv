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

    // User command
    metaIntf.s                  s_rdma_sq,
    metaIntf.m                  m_rdma_ack,

    // Memory
    metaIntf.m                  m_rdma_rd_req,
    metaIntf.m                  m_rdma_wr_req,
    AXI4S.s                     s_axis_rdma_rd,
    AXI4S.m                     m_axis_rdma_wr,

    // Control
    metaIntf.s                  s_rdma_qp_interface,
    metaIntf.s                  s_rdma_conn_interface,
    input  logic [31:0]         local_ip_address,

    output logic                ibv_rx_pkg_count_valid,
    output logic[31:0]          ibv_rx_pkg_count_data,    
    output logic                ibv_tx_pkg_count_valid,
    output logic[31:0]          ibv_tx_pkg_count_data,    
    output logic                crc_drop_pkg_count_valid,
    output logic[31:0]          crc_drop_pkg_count_data,
    output logic                psn_drop_pkg_count_valid,
    output logic[31:0]          psn_drop_pkg_count_data
);

//
// Assign
//

// SQ
metaIntf #(.STYPE(rdma_req_t)) rdma_sq ();
`ifdef VITIS_HLS
    logic [RDMA_REQ_BITS+32-RDMA_OPCODE_BITS-1:0] rdma_sq_data;
`else
    logic [RDMA_REQ_BITS-1:0] rdma_sq_data;
`endif

always_comb begin
`ifdef VITIS_HLS
  rdma_sq_data                                        = 0;
  rdma_sq_data[0+:RDMA_OPCODE_BITS]                   = rdma_sq.data.opcode;
  rdma_sq_data[32+:RDMA_QPN_BITS]                     = rdma_sq.data.qpn;
  rdma_sq_data[32+RDMA_QPN_BITS]                      = rdma_sq.data.host;
  rdma_sq_data[32+RDMA_QPN_BITS+1]                    = rdma_sq.data.mode;
  rdma_sq_data[32+RDMA_QPN_BITS+1+:RDMA_MSG_BITS]     = rdma_sq.data.msg;
`else
  rdma_sq_data                                        = 0;
  rdma_sq_data[0+:RDMA_OPCODE_BITS]                   = rdma_sq.data.opcode;
  rdma_sq_data[RDMA_OPCODE_BITS+:RDMA_QPN_BITS]       = rdma_sq.data.qpn;
  rdma_sq_data[RDMA_OPCODE_BITS+RDMA_QPN_BITS]        = rdma_sq.data.host;
  rdma_sq_data[RDMA_OPCODE_BITS+RDMA_QPN_BITS+1]      = rdma_sq.data.mode;
  rdma_sq_data[RDMA_OPCODE_BITS+RDMA_QPN_BITS+1+:RDMA_MSG_BITS]  = rdma_sq.data.msg;
`endif
end

// RD and WR cmd
logic [RDMA_BASE_REQ_BITS-1:0] rd_cmd_data;
logic [RDMA_BASE_REQ_BITS-1:0] wr_cmd_data;

assign m_rdma_rd_req.data.vaddr             = rd_cmd_data[0+:VADDR_BITS];
assign m_rdma_rd_req.data.len               = rd_cmd_data[VADDR_BITS+:LEN_BITS];
assign m_rdma_rd_req.data.stream            = rd_cmd_data[VADDR_BITS+LEN_BITS+:1];
assign m_rdma_rd_req.data.sync              = rd_cmd_data[VADDR_BITS+LEN_BITS+1+:1];
assign m_rdma_rd_req.data.ctl               = rd_cmd_data[VADDR_BITS+LEN_BITS+2+:1];
assign m_rdma_rd_req.data.host              = rd_cmd_data[VADDR_BITS+LEN_BITS+3+:1];
assign m_rdma_rd_req.data.dest              = rd_cmd_data[VADDR_BITS+LEN_BITS+4+:DEST_BITS];
assign m_rdma_rd_req.data.pid               = rd_cmd_data[VADDR_BITS+LEN_BITS+4+DEST_BITS+:PID_BITS];
assign m_rdma_rd_req.data.vfid              = rd_cmd_data[VADDR_BITS+LEN_BITS+4+DEST_BITS+PID_BITS+:N_REGIONS_BITS];

assign m_rdma_wr_req.data.vaddr             = wr_cmd_data[0+:VADDR_BITS];
assign m_rdma_wr_req.data.len               = wr_cmd_data[VADDR_BITS+:LEN_BITS];
assign m_rdma_wr_req.data.stream            = wr_cmd_data[VADDR_BITS+LEN_BITS+:1];
assign m_rdma_wr_req.data.sync              = wr_cmd_data[VADDR_BITS+LEN_BITS+1+:1];
assign m_rdma_wr_req.data.ctl               = wr_cmd_data[VADDR_BITS+LEN_BITS+2+:1];
assign m_rdma_wr_req.data.host              = wr_cmd_data[VADDR_BITS+LEN_BITS+3+:1];
assign m_rdma_wr_req.data.dest              = wr_cmd_data[VADDR_BITS+LEN_BITS+4+:DEST_BITS];
assign m_rdma_wr_req.data.pid               = wr_cmd_data[VADDR_BITS+LEN_BITS+4+DEST_BITS+:PID_BITS];
assign m_rdma_wr_req.data.vfid              = wr_cmd_data[VADDR_BITS+LEN_BITS+4+DEST_BITS+PID_BITS+:N_REGIONS_BITS];

// DBG
logic [31:0] ibv_rx_count;
logic ibv_rx_count_valid;

// ACKs
metaIntf #(.STYPE(rdma_ack_t)) rdma_ack ();
logic [RDMA_ACK_BITS-1:0] ack_meta_data;
assign rdma_ack.data.rd = ack_meta_data[0];
assign rdma_ack.data.pid = ack_meta_data[1+:PID_BITS];
assign rdma_ack.data.vfid = ack_meta_data[1+PID_BITS+:N_REGIONS_BITS]; 
assign rdma_ack.data.psn = ack_meta_data[1+RDMA_ACK_QPN_BITS+:RDMA_ACK_PSN_BITS];

assign m_rdma_ack.data = rdma_ack.data;
assign m_rdma_ack.valid = rdma_ack.valid;

// MSN flow control
rdma_msn inst_rdma_msn (
    .aclk(nclk),
    .aresetn(nresetn),
    .s_req(s_rdma_sq),
    .m_req(rdma_sq),
    .s_ack(rdma_ack)
);

`ifdef DBG_IBV

metaIntf #(.STYPE(logic[25:0])) m_axis_dbg_0 ();
metaIntf #(.STYPE(logic[25:0])) m_axis_dbg_1 ();
metaIntf #(.STYPE(logic[25:0])) m_axis_dbg_2 ();
metaIntf #(.STYPE(logic[25:0])) m_axis_dbg_3 ();
assign m_axis_dbg_0.ready = 1'b1;
assign m_axis_dbg_1.ready = 1'b1;
assign m_axis_dbg_2.ready = 1'b1;
assign m_axis_dbg_3.ready = 1'b1;

logic [15:0] cnt_dbg_0;
logic [15:0] cnt_dbg_1;
logic [15:0] cnt_dbg_2;
logic [15:0] cnt_dbg_3;

always_ff @(posedge nclk) begin
    if(~nresetn) begin
        cnt_dbg_0 <= 0;
        cnt_dbg_1 <= 0;
        cnt_dbg_2 <= 0;
        cnt_dbg_3 <= 0;
    end
    else begin
        cnt_dbg_0 <= m_axis_dbg_0.valid ? cnt_dbg_0 + 1 : cnt_dbg_0;
        cnt_dbg_1 <= m_axis_dbg_1.valid ? cnt_dbg_1 + 1 : cnt_dbg_1;
        cnt_dbg_2 <= m_axis_dbg_2.valid ? cnt_dbg_2 + 1 : cnt_dbg_2;
        cnt_dbg_3 <= m_axis_dbg_3.valid ? cnt_dbg_3 + 1 : cnt_dbg_3;
    end
end
/*
ila_dbg inst_ila_dbg (
  .clk(nclk),
  .probe0(m_axis_dbg_0.valid),
  .probe1(m_axis_dbg_0.data[0+:24]), // 24
  .probe2(m_axis_dbg_0.data[24+:2]), // 2
  .probe3(m_axis_dbg_1.valid),
  .probe4(m_axis_dbg_1.data[0+:24]), // 24
  .probe5(m_axis_dbg_1.data[24+:2]), // 2
  .probe6(m_axis_dbg_2.valid),
  .probe7(m_axis_dbg_2.data[0+:24]), // 24
  .probe8(m_axis_dbg_2.data[24+:2]), // 2
  .probe9(m_axis_dbg_3.valid),
  .probe10(m_axis_dbg_3.data[0+:24]), // 24
  .probe11(m_axis_dbg_3.data[24+:2]), // 2
  .probe12(cnt_dbg_0), // 16
  .probe13(cnt_dbg_1), // 16
  .probe14(cnt_dbg_2), // 16
  .probe15(cnt_dbg_3)  // 16
);
*/
logic [31:0] cnt_wr_cmd;
logic [31:0] cnt_rd_cmd;
logic [31:0] cnt_wr_data;
logic [31:0] cnt_wr_pck;
logic [31:0] cnt_rd_data;
logic [31:0] cnt_rd_pck;

always_ff @(posedge nclk) begin
    if(~nresetn) begin
        cnt_wr_cmd <= 0;
        cnt_rd_cmd <= 0;
        cnt_wr_data <= 0;
        cnt_wr_pck <= 0;
        cnt_rd_data <= 0;
        cnt_rd_pck <= 0;
    end
    else begin
        cnt_wr_cmd <= (m_rdma_wr_req.valid & m_rdma_wr_req.ready) ? cnt_wr_cmd + 1 : cnt_wr_cmd;
        cnt_rd_cmd <= (m_rdma_rd_req.valid & m_rdma_rd_req.ready) ? cnt_rd_cmd + 1 : cnt_rd_cmd;
        
        cnt_wr_data <= (m_axis_rdma_wr.tvalid & m_axis_rdma_wr.tready) ? cnt_wr_data + 1 : cnt_wr_data;
        cnt_wr_pck <= (m_axis_rdma_wr.tvalid & m_axis_rdma_wr.tready & m_axis_rdma_wr.tlast) ? cnt_wr_pck + 1 : cnt_wr_pck;
        cnt_rd_data <= (s_axis_rdma_rd.tvalid & s_axis_rdma_rd.tready) ? cnt_rd_data + 1 : cnt_rd_data;
        cnt_rd_pck <= (s_axis_rdma_rd.tvalid & s_axis_rdma_rd.tready & s_axis_rdma_rd.tlast) ? cnt_rd_pck + 1 : cnt_rd_pck;
    end
end 

vio_rd_data inst_vio_rd_data (
    .clk(nclk),
    .probe_in0(cnt_wr_cmd), // 32
    .probe_in1(cnt_wr_data), // 32
    .probe_in2(cnt_wr_pck), // 32
    .probe_in3(cnt_rd_data), // 32
    .probe_in4(cnt_rd_pck), // 32
    .probe_in5(cnt_rd_cmd), // 32
    .probe_in6(m_rdma_wr_req.ready),
    .probe_in7(m_rdma_wr_req.valid),
    .probe_in8(m_axis_rdma_wr.tready),
    .probe_in9(m_axis_rdma_wr.tvalid),
    .probe_in10(m_rdma_rd_req.ready),
    .probe_in11(m_rdma_rd_req.valid),
    .probe_in12(s_axis_rdma_rd.tready),
    .probe_in13(s_axis_rdma_rd.tvalid)
);

`endif

// RoCE stack
rocev2_ip rocev2_inst(
    .ap_clk(nclk), // input aclk
    .ap_rst_n(nresetn), // input aresetn
    
`ifdef VITIS_HLS
    // RX
    .s_axis_rx_data_TVALID(s_axis_rx.tvalid),
    .s_axis_rx_data_TREADY(s_axis_rx.tready),
    .s_axis_rx_data_TDATA(s_axis_rx.tdata),
    .s_axis_rx_data_TKEEP(s_axis_rx.tkeep),
    .s_axis_rx_data_TLAST(s_axis_rx.tlast),
    
    // TX
    .m_axis_tx_data_TVALID(m_axis_tx.tvalid),
    .m_axis_tx_data_TREADY(m_axis_tx.tready),
    .m_axis_tx_data_TDATA(m_axis_tx.tdata),
    .m_axis_tx_data_TKEEP(m_axis_tx.tkeep),
    .m_axis_tx_data_TLAST(m_axis_tx.tlast),
    
    // User commands    
    .s_axis_sq_meta_TVALID(rdma_sq.valid),
    .s_axis_sq_meta_TREADY(rdma_sq.ready),
    .s_axis_sq_meta_TDATA(rdma_sq_data), 
    
    // Memory
    // Write commands
    .m_axis_mem_write_cmd_TVALID(m_rdma_wr_req.valid),
    .m_axis_mem_write_cmd_TREADY(m_rdma_wr_req.ready),
    //.m_axis_mem_write_cmd_TDATA(m_rdma_wr_req.data),
    .m_axis_mem_write_cmd_TDATA(wr_cmd_data),
    // Read commands
    .m_axis_mem_read_cmd_TVALID(m_rdma_rd_req.valid),
    .m_axis_mem_read_cmd_TREADY(m_rdma_rd_req.ready),
    //.m_axis_mem_read_cmd_TDATA(m_rdma_rd_req.data),
    .m_axis_mem_read_cmd_TDATA(rd_cmd_data),
    // Write data
    .m_axis_mem_write_data_TVALID(m_axis_rdma_wr.tvalid),
    .m_axis_mem_write_data_TREADY(m_axis_rdma_wr.tready),
    .m_axis_mem_write_data_TDATA(m_axis_rdma_wr.tdata),
    .m_axis_mem_write_data_TKEEP(m_axis_rdma_wr.tkeep),
    .m_axis_mem_write_data_TLAST(m_axis_rdma_wr.tlast),
    // Read data
    .s_axis_mem_read_data_TVALID(s_axis_rdma_rd.tvalid),
    .s_axis_mem_read_data_TREADY(s_axis_rdma_rd.tready),
    .s_axis_mem_read_data_TDATA(s_axis_rdma_rd.tdata),
    .s_axis_mem_read_data_TKEEP(s_axis_rdma_rd.tkeep),
    .s_axis_mem_read_data_TLAST(s_axis_rdma_rd.tlast),

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
    .m_axis_dbg_3_TVALID(m_axis_dbg_3.valid),
    .m_axis_dbg_3_TREADY(m_axis_dbg_3.ready),
    .m_axis_dbg_3_TDATA(m_axis_dbg_3.data),
`endif


    .regIbvCountRx(ibv_rx_pkg_count_data),
    .regIbvCountRx_ap_vld(ibv_rx_pkg_count_valid),
    .regIbvCountTx(ibv_tx_pkg_count_data),
    .regIbvCountTx_ap_vld(ibv_tx_pkg_count_valid),
    .regCrcDropPkgCount(crc_drop_pkg_count_data),
    .regCrcDropPkgCount_ap_vld(crc_drop_pkg_count_valid),
    .regInvalidPsnDropCount(psn_drop_pkg_count_data),
    .regInvalidPsnDropCount_ap_vld(psn_drop_pkg_count_valid)
    
`else
    // RX
    .s_axis_rx_data_TVALID(s_axis_rx.tvalid),
    .s_axis_rx_data_TREADY(s_axis_rx.tready),
    .s_axis_rx_data_TDATA(s_axis_rx.tdata),
    .s_axis_rx_data_TKEEP(s_axis_rx.tkeep),
    .s_axis_rx_data_TLAST(s_axis_rx.tlast),
    
    // TX
    .m_axis_tx_data_TVALID(m_axis_tx.tvalid),
    .m_axis_tx_data_TREADY(m_axis_tx.tready),
    .m_axis_tx_data_TDATA(m_axis_tx.tdata),
    .m_axis_tx_data_TKEEP(m_axis_tx.tkeep),
    .m_axis_tx_data_TLAST(m_axis_tx.tlast),
    
    // User commands    
    .s_axis_sq_meta_V_TVALID(rdma_sq.valid),
    .s_axis_sq_meta_V_TREADY(rdma_sq.ready),
    .s_axis_sq_meta_V_TDATA(rdma_sq_data), 
    
    // Memory
    // Write commands
    .m_axis_mem_write_cmd_V_TVALID(m_rdma_wr_req.valid),
    .m_axis_mem_write_cmd_V_TREADY(m_rdma_wr_req.ready),
    //.m_axis_mem_write_cmd_V_TDATA(m_rdma_wr_req.data),
    .m_axis_mem_write_cmd_V_TDATA(wr_cmd_data),
    // Read commands
    .m_axis_mem_read_cmd_V_TVALID(m_rdma_rd_req.valid),
    .m_axis_mem_read_cmd_V_TREADY(m_rdma_rd_req.ready),
    //.m_axis_mem_read_cmd_V_TDATA(m_rdma_rd_req.data),
    .m_axis_mem_read_cmd_V_TDATA(rd_cmd_data),
    // Write data
    .m_axis_mem_write_data_TVALID(m_axis_rdma_wr.tvalid),
    .m_axis_mem_write_data_TREADY(m_axis_rdma_wr.tready),
    .m_axis_mem_write_data_TDATA(m_axis_rdma_wr.tdata),
    .m_axis_mem_write_data_TKEEP(m_axis_rdma_wr.tkeep),
    .m_axis_mem_write_data_TLAST(m_axis_rdma_wr.tlast),
    // Read data
    .s_axis_mem_read_data_TVALID(s_axis_rdma_rd.tvalid),
    .s_axis_mem_read_data_TREADY(s_axis_rdma_rd.tready),
    .s_axis_mem_read_data_TDATA(s_axis_rdma_rd.tdata),
    .s_axis_mem_read_data_TKEEP(s_axis_rdma_rd.tkeep),
    .s_axis_mem_read_data_TLAST(s_axis_rdma_rd.tlast),

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
    .m_axis_dbg_3_TVALID(m_axis_dbg_3.valid),
    .m_axis_dbg_3_TREADY(m_axis_dbg_3.ready),
    .m_axis_dbg_3_TDATA(m_axis_dbg_3.data),
`endif

    .regIbvCountRx_V(ibv_rx_pkg_count_data),
    .regIbvCountRx_V_ap_vld(ibv_rx_pkg_count_valid),
    .regIbvCountTx_V(ibv_tx_pkg_count_data),
    .regIbvCountTx_V_ap_vld(ibv_tx_pkg_count_valid),
    .regCrcDropPkgCount_V(crc_drop_pkg_count_data),
    .regCrcDropPkgCount_V_ap_vld(crc_drop_pkg_count_valid),
    .regInvalidPsnDropCount_V(psn_drop_pkg_count_data),
    .regInvalidPsnDropCount_V_ap_vld(psn_drop_pkg_count_valid)
`endif
);

endmodule