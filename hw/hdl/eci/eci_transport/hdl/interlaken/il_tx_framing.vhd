-------------------------------------------------------------------------------
-- ECI/Interlaken 67/64 Encoder
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

entity il_tx_framing is
port (
    clk_tx : in std_logic;
    reset  : in std_logic;

    input       :  in std_logic_vector(63 downto 0);

    output       : out std_logic_vector(66 downto 0);
    output_ready :  in std_logic;

    ctrl_word :  in std_logic
);
end il_tx_framing;

architecture behavioural of il_tx_framing is

signal running_disparity : signed(8 downto 0) := "000000000"; -- -256 to 255
signal word_disparity    : signed(7 downto 0); -- -128 to 127

signal invert_bit  : std_logic;
signal frame_bits  : std_logic_vector( 1 downto 0);
signal payload     : std_logic_vector(63 downto 0);

function disparity_4(X : std_logic_vector(3 downto 0))
    return signed is
begin
    case X is
        when "0000" => return to_signed(-4, 4);
        when "0001" => return to_signed(-2, 4);
        when "0010" => return to_signed(-2, 4);
        when "0011" => return to_signed( 0, 4);
        when "0100" => return to_signed(-2, 4);
        when "0101" => return to_signed( 0, 4);
        when "0110" => return to_signed( 0, 4);
        when "0111" => return to_signed(+2, 4);
        when "1000" => return to_signed(-2, 4);
        when "1001" => return to_signed( 0, 4);
        when "1010" => return to_signed( 0, 4);
        when "1011" => return to_signed(+2, 4);
        when "1100" => return to_signed( 0, 4);
        when "1101" => return to_signed(+2, 4);
        when "1110" => return to_signed(+2, 4);
        when "1111" => return to_signed(+4, 4);
    end case;
end function;

function disparity_16(X : std_logic_vector(15 downto 0))
    return signed is
begin
    return resize(disparity_4(X(15 downto 12)), 6) +
           resize(disparity_4(X(11 downto  8)), 6) +
           resize(disparity_4(X( 7 downto  4)), 6) +
           resize(disparity_4(X( 3 downto  0)), 6);
end function;

function disparity_64(X : std_logic_vector(63 downto 0))
    return signed is
begin
    return resize(disparity_16(X(63 downto 48)), 8) +
           resize(disparity_16(X(47 downto 32)), 8) +
           resize(disparity_16(X(31 downto 16)), 8) +
           resize(disparity_16(X(15 downto  0)), 8);
end function;

begin

word_disparity <= disparity_64(input);

invert_bit  <= '1' when (word_disparity /= "00000000" and running_disparity(8) = word_disparity(7)) or (word_disparity = "00000000" and running_disparity < 0) else '0';
frame_bits  <= B"10" when ctrl_word = '1' else B"01";
payload     <= not input when invert_bit = '1' else input;
output      <= invert_bit & frame_bits & payload;

-- Keep track of the running disparity (1s - 0s) in the output.
track_disparity : process(clk_tx)
begin
    if rising_edge(clk_tx) then
        if reset = '1' then
            running_disparity <= to_signed(0, 9);
        else
            if output_ready = '1' then
                if invert_bit = '1' then
                    running_disparity <=
                        running_disparity -
                        -- If we invert the output we invert the disparity of the
                        -- payload (the frame bits are balanced).
                        resize(word_disparity, 9) +
                        -- The invert bit itself contributes to disparity.
                        to_signed(1, 9);
                else
                    running_disparity <=
                        running_disparity +
                        resize(word_disparity, 9) -
                        to_signed(1, 9);
                end if;
            end if;
        end if;
    end if;
end process;

end behavioural;
