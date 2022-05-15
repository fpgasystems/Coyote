library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_top is
generic (
    NUM_LANES : integer := 12;
    LANES_GRPS: integer := 3
    );
port (
    -- 156.25MHz transceiver reference clocks
    ccpi_clk_p : in std_logic_vector(5 downto 0);
    ccpi_clk_n : in std_logic_vector(5 downto 0);

    -- RX differential pairs
    ccpi_rxn, ccpi_rxp : in std_logic_vector(NUM_LANES-1 downto 0);

    -- TX differential pairs
    ccpi_txn, ccpi_txp : out std_logic_vector(NUM_LANES-1 downto 0);
    
    --
    -- Coyote
    --
    clk_axi : out std_logic; -- 322 MHz
    clk_io : in std_logic; -- 50 MHz

    resetn_axi : out std_logic; -- reset

    -- Control
    axil_ctrl_awaddr  : out std_logic_vector(35 downto 0);
    axil_ctrl_awvalid : out std_logic;
    axil_ctrl_awready : in  std_logic;
    axil_ctrl_wdata   : out  std_logic_vector(63 downto 0);
    axil_ctrl_wstrb   : out  std_logic_vector(7 downto 0);
    axil_ctrl_wvalid  : out  std_logic;
    axil_ctrl_wready  : in  std_logic;
    axil_ctrl_bresp   : in  std_logic_vector(1 downto 0);
    axil_ctrl_bvalid  : in  std_logic;
    axil_ctrl_bready  : out std_logic;
    axil_ctrl_araddr  : out std_logic_vector(35 downto 0);
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
end eci_top;

architecture behavioural of eci_top is

component vio_xcvr is
port (
    clk : in std_logic;
    probe_in0 : in std_logic_vector(0 downto 0);
    probe_in1 : in std_logic_vector(2 downto 0);
    probe_in2 : in std_logic_vector(0 downto 0);
    probe_in3 : in std_logic_vector(0 downto 0);
    probe_in4 : in std_logic_vector(0 downto 0);
    probe_in5 : in std_logic_vector(2 downto 0);
    probe_in6 : in std_logic_vector(0 downto 0);
    probe_in7 : in std_logic_vector(0 downto 0);
    probe_out0 : out std_logic_vector(0 downto 0);
    probe_out1 : out std_logic_vector(0 downto 0)
);
end component;

component xcvr_link1
port (
    gtwiz_userclk_tx_active_in : in std_logic_vector(0 downto 0);
    gtwiz_userclk_rx_active_in : in std_logic_vector(0 downto 0);
    rxoutclk_out : out std_logic_vector(NUM_LANES - 1 downto 0);
    rxusrclk_in : in std_logic_vector(NUM_LANES - 1 downto 0);
    rxusrclk2_in : in std_logic_vector(NUM_LANES - 1 downto 0);
    txoutclk_out : out std_logic_vector(NUM_LANES - 1 downto 0);
    txusrclk_in : in std_logic_vector(NUM_LANES - 1 downto 0);
    txusrclk2_in : in std_logic_vector(NUM_LANES - 1 downto 0);

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
    gtwiz_userdata_tx_in  :  in std_logic_vector(NUM_LANES*64-1 downto 0);
    -- Received data, synchronised to rx_usrclk2
    gtwiz_userdata_rx_out : out std_logic_vector(NUM_LANES*64-1 downto 0);

    -- The 156.25MHz reference clocks
    gtrefclk00_in : in std_logic_vector(LANES_GRPS-1 downto 0);

    -- The recovered (10GHz) clocks, and the buffered reference clock.
    qpll0outclk_out    : out std_logic_vector(LANES_GRPS-1 downto 0);
    qpll0outrefclk_out : out std_logic_vector(LANES_GRPS-1 downto 0);

    -- RX differential pairs
    gtyrxn_in : in std_logic_vector(NUM_LANES-1 downto 0);
    gtyrxp_in : in std_logic_vector(NUM_LANES-1 downto 0);

    -- TX differential pair
    gtytxn_out : out std_logic_vector(NUM_LANES-1 downto 0);
    gtytxp_out : out std_logic_vector(NUM_LANES-1 downto 0);

    -- Gearbox
    rxgearboxslip_in :  in std_logic_vector(NUM_LANES-1 downto 0);
    rxdatavalid_out :   out std_logic_vector(2*NUM_LANES-1 downto 0);
    rxheader_out :      out std_logic_vector(6*NUM_LANES-1 downto 0);
    rxheadervalid_out : out std_logic_vector(2*NUM_LANES-1 downto 0);
    rxstartofseq_out :  out std_logic_vector(2*NUM_LANES-1 downto 0);
    txheader_in       : in std_logic_vector(6*NUM_LANES-1 downto 0);
    txsequence_in     : in std_logic_vector(7*NUM_LANES-1 downto 0);

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
    rxpmaresetdone_out    : out std_logic_vector(NUM_LANES-1 downto 0);
    txpmaresetdone_out    : out std_logic_vector(NUM_LANES-1 downto 0);
    txprgdivresetdone_out : out std_logic_vector(NUM_LANES-1 downto 0);
    gtpowergood_out       : out std_logic_vector(NUM_LANES-1 downto 0);

    -- TX driver control
    txdiffctrl_in   : in std_logic_vector(5*NUM_LANES-1 downto 0);
    txpostcursor_in : in std_logic_vector(5*NUM_LANES-1 downto 0);
    txprecursor_in  : in std_logic_vector(5*NUM_LANES-1 downto 0)
);
end component;

-- BUILDDEP il_rx_link
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

-- BUILDDEP il_tx_link
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


-- BUILDDEP ccpi_rx_blk
component ccpi_rx_blk_sync is
generic (
    LANES : integer := 12
);
port (
    clk_rx : in std_logic;
    reset  : in std_logic;

    clk_blk   : in std_logic;
    reset_blk : out std_logic;

    link_aligned : in std_logic;

    link_data       : in std_logic_vector(64*NUM_LANES-1 downto 0);
    link_data_valid : in std_logic;
    ctrl_word       : in std_logic_vector( NUM_LANES-1 downto 0);

    block_out       : out std_logic_vector(511 downto 0);
    block_out_valid : out std_logic;
    crc_match_out   : out std_logic
);
end component;

-- BUILDDEP ccpi_tx_blk
component ccpi_tx_blk_sync is
generic (
    LANES : integer := 12
);
port (
    clk_tx : in std_logic;
    reset  : in std_logic;

    clk_blk   : in std_logic;
    reset_blk : in std_logic;

    block_in       :  in std_logic_vector(511 downto 0);
    block_in_ready : out std_logic;

    link_data       : out std_logic_vector(LANES*64-1 downto 0);
    link_data_ready :  in std_logic;
    ctrl_word_out   : out std_logic_vector( LANES-1 downto 0)
);
end component;

component ccpi_blk is
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
   port(
    clk    : in std_logic;
    reset  : in std_logic;

    blk_rx_data   : in std_logic_vector(511 downto 0);
    blk_rx_valid  : in std_logic;
    blk_crc_match : in std_logic;
    blk_tx_data   : out std_logic_vector(511 downto 0);
    blk_tx_ready  : in std_logic;

    mib_vc11_co       : out std_logic_vector(447 downto 0);
    mib_vc11_co_valid : out std_logic;
    mib_vc11_co_word_enable  : out std_logic_vector(6 downto 0);
    mib_vc11_co_ready : in  std_logic;
    mib_vc10_co       : out std_logic_vector(447 downto 0);
    mib_vc10_co_valid : out std_logic;
    mib_vc10_co_word_enable  : out std_logic_vector(6 downto 0);
    mib_vc10_co_ready : in  std_logic;
    mib_vc9_co        : out std_logic_vector(447 downto 0);
    mib_vc9_co_valid  : out std_logic;
    mib_vc9_co_word_enable   : out std_logic_vector(6 downto 0);
    mib_vc9_co_ready  : in  std_logic;
    mib_vc8_co        : out std_logic_vector(447 downto 0);
    mib_vc8_co_valid  : out std_logic;
    mib_vc8_co_word_enable   : out std_logic_vector(6 downto 0);
    mib_vc8_co_ready  : in  std_logic;
    mib_vc7_co        : out std_logic_vector(447 downto 0);
    mib_vc7_co_valid  : out std_logic;
    mib_vc7_co_word_enable   : out std_logic_vector(6 downto 0);
    mib_vc7_co_ready  : in  std_logic;
    mib_vc6_co        : out std_logic_vector(447 downto 0);
    mib_vc6_co_valid  : out std_logic;
    mib_vc6_co_word_enable   : out std_logic_vector(6 downto 0);
    mib_vc6_co_ready  : in  std_logic;
    -- VC 5 - 2
    mib_vc5_cd        : out std_logic_vector(447 downto 0);
    mib_vc5_cd_valid  : out std_logic;
    mib_vc5_cd_word_enable   : out std_logic_vector(6 downto 0);
    mib_vc5_cd_ready  : in  std_logic;
    mib_vc4_cd        : out std_logic_vector(447 downto 0);
    mib_vc4_cd_valid  : out std_logic;
    mib_vc4_cd_word_enable   : out std_logic_vector(6 downto 0);
    mib_vc4_cd_ready  : in  std_logic;
    mib_vc3_cd        : out std_logic_vector(447 downto 0);
    mib_vc3_cd_valid  : out std_logic;
    mib_vc3_cd_word_enable   : out std_logic_vector(6 downto 0);
    mib_vc3_cd_ready  : in  std_logic;
    mib_vc2_cd        : out std_logic_vector(447 downto 0);
    mib_vc2_cd_valid  : out std_logic;
    mib_vc2_cd_word_enable   : out std_logic_vector(6 downto 0);
    mib_vc2_cd_ready  : in  std_logic;
    -- MCD VC13
    mib_vc_mcd        : out std_logic_vector(63 downto 0);
    mib_vc_mcd_valid  : out std_logic;
    mib_vc_mcd_ready  : in  std_logic;

    mib_vc0_io         : out WORDS(6 downto 0);
    mib_vc0_io_valid   : out std_logic;
    mib_vc0_io_word_enable    : out std_logic_vector(6 downto 0);
    mib_vc0_io_ready   : in std_logic;

    mib_vc1_io         : out WORDS(6 downto 0);
    mib_vc1_io_valid   : out std_logic;
    mib_vc1_io_word_enable    : out std_logic_vector(6 downto 0);
    mib_vc1_io_ready   : in std_logic;

    -------------------------- MOB VCs Inputs ----------------------------//
    -- VC 11 - 6
    mob_vc11_co       : in  std_logic_vector(63 downto 0);
    mob_vc11_co_valid : in  std_logic;
    mob_vc11_co_size  : in  std_logic_vector(4 downto 0);
    mob_vc11_co_ready : out std_logic;
    mob_vc10_co       : in  std_logic_vector(63 downto 0);
    mob_vc10_co_valid : in  std_logic;
    mob_vc10_co_size  : in  std_logic_vector(4 downto 0);
    mob_vc10_co_ready : out std_logic;
    mob_vc9_co        : in  std_logic_vector(63 downto 0);
    mob_vc9_co_valid  : in  std_logic;
    mob_vc9_co_size   : in  std_logic_vector(4 downto 0);
    mob_vc9_co_ready  : out std_logic;
    mob_vc8_co        : in  std_logic_vector(63 downto 0);
    mob_vc8_co_valid  : in  std_logic;
    mob_vc8_co_size   : in  std_logic_vector(4 downto 0);
    mob_vc8_co_ready  : out std_logic;
    mob_vc7_co        : in  std_logic_vector(63 downto 0);
    mob_vc7_co_valid  : in  std_logic;
    mob_vc7_co_size   : in  std_logic_vector(4 downto 0);
    mob_vc7_co_ready  : out std_logic;
    mob_vc6_co        : in  std_logic_vector(63 downto 0);
    mob_vc6_co_valid  : in  std_logic;
    mob_vc6_co_size   : in  std_logic_vector(4 downto 0);
    mob_vc6_co_ready  : out std_logic;
    -- VC 5 - 2
    mob_vc5_cd        : in  std_logic_vector(1087 downto 0);
    mob_vc5_cd_valid  : in  std_logic;
    mob_vc5_cd_size   : in  std_logic_vector(4 downto 0);
    mob_vc5_cd_ready  : out std_logic;
    mob_vc4_cd        : in  std_logic_vector(1087 downto 0);
    mob_vc4_cd_valid  : in  std_logic;
    mob_vc4_cd_size   : in  std_logic_vector(4 downto 0);
    mob_vc4_cd_ready  : out std_logic;
    mob_vc3_cd        : in  std_logic_vector(1087 downto 0);
    mob_vc3_cd_valid  : in  std_logic;
    mob_vc3_cd_size   : in  std_logic_vector(4 downto 0);
    mob_vc3_cd_ready  : out std_logic;
    mob_vc2_cd        : in  std_logic_vector(1087 downto 0);
    mob_vc2_cd_valid  : in  std_logic;
    mob_vc2_cd_size   : in  std_logic_vector(4 downto 0);
    mob_vc2_cd_ready  : out std_logic;
    -- MCD VC13
    mob_vc_mcd        : in  std_logic_vector(63 downto 0);
    mob_vc_mcd_valid  : in  std_logic;
    mob_vc_mcd_ready  : out std_logic;

    mob_vc0_io         : in WORDS(1 downto 0);
    mob_vc0_io_valid   : in std_logic;
    mob_vc0_io_size    : in std_logic_vector(2 downto 0);
    mob_vc0_io_ready   : out std_logic;

    mob_vc1_io         : in WORDS(1 downto 0);
    mob_vc1_io_valid   : in std_logic;
    mob_vc1_io_size    : in std_logic_vector(2 downto 0);
    mob_vc1_io_ready   : out std_logic
);
end component;

component eci_io_bridge is
generic (
    SECOND_LINK_ACTIVE : integer
);
port (
    clk : in std_logic;
    reset : in std_logic;

    -- Link 1 interface
    link1_mib_vc_mcd        : in std_logic_vector(63 downto 0);
    link1_mib_vc_mcd_valid  : in std_logic;
    link1_mib_vc_mcd_ready  : out  std_logic;

    link1_mib_vc0_io         : in WORDS(6 downto 0);
    link1_mib_vc0_io_valid   : in std_logic;
    link1_mib_vc0_io_word_enable    : in std_logic_vector(6 downto 0);
    link1_mib_vc0_io_ready   : out std_logic;

    link1_mib_vc1_io         : in WORDS(6 downto 0);
    link1_mib_vc1_io_valid   : in std_logic;
    link1_mib_vc1_io_word_enable    : in std_logic_vector(6 downto 0);
    link1_mib_vc1_io_ready   : out std_logic;

    link1_mob_vc_mcd        : out std_logic_vector(63 downto 0);
    link1_mob_vc_mcd_valid  : buffer std_logic;
    link1_mob_vc_mcd_ready  : in std_logic;

    link1_mob_vc0_io         : out WORDS(1 downto 0);
    link1_mob_vc0_io_valid   : out std_logic;
    link1_mob_vc0_io_size    : out std_logic_vector(2 downto 0);
    link1_mob_vc0_io_ready   : in std_logic;

    link1_mob_vc1_io         : out WORDS(1 downto 0);
    link1_mob_vc1_io_valid   : buffer std_logic;
    link1_mob_vc1_io_size    : out std_logic_vector(2 downto 0);
    link1_mob_vc1_io_ready   : in std_logic;

    link2_mib_vc_mcd        : in std_logic_vector(63 downto 0);
    link2_mib_vc_mcd_valid  : in std_logic;
    link2_mib_vc_mcd_ready  : out  std_logic;

    -- Link 2 interface
    link2_mib_vc0_io         : in WORDS(6 downto 0);
    link2_mib_vc0_io_valid   : in std_logic;
    link2_mib_vc0_io_word_enable    : in std_logic_vector(6 downto 0);
    link2_mib_vc0_io_ready   : out std_logic;

    link2_mib_vc1_io         : in WORDS(6 downto 0);
    link2_mib_vc1_io_valid   : in std_logic;
    link2_mib_vc1_io_word_enable    : in std_logic_vector(6 downto 0);
    link2_mib_vc1_io_ready   : out std_logic;

    link2_mob_vc_mcd        : out std_logic_vector(63 downto 0);
    link2_mob_vc_mcd_valid  : buffer  std_logic;
    link2_mob_vc_mcd_ready  : in std_logic;

    link2_mob_vc0_io         : out WORDS(1 downto 0);
    link2_mob_vc0_io_valid   : out std_logic;
    link2_mob_vc0_io_size    : out std_logic_vector(2 downto 0);
    link2_mob_vc0_io_ready   : in std_logic;

    link2_mob_vc1_io         : out WORDS(1 downto 0);
    link2_mob_vc1_io_valid   : buffer std_logic;
    link2_mob_vc1_io_size    : out std_logic_vector(2 downto 0);
    link2_mob_vc1_io_ready   : in std_logic;

    -- AXI Lite master interface IO addr space
    m_io_axil_awaddr  : out std_logic_vector(39 downto 0);
    m_io_axil_awvalid : buffer std_logic;
    m_io_axil_awready : in  std_logic;

    m_io_axil_wdata   : out std_logic_vector(63 downto 0);
    m_io_axil_wstrb   : out std_logic_vector(7 downto 0);
    m_io_axil_wvalid  : buffer std_logic;
    m_io_axil_wready  : in  std_logic;

    m_io_axil_bresp   : in  std_logic_vector(1 downto 0);
    m_io_axil_bvalid  : in  std_logic;
    m_io_axil_bready  : buffer std_logic;

    m_io_axil_araddr  : out std_logic_vector(39 downto 0);
    m_io_axil_arvalid : buffer std_logic;
    m_io_axil_arready : in  std_logic;

    m_io_axil_rdata   : in std_logic_vector(63 downto 0);
    m_io_axil_rresp   : in std_logic_vector(1 downto 0);
    m_io_axil_rvalid  : in std_logic;
    m_io_axil_rready  : buffer std_logic
);
end component;

-- Module takes data from VCs, deserializes it and generates ECI packets
-- corresponding to events in the VCs
component vc_eci_pkt_router is
port (
    clk   : in std_logic;
    reset : in std_logic;

    -- Incoming CPU to FPGA events (MIB VCs) c_ -> CPU initated events
    -- VC11 to VC2 (VC1, VC0) are IO VCs not handled here
    -- Incoming response without data VC 11,10
    c11_vc_pkt_i       : in  std_logic_vector(447 downto 0);
    c11_vc_pkt_word_enable_i  : in  std_logic_vector(  6 downto 0);
    c11_vc_pkt_valid_i : in  std_logic;
    c11_vc_pkt_ready_o : out std_logic;

    c10_vc_pkt_i       : in  std_logic_vector(447 downto 0);
    c10_vc_pkt_word_enable_i  : in  std_logic_vector(  6 downto 0);
    c10_vc_pkt_valid_i : in  std_logic;
    c10_vc_pkt_ready_o : out std_logic;

    -- Incoming Forwards VC 9,8
    -- Forwards are command only no data, currently not connected
    c9_vc_pkt_i       : in  std_logic_vector(447 downto 0);
    c9_vc_pkt_word_enable_i  : in  std_logic_vector(  6 downto 0);
    c9_vc_pkt_valid_i : in  std_logic;
    c9_vc_pkt_ready_o : out std_logic;

    c8_vc_pkt_i       : in  std_logic_vector(447 downto 0);
    c8_vc_pkt_word_enable_i  : in  std_logic_vector(  6 downto 0);
    c8_vc_pkt_valid_i : in  std_logic;
    c8_vc_pkt_ready_o : out std_logic;

   -- Incoming requests without data VC 7,6
    c7_vc_pkt_i       : in  std_logic_vector(447 downto 0);
    c7_vc_pkt_word_enable_i  : in  std_logic_vector(  6 downto 0);
    c7_vc_pkt_valid_i : in  std_logic;
    c7_vc_pkt_ready_o : out std_logic;

    c6_vc_pkt_i       : in  std_logic_vector(447 downto 0);
    c6_vc_pkt_word_enable_i  : in  std_logic_vector(  6 downto 0);
    c6_vc_pkt_valid_i : in  std_logic;
    c6_vc_pkt_ready_o : out std_logic;

    -- Incoming resoponse with data VC 5,4
    c5_vc_pkt_i       : in  std_logic_vector(447 downto 0);
    c5_vc_pkt_word_enable_i  : in  std_logic_vector(  6 downto 0);
    c5_vc_pkt_valid_i : in  std_logic;
    c5_vc_pkt_ready_o : out std_logic;

    c4_vc_pkt_i       : in  std_logic_vector(447 downto 0);
    c4_vc_pkt_word_enable_i  : in  std_logic_vector(  6 downto 0);
    c4_vc_pkt_valid_i : in  std_logic;
    c4_vc_pkt_ready_o : out std_logic;

    -- Incoming request with data VC 3,2
    c3_vc_pkt_i       : in  std_logic_vector(447 downto 0);
    c3_vc_pkt_word_enable_i  : in  std_logic_vector(  6 downto 0);
    c3_vc_pkt_valid_i : in  std_logic;
    c3_vc_pkt_ready_o : out std_logic;

    c2_vc_pkt_i       : in  std_logic_vector(447 downto 0);
    c2_vc_pkt_word_enable_i  : in  std_logic_vector(  6 downto 0);
    c2_vc_pkt_valid_i : in  std_logic;
    c2_vc_pkt_ready_o : out std_logic;

    -- ECI packets corresponding to the VCs holding CPU initiated events
    -- ECI packets for VC 11 - 2 (VC1,0 are IO VCs not handled here)

    -- ECI packet for CPU initiated response without data VC 11,10
    -- No payload only header
    c11_eci_hdr_o       : out std_logic_vector(63 downto 0);
    c11_eci_pkt_size_o  : out std_logic_vector( 4 downto 0);
    c11_eci_pkt_vc_o    : out std_logic_vector( 4 downto 0);
    c11_eci_pkt_valid_o : out std_logic;
    c11_eci_pkt_ready_i : in  std_logic;

    c10_eci_hdr_o       : out std_logic_vector(63 downto 0);
    c10_eci_pkt_size_o  : out std_logic_vector( 4 downto 0);
    c10_eci_pkt_vc_o    : out std_logic_vector( 4 downto 0);
    c10_eci_pkt_valid_o : out std_logic;
    c10_eci_pkt_ready_i : in  std_logic;

    -- ECI packet for CPU initiated forwards VC 9,8
    -- No payload only header
    c9_eci_hdr_o       : out std_logic_vector(63 downto 0);
    c9_eci_pkt_size_o  : out std_logic_vector( 4 downto 0);
    c9_eci_pkt_vc_o    : out std_logic_vector( 4 downto 0);
    c9_eci_pkt_valid_o : out std_logic;
    c9_eci_pkt_ready_i : in  std_logic;

    c8_eci_hdr_o       : out std_logic_vector(63 downto 0);
    c8_eci_pkt_size_o  : out std_logic_vector( 4 downto 0);
    c8_eci_pkt_vc_o    : out std_logic_vector( 4 downto 0);
    c8_eci_pkt_valid_o : out std_logic;
    c8_eci_pkt_ready_i : in  std_logic;

    -- ECI packet for CPU initiated request without data VC 7,6
    -- No payload only header
    c7_eci_hdr_o       : out std_logic_vector(63 downto 0);
    c7_eci_pkt_size_o  : out std_logic_vector( 4 downto 0);
    c7_eci_pkt_vc_o    : out std_logic_vector( 4 downto 0);
    c7_eci_pkt_valid_o : out std_logic;
    c7_eci_pkt_ready_i : in  std_logic;

    c6_eci_hdr_o       : out std_logic_vector(63 downto 0);
    c6_eci_pkt_size_o  : out std_logic_vector( 4 downto 0);
    c6_eci_pkt_vc_o    : out std_logic_vector( 4 downto 0);
    c6_eci_pkt_valid_o : out std_logic;
    c6_eci_pkt_ready_i : in  std_logic;

    -- ECI packet for CPU initiated response with data VC 5,4
    -- Header + payload
    c5_eci_pkt_o       : out std_logic_vector(17*64-1 downto 0);
    c5_eci_pkt_size_o  : out std_logic_vector( 4 downto 0);
    c5_eci_pkt_vc_o    : out std_logic_vector( 4 downto 0);
    c5_eci_pkt_valid_o : out std_logic;
    c5_eci_pkt_ready_i : in  std_logic;

    c4_eci_pkt_o       : out std_logic_vector(17*64-1 downto 0);
    c4_eci_pkt_size_o  : out std_logic_vector( 4 downto 0);
    c4_eci_pkt_vc_o    : out std_logic_vector( 4 downto 0);
    c4_eci_pkt_valid_o : out std_logic;
    c4_eci_pkt_ready_i : in  std_logic;

    -- ECI packet for CPU initiated requests with data VC 3,2
    c3_eci_pkt_o       : out std_logic_vector(17*64-1 downto 0);
    c3_eci_pkt_size_o  : out std_logic_vector( 4 downto 0);
    c3_eci_pkt_vc_o    : out std_logic_vector( 4 downto 0);
    c3_eci_pkt_valid_o : out std_logic;
    c3_eci_pkt_ready_i : in  std_logic;

    c2_eci_pkt_o       : out std_logic_vector(17*64-1 downto 0);
    c2_eci_pkt_size_o  : out std_logic_vector( 4 downto 0);
    c2_eci_pkt_vc_o    : out std_logic_vector( 4 downto 0);
    c2_eci_pkt_valid_o : out std_logic;
    c2_eci_pkt_ready_i : in  std_logic;

    -- VC 1,0 are IO VCs, not handled here

    -- Special Handlers
    -- GSYNC from VC7,6 (req without data)
    c7_gsync_hdr_o   : out std_logic_vector(63 downto 0);
    c7_gsync_valid_o : out std_logic;
    c7_gsync_ready_i : in  std_logic;

    c6_gsync_hdr_o   : out std_logic_vector(63 downto 0);
    c6_gsync_valid_o : out std_logic;
    c6_gsync_ready_i : in  std_logic
);
end component;

component eci_pkt_vc_router is
port (
   clk   : in std_logic;
   reset : in std_logic;

   -- Input ECI packets to corresponding VCs from dir controller
   -- VC11 - VC2 (VC1,0 are not handled here)

   -- ECI packet Outgoing response without data VC 11,10
   -- Note: no data sends only header
   dc11_eci_hdr_i       : in  std_logic_vector(63 downto 0);
   dc11_eci_pkt_size_i  : in  std_logic_vector( 4 downto 0);
   dc11_eci_pkt_valid_i : in  std_logic;
   dc11_eci_pkt_ready_o : out std_logic;

   dc10_eci_hdr_i       : in  std_logic_vector(63 downto 0);
   dc10_eci_pkt_size_i  : in  std_logic_vector( 4 downto 0);
   dc10_eci_pkt_valid_i : in  std_logic;
   dc10_eci_pkt_ready_o : out std_logic;

   -- ECI packet outgoing forwareds without data VC 9,8
   dc9_eci_hdr_i       : in  std_logic_vector(63 downto 0);
   dc9_eci_pkt_size_i  : in  std_logic_vector( 4 downto 0);
   dc9_eci_pkt_valid_i : in  std_logic;
   dc9_eci_pkt_ready_o : out std_logic;

   dc8_eci_hdr_i       : in  std_logic_vector(63 downto 0);
   dc8_eci_pkt_size_i  : in  std_logic_vector( 4 downto 0);
   dc8_eci_pkt_valid_i : in  std_logic;
   dc8_eci_pkt_ready_o : out std_logic;

   -- ECI packet outgoing requests without data VC 7,6
   dc7_eci_hdr_i       : in  std_logic_vector(63 downto 0);
   dc7_eci_pkt_size_i  : in  std_logic_vector( 4 downto 0);
   dc7_eci_pkt_valid_i : in  std_logic;
   dc7_eci_pkt_ready_o : out std_logic;

   dc6_eci_hdr_i       : in  std_logic_vector(63 downto 0);
   dc6_eci_pkt_size_i  : in  std_logic_vector( 4 downto 0);
   dc6_eci_pkt_valid_i : in  std_logic;
   dc6_eci_pkt_ready_o : out std_logic;

   -- ECI packet outgoing responses with data VC 5,4
   -- header+payload
   dc5_eci_pkt_i       : in  std_logic_vector(17*64-1 downto 0);
   dc5_eci_pkt_size_i  : in  std_logic_vector( 4 downto 0);
   dc5_eci_pkt_valid_i : in  std_logic;
   dc5_eci_pkt_ready_o : out std_logic;

   dc4_eci_pkt_i       : in  std_logic_vector(17*64-1 downto 0);
   dc4_eci_pkt_size_i  : in  std_logic_vector( 4 downto 0);
   dc4_eci_pkt_valid_i : in  std_logic;
   dc4_eci_pkt_ready_o : out std_logic;

   -- ECI packet outgoing requests with data VC 3,2
   -- header+payload
   dc3_eci_pkt_i       : in  std_logic_vector(17*64-1 downto 0);
   dc3_eci_pkt_size_i  : in  std_logic_vector( 4 downto 0);
   dc3_eci_pkt_valid_i : in  std_logic;
   dc3_eci_pkt_ready_o : out std_logic;

   dc2_eci_pkt_i       : in  std_logic_vector(17*64-1 downto 0);
   dc2_eci_pkt_size_i  : in  std_logic_vector( 4 downto 0);
   dc2_eci_pkt_valid_i : in  std_logic;
   dc2_eci_pkt_ready_o : out std_logic;

   -- Input ECI packets from special handlers
   -- GSDN for GSYNC
   gsdn11_hdr_i   : in  std_logic_vector(63 downto 0);
   gsdn11_valid_i : in  std_logic;
   gsdn11_ready_o : out std_logic;

   gsdn10_hdr_i   : in  std_logic_vector(63 downto 0);
   gsdn10_valid_i : in  std_logic;
   gsdn10_ready_o : out std_logic;

   -- Output VC packets generated by the FPGA
   -- VC11 - VC2 (VC1,0 are not handled here)

   -- VC packet Outgoing response without data VC 11,10
   -- Note: no data sends only header
   f11_vc_pkt_o       : out std_logic_vector(63 downto 0);
   f11_vc_pkt_size_o  : out std_logic_vector(  4 downto 0);
   f11_vc_pkt_valid_o : out std_logic;
   f11_vc_pkt_ready_i : in  std_logic;

   f10_vc_pkt_o       : out std_logic_vector(63 downto 0);
   f10_vc_pkt_size_o  : out std_logic_vector(  4 downto 0);
   f10_vc_pkt_valid_o : out std_logic;
   f10_vc_pkt_ready_i : in  std_logic;

   -- Incoming Forwards VC 9,8
   -- Forwards are command only no data, currently not connected
   f9_vc_pkt_o       : out std_logic_vector(63 downto 0);
   f9_vc_pkt_size_o  : out std_logic_vector(  4 downto 0);
   f9_vc_pkt_valid_o : out std_logic;
   f9_vc_pkt_ready_i : in  std_logic;

   f8_vc_pkt_o       : out std_logic_vector(63 downto 0);
   f8_vc_pkt_size_o  : out std_logic_vector(  4 downto 0);
   f8_vc_pkt_valid_o : out std_logic;
   f8_vc_pkt_ready_i : in  std_logic;

   -- Incoming requests without data VC 7,6
   f7_vc_pkt_o       : out std_logic_vector(63 downto 0);
   f7_vc_pkt_size_o  : out std_logic_vector(  4 downto 0);
   f7_vc_pkt_valid_o : out std_logic;
   f7_vc_pkt_ready_i : in  std_logic;

   f6_vc_pkt_o       : out std_logic_vector(63 downto 0);
   f6_vc_pkt_size_o  : out std_logic_vector(  4 downto 0);
   f6_vc_pkt_valid_o : out std_logic;
   f6_vc_pkt_ready_i : in  std_logic;

   -- Incoming resoponse with data VC 5,4
   f5_vc_pkt_o       : out std_logic_vector(1087 downto 0);
   f5_vc_pkt_size_o  : out std_logic_vector(   4 downto 0);
   f5_vc_pkt_valid_o : out std_logic;
   f5_vc_pkt_ready_i : in  std_logic;

   f4_vc_pkt_o       : out std_logic_vector(1087 downto 0);
   f4_vc_pkt_size_o  : out std_logic_vector(   4 downto 0);
   f4_vc_pkt_valid_o : out std_logic;
   f4_vc_pkt_ready_i : in  std_logic;

   -- Incoming request with data VC 3,2
   f3_vc_pkt_o       : out std_logic_vector(1087 downto 0);
   f3_vc_pkt_size_o  : out std_logic_vector(   4 downto 0);
   f3_vc_pkt_valid_o : out std_logic;
   f3_vc_pkt_ready_i : in  std_logic;

   f2_vc_pkt_o       : out std_logic_vector(1087 downto 0);
   f2_vc_pkt_size_o  : out std_logic_vector(   4 downto 0);
   f2_vc_pkt_valid_o : out std_logic;
   f2_vc_pkt_ready_i : in  std_logic
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
    vc_req_i       : in  std_logic_vector(WORD_WIDTH-1 downto 0);
    vc_req_valid_i : in  std_logic;
    vc_req_ready_o : out std_logic;

    -- ECI Response output stream
    vc_resp_o       : out std_logic_vector(WORD_WIDTH-1 downto 0);
    vc_resp_valid_o : out std_logic;
    vc_resp_ready_i : in  std_logic
);
end component;

component eci_co_cd_top_c is
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
  
      -- Response with data - VC 5/4
      -- Not connected for now 
  
      -- Request with data - VC 3/2
      f_vc3_cd_o         : out std_logic_vector(17*64-1 downto 0);
      f_vc3_cd_valid_o   : out std_logic;
      f_vc3_cd_size_o    : out std_logic_vector(4 downto 0);
      f_vc3_cd_ready_i   : in std_logic;
  
      f_vc2_cd_o         : out std_logic_vector(17*64-1 downto 0);
      f_vc2_cd_valid_o   : out std_logic;
      f_vc2_cd_size_o    : out std_logic_vector(4 downto 0);
      f_vc2_cd_ready_i   : in std_logic;
      
      -- IO response/ reqeuest VC 1/0
      -- not connected here
  
      --------------- CPU to FPGA (MIB) VCs ------------------//
      -- Response without data VC11/10
      c_vc11_co_i       : in std_logic_vector(63 downto 0); 
      c_vc11_co_valid_i : in std_logic;
      c_vc11_co_size_i  : in std_logic_vector(4 downto 0);
      c_vc11_co_ready_o : out std_logic;
  
      c_vc10_co_i       : in std_logic_vector(63 downto 0); 
      c_vc10_co_valid_i : in std_logic;
      c_vc10_co_size_i  : in std_logic_vector(4 downto 0);
      c_vc10_co_ready_o : out std_logic;
  
      -- Response with data - VC 5/4
      c_vc5_cd_i        : in std_logic_vector(17*64-1 downto 0); 
      c_vc5_cd_valid_i  : in std_logic;
      c_vc5_cd_size_i   : in std_logic_vector(4 downto 0);
      c_vc5_cd_ready_o  : out std_logic;
  
      c_vc4_cd_i        : in std_logic_vector(17*64-1 downto 0); 
      c_vc4_cd_valid_i  : in std_logic;
      c_vc4_cd_size_i   : in std_logic_vector(4 downto 0);
      c_vc4_cd_ready_o  : out std_logic
  
      -- Request with data - VC 3/2
      -- Not connected for now
      
      -- IO response/request VC 1/0
      -- Not connected for now 
      );
  end component;

