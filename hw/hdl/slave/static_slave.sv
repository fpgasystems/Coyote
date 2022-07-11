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

module static_slave (
  input  logic              aclk,
  input  logic              aresetn,
  
`ifdef EN_PR
  // DMA 
  dmaIntf.m                 m_pr_dma_rd_req,
  dmaIntf.m                 m_pr_dma_wr_req,
`endif

`ifdef EN_TLBF
  // TLB DMA
  muxIntf.s                 s_mux_tlb,  
  input  logic              done_map, 
`endif 

`ifdef EN_WB
  // Writeback DMA 
  
  AXI4S.m                   m_axis_wb,
  metaIntf.s                s_wback,
`endif

`ifdef EN_UC
  dmaIntf.m                 m_tlb_dma_rd_req,
  dmaIntf.m                 m_wb_dma_wr_req,
`endif

`ifdef EN_NET_0
  // ARP
  metaIntf.m                m_arp_lookup_request_0,
  metaIntf.s                s_arp_lookup_reply_0,

  // IP
  metaIntf.m                m_set_ip_addr_0,
  metaIntf.m                m_set_board_number_0,

  // Net stats
  net_stat_t                s_net_stats_0,
`endif

`ifdef EN_NET_1
  // ARP
  metaIntf.m                m_arp_lookup_request_1,
  metaIntf.s                s_arp_lookup_reply_1,

  // IP
  metaIntf.m                m_set_ip_addr_1,
  metaIntf.m                m_set_board_number_1,

  // Net stats
  net_stat_t                s_net_stats_1,
`endif

`ifdef EN_RDMA_0
  metaIntf.m                m_rdma_0_qp_interface,
  metaIntf.m                m_rdma_0_conn_interface,
`endif

`ifdef EN_RDMA_1
  metaIntf.m                m_rdma_1_qp_interface,
  metaIntf.m                m_rdma_1_conn_interface,
`endif

`ifdef EN_TCP_0
  output logic [63:0]       m_rx_ddr_offset_addr_0,
  output logic [63:0]       m_tx_ddr_offset_addr_0,
`endif

`ifdef EN_TCP_1
  output logic [63:0]       m_rx_ddr_offset_addr_1,
  output logic [63:0]       m_tx_ddr_offset_addr_1,
`endif

  // Lowspeed control (only applicable to u250)
  output logic [2:0]        lowspeed_ctrl_0,
  output logic [2:0]        lowspeed_ctrl_1,

  // Control bus (HOST)
  AXI4L.s                   s_axi_ctrl
);

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------

// Constants
localparam integer N_REGS = 64;
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

`ifdef EN_PR
dmaIntf pr_req ();
`endif 

`ifdef EN_TLBF
dmaIntf tlb_req ();
metaIntf #(.STYPE(logic[N_ID_BITS+BLEN_BITS-1:0])) seq_in ();
logic [BLEN_BITS-1:0] n_tr;
`endif

`ifdef EN_WB
dmaIntf wb_req ();
`endif

// -- Def -----------------------------------------------------------
// ------------------------------------------------------------------

// -- Register map ----------------------------------------------------------------------- 
// CONFIG
// 0 (RW) : Probe
localparam integer PROBE_REG          = 0;
// 1 (RO) : Number of channels
localparam integer N_CHAN_REG         = 1;
// 2 (RO) : Number of regions
localparam integer N_REGIONS_REG      = 2;
// 3 (RO) : Control config
localparam integer CTRL_CNFG_REG      = 3;
// 4 (RO) : Memory config
localparam integer MEM_CNFG_REG       = 4;
// 5 (RO) : Partial reconfiguration config
localparam integer PR_CNFG_REG        = 5;
// 6 (RO) : RDMA config
localparam integer RDMA_CNFG_REG      = 6;
// 7 (RO) : TCP/IP config
localparam integer TCP_CNFG_REG       = 7; 
// 8 (RW) : Control (only for u250)
localparam integer LOWSPEED_REG       = 8;
// PR
// 10 (W1S) : PR control
localparam integer PR_CTRL_REG        = 10;
  localparam integer PR_START  = 0;
  localparam integer PR_CTL    = 1;
  localparam integer PR_CLR    = 2;
