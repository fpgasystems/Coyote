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
 * @brief   Top level Dynamic MGMT
 *
 *
 *  @param ID_DYN   Number of associated dynamic region
 */
module mmu_top #(
	parameter integer 					ID_DYN = 0	
) (
	input logic        					aclk,    
	input logic    						aresetn,
	
	// AXI tlb control
    AXI4L.s   							s_axi_ctrl_sTlb [N_REGIONS],
    AXI4L.s   							s_axi_ctrl_lTlb [N_REGIONS],

`ifdef EN_AVX
	// AXI config
	AXI4.s   							s_axim_ctrl_cnfg [N_REGIONS],
`else
	// AXIL Config
	AXI4L.s 							s_axi_ctrl_cnfg [N_REGIONS],
`endif	

    // Notify
    metaIntf.s                          s_notify [N_REGIONS],

	// Requests user
    metaIntf.m                          m_host_sq [N_REGIONS],

    // Bypass
	metaIntf.s 						    s_bpss_rd_sq [N_REGIONS],
	metaIntf.s						    s_bpss_wr_sq [N_REGIONS],
    metaIntf.m                          m_bpss_rd_cq [N_REGIONS],
    metaIntf.m                          m_bpss_wr_cq [N_REGIONS],

`ifdef EN_STRM
	// Stream DMAs
    dmaIntf.m                           m_rd_XDMA_host,
    dmaIntf.m                           m_wr_XDMA_host,

    // Mux ordering
    metaIntf.m  					    m_mux_host_rd,
    metaIntf.m   				        m_mux_host_wr,

`ifndef EN_CRED_LOCAL
    // Credits
    input  logic [N_REGIONS-1:0]        rxfer_host,
    input  logic [N_REGIONS-1:0]        wxfer_host,
`endif 
`endif

`ifdef EN_MEM
    // Card DMAs
    dmaIntf.m                           m_rd_XDMA_mig,
    dmaIntf.m                           m_wr_XDMA_mig,
    dmaIntf.m                           m_rd_CDMA_mig,
    dmaIntf.m                           m_wr_CDMA_mig,
    dmaIntf.m                           m_rd_CDMA_card [N_REGIONS*N_CARD_AXI],
    dmaIntf.m                           m_wr_CDMA_card [N_REGIONS*N_CARD_AXI],

`ifndef EN_CRED_LOCAL
    input  logic                        rxfer_card [N_REGIONS*N_CARD_AXI],
    input  logic                        wxfer_card [N_REGIONS*N_CARD_AXI],
`endif 
`endif

`ifdef EN_NET
    // ARP 
    metaIntf.m                          m_arp_lookup_request,
`endif 

`ifdef EN_RDMA
    // RDMA
    metaIntf.m                          m_rdma_qp_interface,
    metaIntf.m                          m_rdma_conn_interface,
    metaIntf.s                          s_rdma_cq,
`endif

`ifdef EN_TCP
    // TCP
    metaIntf.m                          m_open_port_cmd,
    metaIntf.s                          m_open_port_sts,
    metaIntf.m                          m_open_conn_cmd,
    metaIntf.s                          m_open_conn_sts,
`endif

`ifdef EN_WB
    // Writeback
    metaIntf.m                          m_wback,
`endif
	
	// Page fault IRQ
	output logic [N_REGIONS-1:0]    	usr_irq
);

//
// MMU
//

`ifdef EN_STRM
    dmaIntf rd_HDMA_arb [N_REGIONS] ();
    dmaIntf wr_HDMA_arb [N_REGIONS] ();

    metaIntf #(.STYPE(ack_t)) rd_host_done [N_REGIONS] ();
    metaIntf #(.STYPE(ack_t)) wr_host_done [N_REGIONS] ();
`endif

`ifdef EN_MEM
    dmaIntf rd_DDMA_assign [N_REGIONS*N_CARD_AXI] ();
    dmaIntf wr_DDMA_assign [N_REGIONS*N_CARD_AXI] ();

    metaIntf #(.STYPE(ack_t)) rd_card_done [N_REGIONS] ();
    metaIntf #(.STYPE(ack_t)) wr_card_done [N_REGIONS] ();
`endif

metaIntf #(.STYPE(irq_pft_t)) rd_pfault_irq [N_REGIONS] ();
logic [N_REGIONS-1:0][LEN_BITS-1:0] rd_pfault_rng;
metaIntf #(.STYPE(irq_pft_t)) wr_pfault_irq [N_REGIONS] ();
logic [N_REGIONS-1:0][LEN_BITS-1:0] wr_pfault_rng;
metaIntf #(.STYPE(irq_inv_t)) rd_invldt_irq [N_REGIONS] ();
metaIntf #(.STYPE(irq_inv_t)) wr_invldt_irq [N_REGIONS] ();
metaIntf #(.STYPE(pf_t)) rd_pfault_ctrl [N_REGIONS] ();
metaIntf #(.STYPE(pf_t)) wr_pfault_ctrl [N_REGIONS] ();
metaIntf #(.STYPE(inv_t)) rd_invldt_ctrl [N_REGIONS] ();
metaIntf #(.STYPE(inv_t)) wr_invldt_ctrl [N_REGIONS] ();

// Instantiate region MMUs
for(genvar i = 0; i < N_REGIONS; i++) begin
    
    mmu_region_top #(
        .ID_REG(i)
    ) inst_mmu_region (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_ctrl_sTlb(s_axi_ctrl_sTlb[i]), // 
        .s_axi_ctrl_lTlb(s_axi_ctrl_lTlb[i]), //
        .s_bpss_rd_sq(s_bpss_rd_sq[i]), // 
		.s_bpss_wr_sq(s_bpss_wr_sq[i]), // 
    `ifdef EN_STRM
        .m_rd_HDMA(rd_HDMA_arb[i]), // 
        .m_wr_HDMA(wr_HDMA_arb[i]), // 
        .m_rd_host_done(rd_host_done[i]),
        .m_wr_host_done(wr_host_done[i]),
    `ifndef EN_CRED_LOCAL
        .rxfer_host(rxfer_host[i]), // 
        .wxfer_host(wxfer_host[i]), //
    `endif
    `endif
    `ifdef EN_MEM
        .m_rd_DDMA(rd_DDMA_assign[i*N_CARD_AXI+:N_CARD_AXI]), // 
        .m_wr_DDMA(wr_DDMA_assign[i*N_CARD_AXI+:N_CARD_AXI]), // 
        .m_rd_card_done(rd_card_done[i]), 
        .m_wr_card_done(wr_card_done[i]),
    `ifndef EN_CRED_LOCAL
        .rxfer_card(rxfer_card[i*N_CARD_AXI+:N_CARD_AXI]), // 
        .wxfer_card(wxfer_card[i*N_CARD_AXI+:N_CARD_AXI]), // 
    `endif 
    `endif  
        .m_rd_pfault_irq(rd_pfault_irq[i]),
        .m_rd_pfault_rng(rd_pfault_rng[i]),
        .s_rd_pfault_ctrl(rd_pfault_ctrl[i]),
        .m_wr_pfault_irq(wr_pfault_irq[i]),
        .m_wr_pfault_rng(wr_pfault_rng[i]),
        .s_wr_pfault_ctrl(wr_pfault_ctrl[i]),

        .s_rd_invldt_ctrl(rd_invldt_ctrl[i]),
        .m_rd_invldt_irq(rd_invldt_irq[i]),
        .s_wr_invldt_ctrl(wr_invldt_ctrl[i]),
        .m_wr_invldt_irq(wr_invldt_irq[i])
    );

end

// Arbitration
`ifdef EN_STRM
    mmu_arbiter inst_hdma_arb_rd (.aclk(aclk), .aresetn(aresetn), .s_req(rd_HDMA_arb), .m_req(m_rd_XDMA_host), .m_mux(m_mux_host_rd));
    mmu_arbiter inst_hdma_arb_wr (.aclk(aclk), .aresetn(aresetn), .s_req(wr_HDMA_arb), .m_req(m_wr_XDMA_host), .m_mux(m_mux_host_wr));
`endif

`ifdef EN_MEM
    for(genvar i = 0; i < N_CARD_AXI * N_REGIONS; i++) begin
        mmu_assign inst_ddma_assign_rd (.aclk(aclk), .aresetn(aresetn), .s_req(rd_DDMA_assign[i]), .m_req(m_rd_CDMA_card[i]));
        mmu_assign inst_ddma_assign_wr (.aclk(aclk), .aresetn(aresetn), .s_req(wr_DDMA_assign[i]), .m_req(m_wr_CDMA_card[i]));
    end
`endif 

// 
// Config
//

`ifdef EN_MEM
    dmaIsrIntf dma_offload [N_REGIONS] ();
    dmaIsrIntf dma_sync [N_REGIONS] ();
`endif

`ifdef EN_NET
    metaIntf #(.STYPE(logic[ARP_LUP_REQ_BITS-1:0])) arp_lookup_request [N_REGIONS] ();
`endif

`ifdef EN_RDMA
    metaIntf #(.STYPE(rdma_qp_ctx_t)) rdma_qp_interface [N_REGIONS] ();
    metaIntf #(.STYPE(rdma_qp_conn_t)) rdma_conn_interface [N_REGIONS] ();
`endif

`ifdef EN_TCP
    metaIntf #(.STYPE(tcp_listen_req_r_t)) open_port_cmd [N_REGIONS] ();
    metaIntf #(.STYPE(tcp_listen_rsp_r_t)) open_port_sts [N_REGIONS] ();
    metaIntf #(.STYPE(tcp_open_req_r_t)) open_conn_cmd [N_REGIONS] ();
    metaIntf #(.STYPE(tcp_open_rsp_r_t)) open_conn_sts [N_REGIONS] ();
`endif

`ifdef EN_WB
    metaIntf #(.STYPE(wback_t)) wback [N_REGIONS] ();
`endif 

// Instantiate region controllers
for(genvar i = 0; i < N_REGIONS; i++) begin

    `ifdef EN_AVX
        cnfg_slave_avx #(.ID_REG(i)) inst_cnfg_slave (
    `else
        cnfg_slave #(.ID_REG(i)) inst_cnfg_slave (
    `endif
            .aclk(aclk),
            .aresetn(aresetn),
    `ifdef EN_AVX
            .s_axim_ctrl(s_axim_ctrl_cnfg[i]),
    `else
            .s_axi_ctrl(s_axi_ctrl_cnfg[i]),
    `endif
            .m_host_sq(m_host_sq[i]),
            .m_bpss_done_rd(m_bpss_rd_cq[i]),
            .m_bpss_done_wr(m_bpss_wr_cq[i]),
    `ifdef EN_STRM
            .s_host_done_rd(rd_host_done[i]),
            .s_host_done_wr(wr_host_done[i]),
    `endif
    `ifdef EN_MEM
            .m_dma_offload(dma_offload[i]),
            .m_dma_sync(dma_sync[i]),
            .s_card_done_rd(rd_card_done[i]),
            .s_card_done_wr(wr_card_done[i]),
    `endif
    `ifdef EN_NET
            .m_arp_lookup_request(arp_lookup_request[i]), //
    `endif 
    `ifdef EN_RDMA
            .m_rdma_qp_interface(rdma_qp_interface[i]), //
            .m_rdma_conn_interface(rdma_conn_interface[i]), //
            .s_rdma_done(s_rdma_cq[i]), // 
    `endif
    `ifdef EN_TCP
            .m_open_port_cmd(open_port_cmd[i]), //
            .s_open_port_sts(open_port_sts[i]), //
            .m_open_conn_cmd(open_conn_cmd[i]), //
            .s_open_conn_sts(open_conn_sts[i]), //
    `endif
    `ifdef EN_WB
            .m_wback(wback[i]),
    `endif
            .s_pfault_rd(rd_pfault_irq[i]),
            .s_pfault_rd_rng(rd_pfault_rng[i]),
            .s_pfault_wr(wr_pfault_irq[i]),
            .s_pfault_wr_rng(wr_pfault_rng[i]),
            .m_pfault_rd(rd_pfault_ctrl[i]),
            .m_pfault_wr(wr_pfault_ctrl[i]),

            .s_invldt_rd(rd_invldt_irq[i]),
            .s_invldt_wr(wr_invldt_irq[i]),
            .m_invldt_rd(rd_invldt_ctrl[i]),
            .m_invldt_wr(wr_invldt_ctrl[i]),        
            
            .s_notify(s_notify[i]), //
            
            .usr_irq(usr_irq[i]) //
        );

end

// Arbitration
`ifdef EN_MEM
    mmu_arbiter_isr #(.RDWR(0)) inst_card_offload_arb (.aclk(aclk), .aresetn(aresetn), .s_req(dma_offload), .m_req_host(m_rd_XDMA_mig), .m_req_card(m_wr_CDMA_mig));
    mmu_arbiter_isr #(.RDWR(1)) inst_card_sync_arb    (.aclk(aclk), .aresetn(aresetn), .s_req(dma_sync),    .m_req_host(m_wr_XDMA_mig), .m_req_card(m_rd_CDMA_mig));
`endif

`ifdef EN_NET
    meta_arbiter #(.DATA_BITS(ARP_LUP_REQ_BITS)) inst_arp_arb (.aclk(aclk), .aresetn(aresetn), .s_meta(arp_lookup_request), .m_meta(m_arp_lookup_request));
`endif

`ifdef EN_RDMA
    meta_arbiter #(.DATA_BITS($bits(rdma_qp_ctx_t)))  inst_rdma_qp_arb   (.aclk(aclk), .aresetn(aresetn), .s_meta(rdma_qp_interface), .m_meta(m_rdma_qp_interface));
    meta_arbiter #(.DATA_BITS($bits(rdma_qp_conn_t))) inst_rdma_conn_arb (.aclk(aclk), .aresetn(aresetn), .s_meta(rdma_conn_interface), .m_meta(m_rdma_conn_interface));
`endif

`ifdef EN_TCP
    meta_arbiter #(.DATA_BITS($bits(tcp_listen_req_r_t))) inst_tcp_listen_req (.aclk(aclk), .aresetn(aresetn), .s_meta(open_port_cmd), .m_meta(m_open_port_cmd));
    meta_dest_mux #(.DATA_BITS($bits(tcp_listen_rsp_r_t))) inst_tcp_listen_req (.aclk(aclk), .aresetn(aresetn), .s_meta(s_open_port_sts), .m_meta(open_port_sts));
    meta_arbiter #(.DATA_BITS($bits(tcp_open_req_r_t)))   inst_tcp_listen_req (.aclk(aclk), .aresetn(aresetn), .s_meta(open_conn_cmd), .m_meta(m_open_conn_cmd));
    meta_dest_mux #(.DATA_BITS($bits(tcp_open_rsp_r_t)))  inst_tcp_listen_req (.aclk(aclk), .aresetn(aresetn), .s_meta(s_open_conn_sts), .m_meta(open_conn_sts));
`endif

`ifdef EN_WB
    meta_arbiter #(.DATA_BITS($bits(wback_t))) inst_meta_arb (.aclk(aclk), .aresetn(aresetn), .s_meta(wback), .m_meta(m_wback));
`endif



/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_MMU_TOP

`endif

endmodule // mmu_top