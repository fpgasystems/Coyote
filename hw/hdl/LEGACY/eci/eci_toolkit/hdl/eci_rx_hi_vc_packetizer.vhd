----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Find ECI packets in a stream of ECI words
-- Take up to 3 words, look for a header, find a whole packet and send it

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_rx_hi_vc_packetizer is
generic (
    VC_NO           : integer
);
port (
    clk             : in std_logic;

    input_data      : in WORDS(2 downto 0);             -- stream of words, up to 3
    input_size      : in std_logic_vector(1 downto 0);  -- number of words
    input_length    : in std_logic_vector(5 downto 0);  -- 3x2 bits describing length of a potential message, taken from the dmask field
    input_valid     : in std_logic;
    input_ready     : out std_logic;

    output          : buffer ECI_CHANNEL;
    output_ready    : in std_logic
);
end eci_rx_hi_vc_packetizer;

architecture Behavioral of eci_rx_hi_vc_packetizer is

signal phase            : std_logic := '0';
signal buf              : WORDS(7 downto 0);
signal msg_pos          : integer range 0 to 8 := 0;

signal beat_valid       : std_logic;
signal beat_size        : integer range 5 to 9;
signal aligned_size     : integer range 0 to 3;

-- ECI message length: 0 - 5 words, 1 - 9 words, 2 - 13 words, 3 - 17 words, taken from DMASK
signal msg_length       : integer range 0 to 3;
signal msg_length_buf   : integer range 0 to 3;

begin

msg_length <= msg_length_buf when msg_pos /= 0 else to_integer(unsigned(input_length(1 downto 0)));
aligned_size <= to_integer(unsigned(input_size)) when input_valid = '1' else 0;
beat_size   <= 5 when msg_length = 0 or (msg_length = 2 and phase = '1') else 9;
beat_valid  <= '1' when aligned_size + msg_pos >= beat_size else '0';
input_ready <= '1' when beat_valid = '0' or (beat_valid = '1' and output_ready = '1') else '0';

output.data(0)  <= buf(0);
output.data(1)  <= buf(1);
output.data(2)  <= input_data(0) when msg_pos = 2 else buf(2);
output.data(3)  <= input_data(0) when msg_pos = 3 else input_data(1) when msg_pos = 2 else buf(3);
output.data(4)  <= input_data(0) when msg_pos = 4 else input_data(1) when msg_pos = 3 else input_data(2) when msg_pos = 2 else buf(4);
output.data(5)  <= buf(5);
output.data(6)  <= input_data(0) when msg_pos = 6 else buf(6);
output.data(7)  <= input_data(0) when msg_pos = 7 else input_data(1) when msg_pos = 6 else buf(7);
output.data(8)  <= input_data(0) when msg_pos = 8 else input_data(1) when msg_pos = 7 else input_data(2);

output.size <=
    ECI_CHANNEL_SIZE_5 when msg_length = 0 else
    ECI_CHANNEL_SIZE_9 when msg_length = 1 else
    ECI_CHANNEL_SIZE_9_1 when (msg_length = 2 or msg_length = 3) and phase = '0' else
    ECI_CHANNEL_SIZE_13_2 when msg_length = 2 and phase = '1' else
    ECI_CHANNEL_SIZE_17_2;
output.vc_no    <= std_logic_vector(to_unsigned(VC_NO, 4));
output.valid    <= beat_valid;

i_process : process(clk)
    variable i, o       : integer;
    variable buf_copy_start : integer range 0 to 2;
    variable buf_copy_count : integer range 0 to 3;
    variable buf_copy_where : integer range 0 to 8;
begin
    if rising_edge(clk) then
        if beat_valid = '1' and output_ready = '1' then
            if output.size = ECI_CHANNEL_SIZE_9_1 then
                phase <= '1'; -- sent 2nd beat
            else
                phase <= '0';
            end if;
        end if;

        if beat_valid = '0' or output_ready = '1' then
            if aligned_size + msg_pos < beat_size then  -- not enough data for a beat, copy all
                buf_copy_start := 0;
                buf_copy_count := aligned_size;
            else                                        -- enough data for a beat, copy the rest
                buf_copy_start := beat_size - msg_pos;
                buf_copy_count := aligned_size + msg_pos - beat_size;
            end if;

            if beat_valid = '0' then -- append
                buf_copy_where := msg_pos;
            elsif output.size = ECI_CHANNEL_SIZE_9_1 then -- 1st beat was sent, keep the header
                buf_copy_where := 1;
            else -- whole packet was sent, start from 0
                buf_copy_where := 0;
            end if;

            for i in 0 to 2 loop
                if i < buf_copy_count then
                    buf(buf_copy_where + i) <= input_data(buf_copy_start + i);
                end if; 
            end loop;

            if buf_copy_count /= 0 and buf_copy_where = 0 then
                msg_length_buf <= to_integer(unsigned(input_length(2*buf_copy_start+1 downto 2*buf_copy_start)));
            end if;

            msg_pos <= buf_copy_where + buf_copy_count;
        end if;
    end if;
end process;

end Behavioral;
