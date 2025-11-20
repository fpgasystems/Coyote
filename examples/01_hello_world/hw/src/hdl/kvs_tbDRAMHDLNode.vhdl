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

-- This is a model of the Maxeler DFE DRAM
-- It is currently a dummy block which just connects up to where
-- the DRAM would in a real design
LIBRARY IEEE;
USE IEEE.std_logic_1164.all ;
USE IEEE.numeric_std.all;
USE IEEE.std_logic_arith.ALL;
USE IEEE.std_logic_unsigned.ALL;

entity kvs_tbDRAMHDLNode is 
  generic (
    DRAM_DATA_WIDTH : integer := 512;
    DRAM_CMD_WIDTH  : integer := 64;
    DRAM_ADDR_WIDTH : integer := 14
    );
  port (
    clk 			: in  std_logic;
    rst 			: in  std_logic;
    
    -- dramRdData goes out from the DRAM to UpdateKernel -pull if
    dramRdData_almost_empty  	: out std_logic;
    dramRdData_empty         	: out std_logic;
    dramRdData_read          	: in std_logic;
    dramRdData_data          	: out std_logic_vector (DRAM_DATA_WIDTH-1 downto 0);

    -- cmd_dramRdData is the command stream from HashKernel
    -- note PUSH input "done" pins are not implemented by MaxCompiler and must not be used
    cmd_dramRdData_valid	: in std_logic;
    cmd_dramRdData_stall	: out std_logic;
    cmd_dramRdData_data 	: in std_logic_vector (DRAM_CMD_WIDTH-1 downto 0);

    -- dramWrData is the "updated" datastream from UpdateKernel-push
    dramWrData_valid        	: in std_logic;
    dramWrData_stall        	: out std_logic;
    dramWrData_data         	: in std_logic_vector (DRAM_DATA_WIDTH-1 downto 0);

    -- cmd_dramWrData is the command stream from UpdateKernel -push
    cmd_dramWrData_valid        : in std_logic;
    cmd_dramWrData_stall        : out std_logic;
    cmd_dramWrData_data         : in std_logic_vector (DRAM_CMD_WIDTH-1 downto 0)

    );
end kvs_tbDRAMHDLNode;

