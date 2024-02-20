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
  * EVEN IF ADVISED OF THE POSSIBILITY OF    SUCH DAMAGE.
  */

module hbm_wide #(
    parameter integer                      HBM_CHAN_SIZE = 33   
)(
    // Slave
    input  wire [63:0]                     s_axi_araddr,
    input  wire [1:0]                      s_axi_arburst,
    input  wire [3:0]                      s_axi_arcache,
    input  wire [0:0]                      s_axi_arid,
    input  wire [7:0]                      s_axi_arlen,
    input  wire [0:0]                      s_axi_arlock,
    input  wire [2:0]                      s_axi_arprot,
    input  wire [3:0]                      s_axi_arqos,
    input  wire [3:0]                      s_axi_arregion,
    input  wire [2:0]                      s_axi_arsize,
    output wire                            s_axi_arready,
    input  wire                            s_axi_arvalid,
    input  wire [63:0]                     s_axi_awaddr,
    input  wire [1:0]                      s_axi_awburst,
    input  wire [3:0]                      s_axi_awcache,
    input  wire [0:0]                      s_axi_awid,
    input  wire [7:0]                      s_axi_awlen,
    input  wire [0:0]                      s_axi_awlock,
    input  wire [2:0]                      s_axi_awprot,
    input  wire [3:0]                      s_axi_awqos,
    input  wire [3:0]                      s_axi_awregion,
    input  wire [2:0]                      s_axi_awsize,
    output wire                            s_axi_awready,
    input  wire                            s_axi_awvalid,
    output wire [511:0]                    s_axi_rdata,
    output wire [0:0]                      s_axi_rid,
    output wire                            s_axi_rlast,
    output wire [1:0]                      s_axi_rresp,
    input  wire                            s_axi_rready,
    output wire                            s_axi_rvalid,
    input  wire [511:0]                    s_axi_wdata,
    input  wire                            s_axi_wlast,
    input  wire [63:0]                     s_axi_wstrb,
    output wire                            s_axi_wready,
    input  wire                            s_axi_wvalid,
    output wire [0:0]                      s_axi_bid,
    output wire [1:0]                      s_axi_bresp,
    input  wire                            s_axi_bready,
    output wire                            s_axi_bvalid,

    // Master
    output wire [63:0]                     m_axi_0_araddr,
    output wire [1:0]                      m_axi_0_arburst,
    output wire [3:0]                      m_axi_0_arcache,
    output wire [0:0]                      m_axi_0_arid,
    output wire [7:0]                      m_axi_0_arlen,
    output wire [0:0]                      m_axi_0_arlock,
    output wire [2:0]                      m_axi_0_arprot,
    output wire [3:0]                      m_axi_0_arqos,
    output wire [3:0]                      m_axi_0_arregion,
    output wire [2:0]                      m_axi_0_arsize,
    input  wire                            m_axi_0_arready,
    output wire                            m_axi_0_arvalid,
    output wire [63:0]                     m_axi_0_awaddr,
    output wire [1:0]                      m_axi_0_awburst,
    output wire [3:0]                      m_axi_0_awcache,
    output wire [0:0]                      m_axi_0_awid,
    output wire [7:0]                      m_axi_0_awlen,
    output wire [0:0]                      m_axi_0_awlock,
    output wire [2:0]                      m_axi_0_awprot,
    output wire [3:0]                      m_axi_0_awqos,
    output wire [3:0]                      m_axi_0_awregion,
    output wire [2:0]                      m_axi_0_awsize,
    input  wire                            m_axi_0_awready,
    output wire                            m_axi_0_awvalid,
    input  wire [255:0]                    m_axi_0_rdata,
    input  wire [0:0]                      m_axi_0_rid,
    input  wire                            m_axi_0_rlast,
    input  wire [1:0]                      m_axi_0_rresp,
    output wire                            m_axi_0_rready,
    input  wire                            m_axi_0_rvalid,
    output wire [255:0]                    m_axi_0_wdata,
    output wire                            m_axi_0_wlast,
    output wire [31:0]                     m_axi_0_wstrb,
    input  wire                            m_axi_0_wready,
    output wire                            m_axi_0_wvalid,
    input  wire [0:0]                      m_axi_0_bid,
    input  wire [1:0]                      m_axi_0_bresp,
    output wire                            m_axi_0_bready,
    input  wire                            m_axi_0_bvalid,

    output wire [63:0]                     m_axi_1_araddr,
    output wire [1:0]                      m_axi_1_arburst,
    output wire [3:0]                      m_axi_1_arcache,
    output wire [0:0]                      m_axi_1_arid,
    output wire [7:0]                      m_axi_1_arlen,
    output wire [0:0]                      m_axi_1_arlock,
    output wire [2:0]                      m_axi_1_arprot,
    output wire [3:0]                      m_axi_1_arqos,
    output wire [3:0]                      m_axi_1_arregion,
    output wire [2:0]                      m_axi_1_arsize,
    input  wire                            m_axi_1_arready,
    output wire                            m_axi_1_arvalid,
    output wire [63:0]                     m_axi_1_awaddr,
    output wire [1:0]                      m_axi_1_awburst,
    output wire [3:0]                      m_axi_1_awcache,
    output wire [0:0]                      m_axi_1_awid,
    output wire [7:0]                      m_axi_1_awlen,
    output wire [0:0]                      m_axi_1_awlock,
    output wire [2:0]                      m_axi_1_awprot,
    output wire [3:0]                      m_axi_1_awqos,
    output wire [3:0]                      m_axi_1_awregion,
    output wire [2:0]                      m_axi_1_awsize,
    input  wire                            m_axi_1_awready,
    output wire                            m_axi_1_awvalid,
    input  wire [255:0]                    m_axi_1_rdata,
    input  wire [0:0]                      m_axi_1_rid,
    input  wire                            m_axi_1_rlast,
    input  wire [1:0]                      m_axi_1_rresp,
    output wire                            m_axi_1_rready,
    input  wire                            m_axi_1_rvalid,
    output wire [255:0]                    m_axi_1_wdata,
    output wire                            m_axi_1_wlast,
    output wire [31:0]                     m_axi_1_wstrb,
    input  wire                            m_axi_1_wready,
    output wire                            m_axi_1_wvalid,
    input  wire [0:0]                      m_axi_1_bid,
    input  wire [1:0]                      m_axi_1_bresp,
    output wire                            m_axi_1_bready,
    input  wire                            m_axi_1_bvalid,
    
    input  wire                            aclk,
    input  wire                            aresetn
);


