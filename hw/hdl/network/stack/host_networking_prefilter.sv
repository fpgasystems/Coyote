`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * @brief   Host Networking Pre-Filter: Let's everything through except for RoCE & TCP (if configured for FPGA-offload)
 *
 * Filter and select packets basing on given configuration
 */
module host_networking_prefilter (
    input wire nclk, 
    input wire nresetn, 

    // Data streams for host networking 
    AXI4S.s s_axis_rx, 
    AXI4S.m m_axis_rx, 

    // Data stream for offloaded networking 
    AXI4S.m m_axis_offloaded_rx
);

    // Flags for filtering out RoCE and TCP packets 
    logic rx_ipv4; 
    logic rx_ipv4_udp; 
    logic rx_ipv4_tcp; 
    logic rx_ipv4_udp_roce; 

    // Constant calculation of the flags based on the incoming traffic 
    always_comb begin 
        rx_ipv4 = {s_axis_rx.tdata[12*8+7:12*8], s_axis_rx.tdata[13*8+7:13*8]} == 16'h0800;
        rx_ipv4_udp = rx_ipv4 && s_axis_rx.tdata[23*8+7:23*8] == 8'h11;
        rx_ipv4_tcp = rx_ipv4 & s_axis_rx.tdata[23*8+7:23*8] == 8'h06;
        rx_ipv4_udp_roce = rx_ipv4_udp & {s_axis_rx.tdata[36*8+7:36*8], s_axis_rx.tdata[37*8+7:37*8]} == 16'hb712;
    end 

    // Signals for dropping packets 
    logic rx_filter_dropping; 
    logic rx_filter_dropped; 
    logic rx_pkt_first_chunk; 
    logic rx_pkt_further_chunks; 

    // Check signal if the current chunk is the first one within a packet 
    assign rx_pkt_first_chunk = s_axis_rx.tvalid && s_axis_rx.tready && ~rx_pkt_further_chunks; 

    // Small FSM to determine current chunk in the packet 
    always_ff @(posedge nclk) begin 
        if(!nresetn) begin 
            rx_pkt_further_chunks <= 1'b0; 
        end else begin 
            if(s_axis_rx.tvalid && s_axis_rx.tready) begin 
                if(s_axis_rx.tlast) begin 
                    rx_pkt_further_chunks <= 1'b0; 
                end else begin 
                    rx_pkt_further_chunks <= 1'b1; 
                end
            end 
        end 
    end 

    // Implementation of the filter-rules 
    `ifdef EN_RDMA
        // Exclusive RDMA 
        `ifndef EN_TCP 
            `define EN_RDMA_NO_TCP
        `endif
        // RDMA + TCP 
        `ifdef EN_TCP
            `define EN_RDMA_AND_TCP
        `endif
    `else 
        `ifdef EN_TCP
            // TCP only 
            `define EN_TCP_NO_RDMA
        `else 
            // No TCP, no RDMA 
            `define EN_NO_TCP_NO_RDMA
        `endif
    `endif

    `ifdef EN_RDMA_AND_TCP
        assign rx_filter_dropping = rx_pkt_first_chunk && (rx_ipv4_tcp || rx_ipv4_udp_roce); // Filter out TCP and RoCE 
    `else 
        `ifdef EN_RDMA_NO_TCP
            assign rx_filter_dropping = rx_pkt_first_chunk && rx_ipv4_udp_roce; // Filter out RoCE
        `else 
            `ifdef EN_TCP_NO_RDMA
                assign rx_filter_dropping = rx_pkt_first_chunk && rx_ipv4_tcp; // Filter out TCP 
            `else 
                assign rx_filter_dropping = 1'b0; // No filtering 
            `endif
        `endif 
    `endif 

    // FSM to keep the dropped flag until the end of the packet stream
    always_ff @(posedge nclk) begin 
        if(!nresetn) begin 
            rx_filter_dropped <= 1'b0; 
        end else begin 
            if(s_axis_rx.tvalid && s_axis_rx.tready) begin 
                // If tlast is reached, we can disable the dropped flag 
                if(s_axis_rx.tlast) begin 
                    rx_filter_dropped <= 1'b1; 
                end else if(rx_filter_dropping) begin 
                    // If we're in the first packet and decide to drop it, we set this flag for the rest of the packet stream 
                    rx_filter_dropped <= 1'b1;
                end 
            end 
        end 
    end 

    // Assigning the output stream 
    assign m_axis_rx.tvalid = s_axis_rx.tvalid && !(rx_filter_dropping || rx_filter_dropped);
    assign m_axis_rx.tdata = s_axis_rx.tdata;
    assign m_axis_rx.tkeep = s_axis_rx.tkeep;
    assign m_axis_rx.tlast = s_axis_rx.tlast;

    assign m_axis_offloaded_rx.tvalid = s_axis_rx.tvalid && (rx_filter_dropping || rx_filter_dropped);
    assign m_axis_offloaded_rx.tdata = s_axis_rx.tdata;
    assign m_axis_offloaded_rx.tkeep = s_axis_rx.tkeep;
    assign m_axis_offloaded_rx.tlast = s_axis_rx.tlast;

    // Input ready only if both output streams are ready
    assign s_axis_rx.tready = m_axis_rx.tready && m_axis_offloaded_rx.tready;

endmodule 