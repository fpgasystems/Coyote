import lynxTypes::*;
`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
  * @brief Host networking slice array
  * 
  * Host Networking Slicing 
  *
  */ 

module host_networking_slice_array_net #(
    parameter integer       N_STAGES = 2
) (
    // Network side 
    AXI4S.m            m_axis_host_tx_n,
    AXI4S.s            s_axis_host_rx_n,

    // Host side 
    AXI4S.s            s_axis_host_tx_u, 
    AXI4S.m            m_axis_host_rx_u,

    // Clock and reset 
    input wire         aclk,
    input wire         aresetn
); 

    // Define all intermediate interfaces between the different slicing stages 
    AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_host_tx_s [N_STAGES+1]();
    AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_host_rx_s [N_STAGES+1]();

    // Slaves 
    `AXIS_ASSIGN(s_axis_host_tx_u, axis_host_tx_s[0])
    `AXIS_ASSIGN(s_axis_host_rx_n, axis_host_rx_s[0])

    // Masters 
    `AXIS_ASSIGN(axis_host_tx_s[N_STAGES], m_axis_host_tx_n)
    `AXIS_ASSIGN(axis_host_rx_s[N_STAGES], m_axis_host_rx_u)

    // Slicing stages 
    for (genvar i = 0; i < N_STAGES; i++) begin
        // TX datapath 
        axis_register_slice_rdma_data_512 inst_host_networking_data_tx_nc(
            .aclk(aclk), 
            .aresetn(aresetn), 
            .s_axis_tvalid(axis_host_tx_s[i].tvalid),
            .s_axis_tready(axis_host_tx_s[i].tready),
            .s_axis_tdata (axis_host_tx_s[i].tdata),
            .s_axis_tkeep (axis_host_tx_s[i].tkeep),
            .s_axis_tlast (axis_host_tx_s[i].tlast),
            .m_axis_tvalid(axis_host_tx_s[i+1].tvalid),
            .m_axis_tready(axis_host_tx_s[i+1].tready),
            .m_axis_tdata (axis_host_tx_s[i+1].tdata),
            .m_axis_tkeep (axis_host_tx_s[i+1].tkeep),
            .m_axis_tlast (axis_host_tx_s[i+1].tlast)
        ); 

        // RX datapath 
        axis_register_slice_rdma_data_512 inst_host_networking_data_rx_nc(
            .aclk(aclk), 
            .aresetn(aresetn), 
            .s_axis_tvalid(axis_host_rx_s[i].tvalid),
            .s_axis_tready(axis_host_rx_s[i].tready),
            .s_axis_tdata (axis_host_rx_s[i].tdata),
            .s_axis_tkeep (axis_host_rx_s[i].tkeep),
            .s_axis_tlast (axis_host_rx_s[i].tlast),
            .m_axis_tvalid(axis_host_rx_s[i+1].tvalid),
            .m_axis_tready(axis_host_rx_s[i+1].tready),
            .m_axis_tdata (axis_host_rx_s[i+1].tdata),
            .m_axis_tkeep (axis_host_rx_s[i+1].tkeep),
            .m_axis_tlast (axis_host_rx_s[i+1].tlast)
        );
    end

endmodule

