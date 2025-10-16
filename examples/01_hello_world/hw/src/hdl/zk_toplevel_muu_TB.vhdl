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
use IEEE.Std_logic_1164.all;
use IEEE.Numeric_Std.all;
USE IEEE.std_logic_arith.ALL;
USE IEEE.std_logic_unsigned.ALL;
use std.textio.all;
USE IEEE.std_logic_textio.ALL;

entity zk_toplevel_muu_TB is
end zk_toplevel_muu_TB;

architecture bench of zk_toplevel_muu_TB is

   --component zookeeper_tcp_top_parallel_nkv
  component muu_TopWrapper_fclk512
  generic (
       IS_SIM : integer := 0 
    );
    port (
      aclk : in std_logic;
      aresetn : in std_logic;
      
      fclk : in std_logic;
      
      m_axis_open_connection_TVALID : out std_logic;
      m_axis_open_connection_TREADY : in std_logic;
      m_axis_open_connection_TDATA: out std_logic_vector(47 downto 0);
      
      s_axis_open_status_TVALID : in std_logic;
      s_axis_open_status_TREADY : out std_logic;
      s_axis_open_status_TDATA: in std_logic_vector(23 downto 0);
      
      m_axis_close_connection_TVALID : out std_logic;
      m_axis_close_connection_TREADY : in std_logic;
      m_axis_close_connection_TDATA: out std_logic_vector(15 downto 0);

      m_axis_listen_port_TVALID : out std_logic;
      m_axis_listen_port_TREADY : in std_logic;
      m_axis_listen_port_TDATA: out std_logic_vector(15 downto 0);

      s_axis_listen_port_status_TVALID : in std_logic;
      s_axis_listen_port_status_TREADY : out std_logic;
      s_axis_listen_port_status_TDATA : in std_logic_vector(7 downto 0);

      s_axis_notifications_TVALID : in std_logic;
      s_axis_notifications_TREADY : out std_logic;
      s_axis_notifications_TDATA : in std_logic_vector(87 downto 0);

      m_axis_read_package_TVALID : out std_logic;
      m_axis_read_package_TREADY : in std_logic;
      m_axis_read_package_TDATA: out std_logic_vector(31 downto 0);
      
      m_axis_tx_data_TVALID : out std_logic;
      m_axis_tx_data_TREADY : in std_logic;
      m_axis_tx_data_TDATA: out std_logic_vector(63 downto 0);
      m_axis_tx_data_TKEEP: out std_logic_vector(7 downto 0);
      m_axis_tx_data_TLAST: out std_logic_vector(0 downto 0);
      
      m_axis_tx_metadata_TVALID : out std_logic;
      m_axis_tx_metadata_TREADY : in std_logic;
      m_axis_tx_metadata_TDATA: out std_logic_vector(31 downto 0);
      
      s_axis_tx_status_TVALID : in std_logic;
      s_axis_tx_status_TREADY : out std_logic;
      s_axis_tx_status_TDATA : in std_logic_vector(63 downto 0);
      
      s_axis_rx_data_TVALID : in std_logic;
      s_axis_rx_data_TREADY : out std_logic;
      s_axis_rx_data_TDATA : in std_logic_vector(63 downto 0);
      s_axis_rx_data_TKEEP:  in std_logic_vector(7 downto 0);
      s_axis_rx_data_TLAST: in std_logic_vector(0 downto 0);
      
      s_axis_rx_metadata_TVALID: in std_logic;
      s_axis_rx_metadata_TREADY : out std_logic;
      s_axis_rx_metadata_TDATA: in std_logic_vector(15 downto 0);
      
      
      ht_dramRdData_almost_empty  	: in std_logic;
      ht_dramRdData_empty             : in std_logic;
      ht_dramRdData_read              : out std_logic;
      ht_dramRdData_data              : in std_logic_vector (512-1 downto 0);
  
      ht_cmd_dramRdData_valid    : out std_logic;
      ht_cmd_dramRdData_stall    : in std_logic;
      ht_cmd_dramRdData_data     : out std_logic_vector (64-1 downto 0);
  
      ht_dramWrData_valid            : out std_logic;
      ht_dramWrData_stall            : in std_logic;
      ht_dramWrData_data             : out std_logic_vector (512-1 downto 0);
  
      ht_cmd_dramWrData_valid        : out std_logic;
      ht_cmd_dramWrData_stall        : in std_logic;
      ht_cmd_dramWrData_data         : out std_logic_vector (64-1 downto 0);
      
      upd_dramRdData_almost_empty  	: in std_logic;
      upd_dramRdData_empty             : in std_logic;
      upd_dramRdData_read              : out std_logic;
      upd_dramRdData_data              : in std_logic_vector (512-1 downto 0);
  
      upd_cmd_dramRdData_valid    : out std_logic;
      upd_cmd_dramRdData_stall    : in std_logic;
      upd_cmd_dramRdData_data     : out std_logic_vector (64-1 downto 0);
      
      
       
           upd_dramWrData_valid             : out std_logic;
           upd_dramWrData_stall              : in std_logic;
           upd_dramWrData_data              : out std_logic_vector (512-1 downto 0);
       
           upd_cmd_dramWrData_valid    : out std_logic;
           upd_cmd_dramWrData_stall    : in std_logic;
           upd_cmd_dramWrData_data     : out std_logic_vector (64-1 downto 0);


  
      ptr_rdcmd_data : out std_logic_vector (64-1 downto 0);
      ptr_rdcmd_valid : out std_logic;
      ptr_rdcmd_ready : in std_logic;

      ptr_rd_data : in std_logic_vector (512-1 downto 0);
      ptr_rd_valid : in std_logic;
      ptr_rd_ready : out std_logic;

      ptr_wr_data : out std_logic_vector (512-1 downto 0);
      ptr_wr_valid : out std_logic;
      ptr_wr_ready : in std_logic;

      ptr_wrcmd_data : out std_logic_vector (64-1 downto 0);
      ptr_wrcmd_valid : out std_logic;
      ptr_wrcmd_ready : in std_logic;


      bmap_rdcmd_data : out std_logic_vector (64-1 downto 0);
      bmap_rdcmd_valid : out std_logic;
      bmap_rdcmd_ready : in std_logic;

      bmap_rd_data : in std_logic_vector (512-1 downto 0);
      bmap_rd_valid : in std_logic;
      bmap_rd_ready : out std_logic;

      bmap_wr_data : out std_logic_vector (512-1 downto 0);
      bmap_wr_valid : out std_logic;
      bmap_wr_ready : in std_logic;

      bmap_wrcmd_data : out std_logic_vector (64-1 downto 0);
      bmap_wrcmd_valid : out std_logic;
      bmap_wrcmd_ready : in std_logic
      
--      para0_in_tdata : in std_logic_vector(63 downto 0);
--      para0_in_tvalid : in std_logic;
--      para0_in_tlast : in std_logic;
--      para0_in_tready : out std_logic;
      
--      para1_in_tdata : in std_logic_vector(63 downto 0);
--      para1_in_tvalid : in std_logic;
--      para1_in_tlast : in std_logic;
--      para1_in_tready : out std_logic;                   

--      para2_in_tdata : in std_logic_vector(63 downto 0);
--      para2_in_tvalid : in std_logic;
--      para2_in_tlast : in std_logic;
--      para2_in_tready : out std_logic;
      
--      para0_out_tdata : out std_logic_vector(63 downto 0);
--      para0_out_tvalid : out std_logic;
--      para0_out_tlast : out std_logic;
--      para0_out_tready : in std_logic;
      
--      para1_out_tdata : out std_logic_vector(63 downto 0);
--      para1_out_tvalid : out std_logic;
--      para1_out_tlast : out std_logic;
--      para1_out_tready : in std_logic;                   

--      para2_out_tdata : out std_logic_vector(63 downto 0);
--      para2_out_tvalid : out std_logic;
--      para2_out_tlast : out std_logic;
--      para2_out_tready : in std_logic
      
      --hadretransmit : in std_logic_vector(63 downto 0)
      --toedebug : in std_logic_vector(161 downto 0)        
      
      );
  end component;
  
  component kvs_tbDRAMHDLNode is 
    generic (
      DRAM_DATA_WIDTH : integer := 512;
      DRAM_CMD_WIDTH  : integer := 64;
      DRAM_ADDR_WIDTH : integer := 14
      );
    port (
      clk             : in  std_logic;
      rst             : in  std_logic;
      
      -- dramRdData goes out from the DRAM to UpdateKernel -pull if
      dramRdData_almost_empty      : out std_logic;
      dramRdData_empty             : out std_logic;
      dramRdData_read              : in std_logic;
      dramRdData_data              : out std_logic_vector (DRAM_DATA_WIDTH-1 downto 0);
  
      -- cmd_dramRdData is the command stream from HashKernel
      -- note PUSH input "done" pins are not implemented by MaxCompiler and must not be used
      cmd_dramRdData_valid    : in std_logic;
      cmd_dramRdData_stall    : out std_logic;
      cmd_dramRdData_data     : in std_logic_vector (DRAM_CMD_WIDTH-1 downto 0);
  
      -- dramWrData is the "updated" datastream from UpdateKernel-push
      dramWrData_valid            : in std_logic;
      dramWrData_stall            : out std_logic;
      dramWrData_data             : in std_logic_vector (DRAM_DATA_WIDTH-1 downto 0);
  
      -- cmd_dramWrData is the command stream from UpdateKernel -push
      cmd_dramWrData_valid        : in std_logic;
      cmd_dramWrData_stall        : out std_logic;
      cmd_dramWrData_data         : in std_logic_vector (DRAM_CMD_WIDTH-1 downto 0)
  
      );
  end component;


  component kvs_tbDRAM_Module is 
  generic (
    DRAM_DATA_WIDTH : integer := 512;
    DRAM_CMD_WIDTH  : integer := 64;
    DRAM_ADDR_WIDTH : integer := 8
    );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    
    dramRdData_valid          : out std_logic;
    dramRdData_ready            : in std_logic;
    dramRdData_data           : out std_logic_vector (DRAM_DATA_WIDTH-1 downto 0);

    cmd_dramRdData_valid  : in std_logic;
    cmd_dramRdData_ready  : out std_logic;
    cmd_dramRdData_data   : in std_logic_vector (DRAM_CMD_WIDTH-1 downto 0);

    dramWrData_valid          : in std_logic;
    dramWrData_ready          : out std_logic;
    dramWrData_data           : in std_logic_vector (DRAM_DATA_WIDTH-1 downto 0);

    cmd_dramWrData_valid        : in std_logic;
    cmd_dramWrData_ready        : out std_logic;
    cmd_dramWrData_data         : in std_logic_vector (DRAM_CMD_WIDTH-1 downto 0)

    );
