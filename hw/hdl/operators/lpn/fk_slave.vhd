--*************************************************************************--
--! @file		: fk_slave.vhd
--! @project	: Firekite, Dual port RAM implementation.
--! 
--! Avalon slave. 6 Interface registers. 
--! 
--! @date		: 10.10.2017.
--*************************************************************************--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fk_slave is
	port (
		clk	: in std_logic;
		reset_n	: in std_logic;
	-- Avalon slave
		avs_Address : in std_logic_vector(2 downto 0); 
		avs_ChipSelect : in std_logic; 
		avs_Read : in std_logic; 
		avs_Write : in std_logic; 
		avs_WriteData : in std_logic_vector(31 downto 0); 
		avs_ReadData : out std_logic_vector(31 downto 0); 
	-- Control
		start : out std_logic; 
		len : out std_logic_vector(15 downto 0); 
		src	: out std_logic_vector(31 downto 0); 
		dest : out std_logic_vector(31 downto 0); 
		mode : out std_logic_vector(1 downto 0); 
		done : in  std_logic; 
		doneIrq	: in  std_logic;
	-- Irq
		irq : out std_logic 
	);
end entity fk_slave;

architecture rtl of fk_slave is
	
	-- Internal interface registers
	signal ireg_command : std_logic_vector(3 downto 0); 
	signal ireg_src : std_logic_vector(31 downto 0); 
	signal ireg_dest : std_logic_vector(31 downto 0); 
	signal ireg_len	: std_logic_vector(15 downto 0); 
	signal ireg_status : std_logic_vector(4 downto 0); 
	signal ireg_irqP : std_logic; 
	
	-- Internal signals
	signal irqEn : std_logic; 
			
begin
	
	-- Write Avalon slave
	--
	WR_CR_REG : process (clk, reset_n) is
	begin
		if reset_n = '0' then
			ireg_command <= (others => '0');
			ireg_src <= (others => '0');
			ireg_dest <= (others => '0');
			ireg_len <= (others => '0');
			ireg_irqP <= '0';
		elsif rising_edge(clk) then
			ireg_command(0) <= '0';
			if doneIrq = '1' then
				ireg_irqP <= '1';
			end if;
			if avs_chipSelect = '1' and avs_write = '1' then
				case avs_address is
					-- Command 
					when "000" =>
						ireg_command <= avs_writeData(3 downto 0);
					-- Source address
					when "001" =>
						ireg_src <= avs_writeData(31 downto 0);	
					-- Destination address
					when "010" =>
						ireg_dest <= avs_writeData(31 downto 0);
					-- Data length
					when "011" =>
						ireg_len <= avs_writeData(15 downto 0);
					-- Clear IRQ
					when "100" =>
						if avs_writeData(0) = '1' then
							ireg_irqP <= '0';
						end if;
					when others => null;
				end case;
			end if;
		end if;	
	end process WR_CR_REG;
	
	-- Read Avalon slave
	--
	RD_C_REG : process (clk) is
	begin
		if rising_edge(clk) then
			if avs_chipSelect = '1' and avs_read = '1' then
				avs_readData <= (others => '0');
				case avs_address is
					-- Command
					when "000" => avs_readData(3 downto 0) <= ireg_command;
					-- Source address
					when "001" => avs_readData(31 downto 0) <= ireg_src;
					-- Destination address
					when "010" => avs_readData(31 downto 0) <= ireg_dest;
					-- Length of the data
					when "011" => avs_readData(15 downto 0) <= ireg_len;
					-- Status
					when "101" => avs_readData(4 downto 0) <= ireg_status;
					when others => null;
				end case;
			end if;
		end if;
	end process RD_C_REG;
	
	-- Datapath
	ireg_status(2 downto 0) <= ireg_command(3 downto 1);
	ireg_status(3) <= ireg_irqP;
	ireg_status(4) <= done;
	irqEn <= ireg_command(1);
	
	-- Output
	start <= ireg_command(0);
	src	<= ireg_src;
	dest <= ireg_dest;
	len	<= ireg_len;
	mode <= ireg_command(3 downto 2);
	
	-- Irq
	irq	<= '1' when ireg_irqP = '1' and irqEn = '1' else '0';
		
end architecture rtl;
