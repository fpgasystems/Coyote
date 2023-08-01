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

`include "lynx_macros.svh"

/**
 * @brief   Top level TLB
 *
 * Top level MMU for all vFPGAs.
 *
 *  @param ID_DYN   Number of associated dynamic region
 */
module tlb_top #(
	parameter integer 					ID_DYN = 0	
) (
	input logic        					aclk,    
	input logic    						aresetn,
	
	// AXI tlb control
`ifdef EN_TLBF
	AXI4S.s 							s_axis_lTlb [N_REGIONS],
	AXI4S.s 							s_axis_sTlb [N_REGIONS],
    output logic                        done_map,
`endif
    AXI4L.s   							s_axi_ctrl_sTlb [N_REGIONS],
    AXI4L.s   							s_axi_ctrl_lTlb [N_REGIONS],

`ifdef EN_AVX
	// AXI config
	AXI4.s   							s_axim_ctrl_cnfg [N_REGIONS],
`else
	// AXIL Config
	AXI4L.s 							s_axi_ctrl_cnfg [N_REGIONS],
`endif	

`ifdef EN_BPSS
	// Requests user
	metaIntf.s 						    s_bpss_rd_req [N_REGIONS],
	metaIntf.s						    s_bpss_wr_req [N_REGIONS],
    metaIntf.m                          m_bpss_rd_done [N_REGIONS],
    metaIntf.m                          m_bpss_wr_done [N_REGIONS],
`endif

`ifdef MULT_STRM_AXI
    metaIntf.m                          m_rd_user_mux[N_REGIONS],
    metaIntf.m                          m_wr_user_mux[N_REGIONS],
`endif 

`ifdef EN_RDMA_0
	// RDMA request QSFP0
	metaIntf.m  						m_rdma_0_sq [N_REGIONS],
    metaIntf.s  						s_rdma_0_ack [N_REGIONS],
`ifdef EN_RPC
    metaIntf.s                          s_rdma_0_sq [N_REGIONS],
    metaIntf.m                          m_rdma_0_ack [N_REGIONS],
`endif  
`endif

`ifdef EN_RDMA_1
	// RDMA request QSFP1
	metaIntf.m  						m_rdma_1_sq [N_REGIONS],
    metaIntf.s  						s_rdma_1_ack [N_REGIONS],
`ifdef EN_RPC
    metaIntf.s                          s_rdma_1_sq [N_REGIONS],
    metaIntf.m                          m_rdma_1_ack [N_REGIONS],
`endif  
`endif

`ifdef EN_STRM
	// Stream DMAs
    dmaIntf.m                           m_rd_XDMA_host,
    dmaIntf.m                           m_wr_XDMA_host,

    // Credits
    input  logic [N_REGIONS-1:0]        rxfer_host,
    input  logic [N_REGIONS-1:0]        wxfer_host,
    output cred_t [N_REGIONS-1:0]       rd_dest_host,

    // Mux ordering
    muxIntf.s  					        s_mux_host_rd_user,
    muxIntf.s   				        s_mux_host_wr_user,
`endif

  // TCP Session Management
`ifdef EN_TCP_0
    metaIntf.m                          m_open_port_cmd_0 [N_REGIONS],
    metaIntf.m                          m_open_con_cmd_0 [N_REGIONS],
    metaIntf.m                          m_close_con_cmd_0 [N_REGIONS],
    metaIntf.s                          s_open_con_sts_0 [N_REGIONS],
    metaIntf.s                          s_open_port_sts_0 [N_REGIONS],
`endif

`ifdef EN_TCP_1
    metaIntf.m                          m_open_port_cmd_1 [N_REGIONS],
    metaIntf.m                          m_open_con_cmd_1 [N_REGIONS],
    metaIntf.m                          m_close_con_cmd_1 [N_REGIONS],
    metaIntf.s                          s_open_con_sts_1 [N_REGIONS],
    metaIntf.s                          s_open_port_sts_1 [N_REGIONS],
`endif