-------------------------------------------------------------------------------------------------------------
-- RECORDS

type AXI_LITE is record
    araddr  : std_logic_vector(31 downto 0);
    arprot  : std_logic_vector( 2 downto 0);
    arready : std_logic;
    arvalid : std_logic;
    awaddr  : std_logic_vector(31 downto 0);
    awprot  : std_logic_vector( 2 downto 0);
    awready : std_logic;
    awvalid : std_logic;
    bready  : std_logic;
    bresp   : std_logic_vector( 1 downto 0);
    bvalid  : std_logic;
    rdata   : std_logic_vector(31 downto 0);
    rready  : std_logic;
    rresp   : std_logic_vector( 1 downto 0);
    rvalid  : std_logic;
    wdata   : std_logic_vector(31 downto 0);
    wready  : std_logic;
    wstrb   : std_logic_vector( 3 downto 0);
    wvalid  : std_logic;
end record AXI_LITE;

type LINK is record
    xcvr_txd_raw        : std_logic_vector(64 * NUM_LANES - 1 downto 0);
    xcvr_rxd_raw        : std_logic_vector(64 * NUM_LANES - 1 downto 0);
    xcvr_txd            : std_logic_vector(64 * NUM_LANES - 1 downto 0);
    xcvr_rxd            : std_logic_vector(64 * NUM_LANES - 1 downto 0);
    xcvr_reset          : std_logic;
    xcvr_reset_tx_all   : std_logic;
    xcvr_reset_tx       : std_logic;
    xcvr_reset_rx_all   : std_logic;
    xcvr_reset_rx       : std_logic;
    xcvr_tx_ready       : std_logic;
    xcvr_txprbssel      : std_logic_vector(4*NUM_LANES - 1 downto 0);
    xcvr_txprbsforceerr : std_logic_vector(NUM_LANES - 1 downto 0);
    xcvr_rx_ready       : std_logic;
    xcvr_rxslide        : std_logic_vector(NUM_LANES - 1 downto 0);
    xcvr_rxprbssel      : std_logic_vector(4*NUM_LANES - 1 downto 0);
    xcvr_rxprbscntreset : std_logic_vector(NUM_LANES - 1 downto 0);
    xcvr_rxprbslocked   : std_logic_vector(NUM_LANES - 1 downto 0);
    xcvr_tx_active      : std_logic;
    xcvr_rx_active      : std_logic;
    xcvr_txdiffctrl     : std_logic_vector(5*NUM_LANES-1 downto 0);
    xcvr_txpostcursor   : std_logic_vector(5*NUM_LANES-1 downto 0);
    xcvr_txprecursor    : std_logic_vector(5*NUM_LANES-1 downto 0);
    train_rx            : std_logic;
    reset_rx            : std_logic;
    train_tx            : std_logic;
    reset_tx            : std_logic;

    xcvr_rxgearboxslip  : std_logic_vector(NUM_LANES-1 downto 0);
    xcvr_rxdatavalid    : std_logic_vector(2*NUM_LANES-1 downto 0);
    xcvr_rxheader       : std_logic_vector(6*NUM_LANES-1 downto 0);
    xcvr_rxheadervalid  : std_logic_vector(2*NUM_LANES-1 downto 0);
    xcvr_rxstartofseq   : std_logic_vector(2*NUM_LANES-1 downto 0);
    xcvr_txheader       : std_logic_vector(6*NUM_LANES-1 downto 0);
    xcvr_txsequence     : std_logic_vector(7*NUM_LANES-1 downto 0);

    xcvr_buffbypass_tx_reset  : std_logic;
    xcvr_buffbypass_tx_start_user : std_logic;
    xcvr_buffbypass_tx_done   : std_logic;
    xcvr_buffbypass_tx_error  : std_logic;
    xcvr_buffbypass_rx_reset  : std_logic;
    xcvr_buffbypass_rx_start_user : std_logic;
    xcvr_buffbypass_rx_done   : std_logic;
    xcvr_buffbypass_rx_error  : std_logic;
    userclk_tx_active_in : std_logic;
    userclk_rx_active_in : std_logic;
    rxoutclk : std_logic_vector(NUM_LANES - 1 downto 0);
    rxusrclk : std_logic_vector(NUM_LANES - 1 downto 0);
    rxusrclk2 : std_logic_vector(NUM_LANES - 1 downto 0);
    txoutclk : std_logic_vector(NUM_LANES - 1 downto 0);
    txusrclk: std_logic_vector(NUM_LANES - 1 downto 0);
    txusrclk2 : std_logic_vector(NUM_LANES - 1 downto 0);

    -- The per-link transceiver data
    txd : std_logic_vector(64*NUM_LANES-1 downto 0);
    txd_header     : std_logic_vector(3 * NUM_LANES - 1 downto 0);
    txd_ready      : std_logic;
    rxd : std_logic_vector(64*NUM_LANES-1 downto 0);

    -- Transceiver-derived clocks.
    clk_tx, clk_rx : std_logic;
    clk_ref : std_logic_vector(2 downto 0);
    reset_blk : std_logic;
