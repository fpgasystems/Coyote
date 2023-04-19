import lynxTypes::*;

module rdma_msn (
    metaIntf.s                  s_req,
    metaIntf.m                  m_req,

    metaIntf.s                  s_ack,

    input  logic                aclk,
    input  logic                aresetn
);

localparam integer RDMA_N_OST = 16;
localparam integer RDMA_OST_BITS = $clog2(RDMA_N_OST);
localparam integer RD_OP = 0;
localparam integer WR_OP = 1;

logic [1:0][N_REGIONS_BITS-1:0][PID_BITS-1:0][RDMA_OST_BITS-1:0] head_C = 0, head_N;
logic [1:0][N_REGIONS_BITS-1:0][PID_BITS-1:0][RDMA_OST_BITS-1:0] tail_C = 0, tail_N;
logic [1:0][N_REGIONS_BITS-1:0][PID_BITS-1:0] issued_C = 0, issued_N;


logic ack_rd;
logic [N_REGIONS_BITS-1:0] ack_vfid;
logic [PID_BITS-1:0] ack_pid;

logic req_rd;
logic [N_REGIONS_BITS-1:0] req_vfid;
logic [PID_BITS-1:0] req_pid;


ila_msn inst_ila_msn (
    .clk(aclk),
    .probe0(head_C[0][0][0]), // 4
    .probe1(head_C[1][0][0]), // 4
    .probe2(tail_C[0][0][0]), // 4
    .probe3(tail_C[1][0][0]), // 4
    .probe4(issued_C[0][0][0]),
    .probe5(issued_C[1][0][0]),
    .probe6(ack_rd),
    .probe7(ack_pid), // 6
    .probe8(req_rd),
    .probe9(req_pid), // 6
    .probe10(s_req.valid),
    .probe11(s_req.ready),
    .probe12(m_req.valid),
    .probe13(m_req.ready),
    .probe14(s_ack.valid),
    .probe15(s_ack.ready)
);

// REG
always_ff @(posedge aclk) begin
    if(~aresetn) begin
        head_C <= 0;
        tail_C <= 0;
        issued_C <= 0;
    end
    else begin
        head_C <= head_N;
        tail_C <= tail_N;
        issued_C <= issued_N;
    end
end

// Service
always_comb begin
    head_N = head_C;
    tail_N = tail_C;
    issued_N = issued_C;
    
    s_ack.ready = 1'b0;
    s_req.ready = 1'b0;

    if(s_ack.valid) begin
        // Service ack
        s_ack.ready = 1'b1;

        tail_N[ack_rd][ack_vfid][ack_pid] = tail_C[ack_rd][ack_vfid][ack_pid] + 1;
        if(head_C[ack_rd][ack_vfid][ack_pid] == tail_N[ack_rd][ack_vfid][ack_pid]) begin
            issued_N[ack_rd][ack_vfid][ack_pid] = 1'b0;
        end
    end
    else if(s_req.valid) begin
        // Service req
        if(!issued_C[req_rd][req_vfid][req_pid] || (head_C[req_rd][req_vfid][req_pid] != tail_C[req_rd][req_vfid][req_pid])) begin
            s_req.ready = 1'b1;

            head_N[req_rd][req_vfid][req_pid] = head_C[req_rd][req_vfid][req_pid] + 1;
            issued_N[req_rd][req_vfid][req_pid] = 1'b1;
        end
    end
end

// DP
assign ack_rd = ~s_ack.data.rd;
assign ack_pid = s_ack.data.pid;
assign ack_vfid = s_ack.data.vfid;

assign req_rd = s_req.data.opcode == RC_RDMA_READ_REQUEST;
assign req_pid = s_req.data.qpn[0+:PID_BITS];
assign req_vfid = s_req.data.qpn[PID_BITS+:N_REGIONS_BITS];


// I/O
assign m_req.valid = s_req.valid & s_req.ready;
assign m_req.data = s_req.data;

endmodule