`ifdef EN_MEM
    // Card DMAs
    dmaIntf.m                           m_rd_XDMA_sync,
    dmaIntf.m                           m_wr_XDMA_sync,
	dmaIntf.m 							m_rd_CDMA_sync,
	dmaIntf.m 							m_wr_CDMA_sync,
    dmaIntf.m                           m_rd_CDMA_card [N_REGIONS*N_CARD_AXI],
    dmaIntf.m                           m_wr_CDMA_card [N_REGIONS*N_CARD_AXI],

    // Credits
    input  logic                        rxfer_card [N_REGIONS*N_CARD_AXI],
    input  logic                        wxfer_card [N_REGIONS*N_CARD_AXI],
    output cred_t                       rd_dest_card [N_REGIONS*N_CARD_AXI],
`endif

`ifdef EN_WB
    // Writeback
    metaIntf.m                          m_wback,
`endif

	// Decoupling
	output logic [N_REGIONS-1:0]		decouple,
	
	// Page fault IRQ
	output logic [N_REGIONS-1:0]    	pf_irq
);

// Internal
`ifdef EN_STRM
    dmaIntf rd_HDMA_arb [N_REGIONS] ();
    dmaIntf wr_HDMA_arb [N_REGIONS] ();
`endif

`ifdef EN_MEM
    dmaIntf rd_DDMA_arb [N_REGIONS*N_CARD_AXI] ();
    dmaIntf wr_DDMA_arb [N_REGIONS*N_CARD_AXI] ();

    dmaIsrIntf IDMA_arb [N_REGIONS] ();
    dmaIsrIntf SDMA_arb [N_REGIONS] ();
`endif

`ifdef EN_WB
    metaIntf #(.STYPE(wback_t)) wback_arb [N_REGIONS] ();
`endif

`ifdef EN_TLBF
    logic [N_REGIONS-1:0] done_map_reg;
    assign done_map = |done_map_reg;
`endif

