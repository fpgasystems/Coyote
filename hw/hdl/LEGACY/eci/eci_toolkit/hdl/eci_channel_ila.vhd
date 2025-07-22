----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- ECI channel ILAs, up to 6 channels

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_channel_ila is
generic (
    NO_CHANNELS     : integer := 1
);
port (
    clk             : in std_logic;
    channels        : in ARRAY_ECI_CHANNELS(NO_CHANNELS downto 1);
    channels_ready  : in std_logic_vector(NO_CHANNELS downto 1)
);
end eci_channel_ila;

architecture Behavioral of eci_channel_ila is

component ila_eci_channels_1 IS
PORT (
    clk : IN STD_LOGIC;
    probe0  : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe1  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe2  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe3  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe4  : IN STD_LOGIC_VECTOR(0 DOWNTO 0)
);
end component;

component ila_eci_channels_2 IS
PORT (
    clk : IN STD_LOGIC;
    probe0  : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe1  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe2  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe3  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe4  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe5  : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe6  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe7  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe8  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe9  : IN STD_LOGIC_VECTOR(0 DOWNTO 0)
);
end component;

component ila_eci_channels_3 IS
PORT (
    clk : IN STD_LOGIC;
    probe0  : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe1  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe2  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe3  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe4  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe5  : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe6  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe7  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe8  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe9  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe10 : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe11 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe12 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe13 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe14 : IN STD_LOGIC_VECTOR(0 DOWNTO 0)
);
end component;

component ila_eci_channels_4 IS
PORT (
    clk : IN STD_LOGIC;
    probe0  : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe1  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe2  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe3  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe4  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe5  : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe6  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe7  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe8  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe9  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe10 : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe11 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe12 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe13 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe14 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe15 : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe16 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe17 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe18 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe19 : IN STD_LOGIC_VECTOR(0 DOWNTO 0)
);
end component;

component ila_eci_channels_5 IS
PORT (
    clk : IN STD_LOGIC;
    probe0  : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe1  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe2  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe3  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe4  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe5  : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe6  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe7  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe8  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe9  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe10 : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe11 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe12 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe13 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe14 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe15 : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe16 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe17 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe18 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe19 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe20 : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe21 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe22 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe23 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe24 : IN STD_LOGIC_VECTOR(0 DOWNTO 0)
);
end component;

component ila_eci_channels_6 IS
PORT (
    clk : IN STD_LOGIC;
    probe0  : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe1  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe2  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe3  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe4  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe5  : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe6  : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe7  : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe8  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe9  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe10 : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe11 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe12 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe13 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe14 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe15 : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe16 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe17 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe18 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe19 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe20 : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe21 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe22 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe23 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe24 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe25 : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    probe26 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    probe27 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    probe28 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    probe29 : IN STD_LOGIC_VECTOR(0 DOWNTO 0)
);
end component;

begin

gen_channels_1 : if NO_CHANNELS = 1 generate
i_ila: ila_eci_channels_1
port map (
    clk         => clk,
    probe0      => channels(1).data(0),
    probe1      => channels(1).size,
    probe2      => channels(1).vc_no,
    probe3(0)   => channels(1).valid,
    probe4(0)   => channels_ready(1)
);
end generate gen_channels_1;

gen_channels_2 : if NO_CHANNELS = 2 generate
i_ila: ila_eci_channels_2
port map (
    clk         => clk,
    probe0      => channels(1).data(0),
    probe1      => channels(1).size,
    probe2      => channels(1).vc_no,
    probe3(0)   => channels(1).valid,
    probe4(0)   => channels_ready(1),
    probe5      => channels(2).data(0),
    probe6      => channels(2).size,
    probe7      => channels(2).vc_no,
    probe8(0)   => channels(2).valid,
    probe9(0)   => channels_ready(2)
);
end generate gen_channels_2;

