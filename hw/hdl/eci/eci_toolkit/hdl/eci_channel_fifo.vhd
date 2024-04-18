----------------------------------------------------------------------------------
-- Module Name: eci_channel_fifo - Behavioral
-- Description: 1-cycle latency ECI channel FIFO
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

entity eci_channel_fifo is
generic (
    FIFO_DEPTH_BITS : integer := 8
);
port (
    clk             : in STD_LOGIC;

    input           : in ECI_CHANNEL;
    input_ready     : out STD_LOGIC;

    output          : out ECI_CHANNEL;
    output_ready    : in STD_LOGIC
);
end eci_channel_fifo;

architecture Behavioral of eci_channel_fifo is

component bus_fifo is
generic (
    FIFO_WIDTH : integer := 32;
    FIFO_DEPTH_BITS : integer := 8
);
Port (
    clk : in STD_LOGIC;

    s_data      : in STD_LOGIC_VECTOR (FIFO_WIDTH-1 downto 0);
    s_valid     : in STD_LOGIC;
    s_ready     : out STD_LOGIC;

    m_data      : out STD_LOGIC_VECTOR (FIFO_WIDTH-1 downto 0);
    m_valid     : out STD_LOGIC;
    m_ready     : in STD_LOGIC
);
end component;

begin

i_link_eci_rx_hi_fifo : bus_fifo
generic map (
    FIFO_WIDTH => 583,
    FIFO_DEPTH_BITS => FIFO_DEPTH_BITS
)
port map (
    clk     => clk,

    s_data(63 downto 0) => input.data(0),
    s_data(127 downto 64) => input.data(1),
    s_data(191 downto 128) => input.data(2),
    s_data(255 downto 192) => input.data(3),
    s_data(319 downto 256) => input.data(4),
    s_data(383 downto 320) => input.data(5),
    s_data(447 downto 384) => input.data(6),
    s_data(511 downto 448) => input.data(7),
    s_data(575 downto 512) => input.data(8),
    s_data(579 downto 576)  => input.vc_no,
    s_data(582 downto 580)  => input.size,
    s_valid                 => input.valid,
    s_ready                 => input_ready,

    m_data(63 downto 0) => output.data(0),
    m_data(127 downto 64) => output.data(1),
    m_data(191 downto 128) => output.data(2),
    m_data(255 downto 192) => output.data(3),
    m_data(319 downto 256) => output.data(4),
    m_data(383 downto 320) => output.data(5),
    m_data(447 downto 384) => output.data(6),
    m_data(511 downto 448) => output.data(7),
    m_data(575 downto 512) => output.data(8),
    m_data(579 downto 576)  => output.vc_no,
    m_data(582 downto 580)  => output.size,
    m_valid                 => output.valid,
    m_ready                 => output_ready
);

end Behavioral;
