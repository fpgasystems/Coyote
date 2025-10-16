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

import lynxTypes::*;


// Tie-off unused signals to avoid synthesis problems
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb axi_ctrl.tie_off_s();

logic [255:0] debug;

axis_host_send[0].tkeep <= '1;
axis_host_send[1].tkeep <= '1;

multes_coyote_hacktoplevel multes (
      .aclk(aclk),
      .aresetn(aresetn),
      
      .in_pack_tdata (axis_host_recv[0].tdata), 
      .in_pack_tvalid(axis_host_recv[0].tvalid), 
      .in_pack_tlast (axis_host_recv[0].tlast),  
      .in_pack_tready(axis_host_recv[0].tready),

      .in_meta_tdata  (axis_host_recv[1].tdata),  
      .in_meta_tvalid (axis_host_recv[1].tvalid), 
      .in_meta_tlast  (axis_host_recv[1].tlast),  
      .in_meta_tready (axis_host_recv[1].tready), 

      .out_pack_tdata   (axis_host_send[0].tdata),  
      .out_pack_tvalid  (axis_host_send[0].tvalid), 
      .out_pack_tlast   (axis_host_send[0].tlast),  
      .out_pack_tready  (axis_host_send[0].tready), 
      
      .out_meta_tdata  (axis_host_send[1].tdata),     
      .out_meta_tvalid (axis_host_send[1].tvalid),    
      .out_meta_tlast  (axis_host_send[1].tlast),     
      .out_meta_tready (axis_host_send[1].tready),    
      
      .debug(debug)
      
);

// Integrated Logic Analyzer (ILA) for debugging on hardware
// Fairly simple ILA, primary meant as an example, to be extended when debugging actual bugs
// See the README.md and init_ip.tcl for more details on how to use and configure ILA
ila_perf_host inst_ila_perf_host (
    .clk(aclk),
    .probe0(axis_host_recv[0].tvalid),  // 1 bit
    .probe1(axis_host_recv[0].tready),  // 1 bit
    .probe2(axis_host_recv[0].tlast),   // 1 bit
    .probe3(axis_host_recv[0].tdata),   // 512 bits
    .probe4(axis_host_send[0].tvalid),  // 1 bit
    .probe5(axis_host_send[0].tready),  // 1 bit
    .probe6(axis_host_send[0].tlast),   // 1 bit
    .probe7(debug)    // 512 bits
);