end component;

  signal clk: std_logic := '0';
  signal fclk: std_logic := '0';
  signal clk200: std_logic := '1';
  signal rst: std_logic := '1';
  signal rstX: std_logic := '1';
  signal rstn: std_logic;
  signal event_valid: std_logic;
  signal event_ready: std_logic;
  signal event_data: std_logic_vector(87 downto 0);
  signal readreq_valid: std_logic;
  signal readreq_ready: std_logic := '1';
  signal readreq_data: std_logic_vector(31 downto 0);
  signal packet_valid: std_logic;
  signal packet_ready: std_logic;
  signal packet_data: std_logic_vector(63 downto 0);
  signal packet_keep: std_logic_vector(7 downto 0);
  signal packet_last: std_logic_vector(0 downto 0);
  signal out_valid: std_logic;
  signal out_ready: std_logic := '1';
  signal out_last: std_logic_vector(0 downto 0);
  signal out_data: std_logic_vector(63 downto 0);
  signal out_meta_valid : std_logic;
  signal out_meta: std_logic_vector(31 downto 0) ;
  
  signal waiting : std_logic_vector(15 downto 0);
  signal waiting2 : std_logic_vector(15 downto 0);
  
  signal openConnReqValid : std_logic;
  signal openConnRespValid : std_logic;
  signal openConnRespReady : std_logic;
  
  signal waitLast : std_logic;
  
  signal cntReady : std_logic_vector(7 downto 0);
  signal cntReady2 : std_logic_vector(7 downto 0);
  signal metaReady : std_logic := '0';
  
    signal d_rd_data              : std_logic_vector(511 downto 0);
  signal d_rd_data_read         : std_logic;
  signal d_rd_data_empty        : std_logic;
  signal d_rd_data_almost_empty : std_logic;

  signal d_rd_cmd       : std_logic_vector(63 downto 0);
  signal d_rd_cmd_valid : std_logic;
  signal d_rd_cmd_stall : std_logic;

  signal d_wr_data       : std_logic_vector(511 downto 0);
  signal d_wr_data_valid : std_logic;
  signal d_wr_data_stall : std_logic;

  signal d_wr_cmd       : std_logic_vector(63 downto 0);
  signal d_wr_cmd_valid : std_logic;
  signal d_wr_cmd_stall : std_logic;

  signal d2_rd_data              : std_logic_vector(511 downto 0);
  signal d2_rd_data_read         : std_logic;
  signal d2_rd_data_empty        : std_logic;
  signal d2_rd_data_almost_empty : std_logic;
  
  signal d2_rd_data_int              : std_logic_vector(511 downto 0);
  signal d2_rd_data_read_int         : std_logic;
  signal d2_rd_data_empty_int        : std_logic;
  signal d2_rd_data_almost_empty_int : std_logic;

  signal d2_rd_cmd       : std_logic_vector(63 downto 0);
  signal d2_rd_cmd_valid : std_logic;
  signal d2_rd_cmd_stall : std_logic;

  signal d2_wr_data       : std_logic_vector(511 downto 0);
  signal d2_wr_data_valid : std_logic;
  signal d2_wr_data_stall : std_logic;

  signal d2_wr_cmd       : std_logic_vector(63 downto 0);
  signal d2_wr_cmd_valid : std_logic;
  signal d2_wr_cmd_stall : std_logic;



  signal ptr_rdcmd_data : std_logic_vector (64-1 downto 0);
  signal ptr_rdcmd_valid : std_logic;
      signal ptr_rdcmd_ready : std_logic;

      signal ptr_rd_data : std_logic_vector (512-1 downto 0);
      signal ptr_rd_valid :  std_logic;
      signal ptr_rd_ready :  std_logic;

      signal ptr_wr_data :  std_logic_vector (512-1 downto 0);
      signal ptr_wr_valid :  std_logic;
      signal ptr_wr_ready :  std_logic;

      signal ptr_wrcmd_data :  std_logic_vector (64-1 downto 0);
      signal ptr_wrcmd_valid :  std_logic;
      signal ptr_wrcmd_ready :  std_logic;


      signal bmap_rdcmd_data :  std_logic_vector (64-1 downto 0);
      signal bmap_rdcmd_valid :  std_logic;
      signal bmap_rdcmd_ready :  std_logic;

      signal bmap_rd_data :  std_logic_vector (512-1 downto 0);
      signal bmap_rd_valid :  std_logic;
      signal bmap_rd_ready :  std_logic;

      signal bmap_wr_data :  std_logic_vector (512-1 downto 0);
      signal bmap_wr_valid :  std_logic;
      signal bmap_wr_ready :  std_logic;

      signal bmap_wrcmd_data :  std_logic_vector (64-1 downto 0);
      signal bmap_wrcmd_valid :  std_logic;
      signal bmap_wrcmd_ready :  std_logic;
      
      signal ticker : std_logic_vector(23 downto 0) := (others=>'0') ;
      
      signal mrdel_data : std_logic_vector(64*512-1 downto 0);
      signal mrdel_empty : std_logic_vector(63 downto 0);
      
      signal count : std_logic_vector(63 downto 0) := (others => '0');

