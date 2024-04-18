-------------------------------------------------------------------------------
-- ECI/Interlaken Framing Decoder
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

entity il_rx_framing is
port (
    clk_rx : in std_logic;
    reset  : in std_logic;

    input       : in std_logic_vector(66 downto 0);
    input_valid : in std_logic;

    -- Payload
    output       : out std_logic_vector(63 downto 0);
    output_valid : out std_logic;

    -- Is this a control word or a data word (0)
    ctrl_word : out std_logic;
    data_word : out std_logic;

    -- Syncronisation words must be recognised before descrambling.
    sync_word : out std_logic
);
end il_rx_framing;

architecture structural of il_rx_framing is

alias invert     : std_logic                     is input(66);
alias sync_bits  : std_logic_vector( 1 downto 0) is input(65 downto 64);
alias payload    : std_logic_vector(63 downto 0) is input(63 downto  0);
alias block_type : std_logic_vector( 5 downto 0) is input(63 downto 58);

begin

ctrl_word <= '1' when sync_bits = B"10" else '0';
data_word <= '1' when sync_bits = B"01" else '0';

output <= not payload when invert = '1' else payload;

output_valid <= input_valid;

sync_word <= '1' when sync_bits = B"10" and
    ((invert = '0' and payload = X"78F678F678F678F6") or
     (invert = '1' and payload = X"8709870987098709")) else '0';

end structural;
