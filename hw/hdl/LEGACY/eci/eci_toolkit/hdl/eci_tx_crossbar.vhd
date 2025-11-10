----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Route incoming packets from multiple channels into 4 channels: 2 hi bandwidth channels and 2 lo bandwidth channels, round robin
-- Based on the message size, pass it to the free channel
-- Hi channels accept all messages
-- Lo channels accept only 1-word messages

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_tx_crossbar is
generic (
    CHANNELS    : integer
);
port (
    clk                 : in std_logic;

    in_channels         : in ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
    in_channels_ready   : out std_logic_vector(CHANNELS-1 downto 0);

    link1_hi            : out ECI_CHANNEL;
    link1_hi_ready      : in std_logic;
    link2_hi            : out ECI_CHANNEL;
    link2_hi_ready      : in std_logic;
    link1_lo            : out ECI_CHANNEL;
    link1_lo_ready      : in std_logic;
    link2_lo            : out ECI_CHANNEL;
    link2_lo_ready      : in std_logic
);
end eci_tx_crossbar;

architecture Behavioral of eci_tx_crossbar is

component eci_channel_buffer is
port (
    clk             : in std_logic;
    input           : in ECI_CHANNEL;
    input_ready     : out std_logic;
    output          : out ECI_CHANNEL;
    output_ready    : in std_logic
);
end component;

signal in_channels_b        : ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
signal in_channels_ready_b  : std_logic_vector(CHANNELS-1 downto 0);

signal lo_valid         : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
signal lo_valid_masked  : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
signal lo_mask          : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
signal link1_lo_active  : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
signal link2_lo_active  : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
signal link1_lo_hold    : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
signal link2_lo_hold    : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');

signal hi_valid         : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
signal hi_valid_masked  : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
signal hi_mask          : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
signal link1_hi_active  : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
signal link2_hi_active  : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
signal link1_hi_hold    : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
signal link2_hi_hold    : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');

signal in_channels_pre          : ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);

signal no_hi_messages   : boolean;

function is_zero(X : std_logic_vector(CHANNELS-1 downto 0)) return boolean is
    variable i : integer;
begin
    for i in 0 to CHANNELS-1 loop
        if X(i) = '1' then
            return false;
        end if;
    end loop;
    return true;
end;

function is_zero_or_one(X : std_logic_vector(CHANNELS-1 downto 0)) return boolean is
    variable i : integer;
    variable second : boolean := false;
begin
    for i in 0 to CHANNELS-1 loop
        if X(i) = '1' then
            if second then
                return false;
            else
                second := true;
            end if;
        end if;
    end loop;
    return true;
end;

function find_first(X : std_logic_vector(CHANNELS-1 downto 0)) return std_logic_vector is
    variable r : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
    variable i : integer;
begin
    for i in 0 to CHANNELS-1 loop
        if X(i) = '1' then
            r(i) := '1';
            exit;
        end if;
    end loop;
    return r;
end;

function find_second(X : std_logic_vector(CHANNELS-1 downto 0)) return std_logic_vector is
    variable r : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
    variable i : integer;
    variable second : boolean := false;
begin
    for i in 0 to CHANNELS-1 loop
        if X(i) = '1' then
            if second then
                r(i) := '1';
                exit;
            else
                second := true;
            end if;
        end if;
    end loop;
    return r;
end;

function select_channel(X : ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0); selected : std_logic_vector) return ECI_CHANNEL is
    variable o : ECI_CHANNEL;
    variable i : integer;
begin
    o.data := (others => (others => '-'));
    o.size := (others => '-');
    o.vc_no := (others => '-');
    o.valid := '0';
    for i in 0 to CHANNELS-1 loop
        if selected(i) = '1' then
            o.data := X(i).data;
            if X(i).size = "001" then -- special size, ECI_CHANNEL_SIZE_1, but for the hi bandwidth path
                o.size := ECI_CHANNEL_SIZE_1;
            else
                o.size := X(i).size;
            end if;
            o.vc_no := X(i).vc_no;
            o.valid := X(i).valid;
            exit;
        end if;
    end loop;
    return o;
end;

function last_beat(X : ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0); selected : std_logic_vector) return boolean is
    variable i : integer;
begin
    for i in 0 to CHANNELS-1 loop
        if selected(i) = '1' then
            if X(i).size = ECI_CHANNEL_SIZE_9_1 then
                return false;
            end if;
            exit;
        end if;
    end loop;
    return true;
end;

function check_if_hi_messages(X : ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0)) return boolean is
    variable i : integer;
begin
    for i in 0 to CHANNELS-1 loop
        if X(i).valid = '1' and X(i).size /= ECI_CHANNEL_SIZE_1  then
            return false;
        end if;
    end loop;
    return true;
end;

function check_if_more_than_two(X : ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0); me : integer) return boolean is
    variable i, j : integer;
begin
    j := 0;
    for i in 0 to CHANNELS-1 loop
        if X(i).valid = '1' then
            j := j + 1;
            if (j = 3 or j = 4) and i = me then
                return true;
            end if;
        end if;
    end loop;
    return false;
end;

begin

no_hi_messages <= check_if_hi_messages(in_channels);

