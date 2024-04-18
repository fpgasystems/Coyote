-------------------------------------------------------------------------------
-- ECI TX Block Encoder
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

library xpm;
use xpm.vcomponents.all;

entity eci_tx_blk is
generic (
    LANES : integer := 12
);
port (
    clk_tx : in std_logic;
    clk_blk   : in std_logic;

    block_in       :  in std_logic_vector(511 downto 0);
    block_in_ready : out std_logic;

    link_data       : out std_logic_vector(LANES*64-1 downto 0);
    link_data_ready :  in std_logic;
    ctrl_word_out   : out std_logic_vector( LANES-1 downto 0)
);
end eci_tx_blk;

architecture behavioural of eci_tx_blk is

-- BUILDDEP eci_tx_blk_crc
component eci_blk_crc is
port (
    clk   : in std_logic;

    block_in  :  in std_logic_vector(511 downto 0);

    block_out    : out std_logic_vector(511 downto 0);
    crc_out      : out std_logic_vector(23 downto 0);
    output_valid : out std_logic;

    ready_in  :  in std_logic;
    ready_out : out std_logic
);
end component;

-- BUILDDEP eci_tx_blk_gbx
component eci_tx_blk_gbx is
generic (
    LANES : integer := 12
);
port (
    clk_tx : in std_logic;
    clk_blk   : in std_logic;

    block_in       :  in std_logic_vector(511 downto 0);
    block_in_ready : out std_logic;

    link_data       : out std_logic_vector(LANES*64-1 downto 0);
    link_data_ready :  in std_logic;
    ctrl_word_out   : out std_logic_vector( LANES-1 downto 0)
);
end component;

signal block_delayed       : std_logic_vector(511 downto 0);
signal crc                 : std_logic_vector(23 downto 0);
signal block_delayed_ready : std_logic;

signal block_with_crc : std_logic_vector(511 downto 0);

begin

-- An 8-stage pipeline calculates the CRC
crc_pipeline : eci_blk_crc
port map(
    clk          => clk_blk,
    block_in     => block_in,
    block_out    => block_delayed,
    crc_out      => crc,

    -- The CRC pipeline will output rubbish for the first 7 cycles after
    -- reset, but we need to produce something on every clock tick.
    output_valid => open,

    -- Flow control is from the gearbox, and to the input.
    ready_in     => block_delayed_ready,
    ready_out    => block_in_ready
);

-- We insert the CRC into bits 23:0 of the last (control) word.
block_with_crc <= block_delayed(511 downto 24) & crc;

-- We then feed the modified block to the link gearbox.
gbx : eci_tx_blk_gbx
generic map (
    LANES     => LANES
)
port map(
    clk_tx          => clk_tx,
    clk_blk         => clk_blk,
    block_in        => block_with_crc,
    block_in_ready  => block_delayed_ready,
    link_data       => link_data,
    link_data_ready => link_data_ready,
    ctrl_word_out   => ctrl_word_out
);

end behavioural;