begin

  
  --  uut: zookeeper_tcp_top_parallel_nkv
    uut: muu_TopWrapper_fclk512 
    generic map ( IS_SIM => 1 )
    port map ( aclk           => clk,
	       aresetn        => rstn,
	       fclk => fclk,
	       
	       m_axis_open_connection_TVALID => openConnReqValid,
	       m_axis_open_connection_TREADY =>  '1',
	       s_axis_open_status_TVALID => openConnRespValid,
	       s_axis_open_status_TREADY => openConnRespReady,
	       s_axis_open_status_TDATA => ticker,--"000011110000111100001111",
	       m_axis_close_connection_TREADY => '1',	       
	       m_axis_listen_port_TREADY => '1',
	       s_axis_listen_port_status_TVALID =>  '0',
	       s_axis_listen_port_status_TDATA => (others => '0'),
	       
	       
	       s_axis_notifications_TVALID => event_valid,
	       s_axis_notifications_TREADY => event_ready,
	       s_axis_notifications_TDATA => event_data,
	       
	       m_axis_read_package_TVALID => readreq_valid,
	       m_axis_read_package_TREADY => readreq_ready,
	       m_axis_read_package_TDATA => readreq_data,

	       m_axis_tx_data_TVALID => out_valid,
               m_axis_tx_data_TREADY => out_ready,
	       m_axis_tx_data_TDATA => out_data,
	       m_axis_tx_data_TLAST => out_last,
	       
	       m_axis_tx_metadata_TVALID => out_meta_valid,
               m_axis_tx_metadata_TREADY => metaReady,
	       m_axis_tx_metadata_TDATA =>  out_meta,

	       s_axis_tx_status_TVALID => '0',
	       s_axis_tx_status_TDATA => (others => '0'),
	       
	       
               s_axis_rx_data_TVALID =>  packet_valid,
	       s_axis_rx_data_TREADY => packet_ready,
	       s_axis_rx_data_TDATA => packet_data,
	       s_axis_rx_data_TKEEP => packet_keep,
	       s_axis_rx_data_TLAST => packet_last,

	       s_axis_rx_metadata_TVALID => '0',
	       s_axis_rx_metadata_TDATA => (others => '0'),
	       
	       
          
          ht_dramRdData_data          => d_rd_data,
                ht_dramRdData_empty         => d_rd_data_empty,
                ht_dramRdData_almost_empty  => '0',
                ht_dramRdData_read          => d_rd_data_read,
                ht_cmd_dramRdData_data      => d_rd_cmd,
                ht_cmd_dramRdData_valid     => d_rd_cmd_valid,
                ht_cmd_dramRdData_stall     => d_rd_cmd_stall,
                ht_dramWrData_data          => d_wr_data,
                ht_dramWrData_valid         => d_wr_data_valid,
                ht_dramWrData_stall         => d_wr_data_stall,
                ht_cmd_dramWrData_data      => d_wr_cmd,
                ht_cmd_dramWrData_valid     => d_wr_cmd_valid,
                ht_cmd_dramWrData_stall     => d_wr_cmd_stall,
          
                -- Update DRAM Connection
          
                upd_dramRdData_data         => d2_rd_data_int,
                upd_dramRdData_empty        => d2_rd_data_empty_int,
                upd_dramRdData_almost_empty => d2_rd_data_almost_empty_int,
                upd_dramRdData_read         => d2_rd_data_read_int,
                upd_cmd_dramRdData_data     => d2_rd_cmd,
                upd_cmd_dramRdData_valid    => d2_rd_cmd_valid,
                upd_cmd_dramRdData_stall    => d2_rd_cmd_stall,
                upd_dramWrData_data         => d2_wr_data,
                upd_dramWrData_valid        => d2_wr_data_valid,
                upd_dramWrData_stall        => d2_wr_data_stall,
                upd_cmd_dramWrData_data     => d2_wr_cmd,
                upd_cmd_dramWrData_valid    => d2_wr_cmd_valid,
                upd_cmd_dramWrData_stall    => d2_wr_cmd_stall,



         ptr_rdcmd_data =>  ptr_rdcmd_data,
      ptr_rdcmd_valid =>ptr_rdcmd_valid,
      ptr_rdcmd_ready =>ptr_rdcmd_ready,

      ptr_rd_data =>ptr_rd_data,
      ptr_rd_valid=>ptr_rd_valid,
      ptr_rd_ready=>ptr_rd_ready,

      ptr_wr_data =>ptr_wr_data,
      ptr_wr_valid=>ptr_wr_valid,
      ptr_wr_ready=>ptr_wr_ready,

      ptr_wrcmd_data =>ptr_wrcmd_data,
      ptr_wrcmd_valid=>ptr_wrcmd_valid,
      ptr_wrcmd_ready=>ptr_wrcmd_ready,


      bmap_rdcmd_data=>bmap_rdcmd_data,
      bmap_rdcmd_valid =>bmap_rdcmd_valid,
      bmap_rdcmd_ready =>bmap_rdcmd_ready,

      bmap_rd_data =>bmap_rd_data,
      bmap_rd_valid =>bmap_rd_valid,
      bmap_rd_ready =>bmap_rd_ready,

      bmap_wr_data =>bmap_wr_data,
      bmap_wr_valid =>bmap_wr_valid,
      bmap_wr_ready =>bmap_wr_ready,

      bmap_wrcmd_data =>bmap_wrcmd_data,
      bmap_wrcmd_valid =>bmap_wrcmd_valid,
      bmap_wrcmd_ready =>bmap_wrcmd_ready
          
        
--                para0_in_tdata => (others => '0'),
--                para1_in_tdata => (others => '0'),
--                para2_in_tdata => (others => '0'),
                
--                para0_in_tvalid => '0',
--                para1_in_tvalid => '0',
--                para2_in_tvalid => '0',
                
--                para0_in_tlast => '0',
--                para1_in_tlast => '0',
--                para2_in_tlast => '0',
                
--                para0_out_tready => '1',
--                          para1_out_tready => '1',
--                          para2_out_tready => '1'
 
          --hadretransmit => (others => '0')
          --toedebug => (others => '0')
          
    
	       );
	       
   mockmem_ht : entity work.kvs_tbDRAMHDLNode
              generic map (
                  DRAM_DATA_WIDTH => 512,
                  DRAM_ADDR_WIDTH => 16
               )
              port map(
                clk                     => clk,
                rst                     => rstX,
          
                -- dramRdData goes out from the DRAM to UpdateKernel -pull if
                dramRdData_almost_empty => d_rd_data_almost_empty,
                dramRdData_empty        => d_rd_data_empty,
                dramRdData_read         => d_rd_data_read,
                dramRdData_data         => d_rd_data,
          
                -- cmd_dramRdData is the command stream from HashKernel
                -- note PUSH input "done" pins are not implemented by MaxCompiler and must not be used
                cmd_dramRdData_valid    => d_rd_cmd_valid,
                cmd_dramRdData_stall    => d_rd_cmd_stall,
                cmd_dramRdData_data     => d_rd_cmd,
          
                -- dramWrData is the "updated" datastream from UpdateKernel-push
                dramWrData_valid        => d_wr_data_valid,
                dramWrData_stall        => d_wr_data_stall,
                dramWrData_data         => d_wr_data,
          
                -- cmd_dramWrData is the command stream from UpdateKernel -push
                cmd_dramWrData_valid    => d_wr_cmd_valid,
                cmd_dramWrData_stall    => d_wr_cmd_stall,
                cmd_dramWrData_data     => d_wr_cmd
                );
          
            mockmem_upd : entity work.kvs_tbDRAMHDLNode
            generic map (
                              DRAM_DATA_WIDTH => 512,
                              DRAM_ADDR_WIDTH => 16
                           )
              port map(
                clk                     => clk,
                rst                     => rstX,
          
                -- dramRdData goes out from the DRAM to UpdateKernel -pull if
                dramRdData_almost_empty => d2_rd_data_almost_empty,
                dramRdData_empty        => d2_rd_data_empty,
                dramRdData_read         => d2_rd_data_read,
                dramRdData_data         => d2_rd_data,
          
                -- cmd_dramRdData is the command stream from HashKernel
                -- note PUSH input "done" pins are not implemented by MaxCompiler and must not be used
                cmd_dramRdData_valid    => d2_rd_cmd_valid,
                cmd_dramRdData_stall    => d2_rd_cmd_stall,
                cmd_dramRdData_data     => d2_rd_cmd,
          
                -- dramWrData is the "updated" datastream from UpdateKernel-push
                dramWrData_valid        => d2_wr_data_valid,
                dramWrData_stall        => d2_wr_data_stall,
                dramWrData_data         => d2_wr_data,
          
                -- cmd_dramWrData is the command stream from UpdateKernel -push
                cmd_dramWrData_valid    => d2_wr_cmd_valid,
                cmd_dramWrData_stall    => d2_wr_cmd_stall,
                cmd_dramWrData_data     => d2_wr_cmd
                );



         mockmem_ptr : entity work.kvs_tbDRAM_Module
              generic map (
                  DRAM_DATA_WIDTH => 512,
                                DRAM_ADDR_WIDTH => 16
               )
              port map(
                clk                     => clk,
                rst                     => rstX,
                          
                dramRdData_valid        => ptr_rd_valid,
                dramRdData_ready         => ptr_rd_ready,
                dramRdData_data         => ptr_rd_data,

                cmd_dramRdData_valid    => ptr_rdcmd_valid,
                cmd_dramRdData_ready    => ptr_rdcmd_ready,
                cmd_dramRdData_data     => ptr_rdcmd_data,
          
                dramWrData_valid        => ptr_wr_valid,
                dramWrData_ready        => ptr_wr_ready,
                dramWrData_data         => ptr_wr_data,
          
                cmd_dramWrData_valid    => ptr_wrcmd_valid,
                cmd_dramWrData_ready    => ptr_wrcmd_ready,
                cmd_dramWrData_data     => ptr_wrcmd_data
                );

