-------------------------------------------------------------------------------
-- ECI/Interlaken Scrambler
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
use ieee.numeric_std.all;

entity il_tx_scrambler is
port (
    clk_tx : in std_logic;
    reset  : in std_logic;

    init_state : in std_logic_vector(57 downto 0);

    input        :  in std_logic_vector(63 downto 0);

    sync_word_in : in std_logic;
    scrm_word_in : in std_logic;

    output        : out std_logic_vector(63 downto 0);
    output_ready  :  in std_logic
);
end il_tx_scrambler;

architecture behavioural of il_tx_scrambler is

signal state : std_logic_vector(57 downto 0);
signal code  : std_logic_vector(63 downto 0);

begin

-- Generate the next 63 bits of the scrambler code.
code(63 downto 25) <= state(57 downto 19) xor state(38 downto  0);
code(24 downto  6) <= state(57 downto 39) xor state(38 downto 20) xor
                      state(18 downto  0);
code( 5 downto  0) <= state(57 downto 52) xor state(19 downto 14);

output <=
    -- The Sync word is transmitted unscrambled.
    input when sync_word_in = '1' else
    -- The Scrambler State word is unscrambled, and has the current scrambler
    -- state inserted into bits 57:0.
    input(63 downto 58) & state when scrm_word_in = '1' else
    -- All other words are scrambled.
    input xor (state & code(63 downto 58));

update_state : process(clk_tx)
begin
    if rising_edge(clk_tx) then
        if reset = '1' then
            state <= init_state;
        elsif output_ready = '1' and
              sync_word_in = '0' and
              scrm_word_in = '0' then
            -- When a scrambled output word (i.e. not a sync or scrambler
            -- state word) is consumed, advance the scrambler state.
            state <= code(57 downto 0);
        end if;
    end if;
end process;

end behavioural;
