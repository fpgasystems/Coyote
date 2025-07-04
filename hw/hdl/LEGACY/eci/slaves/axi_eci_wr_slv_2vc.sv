/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

`ifndef AXI_ECI_WR_SLV_2VC_SV
`define AXI_ECI_WR_SLV_2VC_SV

import eci_cmd_defs::*;
import block_types::*;

module axi_eci_wr_slv_2vc (
  input logic 					                                aclk,
  input logic 					                                aresetn,

  // Write Address AW channel 
  input  logic [ECI_ID_WIDTH-1:0] 			                    s_axi_awid,
  input  logic [ECI_ADDR_WIDTH-1:0] 		                    s_axi_awaddr,
  input  logic [7:0] 					                        s_axi_awlen,
  input  logic 					                                s_axi_awvalid,
  output logic 					                                s_axi_awready,

  // Write data W channel
  input  logic [ECI_CL_WIDTH-1:0] 			                    s_axi_wdata,
  input  logic [(ECI_CL_WIDTH/8)-1:0] 	                        s_axi_wstrb,
  input  logic 					                                s_axi_wlast,
  input  logic 					                                s_axi_wvalid,
  output logic 					                                s_axi_wready,

  // Write response B channel
  output logic [ECI_ID_WIDTH-1:0] 		                        s_axi_bid,
  output logic [1:0] 					                        s_axi_bresp,
  output logic 					                                s_axi_bvalid,
  input  logic 					                                s_axi_bready,

  // Write data to VC
  output logic [17-1:0][ECI_WORD_WIDTH-1:0]                     vc_pkt_o,
  output logic [4:0] 		                                    vc_pkt_size_o,
  output logic 					                                vc_pkt_valid_o,
  input  logic 					                                vc_pkt_ready_i,

  // Write response from VC
  input  logic [ECI_WORD_WIDTH-1:0]                             vc_pkt_i,
  input  logic [4:0] 		                                    vc_pkt_size_i,
  input  logic 					                                vc_pkt_valid_i,
  output logic 					                                vc_pkt_ready_o
);

  // WR request slave
  axi_eci_wr_req_2vc inst_wr_req_slv (
    .aclk               (aclk),
    .aresetn            (aresetn),

    // AXI slave
    .s_axi_awid         (s_axi_awid),
    .s_axi_awaddr       (s_axi_awaddr),
    .s_axi_awlen        (s_axi_awlen),
    .s_axi_awvalid      (s_axi_awvalid),
    .s_axi_awready      (s_axi_awready),

    .s_axi_wdata        (s_axi_wdata),
    .s_axi_wstrb        (s_axi_wstrb),
    .s_axi_wlast        (s_axi_wlast),
    .s_axi_wvalid       (s_axi_wvalid),
    .s_axi_wready       (s_axi_wready),

    // Write requests to CPU
    .vc_pkt_o           (vc_pkt_o),
    .vc_pkt_size_o      (vc_pkt_size_o),
    .vc_pkt_valid_o     (vc_pkt_valid_o),
    .vc_pkt_ready_i     (vc_pkt_ready_i)
  );

  axi_eci_wr_resp_2vc inst_wr_resp_slv (
    .aclk               (aclk),
    .aresetn            (aresetn),

    // AXI slave
    .s_axi_bid          (s_axi_bid),
    .s_axi_bresp        (s_axi_bresp),
    .s_axi_bvalid       (s_axi_bvalid),
    .s_axi_bready       (s_axi_bready),
    
    // Write responses from the CPU
    .vc_pkt_i           (vc_pkt_i),
    .vc_pkt_size_i      (vc_pkt_size_i),
    .vc_pkt_valid_i     (vc_pkt_valid_i),
    .vc_pkt_ready_o     (vc_pkt_ready_o)
	);
   

endmodule // axi_eci_wr_slv
`endif
