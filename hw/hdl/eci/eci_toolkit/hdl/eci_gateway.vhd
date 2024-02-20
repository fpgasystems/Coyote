----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- ECI gateway
-- Process incoming ECI frames and route messages to the specific ECI channels
-- Multiplex outgoing ECI channels into 4 streams (2 links * (1 hi bandwidth + 1 lo bandwidth streams))
-- Instantiates:
-- Clocks buffers
-- Reset and link up handling
-- BSCAN debug bridge

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_gateway is
generic (
    RX_CROSSBAR_TYPE    : string := "full"; -- or "lite"
    LOW_LATENCY         : boolean := false; -- favour latency over resource usage and routability
    DEBUG_BRIDGE_PRESENT: boolean := true;
    TX_NO_CHANNELS      : integer;
    RX_NO_CHANNELS      : integer;
    RX_FILTER_VC        : VC_BITFIELDS;
    RX_FILTER_TYPE_MASK : ECI_TYPE_MASKS;
    RX_FILTER_TYPE      : ECI_TYPE_MASKS;
    RX_FILTER_CLI_MASK  : CLI_ARRAY;
    RX_FILTER_CLI       : CLI_ARRAY
);
port (
    clk_sys                 : in std_logic;
    clk_io_out              : out std_logic;
    clk_prgc0_out           : out std_logic;
    clk_prgc1_out           : out std_logic;

    prgc0_clk_p             : in std_logic;
    prgc0_clk_n             : in std_logic;
    prgc1_clk_p             : in std_logic;
    prgc1_clk_n             : in std_logic;

    reset_sys               : in std_logic;
    reset_out               : out std_logic;
    reset_n_out             : out std_logic;
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

    s_bscan_bscanid_en      : in std_logic;
    s_bscan_capture         : in std_logic;
    s_bscan_drck            : in std_logic;
    s_bscan_reset           : in std_logic;
    s_bscan_runtest         : in std_logic;
    s_bscan_sel             : in std_logic;
    s_bscan_shift           : in std_logic;
    s_bscan_tck             : in std_logic;
    s_bscan_tdi             : in std_logic;
    s_bscan_tdo             : out std_logic;
    s_bscan_tms             : in std_logic;
    s_bscan_update          : in std_logic;

    m0_bscan_bscanid_en     : out std_logic;
    m0_bscan_capture        : out std_logic;
    m0_bscan_drck           : out std_logic;
    m0_bscan_reset          : out std_logic;
    m0_bscan_runtest        : out std_logic;
    m0_bscan_sel            : out std_logic;
    m0_bscan_shift          : out std_logic;
    m0_bscan_tck            : out std_logic;
    m0_bscan_tdi            : out std_logic;
    m0_bscan_tdo            : in std_logic;
    m0_bscan_tms            : out std_logic;
    m0_bscan_update         : out std_logic;

    rx_eci_channels         : out ARRAY_ECI_CHANNELS(RX_NO_CHANNELS-1 downto 0);
    rx_eci_channels_ready   : in std_logic_vector(RX_NO_CHANNELS-1 downto 0);

    tx_eci_channels         : in ARRAY_ECI_CHANNELS(TX_NO_CHANNELS-1 downto 0);
    tx_eci_channels_ready   : out std_logic_vector(TX_NO_CHANNELS-1 downto 0)
);
end eci_gateway;

architecture Behavioral of eci_gateway is

component debug_bridge_dynamic is
port (
    clk : in std_logic;
    s_bscan_bscanid_en : in std_logic;
    s_bscan_capture : in std_logic;
    s_bscan_drck : in std_logic;
    s_bscan_reset : in std_logic;
    s_bscan_runtest : in std_logic;
    s_bscan_sel : in std_logic;
    s_bscan_shift : in std_logic;
    s_bscan_tck : in std_logic;
    s_bscan_tdi : in std_logic;
    s_bscan_tdo : out std_logic;
    s_bscan_tms : in std_logic;
    s_bscan_update : in std_logic;
    m0_bscan_bscanid_en : out std_logic;
    m0_bscan_capture : out std_logic;
    m0_bscan_drck : out std_logic;
    m0_bscan_reset : out std_logic;
    m0_bscan_runtest : out std_logic;
    m0_bscan_sel : out std_logic;
    m0_bscan_shift : out std_logic;
    m0_bscan_tck : out std_logic;
    m0_bscan_tdi : out std_logic;
    m0_bscan_tdo : in std_logic;
    m0_bscan_tms : out std_logic;
    m0_bscan_update : out std_logic
);
end component;

