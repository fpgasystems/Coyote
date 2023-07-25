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

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * @brief   Top level TLB for a single vFPGA
 *
 * Top level of a single vFPGA TLB, feeds into the top level arbitration.
 *
 *  @param ID_REG   Number of associated vFPGA
 */
module tlb_region_top #(
	parameter integer 					ID_REG = 0	
) (
	input logic        					aclk,    
	input logic    						aresetn,
	
	// AXI tlb control and writeback
`ifdef EN_TLBF
    AXI4S.s                             s_axis_lTlb,
    AXI4S.s                             s_axis_sTlb,
    output logic                        done_map,
`endif
    AXI4L.s   							s_axi_ctrl_sTlb,
    AXI4L.s   							s_axi_ctrl_lTlb,

`ifdef EN_WB
    metaIntf.m                          m_wback,
`endif

`ifdef EN_AVX
	// AXI config
	AXI4.s   							s_axim_ctrl_cnfg,
`else
	// AXIL Config
	AXI4L.s 							s_axi_ctrl_cnfg,
`endif	

`ifdef EN_BPSS
	// Requests user
	metaIntf.s 						    s_bpss_rd_req,
	metaIntf.s						    s_bpss_wr_req,
    metaIntf.m                          m_bpss_rd_done,
    metaIntf.m                          m_bpss_wr_done,
`endif

`ifdef MULT_STRM_AXI
    metaIntf.m                          m_rd_user_mux,
    metaIntf.m                          m_wr_user_mux,
`endif 

`ifdef EN_RDMA_0
	// RDMA request QSFP0
	metaIntf.m  						m_rdma_0_sq,
    metaIntf.s  						s_rdma_0_ack,
`ifdef EN_RPC
    metaIntf.s                          s_rdma_0_sq,
    metaIntf.m                          m_rdma_0_ack,
`endif  
`endif

`ifdef EN_RDMA_1
	// RDMA request QSFP1
	metaIntf.m  						m_rdma_1_sq,
    metaIntf.s  						s_rdma_1_ack,
`ifdef EN_RPC
    metaIntf.s                          s_rdma_1_sq,
    metaIntf.m                          m_rdma_1_ack,
`endif  
`endif

`ifdef EN_STRM
	// Stream DMAs
    dmaIntf.m                           m_rd_HDMA,
    dmaIntf.m                           m_wr_HDMA,

    // Credits
    input  logic                        rxfer_host,
    input  logic                        wxfer_host,
    output cred_t                       rd_dest_host,
`endif

  // TCP Session Management
`ifdef EN_TCP_0
    metaIntf.m                          m_open_port_cmd_0,
    metaIntf.m                          m_open_con_cmd_0,
    metaIntf.m                          m_close_con_cmd_0,
    metaIntf.s                          s_open_con_sts_0,
    metaIntf.s                          s_open_port_sts_0,
`endif

`ifdef EN_TCP_1
    metaIntf.m                          m_open_port_cmd_1,
    metaIntf.m                          m_open_con_cmd_1,
    metaIntf.m                          m_close_con_cmd_1,
    metaIntf.s                          s_open_con_sts_1,
    metaIntf.s                          s_open_port_sts_1,
`endif

`ifdef EN_MEM
    // Card DMAs
    dmaIntf.m                           m_rd_DDMA [N_CARD_AXI],
    dmaIntf.m                           m_wr_DDMA [N_CARD_AXI],
    dmaIsrIntf.m                        m_IDMA,
    dmaIsrIntf.m                        m_SDMA,

    // Credits
    input  logic                        rxfer_card [N_CARD_AXI],
    input  logic                        wxfer_card [N_CARD_AXI],
    output cred_t                       rd_dest_card [N_CARD_AXI],
`endif

	// Decoupling
	output logic 		                decouple,
	
	// Page fault IRQ
	output logic                    	pf_irq
);

// -- Decl -----------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------
localparam integer PG_L_SIZE = 1 << PG_L_BITS;
localparam integer PG_S_SIZE = 1 << PG_S_BITS;
localparam integer HASH_L_BITS = TLB_L_ORDER;
localparam integer HASH_S_BITS = TLB_S_ORDER;
localparam integer PHY_L_BITS = PADDR_BITS - PG_L_BITS;
localparam integer PHY_S_BITS = PADDR_BITS - PG_S_BITS;
localparam integer TAG_L_BITS = VADDR_BITS - HASH_L_BITS - PG_L_BITS;
localparam integer TAG_S_BITS = VADDR_BITS - HASH_S_BITS - PG_S_BITS;
localparam integer TLB_L_DATA_BITS = TAG_L_BITS + PID_BITS + 1 + 2*PHY_L_BITS;
localparam integer TLB_S_DATA_BITS = TAG_S_BITS + PID_BITS + 1 + 2*PHY_S_BITS;

// Tlb interfaces
tlbIntf #(.TLB_INTF_DATA_BITS(TLB_L_DATA_BITS)) rd_lTlb ();
tlbIntf #(.TLB_INTF_DATA_BITS(TLB_S_DATA_BITS)) rd_sTlb ();
tlbIntf #(.TLB_INTF_DATA_BITS(TLB_L_DATA_BITS)) wr_lTlb ();
tlbIntf #(.TLB_INTF_DATA_BITS(TLB_S_DATA_BITS)) wr_sTlb ();
tlbIntf #(.TLB_INTF_DATA_BITS(TLB_L_DATA_BITS)) lTlb ();
tlbIntf #(.TLB_INTF_DATA_BITS(TLB_S_DATA_BITS)) sTlb ();

`ifdef EN_STRM
metaIntf #(.STYPE(dma_rsp_t)) rd_host_done ();
metaIntf #(.STYPE(dma_rsp_t)) wr_host_done ();
`endif
`ifdef EN_MEM
metaIntf #(.STYPE(dma_rsp_t)) rd_card_done ();
metaIntf #(.STYPE(dma_rsp_t)) rd_sync_done ();
metaIntf #(.STYPE(dma_rsp_t)) wr_card_done ();
metaIntf #(.STYPE(dma_rsp_t)) wr_sync_done ();
`endif

metaIntf #(.STYPE(pfault_t)) rd_pfault ();
metaIntf #(.STYPE(pfault_t)) wr_pfault ();

logic rd_restart;
logic wr_restart;

// Request interfaces
metaIntf #(.STYPE(req_t)) rd_req ();
metaIntf #(.STYPE(req_t)) wr_req ();

logic done_map_lTlb;
logic done_map_sTlb;

AXI4S #(.AXI4S_DATA_BITS(AXI_TLB_BITS)) axis_lTlb_0 ();
AXI4S #(.AXI4S_DATA_BITS(AXI_TLB_BITS)) axis_sTlb_0 ();
`ifdef EN_TLBF
AXI4S #(.AXI4S_DATA_BITS(AXI_TLB_BITS)) axis_lTlb_1 ();
AXI4S #(.AXI4S_DATA_BITS(AXI_TLB_BITS)) axis_sTlb_1 ();
`endif
AXI4S #(.AXI4S_DATA_BITS(AXI_TLB_BITS)) axis_lTlb ();
AXI4S #(.AXI4S_DATA_BITS(AXI_TLB_BITS)) axis_sTlb ();

// Mutex
logic [1:0] mutex;
logic rd_lock, wr_lock;
logic rd_unlock, wr_unlock;

// ----------------------------------------------------------------------------------------
// Mutex 
// ----------------------------------------------------------------------------------------
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		mutex <= 2'b01;
	end else begin
		if(mutex[0] == 1'b1) begin // free
			if(rd_lock)
				mutex <= 2'b00;
			else if(wr_lock)
				mutex <= 2'b10;
		end
		else begin // locked
			if((mutex[1] == 1'b0) && rd_unlock)
				mutex <= 2'b01;
			else if (wr_unlock)
				mutex <= 2'b01;
		end
	end
end

// ----------------------------------------------------------------------------------------
// TLB
// ---------------------------------------------------------------------------------------- 
assign rd_lTlb.data = lTlb.data;
assign wr_lTlb.data = lTlb.data;
assign rd_sTlb.data = sTlb.data;
assign wr_sTlb.data = sTlb.data;
assign rd_lTlb.hit  = lTlb.hit;
assign wr_lTlb.hit  = lTlb.hit;
assign rd_sTlb.hit  = sTlb.hit;
assign wr_sTlb.hit  = sTlb.hit;

assign lTlb.addr  = mutex[1] ? wr_lTlb.addr : rd_lTlb.addr;
assign sTlb.addr  = mutex[1] ? wr_sTlb.addr : rd_sTlb.addr;
assign lTlb.pid   = mutex[1] ? wr_lTlb.pid : rd_lTlb.pid;
assign sTlb.pid   = mutex[1] ? wr_sTlb.pid : rd_sTlb.pid;
assign lTlb.wr    = mutex[1] ? wr_lTlb.wr : rd_lTlb.wr;
assign sTlb.wr    = mutex[1] ? wr_sTlb.wr : rd_sTlb.wr;
assign lTlb.valid = mutex[1] ? wr_lTlb.valid : rd_lTlb.valid;
assign sTlb.valid = mutex[1] ? wr_sTlb.valid : rd_sTlb.valid;

// TLBs
tlb_controller #(
    .TLB_ORDER(TLB_L_ORDER),
    .PG_BITS(PG_L_BITS),
    .N_ASSOC(N_L_ASSOC),
    .DBG_L(1)
) inst_lTlb (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axis(axis_lTlb),
    .TLB(lTlb),
    .done_map(done_map_lTlb)
);

tlb_controller #(
    .TLB_ORDER(TLB_S_ORDER),
    .PG_BITS(PG_S_BITS),
    .N_ASSOC(N_S_ASSOC),
    .DBG_S(1)
) inst_sTlb (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axis(axis_sTlb),
    .TLB(sTlb),
    .done_map(done_map_sTlb)
);

// TLB slaves
tlb_slave_axil #(
    .TLB_ORDER(TLB_L_ORDER),
    .PG_BITS(PG_L_BITS),
    .N_ASSOC(N_L_ASSOC)
) inst_lTlb_slv_0 (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axi_ctrl(s_axi_ctrl_lTlb),
    .m_axis(axis_lTlb_0)
);

tlb_slave_axil #(
    .TLB_ORDER(TLB_S_ORDER),
    .PG_BITS(PG_S_BITS),
    .N_ASSOC(N_S_ASSOC)
) inst_sTlb_slv_0 (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axi_ctrl(s_axi_ctrl_sTlb),
    .m_axis(axis_sTlb_0)
);

`ifdef EN_TLBF

assign done_map = done_map_lTlb | done_map_sTlb;

tlb_slave_axis #(
    .TLB_ORDER(TLB_L_ORDER),
    .PG_BITS(PG_L_BITS),
    .N_ASSOC(N_L_ASSOC)
) inst_lTlb_slv_1 (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axis(s_axis_lTlb),
    .m_axis(axis_lTlb_1)
);

