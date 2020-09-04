--*************************************************************************--
--! @file		: fk_work_reg.vhd
--! @project	: Firekite, Dual port RAM implementation.
--! 
--! Work register.
--! 
--! @date		: 10.10.2017.
--*************************************************************************--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.utils.all;

entity fk_work_reg is
	generic(
		NBITS : integer := 4096; -- Length of the basis vector
		BUS_SIZE : integer := 32 -- Avalon bus size
	);
	port(
		clk : in std_logic;
		reset_n	: in std_logic;
	-- Control
		ld_work	: in std_logic; -- Parallel load reg.
		wr_work	: in std_logic; -- Serial write reg.
		rst_work : in std_logic; -- Reset reg.
	-- Data
		sink_data_p	: in std_logic_vector(NBITS-1 downto 0); -- Parallel
		src_data_p : out std_logic_vector(NBITS-1 downto 0);
		sink_data_s	: in std_logic_vector(BUS_SIZE-1 downto 0) -- Serial
	);
end entity fk_work_reg;

architecture RTL of fk_work_reg is
	
	-- Internal regsiters
	signal work_reg, work_next : std_logic_vector(NBITS-1 downto 0);
	
begin
	
	-- Register process
	--
	CR_REG: process (clk, reset_n) is
	begin
		if reset_n = '0' then
			work_reg <= (others => '0');
		elsif rising_edge(clk) then
			work_reg <= work_next;
		end if;
	end process CR_REG;
	
	-- Datapath process
	--
	DP: process (work_reg, 
		ld_work, wr_work, rst_work, sink_data_p, sink_data_s) is
	variable idx : integer;
	begin
		work_next <= work_reg;
		
		-- Parallel load work register. XOR-s its contents with
		-- data from the key register(update of the work vector).
		if ld_work = '1' then
			work_next <= work_reg xor sink_data_p;
		end if;
		
		-- Serial write work register. Shift register.
		if wr_work = '1' then
			work_next <= sink_data_s & work_reg(NBITS-1 downto BUS_SIZE);
		end if;
		
		-- Resets the register with all zeros.
		if rst_work = '1' then
			work_next <= (others => '0');
		end if;

	end process DP;
	
	-- Output
	src_data_p <= work_reg;
	
end architecture RTL;
