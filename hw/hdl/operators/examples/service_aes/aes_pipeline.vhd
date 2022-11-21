library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity aes_pipeline is
	port(
		clk : in std_logic;
		reset_n : in std_logic;
		stall : in std_logic; 
	-- Key
		key_in : in std_logic_vector(11*128-1 downto 0);
		last_in : in std_logic;
		last_out : out std_logic;
		keep_in : in std_logic_vector(15 downto 0);
		keep_out : out std_logic_vector(15 downto 0);
	-- Data valid
		dVal_in : in std_logic; -- Data valid
		dVal_out : out std_logic;
	-- Data
		data_in : in  std_logic_vector(127 downto 0); 
		data_out : out std_logic_vector(127 downto 0)
	);
end entity aes_pipeline;

architecture RTL of aes_pipeline is
	
	-- Internal signals
	type dVal_array is array (8 downto 0) of std_logic;
	type data_array is array (8 downto 0) of std_logic_vector(127 downto 0);
	type last_array is array (8 downto 0) of std_logic;
	type keep_array is array (8 downto 0) of std_logic_vector(15 downto 0);

	signal dVal_pipe : dVal_array; -- Data valid signal pipeline
	signal data_pipe : data_array; -- Data pipeline
	signal last_pipe : last_array;
	signal keep_pipe : keep_array;
	
begin
	
	-- Instantiate regular AES stages
	GEN_AES: for i in 0 to 8 generate
		
		GEN_S0: if i = 0 generate
			S0: entity work.aes_pipe_stage
				port map(
					clk 	=> clk,
					reset_n	=> reset_n,
					stall 	=> stall,
					key_in 	=> key_in(127 downto 0), 
					last_in => last_in,
					last_out => last_pipe(0),
					keep_in => keep_in,
					keep_out => keep_pipe(0),
					dVal_in => dVal_in,
					dVal_out => dVal_pipe(0),
					data_in	=> data_in,  
					data_out => data_pipe(0)
				);
		end generate GEN_S0;
	
		GEN_SX: if i > 0 generate
			SX: entity work.aes_pipe_stage
				port map(
					clk 	=> clk,
					reset_n	=> reset_n,
					stall 	=> stall,
					key_in 	=> key_in(128*i+127 downto 128*i), 
					last_in => last_pipe(i-1),
					last_out => last_pipe(i),
					keep_in => keep_pipe(i-1),
					keep_out => keep_pipe(i),
					dVal_in => dVal_pipe(i-1),
					dVal_out => dVal_pipe(i),
					data_in	=> data_pipe(i-1),  
					data_out => data_pipe(i)
				);
		end generate GEN_SX;
	
	end generate GEN_AES;
	
	-- Instantiate last stage
	SL: entity work.aes_pipe_stage_last
		port map(
			clk 	=> clk,
			reset_n	=> reset_n,
			stall 	=> stall,
			key_in 	=> key_in(128*9+127 downto 128*9), 
			key_last => key_in(128*10+127 downto 128*10),
			last_in => last_pipe(8),
			last_out => last_out,
			keep_in => keep_pipe(8),
			keep_out => keep_out,
			dVal_in => dVal_pipe(8),
			dVal_out => dVal_out,
			data_in	=> data_pipe(8),  
			data_out => data_out
		);
	
end architecture RTL;