-------------------------------------------------------------------------------
-- CRC32C (Castagnoli), with 64b input.
-- Reset to ones, with inverted output.  Input and output are MSB-first.
-- Pipeline delay: 1 cycle.
--
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

entity crc32c is
port (
    clk    :  in std_logic;
    reset  :  in std_logic;
    init   :  in std_logic;
    enable :  in std_logic;
    input  :  in std_logic_vector(63 downto 0);
    output : out std_logic_vector(31 downto 0)
);
end crc32c;

architecture behavioural of crc32c is

component crc_64_32_1edc6f41 is
port (
    R   :  in std_logic_vector(31 downto 0);
    X   :  in std_logic_vector(63 downto 0);
    R_n : out std_logic_vector(31 downto 0)
);
end component;

signal remainder : std_logic_vector(31 downto 0);
signal R   : std_logic_vector(31 downto 0);
signal R_n : std_logic_vector(31 downto 0);

begin

-- We take the output from 'remainder', and not from R_n, in order to add a
-- one-cycle delay.  The CRC is a complex function, and I hope this will make
-- timing closure a bit easier.
output <= not remainder;

-- If init is asserted, calculate the next state as if the CRC had been reset.
-- This allows the calculation to be reset without missing an input word.
R <= X"FFFFFFFF" when init = '1' else remainder;

-- The CRC XOR network is purely combinatorial.
crc_net : crc_64_32_1edc6f41
port map (
    R   => R,
    X   => input,
    R_n => R_n
);

step : process(clk)
begin
    if rising_edge(clk) then
        if reset = '1' then
            -- Reset to ones.
            remainder <= (others => '1');
        elsif enable = '1' then
            remainder <= R_n;
        end if;
    end if;
end process;

end behavioural;
