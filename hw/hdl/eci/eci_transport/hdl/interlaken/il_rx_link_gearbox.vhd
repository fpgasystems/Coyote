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

library xpm;
use xpm.vcomponents.all;

entity il_rx_link_gearbox is
generic (
    LANES : integer := 12;
    METAFRAME : integer := 2048
);
port (
    clk_rx : in std_logic;
    reset  : in std_logic;

    xcvr_rxdata     : in std_logic_vector(LANES*64 - 1 downto 0);
    xcvr_rxdatavalid : in std_logic_vector(2*LANES - 1 downto 0);
    xcvr_rxheader    : in std_logic_vector(6*LANES - 1 downto 0);
    xcvr_rxheadervalid : in std_logic_vector(2*LANES - 1 downto 0);
    xcvr_rxgearboxslip : out std_logic_vector(LANES - 1 downto 0);

    output          : out std_logic_vector(LANES*64 - 1 downto 0);
    output_valid    : out std_logic;
    ctrl_word_out   : out std_logic_vector(LANES - 1 downto 0);

    lane_word_lock  : out std_logic_vector(  LANES - 1 downto 0);
    lane_frame_lock : out std_logic_vector(  LANES - 1 downto 0);
    lane_crc32_bad  : out std_logic_vector(  LANES - 1 downto 0);
    lane_status     : out std_logic_vector(2*LANES - 1 downto 0);

    link_aligned    : out std_logic;
    total_skew      : out std_logic_vector(2 downto 0)
);
end il_rx_link_gearbox;

architecture behavioural of il_rx_link_gearbox is

