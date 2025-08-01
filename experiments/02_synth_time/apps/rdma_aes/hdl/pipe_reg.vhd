library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pipe_reg is
    generic(
    	DATA_WIDTH : integer := 128
    );
	port(
		clk      : in  std_logic;
		reset_n  : in  std_logic;
		stall    : in  std_logic;
		last_in  : in  std_logic;
		last_out : out std_logic;
		keep_in  : in  std_logic_vector(DATA_WIDTH/8-1 downto 0);
		keep_out : out std_logic_vector(DATA_WIDTH/8-1 downto 0);
		dVal_in  : in  std_logic; -- Data valid signal
		dVal_out : out std_logic;
		data_in  : in  std_logic_vector(DATA_WIDTH-1 downto 0); 
		data_out : out std_logic_vector(DATA_WIDTH-1 downto 0)
	);
end entity pipe_reg;

architecture RTL of pipe_reg is
	
	-- Internal registers
	signal dVal_reg : std_logic;
	signal last_reg : std_logic;
	signal keep_reg : std_logic_vector(DATA_WIDTH/8-1 downto 0);
	signal data_reg : std_logic_vector(DATA_WIDTH-1 downto 0);

begin
	
	-- Register process
	--
	CR_REG: process (clk, reset_n) is
	begin
         if rising_edge(clk) then
             if reset_n = '0' then
               dVal_reg <= '0';
               last_reg <= '0';
               keep_reg <= (others => '0');
               data_reg <= (others => '0');
             else  --if rising_edge(clk) then
                 if stall = '0' then
                    dVal_reg <= '0';
                    if dVal_in = '1' then
                       dVal_reg <= '1';
                       last_reg <= last_in;
                       keep_reg <= keep_in;
                       data_reg <= data_in;
                    end if;
                 end if;

             end if;
         end if; 
         
	end process CR_REG;
	
	-- Output
	dVal_out <= dVal_reg;
	last_out <= last_reg;
	keep_out <= keep_reg;
	data_out <= data_reg;
	
end architecture RTL;