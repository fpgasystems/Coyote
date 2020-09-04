library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity selection is
port (
  clk : in std_logic;
  rst_n : in std_logic;

  selType : in std_logic_vector(31 downto 0);
  lowThr : in std_logic_vector(31 downto 0);
  uppThr : in std_logic_vector(31 downto 0);

  axis_in_tvalid : in std_logic;
  axis_in_tready : out std_logic;
  axis_in_tdata : in std_logic_vector(511 downto 0);
  axis_in_tkeep : in std_logic_vector(63 downto 0);
  axis_in_tlast : in std_logic;

  axis_out_tvalid : out std_logic;
  axis_out_tready : in std_logic;
  axis_out_tdata : out std_logic_vector(511 downto 0);
  axis_out_tkeep : out std_logic_vector(63 downto 0);
  axis_out_tlast : out std_logic
);
end selection;

architecture behavioral of selection is

signal SelectionType : integer range 0 to 5;
signal LowerThreshold : signed(31 downto 0);
signal UpperThreshold : signed(31 downto 0);

type CLIntegersType is array (15 downto 0) of signed(31 downto 0);
signal CLIntegers : CLIntegersType;
signal predicatesInCL : signed(31 downto 0);
signal equalCLIntegers : CLIntegersType;
signal nonequalCLIntegers : CLIntegersType;
signal smallerCLIntegers : CLIntegersType;
signal smallerequalCLIntegers : CLIntegersType;
signal largerCLIntegers : CLIntegersType;
signal largerequalCLIntegers : CLIntegersType;

signal outputReg : std_logic_vector(511 downto 0);
signal keepReg : std_logic_vector(63 downto 0);
signal lastReg : std_logic;
signal valReg : std_logic;

begin

-- Params
SelectionType <= to_integer(unsigned(selType));
LowerThreshold <= signed(lowThr);
UpperThreshold <= signed(uppThr);

-- Gen CLs
gen_CLIntegers: for i in 0 to 15 generate
  CLIntegers(i) <= signed(axis_in_tdata(i*32+31 downto i*32));

  equalCLIntegers(i) <= CLIntegers(i) when CLIntegers(i) = LowerThreshold else (others => '0');
  nonequalCLIntegers(i) <= CLIntegers(i) when CLIntegers(i) /= LowerThreshold else (others => '0');
  smallerCLIntegers(i) <= CLIntegers(i) when CLIntegers(i) < UpperThreshold else (others => '0');
  smallerequalCLIntegers(i) <= CLIntegers(i) when CLIntegers(i) <= UpperThreshold else (others => '0');
  largerCLIntegers(i) <= CLIntegers(i) when CLIntegers(i) > LowerThreshold else (others => '0');
  largerequalCLIntegers(i) <= CLIntegers(i) when CLIntegers(i) >= LowerThreshold else (others => '0');
end generate gen_CLIntegers;

-- Gen output
axis_out_tdata <= outputReg;
axis_out_tkeep <= keepReg;
axis_out_tlast <= lastReg;
axis_out_tvalid <= valReg;

axis_in_tready <= axis_out_tready;

