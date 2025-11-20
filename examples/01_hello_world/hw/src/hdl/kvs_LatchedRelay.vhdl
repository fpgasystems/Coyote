---------------------------------------------------------------------------
--  Copyright 2015 - 2017 Systems Group, ETH Zurich
-- 
--  This hardware module is free software: you can redistribute it and/or
--  modify it under the terms of the GNU General Public License as published
--  by the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
-- 
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
-- 
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
---------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use IEEE.std_logic_arith.CONV_STD_LOGIC_VECTOR;

-------------------------------------------------------------------------------
-- This is used to provide a buffer between the ready signals of the components
-- connected to input and output. The data line has no delay, it is basically
-- fallthrough.
-------------------------------------------------------------------------------
entity kvs_LatchedRelay is

  generic (
    WIDTH : integer := 16
  );
  port (
    clk      : in std_logic;
    rst      : in std_logic;
    
    in_valid : in std_logic;
    in_ready : out std_logic;
    in_data  : in std_logic_vector (WIDTH-1 downto 0);

    out_valid : out std_logic;
    out_ready : in std_logic;
    out_data  : out std_logic_vector (WIDTH-1 downto 0)
  );
  
  
end kvs_LatchedRelay;

architecture behavioral of kvs_LatchedRelay is

  signal inReady : std_logic;
  
  -- internal buffer
  signal bufData : std_logic_vector (WIDTH-1 downto 0);
  signal bufValid : std_logic;

  -- multiplex the output
  signal useInputLine : std_logic;
  
  signal outValid : std_logic;

begin  -- behavioral

  in_ready <= inReady;
  
  -- output from the buffer if necessary
  out_data <= in_data when useInputLine='1' else bufData;
  outValid <= in_valid when useInputLine='1' else bufValid;
  out_valid <= outValid;

  main: process (clk)
  begin  -- process main
    if clk'event and clk='1' then

      if rst='1' then
        inReady <= '0';
        bufValid <= '0';
        useInputLine <= '0';
      else

        
        inReady <= out_ready or not outValid;

        useInputLine <= out_ready;

        -- latch incoming data
        if (out_ready='0' and inReady='1') or bufValid='0' then
          bufData <= in_data;
          bufValid <= in_valid;
          
          if in_valid ='0' then
            useInputLine <= '1';  
          end if;
        end if;

      end if;      
    end if;
  end process main;

end behavioral;
