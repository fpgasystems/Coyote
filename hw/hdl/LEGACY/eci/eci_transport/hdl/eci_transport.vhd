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

entity eci_transport is
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

    link1_in_data          : out WORDS(6 downto 0);
    link1_in_vc_no         : out VCS(6 downto 0);
    link1_in_we2           : out std_logic_vector(6 downto 0);
    link1_in_we3           : out std_logic_vector(6 downto 0);
    link1_in_we4           : out std_logic_vector(6 downto 0);
    link1_in_we5           : out std_logic_vector(6 downto 0);
    link1_in_valid         : out std_logic;
    link1_in_credit_return : in std_logic_vector(12 downto 0);
    -------------------------- MOB VCs Inputs ----------------------------//
    link1_out_hi_vc         : in ECI_CHANNEL;
    link1_out_hi_vc_ready   : out STD_LOGIC;
    link1_out_lo_vc         : in ECI_CHANNEL;
    link1_out_lo_vc_ready   : out STD_LOGIC;
    link1_out_credit_return : out std_logic_vector(12 downto 0);

    link2_in_data          : out WORDS(6 downto 0);
    link2_in_vc_no         : out VCS(6 downto 0);
    link2_in_we2           : out std_logic_vector(6 downto 0);
    link2_in_we3           : out std_logic_vector(6 downto 0);
    link2_in_we4           : out std_logic_vector(6 downto 0);
    link2_in_we5           : out std_logic_vector(6 downto 0);
    link2_in_valid         : out std_logic;
    link2_in_credit_return : in std_logic_vector(12 downto 0);
    -------------------------- MOB VCs Inputs ----------------------------//
    link2_out_hi_vc         : in ECI_CHANNEL;
    link2_out_hi_vc_ready   : out STD_LOGIC;
    link2_out_lo_vc         : in ECI_CHANNEL;
    link2_out_lo_vc_ready   : out STD_LOGIC;
    link2_out_credit_return : out std_logic_vector(12 downto 0);

    link_up                 : out std_logic;
    link1_link_up           : out std_logic;
    link2_link_up           : out std_logic;

    -- for debug purposes
    link1_eci_block_out         : out std_logic_vector(511 downto 0);
    link1_eci_block_out_valid   : out std_logic;
    link1_eci_crc_match_out     : out std_logic;

    link2_eci_block_out         : out std_logic_vector(511 downto 0);
    link2_eci_block_out_valid   : out std_logic;
    link2_eci_crc_match_out     : out std_logic
);
end eci_transport;

architecture Behavioral of eci_transport is

component xcvr_link1
port (
    gtwiz_userclk_tx_active_in : in std_logic_vector(0 downto 0);
    gtwiz_userclk_rx_active_in : in std_logic_vector(0 downto 0);
    rxoutclk_out : out std_logic_vector(11 downto 0);
    rxusrclk_in : in std_logic_vector(11 downto 0);
    rxusrclk2_in : in std_logic_vector(11 downto 0);
    txoutclk_out : out std_logic_vector(11 downto 0);
    txusrclk_in : in std_logic_vector(11 downto 0);
    txusrclk2_in : in std_logic_vector(11 downto 0);

    ---- Reset Controller Signals
    -- 250MHz free-running clock for the reset controller
    gtwiz_reset_clk_freerun_in         :  in std_logic_vector(0 downto 0);
    -- Reset everything
    gtwiz_reset_all_in                 :  in std_logic_vector(0 downto 0);
    -- Reset TX-side components
    gtwiz_reset_tx_pll_and_datapath_in :  in std_logic_vector(0 downto 0);
    gtwiz_reset_tx_datapath_in         :  in std_logic_vector(0 downto 0);
    -- Reset RX-side components
    gtwiz_reset_rx_pll_and_datapath_in :  in std_logic_vector(0 downto 0);
    gtwiz_reset_rx_datapath_in         :  in std_logic_vector(0 downto 0);
    -- Clock Recovery is stable
    gtwiz_reset_rx_cdr_stable_out      : out std_logic_vector(0 downto 0);
    -- TX/RX subsystem is out of reset
    gtwiz_reset_tx_done_out            : out std_logic_vector(0 downto 0);
    gtwiz_reset_rx_done_out            : out std_logic_vector(0 downto 0);

    -- Data to be transmitted, synchronised to tx_usrclk2
    gtwiz_userdata_tx_in  :  in std_logic_vector(12*64-1 downto 0);
    -- Received data, synchronised to rx_usrclk2
    gtwiz_userdata_rx_out : out std_logic_vector(12*64-1 downto 0);

    -- The 156.25MHz reference clocks
    gtrefclk00_in : in std_logic_vector(2 downto 0);

    -- The recovered (10GHz) clocks, and the buffered reference clock.
    qpll0outclk_out    : out std_logic_vector(2 downto 0);
    qpll0outrefclk_out : out std_logic_vector(2 downto 0);

    -- RX differential pairs
    gtyrxn_in : in std_logic_vector(11 downto 0);
    gtyrxp_in : in std_logic_vector(11 downto 0);

    -- TX differential pair
    gtytxn_out : out std_logic_vector(11 downto 0);
    gtytxp_out : out std_logic_vector(11 downto 0);

    -- Gearbox
    rxgearboxslip_in :  in std_logic_vector(11 downto 0);
    rxdatavalid_out :   out std_logic_vector(2*12-1 downto 0);
    rxheader_out :      out std_logic_vector(6*12-1 downto 0);
    rxheadervalid_out : out std_logic_vector(2*12-1 downto 0);
    rxstartofseq_out :  out std_logic_vector(2*12-1 downto 0);
    txheader_in       : in std_logic_vector(6*12-1 downto 0);
    txsequence_in     : in std_logic_vector(7*12-1 downto 0);

    -- RX bypass buffer
    gtwiz_buffbypass_rx_reset_in : in std_logic_vector(0 downto 0);
    gtwiz_buffbypass_rx_start_user_in : in std_logic_vector(0 downto 0);
    gtwiz_buffbypass_rx_done_out : out std_logic_vector(0 downto 0);
    gtwiz_buffbypass_rx_error_out : out std_logic_vector(0 downto 0);

    -- TX bypass buffer
    gtwiz_buffbypass_tx_reset_in : in std_logic_vector(0 downto 0);
    gtwiz_buffbypass_tx_start_user_in : in std_logic_vector(0 downto 0);
    gtwiz_buffbypass_tx_done_out : out std_logic_vector(0 downto 0);
    gtwiz_buffbypass_tx_error_out : out std_logic_vector(0 downto 0);

    -- Internal reset status.
    rxpmaresetdone_out    : out std_logic_vector(11 downto 0);
    txpmaresetdone_out    : out std_logic_vector(11 downto 0);
    txprgdivresetdone_out : out std_logic_vector(11 downto 0);
    gtpowergood_out       : out std_logic_vector(11 downto 0);

    -- TX driver control
    txdiffctrl_in   : in std_logic_vector(5*12-1 downto 0);
    txpostcursor_in : in std_logic_vector(5*12-1 downto 0);
    txprecursor_in  : in std_logic_vector(5*12-1 downto 0)
);
end component;

