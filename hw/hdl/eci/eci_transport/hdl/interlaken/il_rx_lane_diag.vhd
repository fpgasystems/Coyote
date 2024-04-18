-------------------------------------------------------------------------------
-- ECI/Interlaken RX per-Lane Diagnostics (including CRC32)
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

entity il_rx_lane_diag is
port (
    clk_rx : in std_logic;
    reset  : in std_logic;

    input       : in std_logic_vector(63 downto 0);
    input_valid : in std_logic;

    ctrl_word :  in std_logic;
    sync_word :  in std_logic;
    scrm_word :  in std_logic;
    diag_word : out std_logic;

    crc32_bad  : out std_logic;
    status     : out std_logic_vector( 1 downto 0)
);
end il_rx_lane_diag;

architecture behavioural of il_rx_lane_diag is

-- BUILDDEP crc32c
component crc32c is
port (
    clk    :  in std_logic;
    reset  :  in std_logic;
    enable :  in std_logic;
    init   :  in std_logic;
    input  :  in std_logic_vector(63 downto 0);
    output : out std_logic_vector(31 downto 0)
);
end component;

alias field_bt  : std_logic_vector( 5 downto 0) is input(63 downto 58);
alias field_st  : std_logic_vector( 1 downto 0) is input(33 downto 32);
alias field_crc : std_logic_vector(31 downto 0) is input(31 downto  0);

signal crc32_input    : std_logic_vector(63 downto 0);
signal crc32_output   : std_logic_vector(31 downto 0);
signal crc32_received : std_logic_vector(31 downto 0);

signal diag_word_int : std_logic;

begin

diag_word_int <= '1' when input_valid = '1' and
                          ctrl_word = '1' and
                          field_bt = B"011001"
            else '0';
diag_word <= diag_word_int;

-- The scrambler state and CRC fields are taken as zero when calculating the
-- CRC.
crc32_input <= field_bt & B"00" & X"00000000000000" when scrm_word = '1'
          else input(63 downto 34) & field_st & X"00000000" when
            diag_word_int = '1'
          else input;

crc : crc32c port map(
    clk    => clk_rx,
    reset  => reset,
    enable => input_valid,
    -- The CRC is initialised to all ones at the start of every frame.
    init   => sync_word,
    input  => crc32_input,
    output => crc32_output
);

monitor : process(clk_rx)
begin
    if rising_edge(clk_rx) then
        if reset = '1' then
            crc32_received <= (others => '0');
            crc32_bad      <= '0';
            status         <= (others => '0');
        else
            if input_valid = '1' then
                if ctrl_word = '1' and diag_word_int = '1' then
                    -- Update the status bits, and remember the transmitted
                    -- CRC, so that we can check it against the calculated
                    -- value after the pipeline delay.
                    status         <= field_st;
                    crc32_received <= field_crc;
                elsif ctrl_word = '1' and sync_word = '1' then
                    -- Check the CRC output after one cycle.
                    if crc32_output = crc32_received then
                        crc32_bad <= '0';
                    else
                        crc32_bad <= '1';
                    end if;
                end if;
            end if;
        end if;
    end if;
end process;

end behavioural;
