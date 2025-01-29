`ifndef AXI_ECI_RD_SLV_2VC_SV
`define AXI_ECI_RD_SLV_2VC_SV

import eci_cmd_defs::*;
import block_types::*;

import lynxTypes::*;

module axi_eci_rd_slv_2vc (
  input  logic 						                              aclk,
  input  logic 						                              aresetn,

  // Read Address Channel
  input  logic [ECI_ID_WIDTH-1:0] 			                s_axi_arid,
  input  logic [ECI_ADDR_WIDTH-1:0] 			              s_axi_araddr,
  input  logic [7:0] 					                          s_axi_arlen,
  input  logic 						                              s_axi_arvalid,
  output logic 						                              s_axi_arready,

  // Read Data Channel
  output logic [ECI_ID_WIDTH-1:0] 			                s_axi_rid,
  output logic [ECI_CL_WIDTH-1:0] 			                s_axi_rdata,
  output logic [1:0]                                    s_axi_rresp,
  output logic                                          s_axi_rlast,
  output logic 						                              s_axi_rvalid,
  input  logic 						                              s_axi_rready,

  //MIB VC interface - TO CPU
  output logic [ECI_WORD_WIDTH-1:0]                     mib_vc_data_o,
  output logic [4:0] 		                                mib_vc_size_o,
  output logic 						                              mib_vc_valid_o,
  input  logic 						                              mib_vc_ready_i,

  //MOB VC interface - FROM CPU
  input  logic [17-1:0][ECI_WORD_WIDTH-1:0]             mob_vc_data_i,
  input  logic [4:0] 		                                mob_vc_size_i,
  input  logic 						                              mob_vc_valid_i,
  output logic 						                              mob_vc_ready_o
);

  // RD request slave
  axi_eci_rd_req_2vc inst_rd_req_slv (
    .aclk               (aclk),
    .aresetn            (aresetn),

    // AXI slave
    .s_axi_arid         (s_axi_arid),
    .s_axi_araddr       (s_axi_araddr),
    .s_axi_arlen        (s_axi_arlen),
    .s_axi_arvalid      (s_axi_arvalid),
    .s_axi_arready      (s_axi_arready),
    
    // Read requests to CPU 
    .mib_vc_data_o      (mib_vc_data_o),
    .mib_vc_size_o      (mib_vc_size_o),
    .mib_vc_valid_o     (mib_vc_valid_o),
    .mib_vc_ready_i     (mib_vc_ready_i)
	);

  // RD response slave
  axi_eci_rd_resp_2vc inst_rd_resp_slv (
    .aclk               (aclk),
    .aresetn            (aresetn),

    // AXI slave
    .s_axi_rid          (s_axi_rid),
    .s_axi_rdata        (s_axi_rdata),
    .s_axi_rvalid       (s_axi_rvalid),
    .s_axi_rready       (s_axi_rready),

    // Read responses from the CPU
    .mob_vc_data_i      (mob_vc_data_i),
    .mob_vc_size_i      (mob_vc_size_i),
    .mob_vc_valid_i     (mob_vc_valid_i),
    .mob_vc_ready_o     (mob_vc_ready_o)
	);

  assign s_axi_rresp = 0;
  assign s_axi_rlast = 1'b0;

endmodule // axi_eci_rd_slv

`endif
