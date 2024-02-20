
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

entity cyt_eci_gateway is
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
end cyt_eci_gateway;

architecture Behavioral of cyt_eci_gateway is

-- full version with separate VCs (11 separate inputs to the RX crossbar)
component eci_link_rx is
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

    link1_hi            : buffer ECI_CHANNEL;
    link1_hi_ready      : in STD_LOGIC;
    link2_hi            : buffer ECI_CHANNEL;
    link2_hi_ready      : in STD_LOGIC;
    link1_lo            : buffer ECI_CHANNEL;
    link1_lo_ready      : in STD_LOGIC;
    link2_lo            : buffer ECI_CHANNEL;
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

-- Link
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

-- We need them to have a proper port mapping with records, looks like a Vivado bug
signal link1_out_lo_data_unused : WORDS(8 downto 1);
signal link1_out_lo_size_unused : std_logic_vector(2 downto 0);
signal link2_out_lo_data_unused : WORDS(8 downto 1);
signal link2_out_lo_size_unused : std_logic_vector(2 downto 0);

signal tx_eci_channels_ready_b   : std_logic_vector(TX_NO_CHANNELS-1 downto 0);

begin

-- Link
tx_eci_channels_ready <= tx_eci_channels_ready_b;
link_up <= link1_up and link2_up;

gen_full_rx_crossbar : if RX_CROSSBAR_TYPE = "full" generate
link1_eci_link : eci_link_rx
port map (
    clk                     => clk_sys,
    link_up                 => link_up,

    link_in_data            => link1_in_data,
    link_in_vc_no           => link1_in_vc_no,
    link_in_we2             => link1_in_we2,
    link_in_we3             => link1_in_we3,
    link_in_we4             => link1_in_we4,
    link_in_we5             => link1_in_we5,
    link_in_valid           => link1_in_valid,
    link_in_credit_return   => link1_in_credit_return,

    link                    => link1,
    link_ready              => link1_ready
);

