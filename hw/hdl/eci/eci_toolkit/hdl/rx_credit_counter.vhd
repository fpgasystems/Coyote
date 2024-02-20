----------------------------------------------------------------------------------
-- Module Name: rx_credit_counter_simple - Behavioral
----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Count receiving credits (words read by the FPGA, 1 credit - 8 words) and return them to the CPU

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity rx_credit_counter is
generic (
    VC_NO   : integer
);
port (
    clk             : in std_logic;
    reset_n         : in std_logic;
    input_valid     : in std_logic;
    input_ready     : in std_logic;
    input_size      : in std_logic_vector(2 downto 0) := ECI_CHANNEL_SIZE_1;
    input_vc_no     : in std_logic_vector(3 downto 0);
    credit_return   : out std_logic
);
end rx_credit_counter;

architecture Behavioral of rx_credit_counter is

signal credits : integer range 0 to 255 := 0;
signal popped_words : integer;
signal size : integer;

begin

size <= 1 when input_size = ECI_CHANNEL_SIZE_1 else
        5 when input_size = ECI_CHANNEL_SIZE_5 else
        9 when input_size = ECI_CHANNEL_SIZE_9 else
        9 when input_size = ECI_CHANNEL_SIZE_9_1 else
        4 when input_size = ECI_CHANNEL_SIZE_13_2 else
        8; -- ECI_CHANNEL_SIZE_17_2
popped_words <= size when input_valid = '1' and input_ready = '1' and to_integer(unsigned(input_vc_no)) = VC_NO else 0;

i_process : process (clk)
    variable i  : integer;
begin
    if rising_edge(clk) then
        if reset_n = '0' then
            credits <= 0;
        else
            if credits + popped_words >= 8 then
                credits <= credits + popped_words - 8;
                credit_return <= '1';
            else
                credits <= credits + popped_words;
                credit_return <= '0';
            end if;
        end if;
    end if;
end process;

end Behavioral;
