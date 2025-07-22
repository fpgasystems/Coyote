----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Process received ECI frames
-- Extract ECI messages and route them into specific channel, each channel for each VC

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_link_rx is
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

    link                    : out ARRAY_ECI_CHANNELS(12 downto 2);
    link_ready              : in std_logic_vector(12 downto 2)
);
end eci_link_rx;

architecture Behavioral of eci_link_rx is

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
    MEMORY_TYPE : string := "auto"
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

type ARRAY_WORD_ENABLE is array (integer range <>) of std_logic_vector(6 downto 0);
type ARRAY_DATA is array (integer range <>) of std_logic_vector(447 downto 0);

type LINK_IN_REC is record
    vc                  : ARRAY_ECI_CHANNELS(5 downto 2);
    vc_ready            : std_logic_vector(5 downto 2);

    fifo_data           : ARRAY_DATA(12 downto 6);
    fifo_word_enable    : ARRAY_WORD_ENABLE(12 downto 6);
    fifo_valid          : std_logic_vector(12 downto 6);
    fifo_ready          : std_logic_vector(12 downto 6);
end record LINK_IN_REC;

signal link_in : LINK_IN_REC;

signal vc_valid         : std_logic_vector(12 downto 2);
signal vc_word_enable   : ARRAY_WORD_ENABLE(12 downto 2);
signal link_buf         : ARRAY_ECI_CHANNELS(12 downto 2);

begin

link <= link_buf;
vc_word_enable(2) <= link_in_we2;
vc_word_enable(3) <= link_in_we3;
vc_word_enable(4) <= link_in_we4;
vc_word_enable(5) <= link_in_we5;

gen_vc_valid : for i in 2 to 12 generate
begin
    vc_valid(i) <= or_reduce(vc_word_enable(i)) and link_in_valid;
end generate gen_vc_valid;

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
        output          => link_buf(i),
        output_ready    => link_ready(i)
    );

    i_link_rx_credit : rx_credit_counter
    generic map (
        VC_NO           => i
    )
    port map (
        clk             => clk,
        reset_n         => link_up,
        input_valid     => link_buf(i).valid,
        input_ready     => link_ready(i),
        input_size      => link_buf(i).size,
        input_vc_no     => link_buf(i).vc_no,
        credit_return   => link_in_credit_return(i)
    );
end generate gen_eci_hi_vc_demux;

gen_eci_lo_vc_demux : for i in 6 to 12 generate
begin
    vc_word_enable(i)(0) <= '1' when link_in_vc_no(3 downto 0) = std_logic_vector(to_unsigned(i, 4)) else '0';
    vc_word_enable(i)(1) <= '1' when link_in_vc_no(7 downto 4) = std_logic_vector(to_unsigned(i, 4)) else '0';
    vc_word_enable(i)(2) <= '1' when link_in_vc_no(11 downto 8) = std_logic_vector(to_unsigned(i, 4)) else '0';
    vc_word_enable(i)(3) <= '1' when link_in_vc_no(15 downto 12) = std_logic_vector(to_unsigned(i, 4)) else '0';
    vc_word_enable(i)(4) <= '1' when link_in_vc_no(19 downto 16) = std_logic_vector(to_unsigned(i, 4)) else '0';
    vc_word_enable(i)(5) <= '1' when link_in_vc_no(23 downto 20) = std_logic_vector(to_unsigned(i, 4)) else '0';
    vc_word_enable(i)(6) <= '1' when link_in_vc_no(27 downto 24) = std_logic_vector(to_unsigned(i, 4)) else '0';

    i_link_eci_rx_lo_fifo : bus_fifo
    generic map (
        FIFO_WIDTH => 455,
        FIFO_DEPTH_BITS => 6
    )
    port map (
        clk     => clk,

        s_data(447 downto 0)    => link_in_data,
        s_data(454 downto 448)  => vc_word_enable(i),
        s_valid                 => vc_valid(i),

        m_data(447 downto 0)    => link_in.fifo_data(i),
        m_data(454 downto 448)  => link_in.fifo_word_enable(i),
        m_valid                 => link_in.fifo_valid(i),
        m_ready                 => link_in.fifo_ready(i)
    );

    i_link_eci_rx_lo_vc_extractor : eci_rx_vc_word_extractor_buffered
    port map (
        clk                 => clk,

        input_words         => vector_to_words(link_in.fifo_data(i)),
        input_vc_no(0)      => std_logic_vector(to_unsigned(i, 4)),
        input_vc_no(1)      => std_logic_vector(to_unsigned(i, 4)),
        input_vc_no(2)      => std_logic_vector(to_unsigned(i, 4)),
        input_vc_no(3)      => std_logic_vector(to_unsigned(i, 4)),
        input_vc_no(4)      => std_logic_vector(to_unsigned(i, 4)),
        input_vc_no(5)      => std_logic_vector(to_unsigned(i, 4)),
        input_vc_no(6)      => std_logic_vector(to_unsigned(i, 4)),
        input_word_enable   => link_in.fifo_word_enable(i),
        input_valid         => link_in.fifo_valid(i),
        input_ready         => link_in.fifo_ready(i),

        output              => link_buf(i),
        output_ready        => link_ready(i)
    );
    i_link_rx_credit : rx_credit_counter
    generic map (
        VC_NO           => i
    )
    port map (
        clk             => clk,
        reset_n         => link_up,
        input_valid     => link_buf(i).valid,
        input_ready     => link_ready(i),
        input_size      => link_buf(i).size,
        input_vc_no     => link_buf(i).vc_no,
        credit_return   => link_in_credit_return(i)
    );
end generate gen_eci_lo_vc_demux;

end Behavioral;
