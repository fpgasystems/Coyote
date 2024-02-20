-------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
----------------------------------------------------------------------------------
-- Description: Convert a 9-word dual cycle ECI channel to a 17-word single cycle bus
-- 1:  1  2  3  4  5  6  7  8  9
-- 2:  1 10 11 12 13 14 15 16 17
-- to
-- 1: 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_channel_bus_converter is
port (
    clk             : in STD_LOGIC;

    in_channel      : in ECI_CHANNEL;
    in_ready        : out STD_LOGIC;

    out_data        : out WORDS(16 downto 0);
    out_vc_no       : out std_logic_vector(3 downto 0);
    out_size        : out std_logic_vector(4 downto 0);
    out_valid       : out std_logic;
    out_ready       : in std_logic
);
end eci_channel_bus_converter;

architecture Behavioral of eci_channel_bus_converter is

signal phase        : integer range 0 to 1 := 0;
signal buf_data     : WORDS(8 downto 1);

begin

out_data(0) <= in_channel.data(0);
out_data(8 downto 1) <= buf_data;
out_data(16 downto 9) <= in_channel.data(8 downto 1);
out_size <= "10001";
out_vc_no <= in_channel.vc_no;

in_ready <= '1' when (phase = 0 and in_channel.size = ECI_CHANNEL_SIZE_9_1) or (phase = 1 and in_channel.size = ECI_CHANNEL_SIZE_17_2 and out_ready = '1') else '0';
out_valid <= '1' when phase = 1 and in_channel.valid = '1' else '0';

i_process : process(clk)
begin
    if rising_edge(clk) then
        if in_channel.valid = '1' then
            if phase = 0 and in_channel.size = ECI_CHANNEL_SIZE_9_1 then
                buf_data(8 downto 1) <= in_channel.data(8 downto 1);
                phase <= 1;
            elsif phase = 1 and in_channel.size = ECI_CHANNEL_SIZE_17_2 and out_ready = '1' then
                phase <= 0;
            end if;
        end if;
    end if;
end process;

end Behavioral;
