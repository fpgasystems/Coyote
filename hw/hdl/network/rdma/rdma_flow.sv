import lynxTypes::*;

module rdma_flow (
    metaIntf.s                  s_req,
    metaIntf.m                  m_req,

    metaIntf.s                  s_ack,
    metaIntf.m                  m_ack,

    input  logic                aclk,
    input  logic                aresetn
);

localparam integer RDMA_N_OST = RDMA_N_WR_OUTSTANDING;
localparam integer RDMA_OST_BITS = $clog2(RDMA_N_OST);
localparam integer RD_OP = 0;
localparam integer WR_OP = 1;

// -- FSM
typedef enum logic[2:0]  {ST_IDLE, ST_ACK_LUP_WAIT, ST_REQ_LUP_WAIT, ST_ACK_LUP, ST_REQ_LUP} state_t;
logic [2:0] state_C, state_N;
logic [1+N_REGIONS_BITS+PID_BITS-1:0] addr_C, addr_N;

logic [1:0] ssn_wr;
logic [1+N_REGIONS_BITS+PID_BITS-1:0] ssn_addr;
logic [15:0] ssn_in;
logic [15:0] ssn_out;

metaIntf #(.STYPE(ack_t)) ack_que_in ();
metaIntf #(.STYPE(dreq_t)) req_out ();

logic [RDMA_OST_BITS-1:0] tail, tail_next;
logic [RDMA_OST_BITS-1:0] head, head_next;
logic issued, issued_next;


// Pointer table
ram_sp_nc #(
    .ADDR_BITS(1+N_REGIONS_BITS+PID_BITS),
    .DATA_BITS(16)
) inst_pntr_table (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(ssn_wr),
    .a_addr(ssn_addr),
    .a_data_in(ssn_in),
    .a_data_out(ssn_out)
);

// REG
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;
        addr_C <= 'X;
    end
    else begin
        state_C <= state_N;
        addr_C <= addr_N;
    end
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = (s_ack.valid) ? ST_ACK_LUP_WAIT : (s_req.valid & req_out.ready ? ST_REQ_LUP_WAIT : ST_IDLE);

        ST_ACK_LUP_WAIT:
            state_N = ST_ACK_LUP;

        ST_REQ_LUP_WAIT:
            state_N = ST_REQ_LUP;

        ST_REQ_LUP:
            state_N = ST_IDLE;

        ST_ACK_LUP:
            state_N = ST_IDLE;

	endcase // state_C
end

// DP
assign ssn_in = {7'h00, issued_next, head_next, tail_next};
assign issued = ssn_out[2*RDMA_OST_BITS];
assign head = ssn_out[RDMA_OST_BITS+:RDMA_OST_BITS];
assign tail = ssn_out[0+:RDMA_OST_BITS];

always_comb begin: DP
    addr_N = addr_C;

    // ACKs
    s_ack.ready = 1'b0;

    ack_que_in.valid = 1'b0;
    ack_que_in.data = s_ack.data.ack;

    // Req
    s_req.ready = 1'b0;
    req_out.valid = 1'b0;
    req_out.data = s_req.data;
    req_out.data.req_1.offs = head;

    // Table
    ssn_wr = 0;
    ssn_addr = 0;
    
    // Pointers
    head_next = 0;
    tail_next = 0;
    issued_next = 0;

    case(state_C)
        ST_IDLE: begin
            if(s_ack.valid) begin
                s_ack.ready = 1'b1;
                ack_que_in.valid = s_ack.data.last;

                ssn_addr = {is_opcode_rd_resp(s_ack.data.ack.opcode), s_ack.data.ack.vfid[N_REGIONS_BITS-1:0], s_ack.data.ack.pid};
                addr_N = ssn_addr;
            end
            else if(s_req.valid & req_out.ready) begin
                ssn_addr = {is_opcode_rd_req(s_req.data.req_1.opcode), s_req.data.req_1.vfid[N_REGIONS_BITS-1:0], s_req.data.req_1.pid};
                addr_N = ssn_addr;
            end
        end

        ST_ACK_LUP: begin
            head_next = head;
            tail_next = tail + 1;
            if(head == tail_next) 
                issued_next = 1'b0;
            else
                issued_next = issued;

            ssn_wr = ~0;
            ssn_addr = addr_C;
        end

        ST_REQ_LUP: begin
            if(!issued || (head != tail)) begin
                req_out.valid = 1'b1;
                s_req.ready = 1'b1;       

                head_next = head + 1;
                tail_next = tail;
                issued_next = 1'b1;

                ssn_wr = ~0;
                ssn_addr = addr_C;
            end
        end

    endcase

end

// ACK queue
queue_meta #(
    .QDEPTH(RDMA_N_OST)
) inst_cq (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(ack_que_in),
    .m_meta(m_ack)
);

// REQ queue
queue_meta #(
    .QDEPTH(RDMA_N_OST)
) inst_sq (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(req_out),
    .m_meta(m_req)
);

endmodule