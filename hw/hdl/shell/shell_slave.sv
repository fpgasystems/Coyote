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

import lynxTypes::*;

module shell_slave (
  input  logic              aclk,
  input  logic              aresetn,

`ifdef EN_NET
  // IP
  metaIntf.m                m_set_ip_addr,
  metaIntf.m                m_set_mac_addr,
`endif

`ifdef EN_RDMA
  output logic [63:0]       m_ddr_offset_addr_rdma,
`endif

`ifdef EN_TCP
  output logic [63:0]       m_ddr_offset_addr_tcp,
`endif

  // Decouple app
  output logic [N_REGIONS-1:0]  m_decouple,
  output logic [N_REGIONS-1:0]  m_rst_pr,

  // Stats
`ifdef EN_STATS
  `ifdef EN_XCH_0
    input xdma_stat_t               s_xdma_stats_0,
  `endif
  `ifdef EN_XCH_1
    input xdma_stat_t               s_xdma_stats_1,
  `endif
  `ifdef EN_NET
    input net_stat_t                s_net_stats,
  `endif
`endif 

  // Control bus (HOST)
  AXI4L.s                   s_axi_ctrl
);

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------

// Constants
localparam integer N_REGS = 128;
localparam integer ADDR_LSB = $clog2(AXIL_DATA_BITS/8);
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer AXIL_ADDR_BITS = ADDR_LSB + ADDR_MSB;

