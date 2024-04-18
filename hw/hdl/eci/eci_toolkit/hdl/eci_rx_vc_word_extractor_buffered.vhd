----------------------------------------------------------------------------------
-- Module Name: eci_rx_vc_word_extractor_buffered - Behavioral
----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Extract one by one words from a frame and put them into the channel, with a buffer, 1 cycle latency

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.eci_defs.all;

entity eci_rx_vc_word_extractor_buffered is
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
end eci_rx_vc_word_extractor_buffered;


architecture Behavioral of eci_rx_vc_word_extractor_buffered is

type POSITIONS is array (integer range <>) of integer range 0 to 7;

signal current_word : integer range 0 to 7 := 7;
signal next_word : POSITIONS(0 to 7);
signal input_ready_b         : std_logic;

begin

input_ready <= input_ready_b;

next_word(0) <= 1 when input_word_enable(1) = '1' else
                2 when input_word_enable(2) = '1' else
                3 when input_word_enable(3) = '1' else
                4 when input_word_enable(4) = '1' else
                5 when input_word_enable(5) = '1' else
                6 when input_word_enable(6) = '1' else
                7;
next_word(1) <= 2 when input_word_enable(2) = '1' else
                3 when input_word_enable(3) = '1' else
                4 when input_word_enable(4) = '1' else
                5 when input_word_enable(5) = '1' else
                6 when input_word_enable(6) = '1' else
                7;
next_word(2) <= 3 when input_word_enable(3) = '1' else
                4 when input_word_enable(4) = '1' else
                5 when input_word_enable(5) = '1' else
                6 when input_word_enable(6) = '1' else
                7;
next_word(3) <= 4 when input_word_enable(4) = '1' else
                5 when input_word_enable(5) = '1' else
                6 when input_word_enable(6) = '1' else
                7;
next_word(4) <= 5 when input_word_enable(5) = '1' else
                6 when input_word_enable(6) = '1' else
                7;
next_word(5) <= 6 when input_word_enable(6) = '1' else
                7;
next_word(6) <= 7;
next_word(7) <= 0 when input_word_enable(0) = '1' else
                1 when input_word_enable(1) = '1' else
                2 when input_word_enable(2) = '1' else
                3 when input_word_enable(3) = '1' else
                4 when input_word_enable(4) = '1' else
                5 when input_word_enable(5) = '1' else
                6 when input_word_enable(6) = '1' else
                7;

output.size <= "000";

choose_next_word : process(clk)
begin
    if rising_edge(clk) then
        if input_valid = '0' then
            current_word <= 7;
            input_ready_b <= '0';
            output.valid <= '0';
        elsif input_valid = '1' then
            if input_ready_b = '1' then
                input_ready_b <= '0';
            else
                if current_word = 7 then -- first word
                    current_word <= next_word(current_word);
                    output.data(0) <= input_words(next_word(current_word));
                    output.vc_no <= input_vc_no(next_word(current_word));
                    output.valid <= '1';
                elsif output_ready = '1' then
                    if next_word(current_word) = 7 then -- last word
                        current_word <= 7;
                        input_ready_b <= '1';
                        output.valid <= '0';
                    else
                        current_word <= next_word(current_word);
                        output.data(0) <= input_words(next_word(current_word));
                        output.vc_no <= input_vc_no(next_word(current_word));
                        output.valid <= '1';
                    end if;
                end if;
            end if;
        end if;
    end if;
end process;

end Behavioral;
