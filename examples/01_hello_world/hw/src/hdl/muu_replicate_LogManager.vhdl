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

LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL ;
USE IEEE.std_logic_arith.ALL;
use IEEE.std_logic_unsigned.all;

entity muu_replicate_LogManager is
  generic (
    LOC_ADDR_WIDTH : integer := 7;
    USER_BITS : integer := 3
  );
  port (
    clk         : in std_logic;
    rst         : in std_logic;

    log_add_valid : in std_logic;
    log_add_zxid : in std_logic_vector(31 downto 0);    
    log_add_user : in std_logic_vector(USER_BITS-1 downto 0);
    log_add_key  : in std_logic_vector(63 downto 0);

    log_search_valid : in std_logic;
    log_search_since : in std_logic;
    log_search_user  : in std_logic_vector(USER_BITS-1 downto 0);
    log_search_zxid : in std_logic_vector(31 downto 0);
    
    log_found_valid : out std_logic;
    log_found_key : out std_logic_vector(63 downto 0)
  );
end muu_replicate_LogManager;

architecture beh of muu_replicate_LogManager is

  type DataArray is array(2**(USER_BITS+LOC_ADDR_WIDTH)-1 downto 0) of std_logic_vector(63 downto 0);

  signal LogKeys : DataArray;
  signal logSizes : DataArray;  
  signal logHeadLocation : std_logic_vector(63 downto 0);
  signal lookupOn : std_logic;
  signal lookupAddr : std_logic_vector(USER_BITS+LOC_ADDR_WIDTH-1 downto 0);
  
begin

  main : process(clk)
  begin
    if (Clk'event and clk='1') then
      if (rst='1') then
	logHeadLocation <= (others => '0');

	log_found_valid <= '0';
	lookupOn <= '0';
      else

	log_found_valid <= '0';
	
	if (log_add_valid='1') then
	  LogKeys(conv_integer(log_add_user & log_add_zxid(LOC_ADDR_WIDTH-1 downto 0))) <= log_add_key;

	end if;

	if (log_search_valid='1') then	  
	  lookupOn <= '1';
	  lookupAddr <= log_search_user & log_search_zxid(LOC_ADDR_WIDTH-1 downto 0);
	end if;
	
	if (lookupOn='1') then 
	  lookupOn <= '0';
	  log_found_valid <= '1';
	  log_found_key <= LogKeys(conv_integer(lookupAddr));

	end if;

	
      end if;
    end if;
  end process;
  
end beh;
