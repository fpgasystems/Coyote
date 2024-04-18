----------------------------------------------------------------------------------
-- Module Name: eci_rx_hi_vc_extractor - Behavioral
----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Find ECI packets in a stream of ECI words
-- Take up to 7 words, filter them based on their VC, align
-- Reduce the number of words from 7 to 6 per cycle, use the empty cycle (every 4th cycle) to send extra words
-- Put 6-word frames into the FIFO
-- Frames read from the FIFO, split into 3-word halves and pass them to the packetizer
-- Througput is about 7.4GiB/s, but since you need 2 links x 2 VCs to saturate the ECI link,
-- that gives 29.6 GiB/s of total bandwidith which is enough

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_rx_hi_vc_extractor is
generic (
    VC_NO           : integer := 2;
    LOW_LATENCY     : boolean := false  -- favour latency over resource usage and routability
);
port (
    clk : in std_logic;

    input_data          : in WORDS(6 downto 0);
    input_word_enable   : in std_logic_vector(6 downto 0);
    input_valid         : in std_logic;

    output              : buffer ECI_CHANNEL;
    output_ready        : in std_logic
);
end eci_rx_hi_vc_extractor;

architecture Behavioral of eci_rx_hi_vc_extractor is

component bus_fifo is
generic (
    FIFO_WIDTH : integer := 32;
    FIFO_DEPTH_BITS : integer := 8
);
Port (
    clk         : in STD_LOGIC;

    s_data      : in STD_LOGIC_VECTOR (FIFO_WIDTH-1 downto 0);
    s_valid     : in STD_LOGIC;
    s_ready     : out STD_LOGIC;

    m_data      : out STD_LOGIC_VECTOR (FIFO_WIDTH-1 downto 0);
    m_valid     : out STD_LOGIC;
    m_ready     : in STD_LOGIC
);
end component;

component eci_rx_hi_vc_packetizer is
generic (
    VC_NO           : integer
);
port (
    clk             : in std_logic;

    input_data      : in WORDS(2 downto 0);
    input_size      : in std_logic_vector(1 downto 0);
    input_length    : in std_logic_vector(5 downto 0);
    input_valid     : in std_logic;
    input_ready     : out std_logic;

    output          : buffer ECI_CHANNEL;
    output_ready    : in std_logic
);
end component;


function count_words(word_enable : std_logic_vector(6 downto 0); valid : std_logic) return integer is
    variable i, j : integer;
begin
    j := 0;
    for i in 0 to 6 loop
        if word_enable(i) = '1' and valid = '1' then
            j := j + 1;
        end if;
    end loop;
    return j;
end function;

function find_first_one(word_enable : std_logic_vector(6 downto 0); start : integer) return integer is
    variable i, j : integer;
begin
    j := 0;
    for i in 0 to 6 loop
        if word_enable(i) = '1' then
            if start = j then
                return i;
            else
                j := j + 1;
            end if;
        end if;
    end loop;
    return 6;
end function;

function get_dmask_count(dmask : std_logic_vector(3 downto 0)) return std_logic_vector is
    variable i, j : integer;
begin
    j := 0;
    for i in 0 to 3 loop
        if dmask(i) = '1' then
            j := j + 1;
        end if;
    end loop;
    return std_logic_vector(to_unsigned(j-1, 2));
end function;

-- prealigned
signal p_input_aligned      : WORDS(6 downto 0);
signal counted_words        : integer range 0 to 7;

signal input_aligned        : WORDS(5 downto 0);
signal input_length         : std_logic_vector(11 downto 0);
signal input_aligned_size   : std_logic_vector(2 downto 0);
signal input_aligned_valid  : std_logic;

signal buf                  : WORDS(2 downto 0);
signal buf_pos              : integer range 0 to 3 := 0 ;

signal b_input_aligned          : WORDS(5 downto 0);
signal b_input_length           : std_logic_vector(11 downto 0);
signal b_input_aligned_size     : std_logic_vector(2 downto 0);
signal b_input_aligned_valid    : std_logic;
signal b_input_aligned_ready    : std_logic;
signal fifo_empty               : std_logic;

signal b2_input_aligned         : WORDS(2 downto 0);
signal b2_input_length          : std_logic_vector(5 downto 0);
signal b2_input_aligned_size    : std_logic_vector(2 downto 0);
signal b2_input_aligned_valid   : std_logic;
signal b2_input_aligned_ready   : std_logic;