// 11 (RO) : Status
localparam integer PR_STAT_REG        = 11;
  localparam integer PR_DONE   = 0;
  localparam integer PR_READY  = 1;
// 12 (RW) : Physical address
localparam integer PR_ADDR_REG        = 12;
// 13 (RW) : Length read
localparam integer PR_LEN_REG         = 13;
// TLB
// 14 (W1S) : TLB control
localparam integer TLB_CTRL_REG       = 14;
  localparam integer TLB_START  = 0;
  localparam integer TLB_CTL    = 1;
  localparam integer TLB_CLR    = 2;
  localparam integer TLB_ID_OFFS = 16;
// 15 (RO) : Status
localparam integer TLB_STAT_REG       = 15;
  localparam integer TLB_DONE   = 0;
  localparam integer TLB_READY  = 1;
// 16 (RW) : Physical address
localparam integer TLB_ADDR_REG       = 16;
// 17 (RW) : Length read
localparam integer TLB_LEN_REG        = 17;
// NETWORK QSFP 0
// 20 (RW) : IP address
localparam integer NET_0_IPADDR_REG   = 20;
// 21 (RW) : Board number 
localparam integer NET_0_BOARDNUM_REG = 21;
// 22 (W1S) : ARP lookup
localparam integer NET_0_ARP_REG      = 22;
// RDMA
// 23 - 25 (RW) : Write QP context
localparam integer RDMA_0_CTX_REG_0   = 23;
localparam integer RDMA_0_CTX_REG_1   = 24;
localparam integer RDMA_0_CTX_REG_2   = 25;
// 26 - 28 (RW) : Write QP connection
localparam integer RDMA_0_CONN_REG_0  = 26;
localparam integer RDMA_0_CONN_REG_1  = 27;
localparam integer RDMA_0_CONN_REG_2  = 28;
// TCP/IP
// 29 - (RW) : TCP/IP rx ddr offset
localparam integer TCP_0_RX_OFFS_REG  = 29;
// 30 - (RW) : TCP/IP tx ddr offset
localparam integer TCP_0_TX_OFFS_REG  = 30;
// NET STATS
// 31 - (RO) : rx 
localparam integer NET_STAT_0_RX_REG  = 31;
// 32 - (RO) : tx 
localparam integer NET_STAT_0_TX_REG  = 32;
// 33 - (RO) : arp
localparam integer NET_STAT_0_ARP_REG = 33;
// 34 - (RO) : icmp
localparam integer NET_STAT_0_ICMP_REG = 34;
// 35 - (RO) : tcp
localparam integer NET_STAT_0_TCP_REG = 35;
// 36 - (RO) : rdma
localparam integer NET_STAT_0_RDMA_REG = 36;
// 37 - (RO) : rdma_drop
localparam integer NET_STAT_0_DROP_REG = 37;
// 38 - (RO) : tcp sessions
localparam integer NET_STAT_0_SESS_REG = 38;
// 39 - (RO) : stream status
localparam integer NET_STAT_0_DOWN_REG = 39;
// NETWORK QSFP 1
// 40 (RW) : IP address
localparam integer NET_1_IPADDR_REG   = 40;
// 41 (RW) : Board number 
localparam integer NET_1_BOARDNUM_REG = 41;
// 42 (W1S) : ARP lookup
localparam integer NET_1_ARP_REG      = 42;
// RDMA
// 43 - 45 (RW) : Write QP context
localparam integer RDMA_1_CTX_REG_0   = 43;
localparam integer RDMA_1_CTX_REG_1   = 44;
localparam integer RDMA_1_CTX_REG_2   = 45;
// 46 - 48 (RW) : Write QP connection
localparam integer RDMA_1_CONN_REG_0  = 46;
localparam integer RDMA_1_CONN_REG_1  = 47;
localparam integer RDMA_1_CONN_REG_2  = 48;
// TCP/IP
// 49 - (RW) : TCP/IP rx ddr offset
localparam integer TCP_1_RX_OFFS_REG  = 49;
// 50 - (RW) : TCP/IP tx ddr offset
localparam integer TCP_1_TX_OFFS_REG  = 50;
// NET STATS
// 51 - (RO) : rx 
localparam integer NET_STAT_1_RX_REG  = 51;
// 52 - (RO) : tx 
localparam integer NET_STAT_1_TX_REG  = 52;
// 53 - (RO) : arp
localparam integer NET_STAT_1_ARP_REG = 53;
// 54 - (RO) : icmp
localparam integer NET_STAT_1_ICMP_REG = 54;
// 55 - (RO) : tcp
localparam integer NET_STAT_1_TCP_REG = 55;
// 56 - (RO) : rdma
localparam integer NET_STAT_1_RDMA_REG = 56;
// 57 - (RO) : rdma_drop
localparam integer NET_STAT_1_DROP_REG = 57;
// 58 - (RO) : tcp sessions
localparam integer NET_STAT_1_SESS_REG = 58;
// 59 - (RO) : stream status
localparam integer NET_STAT_1_DOWN_REG = 59;

