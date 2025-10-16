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


entity multes_coyote_hacktoplevel is
port(
      aclk : in std_logic;
      aresetn : in std_logic;
      
      in_pack_tdata : in std_logic_vector (511 downto 0); 
      in_pack_tvalid : in std_logic;
      in_pack_tlast : in std_logic;
      in_pack_tready : out std_logic;  

      in_meta_tdata : in std_logic_vector (511 downto 0); 
      in_meta_tvalid : in std_logic;
      in_meta_tlast : in std_logic;
      in_meta_tready : out std_logic;  

      out_pack_tdata : out std_logic_vector (511 downto 0);
      out_pack_tvalid : out std_logic;
      out_pack_tlast : out  std_logic;
      out_pack_tready : in std_logic;
      
      out_meta_tdata : out std_logic_vector (511 downto 0);
      out_meta_tvalid : out std_logic;
      out_meta_tlast : out  std_logic;
      out_meta_tready : in std_logic;
      
      debug : out std_logic_vector (255 downto 0)
      
);
end multes_coyote_hacktoplevel;

architecture bench of multes_coyote_hacktoplevel is

   --component zookeeper_tcp_top_parallel_nkv
  component muu_TopWrapper_fclk512
  generic (
       IS_SIM : integer := 0;
       USER_BITS : integer := 3;
       HASHTABLE_MEM_SIZE : integer := 16;
       VALUESTORE_MEM_SIZE : integer := 16             
      );
    port (
      aclk : in std_logic;
      aresetn : in std_logic;      
      
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
      m_axis_tx_data_TDATA: out std_logic_vector(511 downto 0);      
      m_axis_tx_data_TLAST: out std_logic_vector(0 downto 0);
      
      m_axis_tx_metadata_TVALID : out std_logic;
      m_axis_tx_metadata_TREADY : in std_logic;
      m_axis_tx_metadata_TDATA: out std_logic_vector(31 downto 0);
      
      s_axis_tx_status_TVALID : in std_logic;
      s_axis_tx_status_TREADY : out std_logic;
      s_axis_tx_status_TDATA : in std_logic_vector(63 downto 0);
      
      s_axis_rx_data_TVALID : in std_logic;
      s_axis_rx_data_TREADY : out std_logic;
      s_axis_rx_data_TDATA : in std_logic_vector(511 downto 0);
      s_axis_rx_data_TLAST: in std_logic_vector(0 downto 0);
      
      s_axis_rx_metadata_TVALID: in std_logic;
      s_axis_rx_metadata_TREADY : out std_logic;
      s_axis_rx_metadata_TDATA: in std_logic_vector(15 downto 0);
      
      
      ht_dramRdData_valid             : in std_logic;
      ht_dramRdData_ready              : out std_logic;
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
      
      upd_dramRdData_valid             : in std_logic;
      upd_dramRdData_ready              : out std_logic;
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
      bmap_wrcmd_ready : in std_logic;
      
      val_to_proc_tdata : out std_logic_vector (511 downto 0);
      val_to_proc_tvalid : out std_logic;
      val_to_proc_tlast  : out std_logic;
      val_to_proc_tready  : in std_logic;

      par_to_proc_tdata : out std_logic_vector (511 downto 0); 
      par_to_proc_tvalid : out std_logic;
      par_to_proc_tlast : out std_logic;
      par_to_proc_tready : in std_logic;  

      val_from_proc_tdata : in std_logic_vector (511 downto 0);
      val_from_proc_tvalid : in std_logic;
      val_from_proc_tlast : in  std_logic;
      val_from_proc_tready : out std_logic;

      par_from_proc_tdata : in std_logic_vector (511 downto 0);
      par_from_proc_tvalid: in std_logic;
      par_from_proc_tlast : in  std_logic;
      par_from_proc_tready : out std_logic;
              

      debug_kvs : out std_logic_vector (255 downto 0)
      
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

  signal rstX : std_logic;
  signal event_valid: std_logic;
  signal event_ready: std_logic;
  signal event_data: std_logic_vector(87 downto 0);
  signal readreq_valid: std_logic;
  signal readreq_ready: std_logic;
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
  signal d_rd_data_ready         : std_logic;
  signal d_rd_data_valid        : std_logic;  
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
  signal d2_rd_data_ready         : std_logic;
  signal d2_rd_data_valid        : std_logic;    
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
      
      signal temp_proc_data :  std_logic_vector (512-1 downto 0);
      signal temp_proc_valid :  std_logic;
      signal temp_proc_ready :  std_logic;
      signal temp_proc_last :  std_logic;
      
      signal temp_par_data :  std_logic_vector (512-1 downto 0);
      signal temp_par_valid :  std_logic;
      signal temp_par_ready :  std_logic;
      signal temp_par_last :  std_logic;
      
      signal debug_signal :  std_logic_vector (255 downto 0);
      
      signal in_pack_lastaux: std_logic_vector (0 downto 0);
      signal out_pack_lastaux : std_logic_vector (0 downto 0);
      
      

begin

  
  --  uut: zookeeper_tcp_top_parallel_nkv
    uut: muu_TopWrapper_fclk512 
    generic map ( IS_SIM => 1, USER_BITS => 3, HASHTABLE_MEM_SIZE => 10, VALUESTORE_MEM_SIZE => 10 )
    port map ( aclk           => aclk,
	       aresetn        => aresetn,	       
	       
	       m_axis_open_connection_TVALID => openConnReqValid,
	       m_axis_open_connection_TREADY =>  '1',
	       s_axis_open_status_TVALID => openConnRespValid,
	       s_axis_open_status_TREADY => openConnRespReady,
	       s_axis_open_status_TDATA => ticker,--"000011110000111100001111",
	       m_axis_close_connection_TREADY => '1',	       
	       m_axis_listen_port_TREADY => '1',
	       s_axis_listen_port_status_TVALID =>  '0',
	       s_axis_listen_port_status_TDATA => (others => '0'),
	       
	       
	       s_axis_notifications_TVALID => in_meta_tvalid,
	       s_axis_notifications_TREADY => in_meta_tready,
	       s_axis_notifications_TDATA => in_meta_tdata(87 downto 0),
	       
	       m_axis_read_package_TVALID => readreq_valid,
	       m_axis_read_package_TREADY => readreq_ready,
	       m_axis_read_package_TDATA => readreq_data,

	       m_axis_tx_data_TVALID => out_pack_tvalid,
               m_axis_tx_data_TREADY => out_pack_tready,
	       m_axis_tx_data_TDATA => out_pack_tdata,
	       m_axis_tx_data_TLAST => out_pack_lastaux,
	       
	       m_axis_tx_metadata_TVALID => out_meta_tvalid,
               m_axis_tx_metadata_TREADY => out_meta_tready,
	       m_axis_tx_metadata_TDATA =>  out_meta_tdata(31 downto 0),

	       s_axis_tx_status_TVALID => '0',
	       s_axis_tx_status_TDATA => (others => '0'),
	       
	       
               s_axis_rx_data_TVALID =>  in_pack_tvalid,
	       s_axis_rx_data_TREADY => in_pack_tready,
	       s_axis_rx_data_TDATA => in_pack_tdata,
	       s_axis_rx_data_TLAST => in_pack_lastaux,

	       s_axis_rx_metadata_TVALID => '0',
	       s_axis_rx_metadata_TDATA => (others => '0'),
	       
	       
          
          ht_dramRdData_data          => d_rd_data,
                ht_dramRdData_valid         => d_rd_data_valid,
                ht_dramRdData_ready          => d_rd_data_ready,
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
          
                upd_dramRdData_data         => d2_rd_data,
                upd_dramRdData_valid        => d2_rd_data_valid,
                upd_dramRdData_ready         => d2_rd_data_ready,
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
      bmap_wrcmd_ready =>bmap_wrcmd_ready,
          
      val_to_proc_tdata => temp_proc_data,           
      val_to_proc_tvalid => temp_proc_valid,                                
val_to_proc_tlast  => temp_proc_last,                       
val_to_proc_tready  => temp_proc_ready,                              
                                                                   
par_to_proc_tdata => temp_par_data,           
par_to_proc_tvalid => temp_par_valid,                                
par_to_proc_tlast => temp_par_last,                              
par_to_proc_tready  => temp_par_ready,                                
                                                                   
val_from_proc_tdata           => temp_proc_data,
val_from_proc_tvalid     => temp_proc_valid,                           
val_from_proc_tlast     => temp_proc_last,                           
val_from_proc_tready      => temp_proc_ready,                        
                                                                   
par_from_proc_tdata     => temp_par_data,      
par_from_proc_tvalid    => temp_par_valid,                            
par_from_proc_tlast      => temp_par_last,                          
par_from_proc_tready     => temp_par_ready,

debug_kvs => debug_signal                           
      
	       );
	       
   mockmem_ht : entity work.kvs_tbDRAMHDLNode
              generic map (
                  DRAM_DATA_WIDTH => 512,
                  DRAM_ADDR_WIDTH => 10
               )
              port map(
                clk                     => aclk,
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
                              DRAM_ADDR_WIDTH => 10
                           )
              port map(
                clk                     => aclk,
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
                                DRAM_ADDR_WIDTH => 10
               )
              port map(
                clk                     => aclk,
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
                                DRAM_ADDR_WIDTH => 10
               )
              port map(
                clk                     => aclk,
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

  d_rd_data_read              <= d_rd_data_ready;
  d_rd_data_valid             <= not d_rd_data_empty;
  

  d2_rd_data_read              <= d2_rd_data_ready;
  d2_rd_data_valid             <= not d2_rd_data_empty;
  
  in_pack_lastaux(0) <= in_pack_tlast;
  out_pack_tlast <= out_pack_lastaux(0);
  debug <= debug_signal;

 main : process(aclk)
  begin
    if (aclk'event and aclk='1') then
    
        rstX <= not aresetn;
    
        if (aresetn='0') then
            readreq_ready <= '0';
        else
            readreq_ready <= '1';
        end if;
    end if;
    
  end process;



end;
