library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity shift_rows is
    port(
        data_in  : in  std_logic_vector(127 downto 0); 
        data_out : out std_logic_vector(127 downto 0) 
    );
end entity shift_rows;

architecture RTL of shift_rows is
    
    -- Internal signals
    type data_array is array (15 downto 0) of std_logic_vector(7 downto 0);
    signal in_array, out_array : data_array; 
    
begin
    
    -- Input generation
    GEN_IN: for i in 15 downto 0 generate
        in_array(15-i) <= data_in(i*8+7 downto i*8);
    end generate GEN_IN;
    
    --First mixed column input
    out_array(0) <= in_array(0);
    out_array(1) <= in_array(5);
    out_array(2) <= in_array(10);
    out_array(3) <= in_array(15);
    
    -- Second mixed column input
    out_array(4) <= in_array(4);
    out_array(5) <= in_array(9);
    out_array(6) <= in_array(14);
    out_array(7) <= in_array(3);
    
    -- Third mixed column input
    out_array(8) <= in_array(8);
    out_array(9) <= in_array(13);
    out_array(10) <= in_array(2);
    out_array(11) <= in_array(7);
    
    -- Fourth mixed column input
    out_array(12) <= in_array(12);
    out_array(13) <= in_array(1);
    out_array(14) <= in_array(6);
    out_array(15) <= in_array(11);
    
    -- Output generation
    GEN_OUT: for i in 15 downto 0 generate
        data_out(i*8+7 downto i*8) <= out_array(15-i);
    end generate GEN_OUT;
    
end architecture RTL;