end record LINK;

-- Interlaken link signals
type INTERLAKEN is record
    rx_reset           : std_logic;
    rx_data            : std_logic_vector(64*NUM_LANES-1 downto 0);
    rx_data_valid      : std_logic;
    rx_ctrl_word       : std_logic_vector(NUM_LANES-1 downto 0);
    rx_lane_word_lock  : std_logic_vector(NUM_LANES-1 downto 0);
    rx_lane_frame_lock : std_logic_vector(NUM_LANES-1 downto 0);
    rx_lane_crc32_bad  : std_logic_vector(NUM_LANES-1 downto 0);
    rx_lane_status     : std_logic_vector(2*NUM_LANES-1 downto 0);
    force_rx_aligned         : std_logic;
    rx_aligned         : std_logic;
    rx_aligned_old         : std_logic;
    rx_total_skew      : std_logic_vector(2 downto 0);

    tx_reset           : std_logic;
    tx_data            : std_logic_vector(64*NUM_LANES-1 downto 0);
    tx_data_ready      : std_logic;
    tx_ctrl_word       : std_logic_vector(NUM_LANES-1 downto 0);

    usr_rx_reset : std_logic;
    usr_tx_reset : std_logic;
end record INTERLAKEN;

-- ECI block-layer signals, on clk_sys
type ECI_BLOCK is record
    rx_block           : std_logic_vector(511 downto 0);
    rx_block_blk       : std_logic_vector(511 downto 0);
    rx_block_valid     : std_logic;
    rx_block_valid_blk : std_logic;
    rx_block_crc_match : std_logic;
    tx_block           : std_logic_vector(511 downto 0);
    tx_block_blk       : std_logic_vector(511 downto 0);
    tx_block_ready     : std_logic;
    tx_block_ready_blk : std_logic;
