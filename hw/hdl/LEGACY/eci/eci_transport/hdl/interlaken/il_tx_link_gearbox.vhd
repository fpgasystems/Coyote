-------------------------------------------------------------------------------
-- ECI/Interlaken RX Link Logic
-- A link is a bundle of aligned lanes, across which data is striped.
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
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

entity il_tx_link_gearbox is
generic (
    LANES : integer := 1;
    METAFRAME : integer := 2048
);
port (
    clk_tx : in std_logic;
    reset  : in std_logic;

    input        :  in std_logic_vector(LANES*64 - 1 downto 0);
    input_ready  : out std_logic;
    ctrl_word_in :  in std_logic_vector(LANES - 1 downto 0);

    xcvr_txdata  : out std_logic_vector(LANES*64 - 1 downto 0);
    xcvr_txheader     : out std_logic_vector(6*LANES-1 downto 0);
    xcvr_txsequence   : out std_logic_vector(7*LANES-1 downto 0)
);
end il_tx_link_gearbox;

architecture behavioural of il_tx_link_gearbox is

-- BUILDDEP il_tx_lane
component il_tx_lane_gearbox is
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
end component;

signal tx_sequence      : integer range 0 to 66 := 0;
signal tx_sequence_int  : std_logic_vector(6 downto 0);
signal tx_ready         : std_logic;
signal metaframe_pos    : integer range 0 to 31 := 0;

signal ctrl_word_mf     : std_logic_vector(LANES - 1 downto 0);

signal ctrl_word        : std_logic;
signal sync_word        : std_logic;
signal scrm_word        : std_logic;
signal skip_word        : std_logic;
signal diag_word        : std_logic;

begin

tx_cycle : process(clk_tx)
begin
    if rising_edge(clk_tx) then
        if tx_sequence = 66 then
            tx_sequence <= 0;
            if metaframe_pos = 31 then
                metaframe_pos <= 0;
                ctrl_word <= '1';
                diag_word <= '1';
            else
                metaframe_pos <= metaframe_pos + 1;
                input_ready <= '1';
            end if;
            tx_ready <= '1';
        else
            tx_sequence <= tx_sequence + 1;
            if metaframe_pos = 0 and tx_sequence = 0 then
                diag_word <= '0';
                sync_word <= '1';
            elsif metaframe_pos = 0 and tx_sequence = 1 then
                sync_word <= '0';
                scrm_word <= '1';
            elsif metaframe_pos = 0 and tx_sequence = 2 then
                scrm_word <= '0';
                skip_word <= '1';
            else
                skip_word <= '0';
                ctrl_word <= '0';
                if tx_sequence = 21 or tx_sequence = 43 or tx_sequence = 65 then
                    tx_ready <= '0';
                    input_ready <= '0';
                else
                    tx_ready <= '1';
                    input_ready <= '1';
                end if;
            end if;
        end if;
        tx_sequence_int <= std_logic_vector(to_unsigned(tx_sequence, 7));
    end if;
end process;

gen_tx :
for i in 0 to LANES - 1 generate
    xcvr_txsequence(i*7 + 6 downto i*7) <= tx_sequence_int(6 downto 0);
end generate;

tx_lanes :
for i in 0 to LANES - 1 generate
    ctrl_word_mf(i) <= ctrl_word_in(i) or ctrl_word;

    tx_lane_X : il_tx_lane_gearbox
    generic map(
        METAFRAME => METAFRAME
    )
    port map (
        clk_tx         => clk_tx,
        reset          => reset,
        scrambler_init => X"1111111111111" & B"00" &
                          std_logic_vector(to_unsigned(i, 4)),
        input          => input(64*i + 63 downto 64*i),
        lane_status    => B"00",
        ctrl_word_in   => ctrl_word_mf(i),

        sync_word_in    => sync_word,
        scrm_word_in    => scrm_word,
        skip_word_in    => skip_word,
        diag_word_in    => diag_word,

        xcvr_txdata    => xcvr_txdata(64*i + 63 downto 64*i),
        xcvr_txheader  => xcvr_txheader(6*i + 5 downto 6*i),
        xcvr_txdata_ready => tx_ready
    );
end generate;

end behavioural;
