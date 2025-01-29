-------------------------------------------------------------------------------
-- eci_channel_buffer - Behavioral
-------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- ECI Channel buffer/register
-- FULL - decouple valid/ready signals if true, otherwise couple valid signals (no latency)
-- COALESCE - in case of two-beat messages (13 or 17 words), don't send the 1st part of a message until the 2nd part arrives

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_channel_buffer is
generic (
    FULL        : boolean := true;
    COALESCE    : boolean := false -- coalesce two beats of a packet
);
port (
    clk             : in STD_LOGIC;
    input           : in ECI_CHANNEL;
    input_ready     : out STD_LOGIC;
    output          : out ECI_CHANNEL;
    output_ready    : in STD_LOGIC
);
end eci_channel_buffer;

architecture Behavioral of eci_channel_buffer is

component bus_buffer is
generic (
    WIDTH   : integer;
    FULL    : boolean
);
port
(
    clk         : in std_logic;
    s_data      : in std_logic_vector(582 downto 0);
    s_valid     : in std_logic;
    s_ready     : out std_logic;
    s_hold      : in std_logic;
    m_data      : out std_logic_vector(582 downto 0);
    m_valid     : out std_logic;
    m_ready     : in std_logic
);
end component;

signal hold : std_logic;

begin

hold <= '1' when COALESCE = true and input.size = ECI_CHANNEL_SIZE_9_1 else '0';

i_buffer : bus_buffer
generic map
(
    WIDTH => 583,
    FULL => FULL
)
port map
(
    clk                     => clk,
    s_data(63 downto 0)     => input.data(0),
    s_data(127 downto 64)   => input.data(1),
    s_data(191 downto 128)  => input.data(2),
    s_data(255 downto 192)  => input.data(3),
    s_data(319 downto 256)  => input.data(4),
    s_data(383 downto 320)  => input.data(5),
    s_data(447 downto 384)  => input.data(6),
    s_data(511 downto 448)  => input.data(7),
    s_data(575 downto 512)  => input.data(8),
    s_data(578 downto 576)  => input.size,
    s_data(582 downto 579)  => input.vc_no,
    s_valid                 => input.valid,
    s_ready                 => input_ready,
    s_hold                  => hold,
    m_data(63 downto 0)     => output.data(0),
    m_data(127 downto 64)   => output.data(1),
    m_data(191 downto 128)  => output.data(2),
    m_data(255 downto 192)  => output.data(3),
    m_data(319 downto 256)  => output.data(4),
    m_data(383 downto 320)  => output.data(5),
    m_data(447 downto 384)  => output.data(6),
    m_data(511 downto 448)  => output.data(7),
    m_data(575 downto 512)  => output.data(8),
    m_data(578 downto 576)  => output.size,
    m_data(582 downto 579)  => output.vc_no,
    m_valid                 => output.valid,
    m_ready                 => output_ready
);

end Behavioral;
