/**
 * TLB top
 * 
 * Top level TLB for sub-regions
 */

import lynxTypes::*;

`include "lynx_macros.svh"

module tlb_top #(
	parameter integer 					ID_DYN = 0	
) (
	input logic        					aclk,    
	input logic    						aresetn,
	
	// AXI tlb control
	AXI4L.s 							axi_ctrl_lTlb [N_REGIONS],
	AXI4L.s 							axi_ctrl_sTlb [N_REGIONS],

`ifdef EN_AVX
	// AXI config
	AXI4.s   							axim_ctrl_cnfg [N_REGIONS],
`else
	// AXIL Config
	AXI4L.s 							axi_ctrl_cnfg [N_REGIONS],
`endif	

`ifdef EN_BPSS
	// Requests user
	reqIntf.s 						    rd_req_user [N_REGIONS],
	reqIntf.s						    wr_req_user [N_REGIONS],
`endif

`ifdef EN_FV
	// FV request
	metaIntf.m  						rdma_req [N_REGIONS],
`endif

`ifdef EN_STRM
	// Stream DMAs
    dmaIntf.m                           rdXDMA_host,
    dmaIntf.m                           wrXDMA_host,

    input  logic [N_REGIONS-1:0]        rxfer_host,
    input  logic [N_REGIONS-1:0]        wxfer_host,
    output logic [N_REGIONS-1:0][3:0]   rd_dest_host,
`endif

`ifdef EN_DDR
    // Card DMAs
    dmaIntf.m                           rdXDMA_sync,
    dmaIntf.m                           wrXDMA_sync,
	dmaIntf.m 							rdCDMA_sync,
	dmaIntf.m 							wrCDMA_sync,
    dmaIntf.m                           rdCDMA_card,
    dmaIntf.m                           wrCDMA_card,

    input  logic [N_REGIONS-1:0]        rxfer_card,
    input  logic [N_REGIONS-1:0]        wxfer_card,
    output logic [N_REGIONS-1:0][3:0]   rd_dest_card,
`endif

`ifdef MULT_REGIONS
    `ifdef EN_STRM
        // Mux user host
        muxUserIntf.s  						mux_host_rd_user,
        muxUserIntf.s   					mux_host_wr_user,
    `endif
    `ifdef EN_DDR
        // Mux user host
        muxUserIntf.s  						mux_card_rd_user,
        muxUserIntf.s   					mux_card_wr_user,
    `endif
`endif

	// Decoupling
	output logic [N_REGIONS-1:0]		decouple,
	
	// Page fault IRQ
	output logic [N_REGIONS-1:0]    	pf_irq
);

//
`ifdef EN_STRM
    dmaIntf rdHDMA_arb [N_REGIONS] ();
    dmaIntf wrHDMA_arb [N_REGIONS] ();
`endif

`ifdef EN_DDR
    dmaIntf rdDDMA_arb [N_REGIONS] ();
    dmaIntf wrDDMA_arb [N_REGIONS] ();

    dmaIsrIntf IDMA_arb [N_REGIONS] ();
    dmaIsrIntf SDMA_arb [N_REGIONS] ();
`endif

// Instantiate region TLBs
for(genvar i = 0; i < N_REGIONS; i++) begin
    
    tlb_region_top #(.ID_REG(ID_DYN*N_REGIONS+i)) inst_reg_top (
        .aclk(aclk),
        .aresetn(aresetn),
        .axi_ctrl_sTlb(axi_ctrl_sTlb[i]),
        .axi_ctrl_lTlb(axi_ctrl_lTlb[i]),
    `ifdef EN_AVX
		.axim_ctrl_cnfg(axim_ctrl_cnfg[i]),
    `else
        .axi_ctrl_cnfg(axi_ctrl_cnfg[i]),
    `endif
    `ifdef EN_BPSS
		.rd_req_user(rd_req_user[i]),
		.wr_req_user(wr_req_user[i]),
    `endif
    `ifdef EN_FV
		.rdma_req(rdma_req[i]),
    `endif
    `ifdef EN_STRM
        .rdHDMA(rdHDMA_arb[i]),
        .wrHDMA(wrHDMA_arb[i]),
        .rxfer_host(rxfer_host[i]),
        .wxfer_host(wxfer_host[i]),
        .rd_dest_host(rd_dest_host[i]),
    `endif
    `ifdef EN_DDR
        .rdDDMA(rdDDMA_arb[i]),
        .wrDDMA(wrDDMA_arb[i]),
        .IDMA(IDMA_arb[i]),
        .SDMA(SDMA_arb[i]),
        .rxfer_card(rxfer_card[i]),
        .wxfer_card(wxfer_card[i]),
        .rd_dest_card(rd_dest_card[i]),
    `endif
        .decouple(decouple[i]),
        .pf_irq(pf_irq[i])
    );

end

// Instantiate arbitration
`ifdef MULT_REGIONS
    
    // Arbiters
    `ifdef EN_STRM
        tlb_arbiter inst_hdma_arb_rd (.aclk(aclk), .aresetn(aresetn), .req_snk(rdHDMA_arb), .req_src(rdXDMA_host), .mux_user(mux_host_rd_user));
        tlb_arbiter inst_hdma_arb_wr (.aclk(aclk), .aresetn(aresetn), .req_snk(wrHDMA_arb), .req_src(wrXDMA_host), .mux_user(mux_host_wr_user));
    `endif

    `ifdef EN_DDR
        tlb_arbiter inst_ddma_arb_rd (.aclk(aclk), .aresetn(aresetn), .req_snk(rdDDMA_arb), .req_src(rdCDMA_card), .mux_user(mux_card_rd_user));
        tlb_arbiter inst_ddma_arb_wr (.aclk(aclk), .aresetn(aresetn), .req_snk(wrDDMA_arb), .req_src(wrCDMA_card), .mux_user(mux_card_wr_user));

        tlb_arbiter_isr #(.RDWR(0)) inst_idma_arb (.aclk(aclk), .aresetn(aresetn), .req_snk(IDMA_arb), .req_src_host(rdXDMA_sync), .req_src_card(wrCDMA_sync));
        tlb_arbiter_isr #(.RDWR(1)) inst_sdma_arb (.aclk(aclk), .aresetn(aresetn), .req_snk(SDMA_arb), .req_src_host(wrXDMA_sync), .req_src_card(rdCDMA_sync));
    `endif

`else

    `ifdef EN_STRM
        `DMA_REQ_ASSIGN(rdHDMA_arb[0], rdXDMA_host)
        `DMA_REQ_ASSIGN(wrHDMA_arb[0], wrXDMA_host)
    `endif

    `ifdef EN_DDR
        `DMA_REQ_ASSIGN(rdDDMA_arb[0], rdCDMA_card)
        `DMA_REQ_ASSIGN(wrDDMA_arb[0], wrCDMA_card)

        tlb_assign_isr #(.RDWR(0)) inst_idma_arb (.aclk(aclk), .aresetn(aresetn), .req_snk(IDMA_arb[0]), .req_src_host(rdXDMA_sync), .req_src_card(wrCDMA_sync));
        tlb_assign_isr #(.RDWR(1)) inst_sdma_arb (.aclk(aclk), .aresetn(aresetn), .req_snk(SDMA_arb[0]), .req_src_host(wrXDMA_sync), .req_src_card(rdCDMA_sync));
    `endif

`endif

endmodule // tlb_top