// ---------------------------------------------------------------------------------------- 
// Write process 
// ----------------------------------------------------------------------------------------
assign slv_reg_wren = axi_wready && s_axi_ctrl.wvalid && axi_awready && s_axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg <= 'X;
    
    slv_reg[LOWSPEED_REG][5:0] <= ~0;
  
`ifdef EN_PR
    slv_reg[PR_CTRL_REG][15:0] <= 0;
    slv_reg[PR_STAT_REG][15:0] <= 0;
`endif

`ifdef EN_TLBF
    slv_reg[TLB_CTRL_REG][15:0] <= 0;
    slv_reg[TLB_STAT_REG][15:0] <= 0;
`endif 

`ifdef EN_NET_0
    m_set_ip_addr_0.valid <= 1'b0;
    m_set_board_number_0.valid <= 1'b0;
    m_arp_lookup_request_0.valid <= 1'b0;
    s_arp_lookup_reply_0.ready <= 1'b1;
`endif

`ifdef EN_NET_1
    m_set_ip_addr_1.valid <= 1'b0;
    m_set_board_number_1.valid <= 1'b0;
    m_arp_lookup_request_1.valid <= 1'b0;
    s_arp_lookup_reply_1.ready <= 1'b1;
`endif

`ifdef EN_RDMA_0
    m_rdma_0_qp_interface.valid <= 1'b0;
    m_rdma_0_conn_interface.valid <= 1'b0;
`endif 

`ifdef EN_RDMA_1
    m_rdma_1_qp_interface.valid <= 1'b0;
    m_rdma_1_conn_interface.valid <= 1'b0;
`endif 

`ifdef EN_TCP_0
    slv_reg[TCP_0_RX_OFFS_REG] <= 0;
    slv_reg[TCP_0_TX_OFFS_REG] <= 0;
`endif

`ifdef EN_TCP_1
    slv_reg[TCP_1_RX_OFFS_REG] <= 0;
    slv_reg[TCP_1_TX_OFFS_REG] <= 0;
`endif

  end
  else begin
`ifdef EN_PR
    slv_reg[PR_CTRL_REG][15:0] <= 0;
    slv_reg[PR_STAT_REG][PR_DONE] <= slv_reg[PR_CTRL_REG][PR_CLR] ? 1'b0 : pr_req.rsp.done ? 1'b1 : slv_reg[PR_STAT_REG][PR_DONE];
`endif

`ifdef EN_TLBF
    slv_reg[TLB_CTRL_REG][15:0] <= 0;
    slv_reg[TLB_STAT_REG][TLB_DONE] <= slv_reg[TLB_CTRL_REG][TLB_CLR] ? 1'b0 : done_map ? 1'b1 : slv_reg[TLB_STAT_REG][TLB_DONE];
`endif

`ifdef EN_NET_0
    m_arp_lookup_request_0.valid <= m_arp_lookup_request_0.ready ? 1'b0 : m_arp_lookup_request_0.valid;
    s_arp_lookup_reply_0.ready <= 1'b1;

    m_set_ip_addr_0.valid <= 1'b0;
    m_set_board_number_0.valid <= 1'b0;
`endif

`ifdef EN_NET_1
    m_arp_lookup_request_1.valid <= m_arp_lookup_request_1.ready ? 1'b0 : m_arp_lookup_request_1.valid;
    s_arp_lookup_reply_1.ready <= 1'b1;

    m_set_ip_addr_1.valid <= 1'b0;
    m_set_board_number_1.valid <= 1'b0;
`endif