signal phase                : std_logic := '0';

begin

input_aligned(0) <= buf(0) when buf_pos > 0 else p_input_aligned(0);
input_aligned(1) <= buf(1) when buf_pos > 1 else p_input_aligned(1 - buf_pos);
input_aligned(2) <= buf(2) when buf_pos > 2 else p_input_aligned(2 - buf_pos);
input_aligned(3) <= p_input_aligned(3 - buf_pos);
input_aligned(4) <= p_input_aligned(4 - buf_pos);
input_aligned(5) <= p_input_aligned(5 - buf_pos);
input_aligned_size <= std_logic_vector(to_unsigned(6, 3)) when counted_words + buf_pos > 6 else std_logic_vector(to_unsigned(counted_words + buf_pos, 3));
input_aligned_valid <= '0' when input_aligned_size = "000" else '1'; 
input_length(1 downto 0) <= get_dmask_count(input_aligned(0)(49 downto 46));
input_length(3 downto 2) <= get_dmask_count(input_aligned(1)(49 downto 46));
input_length(5 downto 4) <= get_dmask_count(input_aligned(2)(49 downto 46));
input_length(7 downto 6) <= get_dmask_count(input_aligned(3)(49 downto 46));
input_length(9 downto 8) <= get_dmask_count(input_aligned(4)(49 downto 46));
input_length(11 downto 10) <= get_dmask_count(input_aligned(5)(49 downto 46));

i_not_low_latency: if not LOW_LATENCY generate
begin
    i_link_eci_rx_hi_fifo : xpm_fifo_sync
    generic map (
        READ_DATA_WIDTH     => 399,
        WRITE_DATA_WIDTH    => 399,
        FIFO_READ_LATENCY   => 1,
        FIFO_WRITE_DEPTH    => 256,
        READ_MODE           => "fwft",
        USE_ADV_FEATURES    => "0000"
    )
    port map (
        wr_clk  => clk,
        din(63 downto 0)        => input_aligned(0),
        din(127 downto 64)      => input_aligned(1),
        din(191 downto 128)     => input_aligned(2),
        din(255 downto 192)     => input_aligned(3),
        din(319 downto 256)     => input_aligned(4),
        din(383 downto 320)     => input_aligned(5),
        din(386 downto 384)     => input_aligned_size,
        din(398 downto 387)     => input_length,
        wr_en                   => input_aligned_valid,
        empty                   => fifo_empty,
        rd_en                   => b_input_aligned_ready,
        dout(63 downto 0)       => b_input_aligned(0),
        dout(127 downto 64)     => b_input_aligned(1),
        dout(191 downto 128)    => b_input_aligned(2),
        dout(255 downto 192)    => b_input_aligned(3),
        dout(319 downto 256)    => b_input_aligned(4),
        dout(383 downto 320)    => b_input_aligned(5),
        dout(386 downto 384)    => b_input_aligned_size,
        dout(398 downto 387)    => b_input_length,
        rst => '0',
        sleep => '0',
        injectdbiterr => '0',
        injectsbiterr => '0'
    );
    b_input_aligned_valid <= not fifo_empty;
end generate;

i_low_latency: if LOW_LATENCY generate
begin
    i_link_eci_rx_hi_fifo : bus_fifo
    generic map (
        FIFO_WIDTH => 399,
        FIFO_DEPTH_BITS => 9
    )
    port map (
        clk     => clk,

        s_data(63 downto 0)     => input_aligned(0),
        s_data(127 downto 64)   => input_aligned(1),
        s_data(191 downto 128)  => input_aligned(2),
        s_data(255 downto 192)  => input_aligned(3),
        s_data(319 downto 256)  => input_aligned(4),
        s_data(383 downto 320)  => input_aligned(5),
        s_data(386 downto 384)  => input_aligned_size,
        s_data(398 downto 387)  => input_length,
        s_valid                 => input_aligned_valid,
        s_ready                 => open,

        m_data(63 downto 0)     => b_input_aligned(0),
        m_data(127 downto 64)   => b_input_aligned(1),
        m_data(191 downto 128)  => b_input_aligned(2),
        m_data(255 downto 192)  => b_input_aligned(3),
        m_data(319 downto 256)  => b_input_aligned(4),
        m_data(383 downto 320)  => b_input_aligned(5),
        m_data(386 downto 384)  => b_input_aligned_size,
        m_data(398 downto 387)  => b_input_length,
        m_valid                 => b_input_aligned_valid,
        m_ready                 => b_input_aligned_ready
    );

    p_input_aligned(0)  <= input_data(find_first_one(input_word_enable, 0));
    p_input_aligned(1)  <= input_data(find_first_one(input_word_enable, 1));
    p_input_aligned(2)  <= input_data(find_first_one(input_word_enable, 2));
    p_input_aligned(3)  <= input_data(find_first_one(input_word_enable, 3));
    p_input_aligned(4)  <= input_data(find_first_one(input_word_enable, 4));
    p_input_aligned(5)  <= input_data(find_first_one(input_word_enable, 5));
    p_input_aligned(6)  <= input_data(find_first_one(input_word_enable, 6));
    counted_words       <= count_words(input_word_enable, input_valid);