-- REG P
process(clk)
begin
if clk'event and clk = '1' then
  if rst_n = '0' then
    outputReg <= (others => '0');
    keepReg <= (others => '0');
    lastReg <= '0';
    valReg <= '0';
  else
    if axis_out_tready = '1' then
        keepReg <= axis_in_tkeep;
        lastReg <= axis_in_tlast;
        valReg <= axis_in_tvalid;
        case SelectionType is
            when 0 => outputReg <=   std_logic_vector(equalCLIntegers(15)) & std_logic_vector(equalCLIntegers(14)) & 
                        std_logic_vector(equalCLIntegers(13)) & std_logic_vector(equalCLIntegers(12)) &
                        std_logic_vector(equalCLIntegers(11)) & std_logic_vector(equalCLIntegers(10)) &
                        std_logic_vector(equalCLIntegers(9)) & std_logic_vector(equalCLIntegers(8)) &
                        std_logic_vector(equalCLIntegers(7)) & std_logic_vector(equalCLIntegers(6)) &
                        std_logic_vector(equalCLIntegers(5)) & std_logic_vector(equalCLIntegers(4)) &
                        std_logic_vector(equalCLIntegers(3)) & std_logic_vector(equalCLIntegers(2)) &
                        std_logic_vector(equalCLIntegers(1)) & std_logic_vector(equalCLIntegers(0));
  
            when 1 => outputReg <=   std_logic_vector(nonequalCLIntegers(15)) & std_logic_vector(nonequalCLIntegers(14)) & 
                        std_logic_vector(nonequalCLIntegers(13)) & std_logic_vector(nonequalCLIntegers(12)) &
                        std_logic_vector(nonequalCLIntegers(11)) & std_logic_vector(nonequalCLIntegers(10)) &
                        std_logic_vector(nonequalCLIntegers(9)) & std_logic_vector(nonequalCLIntegers(8)) &
                        std_logic_vector(nonequalCLIntegers(7)) & std_logic_vector(nonequalCLIntegers(6)) &
                        std_logic_vector(nonequalCLIntegers(5)) & std_logic_vector(nonequalCLIntegers(4)) &
                        std_logic_vector(nonequalCLIntegers(3)) & std_logic_vector(nonequalCLIntegers(2)) &
                        std_logic_vector(nonequalCLIntegers(1)) & std_logic_vector(nonequalCLIntegers(0));
  
            when 2 => outputReg <=   std_logic_vector(smallerCLIntegers(15)) & std_logic_vector(smallerCLIntegers(14)) & 
                        std_logic_vector(smallerCLIntegers(13)) & std_logic_vector(smallerCLIntegers(12)) &
                        std_logic_vector(smallerCLIntegers(11)) & std_logic_vector(smallerCLIntegers(10)) &
                        std_logic_vector(smallerCLIntegers(9)) & std_logic_vector(smallerCLIntegers(8)) &
                        std_logic_vector(smallerCLIntegers(7)) & std_logic_vector(smallerCLIntegers(6)) &
                        std_logic_vector(smallerCLIntegers(5)) & std_logic_vector(smallerCLIntegers(4)) &
                        std_logic_vector(smallerCLIntegers(3)) & std_logic_vector(smallerCLIntegers(2)) &
                        std_logic_vector(smallerCLIntegers(1)) & std_logic_vector(smallerCLIntegers(0));
  
            when 3 => outputReg <=   std_logic_vector(smallerequalCLIntegers(15)) & std_logic_vector(smallerequalCLIntegers(14)) & 
                        std_logic_vector(smallerequalCLIntegers(13)) & std_logic_vector(smallerequalCLIntegers(12)) &
                        std_logic_vector(smallerequalCLIntegers(11)) & std_logic_vector(smallerequalCLIntegers(10)) &
                        std_logic_vector(smallerequalCLIntegers(9)) & std_logic_vector(smallerequalCLIntegers(8)) &
                        std_logic_vector(smallerequalCLIntegers(7)) & std_logic_vector(smallerequalCLIntegers(6)) &
                        std_logic_vector(smallerequalCLIntegers(5)) & std_logic_vector(smallerequalCLIntegers(4)) &
                        std_logic_vector(smallerequalCLIntegers(3)) & std_logic_vector(smallerequalCLIntegers(2)) &
                        std_logic_vector(smallerequalCLIntegers(1)) & std_logic_vector(smallerequalCLIntegers(0));
  
            when 4 => outputReg <=   std_logic_vector(largerCLIntegers(15)) & std_logic_vector(largerCLIntegers(14)) & 
                        std_logic_vector(largerCLIntegers(13)) & std_logic_vector(largerCLIntegers(12)) &
                        std_logic_vector(largerCLIntegers(11)) & std_logic_vector(largerCLIntegers(10)) &
                        std_logic_vector(largerCLIntegers(9)) & std_logic_vector(largerCLIntegers(8)) &
                        std_logic_vector(largerCLIntegers(7)) & std_logic_vector(largerCLIntegers(6)) &
                        std_logic_vector(largerCLIntegers(5)) & std_logic_vector(largerCLIntegers(4)) &
                        std_logic_vector(largerCLIntegers(3)) & std_logic_vector(largerCLIntegers(2)) &
                        std_logic_vector(largerCLIntegers(1)) & std_logic_vector(largerCLIntegers(0));
  
            when 5 => outputReg <=   std_logic_vector(largerequalCLIntegers(15)) & std_logic_vector(largerequalCLIntegers(14)) & 
                        std_logic_vector(largerequalCLIntegers(13)) & std_logic_vector(largerequalCLIntegers(12)) &
                        std_logic_vector(largerequalCLIntegers(11)) & std_logic_vector(largerequalCLIntegers(10)) &
                        std_logic_vector(largerequalCLIntegers(9)) & std_logic_vector(largerequalCLIntegers(8)) &
                        std_logic_vector(largerequalCLIntegers(7)) & std_logic_vector(largerequalCLIntegers(6)) &
                        std_logic_vector(largerequalCLIntegers(5)) & std_logic_vector(largerequalCLIntegers(4)) &
                        std_logic_vector(largerequalCLIntegers(3)) & std_logic_vector(largerequalCLIntegers(2)) &
                        std_logic_vector(largerequalCLIntegers(1)) & std_logic_vector(largerequalCLIntegers(0));

            when others => null;
          end case;
    end if;

  end if;
end if;
end process;

end architecture;