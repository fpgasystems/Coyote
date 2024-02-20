----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Manage transmitting credits
-- Receive returned credits, each bit for every VC, add them to the credit counters
-- Check if incoming message can be sent (i.e. there's enough credits for a given message)
-- lo channels expects only lo VCs (0-1 and 6-12), only 1-word messages
-- hi channels expects all VCs (0-12), any message length
-- Subtract the number of sent words from the counters

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity tlk_credits is
port (
    clk             : in std_logic;
    rst_n           : in std_logic;

    in_hi           : in ECI_CHANNEL;
    in_hi_ready     : out std_logic;
    in_lo           : in ECI_CHANNEL;
    in_lo_ready     : out std_logic;

    out_hi          : out ECI_CHANNEL;
    out_hi_ready    : in std_logic;
    out_lo          : out ECI_CHANNEL;
    out_lo_ready    : in std_logic;

    credit_return   : in std_logic_vector(12 downto 0)
);
end tlk_credits;

architecture Behavioral of tlk_credits is

component eci_channel_buffer is
port (
    clk             : in STD_LOGIC;
    input           : in ECI_CHANNEL;
    input_ready     : out STD_LOGIC;
    output          : out ECI_CHANNEL;
    output_ready    : in STD_LOGIC
);
end component;

type HI_CREDIT is array (integer range <>) of unsigned(7 downto 0);
type LO_CREDIT is array (integer range <>) of unsigned(4 downto 0);
signal hi_credits_available : HI_CREDIT(5 downto 0) := (to_unsigned(256-2, 8), to_unsigned(256-2, 8), to_unsigned(256-17, 8), to_unsigned(256-17, 8), to_unsigned(256-17, 8), to_unsigned(256-17, 8)); -- from -17 to 239 or from -2 to 254
signal lo_credits_available : LO_CREDIT(12 downto 6) := (to_unsigned(32-2, 5), to_unsigned(32-2, 5), to_unsigned(32-2, 5), to_unsigned(32-2, 5), to_unsigned(32-2, 5), to_unsigned(32-2, 5), to_unsigned(32-2, 5)); -- from -2 to 30/31
signal in_hi_credits    : integer;
signal rst_n_old        : std_logic := '0';
signal in_hi_vc_no      : integer range 0 to 12;
signal credits_und      : std_logic_vector(12 downto 0) := (others => '1'); -- if available credits number is negative

signal in_hi_buf           : ECI_CHANNEL;
signal in_hi_ready_buf     : std_logic;
signal in_lo_buf           : ECI_CHANNEL;
signal in_lo_ready_buf     : std_logic;
signal in_lo_vc_no      : integer;

signal in_hi_ready_b   : std_logic;
signal in_lo_ready_b   : std_logic;
signal out_hi_words_b  : WORDS (8 downto 0);
signal out_hi_vc_b     : std_logic_vector(3 downto 0);
signal out_hi_size_b   : std_logic_vector(2 downto 0);
signal out_hi_valid_b  : std_logic := '0';
signal out_lo_word_b   : std_logic_vector(63 downto 0);
signal out_lo_vc_b     : std_logic_vector(3 downto 0);
signal out_lo_valid_b  : std_logic := '0';
signal part1, part2, part3 : std_logic;

function update_und(oldu : std_logic; oldc : unsigned; newc : unsigned) return std_logic is
begin
    if oldc(oldc'LEFT downto oldc'LEFT-1) = "00" and newc(newc'LEFT downto newc'LEFT-1) = "11" then
        return '1';
    elsif oldc(oldc'LEFT downto oldc'LEFT-1) = "11" and newc(newc'LEFT downto newc'LEFT-1) = "00" then
        return '0';
    end if;
    return oldu;
end function update_und;

begin

i_hi_buffer : eci_channel_buffer
port map (
    clk             => clk,
    input           => in_hi,
    input_ready     => in_hi_ready,
    output          => in_hi_buf,
    output_ready    => in_hi_ready_buf
);

i_lo_buffer : eci_channel_buffer
port map (
    clk             => clk,
    input           => in_lo,
    input_ready     => in_lo_ready,
    output          => in_lo_buf,
    output_ready    => in_lo_ready_buf
);

in_hi_ready_buf <= in_hi_ready_b;
in_lo_ready_buf <= in_lo_ready_b;
out_hi.data <= out_hi_words_b;
out_hi.vc_no <= out_hi_vc_b;
out_hi.size <= out_hi_size_b;
out_hi.valid <= out_hi_valid_b;
out_lo.data(0) <= out_lo_word_b;
out_lo.vc_no <= out_lo_vc_b;
out_lo.valid <= out_lo_valid_b;

in_hi_credits <=
    1 when in_hi_buf.size = ECI_CHANNEL_SIZE_1 else -- 1 of 1
    5 when in_hi_buf.size = ECI_CHANNEL_SIZE_5 else -- 1 of 1
    9 when in_hi_buf.size = ECI_CHANNEL_SIZE_9 else -- 1 of 1
    9 when in_hi_buf.size = ECI_CHANNEL_SIZE_9_1 else -- 1 of 2
    4 when in_hi_buf.size = ECI_CHANNEL_SIZE_13_2 else -- 2 of 2
    8; -- "ECI_CHANNEL_SIZE_17_2                    -- 2 of 2

in_hi_vc_no <= to_integer(unsigned(in_hi_buf.vc_no));
in_lo_vc_no <= to_integer(unsigned(in_lo_buf.vc_no));

in_hi_ready_b <=
    '1' when credits_und(in_hi_vc_no) = '0' and (out_hi_valid_b = '0' or (out_hi_valid_b = '1' and out_hi_ready = '1')) else
    '0';

in_lo_ready_b <= 
    '1' when (in_lo_vc_no >= 13 or credits_und(in_lo_vc_no) = '0') and (out_lo_valid_b = '0' or (out_lo_valid_b = '1' and out_lo_ready = '1')) else
    '0';

i_process : process (clk)
    variable i, j         : integer;
    variable new_hi_credits : HI_CREDIT(5 downto 0);
    variable new_lo_credits : LO_CREDIT(12 downto 6);
begin
    if rising_edge(clk) then
        rst_n_old <= rst_n;
        if rst_n_old = '1' and rst_n = '0' then -- reset the credits on the falling edge, not on the level, because credits can arrive one cycle before deasserted rst_n
            out_hi_valid_b <= '0';
            out_lo_valid_b <= '0';
            for i in 0 to 1 loop
                hi_credits_available(i) <= to_unsigned(256-2, 8);
                credits_und(i) <= '1';
            end loop;
            for i in 2 to 5 loop
                hi_credits_available(i) <= to_unsigned(256-17, 8);
                credits_und(i) <= '1';
            end loop;
            for i in 6 to 12 loop
                lo_credits_available(i) <= to_unsigned(32-2, 5);
                credits_und(i) <= '1';
            end loop;
        else
            for i in 0 to 5 loop
                new_hi_credits(i) := hi_credits_available(i);
                if credit_return(i) = '1' then
                    new_hi_credits(i) := new_hi_credits(i) + 8;
                end if; 
            end loop;
            for i in 6 to 12 loop
                new_lo_credits(i) := lo_credits_available(i);
                if credit_return(i) = '1' then
                    new_lo_credits(i) := new_lo_credits(i) + 8;
                end if; 
            end loop;

            if in_hi_ready_b = '1' and in_hi_buf.valid = '1' then
                if in_hi_vc_no <= 5 then
                    new_hi_credits(in_hi_vc_no) := new_hi_credits(in_hi_vc_no) - in_hi_credits;
                else
                    new_lo_credits(in_hi_vc_no) := new_lo_credits(in_hi_vc_no) - 1;
                end if;
                out_hi_valid_b <= '1';
                out_hi_words_b <= in_hi_buf.data;
                out_hi_vc_b    <= in_hi_buf.vc_no;
                out_hi_size_b  <= in_hi_buf.size;
            elsif out_hi_valid_b = '1' and out_hi_ready = '1' then
                out_hi_valid_b <= '0';
            end if;

            if in_lo_ready_b = '1' and in_lo_buf.valid = '1' then
                new_lo_credits(in_lo_vc_no) := new_lo_credits(in_lo_vc_no) - 1;
                out_lo_valid_b <= '1';
                out_lo_word_b  <= in_lo_buf.data(0);
                out_lo_vc_b    <= in_lo_buf.vc_no;
            elsif out_lo_valid_b = '1' and out_lo_ready = '1' then
                out_lo_valid_b <= '0';
            end if;

            for i in 0 to 5 loop
                credits_und(i) <= update_und(credits_und(i), hi_credits_available(i), new_hi_credits(i));
                hi_credits_available(i) <= new_hi_credits(i);
            end loop;
            for i in 6 to 12 loop
                credits_und(i) <= update_und(credits_und(i), lo_credits_available(i), new_lo_credits(i));
                lo_credits_available(i) <= new_lo_credits(i);
            end loop;
        end if;
    end if;
end process;

end Behavioral;
