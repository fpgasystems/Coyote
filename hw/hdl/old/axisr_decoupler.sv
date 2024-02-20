`timescale 1ns / 1ps

import lynxTypes::*;

module axisr_decoupler (
    input  logic [N_REGIONS-1:0]    decouple,

    AXI4SR.s                        s_axis [N_REGIONS],
    AXI4SR.m                       m_axis [N_REGIONS]
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Decoupling --------------------------------------------------------------------------------------------------------- 
// -----------------------------------------------------------------------------------------------------------------------
`ifdef EN_PR

logic [N_REGIONS-1:0]                        s_axis_tvalid;
logic [N_REGIONS-1:0]                        s_axis_tready;
logic [N_REGIONS-1:0][AXI_DATA_BITS-1:0]     s_axis_tdata;
logic [N_REGIONS-1:0][AXI_DATA_BITS/8-1:0]   s_axis_tkeep;
logic [N_REGIONS-1:0]                        s_axis_tlast;
logic [N_REGIONS-1:0][DEST_BITS-1:0]         s_axis_tdest;
logic [N_REGIONS-1:0][PID_BITS-1:0]          s_axis_tid;
logic [N_REGIONS-1:0][USER_BITS-1:0]         s_axis_tuser;

logic [N_REGIONS-1:0]                        m_axis_tvalid;
logic [N_REGIONS-1:0]                        m_axis_tready;
logic [N_REGIONS-1:0][AXI_DATA_BITS-1:0]     m_axis_tdata;
logic [N_REGIONS-1:0][AXI_DATA_BITS/8-1:0]   m_axis_tkeep;
logic [N_REGIONS-1:0]                        m_axis_tlast;
logic [N_REGIONS-1:0][3:0]                   m_axis_tdest;
logic [N_REGIONS-1:0][PID_BITS-1:0]          m_axis_tid;
logic [N_REGIONS-1:0][USER_BITS-1:0]         m_axis_tuser;

// Assign
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign s_axis_tvalid[i] = s_axis[i].tvalid;
    assign s_axis_tdata[i] = s_axis[i].tdata;
    assign s_axis_tkeep[i] = s_axis[i].tkeep;
    assign s_axis_tlast[i] = s_axis[i].tlast;
    assign s_axis_tdest[i] = s_axis[i].tdest;
    assign s_axis_tid[i]   = s_axis[i].tid;
    assign s_axis_tuser[i] = s_axis[i].tuser;
    assign s_axis[i].tready = s_axis_tready[i];

    assign m_axis[i].tvalid = m_axis_tvalid[i];
    assign m_axis[i].tdata = m_axis_tdata[i];
    assign m_axis[i].tkeep = m_axis_tkeep[i];
    assign m_axis[i].tlast = m_axis_tlast[i];
    assign m_axis[i].tdest = m_axis_tdest[i];
    assign m_axis[i].tid   = m_axis_tid[i];
    assign m_axis[i].tuser = m_axis_tuser[i];
    assign m_axis_tready[i] = m_axis[i].tready;
end

// Decoupler
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign m_axis_tvalid[i] = decouple[i] ? 1'b0 : s_axis_tvalid[i];
    assign s_axis_tready[i] = decouple[i] ? 1'b0 : m_axis_tready[i];

    assign m_axis_tdata[i] = s_axis_tdata[i];
    assign m_axis_tlast[i] = s_axis_tlast[i];
    assign m_axis_tkeep[i] = s_axis_tkeep[i];
    assign m_axis_tdest[i] = s_axis_tdest[i];
    assign m_axis_tid[i]   = s_axis_tid[i];
    assign m_axis_tuser[i] = s_axis_tuser[i];
end

`else

for(genvar i = 0; i < N_REGIONS; i++) begin
    `AXISR_ASSIGN(s_axis[i], m_axis[i])
end

`endif

endmodule