`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

module axisr_decoupler #(
    parameter integer               DATA_BITS = AXI_DATA_BITS,
    parameter integer               N_STREAMS = 1
) (
    input  logic [N_REGIONS-1:0]    decouple,

    AXI4SR.s                        s_axis [N_REGIONS*N_STREAMS],
    AXI4SR.m                        m_axis [N_REGIONS*N_STREAMS]
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Decoupling --------------------------------------------------------------------------------------------------------- 
// -----------------------------------------------------------------------------------------------------------------------
`ifdef EN_PR

logic [N_REGIONS*N_STREAMS-1:0]                        s_axis_tvalid;
logic [N_REGIONS*N_STREAMS-1:0]                        s_axis_tready;
logic [N_REGIONS*N_STREAMS-1:0][DATA_BITS-1:0]        s_axis_tdata;
logic [N_REGIONS*N_STREAMS-1:0][DATA_BITS/8-1:0]      s_axis_tkeep;
logic [N_REGIONS*N_STREAMS-1:0][PID_BITS-1:0]         s_axis_tid;
logic [N_REGIONS*N_STREAMS-1:0]                        s_axis_tlast;

logic [N_REGIONS*N_STREAMS-1:0]                        m_axis_tvalid;
logic [N_REGIONS*N_STREAMS-1:0]                        m_axis_tready;
logic [N_REGIONS*N_STREAMS-1:0][DATA_BITS-1:0]        m_axis_tdata;
logic [N_REGIONS*N_STREAMS-1:0][DATA_BITS/8-1:0]      m_axis_tkeep;
logic [N_REGIONS*N_STREAMS-1:0][PID_BITS-1:0]         m_axis_tid;
logic [N_REGIONS*N_STREAMS-1:0]                        m_axis_tlast;

// Assign
for(genvar i = 0; i < N_REGIONS; i++) begin
    for (genvar j = 0; j < N_STREAMS; j++) begin
        assign s_axis_tvalid[i*N_STREAMS+j] = s_axis[i*N_STREAMS+j].tvalid;
        assign s_axis_tdata[i*N_STREAMS+j] = s_axis[i*N_STREAMS+j].tdata;
        assign s_axis_tkeep[i*N_STREAMS+j] = s_axis[i*N_STREAMS+j].tkeep;
        assign s_axis_tid[i*N_STREAMS+j]   = s_axis[i*N_STREAMS+j].tid;
        assign s_axis_tlast[i*N_STREAMS+j] = s_axis[i*N_STREAMS+j].tlast;
        assign s_axis[i*N_STREAMS+j].tready = s_axis_tready[i*N_STREAMS+j];

        assign m_axis[i*N_STREAMS+j].tvalid = m_axis_tvalid[i*N_STREAMS+j];
        assign m_axis[i*N_STREAMS+j].tdata = m_axis_tdata[i*N_STREAMS+j];
        assign m_axis[i*N_STREAMS+j].tkeep = m_axis_tkeep[i*N_STREAMS+j];
        assign m_axis[i*N_STREAMS+j].tid   = m_axis_tid[i*N_STREAMS+j];
        assign m_axis[i*N_STREAMS+j].tlast = m_axis_tlast[i*N_STREAMS+j];
        assign m_axis_tready[i*N_STREAMS+j] = m_axis[i*N_STREAMS+j].tready;
    end
end

// Decoupler
for(genvar i = 0; i < N_REGIONS; i++) begin
    for (genvar j = 0; j < N_STREAMS; j++) begin
        assign m_axis_tvalid[i*N_STREAMS+j] = decouple[i] ? 1'b0 : s_axis_tvalid[i*N_STREAMS+j];
        assign s_axis_tready[i*N_STREAMS+j] = decouple[i] ? 1'b0 : m_axis_tready[i*N_STREAMS+j];

        assign m_axis_tdata[i*N_STREAMS+j] = s_axis_tdata[i*N_STREAMS+j];
        assign m_axis_tlast[i*N_STREAMS+j] = s_axis_tlast[i*N_STREAMS+j];
        assign m_axis_tkeep[i*N_STREAMS+j] = s_axis_tkeep[i*N_STREAMS+j];
        assign m_axis_tid[i*N_STREAMS+j]   = s_axis_tid[i*N_STREAMS+j];
    end
end

`else

for(genvar i = 0; i < N_REGIONS; i++) begin
    for (genvar j = 0; j < N_STREAMS; j++) begin
        `AXIS_ASSIGN(s_axis[i*N_STREAMS+j], m_axis[i*N_STREAMS+j])
    end
end

`endif

endmodule