i_gen: for i in 0 to CHANNELS-1 generate
begin
-- if there are more than 2 one word messages and no longer messages, move them to the hi vc channels, so we can send up to 4 lo vc messages in one cycle
    in_channels_pre(i).data <= in_channels(i).data;
    in_channels_pre(i).size <= "001" when no_hi_messages and check_if_more_than_two(in_channels, i) else in_channels(i).size; -- special size, one word for hi vcs
    in_channels_pre(i).vc_no <= in_channels(i).vc_no;
    in_channels_pre(i).valid <= in_channels(i).valid;

    i_in_buffer : eci_channel_buffer
    port map (
        clk             => clk,
        input           => in_channels_pre(i),
        input_ready     => in_channels_ready(i),
        output          => in_channels_b(i),
        output_ready    => in_channels_ready_b(i)
    );
    lo_valid(i) <= '1' when in_channels_b(i).valid = '1' and in_channels_b(i).size = ECI_CHANNEL_SIZE_1 else '0';
    hi_valid(i) <= '1' when in_channels_b(i).valid = '1' and in_channels_b(i).size /= ECI_CHANNEL_SIZE_1 else '0';
    in_channels_ready_b(i) <= (link1_lo_ready and link1_lo_active(i)) or (link2_lo_ready and link2_lo_active(i)) or (link1_hi_ready and link1_hi_active(i)) or (link2_hi_ready and link2_hi_active(i));
end generate i_gen;

lo_valid_masked <= lo_valid and not lo_mask;
link1_lo_active <= link1_lo_hold when not is_zero(link1_lo_hold) else find_first(lo_valid_masked);
link2_lo_active <= link2_lo_hold when not is_zero(link2_lo_hold) else
                    find_first(lo_valid_masked) when not is_zero(link1_lo_hold) else
                    find_second(lo_valid_masked);
link1_lo <= select_channel(in_channels_b, link1_lo_active);
link2_lo <= select_channel(in_channels_b, link2_lo_active);

hi_valid_masked <= hi_valid and not hi_mask;
link1_hi_active <= link1_hi_hold when not is_zero(link1_hi_hold) else find_first(hi_valid_masked);
link2_hi_active <= link2_hi_hold when not is_zero(link2_hi_hold) else
                    find_first(hi_valid_masked) when not is_zero(link1_hi_hold) else
                    find_second(hi_valid_masked);
link1_hi <= select_channel(in_channels_b, link1_hi_active);
link2_hi <= select_channel(in_channels_b, link2_hi_active);

i_process : process(clk)
    variable new_lo_mask : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
    variable new_link1_lo_hold : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
    variable new_link2_lo_hold : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
    variable new_lo_hold : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
    variable new_hi_mask : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
    variable new_link1_hi_hold : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
    variable new_link2_hi_hold : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
    variable new_hi_hold : std_logic_vector(CHANNELS-1 downto 0) := (others => '0');
begin
    if rising_edge(clk) then
        new_lo_mask := lo_mask;
        new_link1_lo_hold := link1_lo_hold;
        new_link2_lo_hold := link2_lo_hold;
        if not is_zero(link1_lo_active) then
            if link1_lo_ready = '1' then
                new_link1_lo_hold := (others => '0');
            else
                new_link1_lo_hold := link1_lo_active;
            end if;
            new_lo_mask := new_lo_mask or link1_lo_active;
        end if;
        if not is_zero(link2_lo_active) then
            if link2_lo_ready = '1' then
                new_link2_lo_hold := (others => '0');
            else
                new_link2_lo_hold := link2_lo_active;
            end if;
            new_lo_mask := new_lo_mask or link2_lo_active;
        end if;
        new_lo_hold := new_link1_lo_hold or new_link2_lo_hold;
        if not is_zero_or_one((lo_valid and not new_lo_mask) or new_lo_hold) then
            lo_mask <= new_lo_mask;
        else
            lo_mask <= (new_lo_mask and new_lo_hold);
        end if;
        link1_lo_hold <= new_link1_lo_hold;
        link2_lo_hold <= new_link2_lo_hold;

        new_hi_mask := hi_mask;
        new_link1_hi_hold := link1_hi_hold;
        new_link2_hi_hold := link2_hi_hold;
        if not is_zero(link1_hi_active) then
            if link1_hi_ready = '1' and last_beat(in_channels_b, link1_hi_active) then
                new_link1_hi_hold := (others => '0');
            else
                new_link1_hi_hold := link1_hi_active;
            end if;
            new_hi_mask := new_hi_mask or link1_hi_active;
        end if;
        if not is_zero(link2_hi_active) then
            if link2_hi_ready = '1' and last_beat(in_channels_b, link2_hi_active) then
                new_link2_hi_hold := (others => '0');
            else
                new_link2_hi_hold := link2_hi_active;
            end if;
            new_hi_mask := new_hi_mask or link2_hi_active;
        end if;
        new_hi_hold := new_link1_hi_hold or new_link2_hi_hold;
        if not is_zero_or_one((hi_valid and not new_hi_mask) or new_hi_hold) then
            hi_mask <= new_hi_mask;
        else
            hi_mask <= (new_hi_mask and new_hi_hold);
        end if;
        link1_hi_hold <= new_link1_hi_hold;
        link2_hi_hold <= new_link2_hi_hold;
    end if;
end process;

end Behavioral;
