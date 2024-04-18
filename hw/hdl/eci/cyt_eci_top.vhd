
-- Copyright (c) 2021, Systems Group, ETH Zurich
-- All rights reserved.

-- Redistribution and use in source and binary forms, with or without modification,
-- are permitted provided that the following conditions are met:

-- 1. Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright notice,
-- this list of conditions and the following disclaimer in the documentation
-- and/or other materials provided with the distribution.
-- 3. Neither the name of the copyright holder nor the names of its contributors
-- may be used to endorse or promote products derived from this software
-- without specific prior written permission.

-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
-- IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
-- INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
-- OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
-- EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity cyt_eci_top is
generic (
    NUM_LANES : integer := 12;
    LANES_GRPS: integer := 3
);
port (
    -- 156.25MHz transceiver reference clocks
    ccpi_clk_p_1 : in std_logic_vector(2 downto 0);
    ccpi_clk_n_1 : in std_logic_vector(2 downto 0);

    ccpi_clk_p_2 : in std_logic_vector(2 downto 0);
    ccpi_clk_n_2 : in std_logic_vector(2 downto 0);


    -- RX differential pairs
    ccpi_rxn_1, ccpi_rxp_1 : in std_logic_vector(NUM_LANES-1 downto 0);
    ccpi_rxn_2, ccpi_rxp_2 : in std_logic_vector(NUM_LANES-1 downto 0);

    -- TX differential pairs
    ccpi_txn_1, ccpi_txp_1 : out std_logic_vector(NUM_LANES-1 downto 0);
    ccpi_txn_2, ccpi_txp_2 : out std_logic_vector(NUM_LANES-1 downto 0);
    
    --
    -- Coyote
    --
    clk_axi : out std_logic; -- 322 MHz
    clk_io : in std_logic; -- 100 MHz

    resetn_axi : out std_logic; -- reset

    -- Control
    axil_ctrl_awaddr  : out std_logic_vector(43 downto 0);
    axil_ctrl_awvalid : out std_logic;
    axil_ctrl_awready : in  std_logic;
    axil_ctrl_wdata   : out  std_logic_vector(63 downto 0);
    axil_ctrl_wstrb   : out  std_logic_vector(7 downto 0);
    axil_ctrl_wvalid  : out  std_logic;
    axil_ctrl_wready  : in  std_logic;
    axil_ctrl_bresp   : in  std_logic_vector(1 downto 0);
    axil_ctrl_bvalid  : in  std_logic;
    axil_ctrl_bready  : out std_logic;
    axil_ctrl_araddr  : out std_logic_vector(43 downto 0);
    axil_ctrl_arvalid : out std_logic;
    axil_ctrl_arready : in  std_logic;
    axil_ctrl_rdata   : in  std_logic_vector(63 downto 0);
    axil_ctrl_rresp   : in  std_logic_vector(1 downto 0);
    axil_ctrl_rvalid  : in  std_logic;
    axil_ctrl_rready  : out std_logic;

    -- Data
    axis_dyn_out_tdata  : out std_logic_vector(1023 downto 0);
    axis_dyn_out_tkeep  : out std_logic_vector(127 downto 0);
    axis_dyn_out_tlast  : out std_logic;
    axis_dyn_out_tvalid : out std_logic;
    axis_dyn_out_tready : in  std_logic;

    axis_dyn_in_tdata   : in  std_logic_vector(1023 downto 0);
    axis_dyn_in_tkeep   : in  std_logic_vector(127 downto 0);
    axis_dyn_in_tlast   : in  std_logic;
    axis_dyn_in_tvalid  : in  std_logic;
    axis_dyn_in_tready  : out std_logic;

    -- Descriptors
    rd_desc_addr        : in  std_logic_vector(39 downto 0);
    rd_desc_len         : in  std_logic_vector(19 downto 0);
    rd_desc_valid       : in  std_logic;
    rd_desc_ready       : out std_logic;
    rd_desc_done        : out std_logic;

    wr_desc_addr        : in  std_logic_vector(39 downto 0);
    wr_desc_len         : in  std_logic_vector(19 downto 0);
    wr_desc_valid       : in  std_logic;
    wr_desc_ready       : out std_logic;
    wr_desc_done        : out std_logic
);
end cyt_eci_top;

architecture behavioural of cyt_eci_top is

