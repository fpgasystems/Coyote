--*************************************************************************--
--! @file		: fk_key_reg.vhd
--! @project	: Firekite, Dual port RAM implementation.
--! 
--! Key register. Rotating key implementation.
--! 
--! @date		: 10.10.2017.
--*************************************************************************--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.utils.all;

entity fk_key_reg is
	generic(
		NBITS : integer := 4096; -- Length of the basis vector
		VBITS : integer := 512; -- Length of the V vector
		NCYC : integer := 32 -- Number of cycles needed for update
	);
	port(
		clk	: in std_logic;
		reset_n	: in std_logic;
	-- Control
		ld_key_init : in std_logic; -- Load parallel reg.
		ld_v_init : in std_logic;
		ld_v : in std_logic; 
		start : in std_logic;  -- Start the update of the work vctr
		done : out std_logic;
	-- Data
		sink_data_init : in std_logic_vector(NBITS-1 downto 0);
		sink_data : in std_logic_vector(VBITS-1 downto 0);  
		src_data : out std_logic_vector(NBITS-1 downto 0) 
	);
end entity fk_key_reg;

architecture RTL of fk_key_reg is
	
	-- Constants
	constant CNT_BITS : integer := bitlength(NCYC-1); 
	constant ROT_BITS : integer := VBITS/NCYC; -- Keys updated in one cycle
	
	-- FSM
	type state_type is (ST_IDLE, ST_OPER);
	signal state_reg, state_next : state_type;
	
	-- Internal regsiters
	signal key_reg, key_next : std_logic_vector(NBITS-1 downto 0); 
	signal v_reg, v_next : std_logic_vector(VBITS-1 downto 0);
	
	-- Counters
	signal cnt_reg, cnt_next : unsigned(CNT_BITS-1 downto 0); 
	
	-- Types
	type key_array_s0 is array (ROT_BITS-1 downto 0) of std_logic_vector(NBITS-1 downto 0); 
	
	-- Internal signals
	signal key_data	: key_array_s0; 
	signal key_data_s0 : key_array_s0;
	signal v_curr : std_logic_vector(ROT_BITS-1 downto 0);
	
	-- Status signals
	signal d_cnt : std_logic;
	
begin
	
	-- Register process
	--
	CR_REG: process (clk, reset_n) is
	begin
		if reset_n = '0' then
			state_reg <= ST_IDLE;
			cnt_reg	<= to_unsigned(0, CNT_BITS);
			key_reg	<= (others => '0');
			v_reg <= (others => '0');
		elsif rising_edge(clk) then
			state_reg <= state_next;
			cnt_reg <= cnt_next;
			key_reg	<= key_next;
			v_reg <= v_next;			
		end if;
	end process CR_REG;
	
	-- Next state logic
	--
	NSL: process (state_reg, start, d_cnt) is
	begin
		state_next <= state_reg;
		
		case state_reg is
			
			-- IDLE
			-- When start is asserted, start updating the work vector.
			when ST_IDLE =>
				if start = '1' then
					state_next <= ST_OPER;
				end if;
			
			-- OPER
			-- If NCYC has passed return to idle. Work vector updated.
			when ST_OPER =>
				if d_cnt = '1' then
					state_next <= ST_IDLE;
				end if;
		
		end case;		
	end process NSL;
	
	-- Datapath process
	--
	DP: process (state_reg, cnt_reg, key_reg, v_reg, ld_key_init, 
		ld_v_init, ld_v, d_cnt, sink_data, sink_data_init) is
	begin
		cnt_next <= cnt_reg;
		key_next <= key_reg;
		v_next <= v_reg;
		
		-- Load key parallel. During the initial key storage.
		if ld_key_init = '1' then
			key_next <= sink_data_init;
		end if;	
		
		-- Load v parallel during the initial init vector storage.
		if ld_v_init = '1' then
			v_next <= sink_data_init(VBITS-1 downto 0);
		end if;
		
		-- Load v vector parallel.
		if ld_v = '1' then
			v_next <= sink_data;
		end if;
		
		-- Updating of the working vector.
		case state_reg is
			
			-- Counter reset.
			when ST_IDLE =>
				cnt_next <= to_unsigned(0, CNT_BITS);
			
			-- If NCYC has passed end the operation. During the operation and 
			-- during each cycle rotate the base key and V vectors.
			when ST_OPER =>
				if d_cnt = '1' then
					cnt_next <= to_unsigned(0, CNT_BITS);
				else
					cnt_next <= cnt_reg + 1;
				end if;
				-- Key rotation 
				for i in 0 to NBITS/VBITS-1 loop
					key_next(i*VBITS+VBITS-1 downto i*VBITS) <=
						key_reg(i*VBITS+VBITS-1-ROT_BITS downto i*VBITS) &
						key_reg(i*VBITS+VBITS-1 downto i*VBITS+VBITS-ROT_BITS);
				end loop;
				-- V rotation
				v_next <= v_reg(ROT_BITS-1 downto 0) & v_reg(VBITS-1 downto ROT_BITS);
		
		end case;		
	end process DP;
	
	-- Combinational logic. Keys derived from the base key by pure
	-- wiring.
	PS0: process (key_reg) is
	begin
		for i in 1 to ROT_BITS-1 loop
			for j in 0 to NBITS/VBITS-1 loop
				key_data(i)(j*VBITS+VBITS-1 downto j*VBITS) <=
					key_reg(j*VBITS+VBITS-1-i downto j*VBITS) &
					key_reg(j*VBITS+VBITS-1 downto j*VBITS+VBITS-i);
			end loop;
		end loop;
		key_data(0) <= key_reg;  
	end process PS0;
	
	-- Multiplication of the generated keys with the lowest 
	-- ROT_BITS of the V vector.
	v_curr <= v_reg(ROT_BITS-1 downto 0);
	PS0M: process (key_data, v_curr) is
	begin
		for i in 0 to ROT_BITS-1 loop
			if v_curr(i) = '1' then
				key_data_s0(i) <= key_data(i);		
			else
				key_data_s0(i) <= (others => '0');
			end if;
		end loop;
	end process PS0M;
	
	-- Generation of the current update vector by XOR-ing all
	-- generated intermediate keys.
	PS1: process (key_data_s0) is
	variable tmp : std_logic_vector(NBITS-1 downto 0);
	begin
		tmp := (others => '0');
		for i in 0 to ROT_BITS-1 loop
			tmp := tmp xor key_data_s0(i);
		end loop;
		src_data <= tmp;
	end process PS1;
	
	-- Status signals
	d_cnt <= '1' when cnt_reg = NCYC-1 else '0';
	
	-- Output
	done <= '1' when state_reg = ST_IDLE else '0';
	
end architecture RTL;
