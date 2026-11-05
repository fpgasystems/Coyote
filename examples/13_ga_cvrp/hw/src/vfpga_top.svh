/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/////////////////////////////////////////////////////////
//              CONTROL REGISTER INTERFACE             //
/////////////////////////////////////////////////////////
// Coyote offers the user CSRs over axi_ctrl, a 64-bit AXI4-Lite bus, while the
// HLS-generated control interface is 32-bit wide. An AXI4-Lite data width
// converter downsizes the 64-bit accesses; since every configured value fits
// into the lower 32 bits of a CSR write, each CSR write programs exactly one
// kernel register.

logic [31:0] hls_ctrl_awaddr;
logic [2:0]  hls_ctrl_awprot;
logic        hls_ctrl_awvalid;
logic        hls_ctrl_awready;
logic [31:0] hls_ctrl_wdata;
logic [3:0]  hls_ctrl_wstrb;
logic        hls_ctrl_wvalid;
logic        hls_ctrl_wready;
logic [1:0]  hls_ctrl_bresp;
logic        hls_ctrl_bvalid;
logic        hls_ctrl_bready;
logic [31:0] hls_ctrl_araddr;
logic [2:0]  hls_ctrl_arprot;
logic        hls_ctrl_arvalid;
logic        hls_ctrl_arready;
logic [31:0] hls_ctrl_rdata;
logic [1:0]  hls_ctrl_rresp;
logic        hls_ctrl_rvalid;
logic        hls_ctrl_rready;

axil_ctrl_dwidth_64_32 inst_axil_ctrl_dwidth (
    .s_axi_aclk(aclk),
    .s_axi_aresetn(aresetn),

    // Slave interface: 64-bit AXI4-Lite, Coyote user CSR bus
    .s_axi_awaddr(axi_ctrl.awaddr[31:0]),
    .s_axi_awprot(axi_ctrl.awprot),
    .s_axi_awvalid(axi_ctrl.awvalid),
    .s_axi_awready(axi_ctrl.awready),
    .s_axi_wdata(axi_ctrl.wdata),
    .s_axi_wstrb(axi_ctrl.wstrb),
    .s_axi_wvalid(axi_ctrl.wvalid),
    .s_axi_wready(axi_ctrl.wready),
    .s_axi_bresp(axi_ctrl.bresp),
    .s_axi_bvalid(axi_ctrl.bvalid),
    .s_axi_bready(axi_ctrl.bready),
    .s_axi_araddr(axi_ctrl.araddr[31:0]),
    .s_axi_arprot(axi_ctrl.arprot),
    .s_axi_arvalid(axi_ctrl.arvalid),
    .s_axi_arready(axi_ctrl.arready),
    .s_axi_rdata(axi_ctrl.rdata),
    .s_axi_rresp(axi_ctrl.rresp),
    .s_axi_rvalid(axi_ctrl.rvalid),
    .s_axi_rready(axi_ctrl.rready),

    // Master interface: 32-bit AXI4-Lite, to the HLS kernel control registers
    .m_axi_awaddr(hls_ctrl_awaddr),
    .m_axi_awprot(hls_ctrl_awprot),
    .m_axi_awvalid(hls_ctrl_awvalid),
    .m_axi_awready(hls_ctrl_awready),
    .m_axi_wdata(hls_ctrl_wdata),
    .m_axi_wstrb(hls_ctrl_wstrb),
    .m_axi_wvalid(hls_ctrl_wvalid),
    .m_axi_wready(hls_ctrl_wready),
    .m_axi_bresp(hls_ctrl_bresp),
    .m_axi_bvalid(hls_ctrl_bvalid),
    .m_axi_bready(hls_ctrl_bready),
    .m_axi_araddr(hls_ctrl_araddr),
    .m_axi_arprot(hls_ctrl_arprot),
    .m_axi_arvalid(hls_ctrl_arvalid),
    .m_axi_arready(hls_ctrl_arready),
    .m_axi_rdata(hls_ctrl_rdata),
    .m_axi_rresp(hls_ctrl_rresp),
    .m_axi_rvalid(hls_ctrl_rvalid),
    .m_axi_rready(hls_ctrl_rready)
);