component xcvr_link2
port (
    gtwiz_userclk_tx_active_in : in std_logic_vector(0 downto 0);
    gtwiz_userclk_rx_active_in : in std_logic_vector(0 downto 0);
    rxoutclk_out : out std_logic_vector(11 downto 0);
    rxusrclk_in : in std_logic_vector(11 downto 0);
    rxusrclk2_in : in std_logic_vector(11 downto 0);
    txoutclk_out : out std_logic_vector(11 downto 0);
    txusrclk_in : in std_logic_vector(11 downto 0);
    txusrclk2_in : in std_logic_vector(11 downto 0);

    ---- Reset Controller Signals
    -- 250MHz free-running clock for the reset controller
    gtwiz_reset_clk_freerun_in         :  in std_logic_vector(0 downto 0);
    -- Reset everything
    gtwiz_reset_all_in                 :  in std_logic_vector(0 downto 0);
    -- Reset TX-side components
    gtwiz_reset_tx_pll_and_datapath_in :  in std_logic_vector(0 downto 0);
    gtwiz_reset_tx_datapath_in         :  in std_logic_vector(0 downto 0);
    -- Reset RX-side components
    gtwiz_reset_rx_pll_and_datapath_in :  in std_logic_vector(0 downto 0);
    gtwiz_reset_rx_datapath_in         :  in std_logic_vector(0 downto 0);
    -- Clock Recovery is stable
    gtwiz_reset_rx_cdr_stable_out      : out std_logic_vector(0 downto 0);
    -- TX/RX subsystem is out of reset
    gtwiz_reset_tx_done_out            : out std_logic_vector(0 downto 0);
    gtwiz_reset_rx_done_out            : out std_logic_vector(0 downto 0);

    -- Data to be transmitted, synchronised to tx_usrclk2
    gtwiz_userdata_tx_in  :  in std_logic_vector(12*64-1 downto 0);
    -- Received data, synchronised to rx_usrclk2
    gtwiz_userdata_rx_out : out std_logic_vector(12*64-1 downto 0);

    -- The 156.25MHz reference clocks
    gtrefclk00_in : in std_logic_vector(2 downto 0);

    -- The recovered (10GHz) clocks, and the buffered reference clock.
    qpll0outclk_out    : out std_logic_vector(2 downto 0);
    qpll0outrefclk_out : out std_logic_vector(2 downto 0);

    -- RX differential pairs
    gtyrxn_in : in std_logic_vector(11 downto 0);
    gtyrxp_in : in std_logic_vector(11 downto 0);

    -- TX differential pair
    gtytxn_out : out std_logic_vector(11 downto 0);
    gtytxp_out : out std_logic_vector(11 downto 0);

    -- Gearbox
    rxgearboxslip_in :  in std_logic_vector(11 downto 0);
    rxdatavalid_out :   out std_logic_vector(2*12-1 downto 0);
    rxheader_out :      out std_logic_vector(6*12-1 downto 0);
    rxheadervalid_out : out std_logic_vector(2*12-1 downto 0);
    rxstartofseq_out :  out std_logic_vector(2*12-1 downto 0);
    txheader_in       : in std_logic_vector(6*12-1 downto 0);
    txsequence_in     : in std_logic_vector(7*12-1 downto 0);

    -- RX bypass buffer
    gtwiz_buffbypass_rx_reset_in : in std_logic_vector(0 downto 0);
    gtwiz_buffbypass_rx_start_user_in : in std_logic_vector(0 downto 0);
    gtwiz_buffbypass_rx_done_out : out std_logic_vector(0 downto 0);
    gtwiz_buffbypass_rx_error_out : out std_logic_vector(0 downto 0);

    -- TX bypass buffer
    gtwiz_buffbypass_tx_reset_in : in std_logic_vector(0 downto 0);
    gtwiz_buffbypass_tx_start_user_in : in std_logic_vector(0 downto 0);
    gtwiz_buffbypass_tx_done_out : out std_logic_vector(0 downto 0);
    gtwiz_buffbypass_tx_error_out : out std_logic_vector(0 downto 0);

    -- Internal reset status.
    rxpmaresetdone_out    : out std_logic_vector(11 downto 0);
    txpmaresetdone_out    : out std_logic_vector(11 downto 0);
    txprgdivresetdone_out : out std_logic_vector(11 downto 0);
    gtpowergood_out       : out std_logic_vector(11 downto 0);

    -- TX driver control
    txdiffctrl_in   : in std_logic_vector(5*12-1 downto 0);
    txpostcursor_in : in std_logic_vector(5*12-1 downto 0);
    txprecursor_in  : in std_logic_vector(5*12-1 downto 0)
);
end component;

component il_rx_link_gearbox is
generic (
    LANES : integer;
    METAFRAME : integer
);
port (
    clk_rx : in std_logic;
    reset  : in std_logic;

    xcvr_rxdata  : in std_logic_vector(LANES*64 - 1 downto 0);
    xcvr_rxdatavalid : in std_logic_vector(2*LANES - 1 downto 0);
    xcvr_rxheader    : in std_logic_vector(6*LANES - 1 downto 0);
    xcvr_rxheadervalid : in std_logic_vector(2*LANES - 1 downto 0);
    xcvr_rxgearboxslip : out std_logic_vector(LANES - 1 downto 0);

    output        : out std_logic_vector(LANES*64 - 1 downto 0);
    output_valid  : out std_logic;
    ctrl_word_out : out std_logic_vector(LANES - 1 downto 0);

    lane_word_lock  : out std_logic_vector(  LANES - 1 downto 0);
    lane_frame_lock : out std_logic_vector(  LANES - 1 downto 0);
    lane_crc32_bad  : out std_logic_vector(  LANES - 1 downto 0);
    lane_status     : out std_logic_vector(2*LANES - 1 downto 0);

    link_aligned  : out std_logic;
    total_skew     : out std_logic_vector(2 downto 0)
);
end component;

component il_tx_link_gearbox is
generic (
    LANES : integer;
    METAFRAME : integer
);
port (
    clk_tx : in std_logic;
    reset  : in std_logic;

    input        :  in std_logic_vector(LANES*64 - 1 downto 0);
    input_ready  : out std_logic;
    ctrl_word_in :  in std_logic_vector(LANES - 1 downto 0);

    xcvr_txdata  : out std_logic_vector(LANES*64 - 1 downto 0);
    xcvr_txheader     : out std_logic_vector(6*LANES-1 downto 0);
    xcvr_txsequence   : out std_logic_vector(7*LANES-1 downto 0)
);
end component;


