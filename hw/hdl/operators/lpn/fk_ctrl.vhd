--*************************************************************************--
--! @file		: fk_ctrl.vhd
--! @project	: Firekite, Dual port RAM implementation
--! 
--! Controller unit
--! 
--! @date		: 10.10.2017.
--*************************************************************************--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fk_ctrl is
	generic(
		NBITS : integer := 4096; -- Length of the basis vector in bits
		DBITS : integer := 2816 -- Data set length in bits
	);
	port(
		clk : in std_logic;
		reset_n	: in std_logic;
	-- Control DP
		dp_key_ld_init : out std_logic;
		dp_key_ld_v_init : out std_logic;
		dp_key_ld_v : out std_logic;
		dp_key_start : out std_logic; 
		dp_key_done : in std_logic;
		dp_ld_data : out std_logic;
		dp_wr_data : out std_logic;
		dp_rd_data : out std_logic;
		dp_rst_pntr : out std_logic;
		dp_ld_work : out std_logic;
		dp_wr_work : out std_logic;
		dp_rst_work : out std_logic;
		dp_start_init_exp : out std_logic;
		dp_start_exp : out std_logic;
		dp_done_exp	: in std_logic; 
	-- Avalon slave
		avs_start : in std_logic; 
		avs_len : in std_logic_vector(15 downto 0); 
		avs_src	: in std_logic_vector(31 downto 0);
		avs_dest : in std_logic_vector(31 downto 0);
		avs_mode : in std_logic_vector(1 downto 0); 
		avs_done : out std_logic; 
		avs_doneIrq : out std_logic; 
	-- Avalon master Read
		avm_rd_start : out std_logic; 
		avm_rd_src : out std_logic_vector(31 downto 0);
		avm_rd_len	: out std_logic_vector(9 downto 0); 
		avm_rd_dVal : in std_logic;
		avm_rd_done : in std_logic; 
	-- Avalon master Write
		avm_wr_start : out std_logic;
		avm_wr_dest : out std_logic_vector(31 downto 0);
		avm_wr_len : out std_logic_vector(9 downto 0);
		avm_wr_dVal : in std_logic;
		avm_wr_done : in std_logic
	);
end entity fk_ctrl;

architecture RTL of fk_ctrl is
	
	-- Constants
	constant INIT_BYTES	: integer := NBITS/8;
	constant DATA_BYTES	: integer := DBITS/8; 
	
	-- FSM
	type state_type is (ST_IDLE, 
						ST_KEY_FETCH, ST_KEY_STORE,
						ST_INITV_FETCH, ST_INITV_STORE, ST_INITV_EXP,
						ST_OPER_FETCH, ST_OPER_EXEC, ST_OPER_STORE, 
						ST_OPER_STORE_AND_FETCH);
	signal state_reg, state_next : state_type;
	
	-- Internal registers
	signal sadd_reg, sadd_next : std_logic_vector(31 downto 0);
	signal dadd_reg, dadd_next : std_logic_vector(31 downto 0);
	signal slen_reg, slen_next : std_logic_vector(15 downto 0);
	signal dlen_reg, dlen_next : std_logic_vector(15 downto 0);
	signal d_reg, d_next : std_logic; 
	
	-- Status signals
	signal d_oper : std_logic; 
	
