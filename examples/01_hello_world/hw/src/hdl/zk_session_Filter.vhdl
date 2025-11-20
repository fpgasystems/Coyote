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
USE IEEE.std_logic_unsigned.ALL;
USE IEEE.STD_LOGIC_TEXTIO.all;

LIBRARY STD;
USE STD.TEXTIO.ALL;
-------------------------------------------------------------------------------
-- This module is used to filter the input to the hash-table pipeline.
-- It acts as FIFO with a lookup, where the 'find' input is matched to all
-- elements in the queue.
-- The idea is that every write operation is pushed into the filter when
-- entering the pipeline, and popped when the memroy was written.
-- Read operations just need to be checked for address conflicts with the
-- writes, but need  not be stored inside the filter .
-------------------------------------------------------------------------------
entity zk_session_Filter is

  generic (
    CONCURRENT_ADDR : integer := 8;
    ADDR_WIDTH : integer := 16
    );

  port (
    clk         : in std_logic;
    rst         : in std_logic;

    -- push in a new address. Only addresses not inside should pe pushed.
    push_valid  : in std_logic;
    push_addr   : in std_logic_vector(ADDR_WIDTH-1 downto 0);

    -- the probe interface. Use it to check if an address is inside
    find_loc    : out std_logic_vector(CONCURRENT_ADDR-1 downto 0);    

    -- pop the oldest address.
    pop_valid : in std_logic;
    pop_loc: in std_logic_vector(CONCURRENT_ADDR-1 downto 0)
    );
  
end zk_session_Filter;

architecture beh of zk_session_Filter is

  type StackType  is array(CONCURRENT_ADDR-1 downto 0) of std_logic_vector(ADDR_WIDTH-1 downto 0);

  signal stack : StackType;
  signal match : std_logic_vector(CONCURRENT_ADDR-1 downto 0);
  signal empty : std_logic_vector(CONCURRENT_ADDR-1 downto 0);

  signal findAddr : std_logic_vector(ADDR_WIDTH-1 downto 0);
  
  signal tryPush : std_logic := '0';
  signal waiting : std_logic;

begin  -- beh

  find_loc <= match;
  
  comparison: process (clk)
  begin
    -- the probe input is checked in parallel with other operations
    if (clk'event and clk='1') then
      if (rst='1') then	
	waiting <= '0';
      else

	match <= (others => '0');
	
	if (push_valid='1') then
	  
	  findAddr <= push_addr;		

	  for X in 0 to CONCURRENT_ADDR-1 loop
	    if push_addr=stack(X) then
	      match(X) <= '1';
	    else
	      match(X) <= '0';
	    end if;

	    --if (not stack(X))=0 then
	    --  empty(X) <= '1';
	    --end if;
	    
	  end loop;  -- X
	  
	else
	  
	  for X in 0 to CONCURRENT_ADDR-1 loop
	    if findAddr=stack(X) then
	      match(X) <= '1';
	    else
	      match(X) <= '0';
	    end if;
	  end loop;  -- X	  
	end if;
	
      end if;
    end if;
  end process comparison;

  main: process (clk)
    variable pos : integer;
  begin  -- process main

    if (clk='1' and clk'event) then
      if rst='1' then
	
	tryPush <= '0';
	
        -- the queue is empty
        for X in 0 to CONCURRENT_ADDR-1 loop
	  stack(X) <= (others => '1');
	  empty(X) <= '1';
        end loop;
      else

	-- DELETE
	for X in 0 to CONCURRENT_ADDR-1 loop
	  
	  if (pop_valid='1' and pop_loc(X)='1') then
	    stack(X) <= (others => '1');
	    empty(X) <= '1';
	  end if;
	  
	end loop;	


	-- PUSH
	if (tryPush='0') then
	  tryPush <= push_valid;
	end if;

	if (tryPush='1' and match>0) then
	  tryPush <= '0';
	end if;

	if (tryPush='1' and match=0 and empty/=0) then
	  for X in CONCURRENT_ADDR-1 downto 0 loop
	    if (empty(X)='1') then
	      pos := X;
	    end if;	    
	  end loop;

	  stack(pos) <= findAddr;
	  empty(pos) <= '0';

	  tryPush <= '0';
	end if;	

      end if;
    end if;
    
  end process main;
  
end beh;
