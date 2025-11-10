----------------------------------------------------------------------------------
-- Module Name: eci_rx_io_vc_demux - Behavioral
----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Filter ECI words based on the VC number, pass only VCs 0, 1 and 13

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_rx_io_vc_filter is
port (
    clk : in std_logic;

    in_data         : in WORDS(6 downto 0);
    in_vc_no        : in VCS(6 downto 0);
    in_valid        : in std_logic;

    out_data        : out WORDS(6 downto 0);
    out_vc_no       : out VCS(6 downto 0);
    out_word_enable : out std_logic_vector(6 downto 0);
    out_valid       : out std_logic
);
end eci_rx_io_vc_filter;

architecture Behavioral of eci_rx_io_vc_filter is

type WORD_ENABLE_ARRAY is array (integer range <>) of std_logic_vector(6 downto 0);

signal word_enable : std_logic_vector(6 downto 0);

begin

eci_word_no: for j in 0 to 6 generate
    out_data(j) <= in_data(j);
    out_vc_no(j) <= in_vc_no(j);
    word_enable(j) <= '1' when unsigned(in_vc_no(j)) = 0 or unsigned(in_vc_no(j)) = 1 or unsigned(in_vc_no(j)) = 13 else '0';
end generate eci_word_no;

out_valid <= '1' when in_valid = '1' and word_enable /= "0000000" else '0';
out_word_enable <= word_enable;

end Behavioral;