end generate;

fifo_process: process(clk)
begin
    if rising_edge(clk) then
        if not LOW_LATENCY then
            p_input_aligned(0)  <= input_data(find_first_one(input_word_enable, 0));
            p_input_aligned(1)  <= input_data(find_first_one(input_word_enable, 1));
            p_input_aligned(2)  <= input_data(find_first_one(input_word_enable, 2));
            p_input_aligned(3)  <= input_data(find_first_one(input_word_enable, 3));
            p_input_aligned(4)  <= input_data(find_first_one(input_word_enable, 4));
            p_input_aligned(5)  <= input_data(find_first_one(input_word_enable, 5));
            p_input_aligned(6)  <= input_data(find_first_one(input_word_enable, 6));
            counted_words       <= count_words(input_word_enable, input_valid);
        end if;

        if counted_words = 7 and buf_pos = 0 then
            buf(0) <= p_input_aligned(6);
            buf_pos <= 1;
        elsif counted_words >= 6 and buf_pos = 1 then
            if counted_words = 6 then 
                buf(0) <= p_input_aligned(5);
                buf_pos <= 1;
            else
                buf(0) <= p_input_aligned(5);
                buf(1) <= p_input_aligned(6);
                buf_pos <= 2;
            end if;
        elsif counted_words >= 5 and buf_pos = 2 then
            if counted_words = 5 then 
                buf(0) <= p_input_aligned(4);
                buf_pos <= 1;
            elsif counted_words = 6 then
                buf(0) <= p_input_aligned(4);
                buf(1) <= p_input_aligned(5);
                buf_pos <= 2;
            else
                buf(0) <= p_input_aligned(4);
                buf(1) <= p_input_aligned(5);
                buf(2) <= p_input_aligned(6);
                buf_pos <= 3;
            end if;
        else
            buf_pos <= 0;
        end if;

        if b_input_aligned_valid = '1' and b_input_aligned_size(2) = '1' and b2_input_aligned_ready = '1' then
            if phase = '0' then
                phase <= '1';
            else
                phase <= '0';
            end if;
        end if;
    end if;
end process;

b2_input_aligned <= b_input_aligned(2 downto 0) when phase = '0' else b_input_aligned(5 downto 3);
b2_input_aligned_size <=
    b_input_aligned_size when b_input_aligned_size(2) = '0' else
    std_logic_vector(to_unsigned(3, 3)) when phase = '0' else
    std_logic_vector(unsigned(b_input_aligned_size) - to_unsigned(3, 3));

b2_input_length <= b_input_length(5 downto 0) when phase = '0' else b_input_length(11 downto 6);
b2_input_aligned_valid <= b_input_aligned_valid;
b_input_aligned_ready <= '1' when b2_input_aligned_ready = '1' and (b_input_aligned_size(2) = '0' or phase = '1') else '0';

i_packetizer : eci_rx_hi_vc_packetizer
generic map (
    VC_NO       => VC_NO
)
port map (
    clk         => clk,

    input_data      => b2_input_aligned,
    input_size      => b2_input_aligned_size(1 downto 0),
    input_length    => b2_input_length,
    input_valid     => b2_input_aligned_valid,
    input_ready     => b2_input_aligned_ready,

    output          => output,
    output_ready    => output_ready
);

end Behavioral;