component eci_rx_blk is
generic (
    LANES : integer := 12
);
port (
    clk_rx : in std_logic;

    clk_blk   : in std_logic;

    link_aligned : in std_logic;

    link_data       : in std_logic_vector(64*12-1 downto 0);
    link_data_valid : in std_logic;
    ctrl_word       : in std_logic_vector( 11 downto 0);

    block_out       : out std_logic_vector(511 downto 0);
    block_out_valid : out std_logic;
    crc_match_out   : out std_logic
);
end component;

component eci_tx_blk is
generic (
    LANES : integer := 12
);
port (
    clk_tx          : in std_logic;

    clk_blk         : in std_logic;

    block_in        :  in std_logic_vector(511 downto 0);
    block_in_ready  : out std_logic;

    link_data       : out std_logic_vector(LANES*64-1 downto 0);
    link_data_ready :  in std_logic;
    ctrl_word_out   : out std_logic_vector( LANES-1 downto 0)
);
end component;

component eci_blk is
port (
    clk_blk   : in std_logic;
    reset_blk : in std_logic;

    block_in       : in std_logic_vector(511 downto 0);
    block_in_valid : in std_logic;
    crc_match_in   : in std_logic;

    block_out       : out std_logic_vector(511 downto 0);
    block_out_ready :  in std_logic
);
end component;

component eci_link is
port (
    clk     : in std_logic;
    reset   : in std_logic;
    link_up : out std_logic;
    link_state  :  out std_logic_vector(5 downto 0);

    blk_rx_data   : in std_logic_vector(511 downto 0);
    blk_rx_valid  : in std_logic;
    blk_crc_match : in std_logic;
    blk_tx_data   : out std_logic_vector(511 downto 0);
    blk_tx_ready  : in std_logic;

    mib_data            : out WORDS(6 downto 0);
    mib_vc_no           : out VCS(6 downto 0);
    mib_valid           : out std_logic;
    mib_we2             : out std_logic_vector(6 downto 0);
    mib_we3             : out std_logic_vector(6 downto 0);
    mib_we4             : out std_logic_vector(6 downto 0);
    mib_we5             : out std_logic_vector(6 downto 0);
    mib_credit_return   : in std_logic_vector(12 downto 0);

    -------------------------- MOB VCs Inputs ----------------------------//
    mob_hi_data         : in WORDS (8 downto 0);
    mob_hi_vc_no        : in std_logic_vector(3 downto 0);
    mob_hi_size         : in std_logic_vector(2 downto 0);
    mob_hi_valid        : in STD_LOGIC;
    mob_hi_ready        : out STD_LOGIC;
    mob_lo_data         : in std_logic_vector(63 downto 0);
    mob_lo_vc_no        : in std_logic_vector(3 downto 0);
    mob_lo_valid        : in STD_LOGIC;
    mob_lo_ready        : out STD_LOGIC;
    mob_credit_return   : out std_logic_vector(12 downto 0)
);
end component;

component ila_eci_edge is
port (
    clk         : in std_logic;

    probe0      : in std_logic_vector(0 downto 0);
    probe1      : in std_logic_vector(5 downto 0);
    probe2      : in std_logic_vector(0 downto 0);

    probe3      : in std_logic_vector(0 downto 0);
    probe4      : in std_logic_vector(0 downto 0);
    probe5      : in std_logic_vector(0 downto 0);
    probe6      : in std_logic_vector(39 downto 0);
    probe7      : in std_logic_vector(63 downto 0);
    probe8      : in std_logic_vector(63 downto 0);
    probe9      : in std_logic_vector(63 downto 0);
    probe10     : in std_logic_vector(63 downto 0);
    probe11     : in std_logic_vector(63 downto 0);
    probe12     : in std_logic_vector(63 downto 0);
    probe13     : in std_logic_vector(63 downto 0);
    probe14     : in std_logic_vector(0 downto 0);

    probe15     : in std_logic_vector(0 downto 0);
    probe16     : in std_logic_vector(0 downto 0);
    probe17     : in std_logic_vector(0 downto 0);
    probe18     : in std_logic_vector(39 downto 0);
    probe19     : in std_logic_vector(63 downto 0);
    probe20     : in std_logic_vector(63 downto 0);
    probe21     : in std_logic_vector(63 downto 0);
    probe22     : in std_logic_vector(63 downto 0);
    probe23     : in std_logic_vector(63 downto 0);
    probe24     : in std_logic_vector(63 downto 0);
    probe25     : in std_logic_vector(63 downto 0);

    probe26     : in std_logic_vector(0 downto 0);
    probe27     : in std_logic_vector(5 downto 0);
    probe28     : in std_logic_vector(0 downto 0);

    probe29     : in std_logic_vector(0 downto 0);
    probe30     : in std_logic_vector(0 downto 0);
    probe31     : in std_logic_vector(0 downto 0);
    probe32     : in std_logic_vector(39 downto 0);
    probe33     : in std_logic_vector(63 downto 0);
    probe34     : in std_logic_vector(63 downto 0);
    probe35     : in std_logic_vector(63 downto 0);
    probe36     : in std_logic_vector(63 downto 0);
    probe37     : in std_logic_vector(63 downto 0);
    probe38     : in std_logic_vector(63 downto 0);
    probe39     : in std_logic_vector(63 downto 0);
    probe40     : in std_logic_vector(0 downto 0);

    probe41     : in std_logic_vector(0 downto 0);
    probe42     : in std_logic_vector(0 downto 0);
    probe43     : in std_logic_vector(0 downto 0);
    probe44     : in std_logic_vector(39 downto 0);
    probe45     : in std_logic_vector(63 downto 0);
    probe46     : in std_logic_vector(63 downto 0);
    probe47     : in std_logic_vector(63 downto 0);
    probe48     : in std_logic_vector(63 downto 0);
    probe49     : in std_logic_vector(63 downto 0);
    probe50     : in std_logic_vector(63 downto 0);
    probe51     : in std_logic_vector(63 downto 0)
);
end component;

type LINK is record
    xcvr_txd_raw        : std_logic_vector(64 * 12-1 downto 0);
    xcvr_rxd_raw        : std_logic_vector(64 * 12-1 downto 0);
    xcvr_txd            : std_logic_vector(64 * 12-1 downto 0);
    xcvr_rxd            : std_logic_vector(64 * 12-1 downto 0);
    xcvr_reset_rx       : std_logic;
    xcvr_tx_ready       : std_logic;
    xcvr_rx_ready       : std_logic;

    xcvr_txdiffctrl     : std_logic_vector(5*12-1 downto 0);
    xcvr_txpostcursor   : std_logic_vector(5*12-1 downto 0);
    xcvr_txprecursor    : std_logic_vector(5*12-1 downto 0);

    xcvr_rxgearboxslip  : std_logic_vector(11 downto 0);
    xcvr_rxdatavalid    : std_logic_vector(2*12-1 downto 0);
    xcvr_rxheader       : std_logic_vector(6*12-1 downto 0);
    xcvr_rxheadervalid  : std_logic_vector(2*12-1 downto 0);
    xcvr_rxstartofseq   : std_logic_vector(2*12-1 downto 0);
    xcvr_txheader       : std_logic_vector(6*12-1 downto 0);
    xcvr_txsequence     : std_logic_vector(7*12-1 downto 0);

    userclk_tx_active_in : std_logic;
    userclk_rx_active_in : std_logic;
    rxoutclk : std_logic_vector(11 downto 0);
    rxusrclk : std_logic_vector(11 downto 0);
    rxusrclk2 : std_logic_vector(11 downto 0);
    txoutclk : std_logic_vector(11 downto 0);
    txusrclk: std_logic_vector(11 downto 0);
    txusrclk2 : std_logic_vector(11 downto 0);

    -- The per-link transceiver data
    txd : std_logic_vector(64*12-1 downto 0);
    txd_header     : std_logic_vector(3 * 12-1 downto 0);
    txd_ready      : std_logic;
    rxd : std_logic_vector(64*12-1 downto 0);

    -- Transceiver-derived clocks.
    clk_tx, clk_rx : std_logic;
    clk_ref : std_logic_vector(2 downto 0);
    reset : std_logic;
