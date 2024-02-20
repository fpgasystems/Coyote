-------------------------------------------------------------------------------
-- Module Name: il_rx_lane_sync - Behavioral
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

entity il_rx_lane_sync is
Port (
    clk : in STD_LOGIC;
    input : in STD_LOGIC_VECTOR (69 downto 0);
    input_valid : in STD_LOGIC;
    delay_enabled : in STD_LOGIC;
    delay : in STD_LOGIC_VECTOR (2 downto 0);
    output : out STD_LOGIC_VECTOR (69 downto 0);
    output_valid : in STD_LOGIC
);
end il_rx_lane_sync;

architecture Behavioral of il_rx_lane_sync is

signal addra : unsigned(2 downto 0) := "001";
signal addrb : unsigned(2 downto 0) := "000";
signal dina  : std_logic_vector(69 downto 0);
signal doutb : std_logic_vector(69 downto 0);
signal ena   : std_logic;
signal enb   : std_logic;
signal wea   : std_logic_vector(0 downto 0);
signal sync_delay : integer range 0 to 2 := 0;

begin

output <= input when sync_delay = 0 and (delay_enabled = '0' or delay = "000") else doutb;

dina <= input;
ena <= input_valid;

pfifo : process(clk)
begin
    if rising_edge(clk) then
        if input_valid = '1' then
            if output_valid = '0' then
                if sync_delay = 0 then
                    if delay_enabled = '0' or unsigned(delay) = 0 then
                        addra <= addrb + 2;
                        addrb <= addrb + 1;
                    else
                        addra <= addrb + 1 + unsigned(delay);
                    end if;
                    sync_delay <= 1;
                elsif sync_delay = 1 then
                    if delay_enabled = '1' then
                        addra <= addrb + 2 + unsigned(delay);
                    else
                        addra <= addrb + 2;
                    end if;
                    sync_delay <= 2;
                end if;
            else
                if sync_delay = 0 and (delay_enabled = '0' or unsigned(delay) = 0) then
                    addra <= addrb + 2;
                else
                    if delay_enabled = '1' then
                        addra <= addrb + 1 + sync_delay + unsigned(delay);
                    else
                        addra <= addrb + 1 + sync_delay;
                    end if;
                end if;
                addrb <= addrb + 1;
            end if;
        elsif output_valid = '1' then
            if input_valid = '0' and sync_delay /= 0 then
                sync_delay <= sync_delay - 1;
                if sync_delay = 1 then
                    if delay_enabled = '0' or unsigned(delay) = 0 then
                        addra <= addrb + 2;
                    else
                        addra <= addrb + 1 + unsigned(delay);
                    end if;
                end if;
                addrb <= addrb + 1;
            end if;
        end if;
    end if;
end process;

xpm_memory_sdpram_inst : xpm_memory_sdpram
generic map (
    ADDR_WIDTH_A => 3,
    ADDR_WIDTH_B => 3,
    BYTE_WRITE_WIDTH_A => 70,
    CLOCKING_MODE => "common_clock",
    MEMORY_SIZE => 560,
    READ_DATA_WIDTH_B => 70,
    READ_LATENCY_B => 0,
    USE_MEM_INIT => 0,
    WRITE_DATA_WIDTH_A => 70
)
port map (
    doutb => doutb,
    addra => std_logic_vector(addra),
    addrb => std_logic_vector(addrb),
    clka => clk,
    clkb => clk,
    dina => dina,
    ena => ena,
    enb => '1',
    injectdbiterra => '0',
    injectsbiterra => '0',
    regceb => '0',
    rstb => '0',
    sleep => '0',
    wea(0) => '1'
);

end Behavioral;