-- full version with separate VCs (11 separate inputs to the RX crossbar)
component eci_link_rx is
generic (
    LOW_LATENCY             : boolean
);
port (
    clk                     : in std_logic;
    link_up                 : in std_logic;
    link_in_data            : in std_logic_vector(447 downto 0);
    link_in_vc_no           : in std_logic_vector(27 downto 0);
    link_in_we2             : in std_logic_vector(6 downto 0);
    link_in_we3             : in std_logic_vector(6 downto 0);
    link_in_we4             : in std_logic_vector(6 downto 0);
    link_in_we5             : in std_logic_vector(6 downto 0);
    link_in_valid           : in std_logic;
    link_in_credit_return   : out std_logic_vector(12 downto 2);

    link                    : out ARRAY_ECI_CHANNELS(12 downto 2);
    link_ready              : in std_logic_vector(12 downto 2)
);
end component;

component eci_rx_crossbar is
generic (
    CHANNELS            : integer;
    filter_vc           : VC_BITFIELDS;
    filter_type_mask    : ECI_TYPE_MASKS;
    filter_type         : ECI_TYPE_MASKS;
    filter_cli_mask     : CLI_ARRAY;
    filter_cli          : CLI_ARRAY
);
port (
    clk                 : in std_logic;

    link1               : in ARRAY_ECI_CHANNELS(12 downto 2);
    link1_ready         : out std_logic_vector(12 downto 2);
    link2               : in ARRAY_ECI_CHANNELS(12 downto 2);
    link2_ready         : out std_logic_vector(12 downto 2);

    out_channels        : out ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
    out_channels_ready  : in std_logic_vector(CHANNELS-1 downto 0)
);
end component;

-- lite version with combined VCs (3 combined inputs to the RX crossbar to reduce latency and cell usage)
component eci_link_rx_lite is
generic (
    LOW_LATENCY             : boolean
);
port (
    clk                     : in std_logic;
    link_up                 : in std_logic;
    link_in_data            : in std_logic_vector(447 downto 0);
    link_in_vc_no           : in std_logic_vector(27 downto 0);
    link_in_we2             : in std_logic_vector(6 downto 0);
    link_in_we3             : in std_logic_vector(6 downto 0);
    link_in_we4             : in std_logic_vector(6 downto 0);
    link_in_we5             : in std_logic_vector(6 downto 0);
    link_in_valid           : in std_logic;
    link_in_credit_return   : out std_logic_vector(12 downto 2);

    link_hi                 : out ECI_CHANNEL;
    link_hi_ready           : in std_logic;
    link_lo_even            : out ECI_CHANNEL;
    link_lo_even_ready      : in std_logic;
    link_lo_odd             : out ECI_CHANNEL;
    link_lo_odd_ready       : in std_logic
);
end component;

component eci_rx_crossbar_lite is
generic (
    CHANNELS            : integer;
    filter_vc           : VC_BITFIELDS;
    filter_type_mask    : ECI_TYPE_MASKS;
    filter_type         : ECI_TYPE_MASKS;
    filter_cli_mask     : CLI_ARRAY;
    filter_cli          : CLI_ARRAY
);
port (
    clk                 : in std_logic;

    link1_hi            : in ECI_CHANNEL;
    link1_hi_ready      : out std_logic;

    link1_lo_even       : in ECI_CHANNEL;
    link1_lo_even_ready : out std_logic;

    link1_lo_odd        : in ECI_CHANNEL;
    link1_lo_odd_ready  : out std_logic;

    link2_hi            : in ECI_CHANNEL;
    link2_hi_ready      : out std_logic;

    link2_lo_even       : in ECI_CHANNEL;
    link2_lo_even_ready : out std_logic;

    link2_lo_odd        : in ECI_CHANNEL;
    link2_lo_odd_ready  : out std_logic;

    out_channels        : out ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
    out_channels_ready  : in std_logic_vector(CHANNELS-1 downto 0)
);
end component;

