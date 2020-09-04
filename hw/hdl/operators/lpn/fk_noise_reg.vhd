--*************************************************************************--
--! @file		: fk_noise_reg.vhd
--! @project	: Firekite, Dual port RAM implementation.
--! 
--! Expansion of the compressed noise bits.
--! 
--! @date		: 10.10.2017.
--*************************************************************************--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.utils.all;

entity fk_noise_reg is
	generic(
		NBITS : integer := 4096; -- Length of the basis vector
		EBITS : integer := 768;  -- Length of the compressed noise bits 
		NCYC : integer := 32  -- Number of cycles for the exp. of noise bits
	);
	port(
		clk : in std_logic;
		reset_n	: in std_logic;
	-- Control
		start_init : in std_logic; -- Initial expansion
		start : in std_logic; -- Expansion of the noise bits
		done : out std_logic; 
	-- Data
		sink_data_init : in std_logic_vector(EBITS-1 downto 0);
		sink_data : in std_logic_vector(EBITS-1 downto 0);
		src_data : out std_logic_vector(NBITS-1 downto 0)
	);
end entity fk_noise_reg;

architecture RTL of fk_noise_reg is

	-- Constants 
	constant CNT_BITS : integer := bitlength(NCYC-1);
	constant ROT_BITS : integer := EBITS/NCYC; -- Noise bits in one cycle
	constant IDX_LEN : integer := bitlength(NBITS-1);  -- Encoded length
	constant NCYC_FLIP : integer := (EBITS/IDX_LEN)/NCYC; -- Flips in one cycle
	
	-- FSM
	type state_type is (ST_IDLE, ST_EXP);
	signal state_reg, state_next : state_type;
	
	-- Internal regsiters
	signal noise_reg, noise_next : std_logic_vector(NBITS-1 downto 0);
	signal exp_reg, exp_next : std_logic_vector(EBITS-1 downto 0);
	
	-- Counters and pointers
	signal cnt_reg, cnt_next : unsigned(CNT_BITS-1 downto 0);
	
	-- Internal signals
	signal cmpr_data : std_logic_vector(ROT_BITS-1 downto 0);
	signal uncmpr_data : std_logic_vector(NBITS-1 downto 0);	
	
	-- Status signals
	signal d_cnt : std_logic; 
	
begin
	
	-- Register process
	--
	CR_REG: process (clk, reset_n) is
	begin
		if reset_n = '0' then
			state_reg <= ST_IDLE;
			noise_reg <= (others => '0');
			exp_reg	<= (others => '0');
			cnt_reg	<= to_unsigned(0, CNT_BITS);
		elsif rising_edge(clk) then
			state_reg <= state_next;
			noise_reg <= noise_next;
			exp_reg	<= exp_next;
			cnt_reg	<= cnt_next;
		end if;
	end process CR_REG;
	
	-- Next state logic
	--
	NSL: process (state_reg, start_init, start, d_cnt) is
	begin
		state_next <= state_reg;
		
		case state_reg is
			
			-- IDLE
			-- When start is asserted start expanding the noise bits
			-- from the expansion register.
			when ST_IDLE =>
				if start = '1' or start_init = '1' then
					state_next <= ST_EXP;
				end if;
				
			-- EXP
			-- Wait until the counter counts NCYC signalling the end
			-- of the expansion and return to idle.
			when ST_EXP =>
				if d_cnt = '1' then
					state_next <= ST_IDLE;
				end if;
		
		end case;
	end process NSL;
	
	-- Datapath process
	--
	DP: process (state_reg, noise_reg, exp_reg, cnt_reg,
		d_cnt, sink_data, sink_data_init, uncmpr_data, start_init, start) is
	variable idx : integer;
	begin
		noise_next <= noise_reg;
		exp_next <= exp_reg;
		cnt_next <= cnt_reg;
		
		-- Expand the noise bits.
		case state_reg is
			
			-- When started load expansion register with data from the 
			-- work register and reset the noise register.
			when ST_IDLE =>
				cnt_next <= to_unsigned(0, CNT_BITS);
				if start = '1' then
					exp_next <= sink_data;
					noise_next <= (others => '0');
				elsif start_init = '1' then
					exp_next <= sink_data_init;
					noise_next <= (others => '0');
				end if;
			
			-- If NCYC has passed, end the operation. During the operation and 
			-- during each cycle rotate expansion register and update the 
			-- noise vector with the expanded data(OR operation?).
			when ST_EXP =>
				if d_cnt = '1' then
					cnt_next <= to_unsigned(0, CNT_BITS);
				else
					cnt_next <= cnt_reg + 1;
				end if;
				-- E vector rotation.
				exp_next <= exp_reg(ROT_BITS-1 downto 0) & exp_reg(EBITS-1 downto ROT_BITS);
				-- Noise register update with the uncompressed noise bits.
				noise_next <= noise_reg or uncmpr_data;
		
		end case;
	end process DP;
	
	-- Combinational logic present in the expansion of the noise bits.
	-- Data to be expanded in the current cycle is represented by the lowest
	-- ROT_BITS of the expansion register.
	cmpr_data <= exp_reg(ROT_BITS-1 downto 0);
	DCDR: process (cmpr_data) is
	begin
		uncmpr_data <= (others => '0');
		for i in 0 to NCYC_FLIP-1 loop
			uncmpr_data(to_integer(unsigned(cmpr_data(i*IDX_LEN+IDX_LEN-1 downto i*IDX_LEN)))) <= '1';
		end loop;
	end process DCDR;
	
	-- Status signals
	d_cnt <= '1' when cnt_reg = NCYC-1 else '0';
	
	-- Output
	done <= '1' when state_reg = ST_IDLE else '0';
	src_data <= noise_reg;
	
end architecture RTL;