architecture packed of kvs_tbDRAMHDLNode is

  type stateType is (IDLE, INCREMENT, X1, X2, X3);
  
  component nukv_fifogen
     GENERIC (
      ADDR_BITS : integer;
      DATA_SIZE : integer
     ) ;
    PORT (
    clk : IN STD_LOGIC;
    rst : IN STD_LOGIC;
    s_axis_tdata : IN STD_LOGIC_VECTOR(DATA_SIZE-1 DOWNTO 0);
    s_axis_tvalid: IN STD_LOGIC;
    s_axis_tready : OUT STD_LOGIC;
    m_axis_tdata : OUT STD_LOGIC_VECTOR(DATA_SIZE-1 DOWNTO 0);      
    m_axis_tvalid : OUT STD_LOGIC;
    m_axis_tready : IN STD_LOGIC
          );END component;
  
  component fifogen_dram_data_in
    PORT (
      clk : IN STD_LOGIC;
      rst : IN STD_LOGIC;
      din : IN STD_LOGIC_VECTOR(511 DOWNTO 0);
      wr_en : IN STD_LOGIC;
      rd_en : IN STD_LOGIC;
      dout : OUT STD_LOGIC_VECTOR(511 DOWNTO 0);
      full : OUT STD_LOGIC;
      empty : OUT STD_LOGIC
      );END component;

  component fifogen_dram_data_out
    PORT (
      clk : IN STD_LOGIC;
      srst : IN STD_LOGIC;
      din : IN STD_LOGIC_VECTOR(511 DOWNTO 0);
      wr_en : IN STD_LOGIC;
      rd_en : IN STD_LOGIC;
      dout : OUT STD_LOGIC_VECTOR(511 DOWNTO 0);
      full : OUT STD_LOGIC;     
      empty : OUT STD_LOGIC
      );END component;
  
  component fifogen_dram_cmd_in
    PORT (
      clk : IN STD_LOGIC;
      srst : IN STD_LOGIC;
      din : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      wr_en : IN STD_LOGIC;
      rd_en : IN STD_LOGIC;
      dout : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
      full : OUT STD_LOGIC;
      empty : OUT STD_LOGIC
      );END component;
  
  component bram_gen 
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
  end component;

  signal wrCmdEmpty : std_logic;
  signal wrCmdPop : std_logic;
  signal wrCmdData : std_logic_vector(DRAM_CMD_WIDTH-1 downto 0);
  
  signal dramWrDataStall : std_logic_vector(2 downto 0);

  signal wrEmpty : std_logic_vector((DRAM_DATA_WIDTH/512)-1 downto 0);
  signal wrPop : std_logic;
  signal wrData : std_logic_vector(DRAM_DATA_WIDTH-1 downto 0);

  signal memUnusedData : std_logic_vector(DRAM_DATA_WIDTH-1 downto 0);

  signal rdCmdEmpty : std_logic;
  signal rdCmdPop : std_logic;
  signal rdCmdData : std_logic_vector(DRAM_CMD_WIDTH-1 downto 0);

  signal rdNotEmpty : std_logic_vector((DRAM_DATA_WIDTH/512)-1 downto 0);
  signal rdNotFull : std_logic_vector((DRAM_DATA_WIDTH/512)-1 downto 0);
  signal rdProgFull : std_logic_vector((DRAM_DATA_WIDTH/512)-1 downto 0);
  signal rdData : std_logic_vector(DRAM_DATA_WIDTH-1 downto 0);
  signal rdPush : std_logic;

  signal writeDram : std_logic;
  signal rdDataEmpty : std_logic;

  signal readAddr : std_logic_vector(DRAM_ADDR_WIDTH-1 downto 0);
  signal readCnt : std_logic_vector(7 downto 0);
  signal writeAddr : std_logic_vector(DRAM_ADDR_WIDTH-1 downto 0);
  signal writeCnt : std_logic_vector(7 downto 0);

  signal readState : stateType;
  signal writeState : stateType;
  
  signal rstBuf : std_logic;
  
  --signal shiftreg : std_logic_vector(513*7-1 downto 0);
  --signal shiftvalid : std_logic;

--attribute definition
  attribute max_fanout: string;
  
  signal dataread :std_logic;
  
  signal clocker :  std_logic_vector(5 downto 0);
  
  attribute max_fanout of readAddr: signal is "80";
