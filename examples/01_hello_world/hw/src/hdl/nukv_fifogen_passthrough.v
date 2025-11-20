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


module nukv_fifogen_passthrough #(
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

assign m_axis_tdata = s_axis_tdata;
assign m_axis_tvalid = s_axis_tvalid;
assign s_axis_tready = m_axis_tready;
assign s_axis_talmostfull = 0;

endmodule