end record LINK;

-- Interlaken link signals
type INTERLAKEN is record
    rx_data             : std_logic_vector(64*12-1 downto 0);
    rx_data_valid       : std_logic;
    rx_ctrl_word        : std_logic_vector(11 downto 0);
    rx_lane_word_lock   : std_logic_vector(11 downto 0);
    rx_lane_frame_lock  : std_logic_vector(11 downto 0);
    rx_word_lock        : std_logic;
    rx_frame_lock       : std_logic;
    rx_lane_crc32_bad   : std_logic_vector(11 downto 0);
    rx_lane_status      : std_logic_vector(2*12-1 downto 0);
    rx_aligned          : std_logic;
    rx_aligned_old      : std_logic;
    rx_total_skew       : std_logic_vector(2 downto 0);

    tx_data             : std_logic_vector(64*12-1 downto 0);
    tx_data_ready       : std_logic;
    tx_ctrl_word        : std_logic_vector(11 downto 0);

    usr_rx_reset : std_logic;
    usr_tx_reset : std_logic;
end record INTERLAKEN;

-- ECI block-layer signals, on clk
type ECI_BLOCK is record
    link_up             : std_logic;
    link_state          : std_logic_vector(5 downto 0);
    old_link_state      : std_logic_vector(5 downto 0);
    rx_block            : std_logic_vector(511 downto 0);
    rx_block_word1      : std_logic_vector(63 downto 0);
    rx_block_word2      : std_logic_vector(63 downto 0);
    rx_block_word3      : std_logic_vector(63 downto 0);
    rx_block_word4      : std_logic_vector(63 downto 0);
    rx_block_word5      : std_logic_vector(63 downto 0);
    rx_block_word6      : std_logic_vector(63 downto 0);
    rx_block_word7      : std_logic_vector(63 downto 0);
    rx_block_header     : std_logic_vector(39 downto 0);
    rx_block_crc        : std_logic_vector(23 downto 0);
    rx_block_valid      : std_logic;
    rx_block_crc_match  : std_logic;
    tx_block            : std_logic_vector(511 downto 0);
    tx_block_word1      : std_logic_vector(63 downto 0);
    tx_block_word2      : std_logic_vector(63 downto 0);
    tx_block_word3      : std_logic_vector(63 downto 0);
    tx_block_word4      : std_logic_vector(63 downto 0);
    tx_block_word5      : std_logic_vector(63 downto 0);
    tx_block_word6      : std_logic_vector(63 downto 0);
    tx_block_word7      : std_logic_vector(63 downto 0);
    tx_block_header     : std_logic_vector(39 downto 0);
    tx_block_ready      : std_logic;

    link_state_change               : std_logic;
    rx_has_data_payload             : std_logic;
    rx_has_data_payload_filtered    : std_logic;
    tx_has_data_payload             : std_logic;
    tx_has_data_payload_filtered    : std_logic;
    rx_has_gsync                    : std_logic_vector(6 downto 0);
    tx_has_gsync                    : std_logic_vector(6 downto 0);
end record ECI_BLOCK;

-- power on reset
signal por_counter : unsigned(4 downto 0) := "00000";
signal reset, reset_u   : std_logic;

signal clk      : std_logic;
signal clk_gt   : std_logic;

signal realign_counter      : integer range 0 to 131071 := 0;
signal realign_counter_int  : unsigned(27 downto 0) := (others => '0');

signal link1, link2 : LINK;
signal link1_il, link2_il : INTERLAKEN;
signal link1_eci, link2_eci : ECI_BLOCK;

begin

---- Power-on-reset

i_reset_delayer : process(clk)
begin
    if rising_edge(clk) then
        if por_counter < 16 then -- first, deassert reset
            reset_u <= '0';
            por_counter <= por_counter + 1;
        elsif por_counter < 31 then -- next, assert reset
            reset_u <= '1';
            por_counter <= por_counter + 1;
        else -- and then deassert reset
            reset_u <= '0';
        end if;
    end if;
end process;

reset <= reset_u;

reset_sys <= reset;

i_link1_reset : xpm_cdc_single
port map (
    src_in => reset,
    src_clk => clk,
    dest_clk => clk_gt,
    dest_out => link1.reset
);

i_link2_reset : xpm_cdc_single
port map (
    src_in => reset,
    src_clk => clk,
    dest_clk => clk_gt,
    dest_out => link2.reset
);

-- The Ultrascale transceiver wizard expects a single-ended reference clock.
-- This instantiates the clock buffer in the transceiver quad - a normal
-- IBUFDS *won't* work.
eci_refclks: for i in 0 to 2 generate
ref_buf_link1 : IBUFDS_GTE4
generic map (
    REFCLK_EN_TX_PATH  => '0',
    REFCLK_HROW_CK_SEL => "00",
    REFCLK_ICNTL_RX    => "00"
)
port map (
    O   => link1.clk_ref(i),
    I   => eci_gt_clk_p_link1(i),
    IB  => eci_gt_clk_n_link1(i),
    CEB => '0'
);

ref_buf_link2 : IBUFDS_GTE4
generic map (
    REFCLK_EN_TX_PATH  => '0',
    REFCLK_HROW_CK_SEL => "00",
    REFCLK_ICNTL_RX    => "00"
)
port map (
    O   => link2.clk_ref(i),
    I   => eci_gt_clk_p_link2(i + 3),
    IB  => eci_gt_clk_n_link2(i + 3),
    CEB => '0'
);
end generate eci_refclks;

-- 322.265625 MHz
i_clk_gt_link1 : BUFG_GT
port map (
    I => link1.txoutclk(5),
    CE => '1',
    CEMASK => '0',
    CLR =>'0',
    CLRMASK => '0',
    DIV => "000",
    O => clk
);

clk_sys <= clk;

-- 161.1328125 MHz
i_clk_gt2_link1 : BUFG_GT
port map (
    I => link1.txoutclk(5),
    CE => '1',
    CEMASK => '0',
    CLR =>'0',
    CLRMASK => '0',
    DIV => "001", -- divide by 2
    O => clk_gt
);