-- ECI platform
component eci_platform is
port (
    clk_io          : in std_logic;
    clk_sys         : out std_logic;
    clk_icap        : out std_logic;
    reset_sys       : out std_logic;

    -- 156.25MHz transceiver reference clocks
    eci_gt_clk_p_link1  : in std_logic_vector(2 downto 0);
    eci_gt_clk_n_link1  : in std_logic_vector(2 downto 0);

    eci_gt_clk_p_link2  : in std_logic_vector(5 downto 3);
    eci_gt_clk_n_link2  : in std_logic_vector(5 downto 3);

    -- RX differential pairs
    eci_gt_rx_p_link1   : in std_logic_vector(11 downto 0);
    eci_gt_rx_n_link1   : in std_logic_vector(11 downto 0);
    eci_gt_rx_p_link2   : in std_logic_vector(11 downto 0);
    eci_gt_rx_n_link2   : in std_logic_vector(11 downto 0);

    -- TX differential pairs
    eci_gt_tx_p_link1   : out std_logic_vector(11 downto 0);
    eci_gt_tx_n_link1   : out std_logic_vector(11 downto 0);
    eci_gt_tx_p_link2   : out std_logic_vector(11 downto 0);
    eci_gt_tx_n_link2   : out std_logic_vector(11 downto 0);

    link1_in_data           : out WORDS(6 downto 0);
    link1_in_vc_no          : out VCS(6 downto 0);
    link1_in_we2            : out std_logic_vector(6 downto 0);
    link1_in_we3            : out std_logic_vector(6 downto 0);
    link1_in_we4            : out std_logic_vector(6 downto 0);
    link1_in_we5            : out std_logic_vector(6 downto 0);
    link1_in_valid          : out std_logic;
    link1_in_credit_return  : in std_logic_vector(12 downto 2);
    link1_out_hi_vc         : in ECI_CHANNEL;
    link1_out_hi_vc_ready   : out std_logic;
    link1_out_lo_vc         : in ECI_CHANNEL;
    link1_out_lo_vc_ready   : out std_logic;
    link1_out_credit_return : out std_logic_vector(12 downto 2);

    link2_in_data           : out WORDS(6 downto 0);
    link2_in_vc_no          : out VCS(6 downto 0);
    link2_in_we2            : out std_logic_vector(6 downto 0);
    link2_in_we3            : out std_logic_vector(6 downto 0);
    link2_in_we4            : out std_logic_vector(6 downto 0);
    link2_in_we5            : out std_logic_vector(6 downto 0);
    link2_in_valid          : out std_logic;
    link2_in_credit_return  : in std_logic_vector(12 downto 2);
    link2_out_hi_vc         : in ECI_CHANNEL;
    link2_out_hi_vc_ready   : out std_logic;
    link2_out_lo_vc         : in ECI_CHANNEL;
    link2_out_lo_vc_ready   : out std_logic;
    link2_out_credit_return : out std_logic_vector(12 downto 2);

    link_up                 : out std_logic;
    link1_link_up           : out std_logic;
    link2_link_up           : out std_logic;

    -- AXI Lite master interface IO addr space
    m_io_axil_awaddr    : out std_logic_vector(43 downto 0);
    m_io_axil_awvalid   : buffer std_logic;
    m_io_axil_awready   : in  std_logic;
    m_io_axil_wdata     : out std_logic_vector(63 downto 0);
    m_io_axil_wstrb     : out std_logic_vector(7 downto 0);
    m_io_axil_wvalid    : buffer std_logic;
    m_io_axil_wready    : in  std_logic;
    m_io_axil_bresp     : in  std_logic_vector(1 downto 0);
    m_io_axil_bvalid    : in  std_logic;
    m_io_axil_bready    : buffer std_logic;
    m_io_axil_araddr    : out std_logic_vector(43 downto 0);
    m_io_axil_arvalid   : buffer std_logic;
    m_io_axil_arready   : in  std_logic;
    m_io_axil_rdata     : in std_logic_vector(63 downto 0);
    m_io_axil_rresp     : in std_logic_vector(1 downto 0);
    m_io_axil_rvalid    : in std_logic;
    m_io_axil_rready    : buffer std_logic;

    -- AXI Lite slave interface IO addr space
    s_io_axil_awaddr    : in std_logic_vector(43 downto 0);
    s_io_axil_awvalid   : in std_logic;
    s_io_axil_awready   : out std_logic;
    s_io_axil_wdata     : in std_logic_vector(63 downto 0);
    s_io_axil_wstrb     : in std_logic_vector(7 downto 0);
    s_io_axil_wvalid    : in std_logic;
    s_io_axil_wready    : out std_logic;
    s_io_axil_bresp     : out std_logic_vector(1 downto 0);
    s_io_axil_bvalid    : out std_logic;
    s_io_axil_bready    : in std_logic;
    s_io_axil_araddr    : in std_logic_vector(43 downto 0);
    s_io_axil_arvalid   : in std_logic;
    s_io_axil_arready   : out  std_logic;
    s_io_axil_rdata     : out std_logic_vector(63 downto 0);
    s_io_axil_rresp     : out std_logic_vector(1 downto 0);
    s_io_axil_rvalid    : out std_logic;
    s_io_axil_rready    : in std_logic;

    -- ICAP AXI Lite master interface
    m_icap_axi_awaddr   : out std_logic_vector(8 downto 0);
    m_icap_axi_awvalid  : buffer std_logic;
    m_icap_axi_awready  : in  std_logic;

    m_icap_axi_wdata    : out std_logic_vector(31 downto 0);
    m_icap_axi_wstrb    : out std_logic_vector(3 downto 0);
    m_icap_axi_wvalid   : buffer std_logic;
    m_icap_axi_wready   : in  std_logic;

    m_icap_axi_bresp    : in  std_logic_vector(1 downto 0);
    m_icap_axi_bvalid   : in  std_logic;
    m_icap_axi_bready   : buffer std_logic;

    m_icap_axi_araddr   : out std_logic_vector(8 downto 0);
    m_icap_axi_arvalid  : buffer std_logic;
    m_icap_axi_arready  : in  std_logic;

    m_icap_axi_rdata    : in std_logic_vector(31 downto 0);
    m_icap_axi_rresp    : in std_logic_vector(1 downto 0);
    m_icap_axi_rvalid   : in std_logic;
    m_icap_axi_rready   : buffer std_logic
);
end component;

component cyt_eci_gateway is
generic (
    RX_CROSSBAR_TYPE        : string := "full"; -- or "lite"
    DEBUG_BRIDGE_PRESENT    : boolean := true;
    TX_NO_CHANNELS          : integer;
    RX_NO_CHANNELS          : integer;
    RX_FILTER_VC            : VC_BITFIELDS;
    RX_FILTER_TYPE_MASK     : ECI_TYPE_MASKS;
    RX_FILTER_TYPE          : ECI_TYPE_MASKS;
    RX_FILTER_CLI_MASK      : CLI_ARRAY;
    RX_FILTER_CLI           : CLI_ARRAY
);
port (
    clk_sys                 : in std_logic;
    reset_sys               : in std_logic;
    
    -- Link
    link1_up                : in std_logic;
    link2_up                : in std_logic;

    link1_in_data           : in std_logic_vector(447 downto 0);
    link1_in_vc_no          : in std_logic_vector(27 downto 0);
    link1_in_we2            : in std_logic_vector(6 downto 0);
    link1_in_we3            : in std_logic_vector(6 downto 0);
    link1_in_we4            : in std_logic_vector(6 downto 0);
    link1_in_we5            : in std_logic_vector(6 downto 0);
    link1_in_valid          : in std_logic;
    link1_in_credit_return  : out std_logic_vector(12 downto 2);

    link1_out_hi_data       : out std_logic_vector(575 downto 0);
    link1_out_hi_vc_no      : out std_logic_vector(3 downto 0);
    link1_out_hi_size       : out std_logic_vector(2 downto 0);
    link1_out_hi_valid      : out std_logic;
    link1_out_hi_ready      : in std_logic;

    link1_out_lo_data       : out std_logic_vector(63 downto 0);
    link1_out_lo_vc_no      : out std_logic_vector(3 downto 0);
    link1_out_lo_valid      : out std_logic;
    link1_out_lo_ready      : in std_logic;
    link1_out_credit_return : in std_logic_vector(12 downto 2);

    link2_in_data           : in std_logic_vector(447 downto 0);
    link2_in_vc_no          : in std_logic_vector(27 downto 0);
    link2_in_we2            : in std_logic_vector(6 downto 0);
    link2_in_we3            : in std_logic_vector(6 downto 0);
    link2_in_we4            : in std_logic_vector(6 downto 0);
    link2_in_we5            : in std_logic_vector(6 downto 0);
    link2_in_valid          : in std_logic;
    link2_in_credit_return  : out std_logic_vector(12 downto 2);

    link2_out_hi_data       : out std_logic_vector(575 downto 0);
    link2_out_hi_vc_no      : out std_logic_vector(3 downto 0);
    link2_out_hi_size       : out std_logic_vector(2 downto 0);
    link2_out_hi_valid      : out std_logic;
    link2_out_hi_ready      : in std_logic;

    link2_out_lo_data       : out std_logic_vector(63 downto 0);
    link2_out_lo_vc_no      : out std_logic_vector(3 downto 0);
    link2_out_lo_valid      : out std_logic;
    link2_out_lo_ready      : in std_logic;
    link2_out_credit_return : in std_logic_vector(12 downto 2);
    
    -- VC channels
    rx_eci_channels         : out ARRAY_ECI_CHANNELS(RX_NO_CHANNELS-1 downto 0);
    rx_eci_channels_ready   : in std_logic_vector(RX_NO_CHANNELS-1 downto 0);

    tx_eci_channels         : in ARRAY_ECI_CHANNELS(TX_NO_CHANNELS-1 downto 0);
    tx_eci_channels_ready   : out std_logic_vector(TX_NO_CHANNELS-1 downto 0)
);
end component;

