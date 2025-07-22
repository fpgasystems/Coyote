-------------------------------------------------------------------------------
-- ECI/Interlaken Metaframe Generation
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

entity il_tx_metaframe is
generic (
    METAFRAME : integer
);
port (
    clk_tx : in std_logic;
    reset  : in std_logic;

    input        :  in std_logic_vector(63 downto 0);

    output        : out std_logic_vector(63 downto 0);
    output_ready  :  in std_logic;

    sync_word_in    : in std_logic;
    scrm_word_in    : in std_logic;
    skip_word_in    : in std_logic;
    diag_word_in    : in std_logic
);
end il_tx_metaframe;

architecture behavioural of il_tx_metaframe is

-- The Sync and Skip words have a fixed format, while the Scrambler and
-- Diagnostic words have fields to be filled in.  We transmit the these as
-- zeroes here, and they'll be filled in by the relevant modules.
constant SYNC_WORD : std_logic_vector(63 downto 0) := X"78F678F678F678F6";
constant SCRM_WORD : std_logic_vector(63 downto 0) := X"2800000000000000";
constant SKIP_WORD : std_logic_vector(63 downto 0) := X"1E1E1E1E1E1E1E1E";
constant DIAG_WORD : std_logic_vector(63 downto 0) := X"6400000000000000";

begin

-- We signal the position of the metaframe control words so that other
-- modules don't need to track the frame position.

-- In the metaframe control word positions, we send our own control words, and
-- otherwise forward the payload.
output <=
    SYNC_WORD when sync_word_in = '1' else
    SCRM_WORD when scrm_word_in = '1' else
    SKIP_WORD when skip_word_in = '1' else
    DIAG_WORD when diag_word_in = '1' else
    input;

end behavioural;