`ifdef EN_RDMA_0
    m_rdma_0_qp_interface.valid <= m_rdma_0_qp_interface.ready ? 1'b0 : m_rdma_0_qp_interface.valid;
    m_rdma_0_conn_interface.valid <= m_rdma_0_conn_interface.ready ? 1'b0 : m_rdma_0_conn_interface.valid;
`endif

`ifdef EN_RDMA_1
    m_rdma_1_qp_interface.valid <= m_rdma_1_qp_interface.ready ? 1'b0 : m_rdma_1_qp_interface.valid;
    m_rdma_1_conn_interface.valid <= m_rdma_1_conn_interface.ready ? 1'b0 : m_rdma_1_conn_interface.valid;
`endif

    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        LOWSPEED_REG: // Lowspeed control
          for (int i = 0; i < 1; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[LOWSPEED_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end

`ifdef EN_PR  
        PR_CTRL_REG: // PR control
          for (int i = 0; i < 2; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_CTRL_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_ADDR_REG: // PR address
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_ADDR_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_LEN_REG: // PR length
          for (int i = 0; i < 4; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[PR_LEN_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
`endif

`ifdef EN_TLBF
        TLB_CTRL_REG: // TLB control
          for (int i = 0; i < 4; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[TLB_CTRL_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        TLB_ADDR_REG: // TLB address
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[TLB_ADDR_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        TLB_LEN_REG: // TLB length
          for (int i = 0; i < 4; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[TLB_LEN_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
`endif

`ifdef EN_NET_0
        NET_0_IPADDR_REG: // IP address
          for (int i = 0; i < 4; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              m_set_ip_addr_0.data[(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
              m_set_ip_addr_0.valid <= 1'b1;
            end
          end
        NET_0_BOARDNUM_REG: // Board number
          for (int i = 0; i < 1; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              m_set_board_number_0.data[3:0] <= s_axi_ctrl.wdata[3:0];
              m_set_board_number_0.valid <= 1'b1;
            end
          end
        NET_0_ARP_REG: // ARP lookup
          for (int i = 0; i < 4; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              m_arp_lookup_request_0.data[(i*8)+:8] <= s_axi_ctrl.wdata[(24-i*8)+:8];
              m_arp_lookup_request_0.valid <= 1'b1;
            end
          end
 `endif

 `ifdef EN_NET_1
        NET_1_IPADDR_REG: // IP address
          for (int i = 0; i < 4; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              m_set_ip_addr_1.data[(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
              m_set_ip_addr_1.valid <= 1'b1;
            end
          end
        NET_1_BOARDNUM_REG: // Board number
          for (int i = 0; i < 1; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              m_set_board_number_1.data[3:0] <= s_axi_ctrl.wdata[3:0];
              m_set_board_number_1.valid <= 1'b1;
            end
          end
        NET_1_ARP_REG: // ARP lookup
          for (int i = 0; i < 4; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              m_arp_lookup_request_1.data[(i*8)+:8] <= s_axi_ctrl.wdata[(24-i*8)+:8];
              m_arp_lookup_request_1.valid <= 1'b1;
            end
          end
 `endif
          
`ifdef EN_RDMA_0
        RDMA_0_CTX_REG_0: // Context
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_CTX_REG_0][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_0_CTX_REG_1: // Context
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_CTX_REG_1][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_0_CTX_REG_2: // Context final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_CTX_REG_2][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
              m_rdma_0_qp_interface.valid <= 1'b1;
            end
          end
        RDMA_0_CONN_REG_0: // Connection
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_CONN_REG_0][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_0_CONN_REG_1: // Connection
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_CONN_REG_1][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_0_CONN_REG_2: // Connection final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_0_CONN_REG_2][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
              m_rdma_0_conn_interface.valid <= 1'b1;
            end
          end
`endif

`ifdef EN_RDMA_1
        RDMA_1_CTX_REG_0: // Context
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_CTX_REG_0][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_1_CTX_REG_1: // Context
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_CTX_REG_1][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_1_CTX_REG_2: // Context final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_CTX_REG_2][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
              m_rdma_1_qp_interface.valid <= 1'b1;
            end
          end
        RDMA_1_CONN_REG_0: // Connection
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_CONN_REG_0][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_1_CONN_REG_1: // Connection
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_CONN_REG_1][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        RDMA_1_CONN_REG_2: // Connection final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[RDMA_1_CONN_REG_2][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
              m_rdma_1_conn_interface.valid <= 1'b1;
            end
          end
`endif

`ifdef EN_TCP_0
        TCP_0_RX_OFFS_REG: // TCP rx ddr offset
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[TCP_0_RX_OFFS_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        TCP_0_TX_OFFS_REG: // TCP tx ddr offset
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[TCP_0_TX_OFFS_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
`endif

`ifdef EN_TCP_1
        TCP_1_RX_OFFS_REG: // TCP rx ddr offset
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[TCP_1_RX_OFFS_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
            end
          end
        TCP_1_TX_OFFS_REG: // TCP tx ddr offset
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(s_axi_ctrl.wstrb[i]) begin
              slv_reg[TCP_1_TX_OFFS_REG][(i*8)+:8] <= s_axi_ctrl.wdata[(i*8)+:8];
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
          axi_rdata <= PROBE_ID;
        N_CHAN_REG: // Number of channels
          axi_rdata <= N_CHAN;
        N_REGIONS_REG: // Number of regions
          axi_rdata <= N_REGIONS;
        CTRL_CNFG_REG: begin // Control config
          axi_rdata[0] <= AVX_FLOW;
          axi_rdata[1] <= BPSS_FLOW;
          axi_rdata[2] <= TLBF_FLOW;
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
          axi_rdata[0] <= RDMA_0_FLOW;
          axi_rdata[1] <= RDMA_1_FLOW;
        end
        TCP_CNFG_REG: begin // TCP config
          axi_rdata[0] <= TCP_0_FLOW;
          axi_rdata[1] <= TCP_1_FLOW;
        end
        LOWSPEED_REG:
          axi_rdata[5:0] <= slv_reg[LOWSPEED_REG][5:0];
        
`ifdef EN_PR
        PR_STAT_REG:
          axi_rdata[1:0] <= {pr_req.ready, slv_reg[PR_STAT_REG][PR_DONE]};
        PR_ADDR_REG:
          axi_rdata <= slv_reg[PR_ADDR_REG];
        PR_LEN_REG:
          axi_rdata[31:0] <= slv_reg[PR_LEN_REG][31:0];
`endif

`ifdef EN_TLBF
        TLB_STAT_REG:
          axi_rdata[1:0] <= {tlb_req.ready && seq_in.ready, slv_reg[TLB_STAT_REG][TLB_DONE]};
        TLB_ADDR_REG:
          axi_rdata <= slv_reg[TLB_ADDR_REG];
        TLB_LEN_REG:
          axi_rdata[31:0] <= slv_reg[TLB_LEN_REG][31:0];
`endif

`ifdef EN_RDMA_0
        RDMA_0_CTX_REG_0: // Context
          axi_rdata <= slv_reg[RDMA_0_CTX_REG_0];
        RDMA_0_CTX_REG_1: // Context
          axi_rdata <= slv_reg[RDMA_0_CTX_REG_1];
        RDMA_0_CTX_REG_2: // Context final
          axi_rdata <= slv_reg[RDMA_0_CTX_REG_2];
        RDMA_0_CONN_REG_0: // Connection
          axi_rdata <= slv_reg[RDMA_0_CONN_REG_0];
        RDMA_0_CONN_REG_1: // Connection
          axi_rdata <= slv_reg[RDMA_0_CONN_REG_1];
        RDMA_0_CONN_REG_2: // Connection final
          axi_rdata <= slv_reg[RDMA_0_CONN_REG_2];
`endif

`ifdef EN_RDMA_1
        RDMA_1_CTX_REG_0: // Context
          axi_rdata <= slv_reg[RDMA_1_CTX_REG_0];
        RDMA_1_CTX_REG_1: // Context
          axi_rdata <= slv_reg[RDMA_1_CTX_REG_1];
        RDMA_1_CTX_REG_2: // Context final
          axi_rdata <= slv_reg[RDMA_1_CTX_REG_2];
        RDMA_1_CONN_REG_0: // Connection
          axi_rdata <= slv_reg[RDMA_1_CONN_REG_0];
        RDMA_1_CONN_REG_1: // Connection
          axi_rdata <= slv_reg[RDMA_1_CONN_REG_1];
        RDMA_1_CONN_REG_2: // Connection final
          axi_rdata <= slv_reg[RDMA_1_CONN_REG_2];
`endif

`ifdef EN_TCP_0
        TCP_0_RX_OFFS_REG: // TCP rx ddr offset
          axi_rdata <= slv_reg[TCP_0_RX_OFFS_REG];
        TCP_0_TX_OFFS_REG: // TCP tx ddr offset
          axi_rdata <= slv_reg[TCP_0_TX_OFFS_REG];
`endif

`ifdef EN_TCP_1
        TCP_1_RX_OFFS_REG: // TCP rx ddr offset
          axi_rdata <= slv_reg[TCP_1_RX_OFFS_REG];
        TCP_1_TX_OFFS_REG: // TCP tx ddr offset
          axi_rdata <= slv_reg[TCP_1_TX_OFFS_REG];
`endif

`ifdef EN_NET_0
        NET_STAT_0_RX_REG: // rx
          axi_rdata <= {s_net_stats_0.rx_pkg_counter, s_net_stats_0.rx_word_counter};
        NET_STAT_0_TX_REG: // tx
          axi_rdata <= {s_net_stats_0.tx_pkg_counter, s_net_stats_0.tx_word_counter}; 
        NET_STAT_0_ARP_REG: // arp
          axi_rdata <= {s_net_stats_0.arp_tx_pkg_counter, s_net_stats_0.arp_rx_pkg_counter}; 
        NET_STAT_0_ICMP_REG: // icmp
          axi_rdata <= {s_net_stats_0.icmp_tx_pkg_counter, s_net_stats_0.icmp_rx_pkg_counter}; 
        NET_STAT_0_TCP_REG: // tcp
          axi_rdata <= {s_net_stats_0.tcp_tx_pkg_counter, s_net_stats_0.tcp_rx_pkg_counter}; 
        NET_STAT_0_RDMA_REG: // rdma
          axi_rdata <= {s_net_stats_0.roce_tx_pkg_counter, s_net_stats_0.roce_rx_pkg_counter}; 
        NET_STAT_0_DROP_REG: // rdma drop
          axi_rdata <= {s_net_stats_0.roce_psn_drop_counter, s_net_stats_0.roce_crc_drop_counter}; 
        NET_STAT_0_SESS_REG: // tcp sessions
          axi_rdata[31:0] <= s_net_stats_0.tcp_session_counter; 
        NET_STAT_0_DOWN_REG: // rdma
          axi_rdata <= {{31{1'b0}}, s_net_stats_0.axis_stream_down, {24{1'b0}}, s_net_stats_0.axis_stream_down_counter}; 
`endif

`ifdef EN_NET_1
        NET_STAT_1_RX_REG: // rx
          axi_rdata <= {s_net_stats_1.rx_pkg_counter, s_net_stats_1.rx_word_counter};
        NET_STAT_1_TX_REG: // tx
          axi_rdata <= {s_net_stats_1.tx_pkg_counter, s_net_stats_1.tx_word_counter}; 
        NET_STAT_1_ARP_REG: // arp
          axi_rdata <= {s_net_stats_1.arp_tx_pkg_counter, s_net_stats_1.arp_rx_pkg_counter}; 
        NET_STAT_1_ICMP_REG: // icmp
          axi_rdata <= {s_net_stats_1.icmp_tx_pkg_counter, s_net_stats_1.icmp_rx_pkg_counter}; 
        NET_STAT_1_TCP_REG: // tcp
          axi_rdata <= {s_net_stats_1.tcp_tx_pkg_counter, s_net_stats_1.tcp_rx_pkg_counter}; 
        NET_STAT_1_RDMA_REG: // rdma
          axi_rdata <= {s_net_stats_1.roce_tx_pkg_counter, s_net_stats_1.roce_rx_pkg_counter}; 
        NET_STAT_1_DROP_REG: // rdma drop
          axi_rdata <= {s_net_stats_1.roce_psn_drop_counter, s_net_stats_1.roce_crc_drop_counter}; 
        NET_STAT_1_SESS_REG: // tcp sessions
          axi_rdata[31:0] <= s_net_stats_1.tcp_session_counter; 
        NET_STAT_1_DOWN_REG: // rdma
          axi_rdata <= {{31{1'b0}}, s_net_stats_1.axis_stream_down, {24{1'b0}}, s_net_stats_1.axis_stream_down_counter}; 
`endif

        default: ;
      endcase
    end
  end 
end

// ---------------------------------------------------------------------------------------- 
// Output
// ----------------------------------------------------------------------------------------
assign lowspeed_ctrl_0 = slv_reg[LOWSPEED_REG][2:0];
assign lowspeed_ctrl_1 = slv_reg[LOWSPEED_REG][2:0];

// PR
`ifdef EN_PR

always_comb begin
  // PR request
  pr_req.valid = slv_reg[PR_CTRL_REG][PR_START];
  pr_req.req.ctl = slv_reg[PR_CTRL_REG][PR_CTL];
  pr_req.req.paddr = slv_reg[PR_ADDR_REG][PADDR_BITS-1:0];
  pr_req.req.len = slv_reg[PR_LEN_REG][LEN_BITS-1:0];
  // Done signal
  pr_req.rsp.done = m_pr_dma_rd_req.rsp.done;

  // Tie-off write channel
  m_pr_dma_wr_req.valid = 1'b0;
  m_pr_dma_wr_req.req = 0;
end

// DMA out
queue_stream #(
  .QTYPE(dma_req_t),
  .QDEPTH(16)
) inst_que_pr (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(pr_req.valid),
  .rdy_snk(pr_req.ready),
  .data_snk(pr_req.req),
  .val_src(m_pr_dma_rd_req.valid),
  .rdy_src(m_pr_dma_rd_req.ready),
  .data_src(m_pr_dma_rd_req.req)
);

`endif

`ifdef EN_TLBF

// TLB
always_comb begin
  // TLB request
  tlb_req.valid = slv_reg[TLB_CTRL_REG][TLB_START];
  tlb_req.req.ctl = slv_reg[TLB_CTRL_REG][TLB_CTL];
  tlb_req.req.paddr = slv_reg[TLB_ADDR_REG];
  tlb_req.req.len = slv_reg[TLB_LEN_REG];
  // Done signal
  tlb_req.rsp.done = m_tlb_dma_rd_req.rsp.done;

  n_tr = (slv_reg[TLB_LEN_REG] - 1) >> BEAT_LOG_BITS;

  // Sequence
  seq_in.valid = slv_reg[TLB_CTRL_REG][TLB_START];
  seq_in.data = {slv_reg[TLB_CTRL_REG][TLB_ID_OFFS+:N_ID_BITS], n_tr};
end

// DMA out
queue_stream #(
  .QTYPE(dma_req_t),
  .QDEPTH(4)
) inst_que_tlb (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(tlb_req.valid),
  .rdy_snk(tlb_req.ready),
  .data_snk(tlb_req.req),
  .val_src(m_tlb_dma_rd_req.valid),
  .rdy_src(m_tlb_dma_rd_req.ready),
  .data_src(m_tlb_dma_rd_req.req)
);