tlb_slave_axis #(
    .TLB_ORDER(TLB_S_ORDER),
    .PG_BITS(PG_S_BITS),
    .N_ASSOC(N_S_ASSOC)
) inst_sTlb_slv_1 (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axis(s_axis_sTlb),
    .m_axis(axis_sTlb_1)
);

axis_interconnect_tlb inst_mux_stlb (
    .ACLK(aclk),
    .ARESETN(aresetn),
    .S00_AXIS_ACLK(aclk),
    .S01_AXIS_ACLK(aclk),
    .S00_AXIS_ARESETN(aresetn),
    .S01_AXIS_ARESETN(aresetn),
    .M00_AXIS_ACLK(aclk),
    .M00_AXIS_ARESETN(aresetn),
    
    .S00_AXIS_TVALID(axis_sTlb_0.tvalid),
    .S00_AXIS_TREADY(axis_sTlb_0.tready),
    .S00_AXIS_TDATA(axis_sTlb_0.tdata),
    .S00_AXIS_TLAST(axis_sTlb_0.tlast),
    .S01_AXIS_TVALID(axis_sTlb_1.tvalid),
    .S01_AXIS_TREADY(axis_sTlb_1.tready),
    .S01_AXIS_TDATA(axis_sTlb_1.tdata),
    .S01_AXIS_TLAST(axis_sTlb_1.tlast),
    .M00_AXIS_TVALID(axis_sTlb.tvalid),
    .M00_AXIS_TREADY(axis_sTlb.tready),
    .M00_AXIS_TDATA(axis_sTlb.tdata),
    .M00_AXIS_TLAST(axis_sTlb.tlast),

    .S00_ARB_REQ_SUPPRESS(1'b0),
    .S01_ARB_REQ_SUPPRESS(1'b0)
);

axis_interconnect_tlb inst_mux_ltlb (
    .ACLK(aclk),
    .ARESETN(aresetn),
    .S00_AXIS_ACLK(aclk),
    .S01_AXIS_ACLK(aclk),
    .S00_AXIS_ARESETN(aresetn),
    .S01_AXIS_ARESETN(aresetn),
    .M00_AXIS_ACLK(aclk),
    .M00_AXIS_ARESETN(aresetn),
    
    .S00_AXIS_TVALID(axis_lTlb_0.tvalid),
    .S00_AXIS_TREADY(axis_lTlb_0.tready),
    .S00_AXIS_TDATA(axis_lTlb_0.tdata),
    .S00_AXIS_TLAST(axis_lTlb_0.tlast),
    .S01_AXIS_TVALID(axis_lTlb_1.tvalid),
    .S01_AXIS_TREADY(axis_lTlb_1.tready),
    .S01_AXIS_TDATA(axis_lTlb_1.tdata),
    .S01_AXIS_TLAST(axis_lTlb_1.tlast),
    .M00_AXIS_TVALID(axis_lTlb.tvalid),
    .M00_AXIS_TREADY(axis_lTlb.tready),
    .M00_AXIS_TDATA(axis_lTlb.tdata),
    .M00_AXIS_TLAST(axis_lTlb.tlast),

    .S00_ARB_REQ_SUPPRESS(1'b0),
    .S01_ARB_REQ_SUPPRESS(1'b0)
);
   
`else 

`AXIS_ASSIGN(axis_sTlb_0, axis_sTlb)
`AXIS_ASSIGN(axis_lTlb_0, axis_lTlb)

`endif

// ----------------------------------------------------------------------------------------
// Config slave
// ---------------------------------------------------------------------------------------- 
`ifdef EN_AVX
	cnfg_slave_avx #(.ID_REG(ID_REG)) inst_cnfg_slave (
`else
	cnfg_slave #(.ID_REG(ID_REG)) inst_cnfg_slave (
`endif
		.aclk(aclk),
		.aresetn(aresetn),
`ifdef EN_AVX
		.s_axim_ctrl(s_axim_ctrl_cnfg),
`else
		.s_axi_ctrl(s_axi_ctrl_cnfg),
`endif
`ifdef EN_BPSS
		.s_bpss_rd_req(s_bpss_rd_req),
		.s_bpss_wr_req(s_bpss_wr_req),
        .m_bpss_rd_done(m_bpss_rd_done),
        .m_bpss_wr_done(m_bpss_wr_done),
`endif
`ifdef MULT_STRM_AXI
        .m_rd_user_mux(m_rd_user_mux),
        .m_wr_user_mux(m_wr_user_mux),
`endif 
`ifdef EN_RDMA_0
		.m_rdma_0_sq(m_rdma_0_sq),
        .s_rdma_0_ack(s_rdma_0_ack),
`ifdef EN_RPC
        .s_rdma_0_sq(s_rdma_0_sq),
        .m_rdma_0_ack(m_rdma_0_ack),
`endif
`endif
`ifdef EN_RDMA_1
		.m_rdma_1_sq(m_rdma_1_sq),
        .s_rdma_1_ack(s_rdma_1_ack),
`ifdef EN_RPC
        .s_rdma_1_sq(s_rdma_1_sq),
        .m_rdma_1_ack(m_rdma_1_ack),
`endif
`endif
        .m_rd_req(rd_req),
		.m_wr_req(wr_req),
`ifdef EN_STRM
        .s_host_done_rd(rd_host_done),
        .s_host_done_wr(wr_host_done),
`endif
`ifdef EN_MEM
        .s_card_done_rd(rd_card_done),
        .s_card_done_wr(wr_card_done),
        .s_sync_done_rd(rd_sync_done),
        .s_sync_done_wr(wr_sync_done),
`endif
`ifdef EN_TCP_0
        .m_open_port_cmd_0(m_open_port_cmd_0),
        .m_open_con_cmd_0(m_open_con_cmd_0),
        .m_close_con_cmd_0(m_close_con_cmd_0),
        .s_open_con_sts_0(s_open_con_sts_0),
        .s_open_port_sts_0(s_open_port_sts_0),
`endif
`ifdef EN_TCP_1
        .m_open_port_cmd_1(m_open_port_cmd_1),
        .m_open_con_cmd_1(m_open_con_cmd_1),
        .m_close_con_cmd_1(m_close_con_cmd_1),
        .s_open_con_sts_1(s_open_con_sts_1),
        .s_open_port_sts_1(s_open_port_sts_1),
`endif
`ifdef EN_WB
        .m_wback(m_wback),
`endif
        .s_pfault_rd(rd_pfault),
        .s_pfault_wr(wr_pfault),
        .restart_rd(rd_restart),
        .restart_wr(wr_restart),
		.decouple(decouple),
		.pf_irq(pf_irq)
	);

// ----------------------------------------------------------------------------------------
// Parsing
// ----------------------------------------------------------------------------------------
metaIntf #(.STYPE(req_t)) rd_req_parsed ();
metaIntf #(.STYPE(req_t)) wr_req_parsed ();
metaIntf #(.STYPE(req_t)) rd_req_parsed_q ();
metaIntf #(.STYPE(req_t)) wr_req_parsed_q ();

tlb_parser inst_rd_parser (.aclk(aclk), .aresetn(aresetn), .s_req(rd_req), .m_req(rd_req_parsed));
tlb_parser inst_wr_parser (.aclk(aclk), .aresetn(aresetn), .s_req(wr_req), .m_req(wr_req_parsed));

// Queueing
meta_queue #(.DATA_BITS($bits(req_t))) inst_rd_q_parser (.aclk(aclk), .aresetn(aresetn), .s_meta(rd_req_parsed), .m_meta(rd_req_parsed_q));
meta_queue #(.DATA_BITS($bits(req_t))) inst_wr_q_parser (.aclk(aclk), .aresetn(aresetn), .s_meta(wr_req_parsed), .m_meta(wr_req_parsed_q));

// ----------------------------------------------------------------------------------------
// FSM
// ----------------------------------------------------------------------------------------
`ifdef EN_STRM
    // FSM
    dmaIntf rd_HDMA_fsm ();
    dmaIntf wr_HDMA_fsm ();
    
    dmaIntf rd_HDMA_fsm_q ();
    dmaIntf wr_HDMA_fsm_q ();

    // Credits
    dmaIntf rd_HDMA_cred ();
    dmaIntf wr_HDMA_cred ();
`endif

`ifdef EN_MEM
    dmaIntf rd_DDMA_fsm ();
    dmaIntf wr_DDMA_fsm ();
    dmaIsrIntf rd_IDMA_fsm ();
    dmaIsrIntf wr_IDMA_fsm ();
    dmaIsrIntf IDMA_fsm ();
    dmaIsrIntf SDMA_fsm ();

    dmaIntf rd_DDMA_fsm_qin [N_CARD_AXI] ();
    dmaIntf wr_DDMA_fsm_qin [N_CARD_AXI] ();
    dmaIntf rd_DDMA_fsm_qout [N_CARD_AXI] ();
    dmaIntf wr_DDMA_fsm_qout [N_CARD_AXI] ();
    
    // Credits
    dmaIntf rd_DDMA_cred [N_CARD_AXI] ();
    dmaIntf wr_DDMA_cred [N_CARD_AXI] ();
`endif

// TLB rd FSM
tlb_fsm_rd #(
    .ID_REG(ID_REG)   
) inst_fsm_rd (
    .aclk(aclk),
    .aresetn(aresetn),
    .lTlb(rd_lTlb),
    .sTlb(rd_sTlb),
`ifdef EN_STRM
    .m_host_done(rd_host_done),
`endif
`ifdef EN_MEM
    .m_card_done(rd_card_done),
    .m_sync_done(rd_sync_done),
`endif
    .m_pfault(rd_pfault),
    .restart(rd_restart),
    .s_req(rd_req_parsed_q),
`ifdef EN_STRM
    .m_HDMA(rd_HDMA_fsm),
`endif
`ifdef EN_MEM
    .m_DDMA(rd_DDMA_fsm),
    .m_IDMA(rd_IDMA_fsm),
`endif
    .lock(rd_lock),
	.unlock(rd_unlock),
	.mutex(mutex)
);

// TLB wr FSM
tlb_fsm_wr #(
    .ID_REG(ID_REG)   
) inst_fsm_wr (
    .aclk(aclk),
    .aresetn(aresetn),
    .lTlb(wr_lTlb),
    .sTlb(wr_sTlb),
`ifdef EN_STRM
    .m_host_done(wr_host_done),
`endif
`ifdef EN_MEM
    .m_card_done(wr_card_done),
    .m_sync_done(wr_sync_done),
`endif
    .m_pfault(wr_pfault),
    .restart(wr_restart),
    .s_req(wr_req_parsed_q),
`ifdef EN_STRM
    .m_HDMA(wr_HDMA_fsm),
`endif
`ifdef EN_MEM
    .m_DDMA(wr_DDMA_fsm),
    .m_IDMA(wr_IDMA_fsm),
    .m_SDMA(SDMA_fsm),
`endif
    .lock(wr_lock),
	.unlock(wr_unlock),
	.mutex(mutex)
);

// Queueing
`ifdef EN_STRM
    // HDMA
    dma_req_queue inst_rd_q_fsm_hdma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_HDMA_fsm), .m_req(rd_HDMA_fsm_q));
    dma_req_queue inst_wr_q_fsm_hdma (.aclk(aclk), .aresetn(aresetn), .s_req(wr_HDMA_fsm), .m_req(wr_HDMA_fsm_q));
`endif

`ifdef EN_MEM
    // DDMA multiplex to different DMA Channels
    tlb_mux#(.N_OUTPUT(N_CARD_AXI))(.aclk(aclk), .aresetn(aresetn), .s_req(rd_DDMA_fsm), .m_req(rd_DDMA_fsm_qin));
    tlb_mux#(.N_OUTPUT(N_CARD_AXI))(.aclk(aclk), .aresetn(aresetn), .s_req(wr_DDMA_fsm), .m_req(wr_DDMA_fsm_qin));

    for(genvar i = 0; i < N_CARD_AXI; i++) begin
        // DDMA
        dma_req_queue inst_rd_q_fsm_ddma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_DDMA_fsm_qin[i]), .m_req(rd_DDMA_fsm_qout[i]));
        dma_req_queue inst_wr_q_fsm_ddma (.aclk(aclk), .aresetn(aresetn), .s_req(wr_DDMA_fsm_qin[i]), .m_req(wr_DDMA_fsm_qout[i]));
    end

    // IDMA arbitration
    tlb_idma_arb inst_idma_arb (.aclk(aclk), .aresetn(aresetn), .mutex(mutex[1]), .s_rd_IDMA(rd_IDMA_fsm), .s_wr_IDMA(wr_IDMA_fsm), .m_IDMA(IDMA_fsm));

    // IDMA
    dma_isr_req_queue inst_q_fsm_idma (.aclk(aclk), .aresetn(aresetn), .s_req(IDMA_fsm), .m_req(m_IDMA));
    
    // SDMA
    dma_isr_req_queue inst_q_fsm_sdma (.aclk(aclk), .aresetn(aresetn), .s_req(SDMA_fsm), .m_req(m_SDMA));
`endif

// ----------------------------------------------------------------------------------------
// Credits and output
// ----------------------------------------------------------------------------------------
`ifdef EN_STRM
    // HDMA
    tlb_credits_rd #(.ID_REG(ID_REG)) inst_rd_cred_hdma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_HDMA_fsm_q), .m_req(rd_HDMA_cred), .rxfer(rxfer_host), .rd_dest(rd_dest_host));
    tlb_credits_wr #(.ID_REG(ID_REG)) inst_wr_cred_hdma (.aclk(aclk), .aresetn(aresetn), .s_req(wr_HDMA_fsm_q), .m_req(wr_HDMA_cred), .wxfer(wxfer_host));

    // Queueing
    dma_req_queue inst_rd_q_cred_hdma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_HDMA_cred), .m_req(m_rd_HDMA));
    dma_req_queue inst_wr_q_cred_hdma (.aclk(aclk), .aresetn(aresetn), .s_req(wr_HDMA_cred), .m_req(m_wr_HDMA));
`endif

`ifdef EN_MEM
    for(genvar i = 0; i < N_CARD_AXI; i++) begin
        // DDMA
        tlb_credits_rd #(.ID_REG(ID_REG)) inst_rd_cred_ddma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_DDMA_fsm_qout[i]), .m_req(rd_DDMA_cred[i]), .rxfer(rxfer_card[i]), .rd_dest(rd_dest_card[i]));
        tlb_credits_wr #(.ID_REG(ID_REG)) inst_wr_cred_ddma (.aclk(aclk), .aresetn(aresetn), .s_req(wr_DDMA_fsm_qout[i]), .m_req(wr_DDMA_cred[i]), .wxfer(wxfer_card[i]));

        // Queueing
        dma_req_queue inst_rd_q_cred_ddma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_DDMA_cred[i]), .m_req(m_rd_DDMA[i]));
        dma_req_queue inst_wr_q_cred_ddma (.aclk(aclk), .aresetn(aresetn), .s_req(wr_DDMA_cred[i]), .m_req(m_wr_DDMA[i]));
    end
`endif

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_TLB_REGION_TOP

`endif

endmodule // tlb_top