mockmem_bitmap : entity work.kvs_tbDRAM_Module
              generic map (
                  DRAM_DATA_WIDTH => 512,
                                DRAM_ADDR_WIDTH => 16
               )
              port map(
                clk                     => clk,
                rst                     => rstX,
                          
                dramRdData_valid        => bmap_rd_valid,
                dramRdData_ready         => bmap_rd_ready,
                dramRdData_data         => bmap_rd_data,

                cmd_dramRdData_valid    => bmap_rdcmd_valid,
                cmd_dramRdData_ready    => bmap_rdcmd_ready,
                cmd_dramRdData_data     => bmap_rdcmd_data,
          
                dramWrData_valid        => bmap_wr_valid,
                dramWrData_ready        => bmap_wr_ready,
                dramWrData_data         => bmap_wr_data,
          
                cmd_dramWrData_valid    => bmap_wrcmd_valid,
                cmd_dramWrData_ready    => bmap_wrcmd_ready,
                cmd_dramWrData_data     => bmap_wrcmd_data
                );   


  d2_rd_data_int              <= d2_rd_data;
  d2_rd_data_read             <= d2_rd_data_read_int;-- when cntReady2<3 or cntReady<1 else '0';
  d2_rd_data_empty_int        <= d2_rd_data_empty;-- when cntReady2<3 or cntReady<1 else '1';
  d2_rd_data_almost_empty_int <= d2_rd_data_almost_empty;-- when cntReady2<3 or cntReady<1 else '1';

  rstn <= not rst;                                    
  rst <= '0' after 400ns;
  rstX <= '0' after 400ns;
  clk <= not clk after 3.2ns;
  fclk <= not fclk after 1.6ns;
  clk200 <= not clk200 after 1.6ns;

  stim_event: process
    file eventfile : text is in "../../session-event-in.txt";
    variable evinline : line;
    variable evtype : std_logic_vector(15 downto 0);
    variable evdata : std_logic_Vector(87 downto 0);
    
  begin
    wait until clk'event and clk='1';
    
    
    if (rst='1') then
      
      waiting <= (others => '0');
      event_valid <= '0';
      
      openConnRespValid <= '0';
      
      mrdel_data <= (others => '0');
      mrdel_empty <= (others => '1');
      
    else
    
      count <= count + 1;
    
      mrdel_data(64*512-1 downto 63*512) <= d_rd_data;
      mrdel_empty(63) <= d_rd_data_empty;
      
      mrdel_data(63*512-1 downto 0) <= mrdel_data(64*512-1 downto 512);
      mrdel_empty(62 downto 0) <= mrdel_empty(63 downto 1);

      if (openConnRespReady='1') then
        openConnRespValid<='0';
      end if;

	  if (openConnReqValid='1') then
	  	openConnRespValid<='1';
	  end if;

      if (event_ready='1') then
	event_valid <= '0';
      end if;

      if (waiting/=0) then
	waiting <= waiting-1;
	
      else
	
	if (event_ready='1' and  not endfile(eventfile)) then
	  
	  readline(eventfile, evinline);
	  hread(evinline, evtype);

	  if (evtype/=0) then
	    waiting <= evtype;
	  else
	    readline(eventfile, evinline);
	    hread(evinline, evdata);

	    event_valid <= '1';
	    event_data <= evdata;
	  end if;
	end if;
	
      end if;
    end if;
    
  end process;

  stim_data: process
    file datafile : text is in "../../session-data-in-serv.txt";
    variable datinline : line;
    variable dattype : std_logic_vector(15 downto 0);
    variable datdata : std_logic_Vector(67 downto 0);
    
  begin
    wait until clk'event and clk='1';
    
    
    ticker <= ticker + 1;
    ticker(23 downto 16) <= "00001111";
    
    metaReady <= '0';
    
    cntReady <= cntReady +1;
    cntReady2 <= cntReady2 +1;
        
    if (cntReady<=3) then
    	metaReady <= '1';      	  	
    end if;
    
