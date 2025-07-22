-------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Bus buffer/register, 1 cycle latency
-- FULL - decouple valid/ready signals if true, otherwise couple slave to master signals to decrease latency

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

entity bus_buffer is
generic (
    WIDTH   : integer := 32;
    FULL    : boolean := true -- true - registered both ways (1 cycle latency), false - registered only one way (no latency)
);
port (
    clk         : in std_logic;

    s_data      : in std_logic_vector (WIDTH-1 downto 0);
    s_valid     : in std_logic;
    s_ready     : out std_logic;
    s_hold      : in std_logic := '0'; -- if true, hold the first buffer and wait for the second buffer to be filled, used to coalesce two parts of a packet

    m_data      : out std_logic_vector (WIDTH-1 downto 0);
    m_valid     : out std_logic;
    m_ready     : in std_logic
);
end bus_buffer;

architecture Behavioral of bus_buffer is

signal s_ready_b    : std_logic := '0';
signal m_valid_b    : std_logic := '0';
signal m_hold_b     : std_logic := '0';
signal data_buf1    : std_logic_vector(WIDTH-1 downto 0);
signal data_buf1_u  : std_logic := '0';
signal data_buf2    : std_logic_vector(WIDTH-1 downto 0);
signal data_buf2_u  : std_logic := '0';
signal first_buf    : boolean := false;
signal read     : std_logic := '0';
signal written  : std_logic := '0';

begin

s_ready <= s_ready_b;
m_valid <= m_valid_b;

gen_full: if FULL generate
begin
    m_data <= data_buf2 when first_buf else data_buf1;
    m_valid_b <= ((data_buf1_u or data_buf2_u) and not m_hold_b) or (data_buf1_u and data_buf2_u);
    s_ready_b <= data_buf1_u nand data_buf2_u;

    i_process : process(clk)
    begin
        if rising_edge(clk) then
            if s_valid = '1' and s_ready_b = '1' and (m_valid_b /= '1' or m_ready /= '1') then -- only incoming
               if data_buf1_u = '0' then
                    data_buf1 <= s_data;
                    data_buf1_u <= '1';
                    if data_buf2_u = '0' then
                        first_buf <= false;
                    end if;
                else
                    data_buf2 <= s_data;
                    data_buf2_u <= '1';
                end if;
                if m_hold_b = '1' then
                    m_hold_b <= '0';
                else
                    m_hold_b <= s_hold;
                end if;
            elsif (s_valid /= '1' or s_ready_b /= '1') and m_valid_b = '1' and m_ready = '1' then -- only outgoing
                if first_buf then
                    data_buf2_u <= '0';
                    if data_buf1_u = '1' then
                        first_buf <= false;
                    end if;
                else
                    data_buf1_u <= '0';
                    if data_buf2_u = '1' then
                        first_buf <= true;
                    end if;
                end if;
            elsif s_valid = '1' and s_ready_b = '1' and m_valid_b = '1' and m_ready = '1' then -- incoming and outgoing
               if data_buf1_u = '0' then
                    data_buf1 <= s_data;
                    data_buf1_u <= '1';
                    data_buf2_u <= '0';
                    first_buf <= false;
                else
                    data_buf2 <= s_data;
                    data_buf2_u <= '1';
                    data_buf1_u <= '0';
                    first_buf <= true;
                end if;
                if m_hold_b = '1' then
                    m_hold_b <= '0';
                else
                    m_hold_b <= s_hold;
                end if;
            end if;
        end if;
    end process;
end generate;

gen_half: if not FULL generate
begin
    m_data <= data_buf1 when (read xor written) = '1' else s_data;
    m_valid_b <= s_valid or (read xor written);
    s_ready_b <= read xnor written;

    i_process : process(clk)
    begin
        if rising_edge(clk) then
            if s_valid = '1' and s_ready_b = '1' then
                written <= not written;
                data_buf1 <= s_data;
            end if;
            if m_valid_b = '1' and m_ready = '1' then
                read <= not read;
            end if;
        end if;
    end process;
end generate;

end Behavioral;
