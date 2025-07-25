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

`ifndef AXI_ECI_RD_RESP_2VC_SV
`define AXI_ECI_RD_RESP_2VC_SV

import eci_cmd_defs::*;
import block_types::*;

 module axi_eci_rd_resp_2vc (
    input  logic 						                    aclk,
    input  logic 						                    aresetn,
    // AXI R
    output logic [ECI_ID_WIDTH-1:0]                         s_axi_rid,
    output logic [ECI_CL_WIDTH-1:0]                         s_axi_rdata,
    output logic 						                    s_axi_rvalid,
    input  logic 						                    s_axi_rready,
    //MOB VC interface - FROM CPU
    input  logic [17-1:0][ECI_WORD_WIDTH-1:0]               mob_vc_data_i,
    input  logic [4:0]                                      mob_vc_size_i,
    input  logic 						                    mob_vc_valid_i,
    output logic 						                    mob_vc_ready_o
);

    // Header casted into ECI type
    eci_word_t psha_resp_hdr;
    
    // TMP
    logic [17-1:0][ECI_WORD_WIDTH-1:0]                mob_vc_data_tmp;
    logic [4:0]                   mob_vc_size_tmp;
    logic 						                      mob_vc_valid_tmp;
    logic 						                      mob_vc_ready_tmp;
    /*
    ila_rd_resp inst_ila_rd_resp (
        .clk(aclk),
        .probe0(s_axi_rid), // 5
        .probe1(s_axi_rdata[63:0]), // 64
        .probe2(s_axi_rvalid),
        .probe3(s_axi_rready),
        .probe4(mob_vc_data_i[0]), // 64
        .probe5(mob_vc_size_i), // 5
        .probe6(mob_vc_valid_i),
        .probe7(mob_vc_ready_o)
    );
    */
    // Slice    
    axis_reg_array_vc #(
        .N_STAGES(3)
    ) inst_vc_reg (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(mob_vc_data_i),
        .s_axis_tuser(mob_vc_size_i),
        .s_axis_tvalid(mob_vc_valid_i),
        .s_axis_tready(mob_vc_ready_o),
        .m_axis_tdata(mob_vc_data_tmp),
        .m_axis_tuser(mob_vc_size_tmp),
        .m_axis_tvalid(mob_vc_valid_tmp),
        .m_axis_tready(mob_vc_ready_tmp)
    );
        
    // DP
    always_comb begin
        psha_resp_hdr = mob_vc_data_tmp[0];

        s_axi_rid = psha_resp_hdr.psha.rreq_id;
        s_axi_rdata = mob_vc_data_tmp[ECI_PACKET_SIZE-1:1];
        s_axi_rvalid = mob_vc_valid_tmp;
        mob_vc_ready_tmp = s_axi_rready;
    end

endmodule
`endif
