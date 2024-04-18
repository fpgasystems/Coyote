-------------------------------------------------------------------------------
-- ECI/Interlaken Descrambler
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

entity il_rx_descrambler is
port (
    clk_rx : in std_logic;
    reset  : in std_logic;

    input       : in std_logic_vector(63 downto 0);
    input_valid : in std_logic;

    output       : out std_logic_vector(63 downto 0);
    output_valid : out std_logic;

    word_lock_in   :  in std_logic;
    word_lock_out  : out std_logic;
    sync_error_in  :  in std_logic;
    sync_error_out : out std_logic;
    ctrl_word_in   :  in std_logic;
    ctrl_word_out  : out std_logic;
    data_word_in   :  in std_logic;
    data_word_out  : out std_logic;
    sync_word_in   :  in std_logic;
    sync_word_out  : out std_logic;

    scrm_word_out : out std_logic
);
end il_rx_descrambler;

architecture behavioural of il_rx_descrambler is

signal state : std_logic_vector(57 downto 0);
signal code  : std_logic_vector(63 downto 0);

signal scrm_word_in : std_logic;

alias new_state : std_logic_vector(57 downto 0) is input(57 downto 0);

begin

code(63 downto 25) <= state(57 downto 19) xor state(38 downto  0);
code(24 downto  6) <= state(57 downto 39) xor state(38 downto 20) xor
                      state(18 downto  0);
code( 5 downto  0) <= state(57 downto 52) xor state(19 downto 14);

output <= input when sync_word_in = '1' or scrm_word_in = '1' else input xor (state & code(63 downto 58));
output_valid    <= input_valid;
word_lock_out   <= word_lock_in;
sync_error_out  <= sync_error_in;
ctrl_word_out   <= ctrl_word_in;
data_word_out   <= data_word_in;
sync_word_out   <= sync_word_in;
scrm_word_out   <= scrm_word_in;

descramble : process(clk_rx)
begin
    if rising_edge(clk_rx) then
        if input_valid = '1' then
            if sync_word_in = '1' then
                -- The sync word is not scrambled.
                -- Delay the strobe to match the data.
                -- The scrambler state word is recognised by its position
                -- (after the sync word), as its block type can appear
                -- spuriously in other (scrambled) control words.
                scrm_word_in     <= '1';
            elsif scrm_word_in = '1' then
                -- The scrambler word is not scrambled.
                state            <= new_state;
                scrm_word_in     <= '0';
            else
                scrm_word_in     <= '0';
                state            <= code(57 downto 0);
            end if;
        end if;
    end if;
end process;

end behavioural;