component eci_channel_bus_converter is
port (
    clk             : in STD_LOGIC;

    in_channel      : in ECI_CHANNEL;
    in_ready        : out STD_LOGIC;

    out_data        : out WORDS(16 downto 0);
    out_vc_no       : out std_logic_vector(3 downto 0);
    out_size        : out std_logic_vector(4 downto 0);
    out_valid       : out std_logic;
    out_ready       : in std_logic
);
end component;

component eci_bus_channel_converter is
port (
    clk             : in STD_LOGIC;

    in_data         : in WORDS(16 downto 0);
    in_vc_no        : in std_logic_vector(3 downto 0);
    in_size         : in std_logic_vector(4 downto 0);
    in_valid        : in std_logic;
    in_ready        : out std_logic;

    out_channel     : out ECI_CHANNEL;
    out_ready       : in STD_LOGIC
);
end component;

component loopback_vc_resp_nodata is
generic (
   WORD_WIDTH : integer;
   GSDN_GSYNC_FN : integer
);
port (
    clk, reset : in std_logic;

    -- ECI Request input stream
    vc_req_i       : in  std_logic_vector(63 downto 0);
    vc_req_valid_i : in  std_logic;
    vc_req_ready_o : out std_logic;

    -- ECI Response output stream
    vc_resp_o       : out std_logic_vector(63 downto 0);
    vc_resp_valid_o : out std_logic;
    vc_resp_ready_i : in  std_logic
);
end component;

component cyt_eci_bridge is
    port(
      clk   : in std_logic;
      reset : in std_logic;
  
      -- Data
      axis_dyn_out_tdata  : out std_logic_vector(1023 downto 0);
      axis_dyn_out_tkeep  : out std_logic_vector(127 downto 0);
      axis_dyn_out_tlast  : out std_logic;
      axis_dyn_out_tvalid : out std_logic;
      axis_dyn_out_tready : in  std_logic;
  
      axis_dyn_in_tdata   : in  std_logic_vector(1023 downto 0);
      axis_dyn_in_tkeep   : in  std_logic_vector(127 downto 0);
      axis_dyn_in_tlast   : in  std_logic;
      axis_dyn_in_tvalid  : in  std_logic;
      axis_dyn_in_tready  : out std_logic;
  
      -- Descriptors
      rd_desc_addr        : in  std_logic_vector(39 downto 0);
      rd_desc_len         : in  std_logic_vector(19 downto 0);
      rd_desc_valid       : in  std_logic;
      rd_desc_ready       : out std_logic;
      rd_desc_done        : out std_logic;
  
      wr_desc_addr        : in  std_logic_vector(39 downto 0);
      wr_desc_len         : in  std_logic_vector(19 downto 0);
      wr_desc_valid       : in  std_logic;
      wr_desc_ready       : out std_logic;
      wr_desc_done        : out std_logic;
  
      --------------------- FPGA to CPU output VCs (MOB) ------------------//
      -- Request w/o data - VC 7/6
      f_vc7_co_o         : out std_logic_vector(63 downto 0);
      f_vc7_co_valid_o   : out std_logic;
      f_vc7_co_size_o    : out std_logic_vector(4 downto 0);
      f_vc7_co_ready_i   : in std_logic;
  
      f_vc6_co_o         : out std_logic_vector(63 downto 0);
      f_vc6_co_valid_o   : out std_logic;
      f_vc6_co_size_o    : out std_logic_vector(4 downto 0);
      f_vc6_co_ready_i   : in std_logic;
  
      -- Request with data - VC 3/2
      f_vc3_cd_o         : out std_logic_vector(17*64-1 downto 0);
      f_vc3_cd_size_o    : out std_logic_vector(4 downto 0);
      f_vc3_cd_valid_o   : out std_logic;
      f_vc3_cd_ready_i   : in std_logic;
  
      f_vc2_cd_o         : out std_logic_vector(17*64-1 downto 0);
      f_vc2_cd_size_o    : out std_logic_vector(4 downto 0);
      f_vc2_cd_valid_o   : out std_logic;
      f_vc2_cd_ready_i   : in std_logic;
  
      --------------- CPU to FPGA (MIB) VCs ------------------//
      -- Response without data VC11/10
      c_vc11_co_i       : in std_logic_vector(63 downto 0); 
      c_vc11_co_size_i  : in std_logic_vector(4 downto 0); 
      c_vc11_co_valid_i : in std_logic;
      c_vc11_co_ready_o : out std_logic;
  
      c_vc10_co_i       : in std_logic_vector(63 downto 0); 
      c_vc10_co_size_i  : in std_logic_vector(4 downto 0); 
      c_vc10_co_valid_i : in std_logic;
      c_vc10_co_ready_o : out std_logic;
  
      -- Response with data - VC 5/4
      c_vc5_cd_i        : in std_logic_vector(17*64-1 downto 0); 
      c_vc5_cd_size_i   : in std_logic_vector(4 downto 0); 
      c_vc5_cd_valid_i  : in std_logic;
      c_vc5_cd_ready_o  : out std_logic;
  
      c_vc4_cd_i        : in std_logic_vector(17*64-1 downto 0); 
      c_vc4_cd_size_i   : in std_logic_vector(4 downto 0);
      c_vc4_cd_valid_i  : in std_logic;
      c_vc4_cd_ready_o  : out std_logic
      );
  end component;