--    out_ready <= '1';
--    if (cntReady<=1) then
--    	out_ready <= '0';
--    end if;
    
    if (cntReady=4) then
    	cntReady <= (others=>'0');
    end if;
    
    if (cntReady2=10) then
        cntReady2 <= (others=>'0');
    end if;
    
    if (rst='1') then
    
    	cntReady <= (others => '0');
      cntReady2 <= (others => '0');
      
      waiting2 <= (others => '0');
      packet_valid <= '0';
      packet_keep <= (others => '1');
      packet_last(0) <= '0';
      waitLast <= '0';
      
    else

      if (packet_ready='1') then
	packet_valid <= '0';
	packet_last(0) <= '0';
      end if;

      if (waiting2/=0) then
	waiting2 <= waiting2-1;
	
      else
	
	if ((packet_ready='1' or packet_valid='0') and not endfile(datafile)) then
	  	  
	  if (waitLast='0') then 	  	
	  	readline(datafile, datinline);
	  	hread(datinline, dattype);
	  end if;

	  if (dattype/=0 and waitLast='0') then
	    waiting2 <= dattype-1;
	  else
	    readline(datafile, datinline);
	    hread(datinline, datdata);

	    packet_valid <= '1';
	    waitLast <= not datdata(64);
	    
	    for X in 0 to 7 loop
	    	packet_data((7-X)*8+7 downto (7-X)*8) <= datdata(X*8+7 downto X*8);
	    end loop;
	       
	    packet_last(0) <= datdata(64);	    
	  end if;
	end if;
	
      end if;
    end if;
    
  end process;



end;
