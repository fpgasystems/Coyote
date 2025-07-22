-------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_platform is
generic (
    EDGE_ILA_PRESENT    : boolean := true
);
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

    -- ECI interface
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
end eci_platform;

architecture Behavioral of eci_platform is

component eci_transport is
generic (
    EDGE_ILA_PRESENT    : boolean := true
);
port (
    clk_io          : in std_logic;
    clk_sys         : out std_logic;
    clk_icap        : out std_logic;
    reset_sys       : out std_logic;

    -- 156.25MHz transceiver reference clocks
    eci_gt_clk_p_link1 : in std_logic_vector(2 downto 0);
    eci_gt_clk_n_link1 : in std_logic_vector(2 downto 0);

    eci_gt_clk_p_link2 : in std_logic_vector(5 downto 3);
    eci_gt_clk_n_link2 : in std_logic_vector(5 downto 3);

    -- RX differential pairs
    eci_gt_rx_p_link1    : in std_logic_vector(11 downto 0);
    eci_gt_rx_n_link1    : in std_logic_vector(11 downto 0);
    eci_gt_rx_p_link2    : in std_logic_vector(11 downto 0);
    eci_gt_rx_n_link2    : in std_logic_vector(11 downto 0);

    -- TX differential pairs
    eci_gt_tx_p_link1    : out std_logic_vector(11 downto 0);
    eci_gt_tx_n_link1    : out std_logic_vector(11 downto 0);
    eci_gt_tx_p_link2    : out std_logic_vector(11 downto 0);
    eci_gt_tx_n_link2    : out std_logic_vector(11 downto 0);

    link1_in_data           : out WORDS(6 downto 0);
    link1_in_vc_no          : out VCS(6 downto 0);
    link1_in_we2            : out std_logic_vector(6 downto 0);
    link1_in_we3            : out std_logic_vector(6 downto 0);
    link1_in_we4            : out std_logic_vector(6 downto 0);
    link1_in_we5            : out std_logic_vector(6 downto 0);
    link1_in_valid          : out std_logic;
    link1_in_credit_return  : in std_logic_vector(12 downto 0);
    link1_out_hi_vc         : in ECI_CHANNEL;
    link1_out_hi_vc_ready   : out std_logic;
    link1_out_lo_vc         : in ECI_CHANNEL;
    link1_out_lo_vc_ready   : out std_logic;
    link1_out_credit_return : out std_logic_vector(12 downto 0);

    link2_in_data           : out WORDS(6 downto 0);
    link2_in_vc_no          : out VCS(6 downto 0);
    link2_in_we2            : out std_logic_vector(6 downto 0);
    link2_in_we3            : out std_logic_vector(6 downto 0);
    link2_in_we4            : out std_logic_vector(6 downto 0);
    link2_in_we5            : out std_logic_vector(6 downto 0);
    link2_in_valid          : out std_logic;
    link2_in_credit_return  : in std_logic_vector(12 downto 0);
    link2_out_hi_vc         : in ECI_CHANNEL;
    link2_out_hi_vc_ready   : out std_logic;
    link2_out_lo_vc         : in ECI_CHANNEL;
    link2_out_lo_vc_ready   : out std_logic;
    link2_out_credit_return : out std_logic_vector(12 downto 0);

    link_up                 : out std_logic;
    link1_link_up           : out std_logic;
    link2_link_up           : out std_logic
);
end component;

