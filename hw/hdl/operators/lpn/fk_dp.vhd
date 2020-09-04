--*************************************************************************--
--! @file		: fk_dp.vhd
--! @project 	: Firekite, Single port RAM implementation.
--! 
--! Datapath registers consisting of work, key and data registers.
--! 
--! @date		: 10.10.2017.
--*************************************************************************--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.utils.all;

entity fk_dp is
	generic(
		NBITS : integer := 4096; -- Length of the basis vector in bits
		DBITS : integer := 2816; -- Data set length in bits
		EBITS : integer := 768; -- Length of the compressed noise bits
		VBITS : integer := 512; -- Number of basis vectors
		BUS_SIZE : integer := 32; -- Avalon bus size in bits
		NCYC : integer := 32 -- Cycl. to exp. noise bits and update work vctr
	);
	port(
		clk : in std_logic;
		reset_n	: in std_logic;
	-- Control
		ld_key_init : in std_logic; 
		ld_v_init : in std_logic;
		ld_v : in std_logic; 
		start_key : in std_logic; 
		done_key : out std_logic; 
		ld_data	: in std_logic; 
		wr_data	: in std_logic; 
		rd_data	: in std_logic; 
		rst_pntr : in std_logic; 
		ld_work	: in std_logic; 	
		wr_work	: in std_logic; 
		rst_work : in std_logic;
		start_init_exp : in std_logic;
		start_exp : in std_logic; 
		done_exp : out std_logic;
	-- Data
		sink_data_s	: in std_logic_vector(BUS_SIZE-1 downto 0);
		src_data_s : out std_logic_vector(BUS_SIZE-1 downto 0)
	);
end entity fk_dp;

architecture RTL of fk_dp is
	
	-- Internal signals
	signal data_work_in : std_logic_vector(NBITS-1 downto 0);
	signal data_work_out : std_logic_vector(NBITS-1 downto 0);
	signal data_noise_out : std_logic_vector(NBITS-1 downto 0);
	signal data_xor_work_noise : std_logic_vector(NBITS-1 downto 0);
	
begin
	
	-- Key register instantiation.
	GEN_KEY_REG: entity work.fk_key_reg
		generic map(
			NBITS		=> NBITS,
			VBITS 		=> VBITS,
			NCYC 		=> NCYC
		)
		port map(
			clk			=> clk,
			reset_n		=> reset_n,
		-- Control
			ld_key_init	=> ld_key_init,
			ld_v_init 	=> ld_v_init,
			ld_v 		=> ld_v,
			start		=> start_key, 
			done 		=> done_key,
		-- Data
			sink_data_init => data_work_out,
			sink_data 	=> data_xor_work_noise(VBITS-1 downto 0), 
			src_data 	=> data_work_in
		);
	
	-- Work register instantiation.
	GEN_WORK_REG: entity work.fk_work_reg 
		generic map(
			NBITS 		=> NBITS,
			BUS_SIZE 	=> BUS_SIZE
		)
		port map(
			clk 		=> clk,
			reset_n		=> reset_n,
		-- Control
			ld_work		=> ld_work,
			wr_work		=> wr_work,
			rst_work 	=> rst_work,
		-- Data
			sink_data_p	=> data_work_in,
			src_data_p 	=> data_work_out,
			sink_data_s	=> sink_data_s
		);	
		
	-- Data register instantiation.
	GEN_DATA_REG: entity work.fk_data_reg
		generic map(
			NBITS		=> NBITS,
			DBITS		=> DBITS,
			BUS_SIZE 	=> BUS_SIZE
		)
		port map(
			clk 		=> clk,
			reset_n		=> reset_n,
		-- Control
			ld_data		=> ld_data,
			wr_data		=> wr_data,
			rd_data		=> rd_data, 
			rst_pntr 	=> rst_pntr,
		-- Data
			sink_data_p	=> data_xor_work_noise(NBITS-1 downto NBITS-DBITS),
			sink_data_s	=> sink_data_s,	 
			src_data_s 	=> src_data_s
		);
		
	-- Noise register instantiation
	GEN_NOISE_REG: entity work.fk_noise_reg
		generic map(
			NBITS 		=> NBITS,
			EBITS 		=> EBITS,
			NCYC 		=> NCYC
		)
		port map(
			clk			=> clk,
			reset_n		=> reset_n,
		-- Control
			start_init 	=> start_init_exp,
			start 		=> start_exp,
			done 		=> done_exp,
		-- Data
			sink_data_init => data_work_out((NBITS-DBITS)-1 downto VBITS),
			sink_data 	=> data_xor_work_noise((NBITS-DBITS)-1 downto VBITS),
			src_data 	=> data_noise_out
		);
	
	-- XOR noise and work
	data_xor_work_noise <= data_work_out xor data_noise_out;

end architecture RTL;