/////////////////////////////////////////////////////////
//               PROCESSING NODE (HLS)                //
/////////////////////////////////////////////////////////
// Controlled via AXI4-Lite control interface (bundle 'control').
// Configuration is set via scalar argument registers.
// Software starts execution for each generation by writing ap_start (0x01) to offset 0x00.
processing_node_hls_ip inst_pn(
    .ap_clk        (aclk),
    .ap_rst_n      (aresetn),

    // AXI4-Lite control interface (kernel configuration registers)
    .s_axi_control_AWADDR (hls_ctrl_awaddr),
    .s_axi_control_AWVALID(hls_ctrl_awvalid),
    .s_axi_control_AWREADY(hls_ctrl_awready),
    .s_axi_control_WDATA  (hls_ctrl_wdata),
    .s_axi_control_WSTRB  (hls_ctrl_wstrb),
    .s_axi_control_WVALID (hls_ctrl_wvalid),
    .s_axi_control_WREADY (hls_ctrl_wready),
    .s_axi_control_BRESP  (hls_ctrl_bresp),
    .s_axi_control_BVALID (hls_ctrl_bvalid),
    .s_axi_control_BREADY (hls_ctrl_bready),
    .s_axi_control_ARADDR (hls_ctrl_araddr),
    .s_axi_control_ARVALID(hls_ctrl_arvalid),
    .s_axi_control_ARREADY(hls_ctrl_arready),
    .s_axi_control_RDATA  (hls_ctrl_rdata),
    .s_axi_control_RRESP  (hls_ctrl_rresp),
    .s_axi_control_RVALID (hls_ctrl_rvalid),
    .s_axi_control_RREADY (hls_ctrl_rready),

    // AXI-Stream input 0
    .in0_TDATA     (axis_host_recv[0].tdata),
    .in0_TKEEP     (axis_host_recv[0].tkeep),
    .in0_TLAST     (axis_host_recv[0].tlast),
    .in0_TVALID    (axis_host_recv[0].tvalid),
    .in0_TREADY    (axis_host_recv[0].tready),

    // AXI-Stream input 1
    .in1_TDATA     (axis_host_recv[1].tdata),
    .in1_TKEEP     (axis_host_recv[1].tkeep),
    .in1_TLAST     (axis_host_recv[1].tlast),
    .in1_TVALID    (axis_host_recv[1].tvalid),
    .in1_TREADY    (axis_host_recv[1].tready),

    // AXI-Stream output 0
    .out0_TDATA    (axis_host_send[0].tdata),
    .out0_TKEEP    (axis_host_send[0].tkeep),
    .out0_TLAST    (axis_host_send[0].tlast),
    .out0_TVALID   (axis_host_send[0].tvalid),
    .out0_TREADY   (axis_host_send[0].tready),

    // AXI-Stream output 1
    .out1_TDATA    (axis_host_send[1].tdata),
    .out1_TKEEP    (axis_host_send[1].tkeep),
    .out1_TLAST    (axis_host_send[1].tlast),
    .out1_TVALID   (axis_host_send[1].tvalid),
    .out1_TREADY   (axis_host_send[1].tready)
);

// Tie-off unused signals to avoid synthesis problems
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

/*
ila_processing_node inst_ila_processing_node (
    .clk(aclk),
    .probe0(axis_host_recv[0].tvalid),  // 1 bit
    .probe1(axis_host_recv[0].tready),  // 1 bit
    .probe2(axis_host_recv[0].tlast),   // 1 bit
    .probe3(axis_host_recv[0].tdata),   // 512 bits
    .probe4(axis_host_send[0].tvalid),  // 1 bit
    .probe5(axis_host_send[0].tready),  // 1 bit
    .probe6(axis_host_send[0].tlast),   // 1 bit
    .probe7(axis_host_send[0].tdata),   // 512 bits
    .probe8(axis_host_recv[1].tvalid),  // 1 bit
    .probe9(axis_host_recv[1].tready),  // 1 bit
    .probe10(axis_host_recv[1].tlast),   // 1 bit
    .probe11(axis_host_recv[1].tdata),   // 512 bits
    .probe12(axis_host_send[1].tvalid),  // 1 bit
    .probe13(axis_host_send[1].tready),  // 1 bit
    .probe14(axis_host_send[1].tlast),   // 1 bit
    .probe15(axis_host_send[1].tdata)    // 512 bits
);
*/
