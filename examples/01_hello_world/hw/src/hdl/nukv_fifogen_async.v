//---------------------------------------------------------------------------
//--  Copyright 2015 - 2017 Systems Group, ETH Zurich
//-- 
//--  This hardware module is free software: you can redistribute it and/or
//--  modify it under the terms of the GNU General Public License as published
//--  by the Free Software Foundation, either version 3 of the License, or
//--  (at your option) any later version.
//-- 
//--  This program is distributed in the hope that it will be useful,
//--  but WITHOUT ANY WARRANTY; without even the implied warranty of
//--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//--  GNU General Public License for more details.
//-- 
//--  You should have received a copy of the GNU General Public License
//--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//---------------------------------------------------------------------------


module nukv_fifogen_async #(
    parameter ADDR_BITS=5,      // number of bits of address bus
    parameter DATA_SIZE=16     // number of bits of data bus
) 
(
  // Clock
  input wire         m_axis_clk,
  input wire         s_axis_rst,
  input wire         s_axis_clk,

  input  wire [DATA_SIZE-1:0] s_axis_tdata,
  input  wire         s_axis_tvalid,
  output wire         s_axis_tready,
  output wire         s_axis_talmostfull,


  output wire [DATA_SIZE-1:0] m_axis_tdata,
  output wire        m_axis_tvalid,
  input  wire         m_axis_tready
);

wire s_axis_tfull;
assign s_axis_tready = ~s_axis_tfull;

wire m_axis_tempty;
assign m_axis_tvalid = ~m_axis_tempty;

xpm_fifo_async # (

  .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "block", "distributed", or "ultra";
  .ECC_MODE                  ("no_ecc"),         //string; "no_ecc" or "en_ecc";
  .FIFO_WRITE_DEPTH          (2**ADDR_BITS),             //positive integer
  .WRITE_DATA_WIDTH          (DATA_SIZE),               //positive integer
  .WR_DATA_COUNT_WIDTH       (ADDR_BITS),               //positive integer
  .PROG_FULL_THRESH          ((2**ADDR_BITS)-8),               //positive integer
  .FULL_RESET_VALUE          (0),                //positive integer; 0 or 1
  .USE_ADV_FEATURES          ("0707"),           //string; "0000" to "1F1F"; 
  .READ_MODE                 ("fwft"),            //string; "std" or "fwft";
  .FIFO_READ_LATENCY         (0),                //positive integer;
  .READ_DATA_WIDTH           (DATA_SIZE),               //positive integer
  .RD_DATA_COUNT_WIDTH       (ADDR_BITS),               //positive integer
  .PROG_EMPTY_THRESH         (10),               //positive integer
  .DOUT_RESET_VALUE          ("0"),              //string
  .WAKEUP_TIME               (0),                 //positive integer; 0 or 2;
  .RELATED_CLOCKS(0)        // DECIMAL

) xpm_fifo_sync_inst (

  .sleep            (1'b0),
  .rst              (s_axis_rst),
  .wr_clk           (s_axis_clk),
  .wr_en            (s_axis_tvalid),
  .din              (s_axis_tdata),
  .full             (s_axis_tfull),
  .overflow         (),
  .prog_full        (s_axis_talmostfull),
  .wr_data_count    (),
  .almost_full      (),
  .wr_ack           (),
  .wr_rst_busy      (),
  .rd_clk           (m_axis_clk),
  .rd_en            (m_axis_tready),
  .dout             (m_axis_tdata),
  .empty            (m_axis_tempty),
  .prog_empty       (),
  .rd_data_count    (),
  .almost_empty     (),
  .data_valid       (),
  .underflow        (),
  .rd_rst_busy      (),
  .injectsbiterr    (1'b0),
  .injectdbiterr    (1'b0),
  .sbiterr          (),
  .dbiterr          ()

);


endmodule