--------------------------------------------------------------------------------------------
-- RECORDS
--------------------------------------------------------------------------------------------

type ECI_LINK_TX is record
    hi          : ECI_CHANNEL;
    hi_ready    : std_logic;
    lo          : ECI_CHANNEL;
    lo_ready    : std_logic;
end record ECI_LINK_TX;

type ECI_PACKET_RX is record
    c6_gsync            : ECI_CHANNEL;
    c6_gsync_ready      : std_logic;
    c7_gsync            : ECI_CHANNEL;
    c7_gsync_ready      : std_logic;
    ginv                : ECI_CHANNEL;
    -- RX rsp_wod VC 10,11
    dma_c10             : ECI_CHANNEL;
    dma_c10_ready       : std_logic;
    dma_c11             : ECI_CHANNEL;
    dma_c11_ready       : std_logic;
    -- RX rsp_wd VC 4,5
    dma_c4              : ECI_CHANNEL;
    dma_c4_ready        : std_logic;
    dma_c5              : ECI_CHANNEL;
    dma_c5_ready        : std_logic;
    -- RX rsp_wd VC 4,5 ECI packet.
    dma_c4_wd_pkt       : WORDS(16 downto 0);
    dma_c4_wd_pkt_size  : std_logic_vector(4 downto 0);
    dma_c4_wd_pkt_vc    : std_logic_vector(3 downto 0);
    dma_c4_wd_pkt_valid : std_logic;
    dma_c4_wd_pkt_ready : std_logic;
    dma_c5_wd_pkt       : WORDS(16 downto 0);
    dma_c5_wd_pkt_size  : std_logic_vector(4 downto 0);
    dma_c5_wd_pkt_vc    : std_logic_vector(3 downto 0);
    dma_c5_wd_pkt_valid : std_logic;
    dma_c5_wd_pkt_ready : std_logic;
end record ECI_PACKET_RX;

type ECI_PACKET_TX is record
    c10_gsync           : ECI_CHANNEL;
    c10_gsync_ready     : std_logic;
    c11_gsync           : ECI_CHANNEL;
    c11_gsync_ready     : std_logic;
    -- TX rsp_wod VC 10,11
    dma_c6             : ECI_CHANNEL;
    dma_c6_ready       : std_logic;
    dma_c7             : ECI_CHANNEL;
    dma_c7_ready       : std_logic;
    -- TX rsp_wd VC 4,5
    dma_c2              : ECI_CHANNEL;
    dma_c2_ready        : std_logic;
    dma_c3              : ECI_CHANNEL;
    dma_c3_ready        : std_logic;
    -- TX rsp_wd VC 4,5 ECI packet.
    dma_c2_wd_pkt       : std_logic_vector(17*64-1 downto 0);
    dma_c2_wd_pkt_size  : std_logic_vector(4 downto 0);
    dma_c2_wd_pkt_vc    : std_logic_vector(3 downto 0);
    dma_c2_wd_pkt_valid : std_logic;
    dma_c2_wd_pkt_ready : std_logic;
    dma_c3_wd_pkt       : std_logic_vector(17*64-1 downto 0);
    dma_c3_wd_pkt_size  : std_logic_vector(4 downto 0);
    dma_c3_wd_pkt_vc    : std_logic_vector(3 downto 0);
    dma_c3_wd_pkt_valid : std_logic;
    dma_c3_wd_pkt_ready : std_logic;
end record ECI_PACKET_TX;


-- Clocks and resets
signal clk_sys : std_logic; -- 322MHz, generated by the ECI GTY
signal reset_sys : std_logic;

-- Link
signal link1_out, link1_out_cred : ECI_LINK_TX;
signal link2_out, link2_out_cred : ECI_LINK_TX;

signal link_eci_packet_rx : ECI_PACKET_RX;
signal link_eci_packet_tx : ECI_PACKET_TX;

signal eci_link_up      : std_logic;
signal link1_eci_link_up    : std_logic;
signal link2_eci_link_up    : std_logic;

signal link1_in_data   : WORDS(6 downto 0);
signal link1_in_vc_no  : VCS(6 downto 0);
signal link1_in_we2    : std_logic_vector(6 downto 0);
signal link1_in_we3    : std_logic_vector(6 downto 0);
signal link1_in_we4    : std_logic_vector(6 downto 0);
signal link1_in_we5    : std_logic_vector(6 downto 0);
signal link1_in_valid  : std_logic;
signal link1_in_credit_return  : std_logic_vector(12 downto 2);
signal link2_in_data   : WORDS(6 downto 0);
signal link2_in_vc_no  : VCS(6 downto 0);
signal link2_in_we2    : std_logic_vector(6 downto 0);
signal link2_in_we3    : std_logic_vector(6 downto 0);
signal link2_in_we4    : std_logic_vector(6 downto 0);
signal link2_in_we5    : std_logic_vector(6 downto 0);
signal link2_in_valid  : std_logic;
signal link2_in_credit_return  : std_logic_vector(12 downto 2);
signal link1_out_credit_return  : std_logic_vector(12 downto 2);
signal link2_out_credit_return  : std_logic_vector(12 downto 2);

-- AXIL control
signal io_axil_link_awaddr  : std_logic_vector(43 downto 0);
signal io_axil_link_awvalid : std_logic;
signal io_axil_link_awready : std_logic;
signal io_axil_link_araddr  : std_logic_vector(43 downto 0);
signal io_axil_link_arvalid : std_logic;
signal io_axil_link_arready : std_logic;
signal io_axil_link_wdata   : std_logic_vector(63 downto 0);
signal io_axil_link_wstrb   : std_logic_vector(7 downto 0);
signal io_axil_link_wvalid  : std_logic;
signal io_axil_link_wready  : std_logic;
signal io_axil_link_bresp   : std_logic_vector(1 downto 0);
signal io_axil_link_bvalid  : std_logic;
signal io_axil_link_bready  : std_logic;
signal io_axil_link_rdata   : std_logic_vector(63 downto 0);
signal io_axil_link_rresp   : std_logic_vector(1 downto 0);
signal io_axil_link_rvalid  : std_logic;
signal io_axil_link_rready  : std_logic;