link2_eci_link : eci_link_rx
port map (
    clk                     => clk_sys,
    link_up                 => link_up,

    link_in_data            => link2_in_data,
    link_in_vc_no           => link2_in_vc_no,
    link_in_we2             => link2_in_we2,
    link_in_we3             => link2_in_we3,
    link_in_we4             => link2_in_we4,
    link_in_we5             => link2_in_we5,
    link_in_valid           => link2_in_valid,
    link_in_credit_return   => link2_in_credit_return,

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
    clk                 => clk_sys,

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
port map (
    clk                     => clk_sys,
    link_up                 => link_up,

    link_in_data            => link1_in_data,
    link_in_vc_no           => link1_in_vc_no,
    link_in_we2             => link1_in_we2,
    link_in_we3             => link1_in_we3,
    link_in_we4             => link1_in_we4,
    link_in_we5             => link1_in_we5,
    link_in_valid           => link1_in_valid,
    link_in_credit_return   => link1_in_credit_return,

    link_hi                 => link1(2),
    link_hi_ready           => link1_ready(2),
    link_lo_even            => link1(3),
    link_lo_even_ready      => link1_ready(3),
    link_lo_odd             => link1(4),
    link_lo_odd_ready       => link1_ready(4)
);

link2_eci_link : eci_link_rx_lite
port map (
    clk                     => clk_sys,
    link_up                 => link_up,

    link_in_data            => link2_in_data,
    link_in_vc_no           => link2_in_vc_no,
    link_in_we2             => link2_in_we2,
    link_in_we3             => link2_in_we3,
    link_in_we4             => link2_in_we4,
    link_in_we5             => link2_in_we5,
    link_in_valid           => link2_in_valid,
    link_in_credit_return   => link2_in_credit_return,

    link_hi                 => link2(2),
    link_hi_ready           => link2_ready(2),
    link_lo_even            => link2(3),
    link_lo_even_ready      => link2_ready(3),
    link_lo_odd             => link2(4),
    link_lo_odd_ready       => link2_ready(4)
);

i_eci_rx_crossbar : eci_rx_crossbar_lite
generic map (
    CHANNELS                    => RX_NO_CHANNELS,
    filter_vc                   => RX_FILTER_VC,
    filter_type_mask            => RX_FILTER_TYPE_MASK,
    filter_type                 => RX_FILTER_TYPE,
    filter_cli_mask             => RX_FILTER_CLI_MASK,
    filter_cli                  => RX_FILTER_CLI
)
port map (
    clk                         => clk_sys,

    link1_hi                    => link1(2),
    link1_hi_ready              => link1_ready(2),
    link1_lo_even               => link1(3),
    link1_lo_even_ready         => link1_ready(3),
    link1_lo_odd                => link1(4),
    link1_lo_odd_ready          => link1_ready(4),
    link2_hi                    => link2(2),
    link2_hi_ready              => link2_ready(2),
    link2_lo_even               => link2(3),
    link2_lo_even_ready         => link2_ready(3),
    link2_lo_odd                => link2(4),
    link2_lo_odd_ready          => link2_ready(4),
    out_channels                => rx_eci_channels,
    out_channels_ready          => rx_eci_channels_ready
);
end generate gen_lite_rx_crossbar;

assert RX_CROSSBAR_TYPE = "full" or RX_CROSSBAR_TYPE = "lite" report "Unsupported RX crossbar type!" severity ERROR;

i_eci_tx_crossbar : eci_tx_crossbar
generic map (
    CHANNELS                    => TX_NO_CHANNELS
)
port map (
    clk                         => clk_sys,

    in_channels                 => tx_eci_channels,
    in_channels_ready           => tx_eci_channels_ready_b,
    link1_lo                    => link1_out_cred_lo,
    link1_lo_ready              => link1_out_cred_lo_ready,
    link2_lo                    => link2_out_cred_lo,
    link2_lo_ready              => link2_out_cred_lo_ready,
    link1_hi                    => link1_out_cred_hi,
    link1_hi_ready              => link1_out_cred_hi_ready,
    link2_hi                    => link2_out_cred_hi,
    link2_hi_ready              => link2_out_cred_hi_ready
);

link1_tlk_credits : tlk_credits
port map (
    clk                         => clk_sys,
    rst_n                       => link1_up,
    in_hi                       => link1_out_cred_hi,
    in_hi_ready                 => link1_out_cred_hi_ready,
    in_lo                       => link1_out_cred_lo,
    in_lo_ready                 => link1_out_cred_lo_ready,

    out_hi.data(0)              => link1_out_hi_data(63 downto 0),
    out_hi.data(1)              => link1_out_hi_data(127 downto 64),
    out_hi.data(2)              => link1_out_hi_data(191 downto 128),
    out_hi.data(3)              => link1_out_hi_data(255 downto 192),
    out_hi.data(4)              => link1_out_hi_data(319 downto 256),
    out_hi.data(5)              => link1_out_hi_data(383 downto 320),
    out_hi.data(6)              => link1_out_hi_data(447 downto 384),
    out_hi.data(7)              => link1_out_hi_data(511 downto 448),
    out_hi.data(8)              => link1_out_hi_data(575 downto 512),
    out_hi.vc_no                => link1_out_hi_vc_no,
    out_hi.size                 => link1_out_hi_size,
    out_hi.valid                => link1_out_hi_valid,
    out_hi_ready                => link1_out_hi_ready,
    out_lo.data(0)              => link1_out_lo_data,
    out_lo.data(8 downto 1)     => link1_out_lo_data_unused,
    out_lo.size                 => link1_out_lo_size_unused,
    out_lo.vc_no                => link1_out_lo_vc_no,
    out_lo.valid                => link1_out_lo_valid,
    out_lo_ready                => link1_out_lo_ready,
    credit_return(12 downto 2)  => link1_out_credit_return,
    credit_return(1 downto 0)   => "00"
);

link2_tlk_credits : tlk_credits
port map (
    clk                         => clk_sys,
    rst_n                       => link2_up,
    in_hi                       => link2_out_cred_hi,
    in_hi_ready                 => link2_out_cred_hi_ready,
    in_lo                       => link2_out_cred_lo,
    in_lo_ready                 => link2_out_cred_lo_ready,

    out_hi.data(0)              => link2_out_hi_data(63 downto 0),
    out_hi.data(1)              => link2_out_hi_data(127 downto 64),
    out_hi.data(2)              => link2_out_hi_data(191 downto 128),
    out_hi.data(3)              => link2_out_hi_data(255 downto 192),
    out_hi.data(4)              => link2_out_hi_data(319 downto 256),
    out_hi.data(5)              => link2_out_hi_data(383 downto 320),
    out_hi.data(6)              => link2_out_hi_data(447 downto 384),
    out_hi.data(7)              => link2_out_hi_data(511 downto 448),
    out_hi.data(8)              => link2_out_hi_data(575 downto 512),
    out_hi.vc_no                => link2_out_hi_vc_no,
    out_hi.size                 => link2_out_hi_size,
    out_hi.valid                => link2_out_hi_valid,
    out_hi_ready                => link2_out_hi_ready,
    out_lo.data(0)              => link2_out_lo_data,
    out_lo.data(8 downto 1)     => link2_out_lo_data_unused,
    out_lo.size                 => link2_out_lo_size_unused,
    out_lo.vc_no                => link2_out_lo_vc_no,
    out_lo.valid                => link2_out_lo_valid,
    out_lo_ready                => link2_out_lo_ready,
    credit_return(12 downto 2)  => link2_out_credit_return,
    credit_return(1 downto 0)   => "00"
);

end Behavioral;
