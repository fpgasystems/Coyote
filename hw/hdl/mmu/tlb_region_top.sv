/**
 * TLB top
 * 
 * Top level TLB for sub-regions
 */

import lynxTypes::*;

module tlb_region_top #(
	parameter integer 					ID_REG = 0	
) (
	input logic        					aclk,    
	input logic    						aresetn,
	
	// AXI tlb control
	AXI4L.s 							axi_ctrl_lTlb,
	AXI4L.s 							axi_ctrl_sTlb,

`ifdef EN_AVX
	// AXI config
	AXI4.s   							axim_ctrl_cnfg,
`else
	// AXIL Config
	AXI4L.s 							axi_ctrl_cnfg,
`endif	

`ifdef EN_BPSS
	// Requests user
	reqIntf.s 						    rd_req_user,
	reqIntf.s						    wr_req_user,
`endif

`ifdef EN_FV
	// FV request
	metaIntf.m  						rdma_req,
`endif

`ifdef EN_STRM
	// Stream DMAs
    dmaIntf.m                           rdHDMA,
    dmaIntf.m                           wrHDMA,

    // Credits
    input  logic                        rxfer_host,
    input  logic                        wxfer_host,
    output logic [3:0]                  rd_dest_host,
`endif

`ifdef EN_DDR
    // Card DMAs
    dmaIntf.m                           rdDDMA,
    dmaIntf.m                           wrDDMA,
    dmaIsrIntf.m                        IDMA,
    dmaIsrIntf.m                        SDMA,

    // Credits
    input  logic                        rxfer_card,
    input  logic                        wxfer_card,
    output logic [3:0]                  rd_dest_card,
`endif

	// Decoupling
	output logic 		                decouple,
	
	// Page fault IRQ
	output logic                    	pf_irq
);

// -- Decl -----------------------------------------------------------------------------------
// -------------------------------------------------------------------------------------------
// Tlb interfaces
tlbIntf #(.N_ASSOC(N_L_ASSOC)) rd_lTlb ();
tlbIntf #(.N_ASSOC(N_S_ASSOC)) rd_sTlb ();
tlbIntf #(.N_ASSOC(N_L_ASSOC)) wr_lTlb ();
tlbIntf #(.N_ASSOC(N_S_ASSOC)) wr_sTlb ();
tlbIntf #(.N_ASSOC(N_L_ASSOC)) lTlb ();
tlbIntf #(.N_ASSOC(N_S_ASSOC)) sTlb ();

// Config interfaces
cnfgIntf rd_cnfg ();
cnfgIntf wr_cnfg ();

// Request interfaces
reqIntf rd_req ();
reqIntf wr_req ();

// Mutex
logic [1:0] mutex;
logic rd_lock, wr_lock;
logic rd_unlock, wr_unlock;

// ----------------------------------------------------------------------------------------
// Mutex 
// ----------------------------------------------------------------------------------------
always_ff @(posedge aclk or negedge aresetn) begin
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
assign lTlb.addr = mutex[1] ? wr_lTlb.addr : rd_lTlb.addr;
assign sTlb.addr = mutex[1] ? wr_sTlb.addr : rd_sTlb.addr;

// TLB 2M
tlb_slave #(
    .TLB_ORDER(TLB_L_ORDER),
    .PG_BITS(PG_L_BITS),
    .N_ASSOC(N_L_ASSOC)
) inst_lTlb (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl_lTlb),
    .TLB(lTlb)
);

// TLB 4K
tlb_slave #(
    .TLB_ORDER(TLB_S_ORDER),
    .PG_BITS(PG_S_BITS),
    .N_ASSOC(N_S_ASSOC)
) inst_sTlb (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl_sTlb),
    .TLB(sTlb)
);

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
		.axim_ctrl(axim_ctrl_cnfg),
`else
		.axi_ctrl(axi_ctrl_cnfg),
`endif
`ifdef EN_BPSS
		.rd_req_user(rd_req_user),
		.wr_req_user(wr_req_user),
`endif
`ifdef EN_FV
		.rdma_req(rdma_req),
`endif
		.rd_cnfg(rd_cnfg),
		.wr_cnfg(wr_cnfg),
		.rd_req(rd_req),
		.wr_req(wr_req),
		.decouple(decouple),
		.pf_irq(pf_irq)
	);

// ----------------------------------------------------------------------------------------
// Parsing
// ----------------------------------------------------------------------------------------
reqIntf rd_req_parsed ();
reqIntf wr_req_parsed ();
reqIntf rd_req_parsed_q ();
reqIntf wr_req_parsed_q ();

tlb_parser inst_rd_parser (.aclk(aclk), .aresetn(aresetn), .req_in(rd_req), .req_out(rd_req_parsed));
tlb_parser inst_wr_parser (.aclk(aclk), .aresetn(aresetn), .req_in(wr_req), .req_out(wr_req_parsed));

// Queueing
req_queue inst_rd_q_parser (.aclk(aclk), .aresetn(aresetn), .req_in(rd_req_parsed), .req_out(rd_req_parsed_q));
req_queue inst_wr_q_parser (.aclk(aclk), .aresetn(aresetn), .req_in(wr_req_parsed), .req_out(wr_req_parsed_q));

// ----------------------------------------------------------------------------------------
// FSM
// ----------------------------------------------------------------------------------------
`ifdef EN_STRM
    // FSM
    dmaIntf rdHDMA_fsm ();
    dmaIntf wrHDMA_fsm ();
    
    dmaIntf rdHDMA_fsm_q ();
    dmaIntf wrHDMA_fsm_q ();

    // Credits
    dmaIntf rdHDMA_cred ();
    dmaIntf wrHDMA_cred ();
`endif

`ifdef EN_DDR
    dmaIntf rdDDMA_fsm ();
    dmaIntf wrDDMA_fsm ();
    dmaIsrIntf rdIDMA_fsm ();
    dmaIsrIntf wrIDMA_fsm ();
    dmaIsrIntf IDMA_fsm ();
    dmaIsrIntf SDMA_fsm ();

    dmaIntf rdDDMA_fsm_q ();
    dmaIntf wrDDMA_fsm_q ();
    
    // Credits
    dmaIntf rdDDMA_cred ();
    dmaIntf wrDDMA_cred ();
`endif

// TLB rd FSM
tlb_fsm_rd #(
    .ID_REG(ID_REG)   
) inst_fsm_rd (
    .aclk(aclk),
    .aresetn(aresetn),
    .lTlb(rd_lTlb),
    .sTlb(rd_sTlb),
    .cnfg(rd_cnfg),
    .req_in(rd_req_parsed_q),
`ifdef EN_STRM
    .HDMA(rdHDMA_fsm),
`endif
`ifdef EN_DDR
    .DDMA(rdDDMA_fsm),
    .IDMA(rdIDMA_fsm),
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
    .cnfg(wr_cnfg),
    .req_in(wr_req_parsed_q),
`ifdef EN_STRM
    .HDMA(wrHDMA_fsm),
`endif
`ifdef EN_DDR
    .DDMA(wrDDMA_fsm),
    .IDMA(wrIDMA_fsm),
    .SDMA(SDMA_fsm),
`endif
    .lock(wr_lock),
	.unlock(wr_unlock),
	.mutex(mutex)
);

