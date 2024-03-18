library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity inv_s_box_lut is
    port(
        data_in  : in  std_logic_vector(7 downto 0); 
        data_out : out std_logic_vector(7 downto 0)
    );
end entity inv_s_box_lut;

architecture RTL of inv_s_box_lut is
    
    -- Internal RAM
    type ram_type is array(natural range<>) of std_logic_vector(7 downto 0);
    
    constant inv_sbox_ram : ram_type(255 downto 0) := (
        X"7d", X"0c", X"21", X"55", X"63", X"14", X"69", X"e1", X"26", X"d6", X"77", X"ba", X"7e", X"04", X"2b", X"17",                                  
        X"61", X"99", X"53", X"83", X"3c", X"bb", X"eb", X"c8", X"b0", X"f5", X"2a", X"ae", X"4d", X"3b", X"e0", X"a0",                                 
        X"ef", X"9c", X"c9", X"93", X"9f", X"7a", X"e5", X"2d", X"0d", X"4a", X"b5", X"19", X"a9", X"7f", X"51", X"60",                                         
        X"5f", X"ec", X"80", X"27", X"59", X"10", X"12", X"b1", X"31", X"c7", X"07", X"88", X"33", X"a8", X"dd", X"1f", 
        X"f4", X"5a", X"cd", X"78", X"fe", X"c0", X"db", X"9a", X"20", X"79", X"d2", X"c6", X"4b", X"3e", X"56", X"fc", 
        X"1b", X"be", X"18", X"aa", X"0e", X"62", X"b7", X"6f", X"89", X"c5", X"29", X"1d", X"71", X"1a", X"f1", X"47", 
        X"6e", X"df", X"75", X"1c", X"e8", X"37", X"f9", X"e2", X"85", X"35", X"ad", X"e7", X"22", X"74", X"ac", X"96",                               
        X"73", X"e6", X"b4", X"f0", X"ce", X"cf", X"f2", X"97", X"ea", X"dc", X"67", X"4f", X"41", X"11", X"91", X"3a", 
        X"6b", X"8a", X"13", X"01", X"03", X"bd", X"af", X"c1", X"02", X"0f", X"3f", X"ca", X"8f", X"1e", X"2c", X"d0",               
        X"06", X"45", X"b3", X"b8", X"05", X"58", X"e4", X"f7", X"0a", X"d3", X"bc", X"8c", X"00", X"ab", X"d8", X"90", 
        X"84", X"9d", X"8d", X"a7", X"57", X"46", X"15", X"5e", X"da", X"b9", X"ed", X"fd", X"50", X"48", X"70", X"6c", 
        X"92", X"b6", X"65", X"5d", X"cc", X"5c", X"a4", X"d4", X"16", X"98", X"68", X"86", X"64", X"f6", X"f8", X"72", 
        X"25", X"d1", X"8b", X"6d", X"49", X"a2", X"5b", X"76", X"b2", X"24", X"d9", X"28", X"66", X"a1", X"2e", X"08", 
        X"4e", X"c3", X"fa", X"42", X"0b", X"95", X"4c", X"ee", X"3d", X"23", X"c2", X"a6", X"32", X"94", X"7b", X"54", 
        X"cb", X"e9", X"de", X"c4", X"44", X"43", X"8e", X"34", X"87", X"ff", X"2f", X"9b", X"82", X"39", X"e3", X"7c", 
        X"fb", X"d7", X"f3", X"81", X"9e", X"a3", X"40", X"bf", X"38", X"a5", X"36", X"30", X"d5", X"6a", X"09", X"52" 
    );
    
begin
    
    -- Output
    data_out <= inv_sbox_ram(to_integer(unsigned(data_in)));
    
end architecture RTL;