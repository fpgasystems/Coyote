----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Process received ECI frames
-- Extract ECI messages and route them into specific VC group channel:
--  * hi  (2, 3, 4, 5)
--  * lo_even (6, 8, 10, 12)
--  * lo_odd  (7, 9, 11)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_link_rx_lite is
generic (
    LOW_LATENCY             : boolean := false  -- favour latency over resource usage and routability
);
port (
    clk                     : in std_logic;
    link_up                 : in std_logic;
    link_in_data            : in std_logic_vector(447 downto 0);
    link_in_vc_no           : in std_logic_vector(27 downto 0);
    link_in_we2             : in std_logic_vector(6 downto 0);
    link_in_we3             : in std_logic_vector(6 downto 0);
    link_in_we4             : in std_logic_vector(6 downto 0);
    link_in_we5             : in std_logic_vector(6 downto 0);
    link_in_valid           : in std_logic;
    link_in_credit_return   : out std_logic_vector(12 downto 2);

    link_hi                 : out ECI_CHANNEL;
    link_hi_ready           : in std_logic;
    link_lo_even            : out ECI_CHANNEL;
    link_lo_even_ready      : in std_logic;
    link_lo_odd             : out ECI_CHANNEL;
    link_lo_odd_ready       : in std_logic
);
end eci_link_rx_lite;

architecture Behavioral of eci_link_rx_lite is

component eci_rx_hi_vc_extractor is
generic (
    VC_NO           : integer := 2;
    LOW_LATENCY     : boolean
);
port (
    clk : in std_logic;

    input_data          : in WORDS(6 downto 0);
    input_word_enable   : in std_logic_vector(6 downto 0);
    input_valid         : in std_logic;

    output              : buffer ECI_CHANNEL;
    output_ready        : in std_logic
);
end component;

