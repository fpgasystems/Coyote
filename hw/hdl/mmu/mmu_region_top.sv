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
 * @brief   Top level MMU for a single vFPGA
 *
 * Top level of a single vFPGA TLB, feeds into the top level arbitration.
 *
 *  @param ID_REG   Number of associated vFPGA
 */
module mmu_region_top #(
	parameter integer 					ID_REG = 0	
) (
	// AXI tlb control and writeback
    AXI4L.s   							s_axi_ctrl_sTlb,
    AXI4L.s   							s_axi_ctrl_lTlb,

	// Requests user
	metaIntf.s 						    s_bpss_rd_sq,
	metaIntf.s						    s_bpss_wr_sq,

`ifdef EN_STRM
	// Stream DMAs
    dmaIntf.m                           m_rd_HDMA,
    dmaIntf.m                           m_wr_HDMA,
    metaIntf.m                          m_rd_host_done,
    metaIntf.m                          m_wr_host_done,

`ifndef EN_CRED_LOCAL
    input  logic                        rxfer_host,
    input  logic                        wxfer_host,
`endif
`endif

`ifdef EN_MEM
    // Card DMAs
    dmaIntf.m                           m_rd_DDMA [N_CARD_AXI],
    dmaIntf.m                           m_wr_DDMA [N_CARD_AXI],
    metaIntf.m                          m_rd_card_done,
    metaIntf.m                          m_wr_card_done,

`ifndef EN_CRED_LOCAL
    input  logic                        rxfer_card [N_CARD_AXI],
    input  logic                        wxfer_card [N_CARD_AXI],
`endif
`endif

    metaIntf.m                          m_rd_pfault_irq,
    output logic [LEN_BITS-1:0]         m_rd_pfault_rng,
    metaIntf.s                          s_rd_pfault_ctrl,
    metaIntf.m                          m_wr_pfault_irq,
    output logic [LEN_BITS-1:0]         m_wr_pfault_rng,
    metaIntf.s                          s_wr_pfault_ctrl,

    metaIntf.s                          s_rd_invldt_ctrl,
    metaIntf.m                          m_rd_invldt_irq,
    metaIntf.s                          s_wr_invldt_ctrl,
    metaIntf.m                          m_wr_invldt_irq,
    
    input logic        					aclk,    
	input logic    						aresetn
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
localparam integer TLB_L_DATA_BITS = TAG_L_BITS + PID_BITS + 2 + PHY_L_BITS + HPID_BITS;
localparam integer TLB_S_DATA_BITS = TAG_S_BITS + PID_BITS + 2 + PHY_S_BITS + HPID_BITS;

// Tlb interfaces
tlbIntf #(.TLB_INTF_DATA_BITS(TLB_L_DATA_BITS)) rd_lTlb ();
tlbIntf #(.TLB_INTF_DATA_BITS(TLB_S_DATA_BITS)) rd_sTlb ();
tlbIntf #(.TLB_INTF_DATA_BITS(TLB_L_DATA_BITS)) wr_lTlb ();
tlbIntf #(.TLB_INTF_DATA_BITS(TLB_S_DATA_BITS)) wr_sTlb ();
tlbIntf #(.TLB_INTF_DATA_BITS(TLB_L_DATA_BITS)) lTlb ();
tlbIntf #(.TLB_INTF_DATA_BITS(TLB_S_DATA_BITS)) sTlb ();

AXI4S #(.AXI4S_DATA_BITS(AXI_TLB_BITS)) axis_lTlb ();
AXI4S #(.AXI4S_DATA_BITS(AXI_TLB_BITS)) axis_sTlb ();

// Request interfaces
metaIntf #(.STYPE(req_t)) rd_req ();
metaIntf #(.STYPE(req_t)) wr_req ();

// ----------------------------------------------------------------------------------------
// Mutex 
// ----------------------------------------------------------------------------------------
logic [1:0] mutex;
logic rd_lock, wr_lock;
logic rd_unlock, wr_unlock;

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
assign lTlb.strm  = mutex[1] ? wr_lTlb.strm : rd_lTlb.strm;
assign sTlb.strm  = mutex[1] ? wr_sTlb.strm : rd_sTlb.strm;
assign lTlb.wr    = mutex[1] ? wr_lTlb.wr : rd_lTlb.wr;
assign sTlb.wr    = mutex[1] ? wr_sTlb.wr : rd_sTlb.wr;
assign lTlb.valid = mutex[1] ? wr_lTlb.valid : rd_lTlb.valid;
assign sTlb.valid = mutex[1] ? wr_sTlb.valid : rd_sTlb.valid;

// TLBs
tlb_controller #(
    .TLB_ORDER(TLB_L_ORDER),
    .PG_BITS(PG_L_BITS),
    .N_ASSOC(N_L_ASSOC),
    .DBG_L(1),
    .ID_REG(ID_REG)
) inst_lTlb (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axis(axis_lTlb),
    .TLB(lTlb)
);