begin

--------------------------------------------------------------------------------------------
-- BEHAVIOUR
--------------------------------------------------------------------------------------------

-- Reset
resetn_axi <= not reset_sys;
clk_axi <= clk_sys;

---- Assign AXIL
axil_ctrl_awaddr        <= io_axil_link_awaddr(43 downto 0);
axil_ctrl_awvalid       <= io_axil_link_awvalid;
axil_ctrl_araddr        <= io_axil_link_araddr(43 downto 0);
axil_ctrl_arvalid       <= io_axil_link_arvalid;
axil_ctrl_wdata         <= io_axil_link_wdata;
axil_ctrl_wstrb         <= io_axil_link_wstrb;
axil_ctrl_wvalid        <= io_axil_link_wvalid;
axil_ctrl_bready        <= io_axil_link_bready;
axil_ctrl_rready        <= io_axil_link_rready;
io_axil_link_awready    <= axil_ctrl_awready;
io_axil_link_arready    <= axil_ctrl_arready;
io_axil_link_wready     <= axil_ctrl_wready;
io_axil_link_bresp      <= axil_ctrl_bresp;
io_axil_link_bvalid     <= axil_ctrl_bvalid;
io_axil_link_rdata      <= axil_ctrl_rdata;
io_axil_link_rresp      <= axil_ctrl_rresp;
io_axil_link_rvalid     <= axil_ctrl_rvalid;

--
-- ECI platform layer
--

inst_eci_platform : eci_platform
port map (
    clk_io                  => clk_io, -- 100 MHz
    clk_sys                 => clk_sys, -- 322 MHz
    clk_icap                => open,
    reset_sys               => reset_sys,

    eci_gt_clk_p_link1      => ccpi_clk_p_1,
    eci_gt_clk_n_link1      => ccpi_clk_n_1,

    eci_gt_clk_p_link2      => ccpi_clk_p_2,
    eci_gt_clk_n_link2      => ccpi_clk_n_2,

    eci_gt_rx_p_link1       => ccpi_rxp_1,
    eci_gt_rx_n_link1       => ccpi_rxn_1,
    eci_gt_rx_p_link2       => ccpi_rxp_2,
    eci_gt_rx_n_link2       => ccpi_rxn_2,

    eci_gt_tx_p_link1       => ccpi_txp_1,
    eci_gt_tx_n_link1       => ccpi_txn_1,
    eci_gt_tx_p_link2       => ccpi_txp_2,
    eci_gt_tx_n_link2       => ccpi_txn_2,

    link1_in_data           => link1_in_data,
    link1_in_vc_no          => link1_in_vc_no,
    link1_in_we2            => link1_in_we2,
    link1_in_we3            => link1_in_we3,
    link1_in_we4            => link1_in_we4,
    link1_in_we5            => link1_in_we5,
    link1_in_valid          => link1_in_valid,
    link1_in_credit_return  => link1_in_credit_return,
    link1_out_hi_vc         => link1_out.hi,
    link1_out_hi_vc_ready   => link1_out.hi_ready,
    link1_out_lo_vc         => link1_out.lo,
    link1_out_lo_vc_ready   => link1_out.lo_ready,
    link1_out_credit_return => link1_out_credit_return,

    link2_in_data           => link2_in_data,
    link2_in_vc_no          => link2_in_vc_no,
    link2_in_we2            => link2_in_we2,
    link2_in_we3            => link2_in_we3,
    link2_in_we4            => link2_in_we4,
    link2_in_we5            => link2_in_we5,
    link2_in_valid          => link2_in_valid,
    link2_in_credit_return  => link2_in_credit_return,
    link2_out_hi_vc         => link2_out.hi,
    link2_out_hi_vc_ready   => link2_out.hi_ready,
    link2_out_lo_vc         => link2_out.lo,
    link2_out_lo_vc_ready   => link2_out.lo_ready,
    link2_out_credit_return => link2_out_credit_return,

    link_up                 => eci_link_up,
    link1_link_up           => link1_eci_link_up,
    link2_link_up           => link2_eci_link_up,

    -- AXI Lite master interface for IO addr space
    m_io_axil_awaddr        => io_axil_link_awaddr,
    m_io_axil_awvalid       => io_axil_link_awvalid,
    m_io_axil_awready       => io_axil_link_awready,
    m_io_axil_wdata         => io_axil_link_wdata,
    m_io_axil_wstrb         => io_axil_link_wstrb,
    m_io_axil_wvalid        => io_axil_link_wvalid,
    m_io_axil_wready        => io_axil_link_wready,
    m_io_axil_bresp         => io_axil_link_bresp,
    m_io_axil_bvalid        => io_axil_link_bvalid,
    m_io_axil_bready        => io_axil_link_bready,
    m_io_axil_araddr        => io_axil_link_araddr,
    m_io_axil_arvalid       => io_axil_link_arvalid,
    m_io_axil_arready       => io_axil_link_arready,
    m_io_axil_rdata         => io_axil_link_rdata,
    m_io_axil_rresp         => io_axil_link_rresp,
    m_io_axil_rvalid        => io_axil_link_rvalid,
    m_io_axil_rready        => io_axil_link_rready,

    -- AXI Lite master interface for IO addr space
    s_io_axil_awaddr        => (others => '0'),
    s_io_axil_awvalid       => '0',
    s_io_axil_awready       => open,
    s_io_axil_wdata         => (others => '0'),
    s_io_axil_wstrb         => (others => '0'),
    s_io_axil_wvalid        => '0',
    s_io_axil_wready        => open,
    s_io_axil_bresp         => open,
    s_io_axil_bvalid        => open,
    s_io_axil_bready        => '1',
    s_io_axil_araddr        => (others => '0'),
    s_io_axil_arvalid       => '0',
    s_io_axil_arready       => open,
    s_io_axil_rdata         => open,
    s_io_axil_rresp         => open,
    s_io_axil_rvalid        => open,
    s_io_axil_rready        => '1',

    m_icap_axi_awaddr       => open,
    m_icap_axi_awvalid      => open,
    m_icap_axi_awready      => '1',
    m_icap_axi_wdata        => open,
    m_icap_axi_wstrb        => open,
    m_icap_axi_wvalid       => open,
    m_icap_axi_wready       => '1',
    m_icap_axi_bresp        => (others => '0'),
    m_icap_axi_bvalid       => '0',
    m_icap_axi_bready       => open,
    m_icap_axi_araddr       => open,
    m_icap_axi_arvalid      => open,
    m_icap_axi_arready      => '1',
    m_icap_axi_rdata        => (others => '0'),
    m_icap_axi_rresp        => (others => '0'),
    m_icap_axi_rvalid       => '0',
    m_icap_axi_rready       => open
);