component eci_packet_rx_mux is
generic (
    WIDTH           : integer
);
port (
    clk             : in std_logic;
    link1_data      : in std_logic_vector(WIDTH-1 downto 0);
    link1_valid     : in std_logic;
    link1_ready     : out std_logic;
    link2_data      : in std_logic_vector(WIDTH-1 downto 0);
    link2_valid     : in std_logic;
    link2_ready     : out std_logic;
    output_data     : out std_logic_vector(WIDTH-1 downto 0);
    output_valid    : out std_logic;
    output_ready    : in std_logic
);
end component eci_packet_rx_mux;

component eci_tx_crossbar is
generic (
    CHANNELS    : integer
);
port (
    clk                 : in STD_LOGIC;

    in_channels         : in ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
    in_channels_ready   : out std_logic_vector(CHANNELS-1 downto 0);

    link1_hi            : out ECI_CHANNEL;
    link1_hi_ready      : in STD_LOGIC;
    link2_hi            : out ECI_CHANNEL;
    link2_hi_ready      : in STD_LOGIC;
    link1_lo            : out ECI_CHANNEL;
    link1_lo_ready      : in STD_LOGIC;
    link2_lo            : out ECI_CHANNEL;
    link2_lo_ready      : in STD_LOGIC
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

component eci_channel_buffer is
generic (
    FULL    : boolean := true
);
port (
    clk             : in STD_LOGIC;
    input           : in ECI_CHANNEL;
    input_ready     : out STD_LOGIC;
    output          : out ECI_CHANNEL;
    output_ready    : in STD_LOGIC
);
end component;

signal clk          : std_logic;
signal clk_io, clk_io_u : std_logic;
signal reset        : std_logic;
signal reset_n      : std_logic;
signal reset_u      : std_logic;
signal reset_n_u    : std_logic;
signal link_up      : std_logic;

signal link1                    : ARRAY_ECI_CHANNELS(12 downto 2);
signal link1_ready              : std_logic_vector(12 downto 2);
signal link2                    : ARRAY_ECI_CHANNELS(12 downto 2);
signal link2_ready              : std_logic_vector(12 downto 2);

signal link1_out_cred_hi        : ECI_CHANNEL;
signal link1_out_cred_hi_ready  : std_logic;
signal link1_out_cred_lo        : ECI_CHANNEL;
signal link1_out_cred_lo_ready  : std_logic;

signal link2_out_cred_hi        : ECI_CHANNEL;
signal link2_out_cred_hi_ready  : std_logic;
signal link2_out_cred_lo        : ECI_CHANNEL;
signal link2_out_cred_lo_ready  : std_logic;

signal link1_out_buf_hi        : ECI_CHANNEL;
signal link1_out_buf_hi_ready  : std_logic;
signal link1_out_buf_lo        : ECI_CHANNEL;
signal link1_out_buf_lo_ready  : std_logic;

signal link2_out_buf_hi        : ECI_CHANNEL;
signal link2_out_buf_hi_ready  : std_logic;
signal link2_out_buf_lo        : ECI_CHANNEL;
signal link2_out_buf_lo_ready  : std_logic;

-- We need them to have a proper port mapping with records, looks like a Vivado bug
signal link1_out_lo_data_unused : WORDS(8 downto 1);
signal link1_out_lo_size_unused : std_logic_vector(2 downto 0);
signal link2_out_lo_data_unused : WORDS(8 downto 1);
signal link2_out_lo_size_unused : std_logic_vector(2 downto 0);

signal tx_eci_channels_ready_b   : std_logic_vector(TX_NO_CHANNELS-1 downto 0);

-- 300MHz clock
signal clk_prgc1 : std_logic;
attribute dont_touch : string;
attribute dont_touch of clk_prgc1 : signal is "true";

begin

tx_eci_channels_ready <= tx_eci_channels_ready_b;

clk <= clk_sys;
reset_out <= reset;
reset_n_out <= reset_n;
link_up <= link1_up and link2_up;

process_reset : process(clk)
begin
    if rising_edge(clk) then
        reset_u <= reset_sys;
    end if;
end process;

i_reset_bufg : BUFG
port map (
    I   => reset_u,
    O   => reset
);
reset_n <= not reset;

-- 100MHz io clock
i_prgc0 : IBUFDS
port map (
    I   => prgc0_clk_p,
    IB  => prgc0_clk_n,
    O   => clk_io_u
);
clk_prgc0_out <= clk_io_u;

-- 300MHz clock buffer stub
i_prgc1 : IBUFDS
port map (
    I   => prgc1_clk_p,
    IB  => prgc1_clk_n,
    O   => clk_prgc1
);
clk_prgc1_out <= clk_prgc1;

i_clk_io_bufg : BUFG
port map (
    I   => clk_io_u,
    O   => clk_io
);

clk_io_out <= clk_io;

gen_debug_bridge : if DEBUG_BRIDGE_PRESENT generate
i_debug_bridge : debug_bridge_dynamic
PORT map (
    clk                 => clk_io,
    s_bscan_bscanid_en  => s_bscan_bscanid_en,
    s_bscan_capture     => s_bscan_capture,
    s_bscan_drck        => s_bscan_drck,
    s_bscan_reset       => s_bscan_reset,
    s_bscan_runtest     => s_bscan_runtest,
    s_bscan_sel         => s_bscan_sel,
    s_bscan_shift       => s_bscan_shift,
    s_bscan_tck         => s_bscan_tck,
    s_bscan_tdi         => s_bscan_tdi,
    s_bscan_tdo         => s_bscan_tdo,
    s_bscan_tms         => s_bscan_tms,
    s_bscan_update      => s_bscan_update,
    m0_bscan_bscanid_en => m0_bscan_bscanid_en,
    m0_bscan_capture    => m0_bscan_capture,
    m0_bscan_drck       => m0_bscan_drck,
    m0_bscan_reset      => m0_bscan_reset,
    m0_bscan_runtest    => m0_bscan_runtest,
    m0_bscan_sel        => m0_bscan_sel,
    m0_bscan_shift      => m0_bscan_shift,
    m0_bscan_tck        => m0_bscan_tck,
    m0_bscan_tdi        => m0_bscan_tdi,
    m0_bscan_tdo        => m0_bscan_tdo,
    m0_bscan_tms        => m0_bscan_tms,
    m0_bscan_update     => m0_bscan_update
);
end generate gen_debug_bridge;

gen_full_rx_crossbar : if RX_CROSSBAR_TYPE = "full" generate
link1_eci_link : eci_link_rx
generic map (
    LOW_LATENCY => LOW_LATENCY 
)
port map (
    clk                     => clk,
    link_up                 => link_up,

    link_in_data           => link1_in_data,
    link_in_vc_no          => link1_in_vc_no,
    link_in_we2            => link1_in_we2,
    link_in_we3            => link1_in_we3,
    link_in_we4            => link1_in_we4,
    link_in_we5            => link1_in_we5,
    link_in_valid          => link1_in_valid,
    link_in_credit_return  => link1_in_credit_return,

    link                    => link1,
    link_ready              => link1_ready
);

link2_eci_link : eci_link_rx
generic map (
    LOW_LATENCY => LOW_LATENCY 
)
port map (
    clk                     => clk,
    link_up                 => link_up,

    link_in_data           => link2_in_data,
    link_in_vc_no          => link2_in_vc_no,
    link_in_we2            => link2_in_we2,
    link_in_we3            => link2_in_we3,
    link_in_we4            => link2_in_we4,
    link_in_we5            => link2_in_we5,
    link_in_valid          => link2_in_valid,
    link_in_credit_return  => link2_in_credit_return,

    link                    => link2,
    link_ready              => link2_ready
);

i_eci_rx_crossbar : eci_rx_crossbar
generic map (
    CHANNELS            => RX_NO_CHANNELS,
    filter_vc           => RX_FILTER_VC,
    filter_type_mask    => RX_FILTER_TYPE_MASK,
    filter_type         => RX_FILTER_TYPE,
    filter_cli_mask     => RX_FILTER_CLI_MASK,
    filter_cli          => RX_FILTER_CLI
)
port map (
    clk                 => clk,

    link1               => link1,
    link1_ready         => link1_ready,
    link2               => link2,
    link2_ready         => link2_ready,

    out_channels        => rx_eci_channels,
    out_channels_ready  => rx_eci_channels_ready
);
end generate gen_full_rx_crossbar;

gen_lite_rx_crossbar : if RX_CROSSBAR_TYPE = "lite" generate
link1_eci_link : eci_link_rx_lite
generic map (
    LOW_LATENCY => LOW_LATENCY 
)
port map (
    clk                     => clk,
    link_up                 => link_up,

    link_in_data           => link1_in_data,
    link_in_vc_no          => link1_in_vc_no,
    link_in_we2            => link1_in_we2,
    link_in_we3            => link1_in_we3,
    link_in_we4            => link1_in_we4,
    link_in_we5            => link1_in_we5,
    link_in_valid          => link1_in_valid,
    link_in_credit_return  => link1_in_credit_return,

    link_hi                 => link1(2),
    link_hi_ready           => link1_ready(2),
    link_lo_even            => link1(3),
    link_lo_even_ready      => link1_ready(3),
    link_lo_odd             => link1(4),
    link_lo_odd_ready       => link1_ready(4)
);

link2_eci_link : eci_link_rx_lite
generic map (
    LOW_LATENCY => LOW_LATENCY 
)
port map (
    clk                     => clk,
    link_up                 => link_up,

    link_in_data           => link2_in_data,
    link_in_vc_no          => link2_in_vc_no,
    link_in_we2            => link2_in_we2,
    link_in_we3            => link2_in_we3,
    link_in_we4            => link2_in_we4,
    link_in_we5            => link2_in_we5,
    link_in_valid          => link2_in_valid,
    link_in_credit_return  => link2_in_credit_return,

    link_hi                 => link2(2),
    link_hi_ready           => link2_ready(2),
    link_lo_even            => link2(3),
    link_lo_even_ready      => link2_ready(3),
    link_lo_odd             => link2(4),
    link_lo_odd_ready       => link2_ready(4)
);

i_eci_rx_crossbar : eci_rx_crossbar_lite
generic map (
    CHANNELS            => RX_NO_CHANNELS,
    filter_vc           => RX_FILTER_VC,
    filter_type_mask    => RX_FILTER_TYPE_MASK,
    filter_type         => RX_FILTER_TYPE,
    filter_cli_mask     => RX_FILTER_CLI_MASK,
    filter_cli          => RX_FILTER_CLI
)
port map (
    clk                 => clk,

    link1_hi            => link1(2),
    link1_hi_ready      => link1_ready(2),

    link1_lo_even       => link1(3),
    link1_lo_even_ready => link1_ready(3),

    link1_lo_odd        => link1(4),
    link1_lo_odd_ready  => link1_ready(4),

    link2_hi            => link2(2),
    link2_hi_ready      => link2_ready(2),

    link2_lo_even       => link2(3),
    link2_lo_even_ready => link2_ready(3),

    link2_lo_odd        => link2(4),
    link2_lo_odd_ready  => link2_ready(4),

    out_channels        => rx_eci_channels,
    out_channels_ready  => rx_eci_channels_ready
);
end generate gen_lite_rx_crossbar;

assert RX_CROSSBAR_TYPE = "full" or RX_CROSSBAR_TYPE = "lite" report "Unsupported RX crossbar type!" severity ERROR;

i_eci_tx_crossbar : eci_tx_crossbar
generic map (
    CHANNELS        => TX_NO_CHANNELS
)
port map (
    clk             => clk,

    in_channels     => tx_eci_channels,
    in_channels_ready   => tx_eci_channels_ready_b,

    link1_lo        => link1_out_cred_lo,
    link1_lo_ready  => link1_out_cred_lo_ready,

    link2_lo        => link2_out_cred_lo,
    link2_lo_ready  => link2_out_cred_lo_ready,

    link1_hi        => link1_out_cred_hi,
    link1_hi_ready  => link1_out_cred_hi_ready,

    link2_hi        => link2_out_cred_hi,
    link2_hi_ready  => link2_out_cred_hi_ready
);

link1_tlk_credits : tlk_credits
port map (
    clk           => clk,
    rst_n         => link1_up,
    in_hi         => link1_out_cred_hi,
    in_hi_ready   => link1_out_cred_hi_ready,
    in_lo         => link1_out_cred_lo,
    in_lo_ready   => link1_out_cred_lo_ready,

    out_hi         => link1_out_buf_hi,
    out_hi_ready   => link1_out_buf_hi_ready,
    out_lo         => link1_out_buf_lo,
    out_lo_ready   => link1_out_buf_lo_ready,

    credit_return(12 downto 2) => link1_out_credit_return,
    credit_return(1 downto 0) => "00"
);

link1_out_hi_buffer: eci_channel_buffer
generic map (
    FULL    => false
)
port map (
    clk             => clk,
    input           => link1_out_buf_hi,
    input_ready     => link1_out_buf_hi_ready,
    output.data(0)           => link1_out_hi_data(63 downto 0),
    output.data(1)           => link1_out_hi_data(127 downto 64),
    output.data(2)           => link1_out_hi_data(191 downto 128),
    output.data(3)           => link1_out_hi_data(255 downto 192),
    output.data(4)           => link1_out_hi_data(319 downto 256),
    output.data(5)           => link1_out_hi_data(383 downto 320),
    output.data(6)           => link1_out_hi_data(447 downto 384),
    output.data(7)           => link1_out_hi_data(511 downto 448),
    output.data(8)           => link1_out_hi_data(575 downto 512),
    output.vc_no    => link1_out_hi_vc_no,
    output.size     => link1_out_hi_size,
    output.valid    => link1_out_hi_valid,
    output_ready    => link1_out_hi_ready
);

link1_out_lo_buffer: eci_channel_buffer
generic map (
    FULL    => false
)
port map (
    clk             => clk,
    input           => link1_out_buf_lo,
    input_ready     => link1_out_buf_lo_ready,
    output.data(0)  => link1_out_lo_data,
    output.data(8 downto 1)  => link1_out_lo_data_unused,
    output.size     => link1_out_lo_size_unused,
    output.vc_no    => link1_out_lo_vc_no,
    output.valid    => link1_out_lo_valid,
    output_ready    => link1_out_lo_ready
);

link2_tlk_credits : tlk_credits
port map (
    clk           => clk,
    rst_n         => link2_up,
    in_hi         => link2_out_cred_hi,
    in_hi_ready   => link2_out_cred_hi_ready,
    in_lo         => link2_out_cred_lo,
    in_lo_ready   => link2_out_cred_lo_ready,

    out_hi         => link2_out_buf_hi,
    out_hi_ready   => link2_out_buf_hi_ready,
    out_lo         => link2_out_buf_lo,
    out_lo_ready   => link2_out_buf_lo_ready,

    credit_return(12 downto 2) => link2_out_credit_return,
    credit_return(1 downto 0) => "00"
);

link2_out_hi_buffer: eci_channel_buffer
generic map (
    FULL    => false
)
port map (
    clk             => clk,
    input           => link2_out_buf_hi,
    input_ready     => link2_out_buf_hi_ready,
    output.data(0)           => link2_out_hi_data(63 downto 0),
    output.data(1)           => link2_out_hi_data(127 downto 64),
    output.data(2)           => link2_out_hi_data(191 downto 128),
    output.data(3)           => link2_out_hi_data(255 downto 192),
    output.data(4)           => link2_out_hi_data(319 downto 256),
    output.data(5)           => link2_out_hi_data(383 downto 320),
    output.data(6)           => link2_out_hi_data(447 downto 384),
    output.data(7)           => link2_out_hi_data(511 downto 448),
    output.data(8)           => link2_out_hi_data(575 downto 512),
    output.vc_no    => link2_out_hi_vc_no,
    output.size     => link2_out_hi_size,
    output.valid    => link2_out_hi_valid,
    output_ready    => link2_out_hi_ready
);

link2_out_lo_buffer: eci_channel_buffer
generic map (
    FULL    => false
)
port map (
    clk             => clk,
    input           => link2_out_buf_lo,
    input_ready     => link2_out_buf_lo_ready,
    output.data(0)  => link2_out_lo_data,
    output.data(8 downto 1)  => link2_out_lo_data_unused,
    output.size     => link2_out_lo_size_unused,
    output.vc_no    => link2_out_lo_vc_no,
    output.valid    => link2_out_lo_valid,
    output_ready    => link2_out_lo_ready
);

end Behavioral;
