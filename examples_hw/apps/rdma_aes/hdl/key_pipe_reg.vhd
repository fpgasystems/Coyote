library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity key_pipe_reg is
    generic(
        KEY_WIDTH : integer := 128
    );
    port(
        clk      : in  std_logic;
        reset_n  : in  std_logic;
        dVal_in  : in  std_logic; -- Data valid signal
        dVal_out : out std_logic;
        data_in  : in  std_logic_vector(KEY_WIDTH-1 downto 0); 
        data_out : out std_logic_vector(KEY_WIDTH-1 downto 0)
    );
end entity key_pipe_reg;

architecture RTL of key_pipe_reg is
    
    -- Internal registers
    signal dVal_reg : std_logic;
    signal data_reg : std_logic_vector(KEY_WIDTH-1 downto 0);

begin
    
    -- Register process
    --
    CR_REG: process (clk, reset_n) is
    begin
      if rising_edge(clk) then
         if reset_n = '0' then
            dVal_reg <= '0';
            data_reg <= (others => '0');
         else
            dVal_reg <= '0';
            if dVal_in = '1' then
                dVal_reg <= '1';
                data_reg <= data_in;
            end if;
         end if;
     end if;     
    
    end process CR_REG;
    
    -- Output
    dVal_out <= dVal_reg;
    data_out <= data_reg;
    
end architecture RTL;