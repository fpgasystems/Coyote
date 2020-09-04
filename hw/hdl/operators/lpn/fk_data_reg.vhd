--*************************************************************************--
--! @file		: fk_data_reg.vhd
--! @project	: Firekite, Dual port RAM implementation.
--! 
--! Input and output data registers
--! 
--! @date		: 10.10.2017.
--*************************************************************************--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.utils.all;

entity fk_data_reg is
	generic(
		NBITS : integer := 4096; -- Length of the basis vectors in bits
		DBITS : integer := 2816; -- Data set length in bits
		BUS_SIZE : integer := 32 -- Avalon bus size
	);
	port(
		clk : in std_logic;
		reset_n	: in std_logic;
	-- Control
		ld_data	: in std_logic; -- Parallel load reg.
		wr_data	: in std_logic; -- Serial write reg.
		rd_data	: in std_logic; -- Serial read reg.
		rst_pntr : in std_logic; -- Reset reg. pointers
	-- Data
		sink_data_p	: in std_logic_vector(DBITS-1 downto 0); 
		sink_data_s	: in std_logic_vector(BUS_SIZE-1 downto 0);	 
		src_data_s : out std_logic_vector(BUS_SIZE-1 downto 0) 
	);
end entity fk_data_reg;

architecture RTL of fk_data_reg is

	-- Constants
	constant PNT_BITS : integer := bitlength(DBITS/BUS_SIZE-1); 
	
	-- Internal regsiters
	signal data_in_reg, data_in_next : std_logic_vector(DBITS-1 downto 0);
	signal data_out_reg, data_out_next : std_logic_vector(DBITS-1 downto 0); 	
	
	-- Counters and pointers
	signal prd_reg, prd_next : unsigned(PNT_BITS-1 downto 0);
	signal pwr_reg, pwr_next : unsigned(PNT_BITS-1 downto 0);
	
begin
	
	-- Register process 
	--
	CR_REG: process (clk, reset_n) is
	begin
		if reset_n = '0' then
			data_in_reg <= (others => '0');
			data_out_reg <= (others => '0');
			prd_reg <= to_unsigned(0, PNT_BITS);
			pwr_reg <= to_unsigned(0, PNT_BITS);
		elsif rising_edge(clk) then
			data_in_reg <= data_in_next;
			data_out_reg <= data_out_next;
			prd_reg <= prd_next;
			pwr_reg <= pwr_next;
		end if;
	end process CR_REG;
	
	-- Datapath process
	--
	DP: process (data_in_reg, data_out_reg, prd_reg, pwr_reg,
		ld_data, wr_data, rd_data, rst_pntr, sink_data_p, sink_data_s) is
	variable idx : integer;
	begin
		data_in_next <= data_in_reg;
		data_out_next <= data_out_reg;
		prd_next <= prd_reg;
		pwr_next <= pwr_reg;
		
		-- Parallel load output data register. During the execution stage
		-- when work vector is XOR-ed with the data to produce the
		-- result.
		if ld_data = '1' then 
			data_out_next <= data_in_reg xor sink_data_p;
		end if;
		
		-- Serial load data in register. During the phase where the data
		-- is fetched from the memory.
		if wr_data = '1' then
			idx := to_integer(pwr_reg);
			data_in_next(idx*BUS_SIZE+BUS_SIZE-1 downto idx*BUS_SIZE) <= sink_data_s;
			pwr_next <= pwr_reg + 1;
		end if;
		
		-- Serial read data register. During the phase where the result
		-- is stored in the memory.
		if rd_data = '1' then
			prd_next <= prd_reg + 1;
		end if;
		
		-- Reset pointers.
		if rst_pntr = '1' then
			prd_next <= to_unsigned(0, PNT_BITS);
			pwr_next <= to_unsigned(0, PNT_BITS);
		end if;
		
	end process DP;
	
	-- Output
	src_data_s <= data_out_reg(to_integer(prd_reg)*BUS_SIZE+BUS_SIZE-1 downto to_integer(prd_reg)*BUS_SIZE);
	
end architecture RTL;