end record ECI_BLOCK;

type IO_AXI_LITE is record
    awaddr  :  std_logic_vector(39 downto 0);
    awvalid :  std_logic;
    awready :  std_logic;
    wdata   :  std_logic_vector(63 downto 0);
    wstrb   :  std_logic_vector(7 downto 0);
    wvalid  :  std_logic;
    wready  :  std_logic;
    bresp   :  std_logic_vector(1 downto 0);
    bvalid  :  std_logic;
    bready  :  std_logic;
    araddr  :  std_logic_vector(39 downto 0);
    arvalid :  std_logic;
    arready :  std_logic;
    rdata   :  std_logic_vector(63 downto 0);
    rresp   :  std_logic_vector(1 downto 0);
    rvalid  :  std_logic;
    rready  :  std_logic;
end record IO_AXI_LITE;

type MIB is record
    vc11_co       :  std_logic_vector(447 downto 0);
    vc11_co_valid :  std_logic;
    vc11_co_word_enable  :  std_logic_vector(6 downto 0);
    vc11_co_ready :   std_logic;
    vc10_co       :  std_logic_vector(447 downto 0);
    vc10_co_valid :  std_logic;
    vc10_co_word_enable  :  std_logic_vector(6 downto 0);
    vc10_co_ready :   std_logic;
    vc9_co        :  std_logic_vector(447 downto 0);
    vc9_co_valid  :  std_logic;
    vc9_co_word_enable   :  std_logic_vector(6 downto 0);
    vc9_co_ready  :   std_logic;
    vc8_co        :  std_logic_vector(447 downto 0);
    vc8_co_valid  :  std_logic;
    vc8_co_word_enable   :  std_logic_vector(6 downto 0);
    vc8_co_ready  :   std_logic;
    vc7_co        :  std_logic_vector(447 downto 0);
    vc7_co_valid  :  std_logic;
    vc7_co_word_enable   :  std_logic_vector(6 downto 0);
    vc7_co_ready  :   std_logic;
    vc6_co        :  std_logic_vector(447 downto 0);
    vc6_co_valid  :  std_logic;
    vc6_co_word_enable   :  std_logic_vector(6 downto 0);
    vc6_co_ready  :   std_logic;
    -- VC 5 - 2
    vc5_cd        :  std_logic_vector(447 downto 0);
    vc5_cd_valid  :  std_logic;
    vc5_cd_word_enable   :  std_logic_vector(6 downto 0);
    vc5_cd_ready  :   std_logic;
    vc4_cd        :  std_logic_vector(447 downto 0);
    vc4_cd_valid  :  std_logic;
    vc4_cd_word_enable   :  std_logic_vector(6 downto 0);
    vc4_cd_ready  :   std_logic;
    vc3_cd        :  std_logic_vector(447 downto 0);
    vc3_cd_valid  :  std_logic;
    vc3_cd_word_enable   :  std_logic_vector(6 downto 0);
    vc3_cd_ready  :   std_logic;
    vc2_cd        :  std_logic_vector(447 downto 0);
    vc2_cd_valid  :  std_logic;
    vc2_cd_word_enable   :  std_logic_vector(6 downto 0);
    vc2_cd_ready  :   std_logic;
    -- MCD VC13
    vc_mcd        :  std_logic_vector(63 downto 0);
    vc_mcd_valid  :  std_logic;
    vc_mcd_ready  :   std_logic;

    vc0_io         : WORDS(6 downto 0);
    vc0_io_valid   : std_logic;
    vc0_io_word_enable   :  std_logic_vector(6 downto 0);
    vc0_io_ready   : std_logic;
    vc1_io         : WORDS(6 downto 0);
    vc1_io_valid   : std_logic;
    vc1_io_word_enable   :  std_logic_vector(6 downto 0);
    vc1_io_ready   : std_logic;
end record MIB;

-------------------------- MOB VCs Inputs ----------------------------//
-- VC 11 - 6
type MOB is record
    vc11_co       :   std_logic_vector(63 downto 0);
    vc11_co_valid :   std_logic;
    vc11_co_size  :   std_logic_vector(4 downto 0);
    vc11_co_ready :  std_logic;
    vc10_co       :   std_logic_vector(63 downto 0);
    vc10_co_valid :   std_logic;
    vc10_co_size  :   std_logic_vector(4 downto 0);
    vc10_co_ready :  std_logic;
    vc9_co        :   std_logic_vector(63 downto 0);
    vc9_co_valid  :   std_logic;
    vc9_co_size   :   std_logic_vector(4 downto 0);
    vc9_co_ready  :  std_logic;
    vc8_co        :   std_logic_vector(63 downto 0);
    vc8_co_valid  :   std_logic;
    vc8_co_size   :   std_logic_vector(4 downto 0);
    vc8_co_ready  :  std_logic;
    vc7_co        :   std_logic_vector(63 downto 0);
    vc7_co_valid  :   std_logic;
    vc7_co_size   :   std_logic_vector(4 downto 0);
    vc7_co_ready  :  std_logic;
    vc6_co        :   std_logic_vector(63 downto 0);
    vc6_co_valid  :   std_logic;
    vc6_co_size   :   std_logic_vector(4 downto 0);
    vc6_co_ready  :  std_logic;
    -- VC 5 - 2
    vc5_cd        :   std_logic_vector(1087 downto 0);
    vc5_cd_valid  :   std_logic;
    vc5_cd_size   :   std_logic_vector(4 downto 0);
    vc5_cd_ready  :  std_logic;
    vc4_cd        :   std_logic_vector(1087 downto 0);
    vc4_cd_valid  :   std_logic;
    vc4_cd_size   :   std_logic_vector(4 downto 0);
    vc4_cd_ready  :  std_logic;
    vc3_cd        :   std_logic_vector(1087 downto 0);
    vc3_cd_valid  :   std_logic;
    vc3_cd_size   :   std_logic_vector(4 downto 0);
    vc3_cd_ready  :  std_logic;
    vc2_cd        :   std_logic_vector(1087 downto 0);
    vc2_cd_valid  :   std_logic;
    vc2_cd_size   :   std_logic_vector(4 downto 0);
    vc2_cd_ready  :  std_logic;
    -- MCD VC13
    vc_mcd        :   std_logic_vector(63 downto 0);
    vc_mcd_valid  :   std_logic;
    vc_mcd_ready  :  std_logic;

    vc0_io         : WORDS(1 downto 0);
    vc0_io_valid   : std_logic;
    vc0_io_size    : std_logic_vector(2 downto 0);
    vc0_io_ready   : std_logic;
    vc1_io         : WORDS(1 downto 0);
    vc1_io_valid   : std_logic;
    vc1_io_size    : std_logic_vector(2 downto 0);
    vc1_io_ready   : std_logic;
end record MOB;

-- DDR4 types

type DDR4_AXI is record
  awaddr  : std_logic_vector( 39 downto 0);
  awvalid : std_logic;
  awready : std_logic;
  wdata   : std_logic_vector(511 downto 0);
  wstrb   : std_logic_vector( 63 downto 0);
  wvalid  : std_logic;
  wready  : std_logic;
  bvalid  : std_logic;
  bready  : std_logic;
  bresp   : std_logic_vector(  1 downto 0);
  arid    : std_logic_vector(  5 downto 0);
  araddr  : std_logic_vector( 39 downto 0);
  arlen   : std_logic_vector(  7 downto 0);
  arsize  : std_logic_vector(  2 downto 0);
  arburst : std_logic_vector(  1 downto 0);
  arvalid : std_logic;
  arready : std_logic;
  rready  : std_logic;
  rlast   : std_logic;
  rvalid  : std_logic;
  rresp   : std_logic_vector(  1 downto 0);
  rid     : std_logic_vector(  5 downto 0);
  rdata   : std_logic_vector(511 downto 0);
end record DDR4_AXI;

-- Single-ended, buffered clocks.
signal clk_sys : std_logic;
signal clk_gt : std_logic;

-- AXI Busses
signal AXI_aresetn : std_logic;

signal link1, link2 : LINK;

signal il_link1 : INTERLAKEN;
signal il_link2 : INTERLAKEN;

signal eci_link1 : ECI_BLOCK;
signal eci_link2 : ECI_BLOCK;

signal io_axil_link     : IO_AXI_LITE;

signal mib_link1 : MIB;
signal mib_link2 : MIB;

signal mob_link1 : MOB;
signal mob_link2 : MOB;

signal reset, reset_unbuf, reset_unbuf_sync : std_logic;
signal reset_n, reset_n_unbuf : std_logic;

