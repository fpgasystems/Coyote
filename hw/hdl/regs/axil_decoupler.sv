import lynxTypes::*;

module axil_decoupler (
	input  logic [N_REGIONS-1:0]	decouple,

	AXI4L.s 						axi_in [N_REGIONS],
	AXI4L.m 						axi_out [N_REGIONS]
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Decoupling --------------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
logic[AXI_ADDR_BITS-1:0] 			axi_in_araddr;
logic[2:0]							axi_in_arprot;
logic[3:0]							axi_in_arqos;
logic[3:0]							axi_in_arregion;
logic								axi_in_arready;
logic								axi_in_arvalid;
logic[AXI_ADDR_BITS-1:0] 			axi_in_awaddr;
logic[2:0]							axi_in_awprot;
logic[3:0]							axi_in_awqos;
logic[3:0]							axi_in_awregion;
logic								axi_in_awready;
logic								axi_in_awvalid;
logic[AXIL_DATA_BITS-1:0] 			axi_in_rdata;
logic[1:0]							axi_in_rresp;
logic 								axi_in_rready;
logic								axi_in_rvalid;
logic[AXIL_DATA_BITS-1:0] 			axi_in_wdata;
logic[AXIL_DATA_BITS/8-1:0] 		axi_in_wstrb;
logic								axi_in_wready;
logic								axi_in_wvalid;
logic[1:0]							axi_in_bresp;
logic								axi_in_bready;
logic								axi_in_bvalid;

logic[AXI_ADDR_BITS-1:0] 			axi_out_araddr;
logic[2:0]							axi_out_arprot;
logic[3:0]							axi_out_arqos;
logic[3:0]							axi_out_arregion;
logic								axi_out_arready;
logic								axi_out_arvalid;
logic[AXI_ADDR_BITS-1:0] 			axi_out_awaddr;
logic[2:0]							axi_out_awprot;
logic[3:0]							axi_out_awqos;
logic[3:0]							axi_out_awregion;
logic								axi_out_awready;
logic								axi_out_awvalid;
logic[AXIL_DATA_BITS-1:0] 			axi_out_rdata;
logic[1:0]							axi_out_rresp;
logic 								axi_out_rready;
logic								axi_out_rvalid;
logic[AXIL_DATA_BITS-1:0] 			axi_out_wdata;
logic[AXIL_DATA_BITS/8-1:0] 		axi_out_wstrb;
logic								axi_out_wready;
logic								axi_out_wvalid;
logic[1:0]							axi_out_bresp;
logic								axi_out_bready;
logic								axi_out_bvalid;

// Assign
for(genvar i = 0; i < N_REGIONS; i++) begin
	// In
	assign axi_in_araddr[i] 	= axi_in[i].araddr;
	assign axi_in_arprot[i] 	= axi_in[i].arprot;
	assign axi_in_arqos[i] 		= axi_in[i].arqos;
	assign axi_in_arregion[i] 	= axi_in[i].arregion;
	assign axi_in_arvalid[i] 	= axi_in[i].arvalid;
	assign axi_in[i].arready 	= axi_in_arready[i];

	assign axi_in_awaddr[i] 	= axi_in[i].awaddr;
	assign axi_in_awprot[i] 	= axi_in[i].awprot;
	assign axi_in_awqos[i] 		= axi_in[i].awqos;
	assign axi_in_awregion[i] 	= axi_in[i].awregion;
	assign axi_in_awvalid[i] 	= axi_in[i].awvalid;
	assign axi_in[i].awready 	= axi_in_awready[i];

	assign axi_in[i].rdata 		= axi_in_rdata[i];
	assign axi_in[i].rresp		= axi_in_rresp[i];
	assign axi_in[i].rvalid 	= axi_in_rvalid[i];
	assign axi_in_rready[i]		= axi_in[i].rready;

	assign axi_in_wdata[i]		= axi_in[i].wdata;
	assign axi_in_wstrb[i] 		= axi_in[i].wstrb;
	assign axi_in_wvalid[i]		= axi_in[i].wvalid;
	assign axi_in[i].wready 	= axi_in_wready[i];

	assign axi_in[i].bresp		= axi_in_bresp[i];
	assign axi_in[i].bvalid 	= axi_in_bvalid[i];
	assign axi_in_bready[i] 	= axi_in[i].bready;

	// Out	
	assign axi_out[i].araddr 	= axi_out_araddr[i];
	assign axi_out[i].arprot 	= axi_out_arprot[i];
	assign axi_out[i].arqos 	= axi_out_arqos[i];
	assign axi_out[i].arregion	= axi_out_arregion[i];
	assign axi_out[i].arvalid 	= axi_out_arvalid[i];
	assign axi_out_arready[i] 	= axi_out[i].arready;

	assign axi_out[i].awaddr 	= axi_out_awaddr[i];
	assign axi_out[i].awprot 	= axi_out_awprot[i];
	assign axi_out[i].awqos 	= axi_out_awqos[i];
	assign axi_out[i].awregion	= axi_out_awregion[i];
	assign axi_out[i].awvalid 	= axi_out_awvalid[i];
	assign axi_out_awready[i] 	= axi_out[i].awready;

	assign axi_out_rdata[i]		= axi_out[i].rdata;
	assign axi_out_rresp[i] 	= axi_out[i].rresp;
	assign axi_out_rvalid[i] 	= axi_out[i].rvalid;
	assign axi_out[i].rready 	= axi_out_rready[i];

	assign axi_out[i].wdata 	= axi_out_wdata[i];
	assign axi_out[i].wstrb 	= axi_out_wstrb[i];
	assign axi_out[i].wvalid 	= axi_out_wvalid[i];
	assign axi_out_wready[i] 	= axi_out[i].wready;

	assign axi_out_bresp[i] 	= axi_out[i].bresp;
	assign axi_out_bvalid[i] 	= axi_out[i].bvalid;
	assign axi_out[i].bready 	= axi_out_bready[i];
end

genvar i;
generate
for(i = 0; i < N_REGIONS; i++) begin
	// ar
	assign axi_out_arvalid[i] 	= decouple[i] ? 1'b0 : axi_in_arvalid[i];
	assign axi_in_arready[i]	= decouple[i] ? 1'b0 : axi_out_arready[i];

	assign axi_out_araddr[i] 	= axi_in_araddr[i];
	assign axi_out_arprot[i] 	= axi_in_arprot[i];
	assign axi_out_arqos[i] 	= axi_in_arqos[i];
	assign axi_out_arregion[i] 	= axi_in_arregion[i];

	// aw 
	assign axi_out_arvalid[i] 	= decouple[i] ? 1'b0 : axi_in_arvalid[i];
	assign axi_in_arready[i]	= decouple[i] ? 1'b0 : axi_out_arready[i];

	assign axi_out_awaddr[i] 	= axi_in_awaddr[i];
	assign axi_out_awprot[i] 	= axi_in_awprot[i];
	assign axi_out_awqos[i] 	= axi_in_awqos[i];
	assign axi_out_awregion[i] 	= axi_in_awregion[i];

	// b
	assign axi_in_bvalid[i] 	= decouple[i] ? 1'b0 : axi_out_bvalid[i];
	assign axi_out_bready[i] 	= decouple[i] ? 1'b0 : axi_in_bready[i];

	assign axi_in_bresp[i] 		= axi_out_bresp[i];

	// r
	assign axi_in_rvalid[i] 	= decouple[i] ? 1'b0 : axi_out_rvalid[i];
	assign axi_out_rready[i] 	= decouple[i] ? 1'b0 : axi_in_rready[i];

	assign axi_in_rdata[i] 		= axi_out_rdata[i];
	assign axi_in_rresp[i] 		= axi_out_rresp[i];

	// w
	assign axi_out_wvalid[i] 	= decouple[i] ? 1'b0 : axi_in_wvalid[i];
	assign axi_in_wready[i] 	= decouple[i] ? 1'b0 : axi_out_wready[i];

	assign axi_out_wdata[i] 	= axi_in_wdata[i];
	assign axi_out_wstrb[i] 	= axi_in_wstrb[i];
end
endgenerate

endmodule
