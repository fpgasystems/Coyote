-------------------------------------------------------------------------------
-- ECI RX Block Decoder
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
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

entity eci_rx_blk is
generic (
    LANES : integer := 12
);
port (
    clk_rx : in std_logic;
    clk_blk   :  in std_logic;

    link_aligned : in std_logic;

    link_data       : in std_logic_vector(64*LANES-1 downto 0);
    link_data_valid : in std_logic;
    ctrl_word       : in std_logic_vector( LANES-1 downto 0);

    block_out       : out std_logic_vector(511 downto 0);
    block_out_valid : out std_logic;
    crc_match_out   : out std_logic
);
end eci_rx_blk;

architecture behavioural of eci_rx_blk is

-- BUILDDEP eci_rx_blk_gbx
component eci_rx_blk_gbx is
generic (
    LANES : integer := 12
);
port (
    clk_rx : in std_logic;
    clk_blk   :  in std_logic;

    link_aligned : in std_logic;

    link_data       : in std_logic_vector(64*LANES-1 downto 0);
    link_data_valid : in std_logic;
    ctrl_word       : in std_logic_vector( LANES-1 downto 0);

    block_out       : out std_logic_vector(511 downto 0);
    block_out_valid : out std_logic
);
end component;

-- BUILDDEP eci_blk_crc
component eci_blk_crc is
port (
    clk   : in std_logic;

    block_in :  in std_logic_vector(511 downto 0);

    block_out    : out std_logic_vector(511 downto 0);
    crc_out      : out std_logic_vector(23 downto 0);
    output_valid : out std_logic;

    ready_in  :  in std_logic;
    ready_out : out std_logic
);
end component;

signal block_received         : std_logic_vector(511 downto 0);
signal block_received_valid   : std_logic;
signal block_received_1       : std_logic_vector(511 downto 0);
signal block_received_valid_1 : std_logic;

signal block_out_int : std_logic_vector(511 downto 0);
signal crc           : std_logic_vector(23 downto 0);
signal crc_valid     : std_logic;
signal crc_ready     : std_logic;

-- Synthesis fails if Vivado tries to use hard addition logic.
attribute use_dsp48 : string;
attribute use_dsp48 of crc_match_out : signal is "no";

begin

-- The RX gearbox hands us blocks.
gbx : eci_rx_blk_gbx
generic map (
    LANES     => LANES
)
port map(
    clk_rx           => clk_rx,
    clk_blk          => clk_blk,
    link_aligned     => link_aligned,
    link_data        => link_data,
    link_data_valid  => link_data_valid,
    ctrl_word        => ctrl_word,
    block_out        => block_received,
    block_out_valid  => block_received_valid
);

-- Buffer one cycle between gearbox and CRC - timing.
buffer_stage : process(clk_blk)
begin
    if rising_edge(clk_blk) then
        block_received_1       <= block_received;
        block_received_valid_1 <= block_received_valid;
    end if;
end process;

-- And we pass them into the CRC pipeline.
crc_pipeline : eci_blk_crc
port map(
    clk          => clk_blk,
    block_in     => block_received_1,
    block_out    => block_out_int,
    crc_out      => crc,
    output_valid => crc_valid,

    -- Flow control input from the gearbox, and to the output.
    ready_in     => block_received_valid_1,
    ready_out    => crc_ready
);

block_out <= block_out_int;
block_out_valid <= crc_ready and crc_valid;

-- Check that the calculated CRC matches that in the received CRC field.
crc_match_out <= '0' when crc /= block_out_int(23 downto 0) else '1';

end behavioural;