type ECI_PACKET_RX is record
    c7_gsync_hdr_rx   : std_logic_vector(63 downto 0);
    c7_gsync_valid_rx : std_logic;
    c7_gsync_ready_rx : std_logic;

    c6_gsync_hdr_rx   : std_logic_vector(63 downto 0);
    c6_gsync_valid_rx : std_logic;
    c6_gsync_ready_rx : std_logic;

    c11_eci_hdr_rx       : std_logic_vector(63 downto 0);
    c11_eci_pkt_size_rx  : std_logic_vector( 4 downto 0);
    c11_eci_pkt_vc_rx    : std_logic_vector( 4 downto 0);
    c11_eci_pkt_valid_rx : std_logic;
    c11_eci_pkt_ready_rx : std_logic;

    c10_eci_hdr_rx       : std_logic_vector(63 downto 0);
    c10_eci_pkt_size_rx  : std_logic_vector( 4 downto 0);
    c10_eci_pkt_vc_rx    : std_logic_vector( 4 downto 0);
    c10_eci_pkt_valid_rx : std_logic;
    c10_eci_pkt_ready_rx : std_logic;

    c7_eci_hdr_rx       : std_logic_vector(63 downto 0);
    c7_eci_pkt_size_rx  : std_logic_vector( 4 downto 0);
    c7_eci_pkt_vc_rx    : std_logic_vector( 4 downto 0);
    c7_eci_pkt_valid_rx : std_logic;
    c7_eci_pkt_ready_rx : std_logic;

    c6_eci_hdr_rx       : std_logic_vector(63 downto 0);
    c6_eci_pkt_size_rx  : std_logic_vector( 4 downto 0);
    c6_eci_pkt_vc_rx    : std_logic_vector( 4 downto 0);
    c6_eci_pkt_valid_rx : std_logic;
    c6_eci_pkt_ready_rx : std_logic;

    c5_eci_hdr_rx       : std_logic_vector(17*64-1 downto 0);
    c5_eci_pkt_size_rx  : std_logic_vector( 4 downto 0);
    c5_eci_pkt_vc_rx    : std_logic_vector( 4 downto 0);
    c5_eci_pkt_valid_rx : std_logic;
    c5_eci_pkt_ready_rx : std_logic;

    c4_eci_hdr_rx       : std_logic_vector(17*64-1 downto 0);
    c4_eci_pkt_size_rx  : std_logic_vector( 4 downto 0);
    c4_eci_pkt_vc_rx    : std_logic_vector( 4 downto 0);
    c4_eci_pkt_valid_rx : std_logic;
    c4_eci_pkt_ready_rx : std_logic;
end record ECI_PACKET_RX;

type ECI_PACKET_TX is record
-- VC packets inputs, from the ThunderX
-- GSYNC packets to be looped back
    c11_gsync_hdr_tx   : std_logic_vector(63 downto 0);
    c11_gsync_valid_tx : std_logic;
    c11_gsync_ready_tx : std_logic;

    c10_gsync_hdr_tx   : std_logic_vector(63 downto 0);
    c10_gsync_valid_tx : std_logic;
    c10_gsync_ready_tx : std_logic;

-- Responses with data (i.e. read response), to the ThunderX
    c11_eci_pkt_tx       : std_logic_vector(63 downto 0);
    c11_eci_pkt_size_tx  : std_logic_vector( 4 downto 0);
    c11_eci_pkt_valid_tx : std_logic;
    c11_eci_pkt_ready_tx : std_logic;

    c10_eci_pkt_tx       : std_logic_vector(63 downto 0);
    c10_eci_pkt_size_tx  : std_logic_vector( 4 downto 0);
    c10_eci_pkt_valid_tx : std_logic;
    c10_eci_pkt_ready_tx : std_logic;

    c7_eci_pkt_tx       : std_logic_vector(63 downto 0);
    c7_eci_pkt_size_tx  : std_logic_vector( 4 downto 0);
    c7_eci_pkt_valid_tx : std_logic;
    c7_eci_pkt_ready_tx : std_logic;

    c6_eci_pkt_tx       : std_logic_vector(63 downto 0);
    c6_eci_pkt_size_tx  : std_logic_vector( 4 downto 0);
    c6_eci_pkt_valid_tx : std_logic;
    c6_eci_pkt_ready_tx : std_logic;

    c5_eci_pkt_tx       : std_logic_vector(17*64-1 downto 0);
    c5_eci_pkt_size_tx  : std_logic_vector( 4 downto 0);
    c5_eci_pkt_valid_tx : std_logic;
    c5_eci_pkt_ready_tx : std_logic;

    c4_eci_pkt_tx       : std_logic_vector(17*64-1 downto 0);
    c4_eci_pkt_size_tx  : std_logic_vector( 4 downto 0);
    c4_eci_pkt_valid_tx : std_logic;
    c4_eci_pkt_ready_tx : std_logic;

    c3_eci_pkt_tx       : std_logic_vector(17*64-1 downto 0);
    c3_eci_pkt_size_tx  : std_logic_vector( 4 downto 0);
    c3_eci_pkt_valid_tx : std_logic;
    c3_eci_pkt_ready_tx : std_logic;

    c2_eci_pkt_tx       : std_logic_vector(17*64-1 downto 0);
    c2_eci_pkt_size_tx  : std_logic_vector( 4 downto 0);
    c2_eci_pkt_valid_tx : std_logic;
    c2_eci_pkt_ready_tx : std_logic;
end record ECI_PACKET_TX;

signal link1_eci_packet_rx, link2_eci_packet_rx : ECI_PACKET_RX;
signal link1_eci_packet_tx, link2_eci_packet_tx : ECI_PACKET_TX;

-- Manipulated address to interleave blocks between channels.
signal io_axil_awaddr_interleaved : std_logic_vector(34 downto 0);

-- Even block AXI Lite signals (clk_sys)
type IO_AXI_LITE_WRITE is record
    awaddr  :  std_logic_vector(34 downto 0);
    awvalid :  std_logic;
    awready :  std_logic;
    wdata   :  std_logic_vector(63 downto 0);
    wstrb   :  std_logic_vector(7 downto 0);
    wvalid  :  std_logic;
    wready  :  std_logic;
    bresp   :  std_logic_vector(1 downto 0);
    bvalid  :  std_logic;
    bready  :  std_logic;
end record IO_AXI_LITE_WRITE;

signal link1_io_axil_even,link1_io_axil_odd,link2_io_axil_even,link2_io_axil_odd : IO_AXI_LITE_WRITE;

signal io_axil_link_awaddr  : std_logic_vector(39 downto 0);
signal io_axil_link_awvalid : std_logic;
signal io_axil_link_awready : std_logic;
signal io_axil_link_araddr  : std_logic_vector(39 downto 0);
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

---- Assign AXIL
axil_ctrl_awaddr        <= io_axil_link_awaddr(35 downto 0);
axil_ctrl_awvalid       <= io_axil_link_awvalid;
axil_ctrl_araddr        <= io_axil_link_araddr(35 downto 0);
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

---- Resets

reset_unbuf <= link1.reset_blk or link2.reset_blk;
reset_n_unbuf <= not link1.reset_blk and not link2.reset_blk;

i_reset_sync : xpm_cdc_async_rst
port map (
    src_arst => reset_unbuf,
    dest_clk => clk_sys,
    dest_arst => reset_unbuf_sync
);

i_reset_buf : BUFG
port map (
    I => reset_unbuf_sync,
    O => reset
);
    
i_reset_n_buf : BUFG
port map (
    I => reset_n_unbuf,
    O => reset_n
);

resetn_axi <= reset_n;

----
---- Transceivers
----

-- The Ultrascale transceiver wizard expects a single-ended reference clock.
-- This instantiates the clock buffer in the transceiver quad - a normal
-- IBUFDS *won't* work.
ccpi_refclks: for i in 0 to 2 generate
ref_buf_link1 : IBUFDS_GTE4
generic map (
    REFCLK_EN_TX_PATH  => '0',
    REFCLK_HROW_CK_SEL => "00",
    REFCLK_ICNTL_RX    => "00"
)
port map (
    O   => link1.clk_ref(i),
    I   => ccpi_clk_p(i),
    IB  => ccpi_clk_n(i),
    CEB => '0'
);
end generate;

-- 322.265625 MHz
i_clk_gt_link1 : BUFG_GT
port map (
    I => link1.txoutclk(5),
    CE => '1',
    CEMASK => '0',
    CLR =>'0',
    CLRMASK => '0',
    DIV => "000",
    O => clk_sys
);

clk_axi <= clk_sys;

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

link1.clk_rx <= clk_gt;
link1.clk_tx <= clk_gt;

link1.rxusrclk <= (others => clk_sys);
link1.rxusrclk2 <= (others => clk_gt);
link1.txusrclk <= (others => clk_sys);
link1.txusrclk2 <= (others => clk_gt);

i_clk_active_link1 : xpm_cdc_single
port map (
    src_in => '1',
    src_clk => clk_gt,
    dest_clk => clk_io,
    dest_out => link1.userclk_tx_active_in
);
--i_clk_active_link1 : xpm_cdc_sync_rst
--port map (
--    src_rst => '1',
--    dest_clk => link1.clk_gt2,
--    dest_rst => link1.userclk_tx_active_in
--);
link1.userclk_rx_active_in <= link1.userclk_tx_active_in;

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

    gtwiz_buffbypass_rx_reset_in(0)       => '0',--link1.xcvr_buffbypass_rx_reset,
    gtwiz_buffbypass_rx_start_user_in(0)  => '0',--link1.xcvr_buffbypass_rx_start_user,
    gtwiz_buffbypass_rx_done_out(0)       => link1.xcvr_buffbypass_rx_done,
    gtwiz_buffbypass_rx_error_out(0)      => link1.xcvr_buffbypass_rx_error,

    gtwiz_buffbypass_tx_reset_in(0)       => '0',--link1.xcvr_buffbypass_tx_reset,
    gtwiz_buffbypass_tx_start_user_in(0)  => '0',--link1.xcvr_buffbypass_tx_start_user,
    gtwiz_buffbypass_tx_done_out(0)       => link1.xcvr_buffbypass_tx_done,
    gtwiz_buffbypass_tx_error_out(0)      => link1.xcvr_buffbypass_tx_error,

    gtwiz_reset_clk_freerun_in(0)         => clk_io,
    gtwiz_reset_all_in(0)                 => '0',--link1.xcvr_reset,
    gtwiz_reset_tx_pll_and_datapath_in(0) => '0',--link1.xcvr_reset_tx_all,
    gtwiz_reset_tx_datapath_in(0)         => '0',--link1.xcvr_reset_tx,
    gtwiz_reset_rx_pll_and_datapath_in(0) => '0',--link1.xcvr_reset_rx_all,
    gtwiz_reset_rx_datapath_in(0)         => '0',--link1.xcvr_reset_rx,
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

    gtyrxn_in                             => ccpi_rxn(NUM_LANES-1 downto 0),
    gtyrxp_in                             => ccpi_rxp(NUM_LANES-1 downto 0),
    gtytxn_out                            => ccpi_txn(NUM_LANES-1 downto 0),
    gtytxp_out                            => ccpi_txp(NUM_LANES-1 downto 0),

    txdiffctrl_in                         => link1.xcvr_txdiffctrl,
    txpostcursor_in                       => link1.xcvr_txpostcursor,
    txprecursor_in                        => link1.xcvr_txprecursor
);

-- 322.265625 MHz
--i_clk_gt_link2 : BUFG_GT
--port map (
--    I => link2.txoutclk(5),
--    CE => '1',
--    CEMASK => '0',
--    CLR =>'0',
--    CLRMASK => '0',
--    DIV => "000",
--    O => link2.clk_gt
--);

---- 161.1328125 MHz
--i_clk_gt2_link2 : BUFG_GT
--port map (
--    I => link2.txoutclk(5),
--    CE => '1',
--    CEMASK => '0',
--    CLR =>'0',
--    CLRMASK => '0',
--    DIV => "001", -- divide by 2
--    O => link2.clk_gt2
--);

i_vio_xcvr: vio_xcvr
port map (
    clk => clk_gt,
    probe_in0(0) => il_link1.rx_aligned,
    probe_in1    => il_link1.rx_total_skew,
    probe_in2(0) => il_link1.rx_reset,
    probe_in3(0) => il_link1.tx_reset,
    probe_in4(0) => il_link2.rx_aligned,
    probe_in5    => il_link2.rx_total_skew,
    probe_in6(0) => il_link2.rx_reset,
    probe_in7(0) => il_link2.tx_reset,
    probe_out0(0) => il_link1.force_rx_aligned,
    probe_out1(0) => il_link2.force_rx_aligned
);

---- CCPI RX Link
rx_il_link1 : il_rx_link_gearbox
generic map (
    LANES     => NUM_LANES,
    METAFRAME => 2048
)
port map (
    clk_rx          => link1.clk_rx,
    reset           => il_link1.rx_reset,

    xcvr_rxdata         => link1.xcvr_rxd,
    xcvr_rxdatavalid    => link1.xcvr_rxdatavalid,
    xcvr_rxheader       => link1.xcvr_rxheader,
    xcvr_rxheadervalid  => link1.xcvr_rxheadervalid,
    xcvr_rxgearboxslip  => link1.xcvr_rxgearboxslip,

    output          => il_link1.rx_data,
    output_valid    => il_link1.rx_data_valid,
    ctrl_word_out   => il_link1.rx_ctrl_word,
    link_aligned    => il_link1.rx_aligned,
    lane_word_lock  => il_link1.rx_lane_word_lock,
    lane_frame_lock => il_link1.rx_lane_frame_lock,
    lane_crc32_bad  => il_link1.rx_lane_crc32_bad,
    lane_status     => il_link1.rx_lane_status,
    total_skew      => il_link1.rx_total_skew
);