component eci_io_bridge_lite is
port (
    clk : in std_logic;
    reset : in std_logic;

    -- Link 1 interface
    link1_in            : in ECI_CHANNEL;
    link1_in_ready      : buffer std_logic;
    link1_out           : buffer ECI_CHANNEL;
    link1_out_ready     : in std_logic;

    -- Link 2 interface
    link2_in            : in ECI_CHANNEL;
    link2_in_ready      : buffer std_logic;
    link2_out           : buffer ECI_CHANNEL;
    link2_out_ready     : in std_logic;

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

component tlk_credits is
port (
    clk             : in std_logic;
    rst_n           : in std_logic;

    in_hi           : in ECI_CHANNEL;
    in_hi_ready     : out std_logic;
    in_lo           : in ECI_CHANNEL;
    in_lo_ready     : out std_logic;

    out_hi          : out ECI_CHANNEL;
    out_hi_ready    : in std_logic;
    out_lo          : out ECI_CHANNEL;
    out_lo_ready    : in std_logic;

    credit_return   : in std_logic_vector(12 downto 0)
);
end component;

component eci_rx_io_vc_filter is
port (
    clk : in std_logic;

    in_data         : in WORDS(6 downto 0);
    in_vc_no        : in VCS(6 downto 0);
    in_valid        : in std_logic;

    out_data        : out WORDS(6 downto 0);
    out_vc_no       : out VCS(6 downto 0);
    out_word_enable : out std_logic_vector(6 downto 0);
    out_valid       : out std_logic
);
end component;

component eci_channel_muxer
generic (
    CHANNELS    : integer
);
port (
    clk             : in std_logic;

    inputs          : in ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
    inputs_ready    : out std_logic_vector(CHANNELS-1 downto 0);
    output          : out ECI_CHANNEL;
    output_ready    : in std_logic
);
end component;

component eci_rx_vc_word_extractor_buffered is
port (
    clk                 : in std_logic;

    input_words         : in WORDS(6 downto 0);
    input_vc_no         : in VCS(6 downto 0);
    input_word_enable   : in std_logic_vector(6 downto 0);
    input_valid         : in std_logic;
    input_ready         : out std_logic;

    output              : out ECI_CHANNEL;
    output_ready        : in std_logic
);
end component;

component bus_fifo is
generic (
    FIFO_WIDTH : integer := 32;
    FIFO_DEPTH_BITS : integer := 8;
    MEMORY_TYPE : string := "auto"
);
Port (
    clk : in std_logic;

    s_data      : in std_logic_vector (FIFO_WIDTH-1 downto 0);
    s_valid     : in std_logic;
    s_ready     : out std_logic;

    m_data      : out std_logic_vector (FIFO_WIDTH-1 downto 0);
    m_valid     : out std_logic;
    m_ready     : in std_logic
);
end component;

component rx_credit_counter is
generic (
    VC_NO   : integer
);
port (
    clk             : in std_logic;
    reset_n         : in std_logic;
    input_valid     : in std_logic;
    input_ready     : in std_logic;
    input_vc_no     : in std_logic_vector(3 downto 0);
    credit_return   : out std_logic
);
end component;

type ECI_LINK_RX is record
    data_filtered           : WORDS(6 downto 0);
    vc_no_filtered          : VCS(6 downto 0);
    word_enable_filtered    : std_logic_vector(6 downto 0);
    valid_filtered          : std_logic;

    data_fifo           : WORDS(6 downto 0);
    vc_no_fifo          : VCS(6 downto 0);
    word_enable_fifo    : std_logic_vector(6 downto 0);
    valid_fifo          : std_logic;
    ready_fifo          : std_logic;

    data          : ECI_CHANNEL;
    ready         : std_logic;
end record ECI_LINK_RX;

signal clk : std_logic;     -- 322MHz, generated by the ECI GTY

signal path1_in_data   : WORDS(6 downto 0);
signal path1_in_vc_no  : VCS(6 downto 0);
signal path1_in_valid  : std_logic;
signal path1_in_credit_return  : std_logic_vector(1 downto 0);

signal path2_in_data   : WORDS(6 downto 0);
signal path2_in_vc_no  : VCS(6 downto 0);
signal path2_in_valid  : std_logic;
signal path2_in_credit_return   : std_logic_vector(1 downto 0);

signal path1_out_credit_return  : std_logic_vector(1 downto 0);
signal path2_out_credit_return  : std_logic_vector(1 downto 0);

signal link1_io         : ECI_CHANNEL;
signal link1_io_ready   : std_logic;
signal link2_io         : ECI_CHANNEL;
signal link2_io_ready   : std_logic;

signal link1_io_out_cred        : ECI_CHANNEL;
signal link1_io_out_cred_ready  : std_logic;
signal link2_io_out_cred        : ECI_CHANNEL;
signal link2_io_out_cred_ready  : std_logic;

signal link1_out_lo         : ECI_CHANNEL;
signal link1_out_lo_ready   : std_logic;
signal link2_out_lo         : ECI_CHANNEL;
signal link2_out_lo_ready   : std_logic;

signal path1_io_out_lo          : ECI_CHANNEL;
signal path1_io_out_lo_ready    : std_logic;
signal path2_io_out_lo          : ECI_CHANNEL;
signal path2_io_out_lo_ready    : std_logic;

signal link1_in : ECI_LINK_RX;
signal link2_in : ECI_LINK_RX;

signal reset, reset_n   : std_logic;
signal eci_link_up      : std_logic;
signal link1_eci_link_up    : std_logic;
signal link2_eci_link_up    : std_logic;

begin

i_eci_transport : eci_transport
generic map (
    EDGE_ILA_PRESENT    <= EDGE_ILA_PRESENT
)
port map (
    clk_io          => clk_io,
    clk_sys         => clk,
    clk_icap        => clk_icap,
    reset_sys       => reset,

    eci_gt_clk_p_link1  => eci_gt_clk_p_link1,
    eci_gt_clk_n_link1  => eci_gt_clk_n_link1,

    eci_gt_clk_p_link2  => eci_gt_clk_p_link2,
    eci_gt_clk_n_link2  => eci_gt_clk_n_link2,

    eci_gt_rx_p_link1   => eci_gt_rx_p_link1,
    eci_gt_rx_n_link1   => eci_gt_rx_n_link1,
    eci_gt_rx_p_link2   => eci_gt_rx_p_link2,
    eci_gt_rx_n_link2   => eci_gt_rx_n_link2,

    eci_gt_tx_p_link1   => eci_gt_tx_p_link1,
    eci_gt_tx_n_link1   => eci_gt_tx_n_link1,
    eci_gt_tx_p_link2   => eci_gt_tx_p_link2,
    eci_gt_tx_n_link2   => eci_gt_tx_n_link2,

    link1_in_data       => path1_in_data,
    link1_in_vc_no      => path1_in_vc_no,
    link1_in_we2        => link1_in_we2,
    link1_in_we3        => link1_in_we3,
    link1_in_we4        => link1_in_we4,
    link1_in_we5        => link1_in_we5,
    link1_in_valid      => path1_in_valid,
    link1_in_credit_return(12 downto 2) => link1_in_credit_return,
    link1_in_credit_return(1 downto 0)  => path1_in_credit_return,
    link1_out_hi_vc         => link1_out_hi_vc,
    link1_out_hi_vc_ready   => link1_out_hi_vc_ready,
    link1_out_lo_vc         => link1_out_lo,
    link1_out_lo_vc_ready   => link1_out_lo_ready,
    link1_out_credit_return(12 downto 2)    => link1_out_credit_return,
    link1_out_credit_return(1 downto 0)     => path1_out_credit_return,

    link2_in_data       => path2_in_data,
    link2_in_vc_no      => path2_in_vc_no,
    link2_in_we2        => link2_in_we2,
    link2_in_we3        => link2_in_we3,
    link2_in_we4        => link2_in_we4,
    link2_in_we5        => link2_in_we5,
    link2_in_valid      => path2_in_valid,
    link2_in_credit_return(12 downto 2) => link2_in_credit_return,
    link2_in_credit_return(1 downto 0)  => path2_in_credit_return,
    link2_out_hi_vc         => link2_out_hi_vc,
    link2_out_hi_vc_ready   => link2_out_hi_vc_ready,
    link2_out_lo_vc         => link2_out_lo,
    link2_out_lo_vc_ready   => link2_out_lo_ready,
    link2_out_credit_return(12 downto 2)    => link2_out_credit_return,
    link2_out_credit_return(1 downto 0)     => path2_out_credit_return,

    link_up                 => eci_link_up,
    link1_link_up           => link1_eci_link_up,
    link2_link_up           => link2_eci_link_up
);

clk_sys <= clk;
reset_sys <= reset;
link_up <= eci_link_up;
link1_link_up <= link1_eci_link_up;
link2_link_up <= link2_eci_link_up;

link1_in_data   <= path1_in_data;
link1_in_vc_no  <= path1_in_vc_no;
link1_in_valid  <= path1_in_valid;

link2_in_data   <= path2_in_data;
link2_in_vc_no  <= path2_in_vc_no;
link2_in_valid  <= path2_in_valid;

-- Filter out VCs 0, 1 & 13
link1_eci_rx_io_filter : eci_rx_io_vc_filter
port map (
    clk => clk,

    in_data     => path1_in_data,
    in_vc_no    => path1_in_vc_no,
    in_valid    => path1_in_valid,

    out_data     => link1_in.data_filtered,
    out_vc_no    => link1_in.vc_no_filtered,
    out_word_enable => link1_in.word_enable_filtered,
    out_valid    => link1_in.valid_filtered
);

link2_eci_rx_io_filter : eci_rx_io_vc_filter
port map (
    clk => clk,

    in_data     => path2_in_data,
    in_vc_no    => path2_in_vc_no,
    in_valid    => path2_in_valid,

    out_data     => link2_in.data_filtered,
    out_vc_no    => link2_in.vc_no_filtered,
    out_word_enable => link2_in.word_enable_filtered,
    out_valid    => link2_in.valid_filtered
);

-- Input FIFOs
link1_in_fifo : bus_fifo
generic map (
    FIFO_WIDTH      => 483,
    FIFO_DEPTH_BITS => 6,
    MEMORY_TYPE => "distributed"
)
Port map (
    clk         => clk,

    s_data(447 downto 0)    => words_to_vector(link1_in.data_filtered),
    s_data(451 downto 448)  => link1_in.vc_no_filtered(0),
    s_data(455 downto 452)  => link1_in.vc_no_filtered(1),
    s_data(459 downto 456)  => link1_in.vc_no_filtered(2),
    s_data(463 downto 460)  => link1_in.vc_no_filtered(3),
    s_data(467 downto 464)  => link1_in.vc_no_filtered(4),
    s_data(471 downto 468)  => link1_in.vc_no_filtered(5),
    s_data(475 downto 472)  => link1_in.vc_no_filtered(6),
    s_data(482 downto 476)  => link1_in.word_enable_filtered,
    s_valid                 => link1_in.valid_filtered,

    m_data(63 downto 0)     => link1_in.data_fifo(0),
    m_data(127 downto 64)   => link1_in.data_fifo(1),
    m_data(191 downto 128)  => link1_in.data_fifo(2),
    m_data(255 downto 192)  => link1_in.data_fifo(3),
    m_data(319 downto 256)  => link1_in.data_fifo(4),
    m_data(383 downto 320)  => link1_in.data_fifo(5),
    m_data(447 downto 384)  => link1_in.data_fifo(6),
    m_data(451 downto 448)  => link1_in.vc_no_fifo(0),
    m_data(455 downto 452)  => link1_in.vc_no_fifo(1),
    m_data(459 downto 456)  => link1_in.vc_no_fifo(2),
    m_data(463 downto 460)  => link1_in.vc_no_fifo(3),
    m_data(467 downto 464)  => link1_in.vc_no_fifo(4),
    m_data(471 downto 468)  => link1_in.vc_no_fifo(5),
    m_data(475 downto 472)  => link1_in.vc_no_fifo(6),
    m_data(482 downto 476)  => link1_in.word_enable_fifo,
    m_valid                 => link1_in.valid_fifo,
    m_ready                 => link1_in.ready_fifo
);

link2_in_fifo : bus_fifo
generic map (
    FIFO_WIDTH      => 483,
    FIFO_DEPTH_BITS => 6,
    MEMORY_TYPE => "distributed"
)
Port map (
    clk         => clk,

    s_data(447 downto 0)    => words_to_vector(link2_in.data_filtered),
    s_data(451 downto 448)  => link2_in.vc_no_filtered(0),
    s_data(455 downto 452)  => link2_in.vc_no_filtered(1),
    s_data(459 downto 456)  => link2_in.vc_no_filtered(2),
    s_data(463 downto 460)  => link2_in.vc_no_filtered(3),
    s_data(467 downto 464)  => link2_in.vc_no_filtered(4),
    s_data(471 downto 468)  => link2_in.vc_no_filtered(5),
    s_data(475 downto 472)  => link2_in.vc_no_filtered(6),
    s_data(482 downto 476)  => link2_in.word_enable_filtered,
    s_valid                 => link2_in.valid_filtered,

    m_data(63 downto 0)     => link2_in.data_fifo(0),
    m_data(127 downto 64)   => link2_in.data_fifo(1),
    m_data(191 downto 128)  => link2_in.data_fifo(2),
    m_data(255 downto 192)  => link2_in.data_fifo(3),
    m_data(319 downto 256)  => link2_in.data_fifo(4),
    m_data(383 downto 320)  => link2_in.data_fifo(5),
    m_data(447 downto 384)  => link2_in.data_fifo(6),
    m_data(451 downto 448)  => link2_in.vc_no_fifo(0),
    m_data(455 downto 452)  => link2_in.vc_no_fifo(1),
    m_data(459 downto 456)  => link2_in.vc_no_fifo(2),
    m_data(463 downto 460)  => link2_in.vc_no_fifo(3),
    m_data(467 downto 464)  => link2_in.vc_no_fifo(4),
    m_data(471 downto 468)  => link2_in.vc_no_fifo(5),
    m_data(475 downto 472)  => link2_in.vc_no_fifo(6),
    m_data(482 downto 476)  => link2_in.word_enable_fifo,
    m_valid                 => link2_in.valid_fifo,
    m_ready                 => link2_in.ready_fifo
);

-- Serialize messages
link1_eci_rx_word_extractor : eci_rx_vc_word_extractor_buffered
port map (
    clk                 => clk,

    input_words         => link1_in.data_fifo,
    input_vc_no         => link1_in.vc_no_fifo,
    input_word_enable   => link1_in.word_enable_fifo,
    input_valid         => link1_in.valid_fifo,
    input_ready         => link1_in.ready_fifo,

    output              => link1_in.data,
    output_ready        => link1_in.ready
);

link2_eci_rx_word_extractor : eci_rx_vc_word_extractor_buffered
port map (
    clk                 => clk,

    input_words         => link2_in.data_fifo,
    input_vc_no         => link2_in.vc_no_fifo,
    input_word_enable   => link2_in.word_enable_fifo,
    input_valid         => link2_in.valid_fifo,
    input_ready         => link2_in.ready_fifo,

    output              => link2_in.data,
    output_ready        => link2_in.ready
);

-- Count RX credits
link1_vc0_credit_counter : rx_credit_counter
generic map (
    VC_NO               => 0
)
port map (
    clk                 => clk,
    reset_n             => eci_link_up,
    input_valid         => link1_in.data.valid,
    input_ready         => link1_in.ready,
    input_vc_no         => link1_in.data.vc_no,
    credit_return       => path1_in_credit_return(0)
);

link1_vc1_credit_counter : rx_credit_counter
generic map (
    VC_NO               => 1
)
port map (
    clk                 => clk,
    reset_n             => eci_link_up,
    input_valid         => link1_in.data.valid,
    input_ready         => link1_in.ready,
    input_vc_no         => link1_in.data.vc_no,
    credit_return       => path1_in_credit_return(1)
);

link2_vc0_credit_counter : rx_credit_counter
generic map (
    VC_NO               => 0
)
port map (
    clk                 => clk,
    reset_n             => eci_link_up,
    input_valid         => link2_in.data.valid,
    input_ready         => link2_in.ready,
    input_vc_no         => link2_in.data.vc_no,
    credit_return       => path2_in_credit_return(0)
);

link2_vc1_credit_counter : rx_credit_counter
generic map (
    VC_NO               => 1
)
port map (
    clk                 => clk,
    reset_n             => eci_link_up,
    input_valid         => link2_in.data.valid,
    input_ready         => link2_in.ready,
    input_vc_no         => link2_in.data.vc_no,
    credit_return       => path2_in_credit_return(1)
);

-- Handle VC0, VC1 & VC13 messages,
i_eci_io_bridge : eci_io_bridge_lite
port map (
    clk => clk,
    reset => reset,

    link1_in                => link1_in.data,
    link1_in_ready          => link1_in.ready,
    link1_out               => link1_io,
    link1_out_ready         => link1_io_ready,

    -- Link 2 interface
    link2_in                => link2_in.data,
    link2_in_ready          => link2_in.ready,
    link2_out               => link2_io,
    link2_out_ready         => link2_io_ready,

    -- AXI Lite master interface for IO addr space
    m_io_axil_awaddr  => m_io_axil_awaddr,
    m_io_axil_awvalid => m_io_axil_awvalid,
    m_io_axil_awready => m_io_axil_awready,
    m_io_axil_wdata   => m_io_axil_wdata,
    m_io_axil_wstrb   => m_io_axil_wstrb,
    m_io_axil_wvalid  => m_io_axil_wvalid,
    m_io_axil_wready  => m_io_axil_wready,
    m_io_axil_bresp   => m_io_axil_bresp,
    m_io_axil_bvalid  => m_io_axil_bvalid,
    m_io_axil_bready  => m_io_axil_bready,
    m_io_axil_araddr  => m_io_axil_araddr,
    m_io_axil_arvalid => m_io_axil_arvalid,
    m_io_axil_arready => m_io_axil_arready,
    m_io_axil_rdata   => m_io_axil_rdata,
    m_io_axil_rresp   => m_io_axil_rresp,
    m_io_axil_rvalid  => m_io_axil_rvalid,
    m_io_axil_rready  => m_io_axil_rready,

    -- AXI Lite master interface for IO addr space
    s_io_axil_awaddr  => s_io_axil_awaddr,
    s_io_axil_awvalid => s_io_axil_awvalid,
    s_io_axil_awready => s_io_axil_awready,
    s_io_axil_wdata   => s_io_axil_wdata,
    s_io_axil_wstrb   => s_io_axil_wstrb,
    s_io_axil_wvalid  => s_io_axil_wvalid,
    s_io_axil_wready  => s_io_axil_wready,
    s_io_axil_bresp   => s_io_axil_bresp,
    s_io_axil_bvalid  => s_io_axil_bvalid,
    s_io_axil_bready  => s_io_axil_bready,
    s_io_axil_araddr  => s_io_axil_araddr,
    s_io_axil_arvalid => s_io_axil_arvalid,
    s_io_axil_arready => s_io_axil_arready,
    s_io_axil_rdata   => s_io_axil_rdata,
    s_io_axil_rresp   => s_io_axil_rresp,
    s_io_axil_rvalid  => s_io_axil_rvalid,
    s_io_axil_rready  => s_io_axil_rready,

    m_icap_axi_awaddr   => m_icap_axi_awaddr,
    m_icap_axi_awvalid  => m_icap_axi_awvalid,
    m_icap_axi_awready  => m_icap_axi_awready,

    m_icap_axi_wdata    => m_icap_axi_wdata,
    m_icap_axi_wstrb    => m_icap_axi_wstrb,
    m_icap_axi_wvalid   => m_icap_axi_wvalid,
    m_icap_axi_wready   => m_icap_axi_wready,

    m_icap_axi_bresp    => m_icap_axi_bresp,
    m_icap_axi_bvalid   => m_icap_axi_bvalid,
    m_icap_axi_bready   => m_icap_axi_bready,

    m_icap_axi_araddr   => m_icap_axi_araddr,
    m_icap_axi_arvalid  => m_icap_axi_arvalid,
    m_icap_axi_arready  => m_icap_axi_arready,

    m_icap_axi_rdata    => m_icap_axi_rdata,
    m_icap_axi_rresp    => m_icap_axi_rresp,
    m_icap_axi_rvalid   => m_icap_axi_rvalid,
    m_icap_axi_rready   => m_icap_axi_rready
);

-- Count TX credits
link1_tlk_credits : tlk_credits
port map (
    clk             => clk,
    rst_n           => link1_eci_link_up,
    in_hi.data(0)   => (others => '-'),
    in_hi.data(1)   => (others => '-'),
    in_hi.data(2)   => (others => '-'),
    in_hi.data(3)   => (others => '-'),
    in_hi.data(4)   => (others => '-'),
    in_hi.data(5)   => (others => '-'),
    in_hi.data(6)   => (others => '-'),
    in_hi.data(7)   => (others => '-'),
    in_hi.data(8)   => (others => '-'),
    in_hi.vc_no     => "----",
    in_hi.size      => "---",
    in_hi.valid     => '0',
    in_lo           => link1_io,
    in_lo_ready     => link1_io_ready,
    out_hi          => open,
    out_hi_ready    => '0',
    out_lo          => link1_io_out_cred,
    out_lo_ready    => link1_io_out_cred_ready,
    credit_return(12 downto 2) => "00000000000",
    credit_return(1 downto 0) => path1_out_credit_return
);

link2_tlk_credits : tlk_credits
port map (
    clk             => clk,
    rst_n           => link2_eci_link_up,
    in_hi.data(0)   => (others => '-'),
    in_hi.data(1)   => (others => '-'),
    in_hi.data(2)   => (others => '-'),
    in_hi.data(3)   => (others => '-'),
    in_hi.data(4)   => (others => '-'),
    in_hi.data(5)   => (others => '-'),
    in_hi.data(6)   => (others => '-'),
    in_hi.data(7)   => (others => '-'),
    in_hi.data(8)   => (others => '-'),
    in_hi.vc_no     => "----",
    in_hi.size      => "---",
    in_hi.valid     => '0',
    in_lo           => link2_io,
    in_lo_ready     => link2_io_ready,
    out_hi          => open,
    out_hi_ready    => '0',
    out_lo          => link2_io_out_cred,
    out_lo_ready    => link2_io_out_cred_ready,
    credit_return(12 downto 2) => "00000000000",
    credit_return(1 downto 0) => path2_out_credit_return
);

-- Mux IO Bridge channels (VCs 0, 1 & 13) with others (VCs 2-12)
link1_lo_vc_muxer : eci_channel_muxer
generic map (
    CHANNELS    => 2
)
port map (
    clk         => clk,

    inputs(0)    => link1_io_out_cred,
    inputs(1)    => link1_out_lo_vc,

    inputs_ready(0) => link1_io_out_cred_ready,
    inputs_ready(1) => link1_out_lo_vc_ready,

    output          => link1_out_lo,
    output_ready    => link1_out_lo_ready
);

link2_lo_vc_muxer : eci_channel_muxer
generic map (
    CHANNELS    => 2
)
port map (
    clk         => clk,

    inputs(0)    => link2_io_out_cred,
    inputs(1)    => link2_out_lo_vc,

    inputs_ready(0) => link2_io_out_cred_ready,
    inputs_ready(1) => link2_out_lo_vc_ready,

    output          => link2_out_lo,
    output_ready    => link2_out_lo_ready
);

end Behavioral;