// Multiplexer sequence
queue #(
    .QTYPE(logic [N_ID_BITS+BLEN_BITS-1:0]),
    .QDEPTH(4)
) inst_seq_que_user (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(seq_in.valid),
    .rdy_snk(seq_in.ready),
    .data_snk(seq_in.data),
    .val_src(s_mux_tlb.valid),
    .rdy_src(s_mux_tlb.ready),
    .data_src({s_mux_tlb.vfid, s_mux_tlb.len})
);
assign s_mux_tlb.ctl = 1'b1;

`endif

`ifdef EN_WB 

// Writeback
assign wb_req.valid = s_wback.valid;
assign s_wback.ready = wb_req.ready;
assign wb_req.req.ctl = 1'b1;
assign wb_req.req.paddr = s_wback.data.paddr;
assign wb_req.req.len = 4;

// DMA out
queue_stream #(
  .QTYPE(dma_req_t),
  .QDEPTH(4)
) inst_que_wb (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(wb_req.valid),
  .rdy_snk(wb_req.ready),
  .data_snk(wb_req.req),
  .val_src(m_wb_dma_wr_req.valid),
  .rdy_src(m_wb_dma_wr_req.ready),
  .data_src(m_wb_dma_wr_req.req)
);

queue_stream #(
  .QTYPE(logic[31:0]),
  .QDEPTH(N_OUTSTANDING)
) inst_que_wb_data (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(wb_req.valid & wb_req.ready),
  .rdy_snk(),
  .data_snk(s_wback.data.value),
  .val_src(m_axis_wb.tvalid),
  .rdy_src(m_axis_wb.tready),
  .data_src(m_axis_wb.tdata[31:0])
);

