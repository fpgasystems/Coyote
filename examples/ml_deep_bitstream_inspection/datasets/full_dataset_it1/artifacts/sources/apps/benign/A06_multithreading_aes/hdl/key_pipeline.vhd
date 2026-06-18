library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity key_pipeline is
	port(
		clk : in std_logic;
		reset_n : in std_logic; 
		keyVal_in : in std_logic; -- Key valid
		keyVal_out : out std_logic;
		key_in : in std_logic_vector(127 downto 0);
		key_out : out std_logic_vector(11*128-1 downto 0)
	);
end entity key_pipeline;

architecture RTL of key_pipeline is
	
	-- Internal signals
	type keyVal_array is array (10 downto 0) of std_logic;
	type key_array is array (10 downto 0) of std_logic_vector(127 downto 0);
	
	signal keyVal_pipe : keyVal_array; -- Key valid signal pipeline
	signal key_pipe : key_array; -- Key pipeline
	
	-- Internal RAM for round constants
	type ram_type is array(natural range<>) of std_logic_vector(7 downto 0);
	constant rcon: ram_type(0 to 9) := (X"01", X"02", X"04", X"08", X"10", X"20", X"40", X"80", X"1b", X"36");
	
begin
	
	-- Instantiate base key register
	GEN_KEY_BASE: entity work.key_pipe_reg
		port map(
			clk			=> clk,
			reset_n 	=> reset_n,
			dVal_in 	=> keyVal_in,
			dVal_out 	=> keyVal_pipe(0),
			data_in		=> key_in,
			data_out 	=> key_pipe(0)
		);
	
	-- Instantiate key expansion pipeline
	GEN_KEY_EXP: for i in 0 to 9 generate
		KEY_X: entity work.key_pipe_stage
			port map(
				clk 		=> clk,
				reset_n 	=> reset_n,
				keyVal_in 	=> keyVal_pipe(i),
				keyVal_out 	=> keyVal_pipe(i+1),
				key_in 		=> key_pipe(i),
				key_out 	=> key_pipe(i+1),
				rnd_const 	=> rcon(i)
			);
	end generate GEN_KEY_EXP;
	
	-- Key valid out
	keyVal_out <= keyVal_pipe(10);
	
	-- Keys out
	GEN_KEYS_OUT: for i in 0 to 10 generate
		key_out(i*128+127 downto i*128) <= key_pipe(i);
	end generate GEN_KEYS_OUT;
	
end architecture RTL;