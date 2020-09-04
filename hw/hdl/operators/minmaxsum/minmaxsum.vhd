library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity minmaxsum is
port (
  clk : in std_logic;
  rst_n : in std_logic;

  clr : in std_logic;
  done : out std_logic;

  min_out : out std_logic_vector(31 downto 0);
  max_out : out std_logic_vector(31 downto 0);
  sum_out : out std_logic_vector(31 downto 0);
  
  axis_in_tvalid : in std_logic;
  axis_in_tdata : in std_logic_vector(511 downto 0);
  axis_in_tlast : in std_logic
);
end minmaxsum;

architecture behavioral of minmaxsum is

type CLIntegersType is array (15 downto 0) of signed(31 downto 0);
signal CLIntegers : CLIntegersType;

type OddEvenSortIntegersType is array(1 to 16) of CLIntegersType;
signal OddEvenSortIntegers : OddEvenSortIntegersType;
signal sortingSteps : std_logic_vector(1 to 16);
signal lastSteps : std_logic_vector(1 to 16);

signal minimum : signed(31 downto 0);
signal maximum : signed(31 downto 0);
signal summation : signed(31 downto 0);

begin

-- Generate input data
gen_CLIntegers: for i in 0 to 15 generate
  CLIntegers(i) <= signed(axis_in_tdata(i*32+31 downto i*32));
end generate gen_CLIntegers;

min_out <= std_logic_vector(minimum);
max_out <= std_logic_vector(maximum);
sum_out <= std_logic_vector(summation);

process(clk)
begin
if clk'event and clk = '1' then
  if rst_n = '0' then
    minimum <= X"7FFFFFFF";
    maximum <= X"80000000";
    summation <= (others => '0');

    done <= '0';
  else
    done <= '0';

    if clr = '1' then 
      minimum <= X"7FFFFFFF";
      maximum <= X"80000000";
      summation <= (others => '0');
    end if;

    -- Read CLs
    sortingSteps(1) <= axis_in_tvalid;
    lastSteps(1) <= axis_in_tlast;
    for j in 1 to 15 loop
      sortingSteps(j+1) <= sortingSteps(j);
      lastSteps(j+1) <= lastSteps(j);
    end loop;

    -- 1. Cycle
    for i in 0 to 7 loop
      if CLIntegers(2*i) > CLIntegers(2*i+1) then
        OddEvenSortIntegers(1)(2*i) <= CLIntegers(2*i+1); OddEvenSortIntegers(1)(2*i+1) <= CLIntegers(2*i);
      else
        OddEvenSortIntegers(1)(2*i) <= CLIntegers(2*i); OddEvenSortIntegers(1)(2*i+1) <= CLIntegers(2*i+1);
      end if;
    end loop;

    -- 3.5.7.9.11.13.15. Cycle
    for j in 1 to 7 loop
      for i in 0 to 7 loop
        if OddEvenSortIntegers(2*j)(2*i) > OddEvenSortIntegers(2*j)(2*i+1) then
          OddEvenSortIntegers(2*j+1)(2*i) <= OddEvenSortIntegers(2*j)(2*i+1); OddEvenSortIntegers(2*j+1)(2*i+1) <= OddEvenSortIntegers(2*j)(2*i);
        else
          OddEvenSortIntegers(2*j+1)(2*i) <= OddEvenSortIntegers(2*j)(2*i); OddEvenSortIntegers(2*j+1)(2*i+1) <= OddEvenSortIntegers(2*j)(2*i+1);
        end if;
      end loop;
    end loop;

    -- 2.4.6.8.10.12.14.16. Cycle
    for j in 1 to 8 loop
      OddEvenSortIntegers(2*j)(0) <= OddEvenSortIntegers(2*j-1)(0);
      OddEvenSortIntegers(2*j)(15) <= OddEvenSortIntegers(2*j-1)(15);
      for i in 1 to 7 loop
        if OddEvenSortIntegers(2*j-1)(2*i-1) > OddEvenSortIntegers(2*j-1)(2*i) then
          OddEvenSortIntegers(2*j)(2*i-1) <= OddEvenSortIntegers(2*j-1)(2*i); OddEvenSortIntegers(2*j)(2*i) <= OddEvenSortIntegers(2*j-1)(2*i-1);
        else
          OddEvenSortIntegers(2*j)(2*i-1) <= OddEvenSortIntegers(2*j-1)(2*i-1); OddEvenSortIntegers(2*j)(2*i) <= OddEvenSortIntegers(2*j-1)(2*i);
        end if;
      end loop;
    end loop;

    -- Results
    if sortingSteps(16) = '1' then
      if OddEvenSortIntegers(16)(0) < minimum then
        minimum <= OddEvenSortIntegers(16)(0);
      end if;
      if OddEvenSortIntegers(16)(15) > maximum then
        maximum <= OddEvenSortIntegers(16)(15);
      end if;
      summation <= summation +   OddEvenSortIntegers(16)(0) + OddEvenSortIntegers(16)(1) + OddEvenSortIntegers(16)(2) + OddEvenSortIntegers(16)(3) +
                    OddEvenSortIntegers(16)(4) + OddEvenSortIntegers(16)(5) + OddEvenSortIntegers(16)(6) + OddEvenSortIntegers(16)(7) +
                    OddEvenSortIntegers(16)(8) + OddEvenSortIntegers(16)(9) + OddEvenSortIntegers(16)(10) + OddEvenSortIntegers(16)(11) + 
                    OddEvenSortIntegers(16)(12) + OddEvenSortIntegers(16)(13) + OddEvenSortIntegers(16)(14) + OddEvenSortIntegers(16)(15);
    end if;

    -- Done
    if lastSteps(16) = '1' then
      done <= '1';
    end if;

  end if;
end if;
end process;


end architecture;