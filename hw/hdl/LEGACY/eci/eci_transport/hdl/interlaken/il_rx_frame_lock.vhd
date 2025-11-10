-------------------------------------------------------------------------------
-- ECI/Interlaken Metaframe Lock
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

entity il_rx_frame_lock is
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
end il_rx_frame_lock;

architecture behavioural of il_rx_frame_lock is

signal good_sync      : integer range 0 to 3 := 0;
--signal bad_sync       : integer range 0 to 3 := 0;
--signal bad_scrm       : integer range 0 to 2 := 0;
signal frame_pos      : integer range 0 to METAFRAME - 1 := 0;
signal frame_lock_int : std_logic := '0';

begin

frame_lock <= frame_lock_int;

lock : process(clk_rx) is
begin
    if rising_edge(clk_rx) then
        if reset = '1' or word_lock = '0' then
            -- Reset when we lose word lock.
            good_sync      <= 0;
--            bad_sync       <= 0;
--            bad_scrm       <= 0;
            frame_pos      <= 0;
            frame_lock_int <= '0';
        elsif word_valid = '1' then
            -- Only step on valid input words.
            if frame_lock_int = '0' then
                -- Hold the start-of-frame marker.
                frame_pos <= 0;

                if good_sync = 0 then
                    -- Search for the first frame sync word.
                    if sync_word = '1' then
                        good_sync <= 1;
                        frame_pos <= 1;
                    end if;
                else -- good_sync > 0
                    -- Search for 3 more consecutive syncs, at
                    -- METAFRAME intervals.
                    if frame_pos = 0 then
                        if sync_word = '1' then
                            if good_sync = 3 then
                                -- Declare frame lock.
                                frame_lock_int <= '1';

                                -- Reset bad word counters.
--                                bad_sync <= 0;
--                                bad_scrm <= 0;
                            else
                                good_sync <= good_sync + 1;
                            end if;

                            frame_pos <= 1;
                        else -- sync_word = '0'
                            -- Start again, leaving frame_pos at 0.
                            good_sync <= 0;
                        end if;
                    else
                        if frame_pos = METAFRAME - 1 then
                            frame_pos <= 0;
                        else
                            frame_pos <= frame_pos + 1;
                        end if;
                    end if;
                end if;
            else -- frame_lock_int = '1'
                if frame_pos = 0 then
                    -- Check for a bad sync word.
                    if sync_word = '0' then
--                        if bad_sync = 3 then
                            -- Declare frame lock lost.
                            frame_lock_int <= '0';

                            -- Reset good sync counter.
                            good_sync <= 0;
--                        else
--                            bad_sync  <= bad_sync + 1;
--                            frame_pos <= 1;
--                        end if;
                    else -- sync_word = '1'
                        -- Reset the bad sync counter.
--                        bad_sync  <= 0;
                        frame_pos <= 1;
                    end if;
                elsif frame_pos = 1 then
                    -- Check for a bad scrambler state.
                    frame_pos <= 2;
                else
                    if frame_pos = METAFRAME - 1 then
                        frame_pos <= 0;
                    else
                        frame_pos <= frame_pos + 1;
                    end if;
                end if;
            end if;
        end if;
    end if;
end process;

end behavioural;
