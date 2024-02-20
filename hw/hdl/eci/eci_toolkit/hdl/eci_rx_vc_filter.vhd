----------------------------------------------------------------------------------
-- Module Name: eci_rx_vc_filter - Behavioral
----------------------------------------------------------------------------------
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

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_rx_vc_filter is
generic (
    CHANNELS            : integer;
    VC_MASK             : VC_BITFIELDS;
    FILTER_TYPE_MASK    : ECI_TYPE_MASKS;
    FILTER_TYPE         : ECI_TYPE_MASKS;
    FILTER_CLI_MASK     : CLI_ARRAY;
    FILTER_CLI          : CLI_ARRAY
);
port (
    clk             : in std_logic;
    input           : in ECI_CHANNEL;
    input_ready     : out std_logic;
    outputs         : buffer ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
    outputs_ready   : in std_logic_vector(CHANNELS-1 downto 0)
);
end eci_rx_vc_filter;

architecture Behavioral of eci_rx_vc_filter is

signal active       : std_logic_vector(CHANNELS-1 downto 0);
signal sink         : std_logic;
signal input_type   : std_logic_vector(4 downto 0);
signal input_cli    : std_logic_vector(32 downto 0);
signal outputs_valid    : std_logic_vector(7 downto 0);

begin

sink <= '1' when active = std_logic_vector(to_unsigned(0, CHANNELS)) else '0';
input_type <= input.data(0)(63 downto 59);
input_cli <= input.data(0)(39 downto 7);

i_gen : for i in 0 to CHANNELS-1 generate
    outputs(i).data <= input.data;
    outputs(i).size <= input.size;
    outputs(i).vc_no <= input.vc_no;
    active(i) <= '1' when input.valid = '1' and VC_MASK(i)(to_integer(unsigned(input.vc_no))) = '1' and ((input_type and FILTER_TYPE_MASK(i)) = FILTER_TYPE(i)) and ((input_cli and FILTER_CLI_MASK(i)) = FILTER_CLI(i)) else '0';
    outputs(i).valid <= active(0) when i = 0 else (active(i) and not or_reduce(active(i-1 downto 0)));
    outputs_valid(i) <= outputs(i).valid;
end generate i_gen;

input_ready <= or_reduce(outputs_ready and outputs_valid) or sink; -- sink if no filter applies

end Behavioral;