// Instantiate region TLBs
for(genvar i = 0; i < N_REGIONS; i++) begin
    
    tlb_region_top #(
        .ID_REG(ID_DYN*N_REGIONS+i)
    ) inst_reg_top (
        .aclk(aclk),
        .aresetn(aresetn),
    `ifdef EN_TLBF
        .s_axis_sTlb(s_axis_sTlb[i]),
        .s_axis_lTlb(s_axis_lTlb[i]),
        .done_map(done_map_reg[i]),
    `endif
        .s_axi_ctrl_sTlb(s_axi_ctrl_sTlb[i]),
        .s_axi_ctrl_lTlb(s_axi_ctrl_lTlb[i]),
    `ifdef EN_AVX
		.s_axim_ctrl_cnfg(s_axim_ctrl_cnfg[i]),
    `else
        .s_axi_ctrl_cnfg(s_axi_ctrl_cnfg[i]),
    `endif
    `ifdef EN_BPSS
		.s_bpss_rd_req(s_bpss_rd_req[i]),
		.s_bpss_wr_req(s_bpss_wr_req[i]),
        .m_bpss_rd_done(m_bpss_rd_done[i]),
        .m_bpss_wr_done(m_bpss_wr_done[i]),
    `endif
    `ifdef MULT_STRM_AXI
        .m_rd_user_mux(m_rd_user_mux[i]),
        .m_wr_user_mux(m_wr_user_mux[i]),
    `endif 
    `ifdef EN_RDMA_0
		.m_rdma_0_sq(m_rdma_0_sq[i]),
        .s_rdma_0_ack(s_rdma_0_ack[i]),
    `ifdef EN_RPC
        .s_rdma_0_sq(s_rdma_0_sq[i]),
        .m_rdma_0_ack(m_rdma_0_ack[i]),
    `endif
    `endif
    `ifdef EN_RDMA_1
		.m_rdma_1_sq(m_rdma_1_sq[i]),
        .s_rdma_1_ack(s_rdma_1_ack[i]),
    `ifdef EN_RPC
        .s_rdma_1_sq(s_rdma_1_sq[i]),
        .m_rdma_1_ack(m_rdma_1_ack[i]),
    `endif
    `endif
    `ifdef EN_STRM
        .m_rd_HDMA(rd_HDMA_arb[i]),
        .m_wr_HDMA(wr_HDMA_arb[i]),
        .rxfer_host(rxfer_host[i]),
        .wxfer_host(wxfer_host[i]),
        .rd_dest_host(rd_dest_host[i]),
    `endif
    `ifdef EN_TCP_0
        .m_open_port_cmd_0(m_open_port_cmd_0[i]),
        .m_open_con_cmd_0(m_open_con_cmd_0[i]),
        .m_close_con_cmd_0(m_close_con_cmd_0[i]),
        .s_open_con_sts_0(s_open_con_sts_0[i]),
        .s_open_port_sts_0(s_open_port_sts_0[i]),
    `endif
    `ifdef EN_TCP_1
        .m_open_port_cmd_1(m_open_port_cmd_1[i]),
        .m_open_con_cmd_1(m_open_con_cmd_1[i]),
        .m_close_con_cmd_1(m_close_con_cmd_1[i]),
        .s_open_con_sts_1(s_open_con_sts_1[i]),
        .s_open_port_sts_1(s_open_port_sts_1[i]),
    `endif
    `ifdef EN_MEM
        .m_rd_DDMA(rd_DDMA_arb[i*N_CARD_AXI+:N_CARD_AXI]),
        .m_wr_DDMA(wr_DDMA_arb[i*N_CARD_AXI+:N_CARD_AXI]),
        .m_IDMA(IDMA_arb[i]),
        .m_SDMA(SDMA_arb[i]),
        .rxfer_card(rxfer_card[i*N_CARD_AXI+:N_CARD_AXI]),
        .wxfer_card(wxfer_card[i*N_CARD_AXI+:N_CARD_AXI]),
        .rd_dest_card(rd_dest_card[i*N_CARD_AXI+:N_CARD_AXI]),
    `endif
    `ifdef EN_WB
        .m_wback(wback_arb[i]),
    `endif
        .decouple(decouple[i]),
        .pf_irq(pf_irq[i])
    );

end

// Instantiate arbitration
`ifdef EN_STRM
    tlb_arbiter inst_hdma_arb_rd (.aclk(aclk), .aresetn(aresetn), .s_req(rd_HDMA_arb), .m_req(m_rd_XDMA_host), .s_mux_user(s_mux_host_rd_user));
    tlb_arbiter inst_hdma_arb_wr (.aclk(aclk), .aresetn(aresetn), .s_req(wr_HDMA_arb), .m_req(m_wr_XDMA_host), .s_mux_user(s_mux_host_wr_user));
`endif

`ifdef EN_MEM
    for(genvar i = 0; i < N_REGIONS; i++) begin
        for(genvar j = 0; j < N_CARD_AXI; j++) begin
            tlb_assign inst_cdma_arb_rd (.aclk(aclk), .aresetn(aresetn), .s_req(rd_DDMA_arb[i*N_CARD_AXI+j]), .m_req(m_rd_CDMA_card[i*N_CARD_AXI+j]));
            tlb_assign inst_cdma_arb_wr (.aclk(aclk), .aresetn(aresetn), .s_req(wr_DDMA_arb[i*N_CARD_AXI+j]), .m_req(m_wr_CDMA_card[i*N_CARD_AXI+j]));
        end
    end

    tlb_arbiter_isr #(.RDWR(0)) inst_idma_arb (.aclk(aclk), .aresetn(aresetn), .s_req(IDMA_arb), .m_req_host(m_rd_XDMA_sync), .m_req_card(m_wr_CDMA_sync));
    tlb_arbiter_isr #(.RDWR(1)) inst_sdma_arb (.aclk(aclk), .aresetn(aresetn), .s_req(SDMA_arb), .m_req_host(m_wr_XDMA_sync), .m_req_card(m_rd_CDMA_sync));
`endif

`ifdef EN_WB
    meta_arbiter #(.DATA_BITS($bits(wback_t))) inst_meta_arb (.aclk(aclk), .aresetn(aresetn), .s_meta(wback_arb), .m_meta(m_wback));
`endif

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_TLB_TOP

`endif

endmodule // tlb_top