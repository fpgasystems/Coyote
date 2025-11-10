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

library xpm;
use xpm.vcomponents.all;

entity il_rx_lane_gearbox is
generic (
    METAFRAME : integer := 2048
);
port (
    clk_rx : in std_logic;
    reset  : in std_logic;

    xcvr_rxdata  : in std_logic_vector(63 downto 0);
    xcvr_rxgearboxslip : out std_logic;
    xcvr_rxdatavalid : in std_logic;
    xcvr_rxheader    : in std_logic_vector(2 downto 0);
    xcvr_rxheadervalid : in std_logic;

    output       : out std_logic_vector(63 downto 0);
    output_valid : out std_logic;

    ctrl_word : out std_logic;
    data_word : out std_logic;
    sync_word : out std_logic;
    scrm_word : out std_logic;
    skip_word : out std_logic;
    diag_word : out std_logic;

    word_lock   : out std_logic;
    frame_lock  : out std_logic;
    crc32_bad   : out std_logic;
    lane_status : out std_logic_vector( 1 downto 0)
);
end il_rx_lane_gearbox;

architecture behavioural of il_rx_lane_gearbox is

-- BUILDDEP il_rx_gbx
component il_rx_gbx is
port (
    clk_rx : in std_logic;
    reset  : in std_logic;
    slip : in std_logic;

    input  : in std_logic_vector(63 downto 0);

    output       : out std_logic_vector(66 downto 0);
    output_valid : out std_logic
);
end component;

-- BUILDDEP il_rx_word_lock
component il_rx_word_lock is
port (
    clk_rx : in std_logic;
    reset  : in std_logic;

    input       : in std_logic_vector(66 downto 0);
    input_valid : in std_logic;

    slip : out std_logic;

    word_lock  : out std_logic;
    sync_error : out std_logic
);
end component;

-- BUILDDEP il_rx_framing
component il_rx_framing is
port (
    clk_rx : in std_logic;
    reset  : in std_logic;

    input       : in std_logic_vector(66 downto 0);
    input_valid : in std_logic;

    output       : out std_logic_vector(63 downto 0);
    output_valid : out std_logic;

    ctrl_word : out std_logic;
    data_word : out std_logic;
    sync_word : out std_logic
);
end component;

-- BUILDDEP il_rx_descrambler
component il_rx_descrambler is
port (
    clk_rx : in std_logic;
    reset  : in std_logic;

    input       : in std_logic_vector(63 downto 0);
    input_valid : in std_logic;

    output       : out std_logic_vector(63 downto 0);
    output_valid : out std_logic;

    ctrl_word_in   :  in std_logic;
    ctrl_word_out  : out std_logic;
    data_word_in   :  in std_logic;
    data_word_out  : out std_logic;
    sync_word_in   :  in std_logic;
    sync_word_out  : out std_logic;
    word_lock_in   :  in std_logic;
    word_lock_out  : out std_logic;
    sync_error_in  :  in std_logic;
    sync_error_out : out std_logic;

    scrm_word_out  : out std_logic
);
end component;

-- BUILDDEP il_rx_frame_lock
component il_rx_frame_lock is
generic (
    METAFRAME : integer := 2048
);
port (
    clk_rx : in std_logic;
    reset  : in std_logic;

    word_lock  : in std_logic;
    word_valid : in std_logic;
    sync_word  : in std_logic;

    frame_lock : out std_logic
);
end component;

-- BUILDDEP il_rx_lane_diag
component il_rx_lane_diag is
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
end component;

-- As the gearbox from a 64b transceiver word to a 67b encoded word reduces
-- the effective clock rate, the pipeline stutters.  Thus every data signal is
-- qualified by a _valid strobe.

-- Bit slip signal from the word lock process to the gearbox.
signal slip : std_logic;

-- 67b/64b-encoded words from the RX gearbox.
signal data_67       : std_logic_vector(66 downto 0);
signal data_67_valid : std_logic;

-- Word lock status, synchronous with data_67
signal word_lock_67  : std_logic;
signal sync_error_67 : std_logic;

-- Decoded 64b/67b words, with inversion corrected, and pre-descrambler
-- framing signals.  All synchronous with data_67
signal data_64             : std_logic_vector(63 downto 0);
signal data_64_valid       : std_logic;
signal data_word_64        : std_logic;
signal ctrl_word_64        : std_logic;
signal sync_word_64        : std_logic;