rx_eci_blk_link1 : ccpi_rx_blk_sync
generic map (
    LANES     => NUM_LANES
)
port map (
    clk_rx          => link1.clk_rx,
    reset           => il_link1.rx_reset,
    clk_blk         => clk_sys,
    reset_blk       => link1.reset_blk,
    link_aligned    => il_link1.rx_aligned,
    link_data       => il_link1.rx_data,
    link_data_valid => il_link1.rx_data_valid,
    ctrl_word       => il_link1.rx_ctrl_word,
    block_out       => eci_link1.rx_block,
    block_out_valid => eci_link1.rx_block_valid,
    crc_match_out   => eci_link1.rx_block_crc_match
);

---- CCPI TX Link
tx_il_link1 : il_tx_link_gearbox
generic map (
    LANES => NUM_LANES,
    METAFRAME => 2048
)
port map (
    clk_tx       => link1.clk_tx,
    reset        => il_link1.tx_reset,
    input        => il_link1.tx_data,
    input_ready  => il_link1.tx_data_ready,
    ctrl_word_in => il_link1.tx_ctrl_word,
    xcvr_txdata  => link1.xcvr_txd,
    xcvr_txheader       => link1.xcvr_txheader,
    xcvr_txsequence     => link1.xcvr_txsequence
);

tx_eci_blk_link1 : ccpi_tx_blk_sync
generic map (
    LANES => NUM_LANES
)
port map (
    clk_tx          => link1.clk_tx,
    reset           => il_link1.tx_reset,
    clk_blk         => clk_sys,
    reset_blk       => reset,
    block_in        => eci_link1.tx_block,
    block_in_ready  => eci_link1.tx_block_ready,
    link_data       => il_link1.tx_data,
    link_data_ready => il_link1.tx_data_ready,
    ctrl_word_out   => il_link1.tx_ctrl_word
);

-- The CCPI block interface runs on the 300MHz system clock.
-- The CCPI block decoding and link-state logic. XXX to be extended.

eci_1 : eci_link
port map (
    clk              => clk_sys,
    reset            => reset,
    blk_rx_data      => eci_link1.rx_block,
    blk_rx_valid     => eci_link1.rx_block_valid,
    blk_crc_match    => eci_link1.rx_block_crc_match,
    blk_tx_data      => eci_link1.tx_block,
    blk_tx_ready     => eci_link1.tx_block_ready,

    mib_vc11_co       => mib_link1.vc11_co,
    mib_vc11_co_valid => mib_link1.vc11_co_valid,
    mib_vc11_co_word_enable  => mib_link1.vc11_co_word_enable,
    mib_vc11_co_ready => mib_link1.vc11_co_ready,
    mib_vc10_co       => mib_link1.vc10_co,
    mib_vc10_co_valid => mib_link1.vc10_co_valid,
    mib_vc10_co_word_enable  => mib_link1.vc10_co_word_enable,
    mib_vc10_co_ready => mib_link1.vc10_co_ready,
    mib_vc9_co        => mib_link1.vc9_co,
    mib_vc9_co_valid  => mib_link1.vc9_co_valid,
    mib_vc9_co_word_enable   => mib_link1.vc9_co_word_enable,
    mib_vc9_co_ready  => mib_link1.vc9_co_ready,
    mib_vc8_co        => mib_link1.vc8_co,
    mib_vc8_co_valid  => mib_link1.vc8_co_valid,
    mib_vc8_co_word_enable   => mib_link1.vc8_co_word_enable,
    mib_vc8_co_ready  => mib_link1.vc8_co_ready,
    mib_vc7_co        => mib_link1.vc7_co,
    mib_vc7_co_valid  => mib_link1.vc7_co_valid,
    mib_vc7_co_word_enable   => mib_link1.vc7_co_word_enable,
    mib_vc7_co_ready  => mib_link1.vc7_co_ready,
    mib_vc6_co        => mib_link1.vc6_co,
    mib_vc6_co_valid  => mib_link1.vc6_co_valid,
    mib_vc6_co_word_enable   => mib_link1.vc6_co_word_enable,
    mib_vc6_co_ready  => mib_link1.vc6_co_ready,
    -- VC 5 - 2
    mib_vc5_cd        => mib_link1.vc5_cd,
    mib_vc5_cd_valid  => mib_link1.vc5_cd_valid,
    mib_vc5_cd_word_enable   => mib_link1.vc5_cd_word_enable,
    mib_vc5_cd_ready  => mib_link1.vc5_cd_ready,
    mib_vc4_cd        => mib_link1.vc4_cd,
    mib_vc4_cd_valid  => mib_link1.vc4_cd_valid,
    mib_vc4_cd_word_enable   => mib_link1.vc4_cd_word_enable,
    mib_vc4_cd_ready  => mib_link1.vc4_cd_ready,
    mib_vc3_cd        => mib_link1.vc3_cd,
    mib_vc3_cd_valid  => mib_link1.vc3_cd_valid,
    mib_vc3_cd_word_enable   => mib_link1.vc3_cd_word_enable,
    mib_vc3_cd_ready  => mib_link1.vc3_cd_ready,
    mib_vc2_cd        => mib_link1.vc2_cd,
    mib_vc2_cd_valid  => mib_link1.vc2_cd_valid,
    mib_vc2_cd_word_enable   => mib_link1.vc2_cd_word_enable,
    mib_vc2_cd_ready  => mib_link1.vc2_cd_ready,
    -- MCD VC13
    mib_vc_mcd        => mib_link1.vc_mcd,
    mib_vc_mcd_valid  => mib_link1.vc_mcd_valid,
    mib_vc_mcd_ready  => mib_link1.vc_mcd_ready,

    mib_vc0_io         => mib_link1.vc0_io,
    mib_vc0_io_valid   => mib_link1.vc0_io_valid,
    mib_vc0_io_word_enable    => mib_link1.vc0_io_word_enable,
    mib_vc0_io_ready   => mib_link1.vc0_io_ready,

    mib_vc1_io         => mib_link1.vc1_io,
    mib_vc1_io_valid   => mib_link1.vc1_io_valid,
    mib_vc1_io_word_enable    => mib_link1.vc1_io_word_enable,
    mib_vc1_io_ready   => mib_link1.vc1_io_ready,

    -------------------------- MOB VCs Inputs ----------------------------//
    -- VC 11 - 6
    mob_vc11_co       => mob_link1.vc11_co,
    mob_vc11_co_valid => mob_link1.vc11_co_valid,
    mob_vc11_co_size  => mob_link1.vc11_co_size,
    mob_vc11_co_ready => mob_link1.vc11_co_ready,
    mob_vc10_co       => mob_link1.vc10_co,
    mob_vc10_co_valid => mob_link1.vc10_co_valid,
    mob_vc10_co_size  => mob_link1.vc10_co_size,
    mob_vc10_co_ready => mob_link1.vc10_co_ready,
    mob_vc9_co        => mob_link1.vc9_co,
    mob_vc9_co_valid  => mob_link1.vc9_co_valid,
    mob_vc9_co_size   => mob_link1.vc9_co_size,
    mob_vc9_co_ready  => mob_link1.vc9_co_ready,
    mob_vc8_co        => mob_link1.vc8_co,
    mob_vc8_co_valid  => mob_link1.vc8_co_valid,
    mob_vc8_co_size   => mob_link1.vc8_co_size,
    mob_vc8_co_ready  => mob_link1.vc8_co_ready,
    mob_vc7_co        => mob_link1.vc7_co,
    mob_vc7_co_valid  => mob_link1.vc7_co_valid,
    mob_vc7_co_size   => mob_link1.vc7_co_size,
    mob_vc7_co_ready  => mob_link1.vc7_co_ready,
    mob_vc6_co        => mob_link1.vc6_co,
    mob_vc6_co_valid  => mob_link1.vc6_co_valid,
    mob_vc6_co_size   => mob_link1.vc6_co_size,
    mob_vc6_co_ready  => mob_link1.vc6_co_ready,
    -- VC 5 - 2
    mob_vc5_cd        => mob_link1.vc5_cd,
    mob_vc5_cd_valid  => mob_link1.vc5_cd_valid,
    mob_vc5_cd_size   => mob_link1.vc5_cd_size,
    mob_vc5_cd_ready  => mob_link1.vc5_cd_ready,
    mob_vc4_cd        => mob_link1.vc4_cd,
    mob_vc4_cd_valid  => mob_link1.vc4_cd_valid,
    mob_vc4_cd_size   => mob_link1.vc4_cd_size,
    mob_vc4_cd_ready  => mob_link1.vc4_cd_ready,
    mob_vc3_cd        => mob_link1.vc3_cd,
    mob_vc3_cd_valid  => mob_link1.vc3_cd_valid,
    mob_vc3_cd_size   => mob_link1.vc3_cd_size,
    mob_vc3_cd_ready  => mob_link1.vc3_cd_ready,
    mob_vc2_cd        => mob_link1.vc2_cd,
    mob_vc2_cd_valid  => mob_link1.vc2_cd_valid,
    mob_vc2_cd_size   => mob_link1.vc2_cd_size,
    mob_vc2_cd_ready  => mob_link1.vc2_cd_ready,
    -- MCD VC13
    mob_vc_mcd        => mob_link1.vc_mcd,
    mob_vc_mcd_valid  => mob_link1.vc_mcd_valid,
    mob_vc_mcd_ready  => mob_link1.vc_mcd_ready,

    mob_vc0_io         => mob_link1.vc0_io,
    mob_vc0_io_valid   => mob_link1.vc0_io_valid,
    mob_vc0_io_size    => mob_link1.vc0_io_size,
    mob_vc0_io_ready   => mob_link1.vc0_io_ready,

    mob_vc1_io         => mob_link1.vc1_io,
    mob_vc1_io_valid   => mob_link1.vc1_io_valid,
    mob_vc1_io_size    => mob_link1.vc1_io_size,
    mob_vc1_io_ready   => mob_link1.vc1_io_ready
);

-- Short-circuit CCPI forwarding.
eci_link1.rx_block_blk       <= eci_link1.rx_block;
eci_link1.rx_block_valid_blk <= eci_link1.rx_block_valid;

eci_link1.tx_block           <= eci_link1.tx_block_blk;
eci_link1.tx_block_ready_blk <= eci_link1.tx_block_ready;

eci_link2.rx_block_blk       <= eci_link2.rx_block;
eci_link2.rx_block_valid_blk <= eci_link2.rx_block_valid;

eci_link2.tx_block           <= eci_link2.tx_block_blk;
eci_link2.tx_block_ready_blk <= eci_link2.tx_block_ready;

