library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity key_expansion is
	port(
		key_in : in  std_logic_vector(127 downto 0); 
		key_out : out std_logic_vector(127 downto 0); 
		rnd_const : in  std_logic_vector(7 downto 0)
	);
end entity key_expansion;

architecture RTL of key_expansion is
	
	-- Internal signals
	type word_array is array (3 downto 0) of std_logic_vector(31 downto 0);
	signal key_word : word_array;
	signal key_next	: word_array;
	signal key_shift : std_logic_vector(31 downto 0);
	signal key_s_box : std_logic_vector(31 downto 0); 
	signal temp	: std_logic_vector(31 downto 0);
	
begin
	
	-- Key words
	GEN_KW: for i in  0 to 3 generate
		key_word(3-i) <= key_in(32*i+31 downto 32*i);
	end generate GEN_KW;
	
	-- Rotate 8 bits
	key_shift <= key_word(3)(23 downto 0) & key_word(3)(31 downto 24);
	
	-- S-box
	GEN_SBOX: for i in 0 to 3 generate
		SBOX: entity work.s_box_lut port map(
			data_in  	=> key_shift(i*8+7 downto i*8),
			data_out	=> key_s_box(i*8+7 downto i*8)
		);
	end generate GEN_SBOX;
	
	-- Add round constant
	temp(31 downto 24) <= key_s_box(31 downto 24) xor rnd_const;
	temp(23 downto 0)  <= key_s_box(23 downto 0);
	
	-- Next key
	key_next(0) <= key_word(0) xor temp;
	key_next(1) <= key_word(1) xor key_next(0);
	key_next(2) <= key_word(2) xor key_next(1);
	key_next(3) <= key_word(3) xor key_next(2);
	
	-- Output
	key_out <= key_next(0) & key_next(1) & key_next(2) & key_next(3);
	
end architecture RTL;
