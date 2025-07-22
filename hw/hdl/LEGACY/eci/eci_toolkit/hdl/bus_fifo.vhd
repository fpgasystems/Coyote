-------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Bus FIFO, 1 cycle latency

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity bus_fifo is
generic (
    FIFO_WIDTH      : integer := 32;
    FIFO_DEPTH_BITS : integer := 8;
    MEMORY_TYPE     : string := "auto" --"block", "distributed", "registers", "ultra", "mixed"
);
port (
    clk     : in std_logic;

    s_data  : in std_logic_vector (FIFO_WIDTH-1 downto 0);
    s_valid : in std_logic;
    s_ready : out std_logic;

    m_data  : out std_logic_vector (FIFO_WIDTH-1 downto 0);
    m_valid : out std_logic;
    m_ready : in std_logic
);
end bus_fifo;

architecture Behavioral of bus_fifo is

signal waddr : unsigned(FIFO_DEPTH_BITS-1 downto 0) := (others => '0');
signal raddr : unsigned(FIFO_DEPTH_BITS-1 downto 0) := (others => '0');

signal mdin : std_logic_vector (FIFO_WIDTH-1 downto 0);
signal mdout : std_logic_vector (FIFO_WIDTH-1 downto 0);
signal valid_b : std_logic;
signal s_ready_b : std_logic;
signal bdin : std_logic_vector (FIFO_WIDTH-1 downto 0);
signal bdin_full : std_logic := '0';
signal mdout_full : std_logic := '0';

type FIFO_ARRAY is array (integer range <>) of std_logic_vector(FIFO_WIDTH-1 downto 0);
signal mem : FIFO_ARRAY(2**FIFO_DEPTH_BITS-1 downto 0);

attribute ram_style : string;
attribute ram_style of mem : signal is MEMORY_TYPE;

begin

m_valid <= valid_b;
mdin <= s_data;
m_data <=  bdin when bdin_full = '1' else mdout;
valid_b <= '1' when bdin_full = '1' or mdout_full = '1' else '0';
s_ready_b <= '1' when waddr + 1 /= raddr else '0';
s_ready <= s_ready_b;

u_process : process(clk)
begin
    if rising_edge(clk) then
        mem(to_integer(waddr)) <= mdin;
        mdout <= mem(to_integer(raddr));

        if (s_valid = '1' and bdin_full = '0' and raddr = waddr) or
           (s_valid = '1' and m_ready = '1' and raddr = waddr) then
            bdin_full <= '1';
            bdin <= s_data;
        end if;

        if (s_valid = '0' and m_ready = '0' and  bdin_full = '0' and mdout_full = '1') or
           (s_ready_b = '1' and s_valid = '1' and m_ready = '0' and mdout_full = '1') then
            bdin_full <= '1';
            bdin <= mdout;
        end if;

        if (s_valid = '0' and m_ready = '1' and bdin_full = '1') or
           (s_valid = '1' and m_ready = '1' and bdin_full = '1' and waddr /= raddr)
           then
            bdin_full <= '0';
        end if;

        if (s_ready_b = '1' and s_valid = '1' and m_ready = '0' and bdin_full = '1') or
           (s_ready_b = '1' and s_valid = '1' and m_ready = '1' and raddr /= waddr) or
           (s_ready_b = '1' and s_valid = '1' and m_ready = '0' and mdout_full = '1') then
            waddr <= waddr + 1;
        end if;

        if (m_ready = '1' and waddr /= raddr) then
            raddr <= raddr + 1;
        end if;

        if (s_valid = '0' and m_ready = '1' and raddr /= waddr and bdin_full = '1') or
           (s_valid = '1' and m_ready = '1' and bdin_full = '1' and waddr /= raddr)
           then
            mdout_full <= '1';
        end if;

        if (m_ready = '1' and mdout_full = '1' and waddr = raddr) or
           (s_valid = '0' and m_ready = '0' and  bdin_full = '0' and mdout_full = '1') or
           (s_ready_b = '1' and s_valid = '1' and m_ready = '0' and mdout_full = '1')
            then
            mdout_full <= '0';
        end if;
    end if;
end process;

end Behavioral;
