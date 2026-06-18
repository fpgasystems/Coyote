library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity aes_top is
	generic(
		NPAR : integer := 2
	);
	port(
		clk : in std_logic;
		reset_n : in std_logic; 
		stall : in std_logic;
	-- Key
		key_in : in std_logic_vector(127 downto 0);
		keyVal_in : in std_logic;
		keyVal_out : out std_logic;
		last_in : in std_logic;
		last_out : out std_logic;
		keep_in : in std_logic_vector(NPAR*16-1 downto 0);
		keep_out : out std_logic_vector(NPAR*16-1 downto 0);
		id_in : in std_logic_vector(NPAR*6-1 downto 0);
		id_out : out std_logic_vector(NPAR*6-1 downto 0);
	-- Data valid
		dVal_in : in std_logic; -- Data valid
		dVal_out : out std_logic;
	-- Data
		data_in : in  std_logic_vector(NPAR*128-1 downto 0); 
		data_out : out std_logic_vector(NPAR*128-1 downto 0)
	);
end entity aes_top;

architecture RTL of aes_top is

	type keep_array is array (NPAR-1 downto 0) of std_logic_vector(15 downto 0);
	type id_array is array (NPAR-1 downto 0) of std_logic_vector(5 downto 0);

	-- Internal signals
	signal key_exp : std_logic_vector(11*128-1 downto 0);
	signal dVal : std_logic_vector(NPAR-1 downto 0);
	signal last : std_logic_vector(NPAR-1 downto 0);
	signal keep : keep_array;
	signal id: id_array;
	
begin
	
	-- Instantiate key pipeline
	GEN_KEY_PIPE: entity work.key_pipeline
		port map(
			clk			=> clk,
			reset_n 	=> reset_n, 
			keyVal_in 	=> keyVal_in,
			keyVal_out 	=> keyVal_out,
			key_in 		=> key_in,
			key_out 	=> key_exp
		);
	
	-- Instantiate AES pipelines
	GEN_AES_PAR: for i in 0 to NPAR-1 generate
		GEN_AES_PIPE: entity work.aes_pipeline
			port map(
				clk 		=> clk,
				reset_n 	=> reset_n, 
				stall 		=> stall,
			-- Key
				key_in 		=> key_exp,
			-- Data valid
				dVal_in 	=> dVal_in,
				dVal_out 	=> dVal(i),
				last_in 	=> last_in,
				last_out 	=> last(i),
				keep_in 	=> keep_in(i*16+15 downto i*16),
				keep_out 	=> keep(i),
				id_in		=> id_in(i*6+5 downto i*6),
				id_out 		=> id(i),
			-- Data
				data_in 	=> data_in(i*128+127 downto i*128),
				data_out 	=> data_out(i*128+127 downto i*128)
			);
	end generate GEN_AES_PAR;


	GEN_VALID: process (dVal) is
	variable tmp : std_logic;
	begin
		tmp := '0';
		for i in 0 to NPAR-1 loop
			tmp := tmp or dVal(i); 
		end loop;
		dVal_out <= tmp;
	end process GEN_VALID;

	GEN_LAST: process (last) is
	variable tmp : std_logic;
	begin
		tmp := '0';
		for i in 0 to NPAR-1 loop
			tmp := tmp or last(i); 
		end loop;
		last_out <= tmp;
	end process GEN_LAST;

	GEN_KEEP: for i in 0 to NPAR-1 generate
		keep_out(i*16+15 downto i*16) <= keep(i);
	end generate GEN_KEEP;

	GEN_ID: for i in 0 to NPAR-1 generate
		id_out(i*6+5 downto i*6) <= id(i);
	end generate GEN_ID;

	
end architecture RTL;