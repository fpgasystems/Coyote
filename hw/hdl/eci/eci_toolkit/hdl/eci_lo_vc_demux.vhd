----------------------------------------------------------------------------------
-- Module Name: eci_lo_vc_demux - Behavioral
----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Split incoming word stream into two streams, based on the VC number

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_lo_vc_demux is
port (
    clk : in std_logic;

    in_data     : in WORDS(6 downto 0);
    in_vc_no    : in VCS(6 downto 0);
    in_valid    : in std_logic;
-- VCs 6, 8, 10, 12
    out_even_data    : out WORDS(6 downto 0);
    out_even_vc_no   : out VCS(6 downto 0);
    out_even_word_enable : out std_logic_vector(6 downto 0);
    out_even_valid   : out std_logic;
-- VCs 7, 9, 11
    out_odd_data    : out WORDS(6 downto 0);
    out_odd_vc_no   : out VCS(6 downto 0);
    out_odd_word_enable : out std_logic_vector(6 downto 0);
    out_odd_valid   : out std_logic
);
end eci_lo_vc_demux;

architecture Behavioral of eci_lo_vc_demux is

type WORD_ENABLE_ARRAY is array (integer range <>) of std_logic_vector(6 downto 0);

signal even_word_enable : std_logic_vector(6 downto 0);
signal odd_word_enable : std_logic_vector(6 downto 0);

begin

eci_word_no: for j in 0 to 6 generate
    out_even_data(j) <= in_data(j);
    out_even_vc_no(j) <= in_vc_no(j);
    out_odd_data(j) <= in_data(j);
    out_odd_vc_no(j) <= in_vc_no(j);
    even_word_enable(j) <= '1' when unsigned(in_vc_no(j)) = 6 or unsigned(in_vc_no(j)) = 8 or unsigned(in_vc_no(j)) = 10 or unsigned(in_vc_no(j)) = 12 else '0';
    odd_word_enable(j) <= '1' when unsigned(in_vc_no(j)) = 7 or unsigned(in_vc_no(j)) = 9 or unsigned(in_vc_no(j)) = 11 else '0';
end generate eci_word_no;

out_even_word_enable <= even_word_enable;
out_even_valid <= '1' when in_valid = '1' and even_word_enable /= "0000000" else '0';
out_odd_word_enable <= odd_word_enable;
out_odd_valid <= '1' when in_valid = '1' and odd_word_enable /= "0000000" else '0';

end Behavioral;
