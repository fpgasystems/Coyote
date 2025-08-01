library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity s_box_lut is
    port(
        data_in  : in  std_logic_vector(7 downto 0); 
        data_out : out std_logic_vector(7 downto 0)
    );
end entity s_box_lut;

architecture RTL of s_box_lut is
    
    -- Internal RAM
    type ram_type is array(natural range<>) of std_logic_vector(7 downto 0);
    constant sbox_ram : ram_type(255 downto 0) := (
        X"16", X"bb", X"54", X"b0", X"0f", X"2d", X"99", X"41", X"68", X"42", X"e6", X"bf", X"0d", X"89", X"a1", X"8c", 
        X"df", X"28", X"55", X"ce", X"e9", X"87", X"1e", X"9b", X"94", X"8e", X"d9", X"69", X"11", X"98", X"f8", X"e1", 
        X"9e", X"1d", X"c1", X"86", X"b9", X"57", X"35", X"61", X"0e", X"f6", X"03", X"48", X"66", X"b5", X"3e", X"70", 
        X"8a", X"8b", X"bd", X"4b", X"1f", X"74", X"dd", X"e8", X"c6", X"b4", X"a6", X"1c", X"2e", X"25", X"78", X"ba", 
        X"08", X"ae", X"7a", X"65", X"ea", X"f4", X"56", X"6c", X"a9", X"4e", X"d5", X"8d", X"6d", X"37", X"c8", X"e7", 
        X"79", X"e4", X"95", X"91", X"62", X"ac", X"d3", X"c2", X"5c", X"24", X"06", X"49", X"0a", X"3a", X"32", X"e0", 
        X"db", X"0b", X"5e", X"de", X"14", X"b8", X"ee", X"46", X"88", X"90", X"2a", X"22", X"dc", X"4f", X"81", X"60", 
        X"73", X"19", X"5d", X"64", X"3d", X"7e", X"a7", X"c4", X"17", X"44", X"97", X"5f", X"ec", X"13", X"0c", X"cd", 
        X"d2", X"f3", X"ff", X"10", X"21", X"da", X"b6", X"bc", X"f5", X"38", X"9d", X"92", X"8f", X"40", X"a3", X"51", 
        X"a8", X"9f", X"3c", X"50", X"7f", X"02", X"f9", X"45", X"85", X"33", X"4d", X"43", X"fb", X"aa", X"ef", X"d0", 
        X"cf", X"58", X"4c", X"4a", X"39", X"be", X"cb", X"6a", X"5b", X"b1", X"fc", X"20", X"ed", X"00", X"d1", X"53", 
        X"84", X"2f", X"e3", X"29", X"b3", X"d6", X"3b", X"52", X"a0", X"5a", X"6e", X"1b", X"1a", X"2c", X"83", X"09", 
        X"75", X"b2", X"27", X"eb", X"e2", X"80", X"12", X"07", X"9a", X"05", X"96", X"18", X"c3", X"23", X"c7", X"04", 
        X"15", X"31", X"d8", X"71", X"f1", X"e5", X"a5", X"34", X"cc", X"f7", X"3f", X"36", X"26", X"93", X"fd", X"b7", 
        X"c0", X"72", X"a4", X"9c", X"af", X"a2", X"d4", X"ad", X"f0", X"47", X"59", X"fa", X"7d", X"c9", X"82", X"ca", 
        X"76", X"ab", X"d7", X"fe", X"2b", X"67", X"01", X"30", X"c5", X"6f", X"6b", X"f2", X"7b", X"77", X"7c", X"63" 
    );
    
begin
    
    -- Output
    data_out <= sbox_ram(to_integer(unsigned(data_in)));
    
end architecture RTL;