gen_channels_3 : if NO_CHANNELS = 3 generate
i_ila: ila_eci_channels_3
port map (
    clk         => clk,
    probe0      => channels(1).data(0),
    probe1      => channels(1).size,
    probe2      => channels(1).vc_no,
    probe3(0)   => channels(1).valid,
    probe4(0)   => channels_ready(1),
    probe5      => channels(2).data(0),
    probe6      => channels(2).size,
    probe7      => channels(2).vc_no,
    probe8(0)   => channels(2).valid,
    probe9(0)   => channels_ready(2),
    probe10     => channels(3).data(0),
    probe11     => channels(3).size,
    probe12     => channels(3).vc_no,
    probe13(0)  => channels(3).valid,
    probe14(0)  => channels_ready(3)
);
end generate gen_channels_3;

gen_channels_4 : if NO_CHANNELS = 4 generate
i_ila: ila_eci_channels_4
port map (
    clk         => clk,
    probe0      => channels(1).data(0),
    probe1      => channels(1).size,
    probe2      => channels(1).vc_no,
    probe3(0)   => channels(1).valid,
    probe4(0)   => channels_ready(1),
    probe5      => channels(2).data(0),
    probe6      => channels(2).size,
    probe7      => channels(2).vc_no,
    probe8(0)   => channels(2).valid,
    probe9(0)   => channels_ready(2),
    probe10     => channels(3).data(0),
    probe11     => channels(3).size,
    probe12     => channels(3).vc_no,
    probe13(0)  => channels(3).valid,
    probe14(0)  => channels_ready(3),
    probe15     => channels(4).data(0),
    probe16     => channels(4).size,
    probe17     => channels(4).vc_no,
    probe18(0)  => channels(4).valid,
    probe19(0)  => channels_ready(4)
);
end generate gen_channels_4;

gen_channels_5 : if NO_CHANNELS = 5 generate
i_ila: ila_eci_channels_5
port map (
    clk         => clk,
    probe0      => channels(1).data(0),
    probe1      => channels(1).size,
    probe2      => channels(1).vc_no,
    probe3(0)   => channels(1).valid,
    probe4(0)   => channels_ready(1),
    probe5      => channels(2).data(0),
    probe6      => channels(2).size,
    probe7      => channels(2).vc_no,
    probe8(0)   => channels(2).valid,
    probe9(0)   => channels_ready(2),
    probe10     => channels(3).data(0),
    probe11     => channels(3).size,
    probe12     => channels(3).vc_no,
    probe13(0)  => channels(3).valid,
    probe14(0)  => channels_ready(3),
    probe15     => channels(4).data(0),
    probe16     => channels(4).size,
    probe17     => channels(4).vc_no,
    probe18(0)  => channels(4).valid,
    probe19(0)  => channels_ready(4),
    probe20     => channels(5).data(0),
    probe21     => channels(5).size,
    probe22     => channels(5).vc_no,
    probe23(0)  => channels(5).valid,
    probe24(0)  => channels_ready(5)
);
end generate gen_channels_5;

gen_channels_6 : if NO_CHANNELS = 6 generate
i_ila: ila_eci_channels_6
port map (
    clk         => clk,
    probe0      => channels(1).data(0),
    probe1      => channels(1).size,
    probe2      => channels(1).vc_no,
    probe3(0)   => channels(1).valid,
    probe4(0)   => channels_ready(1),
    probe5      => channels(2).data(0),
    probe6      => channels(2).size,
    probe7      => channels(2).vc_no,
    probe8(0)   => channels(2).valid,
    probe9(0)   => channels_ready(2),
    probe10     => channels(3).data(0),
    probe11     => channels(3).size,
    probe12     => channels(3).vc_no,
    probe13(0)  => channels(3).valid,
    probe14(0)  => channels_ready(3),
    probe15     => channels(4).data(0),
    probe16     => channels(4).size,
    probe17     => channels(4).vc_no,
    probe18(0)  => channels(4).valid,
    probe19(0)  => channels_ready(4),
    probe20     => channels(5).data(0),
    probe21     => channels(5).size,
    probe22     => channels(5).vc_no,
    probe23(0)  => channels(5).valid,
    probe24(0)  => channels_ready(5),
    probe25     => channels(6).data(0),
    probe26     => channels(6).size,
    probe27     => channels(6).vc_no,
    probe28(0)  => channels(6).valid,
    probe29(0)  => channels_ready(6)
);
end generate gen_channels_6;

end Behavioral;