begin  -- packed

  rd_cmd_in : fifogen_dram_cmd_in
    port map (
      clk, rst,
      cmd_dramRdData_data, cmd_dramRdData_valid,
      rdCmdPop, rdCmdData,
      cmd_dramRdData_stall,
      rdCmdEmpty
      );

  --shiftvalid <= shiftreg(513*7-1);
  --rd_data_out: for X in (DRAM_DATA_WIDTH/512)-1 downto 0 generate
    rd_data_i : nukv_fifogen
      generic map (8,512)
      port map (
        clk, rst,
        --shiftreg(513*7-2 downto 513*7-513), shiftvalid,
        rdData(511 downto 0), rdPush, rdNotFull(0),
        dramRdData_data(511 downto 0),  rdNotEmpty(0), dataread
        
        );
    
  --end generate rd_data_out;
  
  dataread <= dramRdData_read ; --when clocker<8 else '0'; 
  dramRdData_empty <= not rdNotEmpty(0); -- when clocker<8 else '1';
  
  wr_cmd_in : fifogen_dram_cmd_in
    port map (
      clk, rst,
      cmd_dramWrData_data, cmd_dramWrData_valid,
      wrCmdPop, wrCmdData,
      cmd_dramWrData_stall,
      wrCmdEmpty
      );

  dramWrData_stall <= dramWrDataStall(0);
  wr_data_in: for X in (DRAM_DATA_WIDTH/512)-1 downto 0 generate
    wr_data_i : fifogen_dram_data_in
      port map (
        clk, rst,
        dramWrData_data(512*(X+1)-1 downto 512*X), dramWrData_valid,
        wrPop, wrData(512*(X+1)-1 downto 512*X),
        dramWrDataStall(X), wrEmpty(X)
        );
    
  end generate wr_data_in;

  store : bram_gen
    generic map ( DRAM_DATA_WIDTH, DRAM_ADDR_WIDTH )
    port map (
      clk,
      writeDram,                        -- write enable
      writeAddr,                         --write addr
      readAddr,                         --read addr
      wrData,                            -- write data
      memUnusedData,                    --unused
      rdData                             -- read data
      );

  clock: process (clk)
  begin  -- process clock
    if clk'event and clk='1' then                 
      
      if rst='1' then
        rdPush <= '0';
        readState <= IDLE;
        writeState <= IDLE;

        rdCmdPop <='0';
        rdPush <= '0';
        writeDram <= '0';
        wrPop <= '0';
        wrCmdPop <= '0';
        
        --shiftreg <= (others => '0');
        
        clocker <= (others => '0');
        
      else
      
        clocker <= clocker+1;
	
        --shiftreg(513*7-1 downto 513) <= shiftreg(513*6-1 downto 0);
        --shiftreg(512 downto 0) <= rdPush & rdData;
        -----------------------------------------------------------------------
        -- READ ---------------------------------------------------------------
        -----------------------------------------------------------------------

        case readState is
          when IDLE =>
            rdPush <= '0';
            
            if rdCmdEmpty='0' then
              readAddr <= rdCmdData(DRAM_ADDR_WIDTH-1 downto 0);
              readCnt <= rdCmdData(39 downto 32);
              rdCmdPop <= '1';
              readState <= INCREMENT;
            end if;
          when INCREMENT =>
            rdPush <= '0';
            rdCmdPop <= '0';
            
            --if rdNotFull(0)='0' then
            if (rdNotFull(0)='1') then
              rdPush <= '1';
              readAddr <= readAddr+1;
              readCnt <= readCnt-1;
              if readCnt=1 then
                readState <= IDLE;
	      else 
		readState <= INCREMENT;
              end if;
	      
            end if;
	    
	  when X1 =>
	    rdPush <= '0';
            rdCmdPop <= '0';
	    readState <= INCREMENT;
	    
	  when X2 => 
	    readState <= X3;
	    
	  when X3 => 
	    readState <= INCREMENT;
	    
          when others => null;
        end case;
        
        -----------------------------------------------------------------------
        -- WRITE --------------------------------------------------------------
        -----------------------------------------------------------------------
        case writeState is
          when IDLE =>
            wrPop <= '0';
            writeDram <= '0';
            wrCmdPop <= '0';
            
            if wrCmdEmpty='0' and wrEmpty(0)='0' then
              writeAddr <= wrCmdData(DRAM_ADDR_WIDTH-1 downto 0)-1;
              writeCnt <= wrCmdData(39 downto 32);
              wrCmdPop <= '1';
              writeState <= INCREMENT;
            end if;

          when X1 =>
            writeState <= X2;

          when X2 =>         
	    wrPop <= '0';
            wrCmdPop <= '0';
            writeDram <= '0';			 
            writeState <= INCREMENT;
            
          when INCREMENT =>
            wrPop <= '0';
            wrCmdPop <= '0';
            writeDram <= '0';
            
            if wrEmpty(0)='0' then
              wrPop <= '1';
              writeDram <= '1';
              writeAddr <= writeAddr+1;
              writeCnt <= writeCnt-1;
              if writeCnt=1 then
                writeState <= IDLE;
	      else 
		writeState <= X2;
              end if;
              
            end if;
          when others => null;
        end case;


        
      end if;
    end if;
  end process clock;

  

end packed;