tlb_controller #(
    .TLB_ORDER(TLB_S_ORDER),
    .PG_BITS(PG_S_BITS),
    .N_ASSOC(N_S_ASSOC),
    .DBG_S(1),
    .ID_REG(ID_REG)
) inst_sTlb (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axis(axis_sTlb),
    .TLB(sTlb)
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
    .m_axis(axis_lTlb)
);

tlb_slave_axil #(
    .TLB_ORDER(TLB_S_ORDER),
    .PG_BITS(PG_S_BITS),
    .N_ASSOC(N_S_ASSOC)
) inst_sTlb_slv_0 (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axi_ctrl(s_axi_ctrl_sTlb),
    .m_axis(axis_sTlb)
);

// ----------------------------------------------------------------------------------------
// FSM
// ----------------------------------------------------------------------------------------
`ifdef EN_STRM
    // FSM
    dmaIntf rd_HDMA_fsm ();
    dmaIntf wr_HDMA_fsm ();
    
    // Queue
    dmaIntf rd_HDMA_fsm_q ();
    dmaIntf wr_HDMA_fsm_q ();

    // Parsing
    dmaIntf rd_HDMA_parsed ();
    dmaIntf wr_HDMA_parsed ();

    // Credits
    dmaIntf rd_HDMA_cred ();
    dmaIntf wr_HDMA_cred ();
`endif

`ifdef EN_MEM
    // FSM
    dmaIntf rd_DDMA_fsm [N_CARD_AXI] ();
    dmaIntf wr_DDMA_fsm [N_CARD_AXI] ();

    // Queue
    dmaIntf rd_DDMA_fsm_q [N_CARD_AXI] ();
    dmaIntf wr_DDMA_fsm_q [N_CARD_AXI] ();

    // Parsing
    dmaIntf rd_DDMA_parsed [N_CARD_AXI] ();
    dmaIntf wr_DDMA_parsed [N_CARD_AXI] ();

    // Credits
    dmaIntf rd_DDMA_cred [N_CARD_AXI] ();
    dmaIntf wr_DDMA_cred [N_CARD_AXI] ();
`endif

// TLB rd FSM
tlb_fsm #(
    .ID_REG(ID_REG),
    .RDWR(0)
) inst_fsm_rd (
    .aclk(aclk),
    .aresetn(aresetn),
    .lTlb(rd_lTlb),
    .sTlb(rd_sTlb),
`ifdef EN_STRM
    .m_host_done(m_rd_host_done),
    .m_HDMA(rd_HDMA_fsm),
`endif
`ifdef EN_MEM
    .m_card_done(m_rd_card_done),
    .m_DDMA(rd_DDMA_fsm),
`endif
    .s_req(s_bpss_rd_sq),

    .m_pfault(m_rd_pfault_irq),
    .m_pfault_rng(m_rd_pfault_rng),
    .s_pfault(s_rd_pfault_ctrl),

    .s_invldt(s_rd_invldt_ctrl),
    .m_invldt(m_rd_invldt_irq),

    .lock(rd_lock),
	.unlock(rd_unlock),
	.mutex(mutex)
);

// TLB wr FSM
tlb_fsm #(
    .ID_REG(ID_REG),
    .RDWR(1)
) inst_fsm_wr (
    .aclk(aclk),
    .aresetn(aresetn),
    .lTlb(wr_lTlb),
    .sTlb(wr_sTlb),
`ifdef EN_STRM
    .m_host_done(m_wr_host_done),
    .m_HDMA(wr_HDMA_fsm),
`endif
`ifdef EN_MEM
    .m_card_done(m_wr_card_done),
    .m_DDMA(wr_DDMA_fsm),
`endif
    .s_req(s_bpss_wr_sq),

    .m_pfault(m_wr_pfault_irq),
    .m_pfault_rng(m_wr_pfault_rng),
    .s_pfault(s_wr_pfault_ctrl),

    .s_invldt(s_wr_invldt_ctrl),
    .m_invldt(m_wr_invldt_irq),

    .lock(wr_lock),
	.unlock(wr_unlock),
	.mutex(mutex)
);

// ----------------------------------------------------------------------------------------
// Queueing stage
// ----------------------------------------------------------------------------------------
`ifdef EN_STRM
    // HDMA
    dma_req_queue inst_rd_q_fsm_hdma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_HDMA_fsm), .m_req(rd_HDMA_fsm_q));
    dma_req_queue inst_wr_q_fsm_hdma (.aclk(aclk), .aresetn(aresetn), .s_req(wr_HDMA_fsm), .m_req(wr_HDMA_fsm_q));

    // Parsing 
`ifndef EN_CRED_LOCAL
    dma_parser inst_rd_parser (.aclk(aclk), .aresetn(aresetn), .s_req(rd_HDMA_fsm_q), .m_req(rd_HDMA_parsed));
    dma_parser inst_wr_parser (.aclk(aclk), .aresetn(aresetn), .s_req(wr_HDMA_fsm_q), .m_req(wr_HDMA_parsed));
