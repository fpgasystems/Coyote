----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
--
-- Packs incoming data from Hi bandwidth VCs and Lo bandwidth VCs
-- Hi bandwidth data may come in 2 cycles
-- Lo bandwidth data always comes one word per cycle
--
-- H    - hi vc current word slot
-- b    - hi vc buffered word slot 
-- L    - lo vc word slot
-- -    - unused slot
--
-- Pattern 1, 17 hi vc words is available with/without lo vc data
--              size    phase   buffer_size after
-- 1.  HHHHHHH  100     0       2
-- 2.  bbHHHHH  111     0       3
-- 3.  Lbbb---     -    0       0 -- if no more hi vc data or
-- Pattern 2, if there is more hi vc data
-- 3.  LbbbHHH  100     0       6           
-- 4.  bbbbbbH  111     0       7
-- 5.  bbbbbbb     -    0/1     0
-- Pattern 3, if there are lo vc words as well as hi vc words
-- 6.  LHHHHHH  100     1       3
-- 7.  LbbbHHH  111     1       5
-- 8.  L-bbbbb     -    0       0
-- Pattern 4, if only there is a lo vc word and/or 1 hi vc word
-- 9.  LH-----
-- Pattern 5, lo vc word and 5 hi vc words
-- 10. LHHHHH-  010     0       0
-- Pattern 6, lo vc words and 9 hi vc words
-- 11. LHHHHHH  011     0       3
-- 3.  Lbbb---     -    0       0
-- Pattern 7, 13 hi vc words
-- 1.  HHHHHHH  100     0       2
-- 12. bbHHHH-  110     0       0
-- Pattern 8, 13 hi vc words
-- 3.  LbbbHHH  100     0       6           
-- 13. bbbbbbH  110     0       3
-- 3.  Lbbb---    -     0       0
-- Pattern 9, 13 hi vc words
-- 6.  LHHHHHH  100     1       3
-- 14. bbbHHHH  110     1       0

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity tlk_packer is
port (
    clk       : in std_logic;
    hi_words  : in WORDS (8 downto 0);
    hi_vc     : in std_logic_vector(3 downto 0);
    hi_size   : in std_logic_vector(2 downto 0); -- one beat: "000" - 1 word, "010"- 5 words, "011" - 9 words, two beats: 1st beat, "100" - 9 words, 2nd beat; "110" - 4 words, 13 in total, "111" - 8 words, 17 in total
    hi_valid  : in std_logic;
    hi_ready  : buffer std_logic;
    lo_word   : in std_logic_vector(63 downto 0);
    lo_vc     : in std_logic_vector(3 downto 0);
    lo_valid  : in std_logic;
    lo_ready  : out std_logic;
    out_words : out WORDS (6 downto 0);
    out_vc    : out VCS (6 downto 0);
    out_valid : out std_logic;
    out_ready : in std_logic
);
end tlk_packer;

architecture Behavioral of tlk_packer is

signal buffer1    : WORDS(6 downto 0);
signal buffer1_vc : std_logic_vector(3 downto 0);

signal buffer_size : integer range 0 to 7 := 0;
signal phase       : integer              := 0;

signal p1_w0, p2_w0     : boolean;
signal p3_w0, p3_w4     : boolean;
signal p4_w0            : boolean;
signal p5_w0            : boolean;
signal p6_w0            : boolean;
signal p7_w0            : boolean;
signal p8_w0, p8_w2     : boolean;
signal p9_w0, p9_w1     : boolean;
signal p10_w0, p11_w0, p12_w0, p13_w0, p14_w0   : boolean;

begin

p1_w0   <= hi_valid = '1' and hi_size = "100" and phase = 0 and buffer_size = 0;
p2_w0   <= hi_valid = '1' and hi_size = "111" and phase = 0 and buffer_size = 2;
p3_w0   <= phase = 0 and buffer_size = 3;
p3_w4   <= hi_valid = '1' and hi_size = "100" and phase = 0 and buffer_size = 3;
p4_w0   <= hi_valid = '1' and hi_size = "111" and phase = 0 and buffer_size = 6;
p5_w0   <= phase = 0 and buffer_size = 7;
p6_w0   <= hi_valid = '1' and hi_size = "100" and phase = 1 and buffer_size = 0;
p7_w0   <= hi_valid = '1' and hi_size = "111" and phase = 1 and buffer_size = 3;
p8_w0   <= phase = 1 and buffer_size = 5;
p9_w0   <= hi_valid = '0' and phase = 0 and buffer_size = 0;
p9_w1   <= hi_valid = '1' and hi_size = "000" and phase = 0 and buffer_size = 0;
p10_w0  <= hi_valid = '1' and hi_size = "010" and phase = 0 and buffer_size = 0;
p11_w0  <= hi_valid = '1' and hi_size = "011" and phase = 0 and buffer_size = 0;        
p12_w0  <= hi_valid = '1' and hi_size = "110" and phase = 0 and buffer_size = 2;
p13_w0  <= hi_valid = '1' and hi_size = "110" and phase = 0 and buffer_size = 6;
p14_w0  <= hi_valid = '1' and hi_size = "110" and phase = 1 and buffer_size = 3;

