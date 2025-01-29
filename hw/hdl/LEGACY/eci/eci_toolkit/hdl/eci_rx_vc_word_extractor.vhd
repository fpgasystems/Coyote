----------------------------------------------------------------------------------
-- Module Name: eci_rx_vc_word_extractor - Behavioral
----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Extract one by one words from a frame and put them into the channel, no latency

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.eci_defs.all;

entity eci_rx_vc_word_extractor is
Port (
    clk                 : in std_logic;

    input_words         : in WORDS(6 downto 0);
    input_vc_no         : in VCS(6 downto 0);
    input_word_enable   : in std_logic_vector(6 downto 0);
    input_valid         : in std_logic;
    input_ready         : out std_logic;

    output              : out ECI_CHANNEL;
    output_ready        : in std_logic
);
end eci_rx_vc_word_extractor;

architecture Behavioral of eci_rx_vc_word_extractor is

type POSITIONS is array (integer range <>) of integer range 0 to 6;

signal current_word : integer range 0 to 6 := 6;
signal next_word : POSITIONS(0 to 6);

begin

next_word(0) <= 1 when input_word_enable(1) = '1' else
                2 when input_word_enable(2) = '1' else
                3 when input_word_enable(3) = '1' else
                4 when input_word_enable(4) = '1' else
                5 when input_word_enable(5) = '1' else
                6;
next_word(1) <= 2 when input_word_enable(2) = '1' else
                3 when input_word_enable(3) = '1' else
                4 when input_word_enable(4) = '1' else
                5 when input_word_enable(5) = '1' else
                6;
next_word(2) <= 3 when input_word_enable(3) = '1' else
                4 when input_word_enable(4) = '1' else
                5 when input_word_enable(5) = '1' else
                6;
next_word(3) <= 4 when input_word_enable(4) = '1' else
                5 when input_word_enable(5) = '1' else
                6;
next_word(4) <= 5 when input_word_enable(5) = '1' else
                6;
next_word(5) <= 6;
next_word(6) <= 0 when input_word_enable(0) = '1' else
                1 when input_word_enable(1) = '1' else
                2 when input_word_enable(2) = '1' else
                3 when input_word_enable(3) = '1' else
                4 when input_word_enable(4) = '1' else
                5 when input_word_enable(5) = '1' else
                6;

output.data(0) <= input_words(next_word(current_word));
output.size <= "000";
output.vc_no <= input_vc_no(next_word(current_word));
output.valid <= '1' when input_valid = '1' and (next_word(current_word) /= 6 or input_word_enable(6) = '1') else '0';
input_ready <= '1' when output_ready = '1' and ((next_word(next_word(current_word)) = 6 and input_word_enable(6) = '0') or (next_word(current_word) = 6 and input_word_enable(6) = '1')) else '0';

choose_next_word : process(clk)
begin
    if rising_edge(clk) then
        if input_valid = '0' then
            current_word <= 6;
        elsif input_valid = '1' and output_ready = '1' then
            if (next_word(next_word(current_word)) /= 6 or input_word_enable(6) = '1') then
                current_word <= next_word(current_word);
            else
                current_word <= 6;
            end if;
        end if;
    end if;
end process;

end Behavioral;
