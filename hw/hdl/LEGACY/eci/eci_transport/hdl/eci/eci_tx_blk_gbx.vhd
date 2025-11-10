-------------------------------------------------------------------------------
-- ECI Block TX Gearbox, synchronous version, clk_blk / clk_rx = 2
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

entity eci_tx_blk_gbx is
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
   ctrl_word_out   : out std_logic_vector(LANES-1 downto 0)
);
end eci_tx_blk_gbx;

architecture behavioural of eci_tx_blk_gbx is

-- Block data synchronised into the clk_tx domain.
signal block_reversed : std_logic_vector(511 downto 0);
signal block_buffer   : std_logic_vector(639 downto 0);

signal phase               : std_logic_vector(2 downto 0) := "000";
signal ldr                 : std_logic;

begin

-- The blocks are to be transmitted most-significant-word first, while the
-- Interlaken link will stripe onto lane 0 first.  Thus we must reverse the
-- word order.
reverse_block : for i in 0 to 7 generate
   block_reversed((7-i)*64 + 63 downto (7-i)*64) <=
       block_in(i*64 + 63 downto i*64);
end generate;

block_in_ready <= link_data_ready and not (phase(0) and phase(1));
link_data <= block_reversed(383 downto 0) & block_buffer(383 downto 0) when phase(1) = '0' else block_reversed(127 downto 0) & block_buffer;
ctrl_word_out <= X"020" when phase(1) = '0' else X"202"; -- ThunderX pattern

slow_counter : process(clk_tx)
begin
   if rising_edge(clk_tx) then
       if link_data_ready = '1' then
           phase(1) <= not phase(1);
       end if;
   end if;
end process;

fast_counter : process(clk_blk)
begin
   if rising_edge(clk_blk) then
       if link_data_ready = '1' then
           if phase(1) = '0' then
               if phase(0) = '0' then
               else
                   block_buffer(127 downto 0) <= block_reversed(511 downto 384);
               end if;
           else -- phase(1) = '1'
               if phase(0) = '0' then
                   block_buffer(639 downto 128) <= block_reversed;
               else
                   block_buffer(383 downto 0) <= block_reversed(511 downto 128);
               end if;
           end if;
           phase(0) <= not phase(0);
       end if;
   end if;
end process;

end behavioural;
