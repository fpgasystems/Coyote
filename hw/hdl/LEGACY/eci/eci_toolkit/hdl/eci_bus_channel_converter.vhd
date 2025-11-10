----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Description: Convert a 17-word single cycle bus to a 9-word dual cycle ECI channel
-- 1: 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17
-- to
-- 1:  1  2  3  4  5  6  7  8  9
-- 2:  1 10 11 12 13 14 15 16 17

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_bus_channel_converter is
port (
    clk             : in STD_LOGIC;

    in_data         : in WORDS(16 downto 0);
    in_vc_no        : in std_logic_vector(3 downto 0);
    in_size         : in std_logic_vector(4 downto 0);
    in_valid        : in std_logic;
    in_ready        : out std_logic;

    out_channel     : out ECI_CHANNEL;
    out_ready       : in STD_LOGIC
);
end eci_bus_channel_converter;

architecture Behavioral of eci_bus_channel_converter is

signal phase        : integer range 0 to 1 := 0;

begin

out_channel.data(0) <= in_data(0);
out_channel.data(8 downto 1) <= in_data(8 downto 1) when phase = 0 else in_data(16 downto 9);
out_channel.size <= ECI_CHANNEL_SIZE_9_1 when phase = 0 else ECI_CHANNEL_SIZE_17_2;
out_channel.vc_no <= in_vc_no;
in_ready <= '1' when in_valid = '1' and out_ready = '1' and phase = 1 else '0';
out_channel.valid <= '1' when in_valid = '1' else '0';

i_process : process(clk)
begin
    if rising_edge(clk) then
        if in_valid = '1' and out_ready = '1' then
            if phase = 0 then
                phase <= 1;
            else
                phase <= 0;
            end if;
        end if;
    end if;
end process;

end Behavioral;