// Queueing
`ifdef EN_STRM
    // HDMA
    dma_req_queue inst_rd_q_fsm_hdma (.aclk(aclk), .aresetn(aresetn), .req_in(rdHDMA_fsm), .req_out(rdHDMA_fsm_q));
    dma_req_queue inst_wr_q_fsm_hdma (.aclk(aclk), .aresetn(aresetn), .req_in(wrHDMA_fsm), .req_out(wrHDMA_fsm_q));
`endif

`ifdef EN_DDR
    // IDMA arbitration
    tlb_idma_arb inst_idma_arb (.aclk(aclk), .aresetn(aresetn), .mutex(mutex[1]), .rd_idma(rdIDMA_fsm), .wr_idma(wrIDMA_fsm), .idma(IDMA_fsm));

    // DDMA
    dma_req_queue inst_rd_q_fsm_ddma (.aclk(aclk), .aresetn(aresetn), .req_in(rdDDMA_fsm), .req_out(rdDDMA_fsm_q));
    dma_req_queue inst_wr_q_fsm_ddma (.aclk(aclk), .aresetn(aresetn), .req_in(wrDDMA_fsm), .req_out(wrDDMA_fsm_q));

    // IDMA
    dma_isr_req_queue inst_q_fsm_idma (.aclk(aclk), .aresetn(aresetn), .req_in(IDMA_fsm), .req_out(IDMA));
    
    // SDMA
    dma_isr_req_queue inst_q_fsm_sdma (.aclk(aclk), .aresetn(aresetn), .req_in(SDMA_fsm), .req_out(SDMA));
`endif

// ----------------------------------------------------------------------------------------
// Credits and output
// ----------------------------------------------------------------------------------------
`ifdef EN_STRM
    // HDMA
    tlb_credits_rd #(.ID_REG(ID_REG)) inst_rd_cred_hdma (.aclk(aclk), .aresetn(aresetn), .req_in(rdHDMA_fsm_q), .req_out(rdHDMA_cred), .rxfer(rxfer_host), .rd_dest(rd_dest_host));
    tlb_credits_wr #(.ID_REG(ID_REG)) inst_wr_cred_hdma (.aclk(aclk), .aresetn(aresetn), .req_in(wrHDMA_fsm_q), .req_out(wrHDMA_cred), .wxfer(wxfer_host));

    // Queueing
    dma_req_queue inst_rd_q_cred_hdma (.aclk(aclk), .aresetn(aresetn), .req_in(rdHDMA_cred), .req_out(rdHDMA));
    dma_req_queue inst_wr_q_cred_hdma (.aclk(aclk), .aresetn(aresetn), .req_in(wrHDMA_cred), .req_out(wrHDMA));
`endif

`ifdef EN_DDR
    // DDMA
    tlb_credits_rd #(.ID_REG(ID_REG), .CRED_DATA_BITS(N_DDR_CHAN*AXI_DATA_BITS)) inst_rd_cred_ddma (.aclk(aclk), .aresetn(aresetn), .req_in(rdDDMA_fsm_q), .req_out(rdDDMA_cred), .rxfer(rxfer_card), .rd_dest(rd_dest_card));
    tlb_credits_wr #(.ID_REG(ID_REG), .CRED_DATA_BITS(N_DDR_CHAN*AXI_DATA_BITS)) inst_wr_cred_ddma (.aclk(aclk), .aresetn(aresetn), .req_in(wrDDMA_fsm_q), .req_out(wrDDMA_cred), .wxfer(wxfer_card));

    // Queueing
    dma_req_queue inst_rd_q_cred_ddma (.aclk(aclk), .aresetn(aresetn), .req_in(rdDDMA_cred), .req_out(rdDDMA));
    dma_req_queue inst_wr_q_cred_ddma (.aclk(aclk), .aresetn(aresetn), .req_in(wrDDMA_cred), .req_out(wrDDMA));
`endif

endmodule // tlb_top