always_comb begin
  m_axis_wb.tdata[AXI_DATA_BITS-1:32] = 0;
  m_axis_wb.tkeep = 0;
  m_axis_wb.tkeep[0+:4] = ~0;
  m_axis_wb.tlast = 1'b1;
end

`endif

`ifdef EN_UC

  `ifndef EN_TLBF
    assign m_tlb_dma_rd_req.valid = 1'b0;
    assign m_tlb_dma_rd_req.req = 0;
  `endif

  `ifndef EN_WB
    assign m_wb_dma_wr_req.valid = 1'b0;
    assign m_wb_dma_wr_req.req = 0;
  `endif

`endif

`ifdef EN_RDMA_0

// RDMA qp interface
assign m_rdma_0_qp_interface.data[0+:51] = slv_reg[RDMA_0_CTX_REG_0][50:0]; // remote psn, local qpn, qp state 
assign m_rdma_0_qp_interface.data[51+:40] = slv_reg[RDMA_0_CTX_REG_1][39:0]; // remote key, local psn
assign m_rdma_0_qp_interface.data[91+:48] = slv_reg[RDMA_0_CTX_REG_2][47:0]; // vaddr
assign m_rdma_0_qp_interface.data[139+:5] = 0;

// RDMA qp connection interface
assign m_rdma_0_conn_interface.data[39:0] = slv_reg[RDMA_0_CONN_REG_0][39:0]; // remote qpn, local qpn (24?)
assign m_rdma_0_conn_interface.data[103:40] = slv_reg[RDMA_0_CONN_REG_1][63:0]; // gid
assign m_rdma_0_conn_interface.data[167:104] = slv_reg[RDMA_0_CONN_REG_2][63:0]; // gid
assign m_rdma_0_conn_interface.data[183:168] = slv_reg[RDMA_0_CONN_REG_0][55:40]; // port

