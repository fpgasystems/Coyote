-------------------------------------------------------------------------------
-- ECI/Interlaken RX Lane Logic
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

entity il_tx_lane_gearbox is
generic (
    METAFRAME : integer := 2048
);
port (
    clk_tx : in std_logic;
    reset  : in std_logic;

    scrambler_init : in std_logic_vector(57 downto 0);

    input       :  in std_logic_vector(63 downto 0);

    lane_status  : in std_logic_vector(1 downto 0);
    ctrl_word_in : in std_logic;

    sync_word_in    : in std_logic;
    scrm_word_in    : in std_logic;
    skip_word_in    : in std_logic;
    diag_word_in    : in std_logic;

    xcvr_txdata : out std_logic_vector(63 downto 0);
    xcvr_txheader : out std_logic_vector(5 downto 0);
    xcvr_txdata_ready : in std_logic
);
end il_tx_lane_gearbox;

architecture behavioural of il_tx_lane_gearbox is

-- BUILDDEP il_tx_metaframe
component il_tx_metaframe is
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
end component;

-- BUILDDEP il_tx_lane_diag
component il_tx_lane_diag is
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

    ctrl_word_out : out std_logic;
    sync_word_out : out std_logic;
    scrm_word_out : out std_logic;
    skip_word_out : out std_logic;
    diag_word_out : out std_logic
);
end component;

-- BUILDDEP il_tx_scrambler
component il_tx_scrambler is
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
end component;

-- BUILDDEP il_tx_framing
component il_tx_framing is
port (
    clk_tx : in std_logic;
    reset  : in std_logic;

    input       :  in std_logic_vector(63 downto 0);

    output       : out std_logic_vector(66 downto 0);
    output_ready :  in std_logic;

    ctrl_word :  in std_logic
);
end component;

-- BUILDDEP il_tx_gbx
component il_tx_gbx is
port (
    clk_tx : in std_logic;
    reset  : in std_logic;

    input       : in std_logic_vector(66 downto 0);
    input_ready : out std_logic;

    output : out std_logic_vector(63 downto 0)
);
end component;

-- Stream with metaframe control words inserted.
signal data_mf       : std_logic_vector(63 downto 0);

-- Stream with diagnostic word CRC inserted.
signal data_diag       : std_logic_vector(63 downto 0);
signal ctrl_word_diag  : std_logic;
signal sync_word_diag  : std_logic;
signal scrm_word_diag  : std_logic;
signal skip_word_diag  : std_logic;
signal diag_word_diag  : std_logic;

-- Scrambled stream, with scrambler state inserted into scrm word.
signal data_scrm       : std_logic_vector(63 downto 0);

-- 64/67 framed stream.
signal data_67       : std_logic_vector(66 downto 0);

begin

tx_metaframe : il_tx_metaframe
generic map(
    METAFRAME => METAFRAME
)
port map(
    clk_tx        => clk_tx,
    reset         => reset,
    input         => input,
    output        => data_mf,
    output_ready  => xcvr_txdata_ready,
    sync_word_in  => sync_word_in,
    scrm_word_in  => scrm_word_in,
    skip_word_in  => skip_word_in,
    diag_word_in  => diag_word_in
);

tx_lane_diag : il_tx_lane_diag
port map(
    clk_tx        => clk_tx,
    reset         => reset,
    input         => data_mf,
    ctrl_word_in  => ctrl_word_in,
    sync_word_in  => sync_word_in,
    scrm_word_in  => scrm_word_in,
    skip_word_in  => skip_word_in,
    diag_word_in  => diag_word_in,
    status_in     => lane_status,
    output        => data_diag,
    output_ready  => xcvr_txdata_ready,
    ctrl_word_out => ctrl_word_diag,
    sync_word_out => sync_word_diag,
    scrm_word_out => scrm_word_diag,
    skip_word_out => skip_word_diag,
    diag_word_out => diag_word_diag
);

tx_scrambler : il_tx_scrambler
port map(
    clk_tx       => clk_tx,
    reset        => reset,
    init_state   => scrambler_init,
    input        => data_diag,
    sync_word_in => sync_word_diag,
    scrm_word_in => scrm_word_diag,
    output       => data_scrm,
    output_ready => xcvr_txdata_ready
);

tx_framing : il_tx_framing
port map(
    clk_tx       => clk_tx,
    reset        => reset,
    input        => data_scrm,
    output       => data_67,
    output_ready => xcvr_txdata_ready,
    ctrl_word    => ctrl_word_diag
);

xcvr_txdata <= data_67(63 downto 0);
xcvr_txheader <= "000" & data_67(66 downto 64);

end behavioural;
