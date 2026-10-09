`timescale 1ns / 1ps
import lynxTypes::*;
// Plain ports around rdma_meta_tx_arbiter (N_REGIONS vFPGAs), so that it synthesises out of context
module synth_top (
    input  logic aclk, aresetn,
    input  logic [N_REGIONS-1:0] s_valid, output logic [N_REGIONS-1:0] s_ready, input dreq_t [N_REGIONS-1:0] s_data,
    output logic m_valid, input logic m_ready, output dreq_t m_data,
    input  logic [N_REGIONS-1:0] rd_tvalid, output logic [N_REGIONS-1:0] rd_tready,
    input  logic [N_REGIONS-1:0][AXI_NET_BITS-1:0] rd_tdata, input logic [N_REGIONS-1:0][AXI_NET_BITS/8-1:0] rd_tkeep,
    input  logic [N_REGIONS-1:0] rd_tlast,
    output logic o_tvalid, input logic o_tready, output logic [AXI_NET_BITS-1:0] o_tdata,
    output logic [AXI_NET_BITS/8-1:0] o_tkeep, output logic o_tlast,
    output logic [N_REGIONS_BITS-1:0] vfid);
    metaIntf #(.STYPE(dreq_t)) s_meta [N_REGIONS] (.*);
    metaIntf #(.STYPE(dreq_t)) m_meta (.*);
    AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) s_axis_rd [N_REGIONS] (.*);
    AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) m_axis_rd (.*);
    for (genvar i = 0; i < N_REGIONS; i++) begin
        assign s_meta[i].valid = s_valid[i]; assign s_ready[i] = s_meta[i].ready; assign s_meta[i].data = s_data[i];
        assign s_axis_rd[i].tvalid = rd_tvalid[i]; assign rd_tready[i] = s_axis_rd[i].tready;
        assign s_axis_rd[i].tdata = rd_tdata[i]; assign s_axis_rd[i].tkeep = rd_tkeep[i]; assign s_axis_rd[i].tlast = rd_tlast[i];
    end
    assign m_valid = m_meta.valid; assign m_meta.ready = m_ready; assign m_data = m_meta.data;
    assign o_tvalid = m_axis_rd.tvalid; assign m_axis_rd.tready = o_tready;
    assign o_tdata = m_axis_rd.tdata; assign o_tkeep = m_axis_rd.tkeep; assign o_tlast = m_axis_rd.tlast;
    rdma_meta_tx_arbiter inst (.aclk(aclk), .aresetn(aresetn), .s_meta(s_meta), .m_meta(m_meta),
                               .s_axis_rd(s_axis_rd), .m_axis_rd(m_axis_rd), .vfid(vfid));
endmodule
