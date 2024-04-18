-------------------------------------------------------------------------------
-- ECI Block CRC24 pipeline
--
-- Calculates the CRC24 of the supplied block, with an 8 cycle pipeline delay.
-- The crc is output together with the unmodified corresponding block, so that
-- this can be used either in the TX path (where the CRC is inserted into the
-- block) or in the RX path, where it's compared with the value in bits 23:0
-- of the input.
--
-- The CRC is calculated with the CRC field initialised to zeroes.


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

entity eci_blk_crc is
port (
    clk   : in std_logic;

    block_in  :  in std_logic_vector(511 downto 0);

    block_out    : out std_logic_vector(511 downto 0);
    crc_out      : out std_logic_vector(23 downto 0);
    output_valid : out std_logic;

    ready_in  :  in std_logic;
    ready_out : out std_logic
);
end eci_blk_crc;

architecture behavioural of eci_blk_crc is

component crc_512_24_328b63 is
port (
    R   :  in std_logic_vector(23 downto 0);
    X   :  in std_logic_vector(511 downto 0);
    R_n : out std_logic_vector(23 downto 0)
);
end component;

signal block_512 : std_logic_vector(511 downto 0);

-- 'crc_n_out' is the CRC of the top n words of 'block_(n-1)'.
signal crc_1_out : std_logic_vector(23 downto 0);

begin

block_512 <= block_in(511 downto 24) & X"000000";

crc_512 : crc_512_24_328b63
port map(
    -- The CRC is initialised to all ones.
    R   => (others => '1'),
    X   => block_512,
    R_n => crc_1_out
);

block_out <= block_in;
crc_out <= not crc_1_out;
ready_out <= ready_in;
output_valid <= ready_in;

end behavioural;