i_eci_io_bridge : eci_io_bridge
generic map (
    SECOND_LINK_ACTIVE => 0
)
port map (
    clk => clk_sys,
    reset => reset,

    link1_mib_vc_mcd        => mib_link1.vc_mcd,
    link1_mib_vc_mcd_valid  => mib_link1.vc_mcd_valid,
    link1_mib_vc_mcd_ready  => mib_link1.vc_mcd_ready,

    link1_mib_vc0_io         => mib_link1.vc0_io,
    link1_mib_vc0_io_valid   => mib_link1.vc0_io_valid,
    link1_mib_vc0_io_word_enable    => mib_link1.vc0_io_word_enable,
    link1_mib_vc0_io_ready   => mib_link1.vc0_io_ready,

    link1_mib_vc1_io         => mib_link1.vc1_io,
    link1_mib_vc1_io_valid   => mib_link1.vc1_io_valid,
    link1_mib_vc1_io_word_enable    => mib_link1.vc1_io_word_enable,
    link1_mib_vc1_io_ready   => mib_link1.vc1_io_ready,

    link1_mob_vc_mcd        => mob_link1.vc_mcd,
    link1_mob_vc_mcd_valid  => mob_link1.vc_mcd_valid,
    link1_mob_vc_mcd_ready  => mob_link1.vc_mcd_ready,

    link1_mob_vc0_io         => mob_link1.vc0_io,
    link1_mob_vc0_io_valid   => mob_link1.vc0_io_valid,
    link1_mob_vc0_io_size    => mob_link1.vc0_io_size,
    link1_mob_vc0_io_ready   => mob_link1.vc0_io_ready,

    link1_mob_vc1_io         => mob_link1.vc1_io,
    link1_mob_vc1_io_valid   => mob_link1.vc1_io_valid,
    link1_mob_vc1_io_size    => mob_link1.vc1_io_size,
    link1_mob_vc1_io_ready   => mob_link1.vc1_io_ready,

    link2_mib_vc_mcd        => mib_link2.vc_mcd,
    link2_mib_vc_mcd_valid  => mib_link2.vc_mcd_valid,
    link2_mib_vc_mcd_ready  => mib_link2.vc_mcd_ready,

    link2_mib_vc0_io         => mib_link2.vc0_io,
    link2_mib_vc0_io_valid   => mib_link2.vc0_io_valid,
    link2_mib_vc0_io_word_enable    => mib_link2.vc0_io_word_enable,
    link2_mib_vc0_io_ready   => mib_link2.vc0_io_ready,

    link2_mib_vc1_io         => mib_link2.vc1_io,
    link2_mib_vc1_io_valid   => mib_link2.vc1_io_valid,
    link2_mib_vc1_io_word_enable    => mib_link2.vc1_io_word_enable,
    link2_mib_vc1_io_ready   => mib_link2.vc1_io_ready,

    link2_mob_vc_mcd        => mob_link2.vc_mcd,
    link2_mob_vc_mcd_valid  => mob_link2.vc_mcd_valid,
    link2_mob_vc_mcd_ready  => mob_link2.vc_mcd_ready,

    link2_mob_vc0_io         => mob_link2.vc0_io,
    link2_mob_vc0_io_valid   => mob_link2.vc0_io_valid,
    link2_mob_vc0_io_size    => mob_link2.vc0_io_size,
    link2_mob_vc0_io_ready   => mob_link2.vc0_io_ready,

    link2_mob_vc1_io         => mob_link2.vc1_io,
    link2_mob_vc1_io_valid   => mob_link2.vc1_io_valid,
    link2_mob_vc1_io_size    => mob_link2.vc1_io_size,
    link2_mob_vc1_io_ready   => mob_link2.vc1_io_ready,

    -- AXI Lite master interface for IO addr space
    m_io_axil_awaddr  => io_axil_link_awaddr,
    m_io_axil_awvalid => io_axil_link_awvalid,
    m_io_axil_awready => io_axil_link_awready,
    m_io_axil_wdata   => io_axil_link_wdata,
    m_io_axil_wstrb   => io_axil_link_wstrb,
    m_io_axil_wvalid  => io_axil_link_wvalid,
    m_io_axil_wready  => io_axil_link_wready,
    m_io_axil_bresp   => io_axil_link_bresp,
    m_io_axil_bvalid  => io_axil_link_bvalid,
    m_io_axil_bready  => io_axil_link_bready,
    m_io_axil_araddr  => io_axil_link_araddr,
    m_io_axil_arvalid => io_axil_link_arvalid,
    m_io_axil_arready => io_axil_link_arready,
    m_io_axil_rdata   => io_axil_link_rdata,
    m_io_axil_rresp   => io_axil_link_rresp,
    m_io_axil_rvalid  => io_axil_link_rvalid,
    m_io_axil_rready  => io_axil_link_rready
);

link1_packet_serialiser : eci_pkt_vc_router
port map (
   clk => clk_sys,
   reset => reset,

   -- Input ECI packets to corresponding VCs from dir controller
   -- VC11 - VC2 (VC1,0 are not handled here)

   -- Send nothing on the unused channels.

   -- ECI packet Outgoing response without data VC 11,10
   -- Note: no data sends only header
   -- Who cares 
   dc11_eci_hdr_i       => link1_eci_packet_tx.c11_eci_pkt_tx,
   dc11_eci_pkt_size_i  => link1_eci_packet_tx.c11_eci_pkt_size_tx,
   dc11_eci_pkt_valid_i => link1_eci_packet_tx.c11_eci_pkt_valid_tx,
   dc11_eci_pkt_ready_o => link1_eci_packet_tx.c11_eci_pkt_ready_tx,

   dc10_eci_hdr_i       => link1_eci_packet_tx.c10_eci_pkt_tx,
   dc10_eci_pkt_size_i  => link1_eci_packet_tx.c10_eci_pkt_size_tx,
   dc10_eci_pkt_valid_i => link1_eci_packet_tx.c10_eci_pkt_valid_tx,
   dc10_eci_pkt_ready_o => link1_eci_packet_tx.c10_eci_pkt_ready_tx,

   -- ECI packet outgoing forwareds without data VC 9,8
   dc9_eci_hdr_i       => (others => '0'),
   dc9_eci_pkt_size_i  => (others => '0'),
   dc9_eci_pkt_valid_i => '0',
   dc9_eci_pkt_ready_o => open,

   dc8_eci_hdr_i       => (others => '0'),
   dc8_eci_pkt_size_i  => (others => '0'),
   dc8_eci_pkt_valid_i => '0',
   dc8_eci_pkt_ready_o => open,

   -- ECI packet outgoing requests without data VC 7,6
   -- RD requests
   dc7_eci_hdr_i       => link1_eci_packet_tx.c7_eci_pkt_tx,
   dc7_eci_pkt_size_i  => link1_eci_packet_tx.c7_eci_pkt_size_tx,
   dc7_eci_pkt_valid_i => link1_eci_packet_tx.c7_eci_pkt_valid_tx,
   dc7_eci_pkt_ready_o => link1_eci_packet_tx.c7_eci_pkt_ready_tx,

   dc6_eci_hdr_i       => link1_eci_packet_tx.c6_eci_pkt_tx,
   dc6_eci_pkt_size_i  => link1_eci_packet_tx.c6_eci_pkt_size_tx,
   dc6_eci_pkt_valid_i => link1_eci_packet_tx.c6_eci_pkt_valid_tx,
   dc6_eci_pkt_ready_o => link1_eci_packet_tx.c6_eci_pkt_ready_tx,

   -- ECI packet outgoing responses with data VC 5,4
   -- header+payload
   dc5_eci_pkt_i       => link1_eci_packet_tx.c5_eci_pkt_tx,
   dc5_eci_pkt_size_i  => link1_eci_packet_tx.c5_eci_pkt_size_tx,
   dc5_eci_pkt_valid_i => link1_eci_packet_tx.c5_eci_pkt_valid_tx,
   dc5_eci_pkt_ready_o => link1_eci_packet_tx.c5_eci_pkt_ready_tx,

   dc4_eci_pkt_i       => link1_eci_packet_tx.c4_eci_pkt_tx,
   dc4_eci_pkt_size_i  => link1_eci_packet_tx.c4_eci_pkt_size_tx,
   dc4_eci_pkt_valid_i => link1_eci_packet_tx.c4_eci_pkt_valid_tx,
   dc4_eci_pkt_ready_o => link1_eci_packet_tx.c4_eci_pkt_ready_tx,

   -- ECI packet outgoing requests with data VC 3,2
   -- header+payload
   -- WR requests
   dc3_eci_pkt_i       => link1_eci_packet_tx.c3_eci_pkt_tx,
   dc3_eci_pkt_size_i  => link1_eci_packet_tx.c3_eci_pkt_size_tx,
   dc3_eci_pkt_valid_i => link1_eci_packet_tx.c3_eci_pkt_valid_tx,
   dc3_eci_pkt_ready_o => link1_eci_packet_tx.c3_eci_pkt_ready_tx,

   dc2_eci_pkt_i       => link1_eci_packet_tx.c2_eci_pkt_tx,
   dc2_eci_pkt_size_i  => link1_eci_packet_tx.c2_eci_pkt_size_tx,
   dc2_eci_pkt_valid_i => link1_eci_packet_tx.c2_eci_pkt_valid_tx,
   dc2_eci_pkt_ready_o => link1_eci_packet_tx.c2_eci_pkt_ready_tx,

   -- Input ECI packets from special handlers
   -- GSDN for GSYNC
   gsdn11_hdr_i   => link1_eci_packet_tx.c11_gsync_hdr_tx,
   gsdn11_valid_i => link1_eci_packet_tx.c11_gsync_valid_tx,
   gsdn11_ready_o => link1_eci_packet_tx.c11_gsync_ready_tx,

   gsdn10_hdr_i   => link1_eci_packet_tx.c10_gsync_hdr_tx,
   gsdn10_valid_i => link1_eci_packet_tx.c10_gsync_valid_tx,
   gsdn10_ready_o => link1_eci_packet_tx.c10_gsync_ready_tx,

   -- Output VC packets generated by the FPGA
   -- VC11 - VC2 (VC1,0 are not handled here)

   -- VC packet Outgoing response without data VC 11,10
   -- Note: no data sends only header
   f11_vc_pkt_o       => mob_link1.vc11_co,
   f11_vc_pkt_size_o  => mob_link1.vc11_co_size,
   f11_vc_pkt_valid_o => mob_link1.vc11_co_valid,
   f11_vc_pkt_ready_i => mob_link1.vc11_co_ready,

   f10_vc_pkt_o       => mob_link1.vc10_co,
   f10_vc_pkt_size_o  => mob_link1.vc10_co_size,
   f10_vc_pkt_valid_o => mob_link1.vc10_co_valid,
   f10_vc_pkt_ready_i => mob_link1.vc10_co_ready,

   -- Incoming Forwards VC 9,8
   -- Forwards are command only no data, currently not connected
   f9_vc_pkt_o       => mob_link1.vc9_co,
   f9_vc_pkt_size_o  => mob_link1.vc9_co_size,
   f9_vc_pkt_valid_o => mob_link1.vc9_co_valid,
   f9_vc_pkt_ready_i => mob_link1.vc9_co_ready,

   f8_vc_pkt_o       => mob_link1.vc8_co,
   f8_vc_pkt_size_o  => mob_link1.vc8_co_size,
   f8_vc_pkt_valid_o => mob_link1.vc8_co_valid,
   f8_vc_pkt_ready_i => mob_link1.vc8_co_ready,

   -- Incoming requests without data VC 7,6
   f7_vc_pkt_o       => mob_link1.vc7_co,
   f7_vc_pkt_size_o  => mob_link1.vc7_co_size,
   f7_vc_pkt_valid_o => mob_link1.vc7_co_valid,
   f7_vc_pkt_ready_i => mob_link1.vc7_co_ready,

   f6_vc_pkt_o       => mob_link1.vc6_co,
   f6_vc_pkt_size_o  => mob_link1.vc6_co_size,
   f6_vc_pkt_valid_o => mob_link1.vc6_co_valid,
   f6_vc_pkt_ready_i => mob_link1.vc6_co_ready,

   -- Incoming resoponse with data VC 5,4
   f5_vc_pkt_o       => mob_link1.vc5_cd,
   f5_vc_pkt_size_o  => mob_link1.vc5_cd_size,
   f5_vc_pkt_valid_o => mob_link1.vc5_cd_valid,
   f5_vc_pkt_ready_i => mob_link1.vc5_cd_ready,

   f4_vc_pkt_o       => mob_link1.vc4_cd,
   f4_vc_pkt_size_o  => mob_link1.vc4_cd_size,
   f4_vc_pkt_valid_o => mob_link1.vc4_cd_valid,
   f4_vc_pkt_ready_i => mob_link1.vc4_cd_ready,

   -- Incoming request with data VC 3,2
   f3_vc_pkt_o       => mob_link1.vc3_cd,
   f3_vc_pkt_size_o  => mob_link1.vc3_cd_size,
   f3_vc_pkt_valid_o => mob_link1.vc3_cd_valid,
   f3_vc_pkt_ready_i => mob_link1.vc3_cd_ready,

   f2_vc_pkt_o       => mob_link1.vc2_cd,
   f2_vc_pkt_size_o  => mob_link1.vc2_cd_size,
   f2_vc_pkt_valid_o => mob_link1.vc2_cd_valid,
   f2_vc_pkt_ready_i => mob_link1.vc2_cd_ready
);

