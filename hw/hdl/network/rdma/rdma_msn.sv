import lynxTypes::*;

module rdma_msn (
    metaIntf.s                  s_req,
    metaIntf.m                  m_req,

    metaIntf.s                  s_ack,

    input  logic                aclk,
    input  logic                aresetn
);

localparam integer RDMA_N_OST = 32;

logic [N_REGIONS_BITS-1:0][PID_BITS-1:0][4:0] head_C = 0, head_N;
logic [N_REGIONS_BITS-1:0][PID_BITS-1:0][4:0] tail_C = 0, tail_N;
logic [N_REGIONS_BITS-1:0][PID_BITS-1:0] issued_C = 0, issued_N;
logic [N_REGIONS_BITS-1:0][PID_BITS-1:0][RDMA_N_OST-1:0] rd_C = 0, rd_N;
logic [N_REGIONS_BITS-1:0][PID_BITS-1:0][RDMA_ACK_MSN_BITS-1:0] curr_ssn_C = 0, curr_ssn_N;
logic [N_REGIONS_BITS-1:0][PID_BITS-1:0][RDMA_ACK_MSN_BITS-1:0] curr_msn_C = 0, curr_msn_N;

logic rd_active;

logic [RDMA_ACK_MSN_BITS-1:0] ack_msn;
logic ack_rd;
logic [N_REGIONS_BITS-1:0] ack_vfid;
logic [PID_BITS-1:0] ack_pid;
logic [4:0] msn_diff;

logic [N_REGIONS_BITS-1:0] req_vfid;
logic [PID_BITS-1:0] req_pid;
logic req_rd;

ila_msn inst_ila_msn (
    .clk(aclk),
    .probe0(head_C[0][0]), // 5
    .probe1(tail_C[0][0]), // 5
    .probe2(issued_C[0][0]), 
    .probe3(rd_C[0][0]), // 32
    .probe4(curr_ssn_C[0][0]), // 24
    .probe5(curr_msn_C[0][0]), // 24
    .probe6(rd_active),
    .probe7(ack_msn), // 24
    .probe8(ack_rd),
    .probe9(ack_pid), // 6
    .probe10(msn_diff), // 5
    .probe11(req_pid), // 6
    .probe12(req_rd),
    .probe13(s_req.valid),
    .probe14(s_req.ready),
    .probe15(m_req.valid),
    .probe16(m_req.ready),
    .probe17(s_ack.valid),
    .probe18(s_ack.ready)
);

// REG
always_ff @(posedge aclk) begin
    if(~aresetn) begin
        head_C <= 0;
        tail_C <= 0;
        issued_C <= 0;
        rd_C <= 0;
        curr_ssn_C <= 0;
        curr_msn_C <= 0;
    end
    else begin
        head_C <= head_N;
        tail_C <= tail_N;
        issued_C <= issued_N;
        rd_C <= rd_N;
        curr_ssn_C <= curr_ssn_N;
        curr_msn_C <= curr_msn_N;
    end
end

// Check read active
always_comb begin
    rd_active = 1'b0;
    
    for(int i = 0; i < RDMA_N_OST; i++) begin
        if(head_C[ack_vfid][ack_pid] > tail_C[ack_vfid][ack_pid]) begin
            if(i >= tail_C[ack_vfid][ack_pid] && i < head_C[ack_vfid][ack_pid]) begin
                if(rd_C[ack_vfid][ack_pid]) begin
                    rd_active = 1'b1;
                end
            end
        end
        else if(head_C[ack_vfid][ack_pid] < tail_C[ack_vfid][ack_pid]) begin
            if(i >= tail_C[ack_vfid][ack_pid] || i < head_C[ack_vfid][ack_pid]) begin
                if(rd_C[ack_vfid][ack_pid][i]) begin
                    rd_active = 1'b1;
                end 
            end
        end
        else begin
            if(issued_C[ack_vfid][ack_pid]) begin
                if(rd_C[ack_vfid][ack_pid][i]) begin
                    rd_active = 1'b1;
                end 
            end
        end
    end
end

// Service
always_comb begin
    head_N = head_C;
    tail_N = tail_C;
    issued_N = issued_C;
    rd_N = rd_C;
    
    curr_ssn_N = curr_ssn_C;
    curr_msn_N = curr_msn_C;
    
    s_ack.ready = 1'b0;
    s_req.ready = 1'b0;

    if(s_ack.valid) begin
        // Service ack
        s_ack.ready = 1'b1;

        if(ack_rd) begin
            tail_N[ack_vfid][ack_pid] = tail_C[ack_vfid][ack_pid] + msn_diff;
            curr_msn_N[ack_vfid][ack_pid] = curr_msn_C[ack_vfid][ack_pid] + msn_diff;
            if(head_C[ack_vfid][ack_pid] == tail_N[ack_vfid][ack_pid]) begin
                issued_N[ack_vfid][ack_pid] = 1'b0;
            end
        end
        else begin
            if(!rd_active) begin
                tail_N[ack_vfid][ack_pid] = tail_C[ack_vfid][ack_pid] + msn_diff;
                curr_msn_N[ack_vfid][ack_pid] = curr_msn_C[ack_vfid][ack_pid] + msn_diff;
                if(head_C[ack_vfid][ack_pid] == tail_N[ack_vfid][ack_pid]) begin
                    issued_N[ack_vfid][ack_pid] = 1'b0;
                end
            end
        end
    end
    else if(s_req.valid) begin
        // Service req
        if(!issued_C[req_vfid][req_pid] || (head_C[req_vfid][req_pid] != tail_C[req_vfid][req_pid])) begin
            s_req.ready = 1'b1;
            curr_ssn_N[req_vfid][req_pid] = curr_ssn_C[req_vfid][req_pid] + 1;
            issued_N[req_vfid][req_pid] = 1'b1;

            head_N[req_vfid][req_pid] = head_C[req_vfid][req_pid] + 1;
            rd_N[req_vfid][req_pid][head_C[req_vfid][req_pid]] = req_rd;
        end
    end
end

// DP
assign ack_rd = s_ack.data.rd;
assign ack_pid = s_ack.data.pid;
assign ack_vfid = s_ack.data.vfid;
assign ack_msn = s_ack.data.msn;
assign msn_diff = ack_msn - curr_msn_C;

assign req_pid = s_req.data.qpn[0+:PID_BITS];
assign req_vfid = s_req.data.qpn[PID_BITS+:N_REGIONS_BITS];
assign req_rd = s_req.data.opcode == RC_RDMA_READ_REQUEST;

// I/O
assign m_req.valid = s_req.valid & s_req.ready;
assign m_req.data = s_req.data;

endmodule