`endif

`ifdef EN_RDMA_1

// RDMA qp interface
assign m_rdma_1_qp_interface.data[0+:51] = slv_reg[RDMA_1_CTX_REG_0][50:0]; // remote psn, local qpn, qp state 
assign m_rdma_1_qp_interface.data[51+:40] = slv_reg[RDMA_1_CTX_REG_1][39:0]; // remote key, local psn
assign m_rdma_1_qp_interface.data[91+:48] = slv_reg[RDMA_1_CTX_REG_2][47:0]; // vaddr
assign m_rdma_1_qp_interface.data[139+:5] = 0;

// RDMA qp connection interface
assign m_rdma_1_conn_interface.data[39:0] = slv_reg[RDMA_1_CONN_REG_0][39:0]; // remote qpn, local qpn (24?)
assign m_rdma_1_conn_interface.data[103:40] = slv_reg[RDMA_1_CONN_REG_1][63:0]; // gid
assign m_rdma_1_conn_interface.data[167:104] = slv_reg[RDMA_1_CONN_REG_2][63:0]; // gid
assign m_rdma_1_conn_interface.data[183:168] = slv_reg[RDMA_1_CONN_REG_0][55:40]; // port

`endif

`ifdef EN_TCP_0

// TCP offsets
assign m_rx_ddr_offset_addr_0 = slv_reg[TCP_0_RX_OFFS_REG];
assign m_tx_ddr_offset_addr_0 = slv_reg[TCP_0_TX_OFFS_REG];

`endif

`ifdef EN_TCP_1

// TCP offsets
assign m_rx_ddr_offset_addr_1 = slv_reg[TCP_1_RX_OFFS_REG];
assign m_tx_ddr_offset_addr_1 = slv_reg[TCP_1_TX_OFFS_REG];

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