link1_packet_deserialiser : vc_eci_pkt_router
port map (
    clk => clk_sys,
    reset => reset,

    -- Incoming CPU to FPGA events (MIB VCs) c_ -> CPU initated events
    -- VC11 to VC2 (VC1, VC0) are IO VCs not handled here
    -- Incoming response without data VC 11,10
    c11_vc_pkt_i       => mib_link1.vc11_co,
    c11_vc_pkt_word_enable_i  => mib_link1.vc11_co_word_enable,
    c11_vc_pkt_valid_i => mib_link1.vc11_co_valid,
    c11_vc_pkt_ready_o => mib_link1.vc11_co_ready,

    c10_vc_pkt_i       => mib_link1.vc10_co,
    c10_vc_pkt_word_enable_i  => mib_link1.vc10_co_word_enable,
    c10_vc_pkt_valid_i => mib_link1.vc10_co_valid,
    c10_vc_pkt_ready_o => mib_link1.vc10_co_ready,

    -- Incoming Forwards VC 9,8
    -- Forwards are command only no data, currently not connected
    c9_vc_pkt_i       => mib_link1.vc9_co,
    c9_vc_pkt_word_enable_i  => mib_link1.vc9_co_word_enable,
    c9_vc_pkt_valid_i => mib_link1.vc9_co_valid,
    c9_vc_pkt_ready_o => mib_link1.vc9_co_ready,

    c8_vc_pkt_i       => mib_link1.vc8_co,
    c8_vc_pkt_word_enable_i  => mib_link1.vc8_co_word_enable,
    c8_vc_pkt_valid_i => mib_link1.vc8_co_valid,
    c8_vc_pkt_ready_o => mib_link1.vc8_co_ready,

   -- Incoming requests without data VC 7,6
    c7_vc_pkt_i       => mib_link1.vc7_co,
    c7_vc_pkt_word_enable_i  => mib_link1.vc7_co_word_enable,
    c7_vc_pkt_valid_i => mib_link1.vc7_co_valid,
    c7_vc_pkt_ready_o => mib_link1.vc7_co_ready,

    c6_vc_pkt_i       => mib_link1.vc6_co,
    c6_vc_pkt_word_enable_i  => mib_link1.vc6_co_word_enable,
    c6_vc_pkt_valid_i => mib_link1.vc6_co_valid,
    c6_vc_pkt_ready_o => mib_link1.vc6_co_ready,

    -- Incoming resoponse with data VC 5,4
    c5_vc_pkt_i       => mib_link1.vc5_cd,
    c5_vc_pkt_word_enable_i  => mib_link1.vc5_cd_word_enable,
    c5_vc_pkt_valid_i => mib_link1.vc5_cd_valid,
    c5_vc_pkt_ready_o => mib_link1.vc5_cd_ready,

    c4_vc_pkt_i       => mib_link1.vc4_cd,
    c4_vc_pkt_word_enable_i  => mib_link1.vc4_cd_word_enable,
    c4_vc_pkt_valid_i => mib_link1.vc4_cd_valid,
    c4_vc_pkt_ready_o => mib_link1.vc4_cd_ready,

    -- Incoming request with data VC 3,2
    c3_vc_pkt_i       => mib_link1.vc3_cd,
    c3_vc_pkt_word_enable_i  => mib_link1.vc3_cd_word_enable,
    c3_vc_pkt_valid_i => mib_link1.vc3_cd_valid,
    c3_vc_pkt_ready_o => mib_link1.vc3_cd_ready,

    c2_vc_pkt_i       => mib_link1.vc2_cd,
    c2_vc_pkt_word_enable_i  => mib_link1.vc2_cd_word_enable,
    c2_vc_pkt_valid_i => mib_link1.vc2_cd_valid,
    c2_vc_pkt_ready_o => mib_link1.vc2_cd_ready,

    -- ECI packets corresponding to the VCs holding CPU initiated events
    -- ECI packets for VC 11 - 2 (VC1,0 are IO VCs not handled here)

    -- All VCs other than request without data (6,7 i.e. reads) are just
    -- allowed to drain.

    -- ECI packet for CPU initiated response without data VC 11,10
    -- No payload only header
    -- WR responses
    c11_eci_hdr_o       => link1_eci_packet_rx.c11_eci_hdr_rx,
    c11_eci_pkt_size_o  => link1_eci_packet_rx.c11_eci_pkt_size_rx,
    c11_eci_pkt_vc_o    => link1_eci_packet_rx.c11_eci_pkt_vc_rx,
    c11_eci_pkt_valid_o => link1_eci_packet_rx.c11_eci_pkt_valid_rx,
    c11_eci_pkt_ready_i => link1_eci_packet_rx.c11_eci_pkt_ready_rx,

    c10_eci_hdr_o       => link1_eci_packet_rx.c10_eci_hdr_rx,
    c10_eci_pkt_size_o  => link1_eci_packet_rx.c10_eci_pkt_size_rx,
    c10_eci_pkt_vc_o    => link1_eci_packet_rx.c10_eci_pkt_vc_rx,
    c10_eci_pkt_valid_o => link1_eci_packet_rx.c10_eci_pkt_valid_rx,
    c10_eci_pkt_ready_i => link1_eci_packet_rx.c10_eci_pkt_ready_rx,

    -- ECI packet for CPU initiated forwards VC 9,8
    -- No payload only header
    c9_eci_hdr_o       => open,
    c9_eci_pkt_size_o  => open,
    c9_eci_pkt_vc_o    => open,
    c9_eci_pkt_valid_o => open,
    c9_eci_pkt_ready_i => '1',

    c8_eci_hdr_o       => open,
    c8_eci_pkt_size_o  => open,
    c8_eci_pkt_vc_o    => open,
    c8_eci_pkt_valid_o => open,
    c8_eci_pkt_ready_i => '1',

    -- ECI packet for CPU initiated request without data VC 7,6
    -- No payload only header
    c7_eci_hdr_o       => link1_eci_packet_rx.c7_eci_hdr_rx,
    c7_eci_pkt_size_o  => link1_eci_packet_rx.c7_eci_pkt_size_rx,
    c7_eci_pkt_vc_o    => link1_eci_packet_rx.c7_eci_pkt_vc_rx,
    c7_eci_pkt_valid_o => link1_eci_packet_rx.c7_eci_pkt_valid_rx,
    c7_eci_pkt_ready_i => link1_eci_packet_rx.c7_eci_pkt_ready_rx,

    c6_eci_hdr_o       => link1_eci_packet_rx.c6_eci_hdr_rx,
    c6_eci_pkt_size_o  => link1_eci_packet_rx.c6_eci_pkt_size_rx,
    c6_eci_pkt_vc_o    => link1_eci_packet_rx.c6_eci_pkt_vc_rx,
    c6_eci_pkt_valid_o => link1_eci_packet_rx.c6_eci_pkt_valid_rx,
    c6_eci_pkt_ready_i => link1_eci_packet_rx.c6_eci_pkt_ready_rx,

    -- ECI packet for CPU initiated response with data VC 5,4
    -- Header + payload
    -- RD responses
    c5_eci_pkt_o       => link1_eci_packet_rx.c5_eci_hdr_rx,
    c5_eci_pkt_size_o  => link1_eci_packet_rx.c5_eci_pkt_size_rx,
    c5_eci_pkt_vc_o    => link1_eci_packet_rx.c5_eci_pkt_vc_rx,
    c5_eci_pkt_valid_o => link1_eci_packet_rx.c5_eci_pkt_valid_rx,
    c5_eci_pkt_ready_i => link1_eci_packet_rx.c5_eci_pkt_ready_rx,

    c4_eci_pkt_o       => link1_eci_packet_rx.c4_eci_hdr_rx,
    c4_eci_pkt_size_o  => link1_eci_packet_rx.c4_eci_pkt_size_rx,
    c4_eci_pkt_vc_o    => link1_eci_packet_rx.c4_eci_pkt_vc_rx,
    c4_eci_pkt_valid_o => link1_eci_packet_rx.c4_eci_pkt_valid_rx,
    c4_eci_pkt_ready_i => link1_eci_packet_rx.c4_eci_pkt_ready_rx,

    -- ECI packet for CPU initiated requests with data VC 3,2
    c3_eci_pkt_o       => open,
    c3_eci_pkt_size_o  => open,
    c3_eci_pkt_vc_o    => open,
    c3_eci_pkt_valid_o => open,
    c3_eci_pkt_ready_i => '1',

    c2_eci_pkt_o       => open,
    c2_eci_pkt_size_o  => open,
    c2_eci_pkt_vc_o    => open,
    c2_eci_pkt_valid_o => open,
    c2_eci_pkt_ready_i => '1',

    -- VC 1,0 are IO VCs, not handled here

    -- Special Handlers
    -- GSYNC from VC7,6 (req without data)
    c7_gsync_hdr_o   => link1_eci_packet_rx.c7_gsync_hdr_rx,
    c7_gsync_valid_o => link1_eci_packet_rx.c7_gsync_valid_rx,
    c7_gsync_ready_i => link1_eci_packet_rx.c7_gsync_ready_rx,

    c6_gsync_hdr_o   => link1_eci_packet_rx.c6_gsync_hdr_rx,
    c6_gsync_valid_o => link1_eci_packet_rx.c6_gsync_valid_rx,
    c6_gsync_ready_i => link1_eci_packet_rx.c6_gsync_ready_rx
);

link1_vc7_vc11_gsync_loopback : loopback_vc_resp_nodata
generic map (
   WORD_WIDTH => 64,
   GSDN_GSYNC_FN => 1
)
port map (
    clk   => clk_sys,
    reset => reset,

    vc_req_i       => link1_eci_packet_rx.c7_gsync_hdr_rx,
    vc_req_valid_i => link1_eci_packet_rx.c7_gsync_valid_rx,
    vc_req_ready_o => link1_eci_packet_rx.c7_gsync_ready_rx,

    vc_resp_o       => link1_eci_packet_tx.c11_gsync_hdr_tx,
    vc_resp_valid_o => link1_eci_packet_tx.c11_gsync_valid_tx,
    vc_resp_ready_i => link1_eci_packet_tx.c11_gsync_ready_tx
);

link1_vc6_vc10_gsync_loopback : loopback_vc_resp_nodata
generic map (
   WORD_WIDTH => 64,
   GSDN_GSYNC_FN => 1
)
port map (
    clk   => clk_sys,
    reset => reset,

    vc_req_i       => link1_eci_packet_rx.c6_gsync_hdr_rx,
    vc_req_valid_i => link1_eci_packet_rx.c6_gsync_valid_rx,
    vc_req_ready_o => link1_eci_packet_rx.c6_gsync_ready_rx,

    vc_resp_o       => link1_eci_packet_tx.c10_gsync_hdr_tx,
    vc_resp_valid_o => link1_eci_packet_tx.c10_gsync_valid_tx,
    vc_resp_ready_i => link1_eci_packet_tx.c10_gsync_ready_tx
);

--
-- TOP ORDERING LAYER
--
-- ECI - FPGA 
eci_co_cd_top0 : eci_co_cd_top_c
port map (
    clk   => clk_sys,
    reset => reset,

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
    f_vc7_co_o        => link1_eci_packet_tx.c7_eci_pkt_tx, 
    f_vc7_co_valid_o  => link1_eci_packet_tx.c7_eci_pkt_valid_tx, 
    f_vc7_co_size_o   => link1_eci_packet_tx.c7_eci_pkt_size_tx, 
    f_vc7_co_ready_i  => link1_eci_packet_tx.c7_eci_pkt_ready_tx,

    f_vc6_co_o        => link1_eci_packet_tx.c6_eci_pkt_tx, 
    f_vc6_co_valid_o  => link1_eci_packet_tx.c6_eci_pkt_valid_tx, 
    f_vc6_co_size_o   => link1_eci_packet_tx.c6_eci_pkt_size_tx, 
    f_vc6_co_ready_i  => link1_eci_packet_tx.c6_eci_pkt_ready_tx,

    f_vc3_cd_o        => link1_eci_packet_tx.c3_eci_pkt_tx, 
    f_vc3_cd_valid_o  => link1_eci_packet_tx.c3_eci_pkt_valid_tx, 
    f_vc3_cd_size_o   => link1_eci_packet_tx.c3_eci_pkt_size_tx, 
    f_vc3_cd_ready_i  => link1_eci_packet_tx.c3_eci_pkt_ready_tx,

    f_vc2_cd_o        => link1_eci_packet_tx.c2_eci_pkt_tx, 
    f_vc2_cd_valid_o  => link1_eci_packet_tx.c2_eci_pkt_valid_tx, 
    f_vc2_cd_size_o   => link1_eci_packet_tx.c2_eci_pkt_size_tx, 
    f_vc2_cd_ready_i  => link1_eci_packet_tx.c2_eci_pkt_ready_tx,

    -- Input from MIB of ECI module
    c_vc11_co_i       => link1_eci_packet_rx.c11_eci_hdr_rx, 
    c_vc11_co_valid_i => link1_eci_packet_rx.c11_eci_pkt_valid_rx, 
    c_vc11_co_size_i  => link1_eci_packet_rx.c11_eci_pkt_size_rx, 
    c_vc11_co_ready_o => link1_eci_packet_rx.c11_eci_pkt_ready_rx,

    c_vc10_co_i       => link1_eci_packet_rx.c10_eci_hdr_rx, 
    c_vc10_co_valid_i => link1_eci_packet_rx.c10_eci_pkt_valid_rx, 
    c_vc10_co_size_i  => link1_eci_packet_rx.c10_eci_pkt_size_rx, 
    c_vc10_co_ready_o => link1_eci_packet_rx.c10_eci_pkt_ready_rx, 
    
    c_vc5_cd_i        => link1_eci_packet_rx.c5_eci_hdr_rx, 
    c_vc5_cd_valid_i  => link1_eci_packet_rx.c5_eci_pkt_valid_rx, 
    c_vc5_cd_size_i   => link1_eci_packet_rx.c5_eci_pkt_size_rx, 
    c_vc5_cd_ready_o  => link1_eci_packet_rx.c5_eci_pkt_ready_rx,
    
    c_vc4_cd_i        => link1_eci_packet_rx.c4_eci_hdr_rx, 
    c_vc4_cd_valid_i  => link1_eci_packet_rx.c4_eci_pkt_valid_rx, 
    c_vc4_cd_size_i   => link1_eci_packet_rx.c4_eci_pkt_size_rx, 
    c_vc4_cd_ready_o  => link1_eci_packet_rx.c4_eci_pkt_ready_rx 
);

end behavioural;
