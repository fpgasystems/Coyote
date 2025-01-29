-------------------------------------------------------------------------------
-- ECI Block RX Gearbox, synchronous version, clk_blk / clk_rx = 2
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

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

entity eci_rx_blk_gbx is
generic (
   LANES : integer := 12
);
port (
   clk_rx  : in std_logic;

   clk_blk   :  in std_logic;

   link_aligned : in std_logic;

   link_data       : in std_logic_vector(64*LANES-1 downto 0);
   link_data_valid : in std_logic;
   ctrl_word       : in std_logic_vector( LANES-1 downto 0);

   block_out       : out std_logic_vector(511 downto 0);
   block_out_valid : out std_logic
);
end eci_rx_blk_gbx;

architecture behavioural of eci_rx_blk_gbx is

-- The 64b words of the blocks to be decoded are striped across the lanes,
-- beginning with lane 0.  If the number of lanes is not a factor of 8 (the
-- number of words in a block), then blocks will not begin on the same lane on
-- every input cycle.  As our intended use case is 12 lanes per link, we do
-- need to handle this.
--
-- The high word of the block is sent first.
--
-- We can use the control word strobe from the lane block to detect the last
-- word of a block (ECI sets this even for payload words, which isn't
-- Interlaken compliant, but is useful).

-- Link data synchronised into the output clock domain.
signal data_buffer  : std_logic_vector(639 downto 0);

-- The output block, before word reversal.
signal block_raw    : std_logic_vector(511 downto 0);
signal phase : integer range 1 to 3 := 1;

signal link_data_buf       : std_logic_vector(64*LANES-1 downto 0);
signal link_data_valid_buf : std_logic;
signal ctrl_word_buf       : std_logic_vector( LANES-1 downto 0);

begin

buffer_data : process(clk_rx)
begin
    if rising_edge(clk_rx) then
        link_data_buf       <= link_data;
        link_data_valid_buf <= link_data_valid;
        ctrl_word_buf       <= ctrl_word;
    end if;
end process;

block_raw <=    link_data_buf(127 downto 0) & data_buffer(383 downto 0) when phase = 1 else
                data_buffer(511 downto 0) when phase = 2 else
                link_data_buf(383 downto 0) & data_buffer(639 downto 512);
block_out_valid <= '1' when link_data_valid_buf = '1' and ((ctrl_word_buf = X"202" and (phase = 1 or phase = 2)) or (ctrl_word_buf = X"020" and phase = 3)) else '0';

process_data : process(clk_blk)
begin
    if rising_edge(clk_blk) then
        if link_data_valid_buf = '1' then
            if ctrl_word_buf = X"202" then -- ThunderX pattern
                if phase = 1 then
                    data_buffer(639 downto 0) <= link_data_buf(767 downto 128);
                    phase <= 2;
                elsif phase = 2 then
                    phase <= 3;
                end if;
            elsif ctrl_word_buf = X"020" then
                if phase = 3 then
                    data_buffer(383 downto 0) <= link_data_buf(767 downto 384);
                end if;
                phase <= 1;
            end if;
        end if;
    end if;
end process;

-- Blocks are transmitted most-significant-word fist, but striped by
-- Interlaken beginning with lane 0.  Thus the order of words is reversed
-- relative to the original block word order.
reverse : for i in 0 to 7
generate
   block_out((7-i)*64 + 63 downto (7-i)*64)
       <= block_raw(i*64 + 63 downto i*64);
end generate;

end behavioural;
