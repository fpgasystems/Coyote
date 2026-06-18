library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mix_columns is
	port(
		data_in : in std_logic_vector(127 downto 0); 
		data_out : out std_logic_vector(127 downto 0)
	);
end entity mix_columns;

architecture RTL of mix_columns is
	
	-- Internal signals
	type data_array is array (15 downto 0) of std_logic_vector(7 downto 0);
	-- x1, x2, x3 multiplication
	signal in_array, out_array, in_array_x2, in_array_x3 : data_array;
	
begin
	
	-- Input generation
	GEN_IN: for i in 15 downto 0 generate
		in_array(15-i) <= data_in(i*8+7 downto i*8);
	end generate GEN_IN;
	
	-- Multiplication
	GEN_M: for i in 15 downto 0 generate
		-- x2
		in_array_x2(15-i) <= 
			(in_array(15-i)(6 downto 0) & '0') xor "00011011" when in_array(15-i)(7) = '1' else
			(in_array(15-i)(6 downto 0) & '0');
		-- x3
		in_array_x3(15-i) <=
			(in_array(15-i)(6 downto 0) & '0') xor in_array(15-i) xor "00011011" when in_array(15-i)(7) = '1' else
			(in_array(15-i)(6 downto 0) & '0') xor in_array(15-i);
	end generate GEN_M;
	
	-- Mixed columns generation
	GEN_MC: for i in 0 to 3 generate
		out_array(4*i) <= in_array_x2(4*i) xor in_array_x3(4*i+1) xor in_array(4*i+2) xor in_array(4*i+3);
		out_array(4*i+1) <= in_array(4*i) xor in_array_x2(4*i+1) xor in_array_x3(4*i+2) xor in_array(4*i+3);
		out_array(4*i+2) <= in_array(4*i) xor in_array(4*i+1) xor in_array_x2(4*i+2) xor in_array_x3(4*i+3);
		out_array(4*i+3) <= in_array_x3(4*i) xor in_array(4*i+1) xor in_array(4*i+2) xor in_array_x2(4*i+3);
	end generate;
	
	-- Output generation
	GEN_O: for i in 15 downto 0 generate
		data_out(i*8+7 downto i*8) <= out_array(15-i);
	end generate GEN_O;
	
end architecture RTL;