component bus_fifo is
generic (
    FIFO_WIDTH : integer := 32;
    FIFO_DEPTH_BITS : integer := 8;
    MEMORY_TYPE : string := "block"
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

component eci_channel_buffer is
generic (
    COALESCE        : boolean := false
);
port (
    clk             : in STD_LOGIC;
    input           : in ECI_CHANNEL;
    input_ready     : out STD_LOGIC;
    output          : out ECI_CHANNEL;
    output_ready    : in STD_LOGIC
);
end component;

component eci_lo_vc_demux is
port (
    clk : in std_logic;

    in_data     : in WORDS(6 downto 0);
    in_vc_no    : in VCS(6 downto 0);
    in_valid    : in std_logic;

    out_even_data    : out WORDS(6 downto 0);
    out_even_vc_no   : out VCS(6 downto 0);
    out_even_word_enable : out std_logic_vector(6 downto 0);
    out_even_valid   : out std_logic;

    out_odd_data    : out WORDS(6 downto 0);
    out_odd_vc_no   : out VCS(6 downto 0);
    out_odd_word_enable : out std_logic_vector(6 downto 0);
    out_odd_valid   : out std_logic
);
end component;

component eci_rx_vc_word_extractor is
port (
    clk                 : in std_logic;

    input_words         : in WORDS(6 downto 0);
    input_vc_no         : in VCS(6 downto 0);
    input_word_enable   : in std_logic_vector(6 downto 0);
    input_valid         : in std_logic;
    input_ready         : buffer std_logic;

    output              : out ECI_CHANNEL;
    output_ready        : in std_logic
);
end component;

component eci_rx_vc_word_extractor_buffered is
port (
    clk                 : in std_logic;

    input_words         : in WORDS(6 downto 0);
    input_vc_no         : in VCS(6 downto 0);
    input_word_enable   : in std_logic_vector(6 downto 0);
    input_valid         : in std_logic;
    input_ready         : buffer std_logic;

    output              : out ECI_CHANNEL;
    output_ready        : in std_logic
);
end component;

component rx_credit_counter is
generic (
    VC_NO   : integer
);
port (
    clk             : in std_logic;
    reset_n         : in std_logic;
    input_valid     : in std_logic;
    input_ready     : in std_logic;
    input_size      : in std_logic_vector(2 downto 0) := "000";
    input_vc_no     : in std_logic_vector(3 downto 0);

    credit_return   : out std_logic
);
end component;

component eci_channel_muxer
generic (
    CHANNELS    : integer
);
port (
    clk             : in STD_LOGIC;

    inputs          : in ARRAY_ECI_CHANNELS(CHANNELS-1 downto 0);
    inputs_ready    : out std_logic_vector(CHANNELS-1 downto 0);
    output          : out ECI_CHANNEL;
    output_ready    : in std_logic
);
end component;

type LINK is record
    vc                          : ARRAY_ECI_CHANNELS(5 downto 2);
    vc_ready                    : std_logic_vector(5 downto 2);

    hi_vc_buf                   : ARRAY_ECI_CHANNELS(5 downto 2);
    hi_vc_buf_ready             : std_logic_vector(5 downto 2);

    lo_even_vc_data             : WORDS(6 downto 0);
    lo_even_vc_no               : VCS(6 downto 0);
    lo_even_vc_word_enable      : std_logic_vector(6 downto 0);
    lo_even_vc_valid            : std_logic;

    fifo_lo_even_vc_data        : WORDS(6 downto 0);
    fifo_lo_even_vc_no          : VCS(6 downto 0);
    fifo_lo_even_vc_word_enable : std_logic_vector(6 downto 0);
    fifo_lo_even_vc_valid       : std_logic;
    fifo_lo_even_vc_ready       : std_logic;

    lo_odd_vc_data              : WORDS(6 downto 0);
    lo_odd_vc_no                : VCS(6 downto 0);
    lo_odd_vc_word_enable       : std_logic_vector(6 downto 0);
    lo_odd_vc_valid             : std_logic;

    fifo_lo_odd_vc_data          : WORDS(6 downto 0);
    fifo_lo_odd_vc_no            : VCS(6 downto 0);
    fifo_lo_odd_vc_word_enable   : std_logic_vector(6 downto 0);
    fifo_lo_odd_vc_valid         : std_logic;
    fifo_lo_odd_vc_ready         : std_logic;
end record LINK;

signal link_in : LINK;

signal link_hi_buf      : ECI_CHANNEL;
signal link_lo_even_buf : ECI_CHANNEL;
signal link_lo_odd_buf  : ECI_CHANNEL;

signal beat_size4_i      : std_logic_vector(3 downto 0);
signal msg_pos4_i        : std_logic_vector(3 downto 0);
signal old_msg_pos4_i        : std_logic_vector(3 downto 0);
signal msg_pos4_counter   : integer := 0;

signal next_msg_pos4_i   : std_logic_vector(3 downto 0);
signal buf_copy_start4_i : std_logic_vector(2 downto 0);
signal buf_copy_count4_i : std_logic_vector(2 downto 0);
signal buf_copy_where4_i : std_logic_vector(3 downto 0);
signal phase4_i          : std_logic;
signal aligned_size4_i   : std_logic_vector(2 downto 0);
signal b_input_aligned_ready4_i : std_logic;
signal next_msg_pos_cond4_i   : std_logic_vector(1 downto 0);

signal beat_size5_i      : std_logic_vector(3 downto 0);
signal msg_pos5_i        : std_logic_vector(3 downto 0);
signal old_msg_pos5_i        : std_logic_vector(3 downto 0);
signal msg_pos5_counter   : integer := 0;
signal next_msg_pos5_i   : std_logic_vector(3 downto 0);
signal buf_copy_start5_i : std_logic_vector(2 downto 0);
signal buf_copy_count5_i : std_logic_vector(2 downto 0);
signal buf_copy_where5_i : std_logic_vector(3 downto 0);
signal phase5_i          : std_logic;
signal aligned_size5_i   : std_logic_vector(2 downto 0);
signal b_input_aligned_ready5_i : std_logic;
signal next_msg_pos_cond5_i   : std_logic_vector(1 downto 0);

type ARRAY_WORD_ENABLE is array (integer range <>) of std_logic_vector(6 downto 0);

signal vc_word_enable   : ARRAY_WORD_ENABLE(5 downto 2);

begin

link_hi <= link_hi_buf;
link_lo_even <= link_lo_even_buf;
link_lo_odd <= link_lo_odd_buf;
vc_word_enable(2) <= link_in_we2;
vc_word_enable(3) <= link_in_we3;
vc_word_enable(4) <= link_in_we4;
vc_word_enable(5) <= link_in_we5;

gen_eci_hi_vc_demux : for i in 2 to 5 generate
begin
    link_eci_hi_vc_demux : eci_rx_hi_vc_extractor
    generic map (
        VC_NO       => i,
        LOW_LATENCY => LOW_LATENCY 
    )
    port map (
        clk         => clk,

        input_data(0)       => link_in_data(63 downto 0),
        input_data(1)       => link_in_data(127 downto 64),
        input_data(2)       => link_in_data(191 downto 128),
        input_data(3)       => link_in_data(255 downto 192),
        input_data(4)       => link_in_data(319 downto 256),
        input_data(5)       => link_in_data(383 downto 320),
        input_data(6)       => link_in_data(447 downto 384),
        input_word_enable   => vc_word_enable(i),
        input_valid         => link_in_valid,

        output              => link_in.vc(i),
        output_ready        => link_in.vc_ready(i)
    );

    i_link_eci_rx_hi_buffer : eci_channel_buffer
    generic map (
        COALESCE        => true
    )
    port map (
        clk     => clk,

        input           => link_in.vc(i),
        input_ready     => link_in.vc_ready(i),
        output          => link_in.hi_vc_buf(i),
        output_ready    => link_in.hi_vc_buf_ready(i)
    );

    i_link_rx_credit : rx_credit_counter
    generic map (
        VC_NO           => i
    )
    port map (
        clk             => clk,
        reset_n         => link_up,
        input_valid     => link_in.hi_vc_buf(i).valid,
        input_ready     => link_in.hi_vc_buf_ready(i),
        input_size      => link_in.hi_vc_buf(i).size,
        input_vc_no     => link_in.hi_vc_buf(i).vc_no,
        credit_return   => link_in_credit_return(i)
    );
end generate gen_eci_hi_vc_demux;

link_eci_lo_vc_demux : eci_lo_vc_demux
port map (
    clk => clk,

    in_data(0)  => link_in_data(63 downto 0),
    in_data(1)  => link_in_data(127 downto 64),
    in_data(2)  => link_in_data(191 downto 128),
    in_data(3)  => link_in_data(255 downto 192),
    in_data(4)  => link_in_data(319 downto 256),
    in_data(5)  => link_in_data(383 downto 320),
    in_data(6)  => link_in_data(447 downto 384),
    in_vc_no(0) => link_in_vc_no(3 downto 0),
    in_vc_no(1) => link_in_vc_no(7 downto 4),
    in_vc_no(2) => link_in_vc_no(11 downto 8),
    in_vc_no(3) => link_in_vc_no(15 downto 12),
    in_vc_no(4) => link_in_vc_no(19 downto 16),
    in_vc_no(5) => link_in_vc_no(23 downto 20),
    in_vc_no(6) => link_in_vc_no(27 downto 24),
    in_valid    => link_in_valid,

    out_even_data        => link_in.lo_even_vc_data,
    out_even_vc_no       => link_in.lo_even_vc_no,
    out_even_word_enable => link_in.lo_even_vc_word_enable,
    out_even_valid       => link_in.lo_even_vc_valid,

    out_odd_data        => link_in.lo_odd_vc_data,
    out_odd_vc_no       => link_in.lo_odd_vc_no,
    out_odd_word_enable => link_in.lo_odd_vc_word_enable,
    out_odd_valid       => link_in.lo_odd_vc_valid
);

i_link_eci_rx_lo_even_fifo : bus_fifo
generic map (
    FIFO_WIDTH => 483,
    FIFO_DEPTH_BITS => 8
)
port map (
    clk     => clk,

    s_data(63 downto 0) => link_in.lo_even_vc_data(0),
    s_data(127 downto 64) => link_in.lo_even_vc_data(1),
    s_data(191 downto 128) => link_in.lo_even_vc_data(2),
    s_data(255 downto 192) => link_in.lo_even_vc_data(3),
    s_data(319 downto 256) => link_in.lo_even_vc_data(4),
    s_data(383 downto 320) => link_in.lo_even_vc_data(5),
    s_data(447 downto 384) => link_in.lo_even_vc_data(6),
    s_data(451 downto 448)  => link_in.lo_even_vc_no(0),
    s_data(455 downto 452)  => link_in.lo_even_vc_no(1),
    s_data(459 downto 456)  => link_in.lo_even_vc_no(2),
    s_data(463 downto 460)  => link_in.lo_even_vc_no(3),
    s_data(467 downto 464)  => link_in.lo_even_vc_no(4),
    s_data(471 downto 468)  => link_in.lo_even_vc_no(5),
    s_data(475 downto 472)  => link_in.lo_even_vc_no(6),
    s_data(482 downto 476)  => link_in.lo_even_vc_word_enable,
    s_valid                 => link_in.lo_even_vc_valid,

    m_data(63 downto 0) => link_in.fifo_lo_even_vc_data(0),
    m_data(127 downto 64) => link_in.fifo_lo_even_vc_data(1),
    m_data(191 downto 128) => link_in.fifo_lo_even_vc_data(2),
    m_data(255 downto 192) => link_in.fifo_lo_even_vc_data(3),
    m_data(319 downto 256) => link_in.fifo_lo_even_vc_data(4),
    m_data(383 downto 320) => link_in.fifo_lo_even_vc_data(5),
    m_data(447 downto 384) => link_in.fifo_lo_even_vc_data(6),
    m_data(451 downto 448)  => link_in.fifo_lo_even_vc_no(0),
    m_data(455 downto 452)  => link_in.fifo_lo_even_vc_no(1),
    m_data(459 downto 456)  => link_in.fifo_lo_even_vc_no(2),
    m_data(463 downto 460)  => link_in.fifo_lo_even_vc_no(3),
    m_data(467 downto 464)  => link_in.fifo_lo_even_vc_no(4),
    m_data(471 downto 468)  => link_in.fifo_lo_even_vc_no(5),
    m_data(475 downto 472)  => link_in.fifo_lo_even_vc_no(6),
    m_data(482 downto 476)  => link_in.fifo_lo_even_vc_word_enable,
    m_valid                 => link_in.fifo_lo_even_vc_valid,
    m_ready                 => link_in.fifo_lo_even_vc_ready
);

i_link_eci_rx_lo_odd_fifo : bus_fifo
generic map (
    FIFO_WIDTH => 483,
    FIFO_DEPTH_BITS => 8
)
port map (
    clk     => clk,

    s_data(63 downto 0) => link_in.lo_odd_vc_data(0),
    s_data(127 downto 64) => link_in.lo_odd_vc_data(1),
    s_data(191 downto 128) => link_in.lo_odd_vc_data(2),
    s_data(255 downto 192) => link_in.lo_odd_vc_data(3),
    s_data(319 downto 256) => link_in.lo_odd_vc_data(4),
    s_data(383 downto 320) => link_in.lo_odd_vc_data(5),
    s_data(447 downto 384) => link_in.lo_odd_vc_data(6),
    s_data(451 downto 448)  => link_in.lo_odd_vc_no(0),
    s_data(455 downto 452)  => link_in.lo_odd_vc_no(1),
    s_data(459 downto 456)  => link_in.lo_odd_vc_no(2),
    s_data(463 downto 460)  => link_in.lo_odd_vc_no(3),
    s_data(467 downto 464)  => link_in.lo_odd_vc_no(4),
    s_data(471 downto 468)  => link_in.lo_odd_vc_no(5),
    s_data(475 downto 472)  => link_in.lo_odd_vc_no(6),
    s_data(482 downto 476)  => link_in.lo_odd_vc_word_enable,
    s_valid                 => link_in.lo_odd_vc_valid,

    m_data(63 downto 0) => link_in.fifo_lo_odd_vc_data(0),
    m_data(127 downto 64) => link_in.fifo_lo_odd_vc_data(1),
    m_data(191 downto 128) => link_in.fifo_lo_odd_vc_data(2),
    m_data(255 downto 192) => link_in.fifo_lo_odd_vc_data(3),
    m_data(319 downto 256) => link_in.fifo_lo_odd_vc_data(4),
    m_data(383 downto 320) => link_in.fifo_lo_odd_vc_data(5),
    m_data(447 downto 384) => link_in.fifo_lo_odd_vc_data(6),
    m_data(451 downto 448)  => link_in.fifo_lo_odd_vc_no(0),
    m_data(455 downto 452)  => link_in.fifo_lo_odd_vc_no(1),
    m_data(459 downto 456)  => link_in.fifo_lo_odd_vc_no(2),
    m_data(463 downto 460)  => link_in.fifo_lo_odd_vc_no(3),
    m_data(467 downto 464)  => link_in.fifo_lo_odd_vc_no(4),
    m_data(471 downto 468)  => link_in.fifo_lo_odd_vc_no(5),
    m_data(475 downto 472)  => link_in.fifo_lo_odd_vc_no(6),
    m_data(482 downto 476)  => link_in.fifo_lo_odd_vc_word_enable,
    m_valid                 => link_in.fifo_lo_odd_vc_valid,
    m_ready                 => link_in.fifo_lo_odd_vc_ready
);

i_link_eci_rx_lo_even_vc_extractor : eci_rx_vc_word_extractor_buffered 
port map (
    clk                 => clk,

    input_words         => link_in.fifo_lo_even_vc_data,
    input_vc_no         => link_in.fifo_lo_even_vc_no,
    input_word_enable   => link_in.fifo_lo_even_vc_word_enable,
    input_valid         => link_in.fifo_lo_even_vc_valid,
    input_ready         => link_in.fifo_lo_even_vc_ready,

    output              => link_lo_even_buf,
    output_ready        => link_lo_even_ready
);

i_link_eci_rx_lo_odd_vc_extractor : eci_rx_vc_word_extractor_buffered
port map (
    clk                 => clk,

    input_words         => link_in.fifo_lo_odd_vc_data,
    input_vc_no         => link_in.fifo_lo_odd_vc_no,
    input_word_enable   => link_in.fifo_lo_odd_vc_word_enable,
    input_valid         => link_in.fifo_lo_odd_vc_valid,
    input_ready         => link_in.fifo_lo_odd_vc_ready,

    output              => link_lo_odd_buf,
    output_ready        => link_lo_odd_ready
);

i_link_rx_credit6 : rx_credit_counter
generic map (
    VC_NO           => 6
)
port map (
    clk             => clk,
    reset_n         => link_up,
    input_valid     => link_lo_even_buf.valid,
    input_ready     => link_lo_even_ready,
    input_vc_no     => link_lo_even_buf.vc_no,
    credit_return   => link_in_credit_return(6)
);

i_link_rx_credit7 : rx_credit_counter
generic map (
    VC_NO           => 7
)
port map (
    clk             => clk,
    reset_n         => link_up,
    input_valid     => link_lo_odd_buf.valid,
    input_ready     => link_lo_odd_ready,
    input_vc_no     => link_lo_odd_buf.vc_no,
    credit_return   => link_in_credit_return(7)
);

i_link_rx_credit8 : rx_credit_counter
generic map (
    VC_NO           => 8
)
port map (
    clk             => clk,
    reset_n         => link_up,
    input_valid     => link_lo_even_buf.valid,
    input_ready     => link_lo_even_ready,
    input_vc_no     => link_lo_even_buf.vc_no,
    credit_return   => link_in_credit_return(8)
);

i_link_rx_credit9 : rx_credit_counter
generic map (
    VC_NO           => 9
)
port map (
    clk             => clk,
    reset_n         => link_up,
    input_valid     => link_lo_odd_buf.valid,
    input_ready     => link_lo_odd_ready,
    input_vc_no     => link_lo_odd_buf.vc_no,
    credit_return   => link_in_credit_return(9)
);

i_link_rx_credit10 : rx_credit_counter
generic map (
    VC_NO           => 10
)
port map (
    clk             => clk,
    reset_n         => link_up,
    input_valid     => link_lo_even_buf.valid,
    input_ready     => link_lo_even_ready,
    input_vc_no     => link_lo_even_buf.vc_no,
    credit_return   => link_in_credit_return(10)
);

i_link_rx_credit11 : rx_credit_counter
generic map (
    VC_NO           => 11
)
port map (
    clk             => clk,
    reset_n         => link_up,
    input_valid     => link_lo_odd_buf.valid,
    input_ready     => link_lo_odd_ready,
    input_vc_no     => link_lo_odd_buf.vc_no,
    credit_return   => link_in_credit_return(11)
);

i_link_rx_credit12 : rx_credit_counter
generic map (
    VC_NO           => 12
)
port map (
    clk             => clk,
    reset_n         => link_up,
    input_valid     => link_lo_even_buf.valid,
    input_ready     => link_lo_even_ready,
    input_vc_no     => link_lo_even_buf.vc_no,
    credit_return   => link_in_credit_return(12)
);

i_link_hi_vc_muxer : eci_channel_muxer
generic map (
    CHANNELS    => 4
)
port map (
    clk             => clk,

    inputs          => link_in.hi_vc_buf,
    inputs_ready    => link_in.hi_vc_buf_ready,

    output          => link_hi_buf,
    output_ready    => link_hi_ready
);

i_process : process(clk)
begin
    if rising_edge(clk) then
        if msg_pos4_i /= old_msg_pos4_i then
            old_msg_pos4_i <= msg_pos4_i;
        end if;
        if msg_pos4_i = old_msg_pos4_i and msg_pos4_i /= "0000" and msg_pos4_counter < 100 then
            msg_pos4_counter <= msg_pos4_counter + 1;
        end if;
        if msg_pos4_counter = 100 then
            next_msg_pos_cond4_i(0) <= '1';
        end if;

        if msg_pos5_i /= old_msg_pos5_i then
            old_msg_pos5_i <= msg_pos5_i;
        end if;
        if msg_pos5_i = old_msg_pos5_i and msg_pos5_i /= "0000" and msg_pos5_counter < 100 then
            msg_pos5_counter <= msg_pos5_counter + 1;
        end if;
        if msg_pos5_counter = 100 then
            next_msg_pos_cond5_i(0) <= '1';
        end if;
    end if;
end process;

end Behavioral;