`else
    `DMA_REQ_ASSIGN(rd_HDMA_fsm_q, rd_HDMA_parsed)
    `DMA_REQ_ASSIGN(wr_HDMA_fsm_q, wr_HDMA_parsed)
`endif
`endif

`ifdef EN_MEM
    for(genvar i = 0; i < N_CARD_AXI; i++) begin
        // DDMA
        dma_req_queue inst_rd_q_fsm_ddma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_DDMA_fsm[i]), .m_req(rd_DDMA_fsm_q[i]));
        dma_req_queue inst_wr_q_fsm_ddma (.aclk(aclk), .aresetn(aresetn), .s_req(wr_DDMA_fsm[i]), .m_req(wr_DDMA_fsm_q[i]));
    end

    // Parsing 
`ifndef EN_CRED_LOCAL
    for(genvar i = 0; i < N_CARD_AXI; i++) begin
        dma_parser inst_rd_parser (.aclk(aclk), .aresetn(aresetn), .s_req(rd_DDMA_fsm_q[i]), .m_req(rd_DDMA_parsed[i]));
        dma_parser inst_wr_parser (.aclk(aclk), .aresetn(aresetn), .s_req(wr_DDMA_fsm_q[i]), .m_req(wr_DDMA_parsed[i]));
    end
`else
    for(genvar i = 0; i < N_CARD_AXI; i++) begin
        `DMA_REQ_ASSIGN(rd_DDMA_fsm_q[i], rd_DDMA_parsed[i])
        `DMA_REQ_ASSIGN(wr_DDMA_fsm_q[i], wr_DDMA_parsed[i])
    end
`endif
`endif

// ----------------------------------------------------------------------------------------
// Credits and output
// ----------------------------------------------------------------------------------------
`ifndef EN_CRED_LOCAL

`ifdef EN_STRM
    // HDMA
    mmu_credits_rd #(.ID_REG(ID_REG)) inst_rd_cred_hdma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_HDMA_parsed), .m_req(rd_HDMA_cred), .rxfer(rxfer_host));
    mmu_credits_wr #(.ID_REG(ID_REG)) inst_wr_cred_hdma (.aclk(aclk), .aresetn(aresetn), .s_req(wr_HDMA_parsed), .m_req(wr_HDMA_cred), .wxfer(wxfer_host));

    // Queueing
    dma_req_queue inst_rd_q_cred_hdma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_HDMA_cred), .m_req(m_rd_HDMA));
    dma_req_queue inst_wr_q_cred_hdma (.aclk(aclk), .aresetn(aresetn), .s_req(wr_HDMA_cred), .m_req(m_wr_HDMA));
`endif

`ifdef EN_MEM
    for(genvar i = 0; i < N_CARD_AXI; i++) begin
        // DDMA
        mmu_credits_rd #(.ID_REG(ID_REG)) inst_rd_cred_ddma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_DDMA_parsed[i]), .m_req(rd_DDMA_cred[i]), .rxfer(rxfer_card[i]));
        mmu_credits_wr #(.ID_REG(ID_REG)) inst_wr_cred_ddma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_DDMA_parsed[i]), .m_req(wr_DDMA_cred[i]), .wxfer(wxfer_card[i]));

        // Queueing
        dma_req_queue inst_rd_q_cred_ddma (.aclk(aclk), .aresetn(aresetn), .s_req(rd_DDMA_cred[i]), .m_req(m_rd_DDMA[i]));
        dma_req_queue inst_wr_q_cred_ddma (.aclk(aclk), .aresetn(aresetn), .s_req(wr_DDMA_cred[i]), .m_req(m_wr_DDMA[i]));
    end
`endif

`else

`ifdef EN_STRM
    `DMA_REQ_ASSIGN(rd_HDMA_parsed, m_rd_HDMA)
    `DMA_REQ_ASSIGN(wr_HDMA_parsed, m_wr_HDMA)
`endif

`ifdef EN_MEM
    for(genvar i = 0; i < N_CARD_AXI; i++) begin
        `DMA_REQ_ASSIGN(rd_DDMA_parsed[i], m_rd_DDMA[i])
        `DMA_REQ_ASSIGN(wr_DDMA_parsed[i], m_wr_DDMA[i])
    end
`endif

`endif

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_MMU_REGION_TOP

`endif

endmodule // mmu_region_top