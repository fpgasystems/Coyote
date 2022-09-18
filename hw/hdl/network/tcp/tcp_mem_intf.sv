/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * @brief   TCP memory interface
 */
module tcp_mem_intf #(
    parameter ENABLE = 1,
    parameter UNALIGNED = 0,
    parameter AXI_ID_WIDTH = 1
) (
    input  logic                        aclk,
    input  logic                        aresetn,

    input  logic [63:0]                 addr_offset,

    metaIntf.s                          s_mem_rd_cmd,
    metaIntf.s                          s_mem_wr_cmd,
    metaIntf.m                          m_mem_rd_sts,
    metaIntf.m                          m_mem_wr_sts,
    AXI4S.m                             m_axis_rd_data,
    AXI4S.s                             s_axis_wr_data,

    AXI4.m                              m_axi_mem
);

assign m_axi_awlock = 0;
assign m_axi_arlock = 0;

reg [63:0]  addr_offset_reg;

always @ (posedge aclk) begin
    addr_offset_reg <= addr_offset;
end

/*
 * CLOCK CROSSING
 */

// Prob offset in the DDR
wire [63:0] s_axis_mem_write_cmd_address; 
wire [63:0] s_axis_mem_read_cmd_address;

assign s_axis_mem_write_cmd_address = s_mem_wr_cmd.data[63:0]+addr_offset_reg;
assign s_axis_mem_read_cmd_address  = s_mem_rd_cmd.data[63:0]+addr_offset_reg;

// Command assign
metaIntf #(.STYPE(logic[104-1:0])) axis_to_dm_mem_write_cmd ();
metaIntf #(.STYPE(logic[104-1:0])) axis_to_dm_mem_write_cmd_r ();