-- BUILDDEP il_rx_lane
component il_rx_lane_gearbox is
generic (
    METAFRAME : integer
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
end component;

component il_rx_lane_sync is
Port ( clk : in STD_LOGIC;
       input : in STD_LOGIC_VECTOR (69 downto 0);
       input_valid : in STD_LOGIC;
       delay : in STD_LOGIC_VECTOR (2 downto 0);
       delay_enabled : in STD_LOGIC;
       output : out STD_LOGIC_VECTOR (69 downto 0);
       output_valid : in std_logic
);
end component;

-- These are the unaligned data and status from the RX lanes,
-- unsynchronized to the first lane valid signal
signal lane_data           : std_logic_vector(64*LANES - 1 downto 0);
signal lane_data_valid     : std_logic_vector(   LANES - 1 downto 0);
signal lane_ctrl_word_int  : std_logic_vector(   LANES - 1 downto 0);
signal lane_data_word      : std_logic_vector(   LANES - 1 downto 0);
signal lane_sync_word      : std_logic_vector(   LANES - 1 downto 0);
signal lane_scrm_word      : std_logic_vector(   LANES - 1 downto 0);
signal lane_skip_word      : std_logic_vector(   LANES - 1 downto 0);
signal lane_diag_word      : std_logic_vector(   LANES - 1 downto 0);
signal lane_word_lock_int  : std_logic_vector(   LANES - 1 downto 0);
signal lane_frame_lock_int : std_logic_vector(   LANES - 1 downto 0);
signal lane_crc32_bad_int  : std_logic_vector(   LANES - 1 downto 0);
signal lane_status_int     : std_logic_vector( 2*LANES - 1 downto 0);

-- These are the aligned word strobes *after* the FIFOs.
signal lane_ctrl_word_out : std_logic_vector(   LANES - 1 downto 0);
signal lane_data_word_out : std_logic_vector(   LANES - 1 downto 0);
signal lane_sync_word_out : std_logic_vector(   LANES - 1 downto 0);
signal lane_scrm_word_out : std_logic_vector(   LANES - 1 downto 0);
signal lane_skip_word_out : std_logic_vector(   LANES - 1 downto 0);
signal lane_diag_word_out : std_logic_vector(   LANES - 1 downto 0);

signal output_int       : std_logic_vector(LANES*64 - 1 downto 0);
signal xcvr_rxgearboxslip_int : std_logic_vector(LANES - 1 downto 0);

-- Any metaframe-length window will contain exactly one sync word for each lane
-- (assuming that the inter-sync distance is stable).  In the absence of a
-- sequence number we cannot unambiguously determine which sync words should
-- be aligned.
--
-- We assume that the skew is small relative to the length of the metaframe,
-- and thus the correct window is the one that minimises the span between the
-- first and last sync words.
--
-- To find this, we need to check every possible window start position.
-- Rather than try to implement this O(nlanes) search, we take advantage of
-- the periodicity of the input: If we track the relative position of the last
-- word seen on each lane then, over the course of a metaframe, we will have
-- seen every possible window position.

type pos_array is array(integer range <>) of unsigned(2 downto 0);

-- We record the position of the sync word on each frame within the preceeding
-- metaframe-length window.
signal link_aligned_counter : unsigned(11 downto 0) := to_unsigned(0, 12);

-- Once we know the minimum span, we can calculate skew.  We wait until we see
-- a sync packet arrive at a time when the current span is equal to the
-- minimum.  Any lanes that sync on that cycle are the stragglers, and all
-- other lanes need to be delayed relative to them.
signal skew : pos_array(LANES - 1 downto 0) := (others => (others => '0'));

-- Once we've calculated the per-lane skew, we deskew by inhibiting the read
-- strobe on the FIFOs for the lanes with a non-zero skew (those that synced
-- *earlier*).  This increases the number of words buffered in the FIFO for
-- those lanes, aligning them with the stragglers.  The amount of skew we can
-- compensate for is thus limited by the FIFO depth.  If the minimum span is
-- more than this (minus a margin), we bail out.
signal deskew_started_int : std_logic := '0';
signal delay_enabled : std_logic := '0';
signal link_aligned_int : std_logic;
signal got_sync     : std_logic_vector(LANES - 1 downto 0) := (others => '0');
signal deskewed     : std_logic := '0';

begin

ctrl_word_out <= lane_ctrl_word_out;

lane_word_lock  <= lane_word_lock_int;
lane_frame_lock <= lane_frame_lock_int;
lane_crc32_bad  <= lane_crc32_bad_int;
lane_status     <= lane_status_int;

-- Output is enabled once all lanes are deskewed.
output_valid <= lane_data_valid(0) and
                link_aligned_int;
link_aligned <= link_aligned_int;

check_framing : process(clk_rx)
    variable synced : std_logic;
begin
    if rising_edge(clk_rx) then
        if lane_data_valid(0) = '1' then
            if and_reduce(lane_word_lock_int) = '1' and and_reduce(lane_frame_lock_int) = '1' and and_reduce(lane_crc32_bad_int) = '0' and
               (lane_sync_word_out = X"000" or lane_sync_word_out = X"fff") and
               (lane_scrm_word_out = X"000" or lane_scrm_word_out = X"fff") and
               (lane_skip_word_out = X"000" or lane_skip_word_out = X"fff") and
               (lane_diag_word_out = X"000" or lane_diag_word_out = X"fff") then
                synced := '1';
            else
                synced := '0';
            end if;
            if deskew_started_int = '0' and deskewed = '0' and link_aligned_int = '0' then    -- NT             SEARCHING
                if got_sync = X"000" then
                    if lane_sync_word_out /= X"000" then
                        link_aligned_counter <= (others => '0');
                        for i in 0 to LANES - 1 loop
                            if lane_sync_word_out(i) = '1' then
                                got_sync(i) <= '1';
                                skew(i) <= to_unsigned(0, 3);
                            end if;
                        end loop;
                    end if;
                else
                    if got_sync = X"fff" then
                        deskew_started_int <= '1';
                        delay_enabled <= '1';
                        total_skew <= std_logic_vector(link_aligned_counter(2 downto 0));
                        link_aligned_counter <= (others => '0');
                        got_sync <= (others => '0');
                    else
                        for i in 0 to LANES - 1 loop
                            if got_sync(i) = '0' then
                                if lane_sync_word_out(i) = '1' then
                                    got_sync(i) <= '1';
                                    skew(i) <= to_unsigned(0, 3);
                                end if;
                            else
                                skew(i) <= skew(i) + 1;
                            end if;
                        end loop;
                        if link_aligned_counter = 7 then
                            link_aligned_counter <= (others => '0');
                            got_sync <= (others => '0');
                        else
                            link_aligned_counter <= link_aligned_counter + 1;
                        end if;
                    end if;
                end if;
            elsif deskew_started_int = '1' and deskewed = '0' and link_aligned_int = '0' then -- T              ALIGNING
                if link_aligned_counter = 100 then
                    deskewed <= '1';
                    link_aligned_counter <= (others => '0');
                else
                    link_aligned_counter <= link_aligned_counter + 1;
                end if;
            elsif deskew_started_int = '1' and deskewed = '1' and link_aligned_int = '0' then -- T C            DESKEWING
                if synced = '0' then
                    deskew_started_int <= '0';
                    link_aligned_counter <= (others => '0');
                    delay_enabled <= '0';
                else
                    if link_aligned_counter = 4095 then
                        deskew_started_int <= '0';
                        link_aligned_int <= '1';
                        link_aligned_counter <= (others => '0');
                    else
                        link_aligned_counter <= link_aligned_counter + 1;
                    end if;
                end if;
            elsif deskew_started_int = '0' and deskewed = '1' and link_aligned_int = '1' then -- N C            ALIGNED
                if synced = '0' then
                    link_aligned_int <= '0';
                    link_aligned_counter <= (others => '0');
                    delay_enabled <= '0';
                end if;
            else -- deskew_started_int = '0' and deskewed = '1' and link_aligned_int = '0'    -- T              UNDESKEWING
                if link_aligned_counter = 100 then
                    deskewed <= '0';
                    link_aligned_counter <= (others => '0');
                else
                    link_aligned_counter <= link_aligned_counter + 1;
                end if;
            end if;
        end if;
    end if;
end process;

rx_lanes :
for i in 0 to LANES - 1 generate
    rx_lane_X : il_rx_lane_gearbox
    generic map(
        METAFRAME => METAFRAME
    )
    port map (
        clk_rx       => clk_rx,
        reset        => reset,

        output       => lane_data(64*i + 63 downto 64*i),
        output_valid => lane_data_valid(i),
        ctrl_word    => lane_ctrl_word_int(i),
        data_word    => lane_data_word(i),
        sync_word    => lane_sync_word(i),
        scrm_word    => lane_scrm_word(i),
        skip_word    => lane_skip_word(i),
        diag_word    => lane_diag_word(i),
        word_lock    => lane_word_lock_int(i),
        frame_lock   => lane_frame_lock_int(i),
        crc32_bad    => lane_crc32_bad_int(i),
        lane_status  => lane_status_int(2*i + 1 downto 2*i),

        xcvr_rxdata         => xcvr_rxdata(64*i + 63 downto 64*i),
        xcvr_rxgearboxslip  => xcvr_rxgearboxslip_int(i),
        xcvr_rxdatavalid    => xcvr_rxdatavalid(2*i),
        xcvr_rxheader       => xcvr_rxheader(6*i + 2 downto 6 * i),
        xcvr_rxheadervalid  => xcvr_rxheadervalid(2*i)
    );
end generate;

synchronizers :
for i in 0 to LANES - 1 generate
    rx_lane_sync_X : il_rx_lane_sync
    port map (
        clk => clk_rx,
        input_valid        => lane_data_valid(i),
        input(69)          => lane_ctrl_word_int(i),
        input(68)          => lane_data_word(i),
        input(67)          => lane_sync_word(i),
        input(66)          => lane_scrm_word(i),
        input(65)          => lane_skip_word(i),
        input(64)          => lane_diag_word(i),
        input(63 downto 0) => lane_data(64*i + 63 downto 64*i),
        output_valid        => lane_data_valid(0),
        output(69)          => lane_ctrl_word_out(i),
        output(68)          => lane_data_word_out(i),
        output(67)          => lane_sync_word_out(i),
        output(66)          => lane_scrm_word_out(i),
        output(65)          => lane_skip_word_out(i),
        output(64)          => lane_diag_word_out(i),
        output(63 downto 0) => output_int(64*i + 63 downto 64*i),
        delay => std_logic_vector(skew(i)(2 downto 0)),
        delay_enabled       => delay_enabled
    );
end generate;

output <= output_int;
xcvr_rxgearboxslip <= xcvr_rxgearboxslip_int;

end behavioural;