-- 107.421875 MHz
i_clk_gt3_link1 : BUFG_GT
port map (
    I => link1.txoutclk(5),
    CE => '1',
    CEMASK => '0',
    CLR =>'0',
    CLRMASK => '0',
    DIV => "010", -- divide by 3
    O => clk_icap
);

link1.clk_rx <= clk_gt;
link1.clk_tx <= clk_gt;

link1.rxusrclk <= (others => clk);
link1.rxusrclk2 <= (others => clk_gt);
link1.txusrclk <= (others => clk);
link1.txusrclk2 <= (others => clk_gt);

i_userclk_active : xpm_cdc_single
port map (
    src_in => '1',
    src_clk => clk_gt,
    dest_clk => clk_io,
    dest_out => link1.userclk_tx_active_in
);

link1.userclk_rx_active_in <= link1.userclk_tx_active_in;
link2.userclk_tx_active_in <= link1.userclk_tx_active_in;
link2.userclk_rx_active_in <= link1.userclk_tx_active_in;

-- Maximum swing
link1.xcvr_txdiffctrl <= (others => '1');
link1.xcvr_txpostcursor <= (others => '0');
link1.xcvr_txprecursor <= (others => '0');
--link1.xcvr_reset <= reset;

--- Transceivers

xcvr1 : xcvr_link1
port map (
    gtwiz_userclk_tx_active_in(0) => link1.userclk_tx_active_in,
    gtwiz_userclk_rx_active_in(0) => link1.userclk_rx_active_in,
    rxoutclk_out    => link1.rxoutclk,
    rxusrclk_in     => link1.rxusrclk,
    rxusrclk2_in    => link1.rxusrclk2,
    txoutclk_out    => link1.txoutclk,
    txusrclk_in     => link1.txusrclk,
    txusrclk2_in    => link1.txusrclk2,

    gtwiz_buffbypass_rx_reset_in(0)       => '0',
    gtwiz_buffbypass_rx_start_user_in(0)  => '0',
    gtwiz_buffbypass_tx_reset_in(0)       => '0',
    gtwiz_buffbypass_tx_start_user_in(0)  => '0',

    gtwiz_reset_clk_freerun_in(0)         => clk_io,
    gtwiz_reset_all_in(0)                 => '0',
    gtwiz_reset_tx_pll_and_datapath_in(0) => '0',
    gtwiz_reset_tx_datapath_in(0)         => '0',
    gtwiz_reset_rx_pll_and_datapath_in(0) => '0',
    gtwiz_reset_rx_datapath_in(0)         => link1.xcvr_reset_rx,
    gtwiz_reset_tx_done_out(0)            => link1.xcvr_tx_ready,
    gtwiz_reset_rx_done_out(0)            => link1.xcvr_rx_ready,

    gtwiz_userdata_tx_in                  => link1.xcvr_txd,
    gtwiz_userdata_rx_out                 => link1.xcvr_rxd,

    rxgearboxslip_in                      => link1.xcvr_rxgearboxslip,
    rxdatavalid_out                       => link1.xcvr_rxdatavalid,
    rxheader_out                          => link1.xcvr_rxheader,
    rxheadervalid_out                     => link1.xcvr_rxheadervalid,
    rxstartofseq_out                      => link1.xcvr_rxstartofseq,
    txheader_in                           => link1.xcvr_txheader,
    txsequence_in                         => link1.xcvr_txsequence,

    gtrefclk00_in(2)                      => link1.clk_ref(2),
    gtrefclk00_in(1)                      => link1.clk_ref(1),
    gtrefclk00_in(0)                      => link1.clk_ref(0),

    gtyrxn_in                             => eci_gt_rx_n_link1,
    gtyrxp_in                             => eci_gt_rx_p_link1,
    gtytxn_out                            => eci_gt_tx_n_link1,
    gtytxp_out                            => eci_gt_tx_p_link1,

    txdiffctrl_in                         => link1.xcvr_txdiffctrl,
    txpostcursor_in                       => link1.xcvr_txpostcursor,
    txprecursor_in                        => link1.xcvr_txprecursor
);

link2.clk_rx <= clk_gt;
link2.clk_tx <= clk_gt;

link2.rxusrclk <= (others => clk);
link2.rxusrclk2 <= (others => clk_gt);
link2.txusrclk <= (others => clk);
link2.txusrclk2 <= (others => clk_gt);

-- Maximum swing
link2.xcvr_txdiffctrl <= (others => '1');
link2.xcvr_txpostcursor <= (others => '0');
link2.xcvr_txprecursor <= (others => '0');

xcvr2 : xcvr_link2
port map (
    gtwiz_userclk_tx_active_in(0) => link2.userclk_tx_active_in,
    gtwiz_userclk_rx_active_in(0) => link2.userclk_rx_active_in,
    rxoutclk_out    => link2.rxoutclk,
    rxusrclk_in     => link2.rxusrclk,
    rxusrclk2_in    => link2.rxusrclk2,
    txoutclk_out    => link2.txoutclk,
    txusrclk_in     => link2.txusrclk,
    txusrclk2_in    => link2.txusrclk2,

    gtwiz_buffbypass_rx_reset_in(0)       => '0',
    gtwiz_buffbypass_rx_start_user_in(0)  => '0',
    gtwiz_buffbypass_tx_reset_in(0)       => '0',
    gtwiz_buffbypass_tx_start_user_in(0)  => '0',

    gtwiz_reset_clk_freerun_in(0)         => clk_io,
    gtwiz_reset_all_in(0)                 => '0',
    gtwiz_reset_tx_pll_and_datapath_in(0) => '0',
    gtwiz_reset_tx_datapath_in(0)         => '0',
    gtwiz_reset_rx_pll_and_datapath_in(0) => '0',
    gtwiz_reset_rx_datapath_in(0)         => link2.xcvr_reset_rx,
    gtwiz_reset_tx_done_out(0)            => link2.xcvr_tx_ready,
    gtwiz_reset_rx_done_out(0)            => link2.xcvr_rx_ready,

    gtwiz_userdata_tx_in                  => link2.xcvr_txd,
    gtwiz_userdata_rx_out                 => link2.xcvr_rxd,

    rxgearboxslip_in                      => link2.xcvr_rxgearboxslip,
    rxdatavalid_out                       => link2.xcvr_rxdatavalid,
    rxheader_out                          => link2.xcvr_rxheader,
    rxheadervalid_out                     => link2.xcvr_rxheadervalid,
    rxstartofseq_out                      => link2.xcvr_rxstartofseq,
    txheader_in                           => link2.xcvr_txheader,
    txsequence_in                         => link2.xcvr_txsequence,

    gtrefclk00_in(2)                      => link2.clk_ref(2),
    gtrefclk00_in(1)                      => link2.clk_ref(1),
    gtrefclk00_in(0)                      => link2.clk_ref(0),

    gtyrxn_in                             => eci_gt_rx_n_link2,
    gtyrxp_in                             => eci_gt_rx_p_link2,
    gtytxn_out                            => eci_gt_tx_n_link2,
    gtytxp_out                            => eci_gt_tx_p_link2,

    txdiffctrl_in                         => link2.xcvr_txdiffctrl,
    txpostcursor_in                       => link2.xcvr_txpostcursor,
    txprecursor_in                        => link2.xcvr_txprecursor
);