localparam integer AXI_HBM_SIZE = 3'b101;
localparam integer AXI_HBM_BITS = 256;

wire [63:0] hbm_ch_size;
assign hbm_ch_size = 1 << (HBM_CHAN_SIZE-1);

// R
wire  rvalid [1:0];
wire  rready [1:0];
wire [255:0] rdata [1:0];
wire  rlast [1:0];
wire  rresp [1:0];

axis_data_fifo_hbm_r inst_fifo_rd_axi_0 (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(m_axi_0_rvalid),
    .s_axis_tready(m_axi_0_rready),
    .s_axis_tdata (m_axi_0_rdata),
    .s_axis_tlast (m_axi_0_rlast),
    .s_axis_tuser (m_axi_0_rresp),
    .m_axis_tvalid(rvalid[0]),
    .m_axis_tready(rready[0]),
    .m_axis_tdata (rdata[0]),
    .m_axis_tlast (rlast[0]),
    .m_axis_tuser (rresp[0])
);

axis_data_fifo_hbm_r inst_fifo_rd_axi_1 (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(m_axi_1_rvalid),
    .s_axis_tready(m_axi_1_rready),
    .s_axis_tdata (m_axi_1_rdata),
    .s_axis_tlast (m_axi_1_rlast),
    .s_axis_tuser (m_axi_1_rresp),
    .m_axis_tvalid(rvalid[1]),
    .m_axis_tready(rready[1]),
    .m_axis_tdata (rdata[1]),
    .m_axis_tlast (rlast[1]),
    .m_axis_tuser (rresp[1])
);

// W
wire wvalid [1:0];
wire wready [1:0];
wire [255:0] wdata   [1:0];
wire [31:0] wstrb [1:0];
wire wlast [1:0];

axis_data_fifo_hbm_w inst_fifo_wr_axi_0 (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(wvalid[0]),
    .s_axis_tready(wready[0]),
    .s_axis_tdata (wdata[0]),
    .s_axis_tstrb (wstrb[0]),
    .s_axis_tlast (wlast[0]),
    .m_axis_tvalid(m_axi_0_wvalid),
    .m_axis_tready(m_axi_0_wready),
    .m_axis_tdata (m_axi_0_wdata),
    .m_axis_tstrb (m_axi_0_wstrb),
    .m_axis_tlast (m_axi_0_wlast)
);

axis_data_fifo_hbm_w inst_fifo_wr_axi_1 (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(wvalid[1]),
    .s_axis_tready(wready[1]),
    .s_axis_tdata (wdata[1]),
    .s_axis_tstrb (wstrb[1]),
    .s_axis_tlast (wlast[1]),
    .m_axis_tvalid(m_axi_1_wvalid),
    .m_axis_tready(m_axi_1_wready),
    .m_axis_tdata (m_axi_1_wdata),
    .m_axis_tstrb (m_axi_1_wstrb),
    .m_axis_tlast (m_axi_1_wlast)
);

// B
wire  bvalid [1:0];
wire  bready [1:0];
wire [1:0] bresp [1:0];

axis_data_fifo_hbm_b inst_fifo_b_axi_0 (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(m_axi_0_bvalid),
    .s_axis_tready(m_axi_0_bready),
    .s_axis_tuser (m_axi_0_bresp),
    .m_axis_tvalid(bvalid[0]),
    .m_axis_tready(bready[0]),
    .m_axis_tuser (bresp[0])
);