out_vc(6) <=
    hi_vc when p1_w0 else
    lo_vc when lo_valid = '1' and (p3_w0 or p6_w0 or p7_w0 or p8_w0 or p9_w0 or p9_w1 or p10_w0 or p11_w0) else
    buffer1_vc when p2_w0 or  p4_w0 or p5_w0 or p12_w0 or p13_w0 or p14_w0 else
    X"f";
out_words(6) <=
    hi_words(0) when p1_w0 else
    lo_word when lo_valid = '1' and (p3_w0 or p6_w0 or p7_w0 or p8_w0 or p9_w0 or p9_w1 or p10_w0 or p11_w0) else
    buffer1(0) when p2_w0 or p4_w0 or p5_w0 or p12_w0 or p13_w0 or p14_w0 else
    (others => '-');

out_vc(5) <=
    hi_vc when p1_w0 or p6_w0 or p9_w1 or p10_w0 or p11_w0 else
    buffer1_vc when p2_w0 or p3_w0 or p4_w0 or p5_w0 or p7_w0 or p12_w0 or p13_w0 or p14_w0 else
    X"f";
out_words(5) <=
    hi_words(0) when p6_w0 or p9_w1 or p10_w0 or p11_w0 else
    hi_words(1) when p1_w0 else
    buffer1(1) when p2_w0 or p3_w0 or p4_w0 or p5_w0 or p7_w0 or p12_w0 or p13_w0 or p14_w0 else
    (others => '-');

out_vc(4) <=
    hi_vc when p1_w0 or p2_w0 or p6_w0 or p10_w0 or p11_w0 or p12_w0 else
    buffer1_vc when p3_w0 or p4_w0 or p5_w0 or p7_w0 or p8_w0 or p13_w0 or p14_w0 else
    X"f";
out_words(4) <=
    hi_words(1) when p2_w0 or p6_w0 or p10_w0 or p11_w0 or p12_w0 else
    hi_words(2) when p1_w0 else
    buffer1(2) when p3_w0 or p4_w0 or p5_w0 or p7_w0 or p8_w0 or p13_w0 or p14_w0 else
    (others => '-');

out_vc(3) <=
    hi_vc when p1_w0 or p2_w0 or p6_w0 or p10_w0 or p11_w0 or p12_w0 or p14_w0 else
    buffer1_vc when p3_w0 or p4_w0 or p5_w0 or p7_w0 or p8_w0 or p13_w0 else
    X"f";
out_words(3) <= 
    hi_words(1) when p14_w0 else
    hi_words(2) when p2_w0 or p6_w0 or p10_w0 or p11_w0 or p12_w0 else
    hi_words(3) when p1_w0 else
    buffer1(3) when p3_w0 or p4_w0 or p5_w0 or p7_w0 or p8_w0 or p13_w0 else
    (others => '-');

out_vc(2) <=
    hi_vc when p1_w0 or p2_w0 or p3_w4 or p6_w0 or p7_w0 or p10_w0 or p11_w0 or p12_w0 or p14_w0 else
    buffer1_vc when p4_w0 or p5_w0 or p8_w0 or p13_w0 else
    X"f";
out_words(2) <=
    hi_words(0) when p3_w4 else
    hi_words(1) when p7_w0 else
    hi_words(2) when p14_w0 else
    hi_words(3) when p2_w0 or p6_w0 or p10_w0 or p11_w0 or p12_w0 else
    hi_words(4) when p1_w0 else
    buffer1(4) when p4_w0 or p5_w0 or p8_w0 or p13_w0 else
    (others => '-');

