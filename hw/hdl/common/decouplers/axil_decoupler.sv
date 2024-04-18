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

module axil_decoupler (
	input  logic [N_REGIONS-1:0]	decouple,

	AXI4L.s						s_axi [N_REGIONS],
	AXI4L.m					m_axi [N_REGIONS]
);

// ----------------------------------------------------------------------------------------------------------------------- 
// Decoupling
// ----------------------------------------------------------------------------------------------------------------------- 
`ifdef EN_PR

logic[N_REGIONS-1:0][AXI_ADDR_BITS-1:0] 			s_axi_araddr;
logic[N_REGIONS-1:0][2:0]							s_axi_arprot;
logic[N_REGIONS-1:0][3:0]							s_axi_arqos;
logic[N_REGIONS-1:0][3:0]							s_axi_arregion;
logic[N_REGIONS-1:0]								s_axi_arready;
logic[N_REGIONS-1:0]								s_axi_arvalid;
logic[N_REGIONS-1:0][AXI_ADDR_BITS-1:0] 			s_axi_awaddr;
logic[N_REGIONS-1:0][2:0]							s_axi_awprot;
logic[N_REGIONS-1:0][3:0]							s_axi_awqos;
logic[N_REGIONS-1:0][3:0]							s_axi_awregion;
logic[N_REGIONS-1:0]								s_axi_awready;
logic[N_REGIONS-1:0]								s_axi_awvalid;
logic[N_REGIONS-1:0][AXIL_DATA_BITS-1:0] 			s_axi_rdata;
logic[N_REGIONS-1:0][1:0]							s_axi_rresp;
logic[N_REGIONS-1:0] 								s_axi_rready;
logic[N_REGIONS-1:0]								s_axi_rvalid;
logic[N_REGIONS-1:0][AXIL_DATA_BITS-1:0] 			s_axi_wdata;
logic[N_REGIONS-1:0][AXIL_DATA_BITS/8-1:0] 			s_axi_wstrb;
logic[N_REGIONS-1:0]								s_axi_wready;
logic[N_REGIONS-1:0]								s_axi_wvalid;
logic[N_REGIONS-1:0][1:0]							s_axi_bresp;
logic[N_REGIONS-1:0]								s_axi_bready;
logic[N_REGIONS-1:0]								s_axi_bvalid;

logic[N_REGIONS-1:0][AXI_ADDR_BITS-1:0] 			m_axi_araddr;
logic[N_REGIONS-1:0][2:0]							m_axi_arprot;
logic[N_REGIONS-1:0][3:0]							m_axi_arqos;
logic[N_REGIONS-1:0][3:0]							m_axi_arregion;
logic[N_REGIONS-1:0]								m_axi_arready;
logic[N_REGIONS-1:0]								m_axi_arvalid;
logic[N_REGIONS-1:0][AXI_ADDR_BITS-1:0] 			m_axi_awaddr;
logic[N_REGIONS-1:0][2:0]							m_axi_awprot;
logic[N_REGIONS-1:0][3:0]							m_axi_awqos;
logic[N_REGIONS-1:0][3:0]							m_axi_awregion;
logic[N_REGIONS-1:0]								m_axi_awready;
logic[N_REGIONS-1:0]								m_axi_awvalid;
logic[N_REGIONS-1:0][AXIL_DATA_BITS-1:0] 			m_axi_rdata;
logic[N_REGIONS-1:0][1:0]							m_axi_rresp;
logic[N_REGIONS-1:0] 								m_axi_rready;
logic[N_REGIONS-1:0]								m_axi_rvalid;
logic[N_REGIONS-1:0][AXIL_DATA_BITS-1:0] 			m_axi_wdata;
logic[N_REGIONS-1:0][AXIL_DATA_BITS/8-1:0] 			m_axi_wstrb;
logic[N_REGIONS-1:0]								m_axi_wready;
logic[N_REGIONS-1:0]								m_axi_wvalid;
logic[N_REGIONS-1:0][1:0]							m_axi_bresp;
logic[N_REGIONS-1:0]								m_axi_bready;
logic[N_REGIONS-1:0]								m_axi_bvalid;

// Assign
for(genvar i = 0; i < N_REGIONS; i++) begin
	// In
	assign s_axi_araddr[i] 		= s_axi[i].araddr;
	assign s_axi_arprot[i] 		= s_axi[i].arprot;
	assign s_axi_arqos[i] 		= s_axi[i].arqos;
	assign s_axi_arregion[i] 	= s_axi[i].arregion;
	assign s_axi_arvalid[i] 	= s_axi[i].arvalid;
	assign s_axi[i].arready 	= s_axi_arready[i];

	assign s_axi_awaddr[i] 		= s_axi[i].awaddr;
	assign s_axi_awprot[i] 		= s_axi[i].awprot;
	assign s_axi_awqos[i] 		= s_axi[i].awqos;
	assign s_axi_awregion[i] 	= s_axi[i].awregion;
	assign s_axi_awvalid[i] 	= s_axi[i].awvalid;
	assign s_axi[i].awready 	= s_axi_awready[i];

	assign s_axi[i].rdata 		= s_axi_rdata[i];
	assign s_axi[i].rresp		= s_axi_rresp[i];
	assign s_axi[i].rvalid 		= s_axi_rvalid[i];
	assign s_axi_rready[i]		= s_axi[i].rready;

	assign s_axi_wdata[i]		= s_axi[i].wdata;
	assign s_axi_wstrb[i] 		= s_axi[i].wstrb;
	assign s_axi_wvalid[i]		= s_axi[i].wvalid;
	assign s_axi[i].wready 		= s_axi_wready[i];

	assign s_axi[i].bresp		= s_axi_bresp[i];
	assign s_axi[i].bvalid 		= s_axi_bvalid[i];
	assign s_axi_bready[i] 		= s_axi[i].bready;

	// Out	
	assign m_axi[i].araddr 		= m_axi_araddr[i];
	assign m_axi[i].arprot 		= m_axi_arprot[i];
	assign m_axi[i].arqos 		= m_axi_arqos[i];
	assign m_axi[i].arregion	= m_axi_arregion[i];
	assign m_axi[i].arvalid 	= m_axi_arvalid[i];
	assign m_axi_arready[i] 	= m_axi[i].arready;

	assign m_axi[i].awaddr 		= m_axi_awaddr[i];
	assign m_axi[i].awprot 		= m_axi_awprot[i];
	assign m_axi[i].awqos 		= m_axi_awqos[i];
	assign m_axi[i].awregion	= m_axi_awregion[i];
	assign m_axi[i].awvalid 	= m_axi_awvalid[i];
	assign m_axi_awready[i] 	= m_axi[i].awready;

	assign m_axi_rdata[i]		= m_axi[i].rdata;
	assign m_axi_rresp[i] 		= m_axi[i].rresp;
	assign m_axi_rvalid[i] 		= m_axi[i].rvalid;
	assign m_axi[i].rready 		= m_axi_rready[i];

	assign m_axi[i].wdata 		= m_axi_wdata[i];
	assign m_axi[i].wstrb 		= m_axi_wstrb[i];
	assign m_axi[i].wvalid 		= m_axi_wvalid[i];
	assign m_axi_wready[i] 		= m_axi[i].wready;

	assign m_axi_bresp[i] 		= m_axi[i].bresp;
	assign m_axi_bvalid[i] 		= m_axi[i].bvalid;
	assign m_axi[i].bready 		= m_axi_bready[i];
end

genvar i;
generate
for(i = 0; i < N_REGIONS; i++) begin
	// ar
	assign m_axi_arvalid[i] 	= decouple[i] ? 1'b0 : s_axi_arvalid[i];
	assign s_axi_arready[i]		= decouple[i] ? 1'b0 : m_axi_arready[i];

	assign m_axi_araddr[i] 		= s_axi_araddr[i];
	assign m_axi_arprot[i] 		= s_axi_arprot[i];
	assign m_axi_arqos[i] 		= s_axi_arqos[i];
	assign m_axi_arregion[i] 	= s_axi_arregion[i];

	// aw 
	assign m_axi_awvalid[i] 	= decouple[i] ? 1'b0 : s_axi_awvalid[i];
	assign s_axi_awready[i]		= decouple[i] ? 1'b0 : m_axi_awready[i];

	assign m_axi_awaddr[i] 		= s_axi_awaddr[i];
	assign m_axi_awprot[i] 		= s_axi_awprot[i];
	assign m_axi_awqos[i] 		= s_axi_awqos[i];
	assign m_axi_awregion[i] 	= s_axi_awregion[i];

	// b
	assign s_axi_bvalid[i] 		= decouple[i] ? 1'b0 : m_axi_bvalid[i];
	assign m_axi_bready[i] 		= decouple[i] ? 1'b0 : s_axi_bready[i];

	assign s_axi_bresp[i] 		= m_axi_bresp[i];

	// r
	assign s_axi_rvalid[i] 		= decouple[i] ? 1'b0 : m_axi_rvalid[i];
	assign m_axi_rready[i] 		= decouple[i] ? 1'b0 : s_axi_rready[i];

	assign s_axi_rdata[i] 		= m_axi_rdata[i];
	assign s_axi_rresp[i] 		= m_axi_rresp[i];

	// w
	assign m_axi_wvalid[i] 		= decouple[i] ? 1'b0 : s_axi_wvalid[i];
	assign s_axi_wready[i] 		= decouple[i] ? 1'b0 : m_axi_wready[i];

	assign m_axi_wdata[i] 		= s_axi_wdata[i];
	assign m_axi_wstrb[i] 		= s_axi_wstrb[i];
end
endgenerate

`else

for(genvar i = 0; i < N_REGIONS; i++) begin
    `AXIL_ASSIGN(s_axi[i], m_axi[i])
end

`endif

endmodule
