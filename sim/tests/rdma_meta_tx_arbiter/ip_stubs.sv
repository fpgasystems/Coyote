`timescale 1ns / 1ps
// Behavioural stand-ins for the FIFO IPs rdma_meta_tx_arbiter wraps, so that it synthesises on its
// own: 2-entry queues
module axis_data_fifo_cnfg_rdma_256 (
    input  logic s_axis_aresetn, input logic s_axis_aclk,
    input  logic s_axis_tvalid, output logic s_axis_tready, input logic [255:0] s_axis_tdata,
    output logic m_axis_tvalid, input logic m_axis_tready, output logic [255:0] m_axis_tdata,
    output logic [31:0] axis_wr_data_count);
    logic [255:0] q [2];
    logic [1:0] n;
    assign s_axis_tready = n < 2;
    assign m_axis_tvalid = n > 0;
    assign m_axis_tdata = q[0];
    assign axis_wr_data_count = n;
    always_ff @(posedge s_axis_aclk) begin
        if (!s_axis_aresetn) n <= 0;
        else case ({s_axis_tvalid && s_axis_tready, m_axis_tvalid && m_axis_tready})
            2'b10: begin q[n] <= s_axis_tdata; n <= n + 1; end
            2'b01: begin q[0] <= q[1]; n <= n - 1; end
            2'b11: begin if (n == 1) q[0] <= s_axis_tdata; else begin q[0] <= q[1]; q[1] <= s_axis_tdata; end end
            default: ;
        endcase
    end
endmodule

module axis_data_fifo_512_used (
    input  logic s_axis_aresetn, input logic s_axis_aclk,
    input  logic s_axis_tvalid, output logic s_axis_tready,
    input  logic [511:0] s_axis_tdata, input logic [63:0] s_axis_tkeep, input logic s_axis_tlast,
    output logic m_axis_tvalid, input logic m_axis_tready,
    output logic [511:0] m_axis_tdata, output logic [63:0] m_axis_tkeep, output logic m_axis_tlast,
    output logic [31:0] axis_wr_data_count);
    logic [576:0] q [2];
    logic [1:0] n;
    assign s_axis_tready = n < 2;
    assign m_axis_tvalid = n > 0;
    assign {m_axis_tlast, m_axis_tkeep, m_axis_tdata} = q[0];
    assign axis_wr_data_count = n;
    always_ff @(posedge s_axis_aclk) begin
        if (!s_axis_aresetn) n <= 0;
        else case ({s_axis_tvalid && s_axis_tready, m_axis_tvalid && m_axis_tready})
            2'b10: begin q[n] <= {s_axis_tlast, s_axis_tkeep, s_axis_tdata}; n <= n + 1; end
            2'b01: begin q[0] <= q[1]; n <= n - 1; end
            2'b11: begin if (n == 1) q[0] <= {s_axis_tlast, s_axis_tkeep, s_axis_tdata}; else begin q[0] <= q[1]; q[1] <= {s_axis_tlast, s_axis_tkeep, s_axis_tdata}; end end
            default: ;
        endcase
    end
endmodule