assign axis_to_dm_mem_write_cmd.valid = s_mem_wr_cmd.valid;
assign s_mem_wr_cmd.ready = axis_to_dm_mem_write_cmd.ready;
// [103:100] reserved, [99:96] tag, [95:32] address,[31] drr, [30] eof, [29:24] dsa, [23] type, [22:0] btt (bytes to transfer)
assign axis_to_dm_mem_write_cmd.data = {8'h0, s_axis_mem_write_cmd_address, 1'b1, 1'b1, 6'h0, 1'b1, s_mem_wr_cmd.data[64+:23]};

metaIntf #(.STYPE(logic[104-1:0])) axis_to_dm_mem_read_cmd ();
metaIntf #(.STYPE(logic[104-1:0])) axis_to_dm_mem_read_cmd_r ();

assign axis_to_dm_mem_read_cmd.valid = s_mem_rd_cmd.valid;
assign s_mem_rd_cmd.ready = axis_to_dm_mem_read_cmd.ready;
// [103:100] reserved, [99:96] tag, [95:32] address,[31] drr, [30] eof, [29:24] dsa, [23] type, [22:0] btt (bytes to transfer)
assign axis_to_dm_mem_read_cmd.data = {8'h0, s_axis_mem_read_cmd_address, 1'b1, 1'b1, 6'h0, 1'b1, s_mem_rd_cmd.data[64+:23]};

AXI4S #(.AXI4S_DATA_BITS(AXI_DDR_BITS)) axis_wr_data_r();
AXI4S #(.AXI4S_DATA_BITS(AXI_DDR_BITS)) axis_rd_data_r();

reg running;
reg [31:0] exe_cycle;

always @ (posedge aclk) begin
    if (~aresetn) begin
        running <= '0;
        exe_cycle <= '0;
    end
    else begin
        if (running & exe_cycle == 750000000) begin
            running <= 1'b0;
        end
        else if (s_mem_wr_cmd.valid & s_mem_wr_cmd.ready & ~running) begin
            running <= 1'b1;
        end

        if (exe_cycle == 750000000) begin
            exe_cycle <= '0;
        end
        else if (running) begin
            exe_cycle <= exe_cycle + 1'b1;
        end

    end
end

generate
if (ENABLE == 1) begin

// ! No need for a cross here

axis_register_slice_tcp_mem_104 axis_to_dm_mem_write_cmd_slice_inst(
     .aclk(aclk),
     .aresetn(aresetn),
     .s_axis_tvalid(axis_to_dm_mem_write_cmd.valid),
     .s_axis_tready(axis_to_dm_mem_write_cmd.ready),
     .s_axis_tdata(axis_to_dm_mem_write_cmd.data),
     .s_axis_tkeep('1),
     .s_axis_tlast(1),
     .m_axis_tvalid(axis_to_dm_mem_write_cmd_r.valid),
     .m_axis_tready(axis_to_dm_mem_write_cmd_r.ready),
     .m_axis_tdata(axis_to_dm_mem_write_cmd_r.data),
     .m_axis_tkeep(),
     .m_axis_tlast()
);

axis_register_slice_tcp_mem_104 axis_to_dm_mem_read_cmd_slice_inst(
     .aclk(aclk),
     .aresetn(aresetn),
     .s_axis_tvalid(axis_to_dm_mem_read_cmd.valid),
     .s_axis_tready(axis_to_dm_mem_read_cmd.ready),
     .s_axis_tdata(axis_to_dm_mem_read_cmd.data),
     .s_axis_tkeep('1),
     .s_axis_tlast(1),
     .m_axis_tvalid(axis_to_dm_mem_read_cmd_r.valid),
     .m_axis_tready(axis_to_dm_mem_read_cmd_r.ready),
     .m_axis_tdata(axis_to_dm_mem_read_cmd_r.data),
     .m_axis_tkeep(),
     .m_axis_tlast()
);

axis_reg_array #(.N_STAGES(4)) inst_reg_array_mem_write_data (.aclk(aclk), .aresetn(aresetn), .s_axis(s_axis_wr_data), .m_axis(axis_wr_data_r));
axis_reg_array #(.N_STAGES(4)) inst_reg_array_mem_read_data (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_rd_data_r), .m_axis(m_axis_rd_data));

end
else begin
    assign s_axis_wr_data.tready = 1'b1;
    assign m_axis_rd_data.tvalid = 1'b0;
end

endgenerate

/*
 * DATA MOVERS
 */

wire s2mm_error;
wire mm2s_error;

generate
    if (ENABLE == 1) begin
        if (UNALIGNED == 1) begin

axi_datamover_mem_unaligned datamover_mem (
    .m_axi_mm2s_aclk(aclk),// : IN STD_LOGIC;
    .m_axi_mm2s_aresetn(aresetn), //: IN STD_LOGIC;
    .mm2s_err(mm2s_error), //: OUT STD_LOGIC;
    .m_axis_mm2s_cmdsts_aclk(aclk), //: IN STD_LOGIC;
    .m_axis_mm2s_cmdsts_aresetn(aresetn), //: IN STD_LOGIC;
    .s_axis_mm2s_cmd_tvalid(axis_to_dm_mem_read_cmd_r.valid), //: IN STD_LOGIC;
    .s_axis_mm2s_cmd_tready(axis_to_dm_mem_read_cmd_r.ready), //: OUT STD_LOGIC;
    .s_axis_mm2s_cmd_tdata(axis_to_dm_mem_read_cmd_r.data), //: IN STD_LOGIC_VECTOR(103 DOWNTO 0);
    .m_axis_mm2s_sts_tvalid(m_mem_rd_sts.valid), //: OUT STD_LOGIC;
    .m_axis_mm2s_sts_tready(m_mem_rd_sts.ready), //: IN STD_LOGIC;
    .m_axis_mm2s_sts_tdata(m_mem_rd_sts.data), //: OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    .m_axis_mm2s_sts_tkeep(), //: OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    .m_axis_mm2s_sts_tlast(), //: OUT STD_LOGIC;
    .m_axi_mm2s_arid(m_axi_mem.arid), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_mm2s_araddr(m_axi_mem.araddr), //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    .m_axi_mm2s_arlen(m_axi_mem.arlen), //: OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    .m_axi_mm2s_arsize(m_axi_mem.arsize), //: OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    .m_axi_mm2s_arburst(m_axi_mem.arburst), //: OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    .m_axi_mm2s_arprot(m_axi_mem.arprot), //: OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    .m_axi_mm2s_arcache(m_axi_mem.arcache), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_mm2s_aruser(), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_mm2s_arvalid(m_axi_mem.arvalid), //: OUT STD_LOGIC;
    .m_axi_mm2s_arready(m_axi_mem.arready), //: IN STD_LOGIC;
    .m_axi_mm2s_rdata(m_axi_mem.rdata), //: IN STD_LOGIC_VECTOR(511 DOWNTO 0);
    .m_axi_mm2s_rresp(m_axi_mem.rresp), //: IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    .m_axi_mm2s_rlast(m_axi_mem.rlast), //: IN STD_LOGIC;
    .m_axi_mm2s_rvalid(m_axi_mem.rvalid), //: IN STD_LOGIC;
    .m_axi_mm2s_rready(m_axi_mem.rready), //: OUT STD_LOGIC;
    .m_axis_mm2s_tdata(axis_rd_data_r.tdata), //: OUT STD_LOGIC_VECTOR(255 DOWNTO 0);
    .m_axis_mm2s_tkeep(axis_rd_data_r.tkeep), //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    .m_axis_mm2s_tlast(axis_rd_data_r.tlast), //: OUT STD_LOGIC;
    .m_axis_mm2s_tvalid(axis_rd_data_r.tvalid), //: OUT STD_LOGIC;
    .m_axis_mm2s_tready(axis_rd_data_r.tready), //: IN STD_LOGIC;

    .m_axi_s2mm_aclk(aclk), //: IN STD_LOGIC;
    .m_axi_s2mm_aresetn(aresetn), //: IN STD_LOGIC;
    .s2mm_err(s2mm_error), //: OUT STD_LOGIC;
    .m_axis_s2mm_cmdsts_awclk(aclk), //: IN STD_LOGIC;
    .m_axis_s2mm_cmdsts_aresetn(aresetn), //: IN STD_LOGIC;
    .s_axis_s2mm_cmd_tvalid(axis_to_dm_mem_write_cmd_r.valid), //: IN STD_LOGIC;
    .s_axis_s2mm_cmd_tready(axis_to_dm_mem_write_cmd_r.ready), //: OUT STD_LOGIC;
    .s_axis_s2mm_cmd_tdata(axis_to_dm_mem_write_cmd_r.data), //: IN STD_LOGIC_VECTOR(103 DOWNTO 0);
    .m_axis_s2mm_sts_tvalid(m_mem_wr_sts.valid), //: OUT STD_LOGIC;
    .m_axis_s2mm_sts_tready(m_mem_wr_sts.ready), //: IN STD_LOGIC;
    .m_axis_s2mm_sts_tdata(m_mem_wr_sts.data), //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    .m_axis_s2mm_sts_tkeep(), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axis_s2mm_sts_tlast(), //: OUT STD_LOGIC;
    .m_axi_s2mm_awid(m_axi_mem.awid), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_s2mm_awaddr(m_axi_mem.awaddr), //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    .m_axi_s2mm_awlen(m_axi_mem.awlen), //: OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    .m_axi_s2mm_awsize(m_axi_mem.awsize), //: OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    .m_axi_s2mm_awburst(m_axi_mem.awburst), //: OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    .m_axi_s2mm_awprot(m_axi_mem.awprot), //: OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    .m_axi_s2mm_awcache(m_axi_mem.awcache), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_s2mm_awuser(), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_s2mm_awvalid(m_axi_mem.awvalid), //: OUT STD_LOGIC;
    .m_axi_s2mm_awready(m_axi_mem.awready), //: IN STD_LOGIC;
    .m_axi_s2mm_wdata(m_axi_mem.wdata), //: OUT STD_LOGIC_VECTOR(511 DOWNTO 0);
    .m_axi_s2mm_wstrb(m_axi_mem.wstrb), //: OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    .m_axi_s2mm_wlast(m_axi_mem.wlast), //: OUT STD_LOGIC;
    .m_axi_s2mm_wvalid(m_axi_mem.wvalid), //: OUT STD_LOGIC;
    .m_axi_s2mm_wready(m_axi_mem.wready), //: IN STD_LOGIC;
    .m_axi_s2mm_bresp(m_axi_mem.bresp), //: IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    .m_axi_s2mm_bvalid(m_axi_mem.bvalid), //: IN STD_LOGIC;
    .m_axi_s2mm_bready(m_axi_mem.bready), //: OUT STD_LOGIC;
    .s_axis_s2mm_tdata(axis_wr_data_r.tdata), //: IN STD_LOGIC_VECTOR(511 DOWNTO 0);
    .s_axis_s2mm_tkeep(axis_wr_data_r.tkeep), //: IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    .s_axis_s2mm_tlast(axis_wr_data_r.tlast), //: IN STD_LOGIC;
    .s_axis_s2mm_tvalid(axis_wr_data_r.tvalid), //: IN STD_LOGIC;
    .s_axis_s2mm_tready(axis_wr_data_r.tready) //: OUT STD_LOGIC;
);
        end
        else begin

axi_datamover_mem datamover_mem (
    .m_axi_mm2s_aclk(aclk),// : IN STD_LOGIC;
    .m_axi_mm2s_aresetn(aresetn), //: IN STD_LOGIC;
    .mm2s_err(mm2s_error), //: OUT STD_LOGIC;
    .m_axis_mm2s_cmdsts_aclk(aclk), //: IN STD_LOGIC;
    .m_axis_mm2s_cmdsts_aresetn(aresetn), //: IN STD_LOGIC;
    .s_axis_mm2s_cmd_tvalid(axis_to_dm_mem_read_cmd_r.valid), //: IN STD_LOGIC;
    .s_axis_mm2s_cmd_tready(axis_to_dm_mem_read_cmd_r.ready), //: OUT STD_LOGIC;
    .s_axis_mm2s_cmd_tdata(axis_to_dm_mem_read_cmd_r.data), //: IN STD_LOGIC_VECTOR(103 DOWNTO 0);
    .m_axis_mm2s_sts_tvalid(m_mem_rd_sts.valid), //: OUT STD_LOGIC;
    .m_axis_mm2s_sts_tready(m_mem_rd_sts.ready), //: IN STD_LOGIC;
    .m_axis_mm2s_sts_tdata(m_mem_rd_sts.data), //: OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    .m_axis_mm2s_sts_tkeep(), //: OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    .m_axis_mm2s_sts_tlast(), //: OUT STD_LOGIC;
    .m_axi_mm2s_arid(m_axi_mem.arid), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_mm2s_araddr(m_axi_mem.araddr), //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    .m_axi_mm2s_arlen(m_axi_mem.arlen), //: OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    .m_axi_mm2s_arsize(m_axi_mem.arsize), //: OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    .m_axi_mm2s_arburst(m_axi_mem.arburst), //: OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    .m_axi_mm2s_arprot(m_axi_mem.arprot), //: OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    .m_axi_mm2s_arcache(m_axi_mem.arcache), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_mm2s_aruser(), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_mm2s_arvalid(m_axi_mem.arvalid), //: OUT STD_LOGIC;
    .m_axi_mm2s_arready(m_axi_mem.arready), //: IN STD_LOGIC;
    .m_axi_mm2s_rdata(m_axi_mem.rdata), //: IN STD_LOGIC_VECTOR(511 DOWNTO 0);
    .m_axi_mm2s_rresp(m_axi_mem.rresp), //: IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    .m_axi_mm2s_rlast(m_axi_mem.rlast), //: IN STD_LOGIC;
    .m_axi_mm2s_rvalid(m_axi_mem.rvalid), //: IN STD_LOGIC;
    .m_axi_mm2s_rready(m_axi_mem.rready), //: OUT STD_LOGIC;
    .m_axis_mm2s_tdata(axis_rd_data_r.tdata), //: OUT STD_LOGIC_VECTOR(255 DOWNTO 0);
    .m_axis_mm2s_tkeep(axis_rd_data_r.tkeep), //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    .m_axis_mm2s_tlast(axis_rd_data_r.tlast), //: OUT STD_LOGIC;
    .m_axis_mm2s_tvalid(axis_rd_data_r.tvalid), //: OUT STD_LOGIC;
    .m_axis_mm2s_tready(axis_rd_data_r.tready), //: IN STD_LOGIC;

    .m_axi_s2mm_aclk(aclk), //: IN STD_LOGIC;
    .m_axi_s2mm_aresetn(aresetn), //: IN STD_LOGIC;
    .s2mm_err(s2mm_error), //: OUT STD_LOGIC;
    .m_axis_s2mm_cmdsts_awclk(aclk), //: IN STD_LOGIC;
    .m_axis_s2mm_cmdsts_aresetn(aresetn), //: IN STD_LOGIC;
    .s_axis_s2mm_cmd_tvalid(axis_to_dm_mem_write_cmd_r.valid), //: IN STD_LOGIC;
    .s_axis_s2mm_cmd_tready(axis_to_dm_mem_write_cmd_r.ready), //: OUT STD_LOGIC;
    .s_axis_s2mm_cmd_tdata(axis_to_dm_mem_write_cmd_r.data), //: IN STD_LOGIC_VECTOR(103 DOWNTO 0);
    .m_axis_s2mm_sts_tvalid(m_mem_wr_sts.valid), //: OUT STD_LOGIC;
    .m_axis_s2mm_sts_tready(m_mem_wr_sts.ready), //: IN STD_LOGIC;
    .m_axis_s2mm_sts_tdata(m_mem_wr_sts.data), //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    .m_axis_s2mm_sts_tkeep(), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axis_s2mm_sts_tlast(), //: OUT STD_LOGIC;
    .m_axi_s2mm_awid(m_axi_mem.awid), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_s2mm_awaddr(m_axi_mem.awaddr), //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    .m_axi_s2mm_awlen(m_axi_mem.awlen), //: OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    .m_axi_s2mm_awsize(m_axi_mem.awsize), //: OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    .m_axi_s2mm_awburst(m_axi_mem.awburst), //: OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    .m_axi_s2mm_awprot(m_axi_mem.awprot), //: OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    .m_axi_s2mm_awcache(m_axi_mem.awcache), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_s2mm_awuser(), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_s2mm_awvalid(m_axi_mem.awvalid), //: OUT STD_LOGIC;
    .m_axi_s2mm_awready(m_axi_mem.awready), //: IN STD_LOGIC;
    .m_axi_s2mm_wdata(m_axi_mem.wdata), //: OUT STD_LOGIC_VECTOR(511 DOWNTO 0);
    .m_axi_s2mm_wstrb(m_axi_mem.wstrb), //: OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    .m_axi_s2mm_wlast(m_axi_mem.wlast), //: OUT STD_LOGIC;
    .m_axi_s2mm_wvalid(m_axi_mem.wvalid), //: OUT STD_LOGIC;
    .m_axi_s2mm_wready(m_axi_mem.wready), //: IN STD_LOGIC;
    .m_axi_s2mm_bresp(m_axi_mem.bresp), //: IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    .m_axi_s2mm_bvalid(m_axi_mem.bvalid), //: IN STD_LOGIC;
    .m_axi_s2mm_bready(m_axi_mem.bready), //: OUT STD_LOGIC;
    .s_axis_s2mm_tdata(axis_wr_data_r.tdata), //: IN STD_LOGIC_VECTOR(511 DOWNTO 0);
    .s_axis_s2mm_tkeep(axis_wr_data_r.tkeep), //: IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    .s_axis_s2mm_tlast(axis_wr_data_r.tlast), //: IN STD_LOGIC;
    .s_axis_s2mm_tvalid(axis_wr_data_r.tvalid), //: IN STD_LOGIC;
    .s_axis_s2mm_tready(axis_wr_data_r.tready) //: OUT STD_LOGIC;
);
        end
    end
else begin
    assign s_mem_rd_cmd.ready = 1'b1;
    //assign axis_mem_dm_to_cc_read_tvalid = 1'b0;
    assign m_mem_rd_sts.valid = 1'b0;
    assign s_mem_wr_cmd.ready = 1'b1;
    assign m_mem_wr_sts.valid = 1'b0;
    //assign axis_mem_cc_to_dm_write_tready = 1'b1;
end

endgenerate

endmodule