-- Reset the receivers if there's no Interlaken word lock
i_realign_rx : process(clk_gt)
begin
    if rising_edge(clk_gt) then
        link1_il.rx_aligned_old <= link1_il.rx_word_lock;
        link2_il.rx_aligned_old <= link2_il.rx_word_lock;
        if realign_counter = 131071 or (link1_il.rx_aligned_old = '1' and link1_il.rx_word_lock = '0') or
            (link2_il.rx_aligned_old = '1' and link2_il.rx_word_lock = '0') then
            if link1_il.rx_word_lock = '0' then
                link1.xcvr_reset_rx <= '1';
            end if;
            if link2_il.rx_word_lock = '0' then
                link2.xcvr_reset_rx <= '1';
            end if;
            realign_counter <= 0;
        elsif link1_il.rx_word_lock = '0' or link2_il.rx_word_lock = '0' then
            realign_counter <= realign_counter + 1;
        else
            realign_counter <= 0;
        end if;
        if link1.xcvr_reset_rx = '1' and link1.xcvr_rx_ready = '0' then
                link1.xcvr_reset_rx <= '0';
        end if;
        if link2.xcvr_reset_rx = '1' and link2.xcvr_rx_ready = '0' then
                link2.xcvr_reset_rx <= '0';
        end if;
    end if;
end process;

link1_il.rx_word_lock <= '1' when link1_il.rx_lane_word_lock = X"fff" else '0';
link1_il.rx_frame_lock <= '1' when link1_il.rx_lane_frame_lock = X"fff" else '0';
link2_il.rx_word_lock <= '1' when link2_il.rx_lane_word_lock = X"fff" else '0';
link2_il.rx_frame_lock <= '1' when link2_il.rx_lane_frame_lock = X"fff" else '0';

-- Link 1
rx_link1_il : il_rx_link_gearbox
generic map (
    LANES     => 12,
    METAFRAME => 2048
)
port map (
    clk_rx          => link1.clk_rx,
    reset           => link1.reset,

    xcvr_rxdata         => link1.xcvr_rxd,
    xcvr_rxdatavalid    => link1.xcvr_rxdatavalid,
    xcvr_rxheader       => link1.xcvr_rxheader,
    xcvr_rxheadervalid  => link1.xcvr_rxheadervalid,
    xcvr_rxgearboxslip  => link1.xcvr_rxgearboxslip,

    output          => link1_il.rx_data,
    output_valid    => link1_il.rx_data_valid,
    ctrl_word_out   => link1_il.rx_ctrl_word,
    link_aligned    => link1_il.rx_aligned,
    lane_word_lock  => link1_il.rx_lane_word_lock,
    lane_frame_lock => link1_il.rx_lane_frame_lock,
    lane_crc32_bad  => link1_il.rx_lane_crc32_bad,
    lane_status     => link1_il.rx_lane_status,
    total_skew      => link1_il.rx_total_skew
);

-- ECI RX Link
rx_eci_blk_link1 : eci_rx_blk
generic map (
    LANES => 12
)
port map (
    clk_rx          => link1.clk_rx,
    clk_blk         => clk,
    link_aligned    => link1_il.rx_aligned,
    link_data       => link1_il.rx_data,
    link_data_valid => link1_il.rx_data_valid,
    ctrl_word       => link1_il.rx_ctrl_word,
    block_out       => link1_eci.rx_block,
    block_out_valid => link1_eci.rx_block_valid,
    crc_match_out   => link1_eci.rx_block_crc_match
);

link1_eci_block_out         <= link1_eci.rx_block;
link1_eci_block_out_valid   <= link1_eci.rx_block_valid;
link1_eci_crc_match_out     <= link1_eci.rx_block_crc_match;

i_link1_eci : eci_link
port map (
    clk             => clk,
    reset           => reset,
    link_up         => link1_eci.link_up,
    link_state      => link1_eci.link_state,
    blk_rx_data     => link1_eci.rx_block,
    blk_rx_valid    => link1_eci.rx_block_valid,
    blk_crc_match   => link1_eci.rx_block_crc_match,
    blk_tx_data     => link1_eci.tx_block,
    blk_tx_ready    => link1_eci.tx_block_ready,

    mib_data        => link1_in_data,
    mib_vc_no       => link1_in_vc_no,
    mib_we2         => link1_in_we2,
    mib_we3         => link1_in_we3,
    mib_we4         => link1_in_we4,
    mib_we5         => link1_in_we5,
    mib_valid       => link1_in_valid,
    mib_credit_return       => link1_in_credit_return,

    -------------------------- MOB VCs Inputs ----------------------------//
    mob_hi_data             => link1_out_hi_vc.data,
    mob_hi_vc_no            => link1_out_hi_vc.vc_no,
    mob_hi_size             => link1_out_hi_vc.size,
    mob_hi_valid            => link1_out_hi_vc.valid,
    mob_hi_ready            => link1_out_hi_vc_ready,
    mob_lo_data             => link1_out_lo_vc.data(0),
    mob_lo_vc_no            => link1_out_lo_vc.vc_no,
    mob_lo_valid            => link1_out_lo_vc.valid,
    mob_lo_ready            => link1_out_lo_vc_ready,
    mob_credit_return       => link1_out_credit_return
);

tx_eci_blk_link1 : eci_tx_blk
generic map (
    LANES => 12
)
port map (
    clk_tx          => link1.clk_tx,
    clk_blk         => clk,
    block_in        => link1_eci.tx_block,
    block_in_ready  => link1_eci.tx_block_ready,
    link_data       => link1_il.tx_data,
    link_data_ready => link1_il.tx_data_ready,
    ctrl_word_out   => link1_il.tx_ctrl_word
);

tx_link1_il : il_tx_link_gearbox
generic map (
    LANES     => 12,
    METAFRAME => 2048
)
port map (
    clk_tx       => link1.clk_tx,
    reset        => link1.reset,
    input        => link1_il.tx_data,
    input_ready  => link1_il.tx_data_ready,
    ctrl_word_in => link1_il.tx_ctrl_word,
    xcvr_txdata  => link1.xcvr_txd,
    xcvr_txheader       => link1.xcvr_txheader,
    xcvr_txsequence     => link1.xcvr_txsequence
);

