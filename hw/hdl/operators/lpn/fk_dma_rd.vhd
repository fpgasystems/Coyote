--*************************************************************************--
--! @file		: fk_dma_rd.vhd
--! @project 	: Firekite, Dual port RAM implementation.
--! 
--! DMA read unit. Generic bus size. Burst operation. 
--! 
--! @date		: 10.10.2017.
--*************************************************************************--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.utils.all;

entity fk_dma_rd is
	generic(
		BUS_SIZE : integer := 32 -- Avalon bus size in bits
	);
	port(
		clk : in std_logic;
		reset_n	: in std_logic;
	-- Control
		start : in std_logic;
		src : in std_logic_vector(31 downto 0); 
		len	: in std_logic_vector(9 downto 0);
		dVal : out std_logic; 
		done : out std_logic; 
	-- Data
		src_data : out std_logic_vector(BUS_SIZE-1 downto 0);
	-- Avalon master
		avm_WaitRequest : in std_logic; 
		avm_Read : out std_logic; 
		avm_ReadDataValid : in std_logic; 
		avm_ReadData : in std_logic_vector(BUS_SIZE-1 downto 0); 
		avm_Address	: out std_logic_vector(31 downto 0); 
		avm_BurstCount : out std_logic_vector(7 downto 0)
	);
end entity fk_dma_rd;

architecture RTL of fk_dma_rd is
	
	-- Constants
	constant MAX_BURST_SIZE : integer := 128; -- Max burst size on the bus
	constant BUS_SIZE_BYTES	: integer := BUS_SIZE/8; -- Bus size in bytes
	constant CNT_BURST : integer := bitlength(MAX_BURST_SIZE-1);
	
	-- FSM
	type state_type is (ST_IDLE, ST_READ_BURST_START, ST_READ_BURST);
	signal state_reg, state_next : state_type;			
	
	-- Internal registers
	signal sadd_reg, sadd_next : std_logic_vector(31 downto 0);
	signal len_reg, len_next : std_logic_vector(7 downto 0);
	
	-- Counters
	signal cnt_b_reg, cnt_b_next : unsigned(CNT_BURST-1 downto 0);
	
	-- Status signals
	signal d_cnt_burst : std_logic;
	
begin
	
	-- Register process
	--
	CR_REG: process (clk, reset_n) is
	begin		
		if reset_n = '0' then
			state_reg <= ST_IDLE;
			cnt_b_reg <= to_unsigned(0, CNT_BURST);
			sadd_reg <= (others => '0');
			len_reg	<= (others => '0');
		elsif rising_edge(clk) then
			state_reg <= state_next;
			cnt_b_reg <= cnt_b_next;
			sadd_reg <= sadd_next;
			len_reg	<= len_next;
		end if;	
	end process CR_REG;
	
	-- Next state logic
	--
	NSL: process (state_reg, start, avm_WaitRequest, d_cnt_burst) is
	begin	
		state_next <= state_reg;
		
		case state_reg is
			
			-- IDLE
			-- When start is asserted go to Read state.
			when ST_IDLE =>
				if start = '1' then
					state_next <= ST_READ_BURST_START;
				end if;
			
			-- READ BURST START
			-- Signal the start of the burst read sequence.
			when ST_READ_BURST_START =>
				if avm_WaitRequest /= '1' then
					state_next <= ST_READ_BURST;
				end if;
			
			-- READ BURST
			-- Burst read the data from the memory.
			when ST_READ_BURST =>
				if d_cnt_burst = '1' then
					state_next <= ST_IDLE;
				end if;
		
		end case;		
	end process NSL;
	
	-- Datapath process
	--
	DP: process (state_reg, cnt_b_reg, sadd_reg, len_reg,
		start, len, src, avm_ReadDataValid, d_cnt_burst, avm_WaitRequest) is
	begin
		cnt_b_next <= cnt_b_reg;
		sadd_next <= sadd_reg;
		len_next <= len_reg;	
		
		dVal <= '0';
		
		case state_reg is 
			
			-- Latch source and the length of the data in
			-- the dedicated registers.
			when ST_IDLE =>
				if start = '1' then
					sadd_next <= src;
					len_next <= std_logic_vector(to_unsigned((to_integer(unsigned(len))/BUS_SIZE_BYTES), 8));
				end if;
			
			-- Increment counters and address when read data is valid and signal to the 
			-- controller that the data is valid.
			when ST_READ_BURST =>
				if avm_ReadDataValid = '1' then
					dVal <= '1';
					sadd_next <= std_logic_vector(unsigned(sadd_reg) + to_unsigned(BUS_SIZE_BYTES, 32));
					if d_cnt_burst = '1' then
						cnt_b_next <= to_unsigned(0, CNT_BURST);
					else
						cnt_b_next <= cnt_b_reg + 1;		
					end if;
				end if;
			
			when others => null;
		
		end case;
	end process DP;
		
	-- Status signals
	d_cnt_burst <= '1' when cnt_b_reg = unsigned(len_reg)-1 else '0';
	
	-- Output	
	done <= '1' when state_reg = ST_IDLE else '0';
	src_data <= avm_ReadData;
		
	avm_Read <= '1' when state_reg = ST_READ_BURST_START else '0';	
	avm_BurstCount <= len_reg;
	avm_Address	<= sadd_reg;
	
end architecture RTL;
