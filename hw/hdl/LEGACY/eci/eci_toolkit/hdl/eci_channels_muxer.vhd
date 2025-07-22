----------------------------------------------------------------------------------
-- Module Name: hi_vc_muxer - Behavioral
----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Multiplex ECI channels into one
-- Round robin

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_channel_muxer is
generic (
    CHANNELS    : integer
);
port (
    clk             : in STD_LOGIC;

    inputs          : in ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
    inputs_ready    : out std_logic_vector(CHANNELS-1 downto 0);
    output          : out ECI_CHANNEL;
    output_ready    : in std_logic
);
end eci_channel_muxer;

architecture Behavioral of eci_channel_muxer is

signal s            : integer range 0 to (CHANNELS - 1) := 0;
signal ch_active    : integer range 0 to (CHANNELS - 1) := 0;
signal selected     : integer range 0 to (CHANNELS - 1);
signal hold         : integer range -1 to (CHANNELS - 1) := -1;

signal hi_size_b    : std_logic_vector(2 downto 0);
signal input_valid  : std_logic_vector(CHANNELS - 1 downto 0);

function find_one(vec : std_logic_vector; start : integer) return integer is
begin
    for i in 0 to vec'high loop
        if i >= start and vec(i) = '1' then
            return i;
        end if;
    end loop;
    if start > vec'low then
        for i in vec'low to vec'high loop
            if i < start and vec(i) = '1' then
                return i;
            end if;
        end loop;
    end if;
    return vec'high;
end function;

begin

ch_active <= find_one(input_valid, s);
selected <= hold when hold /= -1 else ch_active;

output.data <= inputs(selected).data;
output.vc_no <= inputs(selected).vc_no;
hi_size_b <= inputs(selected).size;
output.size <= hi_size_b;
output.valid <= input_valid(selected);

gen_ready : for i in 0 to CHANNELS-1 generate
    input_valid(i) <= inputs(i).valid;
    inputs_ready(i) <= output_ready when i = selected else '0';
end generate gen_ready;

i_process : process(clk)
begin
    if rising_edge(clk) then
        if input_valid(selected) = '1' then
            if output_ready = '0' or inputs(selected).size = ECI_CHANNEL_SIZE_9_1 then
                hold <= selected;
            else
                hold <= -1;
                if selected /= CHANNELS-1 then
                    s <= selected + 1;
                else
                    s <= 0;
                end if;
            end if;
        end if;
    end if;
end process;

end Behavioral;