axis_data_fifo_hbm_b inst_fifo_b_axi_1 (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(m_axi_1_bvalid),
    .s_axis_tready(m_axi_1_bready),
    .s_axis_tuser (m_axi_1_bresp),
    .m_axis_tvalid(bvalid[1]),
    .m_axis_tready(bready[1]),
    .m_axis_tuser (bresp[1])
);
    
    // AR
    assign m_axi_0_araddr      = s_axi_araddr >> 1;  
    assign m_axi_0_arburst     = s_axi_arburst;
    assign m_axi_0_arcache     = s_axi_arcache;
    assign m_axi_0_arid        = s_axi_arid;
    assign m_axi_0_arlen       = s_axi_arlen;
    assign m_axi_0_arlock      = s_axi_arlock;
    assign m_axi_0_arprot      = s_axi_arprot;
    assign m_axi_0_arqos       = s_axi_arqos;
    assign m_axi_0_arregion    = s_axi_arregion;
    assign m_axi_0_arsize      = AXI_HBM_SIZE;

    assign m_axi_1_araddr      = hbm_ch_size | (s_axi_araddr >> 1);
    assign m_axi_1_arburst     = s_axi_arburst;
    assign m_axi_1_arcache     = s_axi_arcache;
    assign m_axi_1_arid        = s_axi_arid;
    assign m_axi_1_arlen       = s_axi_arlen;
    assign m_axi_1_arlock      = s_axi_arlock;
    assign m_axi_1_arprot      = s_axi_arprot;
    assign m_axi_1_arqos       = s_axi_arqos;
    assign m_axi_1_arregion    = s_axi_arregion;
    assign m_axi_1_arsize      = AXI_HBM_SIZE;

    assign s_axi_arready       = m_axi_0_arready & m_axi_1_arready;
    assign m_axi_0_arvalid     = s_axi_arready & s_axi_arvalid;   
    assign m_axi_1_arvalid     = s_axi_arready & s_axi_arvalid;  

    // AW
    assign m_axi_0_awaddr      = s_axi_awaddr >> 1;
    assign m_axi_0_awburst     = s_axi_awburst;
    assign m_axi_0_awcache     = s_axi_awcache;
    assign m_axi_0_awid        = s_axi_awid;
    assign m_axi_0_awlen       = s_axi_awlen;
    assign m_axi_0_awlock      = s_axi_awlock;
    assign m_axi_0_awprot      = s_axi_awprot;
    assign m_axi_0_awqos       = s_axi_awqos;
    assign m_axi_0_awregion    = s_axi_awregion;
    assign m_axi_0_awsize      = AXI_HBM_SIZE;

    assign m_axi_1_awaddr      = hbm_ch_size | (s_axi_awaddr >> 1);
    assign m_axi_1_awburst     = s_axi_awburst;
    assign m_axi_1_awcache     = s_axi_awcache;
    assign m_axi_1_awid        = s_axi_awid;
    assign m_axi_1_awlen       = s_axi_awlen;
    assign m_axi_1_awlock      = s_axi_awlock;
    assign m_axi_1_awprot      = s_axi_awprot;
    assign m_axi_1_awqos       = s_axi_awqos;
    assign m_axi_1_awregion    = s_axi_awregion;
    assign m_axi_1_awsize      = AXI_HBM_SIZE;

    assign s_axi_awready       = m_axi_0_awready & m_axi_1_awready;
    assign m_axi_0_awvalid     = s_axi_awready & s_axi_awvalid;   
    assign m_axi_1_awvalid     = s_axi_awready & s_axi_awvalid;   

    // R
    assign s_axi_rdata         = {rdata[1], rdata[0]};
    assign s_axi_rid           = 0;
    assign s_axi_rlast         = rlast[0];
    assign s_axi_rresp         = ((rresp[0] == 0) && (rresp[1] == 0)) ? 0 : 1;

    assign s_axi_rvalid        = rvalid[0] & rvalid[1];
    assign rready[0]           = s_axi_rvalid & s_axi_rready;
    assign rready[1]           = s_axi_rvalid & s_axi_rready;

    // W
    assign wdata[0]            = s_axi_wdata[0+:AXI_HBM_BITS];
    assign wdata[1]            = s_axi_wdata[AXI_HBM_BITS+:AXI_HBM_BITS];
    assign wlast[0]            = s_axi_wlast;
    assign wlast[1]            = s_axi_wlast;
    assign wstrb[0]            = s_axi_wstrb[0+:AXI_HBM_BITS/8];
    assign wstrb[1]            = s_axi_wstrb[AXI_HBM_BITS/8+:AXI_HBM_BITS/8];

    assign s_axi_wready        = wready[0] & wready[1];
    assign wvalid[0]           = s_axi_wvalid & s_axi_wready;
    assign wvalid[1]           = s_axi_wvalid & s_axi_wready;

    // B
    assign s_axi_bid           = 0;
    assign s_axi_resp          = ((bresp[0] == 0) && (bresp[1] == 0)) ? 0 : 1;

    assign s_axi_bvalid        = bvalid[0] & bvalid[1];
    assign bready[0]           = s_axi_bvalid & s_axi_bready;
    assign bready[1]           = s_axi_bvalid & s_axi_bready;
    
endmodule