out_vc(1) <=
    hi_vc when p1_w0 or p2_w0 or p3_w4 or p6_w0 or p7_w0 or p10_w0 or p11_w0 or p12_w0 or p14_w0 else
    buffer1_vc when p4_w0 or p5_w0 or p8_w0 or p13_w0 else
    X"f";
out_words(1) <=
    hi_words(1) when p3_w4 else
    hi_words(2) when p7_w0 else
    hi_words(3) when p14_w0 else
    hi_words(4) when p2_w0 or p6_w0 or p10_w0 or p11_w0 or p12_w0 else
    hi_words(5) when p1_w0 else
    buffer1(5) when p4_w0 or p5_w0 or p8_w0 or p13_w0 else
    (others => '-');

out_vc(0) <=
    hi_vc when p1_w0 or p2_w0 or p3_w4 or p4_w0 or p6_w0 or p7_w0 or p11_w0 or p13_w0 or p14_w0 else
    buffer1_vc when p5_w0 or p8_w0 else
    X"f";
out_words(0) <=
    hi_words(1) when p4_w0 or p13_w0 else
    hi_words(2) when p3_w4 else
    hi_words(3) when p7_w0 else
    hi_words(4) when p14_w0 or p14_w0 else
    hi_words(5) when p2_w0 or p6_w0 or p11_w0 else
    hi_words(6) when p1_w0 else
    buffer1(6) when p5_w0 or p8_w0 else
    (others => '-');

hi_ready <=
    '1' when out_ready = '1' and (p1_w0 or p2_w0 or p3_w4 or p4_w0 or p6_w0 or p7_w0 or p9_w1 or p10_w0 or p11_w0 or p12_w0 or p13_w0 or p14_w0) else
    '0';

lo_ready <=
    '1' when out_ready = '1' and lo_valid = '1' and (p3_w0 or p6_w0 or p7_w0 or p8_w0 or p9_w0 or p9_w1 or p10_w0 or p11_w0) else
    '0';

out_valid <= '1' when hi_valid = '1' or lo_valid = '1' or buffer_size /= 0
    else
    '0';

i_process : process (clk)
    variable i, l : integer;
begin
    if rising_edge(clk) then
        if out_ready = '1' then
            if p1_w0 then
                for i in 0 to 1 loop
                    buffer1(i)    <= hi_words(i + 7);
                end loop;
                buffer1_vc <= hi_vc;
                buffer_size <= 2;
            elsif p11_w0 then
                for i in 1 to 3 loop
                    buffer1(i)    <= hi_words(i + 5);
                end loop;
                buffer1_vc <= hi_vc;
                buffer_size <= 3;
            elsif p12_w0 then
                buffer_size <= 0;
            elsif p2_w0 then
                for i in 1 to 3 loop
                    buffer1(i)    <= hi_words(i + 5);
                end loop;
                buffer1_vc <= hi_vc;
                buffer_size <= 3;
            elsif p3_w4 then
                for i in 0 to 5 loop
                    buffer1(i)    <= hi_words(i + 3);
                end loop;
                buffer1_vc <= hi_vc;
                buffer_size <= 6;
            elsif (hi_valid = '0' and p3_w0) or (hi_valid = '1' and hi_size /= "100" and p3_w0) then
                buffer_size <= 0;
            elsif p4_w0 then
                for i in 0 to 6 loop
                    buffer1(i)    <= hi_words(i + 2);
                end loop;
                buffer1_vc <= hi_vc;
                buffer_size <= 7;
            elsif p13_w0 then
                for i in 1 to 3 loop
                    buffer1(i)    <= hi_words(i + 1);
                end loop;
                buffer1_vc <= hi_vc;
                buffer_size <= 3;
            elsif p5_w0 then
                buffer_size <= 0;
                if lo_valid = '1' and hi_valid = '1' and hi_size = "100" then
                    phase <= 1;
                else
                    phase <= 0;
                end if;
            elsif p6_w0 then
                for i in 1 to 3 loop
                    buffer1(i)    <= hi_words(i + 5);
                end loop;
                buffer1_vc <= hi_vc;
                buffer_size <= 3;
            elsif p7_w0 then
                for i in 2 to 6 loop
                    buffer1(i)    <= hi_words(i + 2);
                end loop;
                buffer1_vc <= hi_vc;
                buffer_size <= 5;
            elsif p8_w0 or p14_w0 then
                buffer_size <= 0;
                phase <= 0;
            end if;
        end if;
    end if;
end process;

end Behavioral;