--
-- ECI gateway layer
--

inst_cyt_eci_gateway : cyt_eci_gateway
  generic map (
    TX_NO_CHANNELS      => 6,
    RX_NO_CHANNELS      => 7,
    RX_FILTER_VC        => ("00000100000", "00000010000", "00000110000", "01000000000", "00100000000", "00000001000", "00000000100"),
    RX_FILTER_TYPE_MASK => ("11111", "11111", "11111", "00000", "00000", "00000", "00000"),
    RX_FILTER_TYPE      => ("11000", "11000", "10100", "00000", "00000", "00000", "00000"),
    RX_FILTER_CLI_MASK  => ((others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0')),
    RX_FILTER_CLI       => ((others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'))
)
port map (
    clk_sys                 => clk_sys,
    reset_sys               => reset_sys,

    -- Link
    link1_up                => link1_eci_link_up,
    link2_up                => link2_eci_link_up,

    link1_in_data(63 downto 0)     => link1_in_data(0),
    link1_in_data(127 downto 64)   => link1_in_data(1),
    link1_in_data(191 downto 128)  => link1_in_data(2),
    link1_in_data(255 downto 192)  => link1_in_data(3),
    link1_in_data(319 downto 256)  => link1_in_data(4),
    link1_in_data(383 downto 320)  => link1_in_data(5),
    link1_in_data(447 downto 384)  => link1_in_data(6),
    link1_in_vc_no(3 downto 0)     => link1_in_vc_no(0),
    link1_in_vc_no(7 downto 4)     => link1_in_vc_no(1),
    link1_in_vc_no(11 downto 8)    => link1_in_vc_no(2),
    link1_in_vc_no(15 downto 12)   => link1_in_vc_no(3),
    link1_in_vc_no(19 downto 16)   => link1_in_vc_no(4),
    link1_in_vc_no(23 downto 20)   => link1_in_vc_no(5),
    link1_in_vc_no(27 downto 24)   => link1_in_vc_no(6),
    link1_in_we2                   => link1_in_we2,
    link1_in_we3                   => link1_in_we3,
    link1_in_we4                   => link1_in_we4,
    link1_in_we5                   => link1_in_we5,
    link1_in_valid                 => link1_in_valid,
    link1_in_credit_return         => link1_in_credit_return,

    link1_out_hi_data(63 downto 0)      => link1_out.hi.data(0),
    link1_out_hi_data(127 downto 64)    => link1_out.hi.data(1),
    link1_out_hi_data(191 downto 128)   => link1_out.hi.data(2),
    link1_out_hi_data(255 downto 192)   => link1_out.hi.data(3),
    link1_out_hi_data(319 downto 256)   => link1_out.hi.data(4),
    link1_out_hi_data(383 downto 320)   => link1_out.hi.data(5),
    link1_out_hi_data(447 downto 384)   => link1_out.hi.data(6),
    link1_out_hi_data(511 downto 448)   => link1_out.hi.data(7),
    link1_out_hi_data(575 downto 512)   => link1_out.hi.data(8),
    link1_out_hi_vc_no                  => link1_out.hi.vc_no,
    link1_out_hi_size                   => link1_out.hi.size,
    link1_out_hi_valid                  => link1_out.hi.valid,
    link1_out_hi_ready                  => link1_out.hi_ready,
    link1_out_lo_data                   => link1_out.lo.data(0),
    link1_out_lo_vc_no                  => link1_out.lo.vc_no,
    link1_out_lo_valid                  => link1_out.lo.valid,
    link1_out_lo_ready                  => link1_out.lo_ready,
    link1_out_credit_return             => link1_out_credit_return,

    link2_in_data(63 downto 0)     => link2_in_data(0),
    link2_in_data(127 downto 64)   => link2_in_data(1),
    link2_in_data(191 downto 128)  => link2_in_data(2),
    link2_in_data(255 downto 192)  => link2_in_data(3),
    link2_in_data(319 downto 256)  => link2_in_data(4),
    link2_in_data(383 downto 320)  => link2_in_data(5),
    link2_in_data(447 downto 384)  => link2_in_data(6),
    link2_in_vc_no(3 downto 0)     => link2_in_vc_no(0),
    link2_in_vc_no(7 downto 4)     => link2_in_vc_no(1),
    link2_in_vc_no(11 downto 8)    => link2_in_vc_no(2),
    link2_in_vc_no(15 downto 12)   => link2_in_vc_no(3),
    link2_in_vc_no(19 downto 16)   => link2_in_vc_no(4),
    link2_in_vc_no(23 downto 20)   => link2_in_vc_no(5),
    link2_in_vc_no(27 downto 24)   => link2_in_vc_no(6),
    link2_in_we2                   => link2_in_we2,
    link2_in_we3                   => link2_in_we3,
    link2_in_we4                   => link2_in_we4,
    link2_in_we5                   => link2_in_we5,
    link2_in_valid                 => link2_in_valid,
    link2_in_credit_return         => link2_in_credit_return,


    link2_out_hi_data(63 downto 0)      => link2_out.hi.data(0),
    link2_out_hi_data(127 downto 64)    => link2_out.hi.data(1),
    link2_out_hi_data(191 downto 128)   => link2_out.hi.data(2),
    link2_out_hi_data(255 downto 192)   => link2_out.hi.data(3),
    link2_out_hi_data(319 downto 256)   => link2_out.hi.data(4),
    link2_out_hi_data(383 downto 320)   => link2_out.hi.data(5),
    link2_out_hi_data(447 downto 384)   => link2_out.hi.data(6),
    link2_out_hi_data(511 downto 448)   => link2_out.hi.data(7),
    link2_out_hi_data(575 downto 512)   => link2_out.hi.data(8),
    link2_out_hi_vc_no                  => link2_out.hi.vc_no,
    link2_out_hi_size                   => link2_out.hi.size,
    link2_out_hi_valid                  => link2_out.hi.valid,
    link2_out_hi_ready                  => link2_out.hi_ready,
    link2_out_lo_data                   => link2_out.lo.data(0),
    link2_out_lo_vc_no                  => link2_out.lo.vc_no,
    link2_out_lo_valid                  => link2_out.lo.valid,
    link2_out_lo_ready                  => link2_out.lo_ready,
    link2_out_credit_return             => link2_out_credit_return,

    -- VC channels
    rx_eci_channels(0)      => link_eci_packet_rx.c7_gsync,
    rx_eci_channels(1)      => link_eci_packet_rx.c6_gsync,
    rx_eci_channels(2)      => link_eci_packet_rx.ginv,
    rx_eci_channels(3)      => link_eci_packet_rx.dma_c11,
    rx_eci_channels(4)      => link_eci_packet_rx.dma_c10,
    rx_eci_channels(5)      => link_eci_packet_rx.dma_c5,
    rx_eci_channels(6)      => link_eci_packet_rx.dma_c4,

    rx_eci_channels_ready(0)   => link_eci_packet_rx.c7_gsync_ready,
    rx_eci_channels_ready(1)   => link_eci_packet_rx.c6_gsync_ready,
    rx_eci_channels_ready(2)   => '1',
    rx_eci_channels_ready(3)   => link_eci_packet_rx.dma_c11_ready,
    rx_eci_channels_ready(4)   => link_eci_packet_rx.dma_c10_ready,
    rx_eci_channels_ready(5)   => link_eci_packet_rx.dma_c5_ready,
    rx_eci_channels_ready(6)   => link_eci_packet_rx.dma_c4_ready,

    tx_eci_channels(0)      => link_eci_packet_tx.c11_gsync,
    tx_eci_channels(1)      => link_eci_packet_tx.c10_gsync,
    tx_eci_channels(2)      => link_eci_packet_tx.dma_c2,
    tx_eci_channels(3)      => link_eci_packet_tx.dma_c3,
    tx_eci_channels(4)      => link_eci_packet_tx.dma_c6,
    tx_eci_channels(5)      => link_eci_packet_tx.dma_c7,

    tx_eci_channels_ready(0)   => link_eci_packet_tx.c11_gsync_ready,
    tx_eci_channels_ready(1)   => link_eci_packet_tx.c10_gsync_ready,
    tx_eci_channels_ready(2)   => link_eci_packet_tx.dma_c2_ready,
    tx_eci_channels_ready(3)   => link_eci_packet_tx.dma_c3_ready,
    tx_eci_channels_ready(4)   => link_eci_packet_tx.dma_c6_ready,
    tx_eci_channels_ready(5)   => link_eci_packet_tx.dma_c7_ready
);


-- GSYNC response handler, sends GSDN.
-- Odd VCs, GSYNC arrives in VC7 and GSDN sent in VC11.
inst_vc7_vc11_gsync_loopback : loopback_vc_resp_nodata
generic map (
   WORD_WIDTH => 64,
   GSDN_GSYNC_FN => 1
)
port map (
    clk   => clk_sys,
    reset => reset_sys,

    vc_req_i       => link_eci_packet_rx.c7_gsync.data(0),
    vc_req_valid_i => link_eci_packet_rx.c7_gsync.valid,
    vc_req_ready_o => link_eci_packet_rx.c7_gsync_ready,

    vc_resp_o       => link_eci_packet_tx.c11_gsync.data(0),
    vc_resp_valid_o => link_eci_packet_tx.c11_gsync.valid,
    vc_resp_ready_i => link_eci_packet_tx.c11_gsync_ready
);

link_eci_packet_tx.c11_gsync.vc_no <= "1011";
link_eci_packet_tx.c11_gsync.size <= "000";

-- GSYNC response handler, sends GSDN.
-- Even VCs, GSYNC arrives in VC6 and GSDN sent in VC10.
inst_vc6_vc10_gsync_loopback : loopback_vc_resp_nodata
generic map (
   WORD_WIDTH => 64,
   GSDN_GSYNC_FN => 1
)
port map (
    clk   => clk_sys,
    reset => reset_sys,

    vc_req_i       => link_eci_packet_rx.c6_gsync.data(0),
    vc_req_valid_i => link_eci_packet_rx.c6_gsync.valid,
    vc_req_ready_o => link_eci_packet_rx.c6_gsync_ready,

    vc_resp_o       => link_eci_packet_tx.c10_gsync.data(0),
    vc_resp_valid_o => link_eci_packet_tx.c10_gsync.valid,
    vc_resp_ready_i => link_eci_packet_tx.c10_gsync_ready
);

link_eci_packet_tx.c10_gsync.vc_no <= "1010";
link_eci_packet_tx.c10_gsync.size <= "000";

-- RX packetizer.
-- Packetize data from eci_gateway into ECI packet. 
-- RX rsp_wd VC5.
inst_dma_c5_eci_channel_to_bus : eci_channel_bus_converter
port map (
    clk             => clk_sys,
    -- Input eci_gateway packet.
    in_channel      => link_eci_packet_rx.dma_c5,
    in_ready        => link_eci_packet_rx.dma_c5_ready,
    -- Output ECI packet.
    out_data        => link_eci_packet_rx.dma_c5_wd_pkt,
    out_vc_no       => link_eci_packet_rx.dma_c5_wd_pkt_vc,
    out_size        => link_eci_packet_rx.dma_c5_wd_pkt_size,
    out_valid       => link_eci_packet_rx.dma_c5_wd_pkt_valid,
    out_ready       => link_eci_packet_rx.dma_c5_wd_pkt_ready
);

-- RX packetizer.
-- Packetize data from eci_gateway into ECI packet. 
-- RX rsp_wd VC4.
inst_dma_c4_eci_channel_to_bus : eci_channel_bus_converter
port map (
    clk             => clk_sys,
    -- Input eci_gateway packet.
    in_channel      => link_eci_packet_rx.dma_c4,
    in_ready        => link_eci_packet_rx.dma_c4_ready,
    -- output ECI packet.
    out_data        => link_eci_packet_rx.dma_c4_wd_pkt,
    out_vc_no       => link_eci_packet_rx.dma_c4_wd_pkt_vc,
    out_size        => link_eci_packet_rx.dma_c4_wd_pkt_size,
    out_valid       => link_eci_packet_rx.dma_c4_wd_pkt_valid,
    out_ready       => link_eci_packet_rx.dma_c4_wd_pkt_ready
);

-- TX serializer.
-- Serialize ECI packet into eci_gateway.
-- TX rsp_wd VC5.
inst_dma_c3_bus_to_eci_channel : eci_bus_channel_converter
port map (
    clk             => clk_sys,
    -- Input ECI packet.
    in_data         => vector_to_words(link_eci_packet_tx.dma_c3_wd_pkt),
    in_vc_no        => "0011",
    in_size         => link_eci_packet_tx.dma_c3_wd_pkt_size,
    in_valid        => link_eci_packet_tx.dma_c3_wd_pkt_valid,
    in_ready        => link_eci_packet_tx.dma_c3_wd_pkt_ready,
    -- output eci_gateway packet.
    out_channel     => link_eci_packet_tx.dma_c3,
    out_ready       => link_eci_packet_tx.dma_c3_ready
);

-- TX serializer.
-- Serialize ECI packet into eci_gateway.
-- TX rsp_wd VC4.
inst_dma_c2_bus_to_eci_channel : eci_bus_channel_converter
port map (
    clk             => clk_sys,
    -- Input ECI packet.
    in_data         => vector_to_words(link_eci_packet_tx.dma_c2_wd_pkt),
    in_vc_no        => "0010",
    in_size         => link_eci_packet_tx.dma_c2_wd_pkt_size,
    in_valid        => link_eci_packet_tx.dma_c2_wd_pkt_valid,
    in_ready        => link_eci_packet_tx.dma_c2_wd_pkt_ready,
    -- output eci_gateway packet.
    out_channel     => link_eci_packet_tx.dma_c2,
    out_ready       => link_eci_packet_tx.dma_c2_ready
);

link_eci_packet_tx.dma_c6.vc_no <= "0110";
link_eci_packet_tx.dma_c6.size <= "000";

link_eci_packet_tx.dma_c7.vc_no <= "0111";
link_eci_packet_tx.dma_c7.size <= "000";

--
-- Coyote ECI layer
--

inst_cyt_eci_bridge : cyt_eci_bridge
port map (
    clk                     => clk_sys,
    reset                   => reset_sys,

    -- Data and descriptors
    axis_dyn_out_tdata      => axis_dyn_out_tdata,
    axis_dyn_out_tkeep      => axis_dyn_out_tkeep,
    axis_dyn_out_tlast      => axis_dyn_out_tlast,
    axis_dyn_out_tvalid     => axis_dyn_out_tvalid,
    axis_dyn_out_tready     => axis_dyn_out_tready,

    axis_dyn_in_tdata       => axis_dyn_in_tdata,
    axis_dyn_in_tkeep       => axis_dyn_in_tkeep,
    axis_dyn_in_tlast       => axis_dyn_in_tlast,
    axis_dyn_in_tvalid      => axis_dyn_in_tvalid,
    axis_dyn_in_tready      => axis_dyn_in_tready,

    rd_desc_addr            => rd_desc_addr,
    rd_desc_len             => rd_desc_len,
    rd_desc_valid           => rd_desc_valid,
    rd_desc_ready           => rd_desc_ready,
    rd_desc_done            => rd_desc_done,
    
    wr_desc_addr            => wr_desc_addr,
    wr_desc_len             => wr_desc_len,
    wr_desc_valid           => wr_desc_valid,
    wr_desc_ready           => wr_desc_ready,
    wr_desc_done            => wr_desc_done,

    -- Output to MOB of ECI module 
    f_vc7_co_o              => link_eci_packet_tx.dma_c7.data(0), -- Request read 64
    f_vc7_co_size_o         => open, --link_eci_packet_tx.dma_c7.size,
    f_vc7_co_valid_o        => link_eci_packet_tx.dma_c7.valid, 
    f_vc7_co_ready_i        => link_eci_packet_tx.dma_c7_ready,

    f_vc6_co_o              => link_eci_packet_tx.dma_c6.data(0), -- request read 64
    f_vc6_co_size_o         => open, --link_eci_packet_tx.dma_c6.size,
    f_vc6_co_valid_o        => link_eci_packet_tx.dma_c6.valid, 
    f_vc6_co_ready_i        => link_eci_packet_tx.dma_c6_ready,

    f_vc3_cd_o              => link_eci_packet_tx.dma_c3_wd_pkt,  -- request write 17x64
    f_vc3_cd_size_o         => link_eci_packet_tx.dma_c3_wd_pkt_size,
    f_vc3_cd_valid_o        => link_eci_packet_tx.dma_c3_wd_pkt_valid, 
    f_vc3_cd_ready_i        => link_eci_packet_tx.dma_c3_wd_pkt_ready,

    f_vc2_cd_o              => link_eci_packet_tx.dma_c2_wd_pkt, -- request write 17x64
    f_vc2_cd_size_o         => link_eci_packet_tx.dma_c2_wd_pkt_size,
    f_vc2_cd_valid_o        => link_eci_packet_tx.dma_c2_wd_pkt_valid, 
    f_vc2_cd_ready_i        => link_eci_packet_tx.dma_c2_wd_pkt_ready,

    -- Input from MIB of ECI module
    c_vc11_co_i             => link_eci_packet_rx.dma_c11.data(0), -- response write 64
    c_vc11_co_size_i        => "00001", --link_eci_packet_rx.dma_c11.size, 
    c_vc11_co_valid_i       => link_eci_packet_rx.dma_c11.valid, 
    c_vc11_co_ready_o       => link_eci_packet_rx.dma_c11_ready,

    c_vc10_co_i             => link_eci_packet_rx.dma_c10.data(0), -- response write 64
    c_vc10_co_size_i        => "00001", --link_eci_packet_rx.dma_c10.size, 
    c_vc10_co_valid_i       => link_eci_packet_rx.dma_c10.valid, 
    c_vc10_co_ready_o       => link_eci_packet_rx.dma_c10_ready, 
    
    c_vc5_cd_i              => words_to_vector(link_eci_packet_rx.dma_c5_wd_pkt), -- response read 17x64
    c_vc5_cd_size_i         => link_eci_packet_rx.dma_c5_wd_pkt_size, 
    c_vc5_cd_valid_i        => link_eci_packet_rx.dma_c5_wd_pkt_valid, 
    c_vc5_cd_ready_o        => link_eci_packet_rx.dma_c5_wd_pkt_ready,
   
    c_vc4_cd_i              => words_to_vector(link_eci_packet_rx.dma_c4_wd_pkt), -- response read 17x64
    c_vc4_cd_size_i         => link_eci_packet_rx.dma_c4_wd_pkt_size, 
    c_vc4_cd_valid_i        => link_eci_packet_rx.dma_c4_wd_pkt_valid, 
    c_vc4_cd_ready_o        => link_eci_packet_rx.dma_c4_wd_pkt_ready 
);

end behavioural;
