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

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
entity bram_gen is
  generic (
    DATA_WIDTH   : integer := 16;
    ADDRESS_WIDTH : integer := 8
           );
  port (clk : in std_logic;
        we : in std_logic;
        a : in std_logic_vector(ADDRESS_WIDTH-1 downto 0);
        dpra : in std_logic_vector(ADDRESS_WIDTH-1 downto 0);
        di : in std_logic_vector(DATA_WIDTH-1 downto 0);
        spo : out std_logic_vector(DATA_WIDTH-1 downto 0);
        dpo : out std_logic_vector(DATA_WIDTH-1 downto 0)
        );
end bram_gen;
architecture syn of bram_gen is
  type ram_type is array (2**ADDRESS_WIDTH-1 downto 0)
    of std_logic_vector (DATA_WIDTH-1 downto 0);
  signal RAM : ram_type := (others => (others => '0'));
  signal read_a : std_logic_vector(ADDRESS_WIDTH-1 downto 0);
  signal read_dpra : std_logic_vector(ADDRESS_WIDTH-1 downto 0);
begin
  process (clk)
  begin
    if (clk'event and clk = '1') then
      if (we = '1') then
        RAM(conv_integer(a)) <= di;
      end if;
      read_a <= a;
      read_dpra <= dpra;
    end if;
  end process;
  spo <= RAM(conv_integer(read_a));
  dpo <= RAM(conv_integer(read_dpra));
end syn;