-- The descrambler is applied to the decoded words, and has a pipeline delay.
-- It therefore resynchronises framing and status signals from earlier stages.
-- It also provides the scrambler frame strobe.
signal data_dscrm       : std_logic_vector(63 downto 0);
signal data_dscrm_valid : std_logic;
signal word_lock_dscrm  : std_logic;
signal sync_error_dscrm : std_logic;
signal data_word_dscrm  : std_logic;
signal ctrl_word_dscrm  : std_logic;
signal sync_word_dscrm  : std_logic;
signal scrm_word_dscrm  : std_logic;
signal diag_word_dscrm  : std_logic;

begin

data_67 <= xcvr_rxheader & xcvr_rxdata;
data_67_valid <= xcvr_rxdatavalid;
xcvr_rxgearboxslip <= slip;

-- The word lock module searches for 64 consecutive valid framing bits by
-- sliding the gearbox.  sync_error is asserted synchronous with the input,
-- while word_lock is delayed one cycle.
sync : il_rx_word_lock port map(
    clk_rx      => clk_rx,
    reset       => reset,
    input       => data_67,
    input_valid => data_67_valid,
    slip        => slip,
    word_lock   => word_lock_67,
    sync_error  => sync_error_67
);

-- The pre-descrambler framing detector is purely combinatorial, with no
-- pipeline delay.  This detects sync words.
frame : il_rx_framing port map(
    clk_rx       => clk_rx,
    reset        => reset,
    input        => data_67,
    input_valid  => data_67_valid,
    output       => data_64,
    output_valid => data_64_valid,
    data_word    => data_word_64,
    ctrl_word    => ctrl_word_64,
    sync_word    => sync_word_64
);

-- The descrambler is applied to all words except sync and scrambler state.
-- As there's a pipeline delay, it resynchronises all control signals.
descrambler : il_rx_descrambler port map(
    clk_rx         => clk_rx,
    reset          => reset,
    input          => data_64,
    input_valid    => data_64_valid,
    output         => data_dscrm,
    output_valid   => data_dscrm_valid,
    word_lock_in   => word_lock_67,
    word_lock_out  => word_lock_dscrm,
    sync_error_in  => sync_error_67,
    sync_error_out => sync_error_dscrm,
    ctrl_word_in   => ctrl_word_64,
    ctrl_word_out  => ctrl_word_dscrm,
    data_word_in   => data_word_64,
    data_word_out  => data_word_dscrm,
    sync_word_in   => sync_word_64,
    sync_word_out  => sync_word_dscrm,
    scrm_word_out  => scrm_word_dscrm
);

-- The descrambled payload is passed up, together with synchronous status
-- signals and strobes.
output       <= data_dscrm;
output_valid <= data_dscrm_valid;
word_lock    <= word_lock_dscrm;
ctrl_word    <= ctrl_word_dscrm;
data_word    <= data_word_dscrm;
sync_word    <= sync_word_dscrm;
scrm_word    <= scrm_word_dscrm;

-- We detect and signal skip words at the lane level.
skip_word <= '1' when ctrl_word_dscrm = '1' and
                      data_dscrm(63 downto 58) = B"000111"
                 else '0';

-- The metaframe search logic operates on the descrambled data, as it needs to
-- monitor scrm_bad.
-- frame_lock is delayed by 1 cycle.
lane_frame_lock : il_rx_frame_lock
generic map(
    METAFRAME => METAFRAME
)
port map(
    clk_rx     => clk_rx,
    reset      => reset,
    word_valid => data_dscrm_valid,
    word_lock  => word_lock_dscrm,
    sync_word  => sync_word_dscrm,
    frame_lock => frame_lock
);

-- The diagnostic results are updated on completion of a metaframe, plus
-- pipeline delay for CRC calculation.
lane_diag : il_rx_lane_diag port map(
    clk_rx      => clk_rx,
    reset       => reset,
    input       => data_dscrm,
    input_valid => data_dscrm_valid,

    ctrl_word   => ctrl_word_dscrm,
    sync_word   => sync_word_dscrm,
    scrm_word   => scrm_word_dscrm,
    diag_word   => diag_word_dscrm,

    crc32_bad   => crc32_bad,
    status      => lane_status
);

-- Export lane diagnostics strobe.
diag_word    <= diag_word_dscrm;

end behavioural;
