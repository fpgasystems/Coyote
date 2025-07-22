----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Crossbar switch
-- Full switch, 22 inputs (2 links * 11 VCs)
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

entity eci_rx_crossbar is
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

    link1               : in ARRAY_ECI_CHANNELS(12 downto 2);
    link1_ready         : out std_logic_vector(12 downto 2);
    link2               : in ARRAY_ECI_CHANNELS(12 downto 2);
    link2_ready         : out std_logic_vector(12 downto 2);

    out_channels        : out ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
    out_channels_ready  : in std_logic_vector(CHANNELS-1 downto 0)
);
end eci_rx_crossbar;

architecture Behavioral of eci_rx_crossbar is

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

component eci_channel_muxer
generic (
    CHANNELS    : integer
);
port (
    clk             : in STD_LOGIC;

    inputs          : in ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
    inputs_ready    : out std_logic_vector(CHANNELS-1 downto 0);
    output          : out ECI_CHANNEL;
    output_ready    : in std_logic
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

type MATRIX_ECI_CHANNELS_IN is array (integer range <>) of ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
type MATRIX_READYS_IN is array (integer range <>) of std_logic_vector(CHANNELS-1 downto 0);
type MATRIX_ECI_CHANNELS_OUT is array (integer range <>) of ARRAY_ECI_CHANNELS(10 downto 0);
type MATRIX_READYS_OUT is array (integer range <>) of std_logic_vector(10 downto 0);

signal link1_sink           : std_logic_vector(12 downto 2);
signal link1_valids         : ARRAY_VALIDS(12 downto 2);
signal link2_sink           : std_logic_vector(12 downto 2);
signal link2_valids         : ARRAY_VALIDS(12 downto 2);

signal inputs_muxed     : ARRAY_ECI_CHANNELS(10 downto 0);
signal inputs_muxed_ready   : std_logic_vector(10 downto 0);

signal inputs           : ARRAY_ECI_CHANNELS(10 downto 0);
signal inputs_vcs       : VC_BITFIELDS(10 downto 0);
signal inputs_valids_b  : ARRAY_VALIDS(10 downto 0);
signal inputs_valids    : ARRAY_VALIDS(10 downto 0);
signal inputs_sink      : std_logic_vector(10 downto 0);
signal input_ready      : std_logic_vector(10 downto 0);

signal channels_buffered            : ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
signal channels_ready_buffered      : std_logic_vector(CHANNELS - 1 downto 0);

signal channels_mid_in          : MATRIX_ECI_CHANNELS_IN(10 downto 0);
signal channels_mid_in_ready    : MATRIX_READYS_IN(10 downto 0);
signal channels_mid_out         : MATRIX_ECI_CHANNELS_OUT(CHANNELS-1 downto 0);
signal channels_mid_out_ready   : MATRIX_READYS_OUT(CHANNELS-1 downto 0);

function get_vcs(vc_no : std_logic_vector(3 downto 0)) return std_logic_vector is
    variable vcs : std_logic_vector(12 downto 2) := "00000000000";
begin
    if vc_no = "0010" then
        vcs(2) := '1';
    elsif vc_no = "0011" then
        vcs(3) := '1';
    elsif vc_no = "0100" then
        vcs(4) := '1';
    elsif vc_no = "0101" then
        vcs(5) := '1';
    elsif vc_no = "0110" then
        vcs(6) := '1';
    elsif vc_no = "0111" then
        vcs(7) := '1';
    elsif vc_no = "1000" then
        vcs(8) := '1';
    elsif vc_no = "1001" then
        vcs(9) := '1';
    elsif vc_no = "1010" then
        vcs(10) := '1';
    elsif vc_no = "1011" then
        vcs(11) := '1';
    else--if vc_no = "1100" then
        vcs(12) := '1';
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

function find_first(X : ARRAY_VALIDS(10 downto 0); ic : integer) return integer is
    variable i : integer;
begin
    i := 0;
    for i in 0 to 9 loop
        if X(i)(ic) = '1' then
            return i;
        end if;
    end loop;
    return 10;
end function;

function or_array_reduced(X : ARRAY_VALIDS(10 downto 0); ic : integer) return std_logic is
    variable i : integer;
begin
    i := 0;
    for i in 0 to 10 loop
        if X(i)(ic) = '1' then
            return '1';
        end if;
    end loop;
    return '0';
end function;

begin

gen_input_buffers : for i in 0 to 10 generate
begin
    i_input_muxer : eci_channel_muxer
    generic map (
        CHANNELS        => 2
    )
    port map (
        clk             => clk,
        inputs(0)       => link1(i+2),
        inputs(1)       => link2(i+2),
        inputs_ready(0) => link1_ready(i+2),
        inputs_ready(1) => link2_ready(i+2),
        output          => inputs_muxed(i),
        output_ready    => inputs_muxed_ready(i)
    );
    i_link_buffer : eci_channel_buffer
    port map (
        clk             => clk,
        input           => inputs_muxed(i),
        input_ready     => inputs_muxed_ready(i),
        output          => inputs(i),
        output_ready    => input_ready(i)
    );

    inputs_vcs(i) <= get_vcs(inputs(i).vc_no);
    inputs_valids(i) <= get_filtered_valid(inputs(i), inputs_vcs(i));
    inputs_sink(i) <= check_if_sink(inputs(i), inputs_vcs(i));
    input_ready(i) <= or_reduce(channels_mid_in_ready(i) and inputs_valids(i)) or inputs_sink(i);
end generate;

gen_mux : for ic in 0 to CHANNELS-1 generate
    shared variable channel_validaa : std_logic;
begin
    gen_mux_in : for i in 0 to 10 generate
    begin
        channels_mid_in(i)(ic).data <= inputs(i).data;
        channels_mid_in(i)(ic).size <= inputs(i).size;
        channels_mid_in(i)(ic).vc_no <= inputs(i).vc_no;
        channels_mid_in(i)(ic).valid <= inputs_valids(i)(ic);

        i_mid_buffer : eci_channel_buffer
        port map (
            clk             => clk,
            input           => channels_mid_in(i)(ic),
            input_ready     => channels_mid_in_ready(i)(ic),
            output          => channels_mid_out(ic)(i),
            output_ready    => channels_mid_out_ready(ic)(i)
        );
    end generate gen_mux_in;

    i_output_muxer : eci_channel_muxer
    generic map (
        CHANNELS        => 11
    )
    port map (
        clk             => clk,
        inputs          => channels_mid_out(ic),
        inputs_ready    => channels_mid_out_ready(ic),
        output          => channels_buffered(ic),
        output_ready    => channels_ready_buffered(ic)
    );

    i_buffer : eci_channel_buffer
    port map (
        clk             => clk,
        input           => channels_buffered(ic),
        input_ready     => channels_ready_buffered(ic),
        output          => out_channels(ic),
        output_ready    => out_channels_ready(ic)
    );
end generate gen_mux;

end Behavioral;