begin
	
	-- Register process 
	--
	CR_REG: process (clk, reset_n) is
	begin
		if reset_n = '0' then
			state_reg <= ST_IDLE;
			sadd_reg <= (others => '0');
			dadd_reg <= (others => '0');
			slen_reg <= (others => '0');
			dlen_reg <= (others => '0');
			d_reg <= '0';
		elsif rising_edge(clk) then
			state_reg <= state_next;
			sadd_reg <= sadd_next;
			dadd_reg <= dadd_next;
			slen_reg <= slen_next;
			dlen_reg <= dlen_next;
			d_reg <= d_next;
		end if;
	end process CR_REG;
	
	-- Next state logic
	--
	NSL: process (state_reg, 
		avs_start, avs_mode, avm_rd_done, avm_wr_done, dp_done_exp, dp_key_done, d_oper) is
	begin
		state_next <= state_reg;
		
		case state_reg is
			
			-- IDLE
			-- When start is asserted by the slave the state changes to either
			-- fetching the base key, fetching the initial vector or 
			-- starting the operation. Mode signal determines which of 
			-- these will materialise.
			when ST_IDLE =>
				if avs_start = '1'then
					case avs_mode is
						when "00" =>
							state_next <= ST_KEY_FETCH;
						when "01" =>
							state_next <= ST_INITV_FETCH;
						when "10" =>
							state_next <= ST_OPER_FETCH;
						when others => null;
					end case;
				end if;
				
			-- KEY FETCH
			-- If DMA is done fetching the base key, the base key can be
			-- stored in the key register.
			when ST_KEY_FETCH =>
				if avm_rd_done = '1' then
					state_next <= ST_KEY_STORE;
				end if;
				
			-- KEY STORE
			-- Store the fetched key in the key register.
			when ST_KEY_STORE =>
				state_next <= ST_IDLE;
			
			-- INITV_FETCH
			-- If DMA is done fetching the init vector, the V vector can
			-- be stored and the expansion of the noise bits can be started.
			when ST_INITV_FETCH =>
				if avm_rd_done = '1' then
					state_next <= ST_INITV_STORE;
				end if;
			
			-- INITV_STORE
			-- Store V vector and start the expansion of the noise bits.
			when ST_INITV_STORE =>
				state_next <= ST_INITV_EXP;
			
			-- INITV_EXP
			-- Check whether the expansion of the noise bits is done.
			when ST_INITV_EXP =>
				if dp_done_exp = '1' then
					state_next <= ST_IDLE;
				end if;
			
			-- OPER FETCH
			-- Check whether the data has been fetched and whether
			-- the work vector has been updated.
			when ST_OPER_FETCH =>
				if avm_rd_done = '1' and dp_key_done = '1' then
					state_next <= ST_OPER_EXEC;
				end if;
			
			-- OPER EXEC
			-- XOR the fetched data with the work vector.
			when ST_OPER_EXEC =>
				if d_oper = '1' then
					state_next <= ST_OPER_STORE;
				else
					state_next <= ST_OPER_STORE_AND_FETCH;
				end if;
			
			-- OPER STORE
			-- Final state.
			when ST_OPER_STORE =>
				if avm_wr_done = '1' then
					state_next <= ST_IDLE;
				end if;
			
			-- OPER STORE AND FETCH
			-- Store and fetch at the same time. While doing that
			-- also expand the noise bits and update work vector. 
			-- In short parallelize everything.
			when ST_OPER_STORE_AND_FETCH =>
				if avm_rd_done = '1' and avm_wr_done = '1' and
				   dp_key_done = '1' and dp_done_exp = '1' then
					state_next <= ST_OPER_EXEC;
				end if;
				
		end case;
	end process NSL;
	
	-- Datapath process
	--
	DP: process (state_reg, sadd_reg, dadd_reg, slen_reg, dlen_reg, d_reg,
		avs_start, avs_src, avs_dest, avs_mode, avs_len, 
		dp_done_exp, avm_rd_done, avm_wr_done, d_oper, dp_key_done, 
		avm_rd_dVal, avm_wr_dVal) is
	begin
		sadd_next <= sadd_reg;
		dadd_next <= dadd_reg;
		slen_next <= slen_reg;
		dlen_next <= dlen_reg;
		d_next <= '0';
		
		dp_key_start <= '0';
		dp_start_exp <= '0';
		dp_rst_work <= '0';
		dp_rst_pntr <= '0';
		dp_rd_data <= '0';
		dp_wr_data <= '0';
		dp_ld_work <= '0';
		avm_rd_start <= '0';
		avm_rd_src <= (others => '0');
		avm_rd_len <= (others => '0');
		avm_wr_start <= '0';
		avm_wr_dest <= (others => '0');
		avm_wr_len <= (others => '0');
		
		case state_reg is 
			
			-- Latch the length, destination and source when started.
			when ST_IDLE =>
				dp_rst_pntr <= '1';
				dp_rst_work <= '1';
				if avs_start = '1' then	
					avm_rd_start <= '1';
					avm_rd_src <= avs_src;
					case avs_mode is
						when "00" | "01" =>
							avm_rd_len <= std_logic_vector(to_unsigned(INIT_BYTES, 10));
						when "10" =>
							dp_key_start <= '1';
							sadd_next <= std_logic_vector(unsigned(avs_src) + to_unsigned(DATA_BYTES, 32));
							dadd_next <= avs_dest;
							slen_next <= std_logic_vector(unsigned(avs_len) - to_unsigned(DATA_BYTES, 16));
							dlen_next <= avs_len;
							if unsigned(avs_len) > to_unsigned(DATA_BYTES, 16) then
								avm_rd_len <= std_logic_vector(to_unsigned(DATA_BYTES, 10)); 
							else
								avm_rd_len <= avs_len(9 downto 0);
							end if;
						when others => null;
					end case;
				end if;
			
			-- Signal to the Avalon slave that the operation is done.
			when ST_KEY_STORE =>
				d_next <= '1';
			
			-- Signal to the Avalon slave that the operation is done.
			when ST_INITV_EXP =>
				if dp_done_exp = '1' then
					d_next <= '1';
				end if;
			
			-- Control the work vector and the serial write of
			-- the data input register.
			when ST_OPER_FETCH =>
				if avm_rd_done /= '1' then
					dp_wr_data <= avm_rd_dVal;
				end if;
				if dp_key_done /= '1' then
					dp_ld_work <= '1';
				end if;
			
			-- Prepare the Write DMA for memory Write sequence.
			-- If operation is not done start fetching data, 
			-- epxanding noise bits and updating key vector in 
			-- parallel.
			when ST_OPER_EXEC =>
				dp_rst_pntr <= '1';
				dp_rst_work <= '1';
				avm_wr_start <= '1';
				avm_wr_dest <= dadd_reg;
				dadd_next <= std_logic_vector(unsigned(dadd_reg) + to_unsigned(DATA_BYTES, 32));
				if d_oper = '1' then
					avm_wr_len <= dlen_reg(9 downto 0);
					dlen_next <= (others => '0');
				else
					avm_wr_len <= std_logic_vector(to_unsigned(DATA_BYTES, 10)); 
					slen_next <= std_logic_vector(unsigned(slen_reg) - to_unsigned(DATA_BYTES, 16));
					dlen_next <= slen_reg;
					dp_key_start <= '1';
					dp_start_exp <= '1';
					avm_rd_start <= '1';
					avm_rd_src <= sadd_reg;
					sadd_next <= std_logic_vector(unsigned(sadd_reg) + to_unsigned(DATA_BYTES, 32));				
					if unsigned(slen_reg) > to_unsigned(DATA_BYTES, 16) then
						avm_rd_len <= std_logic_vector(to_unsigned(DATA_BYTES, 10));
					else
						avm_rd_len <= slen_reg(9 downto 0);
					end if;
				end if;
			
			-- Store the data. If DMA Write is done signal the 
			-- end of operation.
			when ST_OPER_STORE =>
				if avm_wr_done = '1' then
					d_next <= '1';
				else
					dp_rd_data <= avm_wr_dVal;
				end if;
			
			-- Control serial write, read, and the work 
			-- vector update.
			when ST_OPER_STORE_AND_FETCH =>
				if avm_wr_done /= '1' then
					dp_rd_data <= avm_wr_dVal;
				end if;
				if avm_rd_done /= '1' then
					dp_wr_data <= avm_rd_dVal;
				end if;
				if dp_key_done /= '1' then
					dp_ld_work <= '1';
				end if;
			
			when others => null;	
			
		end case;
	end process DP;
	
	-- Status signals
	d_oper <= '1' when unsigned(dlen_reg) <= to_unsigned(DATA_BYTES, 16)  else '0';
	
	-- Output
	dp_key_ld_init <= '1' when state_reg = ST_KEY_STORE else '0';
	dp_key_ld_v_init <= '1' when state_reg = ST_INITV_STORE else '0';
	dp_key_ld_v <= '1' when state_reg = ST_OPER_EXEC else '0';
	
	dp_ld_data <= '1' when state_reg = ST_OPER_EXEC	else '0';

	dp_wr_work <= avm_rd_dVal when state_reg = ST_KEY_FETCH or state_reg = ST_INITV_FETCH else '0';
	
	dp_start_init_exp <= '1' when state_reg = ST_INITV_STORE else '0';
	 
	avs_done <= '1' when state_reg = ST_IDLE else '0';
	avs_doneIrq <= d_reg;
					   
end architecture RTL;