-- Link 2
rx_link2_il : il_rx_link_gearbox
generic map (
    LANES     => 12,
    METAFRAME => 2048
)
port map (
    clk_rx          => link2.clk_rx,
    reset           => link2.reset,

    xcvr_rxdata         => link2.xcvr_rxd,
    xcvr_rxdatavalid    => link2.xcvr_rxdatavalid,
    xcvr_rxheader       => link2.xcvr_rxheader,
    xcvr_rxheadervalid  => link2.xcvr_rxheadervalid,
    xcvr_rxgearboxslip  => link2.xcvr_rxgearboxslip,

    output          => link2_il.rx_data,
    output_valid    => link2_il.rx_data_valid,
    ctrl_word_out   => link2_il.rx_ctrl_word,
    link_aligned    => link2_il.rx_aligned,
    lane_word_lock  => link2_il.rx_lane_word_lock,
    lane_frame_lock => link2_il.rx_lane_frame_lock,
    lane_crc32_bad  => link2_il.rx_lane_crc32_bad,
    lane_status     => link2_il.rx_lane_status,
    total_skew      => link2_il.rx_total_skew
);

rx_eci_blk_link2 : eci_rx_blk
generic map (
    LANES => 12
)
port map (
    clk_rx          => link2.clk_rx,
    clk_blk         => clk,
    link_aligned    => link2_il.rx_aligned,
    link_data       => link2_il.rx_data,
    link_data_valid => link2_il.rx_data_valid,
    ctrl_word       => link2_il.rx_ctrl_word,
    block_out       => link2_eci.rx_block,
    block_out_valid => link2_eci.rx_block_valid,
    crc_match_out   => link2_eci.rx_block_crc_match
);

link2_eci_block_out         <= link2_eci.rx_block;
link2_eci_block_out_valid   <= link2_eci.rx_block_valid;
link2_eci_crc_match_out     <= link2_eci.rx_block_crc_match;

i_link2_eci : eci_link
port map (
    clk             => clk,
    reset           => reset,
    link_up         => link2_eci.link_up,
    link_state      => link2_eci.link_state,
    blk_rx_data     => link2_eci.rx_block,
    blk_rx_valid    => link2_eci.rx_block_valid,
    blk_crc_match   => link2_eci.rx_block_crc_match,
    blk_tx_data     => link2_eci.tx_block,
    blk_tx_ready    => link2_eci.tx_block_ready,

    mib_data        => link2_in_data,
    mib_vc_no       => link2_in_vc_no,
    mib_we2         => link2_in_we2,
    mib_we3         => link2_in_we3,
    mib_we4         => link2_in_we4,
    mib_we5         => link2_in_we5,
    mib_valid       => link2_in_valid,
    mib_credit_return       => link2_in_credit_return,

    -------------------------- MOB VCs Inputs ----------------------------//
    mob_hi_data             => link2_out_hi_vc.data,
    mob_hi_vc_no            => link2_out_hi_vc.vc_no,
    mob_hi_size             => link2_out_hi_vc.size,
    mob_hi_valid            => link2_out_hi_vc.valid,
    mob_hi_ready            => link2_out_hi_vc_ready,
    mob_lo_data             => link2_out_lo_vc.data(0),
    mob_lo_vc_no            => link2_out_lo_vc.vc_no,
    mob_lo_valid            => link2_out_lo_vc.valid,
    mob_lo_ready            => link2_out_lo_vc_ready,
    mob_credit_return       => link2_out_credit_return
);

tx_eci_blk_link2 : eci_tx_blk
generic map (
    LANES => 12
)
port map (
    clk_tx          => link2.clk_tx,
    clk_blk         => clk,
    block_in        => link2_eci.tx_block,
    block_in_ready  => link2_eci.tx_block_ready,
    link_data       => link2_il.tx_data,
    link_data_ready => link2_il.tx_data_ready,
    ctrl_word_out   => link2_il.tx_ctrl_word
);

tx_link2_il : il_tx_link_gearbox
generic map (
    LANES     => 12,
    METAFRAME => 2048
)
port map (
    clk_tx       => link2.clk_tx,
    reset        => link2.reset,
    input        => link2_il.tx_data,
    input_ready  => link2_il.tx_data_ready,
    ctrl_word_in => link2_il.tx_ctrl_word,
    xcvr_txdata  => link2.xcvr_txd,
    xcvr_txheader       => link2.xcvr_txheader,
    xcvr_txsequence     => link2.xcvr_txsequence
);

gen_edge_ila : if EDGE_ILA_PRESENT generate
begin
i_ila_eci_edge : ila_eci_edge
port map (
    clk         => clk,

    probe0(0)   => link1_eci.link_up,
    probe1      => link1_eci.link_state,
    probe2(0)   => link1_eci.link_state_change,

    probe3(0)   => link1_eci.rx_block_valid,
    probe4(0)   => link1_eci.rx_has_data_payload,
    probe5(0)   => link1_eci.rx_has_data_payload_filtered,
    probe6      => link1_eci.rx_block_header,
    probe7      => link1_eci.rx_block_word1,
    probe8      => link1_eci.rx_block_word2,
    probe9      => link1_eci.rx_block_word3,
    probe10     => link1_eci.rx_block_word4,
    probe11     => link1_eci.rx_block_word5,
    probe12     => link1_eci.rx_block_word6,
    probe13     => link1_eci.rx_block_word7,
    probe14(0)  => link1_eci.rx_block_crc_match,


    probe15(0)  => link1_eci.tx_block_ready,
    probe16(0)  => link1_eci.tx_has_data_payload,
    probe17(0)  => link1_eci.tx_has_data_payload_filtered,
    probe18     => link1_eci.tx_block_header,
    probe19     => link1_eci.tx_block_word1,
    probe20     => link1_eci.tx_block_word2,
    probe21     => link1_eci.tx_block_word3,
    probe22     => link1_eci.tx_block_word4,
    probe23     => link1_eci.tx_block_word5,
    probe24     => link1_eci.tx_block_word6,
    probe25     => link1_eci.tx_block_word7,

    probe26(0)  => link2_eci.link_up,
    probe27     => link2_eci.link_state,
    probe28(0)  => link2_eci.link_state_change,

    probe29(0)  => link2_eci.rx_block_valid,
    probe30(0)  => link2_eci.rx_has_data_payload,
    probe31(0)  => link2_eci.rx_has_data_payload_filtered,
    probe32     => link2_eci.rx_block_header,
    probe33     => link2_eci.rx_block_word1,
    probe34     => link2_eci.rx_block_word2,
    probe35     => link2_eci.rx_block_word3,
    probe36     => link2_eci.rx_block_word4,
    probe37     => link2_eci.rx_block_word5,
    probe38     => link2_eci.rx_block_word6,
    probe39     => link2_eci.rx_block_word7,
    probe40(0)  => link2_eci.rx_block_crc_match,


    probe41(0)  => link2_eci.tx_block_ready,
    probe42(0)  => link2_eci.tx_has_data_payload,
    probe43(0)  => link2_eci.tx_has_data_payload_filtered,
    probe44     => link2_eci.tx_block_header,
    probe45     => link2_eci.tx_block_word1,
    probe46     => link2_eci.tx_block_word2,
    probe47     => link2_eci.tx_block_word3,
    probe48     => link2_eci.tx_block_word4,
    probe49     => link2_eci.tx_block_word5,
    probe50     => link2_eci.tx_block_word6,
    probe51     => link2_eci.tx_block_word7
);
end generate gen_edge_ila;