localparam integer N_ID = 2 * N_REGIONS;
localparam integer N_ID_BITS = $clog2(N_ID);
localparam integer BEAT_LOG_BITS = $clog2(AXI_DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;

// Internal registers
logic [AXIL_ADDR_BITS-1:0] axi_awaddr;
logic axi_awready;
logic [AXIL_ADDR_BITS-1:0] axi_araddr;
logic axi_arready;
logic [1:0] axi_bresp;
logic axi_bvalid;
logic axi_wready;
logic [AXIL_DATA_BITS-1:0] axi_rdata;
logic [1:0] axi_rresp;
logic axi_rvalid;

// Registers
logic [N_REGS-1:0][AXIL_DATA_BITS-1:0] slv_reg;
logic slv_reg_rden;
logic slv_reg_wren;
logic aw_en;

// -- Def -----------------------------------------------------------
// ------------------------------------------------------------------

// -- Register map ----------------------------------------------------------------------- 
// CONFIG
// 0 (RW) : Probe
localparam integer PROBE_REG              = 0;
// 1 (RO) : Number of channels
localparam integer N_CHAN_REG             = 1;
// 2 (RO) : Number of regions
localparam integer N_REGIONS_REG          = 2;
// 3 (RO) : Control config
localparam integer CTRL_CNFG_REG          = 3;
// 4 (RO) : Memory config
localparam integer MEM_CNFG_REG           = 4;
// 5 (RO) : Partial reconfiguration config
localparam integer PR_CNFG_REG            = 5;
// 6 (RO) : RDMA config
localparam integer RDMA_CNFG_REG          = 6;
// 7 (RO) : TCP/IP config
localparam integer TCP_CNFG_REG           = 7; 
// 9, 10 (W1S|W1C|R) : Datapath control set/clear
localparam integer CTRL_DP_REG_SET        = 8;
localparam integer CTRL_DP_REG_CLR        = 9;
  localparam integer CTRL_DP_DECOUPLE  = 0;
// NETWORK 
// 32 (RW) : IP address
localparam integer NET_IPADDR_REG         = 32;
// 33 (RW) : MAC address 
localparam integer NET_MACADDR_REG        = 33;
// 34 - (RW) : TCP/IP ddr offset
localparam integer TCP_OFFS_REG           = 34;
// 35 - (RW) : RDMA ddr offset
localparam integer RDMA_OFFS_REG          = 35;

// XDMA STATS
localparam integer XDMA_STAT_0_BPSS       = 64;
localparam integer XDMA_STAT_0_CMPL       = 65;
localparam integer XDMA_STAT_0_AXIS       = 66;
localparam integer XDMA_STAT_1_BPSS       = 67;
localparam integer XDMA_STAT_1_CMPL       = 68;
localparam integer XDMA_STAT_1_AXIS       = 69;

// NET STATS
localparam integer NET_STAT_PKG_REG       = 96;
localparam integer NET_STAT_ARP_REG       = 97;
localparam integer NET_STAT_ICMP_REG      = 98;
localparam integer NET_STAT_TCP_REG       = 99;
localparam integer NET_STAT_RDMA_REG      = 100;
localparam integer NET_STAT_IBV_REG       = 101;
localparam integer NET_STAT_DROP_REG      = 102;
localparam integer NET_STAT_SESS_REG      = 103;
localparam integer NET_STAT_DOWN_REG      = 104;

// ---------------------------------------------------------------------------------------- 
// Write process 
// ----------------------------------------------------------------------------------------
assign slv_reg_wren = axi_wready && s_axi_ctrl.wvalid && axi_awready && s_axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg <= 'X;
    slv_reg[CTRL_DP_REG_SET][63:32] <= 1'b1;

`ifdef EN_NET
    m_set_ip_addr.valid <= 1'b0;
    m_set_mac_addr.valid <= 1'b0;
`endif

`ifdef EN_RDMA
    slv_reg[RDMA_OFFS_REG] <= 0;
`endif 

`ifdef EN_TCP
    slv_reg[TCP_OFFS_REG] <= 0;
`endif

  end
  else begin

`ifdef EN_NET
    m_set_ip_addr.valid <= 1'b0;
    m_set_mac_addr.valid <= 1'b0;
`endif

    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        CTRL_DP_REG_SET: // Datapath control set
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[CTRL_DP_REG_SET][(i*8)+:8] <= slv_reg[CTRL_DP_REG_SET][(i*8)+:8] | s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CTRL_DP_REG_CLR: // Datapath control clear
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[CTRL_DP_REG_SET][(i*8)+:8] <= slv_reg[CTRL_DP_REG_SET][(i*8)+:8] & ~s_axi_ctrl.wdata[(i*8)+:8];
            end
          end

`ifdef EN_NET
        NET_IPADDR_REG: // IP address
          for (int i = 0; i < 4; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              m_set_ip_addr.data[(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
              m_set_ip_addr.valid <= 1'b1;
            end
          end
        NET_MACADDR_REG: // MAC address
          for (int i = 0; i < MAC_ADDR_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              m_set_mac_addr.data[(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
              m_set_mac_addr.valid <= 1'b1;
            end
          end
 `endif
          
`ifdef EN_RDMA
        RDMA_OFFS_REG: // RDMA offset
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_OFFS_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
`endif

`ifdef EN_TCP
        TCP_OFFS_REG: // TCP offset
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[TCP_OFFS_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
`endif

        default : ;
      endcase
    end
  end
end    

// ---------------------------------------------------------------------------------------- 
// Read process 
// ----------------------------------------------------------------------------------------
assign slv_reg_rden = axi_arready & s_axi_ctrl.arvalid & ~axi_rvalid;

always_ff @(posedge aclk) begin
  if( aresetn == 1'b0 ) begin
    axi_rdata <= 'X;
  end
  else begin
    if(slv_reg_rden) begin
      axi_rdata <= 0;

      case (axi_araddr[ADDR_LSB+:ADDR_MSB])
        PROBE_REG:
          axi_rdata <= SHELL_PROBE;
        N_CHAN_REG: // Number of channels
          axi_rdata <= N_CHAN;
        N_REGIONS_REG: // Number of regions
          axi_rdata <= N_REGIONS;
        CTRL_CNFG_REG: begin // Control config
          axi_rdata[0] <= AVX_FLOW;
          axi_rdata[1] <= 1'b1; // BPSS
          axi_rdata[2] <= 1'b0; // TLBF
          axi_rdata[3] <= WB_FLOW;
          axi_rdata[7:4] <= TLB_S_ORDER;
          axi_rdata[11:8] <= N_S_ASSOC;
          axi_rdata[15:12] <= TLB_L_ORDER;
          axi_rdata[19:16] <= N_L_ASSOC;
          axi_rdata[25:20] <= PG_S_BITS;
          axi_rdata[31:26] <= PG_L_BITS;
        end
        MEM_CNFG_REG: begin // Memory config
          axi_rdata[0] <= STRM_FLOW;
          axi_rdata[1] <= MEM_FLOW;
        end
        PR_CNFG_REG: // PR config
          axi_rdata <= PR_FLOW;
        RDMA_CNFG_REG: begin // RDMA config
          axi_rdata[0] <= RDMA_FLOW;
          axi_rdata[1] <= QSFP;
        end
        TCP_CNFG_REG: begin // TCP config
          axi_rdata[0] <= TCP_FLOW;
          axi_rdata[1] <= QSFP;
        end

`ifdef EN_RDMA
        RDMA_OFFS_REG: // Offset
          axi_rdata <= slv_reg[RDMA_OFFS_REG];
`endif

`ifdef EN_TCP
        TCP_OFFS_REG: // TCP ddr offset
          axi_rdata <= slv_reg[TCP_OFFS_REG];
`endif

`ifdef EN_STATS

  `ifdef EN_XCH_0
          XDMA_STAT_0_BPSS: // bpss
            axi_rdata <= {s_xdma_stats_0.bpss_c2h_req_counter, s_xdma_stats_0.bpss_h2c_req_counter};
          XDMA_STAT_0_CMPL: // cmpl
            axi_rdata <= {s_xdma_stats_0.bpss_c2h_cmpl_counter, s_xdma_stats_0.bpss_h2c_cmpl_counter};
          XDMA_STAT_0_AXIS: // data
            axi_rdata <= {s_xdma_stats_0.bpss_c2h_axis_counter, s_xdma_stats_0.bpss_h2c_axis_counter};
  `endif

  `ifdef EN_XCH_1
          XDMA_STAT_1_BPSS: // bpss
            axi_rdata <= {s_xdma_stats_1.bpss_c2h_req_counter, s_xdma_stats_1.bpss_h2c_req_counter};
          XDMA_STAT_1_CMPL: // cmpl
            axi_rdata <= {s_xdma_stats_1.bpss_c2h_cmpl_counter, s_xdma_stats_1.bpss_h2c_cmpl_counter};
          XDMA_STAT_1_AXIS: // data
            axi_rdata <= {s_xdma_stats_1.bpss_c2h_axis_counter, s_xdma_stats_1.bpss_h2c_axis_counter};
  `endif

  `ifdef EN_NET
          NET_STAT_PKG_REG: // rx and tx
            axi_rdata <= {s_net_stats.tx_pkg_counter, s_net_stats.rx_pkg_counter};
          NET_STAT_ARP_REG: // arp
            axi_rdata <= {s_net_stats.arp_tx_pkg_counter, s_net_stats.arp_rx_pkg_counter}; 
          NET_STAT_ICMP_REG: // icmp
            axi_rdata <= {s_net_stats.icmp_tx_pkg_counter, s_net_stats.icmp_rx_pkg_counter}; 
          NET_STAT_TCP_REG: // tcp
            axi_rdata <= {s_net_stats.tcp_tx_pkg_counter, s_net_stats.tcp_rx_pkg_counter}; 
          NET_STAT_RDMA_REG: // rdma
            axi_rdata <= {s_net_stats.roce_tx_pkg_counter, s_net_stats.roce_rx_pkg_counter}; 
          NET_STAT_IBV_REG: // ibv
            axi_rdata <= {s_net_stats.ibv_tx_pkg_counter, s_net_stats.ibv_rx_pkg_counter}; 
          NET_STAT_DROP_REG: // rdma drop
            axi_rdata <= {s_net_stats.roce_retrans_counter, s_net_stats.roce_psn_drop_counter}; 
          NET_STAT_SESS_REG: // tcp sessions
            axi_rdata[31:0] <= s_net_stats.tcp_session_counter; 
          NET_STAT_DOWN_REG: // rdma
            axi_rdata[0] <= s_net_stats.axis_stream_down;
  `endif

`endif

        default: ;
      endcase
    end
  end 
end

// ---------------------------------------------------------------------------------------- 
// Output
// ----------------------------------------------------------------------------------------

// Decoupling
assign m_decouple = slv_reg[CTRL_DP_REG_SET][0+:N_REGIONS];
assign m_rst_pr = slv_reg[CTRL_DP_REG_SET][32+:N_REGIONS];

`ifdef EN_RDMA

// RDMA offset
assign m_ddr_offset_addr_rdma = slv_reg[RDMA_OFFS_REG];

`endif

`ifdef EN_TCP

// TCP offset
assign m_ddr_offset_addr_tcp = slv_reg[TCP_OFFS_REG];

`endif

// ---------------------------------------------------------------------------------------- 
// AXI
// ----------------------------------------------------------------------------------------

// I/O
assign s_axi_ctrl.awready = axi_awready;
assign s_axi_ctrl.arready = axi_arready;
assign s_axi_ctrl.bresp = axi_bresp;
assign s_axi_ctrl.bvalid = axi_bvalid;
assign s_axi_ctrl.wready = axi_wready;
assign s_axi_ctrl.rdata = axi_rdata;
assign s_axi_ctrl.rresp = axi_rresp;
assign s_axi_ctrl.rvalid = axi_rvalid;

// awready and awaddr
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_awready <= 1'b0;
      axi_awaddr <= 0;
      aw_en <= 1'b1;
    end 
  else
    begin    
      if (~axi_awready && s_axi_ctrl.awvalid && s_axi_ctrl.wvalid && aw_en)
        begin
          axi_awready <= 1'b1;
          aw_en <= 1'b0;
          axi_awaddr <= s_axi_ctrl.awaddr;
        end
      else if (s_axi_ctrl.bready && axi_bvalid)
        begin
          aw_en <= 1'b1;
          axi_awready <= 1'b0;
        end
      else           
        begin
          axi_awready <= 1'b0;
        end
    end 
end  

// arready and araddr
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_arready <= 1'b0;
      axi_araddr  <= 0;
    end 
  else
    begin    
      if (~axi_arready && s_axi_ctrl.arvalid)
        begin
          axi_arready <= 1'b1;
          axi_araddr  <= s_axi_ctrl.araddr;
        end
      else
        begin
          axi_arready <= 1'b0;
        end
    end 
end    

// bvalid and bresp
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_bvalid  <= 0;
      axi_bresp   <= 2'b0;
    end 
  else
    begin    
      if (axi_awready && s_axi_ctrl.awvalid && ~axi_bvalid && axi_wready && s_axi_ctrl.wvalid)
        begin
          axi_bvalid <= 1'b1;
          axi_bresp  <= 2'b0;
        end                   
      else
        begin
          if (s_axi_ctrl.bready && axi_bvalid) 
            begin
              axi_bvalid <= 1'b0; 
            end  
        end
    end
end

// wready
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_wready <= 1'b0;
    end 
  else
    begin    
      if (~axi_wready && s_axi_ctrl.wvalid && s_axi_ctrl.awvalid && aw_en )
        begin
          axi_wready <= 1'b1;
        end
      else
        begin
          axi_wready <= 1'b0;
        end
    end 
end  

// rvalid and rresp (1Del?)
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_rvalid <= 0;
      axi_rresp  <= 0;
    end 
  else
    begin    
      if (axi_arready && s_axi_ctrl.arvalid && ~axi_rvalid)
        begin
          axi_rvalid <= 1'b1;
          axi_rresp  <= 2'b0;
        end   
      else if (axi_rvalid && s_axi_ctrl.rready)
        begin
          axi_rvalid <= 1'b0;
        end                
    end
end    

endmodule // cnfg_slave
