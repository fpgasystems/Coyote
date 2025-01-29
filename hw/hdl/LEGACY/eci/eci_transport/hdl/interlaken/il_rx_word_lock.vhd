-------------------------------------------------------------------------------
-- ECI/Interlaken 64b/67b RX word lock logic
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

entity il_rx_word_lock is
port (
    clk_rx : in std_logic;
    reset  : in std_logic;

    input       : in std_logic_vector(66 downto 0);
    input_valid : in std_logic;

    slip : out std_logic;

    word_lock  : out std_logic;
    sync_error : out std_logic
);
end il_rx_word_lock;

architecture behavioural of il_rx_word_lock is

signal word_lock_int    : std_logic;
signal sync_good        : std_logic;
signal word_count       : integer range 0 to 63;
signal sync_error_count : integer range 0 to 15;
signal sync_counter     : integer range 0 to 63;
signal slip_delay       : integer range 0 to 10 := 0;

begin

word_lock  <= word_lock_int;
sync_error <= not sync_good;

-- There must be a transition between bits 64 and 65.
with input(65 downto 64) select sync_good <=
    '1' when B"01", '1' when B"10", '0' when others;

lock_logic : process(clk_rx)
begin
    if rising_edge(clk_rx) then
        if reset = '1' then
            word_lock_int    <= '0';
            slip             <= '0';
            word_count       <= 0;
            sync_error_count <= 0;
            sync_counter     <= 0;
            slip_delay       <= 0;
        elsif slip_delay = 0 then
            if input_valid = '1' then
                -- Not all clock edges carry valid data.
                if word_lock_int = '0' then
                    -- We don't have word lock yet (or we've lost it).
                    if sync_good = '0' then
                        -- Whenever we get a bad sync, slip one bit position.
                        sync_counter <= 0;
                        slip         <= '1';
                        slip_delay   <= 10;
                    elsif sync_counter < 63 then
                        -- Count consecutive good syncs.
                        sync_counter <= sync_counter + 1;
                        slip         <= '0';
                    else -- sync_good = '1' and sync_counter = 63
                        -- Once we get 64, declare word lock.
                        word_lock_int    <= '1';
                        word_count       <= 0;
                        sync_error_count <= 0;
                        slip             <= '0';
                    end if;
                else -- word_lock_int = '1'
                    slip <= '0';

                    if sync_good = '0' then
                        -- Allow 15 bad syncs per 64 words before losing lock.
--                        if sync_error_count < 15 then
--                            sync_error_count <= sync_error_count + 1;
--                        else
                            word_lock_int <= '0';
                            sync_counter  <= 0;
--                        end if;
                    end if;

                    if word_count < 63 then
                        word_count <= word_count + 1;
                    else
                        -- Reset bad sync count every 64 words.
                        word_count       <= 0;
                        sync_error_count <= 0;
                    end if;
                end if;
            end if;
        else
            slip_delay <= slip_delay - 1;
            slip <= '0';
        end if;
    end if;
end process;

end behavioural;
