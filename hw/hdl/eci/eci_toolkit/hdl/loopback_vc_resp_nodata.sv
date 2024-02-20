/*
    Copyright (c) 2022 ETH Zurich.
    All rights reserved.

    This file is distributed under the terms in the attached LICENSE file.
    If you do not find this file, copies can be found by writing to:
    ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
*/

/*
 * Systems Group, D-INFK, ETH Zurich
 *
 * Author  : A.Ramdas
 * Date    : 2020-06-29
 * Project : Enzian
 *
 */

`ifndef LOOPBACK_VC_RESP_NODATA_SV
`define LOOPBACK_VC_RESP_NODATA_SV

import eci_cmd_defs::*;

/*
 * Module Description:
 *  This module is used to generate no-data responses to ECI requests
 *  The input ECI request comes with valid ready flow control
 *  For this request, a response is generated COMBINATORIALLY within one clock cycle
 *  The ECI response is then sent out using valid, ready flow controls
 *  The response function is parameterized same module can be used to generate different responses
 *
 * Input Output Description:
 *  ECI Request Input stream: Input 64-bit ECI request with valid-ready flow control
 *  ECI Response output stream: Output 64-bit ECI response (no-payload) with valid-ready flow control
 *
 * Architecture Description:
 *  Parameters are used to choose which request-response function is to be instantiated
 *  Only 1 req-resp function can be defined for a given instance
 *  A controller takes care of input and output valid-ready flow control
 *
 * Modifiable Parameters:
 *  WORD_WIDTH - width of ECI request
 *  GSDN_GSYNC_FN - Generate GSDN response for GSYNC request
 *
 *  NOTE: Of all *_FN parameters, only 1 of them can be 1 for an instance, the rest should be 0
 *  This is validated using an assertion
 *
 * Non-modifiable Parameters:
 *  None
 *
 * Modules Used:
 *  Function definitions included in eci_cmd_defs package, eci_fn_defs header
 *
 * Notes:
 * * Supports only combinational request-response transformation function
 * * Each instance can have only 1 request-response transformation function
 * * ready before valid pipeline
 *
 */


/////////////////////////////////////////////////////////////////////////////////////
//                        +-------------------+					   //
//                1*64    | Parameterizable   |  1*64  +--------+ 1*64		   //
//   ECI Req  +----/----->+ Combinational     +--/---->+ Reg    +--/---> ECI Resp  //
//   w/o data             | Response          |        +--------+        w/o data  //
//                        | Generator         |					   //
//                        |                   |        +--------+   1		   //
//                        +-------------------+   +--->+ Reg    +---/---> ECI Resp //
//                                                |    +--------+         Valid	   //
//               1        +-------------------+   |				   //
// ECI Req +-----/------->+ Valid Ready       +---+				   //
// Valid                  | Handshake         |            1			   //
//            +------+    | Controller        +<-----------/------------+ ECI Resp //
// ECI Req <--+ Reg  +<---+                   |                           Ready	   //
// Ready      +------+    |                   |					   //
//                        +-------------------+					   //
/////////////////////////////////////////////////////////////////////////////////////


module loopback_vc_resp_nodata #
  (
   parameter WORD_WIDTH = 64,
   parameter GSDN_GSYNC_FN = 1
   )
   (
    input logic 		  clk, reset,

    // ECI Request input stream
    input logic [WORD_WIDTH-1:0]  vc_req_i,
    input logic 		  vc_req_valid_i,
    output logic 		  vc_req_ready_o,

    // ECI Response output stream
    output logic [WORD_WIDTH-1:0] vc_resp_o,
    output logic 		  vc_resp_valid_o,
    input logic 		  vc_resp_ready_i
    );

   // Assertions
   initial begin
      // Only 1 function for each instantiation
      // TODO - add assertion when adding another function
      if( GSDN_GSYNC_FN == 0 ) begin
	 $error("Error: Atleast 1 function must be enabled (instance %m)");
	 $finish;
      end
   end

   //Register the outputs
   logic [WORD_WIDTH-1:0] 	  vc_resp_reg = '0, vc_resp_next;
   logic 			  vc_resp_valid_reg = '0, vc_resp_valid_next;
   logic 			  vc_req_ready_reg = '0, vc_req_ready_next;

   //Handshake signals
   logic 			  ip_hs, op_hs;

   //Assign registers to output signals
   assign vc_resp_o = vc_resp_reg;
   assign vc_resp_valid_o = vc_resp_valid_reg;
   assign vc_req_ready_o = vc_req_ready_reg;

   //Assign handshake
   assign ip_hs = vc_req_valid_i & vc_req_ready_o;
   assign op_hs = vc_resp_valid_o & vc_resp_ready_i;

   //Output of function
   logic [WORD_WIDTH-1:0] 	  this_resp;

   // Generate different hardware based on parameters
   // Functions are defined in eci_fn_defs
   generate
      if( GSDN_GSYNC_FN == 1 ) begin
	 assign this_resp = gsdn_for_gsync(vc_req_i);
      end
   endgenerate

   // Valid ready controller
   // Does not wait for valid to be asserted before asserting ready at input
   // ready before valid signalling
   always_comb begin : CONTROLLER
      vc_resp_next = vc_resp_reg;
      vc_resp_valid_next = vc_resp_valid_reg;
      vc_req_ready_next = vc_req_ready_reg;

      if( ~vc_resp_valid_o & ~ip_hs) begin
	 vc_req_ready_next = 1'b1;
      end else if( ip_hs ) begin
	 vc_resp_next = this_resp;
	 vc_resp_valid_next = 1'b1;
	 vc_req_ready_next  = 1'b0;
      end else if( op_hs ) begin
	 vc_resp_valid_next = 1'b0;
	 vc_req_ready_next  = 1'b1;
      end
   end : CONTROLLER

   always_ff @(posedge clk) begin : REG_ASSIGN
      if( reset ) begin
	 // No reset for vc_resp_reg to minimize reset fanout
	 vc_resp_valid_reg <= 0;
	 vc_req_ready_reg  <= 0;
      end else begin
	 vc_resp_reg       <= vc_resp_next;
	 vc_resp_valid_reg <= vc_resp_valid_next;
	 vc_req_ready_reg  <= vc_req_ready_next;
      end
   end : REG_ASSIGN

//ila_vc_loopback i_ila_vc_loopback
//(
//    .clk(clk),
//    .probe0  (vc_req_i),
//    .probe1  (vc_req_valid_i),
//    .probe2  (vc_req_ready_reg),

//    // ECI Response output stream
//    .probe3  (vc_resp_reg),
//    .probe4  (vc_resp_valid_reg),
//    .probe5  (vc_resp_ready_i)
//);

endmodule
`endif
