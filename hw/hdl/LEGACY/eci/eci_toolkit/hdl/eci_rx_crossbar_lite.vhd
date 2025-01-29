----------------------------------------------------------------------------------
-- Module Name: eci_rx_crossbar_lite - Behavioral
----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Crossbar switch
-- Lite version, 6 inputs (2 links * 3 VC groups)
-- Route the incoming message to the output channel, based on the filter definition:
-- VC number(s), ECI message type (bits 63:59), cache line index (bits 39:7)
-- FILTER_VC - bitfield of VCs
-- FILTER_TYPE_MASK - mask of valid type bits (0 if not used)
-- FILTER_TYPE - message type (0 if not used)
-- FILTER_CLI_MASK - mask of valid cache line number bits (0 if not used)
-- FILTER_CLI - cache line number (0 if not used)
-- Filters are applied in order

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_rx_crossbar_lite is
generic (
    CHANNELS            : integer;
    FILTER_VC           : VC_BITFIELDS;
    FILTER_TYPE_MASK    : ECI_TYPE_MASKS;
    FILTER_TYPE         : ECI_TYPE_MASKS;
    FILTER_CLI_MASK     : CLI_ARRAY;
    FILTER_CLI          : CLI_ARRAY
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
end eci_rx_crossbar_lite;

architecture Behavioral of eci_rx_crossbar_lite is

component bus_buffer is
generic
(
    WIDTH       : integer
);
port
(
    clk         : in std_logic;
    s_data      : in std_logic_vector(WIDTH-1 downto 0);
    s_valid     : in std_logic;
    s_ready     : out std_logic;
    m_data      : out std_logic_vector(WIDTH-1 downto 0);
    m_valid     : out std_logic;
    m_ready     : in std_logic
);
end component;

component eci_channel_buffer is
port (
    clk             : in STD_LOGIC;
    input           : in ECI_CHANNEL;
    input_ready     : out STD_LOGIC;
    output          : out ECI_CHANNEL;
    output_ready    : in STD_LOGIC
);
end component;

constant c_filter_vc         : VC_BITFIELDS(0 to CHANNELS-1) := filter_vc;
constant c_filter_type_mask  : ECI_TYPE_MASKS(0 to CHANNELS-1) := filter_type_mask;
constant c_filter_type       : ECI_TYPE_MASKS(0 to CHANNELS-1) := filter_type;
constant c_filter_cli_mask   : CLI_ARRAY(0 to CHANNELS-1) := filter_cli_mask;
constant c_filter_cli        : CLI_ARRAY(0 to CHANNELS-1) := filter_cli;

type ARRAY_VALIDS is array (integer range <>) of std_logic_vector(CHANNELS-1 downto 0);
type ARRAY_ACTIVE is array (integer range <>) of integer;
type ARRAY_ACTIVE_INT is array (integer range <>) of std_logic_vector(3 downto 0);

signal link1_hi_sink        : std_logic;
signal link1_hi_valids      : std_logic_vector(CHANNELS-1 downto 0);
signal link1_lo_even_sink   : std_logic;
signal link1_lo_even_valids : std_logic_vector(CHANNELS-1 downto 0);
signal link1_lo_odd_sink    : std_logic;
signal link1_lo_odd_valids  : std_logic_vector(CHANNELS-1 downto 0);

signal link2_hi_sink        : std_logic;
signal link2_hi_valids      : std_logic_vector(CHANNELS-1 downto 0);
signal link2_lo_even_sink   : std_logic;
signal link2_lo_even_valids : std_logic_vector(CHANNELS-1 downto 0);
signal link2_lo_odd_sink    : std_logic;
signal link2_lo_odd_valids  : std_logic_vector(CHANNELS-1 downto 0);

signal inputs           : ARRAY_ECI_CHANNELS(5 downto 0);
signal inputs_vcs       : VC_BITFIELDS(5 downto 0);
signal inputs_valids_b  : ARRAY_VALIDS(5 downto 0);
signal inputs_valids    : ARRAY_VALIDS(5 downto 0);
signal inputs_readys    : ARRAY_VALIDS(5 downto 0);
signal inputs_sink      : std_logic_vector(5 downto 0);
signal input_ready      : std_logic_vector(5 downto 0);
signal inputs_active    : ARRAY_ACTIVE(CHANNELS-1 downto 0);
signal inputs_hold      : ARRAY_ACTIVE(CHANNELS-1 downto 0) := (others => -1);
signal inputs_active_int    : ARRAY_ACTIVE_INT(CHANNELS-1 downto 0);

signal channels_buffered            : ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
signal channels_ready_buffered      : std_logic_vector(CHANNELS - 1 downto 0);


function get_hi_vcs(vc_no : std_logic_vector(3 downto 0)) return std_logic_vector is
    variable vcs : std_logic_vector(12 downto 2) := "00000000000";
begin
    if vc_no = "0010" then
        vcs(2) := '1';
    elsif vc_no = "0011" then
        vcs(3) := '1';
    elsif vc_no = "0100" then
        vcs(4) := '1';
    else--if vc_no = "0101" then
        vcs(5) := '1';
    end if;
    return vcs;
end function;

function get_lo_even_vcs(vc_no : std_logic_vector(3 downto 0)) return std_logic_vector is
    variable vcs : std_logic_vector(12 downto 2) := "00000000000";
begin
    if vc_no = "0110" then
        vcs(6) := '1';
    elsif vc_no = "1000" then
        vcs(8) := '1';
    elsif vc_no = "1010" then
        vcs(10) := '1';
    else--if vc_no = "1100" then
        vcs(12) := '1';
    end if;
    return vcs;
end function;

function get_lo_odd_vcs(vc_no : std_logic_vector(3 downto 0)) return std_logic_vector is
    variable vcs : std_logic_vector(12 downto 2) := "00000000000";
begin
    if vc_no = "0111" then
        vcs(7) := '1';
    elsif vc_no = "1001" then
        vcs(9) := '1';
    else--if vc_no = "1011" then
        vcs(11) := '1';
    end if;
    return vcs;
end function;

function get_filtered_valid(channel : ECI_CHANNEL; vcs : std_logic_vector(12 downto 2)) return std_logic_vector is
    variable r : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
begin
    for i in 0 to CHANNELS-1 loop
        if channel.valid = '1' and ((c_filter_vc(i) and vcs) /= std_logic_vector(to_unsigned(0, 11)))
            and ((channel.data(0)(63 downto 59) and c_filter_type_mask(i)) = c_filter_type(i))
            and ((channel.data(0)(39 downto 7) and c_filter_cli_mask(i)) = c_filter_cli(i)) then
            r(i) := '1';
            exit;
        end if;
    end loop;
    return r;
end function;

function check_if_sink(channel : ECI_CHANNEL; vcs : std_logic_vector(12 downto 2)) return std_logic is
begin
    for i in 0 to CHANNELS-1 loop
        if channel.valid = '1' and ((c_filter_vc(i) and vcs) /= std_logic_vector(to_unsigned(0, 11)))
            and ((channel.data(0)(63 downto 59) and c_filter_type_mask(i)) = c_filter_type(i))
            and ((channel.data(0)(39 downto 7) and c_filter_cli_mask(i)) = c_filter_cli(i)) then
            return '0';
        end if;
    end loop;
    return '1';
end function;

begin

i_link1_hi_buffer : eci_channel_buffer
port map (
    clk             => clk,
    input           => link1_hi,
    input_ready     => link1_hi_ready,
    output          => inputs(0),
    output_ready    => input_ready(0)
);

i_link1_lo_even_buffer : eci_channel_buffer
port map (
    clk             => clk,
    input           => link1_lo_even,
    input_ready     => link1_lo_even_ready,
    output          => inputs(1),
    output_ready    => input_ready(1)
);

i_link1_lo_odd_buffer : eci_channel_buffer
port map (
    clk             => clk,
    input           => link1_lo_odd,
    input_ready     => link1_lo_odd_ready,
    output          => inputs(2),
    output_ready    => input_ready(2)
);

i_link2_hi_buffer : eci_channel_buffer
port map (
    clk             => clk,
    input           => link2_hi,
    input_ready     => link2_hi_ready,
    output          => inputs(3),
    output_ready    => input_ready(3)
);

i_link2_lo_even_buffer : eci_channel_buffer
port map (
    clk             => clk,
    input           => link2_lo_even,
    input_ready     => link2_lo_even_ready,
    output          => inputs(4),
    output_ready    => input_ready(4)
);

i_link2_lo_odd_buffer : eci_channel_buffer
port map (
    clk             => clk,
    input           => link2_lo_odd,
    input_ready     => link2_lo_odd_ready,
    output          => inputs(5),
    output_ready    => input_ready(5)
);

inputs_vcs(0) <= get_hi_vcs(inputs(0).vc_no);
inputs_vcs(1) <= get_lo_even_vcs(inputs(1).vc_no);
inputs_vcs(2) <= get_lo_odd_vcs(inputs(2).vc_no);
inputs_vcs(3) <= get_hi_vcs(inputs(3).vc_no);
inputs_vcs(4) <= get_lo_even_vcs(inputs(4).vc_no);
inputs_vcs(5) <= get_lo_odd_vcs(inputs(5).vc_no);

gen_in : for i in 0 to 5 generate
begin
    inputs_valids(i) <= get_filtered_valid(inputs(i), inputs_vcs(i));
    inputs_sink(i) <= check_if_sink(inputs(i), inputs_vcs(i));
    input_ready(i) <= or_reduce(inputs_readys(i)) or inputs_sink(i);
end generate;

gen_mux : for ic in 0 to CHANNELS-1 generate
begin
    inputs_active_int(ic) <= std_logic_vector(to_signed(inputs_active(ic), 4));

    inputs_active(ic) <= inputs_hold(ic) when inputs_hold(ic) /= -1 else
        0 when inputs_valids(0)(ic) = '1' else
        1 when inputs_valids(1)(ic) = '1' else
        2 when inputs_valids(2)(ic) = '1' else
        3 when inputs_valids(3)(ic) = '1' else
        4 when inputs_valids(4)(ic) = '1' else
        5;
    channels_buffered(ic).valid <= inputs_valids(inputs_active(ic))(ic);
    channels_buffered(ic).data <= inputs(inputs_active(ic)).data;
    channels_buffered(ic).vc_no <= inputs(inputs_active(ic)).vc_no;
    channels_buffered(ic).size <= inputs(inputs_active(ic)).size;
    inputs_readys(0)(ic) <= channels_buffered(ic).valid and channels_ready_buffered(ic) when inputs_active(ic) = 0 else '0';
    inputs_readys(1)(ic) <= channels_buffered(ic).valid and channels_ready_buffered(ic) when inputs_active(ic) = 1 else '0';
    inputs_readys(2)(ic) <= channels_buffered(ic).valid and channels_ready_buffered(ic) when inputs_active(ic) = 2 else '0';
    inputs_readys(3)(ic) <= channels_buffered(ic).valid and channels_ready_buffered(ic) when inputs_active(ic) = 3 else '0';
    inputs_readys(4)(ic) <= channels_buffered(ic).valid and channels_ready_buffered(ic) when inputs_active(ic) = 4 else '0';
    inputs_readys(5)(ic) <= channels_buffered(ic).valid and channels_ready_buffered(ic) when inputs_active(ic) = 5 else '0';

    i_buffer : eci_channel_buffer
    port map (
        clk             => clk,
        input           => channels_buffered(ic),
        input_ready     => channels_ready_buffered(ic),
        output          => out_channels(ic),
        output_ready    => out_channels_ready(ic)
    );
end generate gen_mux;

i_process : process(clk)
    variable i : integer;
begin
    if rising_edge(clk) then
        for ic in 0 to CHANNELS-1 loop
             if channels_buffered(ic).valid = '1' then
                if (channels_ready_buffered(ic) = '0' or channels_buffered(ic).size = ECI_CHANNEL_SIZE_9_1) then
                    inputs_hold(ic) <= inputs_active(ic);
                else
                    inputs_hold(ic) <= -1;
                end if;
             end if;
        end loop;
    end if;
end process;

end Behavioral;
