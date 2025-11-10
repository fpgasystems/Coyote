-------------------------------------------------------------------------------
-- ECI/Interlaken TX per-Lane Diagnostics (including CRC32)
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

entity il_tx_lane_diag is
port (
    clk_tx : in std_logic;
    reset  : in std_logic;

    input       :  in std_logic_vector(63 downto 0);

    ctrl_word_in : in std_logic;
    sync_word_in : in std_logic;
    scrm_word_in : in std_logic;
    skip_word_in : in std_logic;
    diag_word_in : in std_logic;

    status_in : in std_logic_vector( 1 downto 0);

    output       : out std_logic_vector(63 downto 0);
    output_ready :  in std_logic;

    -- This introduces a pipeline delay of one, so we must resynchronise the
    -- strobes.
    ctrl_word_out : out std_logic;
    sync_word_out : out std_logic;
    scrm_word_out : out std_logic;
    skip_word_out : out std_logic;
    diag_word_out : out std_logic
);
end il_tx_lane_diag;

architecture behavioural of il_tx_lane_diag is

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

signal crc32_input  : std_logic_vector(63 downto 0);
signal crc32_output : std_logic_vector(31 downto 0);
--signal crc32_last   : std_logic_vector(31 downto 0);

signal output_reg : std_logic_vector(63 downto 0);

signal diag_word : std_logic;

begin

-- The scrambler state and CRC fields that are passed to us will have been
-- initialised to zero, and thus we don't need to mask them, as on the RX
-- path.  We do need to incorporate the diagnostic bits before the CRC,
-- however.
crc32_input <= input(63 downto 34) & status_in & input(31 downto 0)
               when diag_word_in = '1' else input;

crc : crc32c port map(
    clk    => clk_tx,
    reset  => reset,
    -- Pipeline advance is controlled by backpressure.
    enable => output_ready,
    -- The CRC is initialised to all ones at the start of every frame.
    init   => sync_word_in,
    input  => crc32_input,
    output => crc32_output
);

diag_word_out <= diag_word;

output <= output_reg(63 downto 34) & status_in & crc32_output
          when diag_word = '1'
          else output_reg;

step : process(clk_tx)
begin
    if rising_edge(clk_tx) then
        if output_ready = '1' then -- and reset = '0'
            -- Delay the data to wait for the CRC result.
            output_reg <= input;

            -- Delay the strobes.
            ctrl_word_out <= ctrl_word_in;
            sync_word_out <= sync_word_in;
            scrm_word_out <= scrm_word_in;
            skip_word_out <= skip_word_in;
            diag_word     <= diag_word_in;
        end if;
    end if;
end process;

end behavioural;
