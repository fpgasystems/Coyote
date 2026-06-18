library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity aes_round_last is
	port(
		key_in : in std_logic_vector(127 downto 0); 
		key_last : in std_logic_vector(127 downto 0); 
		data_in : in  std_logic_vector(127 downto 0); 
		data_out : out std_logic_vector(127 downto 0)
	);
end entity aes_round_last;

architecture RTL of aes_round_last is
	
	-- Internal signals
	signal data_in_sbox	: std_logic_vector(127 downto 0); 
	signal data_out_sbox : std_logic_vector(127 downto 0);
	signal data_out_sr : std_logic_vector(127 downto 0);

begin
	
	-- Add round key
	data_in_sbox <= data_in xor key_in;
	
	-- S-box stage
	GEN_SBOX: for i in 0 to 15 generate
		SBOX: entity work.s_box_lut port map(
			data_in		=> data_in_sbox(8*i+7 downto 8*i),
			data_out	=> data_out_sbox(8*i+7 downto 8*i)
		);
	end generate GEN_SBOX;
	
	-- Shift row
	GEN_SROW: entity work.shift_rows port map(
		data_in		=> data_out_sbox,
		data_out	=> data_out_sr
	);
	
	-- Last add round key
	data_out <= data_out_sr xor key_last;
	
end architecture RTL;