link_up <= link1_eci.link_up and link2_eci.link_up;
link1_link_up <= link1_eci.link_up;
link2_link_up <= link2_eci.link_up;
realign_counter_int <= to_unsigned(realign_counter, 28);

-- Check if there's GSYNC, GSDN or GINV only
gen_gsync_check : for i in 0 to 6 generate
    link1_eci.rx_has_gsync(i) <= '1' when link1_eci.rx_block(27+4*i downto 25+4*i) = "011" and (link1_eci.rx_block(127+64*i downto 123+64*i) = "11000" or link1_eci.rx_block(127+64*i downto 123+64*i) = "10100") else '0';
    link2_eci.rx_has_gsync(i) <= '1' when link2_eci.rx_block(27+4*i downto 25+4*i) = "011" and (link2_eci.rx_block(127+64*i downto 123+64*i) = "11000" or link2_eci.rx_block(127+64*i downto 123+64*i) = "10100") else '0';
    link1_eci.Tx_has_gsync(i) <= '1' when link1_eci.tx_block(27+4*i downto 25+4*i) = "101" and link1_eci.tx_block(127+64*i downto 123+64*i) = "11000" else '0';
    link2_eci.Tx_has_gsync(i) <= '1' when link2_eci.tx_block(27+4*i downto 25+4*i) = "101" and link2_eci.tx_block(127+64*i downto 123+64*i) = "11000" else '0';
end generate gen_gsync_check;

link1_eci.rx_block_word1 <= link1_eci.rx_block(511 downto 448);
link1_eci.rx_block_word2 <= link1_eci.rx_block(447 downto 384);
link1_eci.rx_block_word3 <= link1_eci.rx_block(383 downto 320);
link1_eci.rx_block_word4 <= link1_eci.rx_block(319 downto 256);
link1_eci.rx_block_word5 <= link1_eci.rx_block(255 downto 192);
link1_eci.rx_block_word6 <= link1_eci.rx_block(191 downto 128);
link1_eci.rx_block_word7 <= link1_eci.rx_block(127 downto 64);
link1_eci.rx_block_header <= link1_eci.rx_block(63 downto 24);
link1_eci.rx_block_crc <= link1_eci.rx_block(23 downto 0);
link1_eci.tx_block_word1 <= link1_eci.tx_block(511 downto 448);
link1_eci.tx_block_word2 <= link1_eci.tx_block(447 downto 384);
link1_eci.tx_block_word3 <= link1_eci.tx_block(383 downto 320);
link1_eci.tx_block_word4 <= link1_eci.tx_block(319 downto 256);
link1_eci.tx_block_word5 <= link1_eci.tx_block(255 downto 192);
link1_eci.tx_block_word6 <= link1_eci.tx_block(191 downto 128);
link1_eci.tx_block_word7 <= link1_eci.tx_block(127 downto 64);
link1_eci.tx_block_header <= link1_eci.tx_block(63 downto 24);

link2_eci.rx_block_word1 <= link2_eci.rx_block(511 downto 448);
link2_eci.rx_block_word2 <= link2_eci.rx_block(447 downto 384);
link2_eci.rx_block_word3 <= link2_eci.rx_block(383 downto 320);
link2_eci.rx_block_word4 <= link2_eci.rx_block(319 downto 256);
link2_eci.rx_block_word5 <= link2_eci.rx_block(255 downto 192);
link2_eci.rx_block_word6 <= link2_eci.rx_block(191 downto 128);
link2_eci.rx_block_word7 <= link2_eci.rx_block(127 downto 64);
link2_eci.rx_block_header <= link2_eci.rx_block(63 downto 24);
link2_eci.rx_block_crc <= link2_eci.rx_block(23 downto 0);
link2_eci.tx_block_word1 <= link2_eci.tx_block(511 downto 448);
link2_eci.tx_block_word2 <= link2_eci.tx_block(447 downto 384);
link2_eci.tx_block_word3 <= link2_eci.tx_block(383 downto 320);
link2_eci.tx_block_word4 <= link2_eci.tx_block(319 downto 256);
link2_eci.tx_block_word5 <= link2_eci.tx_block(255 downto 192);
link2_eci.tx_block_word6 <= link2_eci.tx_block(191 downto 128);
link2_eci.tx_block_word7 <= link2_eci.tx_block(127 downto 64);
link2_eci.tx_block_header <= link2_eci.tx_block(63 downto 24);

link1_eci.rx_has_data_payload <= '1' when link1_eci.rx_block(63 downto 62) = "10" and link1_eci.rx_block_valid = '1' and link1_eci.rx_block(51 downto 24) /= x"fffffff" else '0';
link2_eci.rx_has_data_payload <= '1' when link2_eci.rx_block(63 downto 62) = "10" and link2_eci.rx_block_valid = '1' and link2_eci.rx_block(51 downto 24) /= x"fffffff" else '0';
link1_eci.rx_has_data_payload_filtered <= '1' when link1_eci.rx_has_data_payload = '1' and or_reduce(link1_eci.rx_has_gsync) = '0' else '0';
link2_eci.rx_has_data_payload_filtered <= '1' when link2_eci.rx_has_data_payload = '1' and or_reduce(link2_eci.rx_has_gsync) = '0' else '0';

link1_eci.tx_has_data_payload <= '1' when link1_eci.tx_block(63 downto 62) = "10" and link1_eci.tx_block_ready = '1' and link1_eci.tx_block(51 downto 24) /= x"fffffff" else '0';
link2_eci.tx_has_data_payload <= '1' when link2_eci.tx_block(63 downto 62) = "10" and link2_eci.tx_block_ready = '1' and link2_eci.tx_block(51 downto 24) /= x"fffffff" else '0';
link1_eci.tx_has_data_payload_filtered <= '1' when link1_eci.tx_has_data_payload = '1' and or_reduce(link1_eci.tx_has_gsync) = '0' else '0';
link2_eci.tx_has_data_payload_filtered <= '1' when link2_eci.tx_has_data_payload = '1' and or_reduce(link2_eci.tx_has_gsync) = '0' else '0';

i_link_state_counter : process(clk)
begin
    if rising_edge(clk) then
        if (link1_eci.link_state /= link1_eci.old_link_state) then
            link1_eci.link_state_change <= '1';
            link1_eci.old_link_state <= link1_eci.link_state;
        else
            link1_eci.link_state_change <= '0';
        end if;
        if (link2_eci.link_state /= link2_eci.old_link_state) then
            link2_eci.link_state_change <= '1';
            link2_eci.old_link_state <= link2_eci.link_state;
        else
            link2_eci.link_state_change <= '0';
        end if;
    end if;
end process;

end Behavioral;
