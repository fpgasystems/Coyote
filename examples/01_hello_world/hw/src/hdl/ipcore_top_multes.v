`default_nettype none

//(* DowngradeIPIdentifiedWarnings="yes" *)
module ipcore_top_multes
#(
   parameter integer C_S_AXI_CONTROL_ADDR_WIDTH                = 12 ,
  parameter integer C_S_AXI_CONTROL_DATA_WIDTH                = 32 ,
  parameter integer C_S_AXIS_UDP_RX_TDATA_WIDTH               = 512,
  parameter integer C_M_AXIS_UDP_TX_TDATA_WIDTH               = 512,
  parameter integer C_S_AXIS_UDP_RX_META_TDATA_WIDTH          = 256,
  parameter integer C_M_AXIS_UDP_TX_META_TDATA_WIDTH          = 256,
  parameter integer C_M_AXIS_TCP_LISTEN_PORT_TDATA_WIDTH      = 16 ,
  parameter integer C_S_AXIS_TCP_PORT_STATUS_TDATA_WIDTH      = 8  ,
  parameter integer C_M_AXIS_TCP_OPEN_CONNECTION_TDATA_WIDTH  = 64 ,
  parameter integer C_S_AXIS_TCP_OPEN_STATUS_TDATA_WIDTH      = 32 ,
  parameter integer C_M_AXIS_TCP_CLOSE_CONNECTION_TDATA_WIDTH = 16 ,
  parameter integer C_S_AXIS_TCP_NOTIFICATION_TDATA_WIDTH     = 128,
  parameter integer C_M_AXIS_TCP_READ_PKG_TDATA_WIDTH         = 32 ,
  parameter integer C_S_AXIS_TCP_RX_META_TDATA_WIDTH          = 16 ,
  parameter integer C_S_AXIS_TCP_RX_DATA_TDATA_WIDTH          = 512,
  parameter integer C_M_AXIS_TCP_TX_META_TDATA_WIDTH          = 32 ,
  parameter integer C_M_AXIS_TCP_TX_DATA_TDATA_WIDTH          = 512,
  parameter integer C_S_AXIS_TCP_TX_STATUS_TDATA_WIDTH        = 64,

  parameter integer ENABLE_PROCESSING                         = 0

)
(
  input wire      ap_clk,
  input wire      ap_rst_n,

  input  wire                                                   s_axis_udp_rx_tvalid              ,
  output wire                                                   s_axis_udp_rx_tready              ,
  input  wire [C_S_AXIS_UDP_RX_TDATA_WIDTH-1:0]                 s_axis_udp_rx_tdata               ,
  input  wire [C_S_AXIS_UDP_RX_TDATA_WIDTH/8-1:0]               s_axis_udp_rx_tkeep               ,
  input  wire                                                   s_axis_udp_rx_tlast               ,
  // AXI4-Stream (master) interface m_axis_udp_tx
  output wire                                                   m_axis_udp_tx_tvalid              ,
  input  wire                                                   m_axis_udp_tx_tready              ,
  output wire [C_M_AXIS_UDP_TX_TDATA_WIDTH-1:0]                 m_axis_udp_tx_tdata               ,
  output wire [C_M_AXIS_UDP_TX_TDATA_WIDTH/8-1:0]               m_axis_udp_tx_tkeep               ,
  output wire                                                   m_axis_udp_tx_tlast               ,
  // AXI4-Stream (slave) interface s_axis_udp_rx_meta
  input  wire                                                   s_axis_udp_rx_meta_tvalid         ,
  output wire                                                   s_axis_udp_rx_meta_tready         ,
  input  wire [C_S_AXIS_UDP_RX_META_TDATA_WIDTH-1:0]            s_axis_udp_rx_meta_tdata          ,
  input  wire [C_S_AXIS_UDP_RX_META_TDATA_WIDTH/8-1:0]          s_axis_udp_rx_meta_tkeep          ,
  input  wire                                                   s_axis_udp_rx_meta_tlast          ,
  // AXI4-Stream (master) interface m_axis_udp_tx_meta
  output wire                                                   m_axis_udp_tx_meta_tvalid         ,
  input  wire                                                   m_axis_udp_tx_meta_tready         ,
  output wire [C_M_AXIS_UDP_TX_META_TDATA_WIDTH-1:0]            m_axis_udp_tx_meta_tdata          ,
  output wire [C_M_AXIS_UDP_TX_META_TDATA_WIDTH/8-1:0]          m_axis_udp_tx_meta_tkeep          ,
  output wire                                                   m_axis_udp_tx_meta_tlast          ,
  // AXI4-Stream (master) interface m_axis_tcp_listen_port
  output wire                                                   m_axis_tcp_listen_port_tvalid     ,
  input  wire                                                   m_axis_tcp_listen_port_tready     ,
  output wire [C_M_AXIS_TCP_LISTEN_PORT_TDATA_WIDTH-1:0]        m_axis_tcp_listen_port_tdata      ,
  output wire [C_M_AXIS_TCP_LISTEN_PORT_TDATA_WIDTH/8-1:0]      m_axis_tcp_listen_port_tkeep      ,
  output wire                                                   m_axis_tcp_listen_port_tlast      ,
  // AXI4-Stream (slave) interface s_axis_tcp_port_status
  input  wire                                                   s_axis_tcp_port_status_tvalid     ,
  output wire                                                   s_axis_tcp_port_status_tready     ,
  input  wire [C_S_AXIS_TCP_PORT_STATUS_TDATA_WIDTH-1:0]        s_axis_tcp_port_status_tdata      ,
  input  wire                                                   s_axis_tcp_port_status_tlast      ,
  // AXI4-Stream (master) interface m_axis_tcp_open_connection
  output wire                                                   m_axis_tcp_open_connection_tvalid ,
  input  wire                                                   m_axis_tcp_open_connection_tready ,
  output wire [C_M_AXIS_TCP_OPEN_CONNECTION_TDATA_WIDTH-1:0]    m_axis_tcp_open_connection_tdata  ,
  output wire [C_M_AXIS_TCP_OPEN_CONNECTION_TDATA_WIDTH/8-1:0]  m_axis_tcp_open_connection_tkeep  ,
  output wire                                                   m_axis_tcp_open_connection_tlast  ,
  // AXI4-Stream (slave) interface s_axis_tcp_open_status
  input  wire                                                   s_axis_tcp_open_status_tvalid     ,
  output wire                                                   s_axis_tcp_open_status_tready     ,
  input  wire [C_S_AXIS_TCP_OPEN_STATUS_TDATA_WIDTH-1:0]        s_axis_tcp_open_status_tdata      ,
  input  wire [C_S_AXIS_TCP_OPEN_STATUS_TDATA_WIDTH/8-1:0]      s_axis_tcp_open_status_tkeep      ,
  input  wire                                                   s_axis_tcp_open_status_tlast      ,
  // AXI4-Stream (master) interface m_axis_tcp_close_connection
  output wire                                                   m_axis_tcp_close_connection_tvalid,
  input  wire                                                   m_axis_tcp_close_connection_tready,
  output wire [C_M_AXIS_TCP_CLOSE_CONNECTION_TDATA_WIDTH-1:0]   m_axis_tcp_close_connection_tdata ,
  output wire [C_M_AXIS_TCP_CLOSE_CONNECTION_TDATA_WIDTH/8-1:0] m_axis_tcp_close_connection_tkeep ,
  output wire                                                   m_axis_tcp_close_connection_tlast ,
  // AXI4-Stream (slave) interface s_axis_tcp_notification
  input  wire                                                   s_axis_tcp_notification_tvalid    ,
  output wire                                                   s_axis_tcp_notification_tready    ,
  input  wire [C_S_AXIS_TCP_NOTIFICATION_TDATA_WIDTH-1:0]       s_axis_tcp_notification_tdata     ,
  input  wire [C_S_AXIS_TCP_NOTIFICATION_TDATA_WIDTH/8-1:0]     s_axis_tcp_notification_tkeep     ,
  input  wire                                                   s_axis_tcp_notification_tlast     ,
  // AXI4-Stream (master) interface m_axis_tcp_read_pkg
  output wire                                                   m_axis_tcp_read_pkg_tvalid        ,
  input  wire                                                   m_axis_tcp_read_pkg_tready        ,
  output wire [C_M_AXIS_TCP_READ_PKG_TDATA_WIDTH-1:0]           m_axis_tcp_read_pkg_tdata         ,
  output wire [C_M_AXIS_TCP_READ_PKG_TDATA_WIDTH/8-1:0]         m_axis_tcp_read_pkg_tkeep         ,
  output wire                                                   m_axis_tcp_read_pkg_tlast         ,
  // AXI4-Stream (slave) interface s_axis_tcp_rx_meta
  input  wire                                                   s_axis_tcp_rx_meta_tvalid         ,
  output wire                                                   s_axis_tcp_rx_meta_tready         ,
  input  wire [C_S_AXIS_TCP_RX_META_TDATA_WIDTH-1:0]            s_axis_tcp_rx_meta_tdata          ,
  input  wire [C_S_AXIS_TCP_RX_META_TDATA_WIDTH/8-1:0]          s_axis_tcp_rx_meta_tkeep          ,
  input  wire                                                   s_axis_tcp_rx_meta_tlast          ,
  // AXI4-Stream (slave) interface s_axis_tcp_rx_data
  input  wire                                                   s_axis_tcp_rx_data_tvalid         ,
  output wire                                                   s_axis_tcp_rx_data_tready         ,
  input  wire [C_S_AXIS_TCP_RX_DATA_TDATA_WIDTH-1:0]            s_axis_tcp_rx_data_tdata          ,
  input  wire [C_S_AXIS_TCP_RX_DATA_TDATA_WIDTH/8-1:0]          s_axis_tcp_rx_data_tkeep          ,
  input  wire                                                   s_axis_tcp_rx_data_tlast          ,
  // AXI4-Stream (master) interface m_axis_tcp_tx_meta
  output wire                                                   m_axis_tcp_tx_meta_tvalid         ,
  input  wire                                                   m_axis_tcp_tx_meta_tready         ,
  output wire [C_M_AXIS_TCP_TX_META_TDATA_WIDTH-1:0]            m_axis_tcp_tx_meta_tdata          ,
  output wire [C_M_AXIS_TCP_TX_META_TDATA_WIDTH/8-1:0]          m_axis_tcp_tx_meta_tkeep          ,
  output wire                                                   m_axis_tcp_tx_meta_tlast          ,
  // AXI4-Stream (master) interface m_axis_tcp_tx_data
  output wire                                                   m_axis_tcp_tx_data_tvalid         ,
  input  wire                                                   m_axis_tcp_tx_data_tready         ,
  output wire [C_M_AXIS_TCP_TX_DATA_TDATA_WIDTH-1:0]            m_axis_tcp_tx_data_tdata          ,
  output wire [C_M_AXIS_TCP_TX_DATA_TDATA_WIDTH/8-1:0]          m_axis_tcp_tx_data_tkeep          ,
  output wire                                                   m_axis_tcp_tx_data_tlast          ,
  // AXI4-Stream (slave) interface s_axis_tcp_tx_status
  input  wire                                                   s_axis_tcp_tx_status_tvalid       ,
  output wire                                                   s_axis_tcp_tx_status_tready       ,
  input  wire [C_S_AXIS_TCP_TX_STATUS_TDATA_WIDTH-1:0]          s_axis_tcp_tx_status_tdata        ,
  input  wire [C_S_AXIS_TCP_TX_STATUS_TDATA_WIDTH/8-1:0]        s_axis_tcp_tx_status_tkeep        ,
  input  wire                                                   s_axis_tcp_tx_status_tlast        ,


  // AXI4-Lite slave interface
  input  wire                                                   s_axi_control_awvalid             ,
  output wire                                                   s_axi_control_awready             ,
  input  wire [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]                  s_axi_control_awaddr              ,
  input  wire                                                   s_axi_control_wvalid              ,
  output wire                                                   s_axi_control_wready              ,
  input  wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0]                  s_axi_control_wdata               ,
  input  wire [C_S_AXI_CONTROL_DATA_WIDTH/8-1:0]                s_axi_control_wstrb               ,
  input  wire                                                   s_axi_control_arvalid             ,
  output wire                                                   s_axi_control_arready             ,
  input  wire [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]                  s_axi_control_araddr              ,
  output wire                                                   s_axi_control_rvalid              ,
  input  wire                                                   s_axi_control_rready              ,
  output wire [C_S_AXI_CONTROL_DATA_WIDTH-1:0]                  s_axi_control_rdata               ,
  output wire [2-1:0]                                           s_axi_control_rresp               ,
  output wire                                                   s_axi_control_bvalid              ,
  input  wire                                                   s_axi_control_bready              ,
  output wire [2-1:0]                                           s_axi_control_bresp               ,

        // Slave Interface Write Address Ports
        output wire  [3:0]                                 c0_s_axi_awid,
        output wire  [63:0]                                c0_s_axi_awaddr,
        output wire  [7:0]                                 c0_s_axi_awlen,
        output wire  [2:0]                                 c0_s_axi_awsize,
        output wire  [1:0]                                 c0_s_axi_awburst,

        output wire                                        c0_s_axi_awvalid,
        input wire                                        c0_s_axi_awready,
        // Slave Interface Write Data Ports
        output wire  [511:0]              c0_s_axi_wdata,
        output wire  [63:0]               c0_s_axi_wstrb,
        output wire                       c0_s_axi_wlast,
        output wire                       c0_s_axi_wvalid,
        input wire                       c0_s_axi_wready,
        // Slave Interface Write Response Ports
        output wire                       c0_s_axi_bready,
        input wire [3:0]                      c0_s_axi_bid,
        input wire [1:0]                 c0_s_axi_bresp,
        input wire                       c0_s_axi_bvalid,
        // Slave Interface Read Address Ports
        output wire  [3:0]                c0_s_axi_arid,
        output wire  [63:0]          c0_s_axi_araddr,
        output wire  [7:0]                                 c0_s_axi_arlen,
        output wire  [2:0]                                 c0_s_axi_arsize,
        output wire  [1:0]                                 c0_s_axi_arburst,
        output wire                                        c0_s_axi_arvalid,
        input wire                                       c0_s_axi_arready,
        // Slave Interface Read Data Ports
        output wire                                        c0_s_axi_rready,
        input wire [3:0]                c0_s_axi_rid,
        input wire [511:0]              c0_s_axi_rdata,
        input wire [1:0]                                 c0_s_axi_rresp,
        input wire                                       c0_s_axi_rlast,
        input wire                                       c0_s_axi_rvalid,


        // Slave Interface Write Address Ports
        output wire  [3:0]                                 c1_s_axi_awid,
        output wire  [63:0]                                c1_s_axi_awaddr,
        output wire  [7:0]                                 c1_s_axi_awlen,
        output wire  [2:0]                                 c1_s_axi_awsize,
        output wire  [1:0]                                 c1_s_axi_awburst,

        output wire                                        c1_s_axi_awvalid,
        input wire                                        c1_s_axi_awready,
        // Slave Interface Write Data Ports
        output wire  [511:0]              c1_s_axi_wdata,
        output wire  [63:0]               c1_s_axi_wstrb,
        output wire                       c1_s_axi_wlast,
        output wire                       c1_s_axi_wvalid,
        input wire                       c1_s_axi_wready,
        // Slave Interface Write Response Ports
        output wire                       c1_s_axi_bready,
        input wire [3:0]                      c1_s_axi_bid,
        input wire [1:0]                 c1_s_axi_bresp,
        input wire                       c1_s_axi_bvalid,
        // Slave Interface Read Address Ports
        output wire  [3:0]                c1_s_axi_arid,
        output wire  [63:0]          c1_s_axi_araddr,
        output wire  [7:0]                                 c1_s_axi_arlen,
        output wire  [2:0]                                 c1_s_axi_arsize,
        output wire  [1:0]                                 c1_s_axi_arburst,
        output wire                                        c1_s_axi_arvalid,
        input wire                                       c1_s_axi_arready,
        // Slave Interface Read Data Ports
        output wire                                        c1_s_axi_rready,
        input wire [3:0]                c1_s_axi_rid,
        input wire [511:0]              c1_s_axi_rdata,
        input wire [1:0]                                 c1_s_axi_rresp,
        input wire                                       c1_s_axi_rlast,
        input wire                                       c1_s_axi_rvalid,


        // Slave Interface Write Address Ports
        output wire  [3:0]                                 c2_s_axi_awid,
        output wire  [33:0]                                c2_s_axi_awaddr,
        output wire  [7:0]                                 c2_s_axi_awlen,
        output wire  [2:0]                                 c2_s_axi_awsize,
        output wire  [1:0]                                 c2_s_axi_awburst,

        output wire                                        c2_s_axi_awvalid,
        input wire                                        c2_s_axi_awready,
        // Slave Interface Write Data Ports
        output wire  [511:0]              c2_s_axi_wdata,
        output wire  [63:0]               c2_s_axi_wstrb,
        output wire                       c2_s_axi_wlast,
        output wire                       c2_s_axi_wvalid,
        input wire                       c2_s_axi_wready,
        // Slave Interface Write Response Ports
        output wire                       c2_s_axi_bready,
        input wire [3:0]                      c2_s_axi_bid,
        input wire [1:0]                 c2_s_axi_bresp,
        input wire                       c2_s_axi_bvalid,
        // Slave Interface Read Address Ports
        output wire  [3:0]                c2_s_axi_arid,
        output wire  [33:0]          c2_s_axi_araddr,
        output wire  [7:0]                                 c2_s_axi_arlen,
        output wire  [2:0]                                 c2_s_axi_arsize,
        output wire  [1:0]                                 c2_s_axi_arburst,
        output wire                                        c2_s_axi_arvalid,
        input wire                                       c2_s_axi_arready,
        // Slave Interface Read Data Ports
        output wire                                        c2_s_axi_rready,
        input wire [3:0]                c2_s_axi_rid,
        input wire [511:0]              c2_s_axi_rdata,
        input wire [1:0]                                 c2_s_axi_rresp,
        input wire                                       c2_s_axi_rlast,
        input wire                                       c2_s_axi_rvalid,


        // Slave Interface Write Address Ports
        output wire  [3:0]                                 c3_s_axi_awid,
        output wire  [33:0]                                c3_s_axi_awaddr,
        output wire  [7:0]                                 c3_s_axi_awlen,
        output wire  [2:0]                                 c3_s_axi_awsize,
        output wire  [1:0]                                 c3_s_axi_awburst,

        output wire                                        c3_s_axi_awvalid,
        input wire                                        c3_s_axi_awready,
        // Slave Interface Write Data Ports
        output wire  [511:0]              c3_s_axi_wdata,
        output wire  [63:0]               c3_s_axi_wstrb,
        output wire                       c3_s_axi_wlast,
        output wire                       c3_s_axi_wvalid,
        input wire                       c3_s_axi_wready,
        // Slave Interface Write Response Ports
        output wire                       c3_s_axi_bready,
        input wire [3:0]                      c3_s_axi_bid,
        input wire [1:0]                 c3_s_axi_bresp,
        input wire                       c3_s_axi_bvalid,
        // Slave Interface Read Address Ports
        output wire  [3:0]                c3_s_axi_arid,
        output wire  [33:0]          c3_s_axi_araddr,
        output wire  [7:0]                                 c3_s_axi_arlen,
        output wire  [2:0]                                 c3_s_axi_arsize,
        output wire  [1:0]                                 c3_s_axi_arburst,
        output wire                                        c3_s_axi_arvalid,
        input wire                                       c3_s_axi_arready,
        // Slave Interface Read Data Ports
        output wire                                        c3_s_axi_rready,
        input wire [3:0]                c3_s_axi_rid,
        input wire [511:0]              c3_s_axi_rdata,
        input wire [1:0]                                 c3_s_axi_rresp,
        input wire                                       c3_s_axi_rlast,
        input wire                                       c3_s_axi_rvalid



);
  wire uclk;
  wire urst;

  wire ap_start, ap_done, ap_ready, ap_idle, interrupt;
wire ap_start_pulse;
reg ap_start_r;

wire       runExperiment;
reg       finishExperiment;
reg       finishPulse;


  ///////////////////////////////////////////////////////////////////////////////
// Wires and Variables
///////////////////////////////////////////////////////////////////////////////

reg areset ;

// Register and invert reset signal.
always @(posedge ap_clk) begin
  areset <= ~ap_rst_n;
end

assign interrupt = 1'b0;
///////////////////////////////////////////////////////////////////////////////
// User stack
///////////////////////////////////////////////////////////////////////////////

  assign uclk = ap_clk;
  assign urst = areset;

  wire fclk;
  wire frst;

  assign fclk = ap_clk;
  assign frst = areset;


  /* CUT OFF UDP */
  assign s_axis_udp_rx_tready = 1;
  assign s_axis_udp_rx_meta_tready = 1;
  assign m_axis_udp_tx_tvalid = 0;
  assign m_axis_udp_tx_meta_tvalid = 0;
  assign m_axis_udp_tx_meta_tlast = 0;
  assign m_axis_udp_tx_meta_tkeep = 32'hffffffff;


  /**/



   wire [511:0] ht_dramRdData_data;
     wire          ht_dramRdData_valid;
    wire          ht_dramRdData_ready;


    wire [63:0] ht_cmd_dramRdData_data;
    wire        ht_cmd_dramRdData_valid;
     wire        ht_cmd_dramRdData_stall;


    wire [511:0] ht_dramWrData_data;
    wire          ht_dramWrData_valid;
     wire          ht_dramWrData_stall;


    wire [63:0] ht_cmd_dramWrData_data;
    wire        ht_cmd_dramWrData_valid;
     wire        ht_cmd_dramWrData_stall;
     

     
   wire [511:0] upd_dramRdData_data;
   wire          upd_dramRdData_valid;
  wire          upd_dramRdData_ready;

 
  wire [63:0] upd_cmd_dramRdData_data;
  wire        upd_cmd_dramRdData_valid;
   wire        upd_cmd_dramRdData_stall;

 
  wire [511:0] upd_dramWrData_data;
  wire          upd_dramWrData_valid;
   wire          upd_dramWrData_stall;

 
  wire [63:0] upd_cmd_dramWrData_data;
  wire        upd_cmd_dramWrData_valid;
   wire        upd_cmd_dramWrData_stall;    


  wire [63:0] ptr_rdcmd_data;
  wire         ptr_rdcmd_valid;
  wire         ptr_rdcmd_ready;

  wire [512-1:0]  ptr_rd_data;
  wire         ptr_rd_valid;
  wire         ptr_rd_ready; 

  wire [512-1:0] ptr_wr_data;
  wire         ptr_wr_valid;
  wire         ptr_wr_ready;

  wire [63:0] ptr_wrcmd_data;
  wire         ptr_wrcmd_valid;
  wire         ptr_wrcmd_ready;


  wire [63:0] bmap_rdcmd_data;
  wire         bmap_rdcmd_valid;
  wire         bmap_rdcmd_ready;

  wire [512-1:0]  bmap_rd_data;
  wire         bmap_rd_valid;
  wire         bmap_rd_ready; 

  wire [512-1:0] bmap_wr_data;
  wire         bmap_wr_valid;
  wire         bmap_wr_ready;

  wire [63:0] bmap_wrcmd_data;
  wire         bmap_wrcmd_valid;
  wire         bmap_wrcmd_ready;


//convert 34 bit mem address to 64 bit mem address offset by axi pointer
wire [33:0] c0_awaddr, c0_araddr, c1_araddr, c1_awaddr;
wire [33:0] c2_awaddr, c2_araddr, c3_araddr, c3_awaddr;

wire [63:0] axi00_ptr0, axi01_ptr0;
wire [63:0] axi02_ptr0, axi03_ptr0;

reg [63:0] axi00_ptr_r, axi01_ptr_r;
reg [63:0] axi02_ptr_r, axi03_ptr_r;

assign c0_s_axi_awaddr = axi00_ptr_r + c0_awaddr;
assign c0_s_axi_araddr = axi00_ptr_r + c0_araddr;

assign c1_s_axi_awaddr = axi01_ptr_r + c1_awaddr;
assign c1_s_axi_araddr = axi01_ptr_r + c1_araddr;

assign c2_s_axi_awaddr = axi02_ptr_r + c2_awaddr;
assign c2_s_axi_araddr = axi02_ptr_r + c2_araddr;

assign c3_s_axi_awaddr = axi03_ptr_r + c3_awaddr;
assign c3_s_axi_araddr = axi03_ptr_r + c3_araddr;


//DRAM MEM interface


//upd stream interface signals
wire           upd_s_axis_read_cmd_tvalid;
wire          upd_s_axis_read_cmd_tready;
wire[71:0]     upd_s_axis_read_cmd_tdata;
//read status
wire          upd_m_axis_read_sts_tvalid;
wire           upd_m_axis_read_sts_tready;
wire[7:0]     upd_m_axis_read_sts_tdata;
//read stream
wire[511:0]    upd_m_axis_read_tdata;
wire[63:0]     upd_m_axis_read_tkeep;
wire          upd_m_axis_read_tlast;
wire          upd_m_axis_read_tvalid;
wire           upd_m_axis_read_tready;

//write commands
wire           upd_s_axis_write_cmd_tvalid;
wire          upd_s_axis_write_cmd_tready;
wire[71:0]     upd_s_axis_write_cmd_tdata;
//write status
wire          upd_m_axis_write_sts_tvalid;
wire           upd_m_axis_write_sts_tready;
wire[31:0]     upd_m_axis_write_sts_tdata;
//write stream
wire[511:0]     upd_s_axis_write_tdata;
wire[63:0]      upd_s_axis_write_tkeep;
wire           upd_s_axis_write_tlast;
wire           upd_s_axis_write_tvalid;
wire          upd_s_axis_write_tready;

wire[511:0]     upd_s_axis_write_tdata_x;
wire[63:0]      upd_s_axis_write_tkeep_x;
wire           upd_s_axis_write_tlast_x;
wire           upd_s_axis_write_tvalid_x;
wire          upd_s_axis_write_tready_x;

assign m_axis_tcp_open_connection_tkeep = 16'hffff;
assign m_axis_tcp_open_connection_tlast = 1;

assign m_axis_tcp_close_connection_tkeep = 16'hffff;
assign m_axis_tcp_close_connection_tlast = 1;

assign m_axis_tcp_listen_port_tkeep = 16'hffff;
assign m_axis_tcp_listen_port_tlast = 1;

assign m_axis_tcp_read_pkg_tkeep = 16'hffff;
assign m_axis_tcp_read_pkg_tlast = 1;

assign m_axis_tcp_tx_meta_tkeep = 16'hffff;
assign m_axis_tcp_tx_meta_tlast = 1;

assign m_axis_tcp_tx_data_tkeep = 64'hffffffffffffffff;


wire [512-1:0]  val_to_proc_tdata;
wire         val_to_proc_tvalid;
wire         val_to_proc_tlast;
wire         val_to_proc_tready;

wire [512-1:0]  par_to_proc_tdata;
wire         par_to_proc_tvalid;
wire         par_to_proc_tlast;
wire         par_to_proc_tready;

wire [512-1:0]  val_from_proc_tdata;
wire         val_from_proc_tvalid;
wire         val_from_proc_tlast;
wire         val_from_proc_tready;

wire [0:0]  par_from_proc_tdata;
wire         par_from_proc_tvalid;
wire         par_from_proc_tlast;
wire         par_from_proc_tready;


ipcore_user_processing processing_core (
  .aclk(uclk),
  .aresetn(~urst),
  
  .in_word_tdata(val_to_proc_tdata),
  .in_word_tvalid(val_to_proc_tvalid),
  .in_word_tlast(val_to_proc_tlast),
  .in_word_tready(val_to_proc_tready),

  .parameter_tdata(par_to_proc_tdata),
  .parameter_tvalid(par_to_proc_tvalid),
  .parameter_tlast(par_to_proc_tlast),
  .parameter_tready(par_to_proc_tready),

  .out_word_tdata(val_from_proc_tdata),
  .out_word_tvalid(val_from_proc_tvalid),
  .out_word_tlast(val_from_proc_tlast),
  .out_word_tready(val_from_proc_tready),

  .drop_decision_tdata(par_from_proc_tdata),
  .drop_decision_tvalid(par_from_proc_tvalid),
  .drop_decision_tlast(par_from_proc_tlast),
  .drop_decision_tready(par_from_proc_tready)

);

muu_TopWrapper_fclk512 # (
  .HASHTABLE_MEM_SIZE(22), //2^22 * 64B = 256MB
  .VALUESTORE_MEM_SIZE(22)
  ) multiuser_kvs_top  (

  .m_axis_open_connection_TVALID(m_axis_tcp_open_connection_tvalid),
  .m_axis_open_connection_TDATA(m_axis_tcp_open_connection_tdata),
  .m_axis_open_connection_TREADY(m_axis_tcp_open_connection_tready),
  .m_axis_close_connection_TVALID(m_axis_tcp_close_connection_tvalid),
  .m_axis_close_connection_TDATA(m_axis_tcp_close_connection_tdata),
  .m_axis_close_connection_TREADY(m_axis_tcp_close_connection_tready),
  .m_axis_listen_port_TVALID(m_axis_tcp_listen_port_tvalid),                // output wire m_axis_listen_port_TVALID
  .m_axis_listen_port_TREADY(m_axis_tcp_listen_port_tready),                // input wire m_axis_listen_port_TREADY
  .m_axis_listen_port_TDATA(m_axis_tcp_listen_port_tdata),                  // output wire [15 : 0] m_axis_listen_port_TDATA
  .m_axis_read_package_TVALID(m_axis_tcp_read_pkg_tvalid),              // output wire m_axis_read_package_TVALID
  .m_axis_read_package_TREADY(m_axis_tcp_read_pkg_tready),              // input wire m_axis_read_package_TREADY
  .m_axis_read_package_TDATA(m_axis_tcp_read_pkg_tdata),                // output wire [31 : 0] m_axis_read_package_TDATA
  .m_axis_tx_data_TVALID(m_axis_tcp_tx_data_tvalid),                        // output wire m_axis_tx_data_TVALID
  .m_axis_tx_data_TREADY(m_axis_tcp_tx_data_tready),                        // input wire m_axis_tx_data_TREADY
  .m_axis_tx_data_TDATA(m_axis_tcp_tx_data_tdata),                          // output wire [63 : 0] m_axis_tx_data_TDATA
  //.m_axis_tx_data_TKEEP(m_axis_tcp_tx_data_tkeep),                          // output wire [7 : 0] m_axis_tx_data_TKEEP
  .m_axis_tx_data_TLAST(m_axis_tcp_tx_data_tlast),                          // output wire [0 : 0] m_axis_tx_data_TLAST
  .m_axis_tx_metadata_TVALID(m_axis_tcp_tx_meta_tvalid),                // output wire m_axis_tx_metadata_TVALID
  .m_axis_tx_metadata_TREADY(m_axis_tcp_tx_meta_tready),                // input wire m_axis_tx_metadata_TREADY
  .m_axis_tx_metadata_TDATA(m_axis_tcp_tx_meta_tdata),                  // output wire [15 : 0] m_axis_tx_metadata_TDATA
  .s_axis_listen_port_status_TVALID(s_axis_tcp_port_status_tvalid),  // input wire s_axis_listen_port_status_TVALID
  .s_axis_listen_port_status_TREADY(s_axis_tcp_port_status_tready),  // output wire s_axis_listen_port_status_TREADY
  .s_axis_listen_port_status_TDATA(s_axis_tcp_port_status_tdata),    // input wire [7 : 0] s_axis_listen_port_status_TDATA
  .s_axis_open_status_TVALID(s_axis_tcp_open_status_tvalid),
  .s_axis_open_status_TDATA(s_axis_tcp_open_status_tdata),
  .s_axis_open_status_TREADY(s_axis_tcp_open_status_tready),
  .s_axis_notifications_TVALID(s_axis_tcp_notification_tvalid),            // input wire s_axis_notifications_TVALID
  .s_axis_notifications_TREADY(s_axis_tcp_notification_tready),            // output wire s_axis_notifications_TREADY
  .s_axis_notifications_TDATA(s_axis_tcp_notification_tdata),              // input wire [87 : 0] s_axis_notifications_TDATA
  .s_axis_rx_data_TVALID(s_axis_tcp_rx_data_tvalid),                        // input wire s_axis_rx_data_TVALID
  .s_axis_rx_data_TREADY(s_axis_tcp_rx_data_tready),                        // output wire s_axis_rx_data_TREADY
  .s_axis_rx_data_TDATA(s_axis_tcp_rx_data_tdata),                          // input wire [63 : 0] s_axis_rx_data_TDATA
  //.s_axis_rx_data_TKEEP(s_axis_tcp_rx_data_tkeep),                          // input wire [7 : 0] s_axis_rx_data_TKEEP
  .s_axis_rx_data_TLAST(s_axis_tcp_rx_data_tlast),                          // input wire [0 : 0] s_axis_rx_data_TLAST
  .s_axis_rx_metadata_TVALID(s_axis_tcp_rx_meta_tvalid),                // input wire s_axis_rx_metadata_TVALID
  .s_axis_rx_metadata_TREADY(s_axis_tcp_rx_meta_tready),                // output wire s_axis_rx_metadata_TREADY
  .s_axis_rx_metadata_TDATA(s_axis_tcp_rx_meta_tdata),                  // input wire [15 : 0] s_axis_rx_metadata_TDATA
  .s_axis_tx_status_TVALID(s_axis_tcp_tx_status_tvalid),                    // input wire s_axis_tx_status_TVALID
  .s_axis_tx_status_TREADY(s_axis_tcp_tx_status_tready),                    // output wire s_axis_tx_status_TREADY
  .s_axis_tx_status_TDATA(s_axis_tcp_tx_status_tdata),                      // input wire [23 : 0] s_axis_tx_status_TDATA


  
  .ht_dramRdData_data(ht_dramRdData_data),
  .ht_dramRdData_valid(ht_dramRdData_valid),
  .ht_dramRdData_ready(ht_dramRdData_ready),
  
  .ht_cmd_dramRdData_data(ht_cmd_dramRdData_data),
  .ht_cmd_dramRdData_valid(ht_cmd_dramRdData_valid),
  .ht_cmd_dramRdData_stall(ht_cmd_dramRdData_stall),

  .ht_dramWrData_data(ht_dramWrData_data),
  .ht_dramWrData_valid(ht_dramWrData_valid),
  .ht_dramWrData_stall(ht_dramWrData_stall),
  
  .ht_cmd_dramWrData_data(ht_cmd_dramWrData_data),
  .ht_cmd_dramWrData_valid(ht_cmd_dramWrData_valid),
  .ht_cmd_dramWrData_stall(ht_cmd_dramWrData_stall),  
  
  // Update DRAM Connection  
  .upd_dramRdData_data(upd_dramRdData_data),
  .upd_dramRdData_valid(upd_dramRdData_valid),
  .upd_dramRdData_ready(upd_dramRdData_ready),
  
  .upd_cmd_dramRdData_data(upd_cmd_dramRdData_data),
  .upd_cmd_dramRdData_valid(upd_cmd_dramRdData_valid),
  .upd_cmd_dramRdData_stall(upd_cmd_dramRdData_stall),
  
  .upd_dramWrData_data(upd_dramWrData_data),
  .upd_dramWrData_valid(upd_dramWrData_valid),
  .upd_dramWrData_stall(upd_dramWrData_stall),

  .upd_cmd_dramWrData_data(upd_cmd_dramWrData_data),
  .upd_cmd_dramWrData_valid(upd_cmd_dramWrData_valid),
  .upd_cmd_dramWrData_stall(upd_cmd_dramWrData_stall),  

  .ptr_rdcmd_data(ptr_rdcmd_data),
  .ptr_rdcmd_valid(ptr_rdcmd_valid),
  .ptr_rdcmd_ready(ptr_rdcmd_ready),

  .ptr_rd_data(ptr_rd_data),
  .ptr_rd_valid(ptr_rd_valid),
  .ptr_rd_ready(ptr_rd_ready),  

  .ptr_wr_data(ptr_wr_data),
  .ptr_wr_valid(ptr_wr_valid),
  .ptr_wr_ready(ptr_wr_ready),

  .ptr_wrcmd_data(ptr_wrcmd_data),
  .ptr_wrcmd_valid(ptr_wrcmd_valid),
  .ptr_wrcmd_ready(ptr_wrcmd_ready),


  .bmap_rdcmd_data(bmap_rdcmd_data),
  .bmap_rdcmd_valid(bmap_rdcmd_valid),
  .bmap_rdcmd_ready(bmap_rdcmd_ready),

  .bmap_rd_data(bmap_rd_data),
  .bmap_rd_valid(bmap_rd_valid),
  .bmap_rd_ready(bmap_rd_ready),  

  .bmap_wr_data(bmap_wr_data),
  .bmap_wr_valid(bmap_wr_valid),
  .bmap_wr_ready(bmap_wr_ready),

  .bmap_wrcmd_data(bmap_wrcmd_data),
  .bmap_wrcmd_valid(bmap_wrcmd_valid),
  .bmap_wrcmd_ready(bmap_wrcmd_ready), 

  .debug_kvs                 (m_axis_udp_tx_meta_tdata),
  

  .val_to_proc_tdata(val_to_proc_tdata),
  .val_to_proc_tvalid(val_to_proc_tvalid),
  .val_to_proc_tlast(val_to_proc_tlast),
  .val_to_proc_tready(val_to_proc_tready),

  .par_to_proc_tdata(par_to_proc_tdata),
  .par_to_proc_tvalid(par_to_proc_tvalid),
  .par_to_proc_tlast(par_to_proc_tlast),
  .par_to_proc_tready(par_to_proc_tready),

  .val_from_proc_tdata(val_from_proc_tdata),
  .val_from_proc_tvalid(val_from_proc_tvalid),
  .val_from_proc_tlast(val_from_proc_tlast),
  .val_from_proc_tready(val_from_proc_tready),

  .par_from_proc_tdata(par_from_proc_tdata),
  .par_from_proc_tvalid(par_from_proc_tvalid),
  .par_from_proc_tlast(par_from_proc_tlast),
  .par_from_proc_tready(par_from_proc_tready),

  //.fclk(fclk),
  
  .aclk(uclk),                                                          // input wire aclk
  .aresetn(~urst)                                                    // input wire aresetn
);


/*
 * TCP DDR Memory Interface
 */
muu_memory_datamovers #(
    .HASHTABLE_MEM_SIZE(21), 
    .VALUESTORE_MEM_SIZE(21)
  )mem_inf_inst(

.sys_rst_n(~urst),
.sys_clk(uclk),

.user_clk(uclk),
.user_rst_n(~urst),

  // HashTable DRAM Connection

  .ht_dramRdData_data(ht_dramRdData_data),
  .ht_dramRdData_valid(ht_dramRdData_valid),
  .ht_dramRdData_ready(ht_dramRdData_ready),
  
  .ht_cmd_dramRdData_data(ht_cmd_dramRdData_data),
  .ht_cmd_dramRdData_valid(ht_cmd_dramRdData_valid),
  .ht_cmd_dramRdData_stall(ht_cmd_dramRdData_stall),

  .ht_dramWrData_data(ht_dramWrData_data),
  .ht_dramWrData_valid(ht_dramWrData_valid),
  .ht_dramWrData_stall(ht_dramWrData_stall),
  
  .ht_cmd_dramWrData_data(ht_cmd_dramWrData_data),
  .ht_cmd_dramWrData_valid(ht_cmd_dramWrData_valid),
  .ht_cmd_dramWrData_stall(ht_cmd_dramWrData_stall),
  
  .upd_dramRdData_data(upd_dramRdData_data),
  .upd_dramRdData_valid(upd_dramRdData_valid),
  .upd_dramRdData_ready(upd_dramRdData_ready),
  
  .upd_cmd_dramRdData_data(upd_cmd_dramRdData_data),
  .upd_cmd_dramRdData_valid(upd_cmd_dramRdData_valid),
  .upd_cmd_dramRdData_stall(upd_cmd_dramRdData_stall),
  
  .upd_dramWrData_data(upd_dramWrData_data),
  .upd_dramWrData_valid(upd_dramWrData_valid),
  .upd_dramWrData_stall(upd_dramWrData_stall),

  .upd_cmd_dramWrData_data(upd_cmd_dramWrData_data),
  .upd_cmd_dramWrData_valid(upd_cmd_dramWrData_valid),
  .upd_cmd_dramWrData_stall(upd_cmd_dramWrData_stall), 
  
   .ptr_rdcmd_data(ptr_rdcmd_data),
   .ptr_rdcmd_valid(ptr_rdcmd_valid),
   .ptr_rdcmd_ready(ptr_rdcmd_ready),
 
   .ptr_rd_data(ptr_rd_data),
   .ptr_rd_valid(ptr_rd_valid),
   .ptr_rd_ready(ptr_rd_ready),  
 
   .ptr_wr_data(ptr_wr_data),
   .ptr_wr_valid(ptr_wr_valid),
   .ptr_wr_ready(ptr_wr_ready),
 
   .ptr_wrcmd_data(ptr_wrcmd_data),
   .ptr_wrcmd_valid(ptr_wrcmd_valid),
   .ptr_wrcmd_ready(ptr_wrcmd_ready),
 
 
   .bmap_rdcmd_data(bmap_rdcmd_data),
   .bmap_rdcmd_valid(bmap_rdcmd_valid),
   .bmap_rdcmd_ready(bmap_rdcmd_ready),
 
   .bmap_rd_data(bmap_rd_data),
   .bmap_rd_valid(bmap_rd_valid),
   .bmap_rd_ready(bmap_rd_ready),  
 
   .bmap_wr_data(bmap_wr_data),
   .bmap_wr_valid(bmap_wr_valid),
   .bmap_wr_ready(bmap_wr_ready),
 
   .bmap_wrcmd_data(bmap_wrcmd_data),
   .bmap_wrcmd_valid(bmap_wrcmd_valid),
   .bmap_wrcmd_ready(bmap_wrcmd_ready),


  .c0_s_axi_awid(c0_s_axi_awid),
  .c0_s_axi_awaddr(c0_awaddr),
  .c0_s_axi_awlen(c0_s_axi_awlen),
  .c0_s_axi_awsize(c0_s_axi_awsize),
  .c0_s_axi_awburst(c0_s_axi_awburst),

  .c0_s_axi_awvalid(c0_s_axi_awvalid),
  .c0_s_axi_awready(c0_s_axi_awready),        
  .c0_s_axi_wdata(c0_s_axi_wdata),
  .c0_s_axi_wstrb(c0_s_axi_wstrb),
  .c0_s_axi_wlast(c0_s_axi_wlast),
  .c0_s_axi_wvalid(c0_s_axi_wvalid),
  .c0_s_axi_wready(c0_s_axi_wready),
  .c0_s_axi_bready(c0_s_axi_bready),
  .c0_s_axi_bid(c0_s_axi_bid),
  .c0_s_axi_bresp(c0_s_axi_bresp),
  .c0_s_axi_bvalid(c0_s_axi_bvalid),
  
  .c0_s_axi_arid(c0_s_axi_arid),
  .c0_s_axi_araddr(c0_araddr),
  .c0_s_axi_arlen(c0_s_axi_arlen),
  .c0_s_axi_arsize(c0_s_axi_arsize),
  .c0_s_axi_arburst(c0_s_axi_arburst),
  .c0_s_axi_arvalid(c0_s_axi_arvalid),
  .c0_s_axi_arready(c0_s_axi_arready),
  
  .c0_s_axi_rready(c0_s_axi_rready),
  .c0_s_axi_rid(c0_s_axi_rid),
  .c0_s_axi_rdata(c0_s_axi_rdata),
  .c0_s_axi_rresp(c0_s_axi_rresp),
  .c0_s_axi_rlast(c0_s_axi_rlast),
  .c0_s_axi_rvalid(c0_s_axi_rvalid),



  .c1_s_axi_awid(c1_s_axi_awid),
  .c1_s_axi_awaddr(c1_awaddr),
  .c1_s_axi_awlen(c1_s_axi_awlen),
  .c1_s_axi_awsize(c1_s_axi_awsize),
  .c1_s_axi_awburst(c1_s_axi_awburst),

  .c1_s_axi_awvalid(c1_s_axi_awvalid),
  .c1_s_axi_awready(c1_s_axi_awready),        
  .c1_s_axi_wdata(c1_s_axi_wdata),
  .c1_s_axi_wstrb(c1_s_axi_wstrb),
  .c1_s_axi_wlast(c1_s_axi_wlast),
  .c1_s_axi_wvalid(c1_s_axi_wvalid),
  .c1_s_axi_wready(c1_s_axi_wready),
  .c1_s_axi_bready(c1_s_axi_bready),
  .c1_s_axi_bid(c1_s_axi_bid),
  .c1_s_axi_bresp(c1_s_axi_bresp),
  .c1_s_axi_bvalid(c1_s_axi_bvalid),
  
  .c1_s_axi_arid(c1_s_axi_arid),
  .c1_s_axi_araddr(c1_araddr),
  .c1_s_axi_arlen(c1_s_axi_arlen),
  .c1_s_axi_arsize(c1_s_axi_arsize),
  .c1_s_axi_arburst(c1_s_axi_arburst),
  .c1_s_axi_arvalid(c1_s_axi_arvalid),
  .c1_s_axi_arready(c1_s_axi_arready),
  
  .c1_s_axi_rready(c1_s_axi_rready),
  .c1_s_axi_rid(c1_s_axi_rid),
  .c1_s_axi_rdata(c1_s_axi_rdata),
  .c1_s_axi_rresp(c1_s_axi_rresp),
  .c1_s_axi_rlast(c1_s_axi_rlast),
  .c1_s_axi_rvalid(c1_s_axi_rvalid),


  .c2_s_axi_awid(c2_s_axi_awid),
  .c2_s_axi_awaddr(c2_awaddr),
  .c2_s_axi_awlen(c2_s_axi_awlen),
  .c2_s_axi_awsize(c2_s_axi_awsize),
  .c2_s_axi_awburst(c2_s_axi_awburst),

  .c2_s_axi_awvalid(c2_s_axi_awvalid),
  .c2_s_axi_awready(c2_s_axi_awready),        
  .c2_s_axi_wdata(c2_s_axi_wdata),
  .c2_s_axi_wstrb(c2_s_axi_wstrb),
  .c2_s_axi_wlast(c2_s_axi_wlast),
  .c2_s_axi_wvalid(c2_s_axi_wvalid),
  .c2_s_axi_wready(c2_s_axi_wready),
  .c2_s_axi_bready(c2_s_axi_bready),
  .c2_s_axi_bid(c2_s_axi_bid),
  .c2_s_axi_bresp(c2_s_axi_bresp),
  .c2_s_axi_bvalid(c2_s_axi_bvalid),
  
  .c2_s_axi_arid(c2_s_axi_arid),
  .c2_s_axi_araddr(c2_araddr),
  .c2_s_axi_arlen(c2_s_axi_arlen),
  .c2_s_axi_arsize(c2_s_axi_arsize),
  .c2_s_axi_arburst(c2_s_axi_arburst),
  .c2_s_axi_arvalid(c2_s_axi_arvalid),
  .c2_s_axi_arready(c2_s_axi_arready),
  
  .c2_s_axi_rready(c2_s_axi_rready),
  .c2_s_axi_rid(c2_s_axi_rid),
  .c2_s_axi_rdata(c2_s_axi_rdata),
  .c2_s_axi_rresp(c2_s_axi_rresp),
  .c2_s_axi_rlast(c2_s_axi_rlast),
  .c2_s_axi_rvalid(c2_s_axi_rvalid),



  .c3_s_axi_awid(c3_s_axi_awid),
  .c3_s_axi_awaddr(c3_awaddr),
  .c3_s_axi_awlen(c3_s_axi_awlen),
  .c3_s_axi_awsize(c3_s_axi_awsize),
  .c3_s_axi_awburst(c3_s_axi_awburst),

  .c3_s_axi_awvalid(c3_s_axi_awvalid),
  .c3_s_axi_awready(c3_s_axi_awready),        
  .c3_s_axi_wdata(c3_s_axi_wdata),
  .c3_s_axi_wstrb(c3_s_axi_wstrb),
  .c3_s_axi_wlast(c3_s_axi_wlast),
  .c3_s_axi_wvalid(c3_s_axi_wvalid),
  .c3_s_axi_wready(c3_s_axi_wready),
  .c3_s_axi_bready(c3_s_axi_bready),
  .c3_s_axi_bid(c3_s_axi_bid),
  .c3_s_axi_bresp(c3_s_axi_bresp),
  .c3_s_axi_bvalid(c3_s_axi_bvalid),
  
  .c3_s_axi_arid(c3_s_axi_arid),
  .c3_s_axi_araddr(c3_araddr),
  .c3_s_axi_arlen(c3_s_axi_arlen),
  .c3_s_axi_arsize(c3_s_axi_arsize),
  .c3_s_axi_arburst(c3_s_axi_arburst),
  .c3_s_axi_arvalid(c3_s_axi_arvalid),
  .c3_s_axi_arready(c3_s_axi_arready),
  
  .c3_s_axi_rready(c3_s_axi_rready),
  .c3_s_axi_rid(c3_s_axi_rid),
  .c3_s_axi_rdata(c3_s_axi_rdata),
  .c3_s_axi_rresp(c3_s_axi_rresp),
  .c3_s_axi_rlast(c3_s_axi_rlast),
  .c3_s_axi_rvalid(c3_s_axi_rvalid)

);

// create pulse when ap_start transitions to 1
always @(posedge ap_clk) begin
  begin
    ap_start_r <= ap_start;
  end
end

assign ap_start_pulse = ap_start & ~ap_start_r;

reg[63:0] countDown;

wire [31:0] useConn, useIpAddr, pkgWordCount, basePort ,baseIpAddress;

wire[31:0] timeInSeconds, dualMode, packetGap;
wire[63:0] timeInCycles;

// ap_idle is asserted when done is asserted, it is de-asserted when ap_start_pulse
// is asserted
always @(posedge ap_clk) begin
   
  if (~ap_rst_n) begin
    finishExperiment <= 1;
    countDown <= 0;
    axi00_ptr_r <= 0;
    axi01_ptr_r <= 0;
     axi02_ptr_r <= 0;
    axi03_ptr_r <= 0;
  end
  else begin

    if (ap_start_pulse==1) begin
      countDown <= timeInCycles;
      finishExperiment <= 0;
      axi00_ptr_r <= axi00_ptr0;
      axi01_ptr_r <= axi01_ptr0;
      axi02_ptr_r <= axi02_ptr0;
      axi03_ptr_r <= axi03_ptr0;

    end else begin      
  
      if (countDown==0) begin
        countDown <= 0;
        finishExperiment <= 1;

        if (finishExperiment==0) begin
          finishPulse <= 1;
        end else begin
          finishPulse <= 0;
        end
  
      end else begin
        countDown <= countDown-1;
      end
    end
  end
end

assign ap_idle = finishExperiment;

// Done logic

assign ap_done = finishPulse;

// Ready Logic (non-pipelined case)
assign ap_ready = ap_done;




user_krnl_control_s_axi #(
  .C_S_AXI_ADDR_WIDTH ( C_S_AXI_CONTROL_ADDR_WIDTH ),
  .C_S_AXI_DATA_WIDTH ( C_S_AXI_CONTROL_DATA_WIDTH )
)
inst_control_s_axi (
  .ACLK                   ( ap_clk                 ),
  .ARESET                 ( ~ap_rst_n              ),
  .ACLK_EN                ( 1'b1                   ),
  .AWVALID                ( s_axi_control_awvalid  ), 
  .AWREADY                ( s_axi_control_awready  ),
  .AWADDR                 ( s_axi_control_awaddr   ),
  .WVALID                 ( s_axi_control_wvalid   ),
  .WREADY                 ( s_axi_control_wready   ),
  .WDATA                  ( s_axi_control_wdata    ),
  .WSTRB                  ( s_axi_control_wstrb    ),
  .ARVALID                ( s_axi_control_arvalid  ),
  .ARREADY                ( s_axi_control_arready  ),
  .ARADDR                 ( s_axi_control_araddr   ),
  .RVALID                 ( s_axi_control_rvalid   ),
  .RREADY                 ( s_axi_control_rready   ),
  .RDATA                  ( s_axi_control_rdata    ),
  .RRESP                  ( s_axi_control_rresp    ),
  .BVALID                 ( s_axi_control_bvalid   ),
  .BREADY                 ( s_axi_control_bready   ),
  .BRESP                  ( s_axi_control_bresp    ),
  .interrupt              ( interrupt              ),
  .ap_start               ( ap_start               ),
  .ap_done                ( ap_done                ),
  .ap_ready               ( ap_ready               ),
  .ap_idle                ( ap_idle                ),
  .runForCycles           ( timeInCycles      ),//64 bit
  .axi00_ptr0             ( axi00_ptr0 ),
  .axi01_ptr0             ( axi01_ptr0 ),
  .axi02_ptr0             ( axi02_ptr0 ),
  .axi03_ptr0             ( axi03_ptr0 )
  
);



endmodule
