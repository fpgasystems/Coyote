/*import lynxTypes::*;

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
*/
/*

ila_flowcontrol inst_ila_flowcontrol (
    .clk(aclk),  
    .probe0(ack_que_in.valid),
    .probe1(ack_que_in.ready),

    .probe2(s_ack.valid),
    .probe3(s_ack.ready),

    .probe4(m_ack.valid),
    .probe5(m_ack.ready),

    .probe6(req_out.valid), 
    .probe7(req_out.ready),

    .probe8(s_req.valid), 
    .probe9(s_req.ready),

    .probe10(m_req.valid), 
    .probe11(m_req.ready),

    .probe12(ecn_marked),
    .probe13(ecn_consumed),
    .probe14(s_ack.data.ack.ecn),
    .probe15(s_ack.data.last)
);
*/
/*

// ACK queue
queue_meta #(
    .QDEPTH(RDMA_N_OST)
) inst_cq (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(ack_que_in),
    .m_meta(m_ack)
);


localparam integer N_QUEUES = 4; 
localparam integer QUEUE_SEL_BITS = $clog2(N_QUEUES);


logic [DEST_BITS+PID_BITS-1:0] routing_key;
logic [QUEUE_SEL_BITS-1:0] queue_idx;

logic [DEST_BITS+PID_BITS-1:0] ack_routing_key;
logic [QUEUE_SEL_BITS-1:0]     ack_queue_idx;

logic [N_QUEUES-1:0] ecn_mark_queue;
logic [N_QUEUES-1:0] ecn_write_rdy_queue;

metaIntf #(.STYPE(dreq_t)) ccq_s_req [N_QUEUES] ();
metaIntf #(.STYPE(dreq_t)) ccq_m_req [N_QUEUES] ();

assign routing_key = {s_req.data.req_1.vfid, s_req.data.req_1.pid};
assign queue_idx = routing_key[DEST_BITS+PID_BITS-1 -: QUEUE_SEL_BITS];

assign ack_routing_key = {s_ack.data.ack.vfid, s_ack.data.ack.pid};
assign ack_queue_idx = ack_routing_key[DEST_BITS+PID_BITS-1 -: QUEUE_SEL_BITS];

logic ecn_marked;
assign ecn_marked = (s_ack.data.ack.ecn == 3);

logic ecn_consumed;
assign ecn_consumed = (s_ack.valid & s_ack.ready) & s_ack.data.last;

always_comb begin
    ecn_mark_queue = 0;
    ecn_write_rdy_queue = 0;

    if (ecn_marked) begin
        ecn_mark_queue[ack_queue_idx] = 1'b1;
    end 
    if (ecn_consumed) begin
        ecn_write_rdy_queue[ack_queue_idx] = 1'b1;
    end
end

logic [N_QUEUES-1:0] in_ready;

genvar i_gen_in;
generate
    for (i_gen_in = 0; i_gen_in < N_QUEUES; i_gen_in++) begin: gen_in
        always_comb begin
            ccq_s_req[i_gen_in].valid = 0;
            ccq_s_req[i_gen_in].data  = 0;
            in_ready[i_gen_in] = 0;
            if (queue_idx == i_gen_in) begin
                ccq_s_req[i_gen_in].valid = req_out.valid;
                ccq_s_req[i_gen_in].data  = req_out.data;
                in_ready[i_gen_in] = ccq_s_req[i_gen_in].ready;
            end
        end
    end
endgenerate

assign req_out.ready = |in_ready;


logic [QUEUE_SEL_BITS-1:0] readout_counter;
logic [N_QUEUES-1:0] ccq_m_req_valid;
logic state;

genvar i_gen_out_valid;
generate
  for (i_gen_out_valid = 0; i_gen_out_valid < N_QUEUES; i_gen_out_valid++) begin
    assign ccq_m_req_valid[i_gen_out_valid] = ccq_m_req[i_gen_out_valid].valid;
  end
endgenerate


always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        readout_counter <= 0;
        state <= 0;
    end 
    else begin
        if(state == 0) begin
            if(ccq_m_req_valid[readout_counter]) begin
                state <= 1;
            end 
            else begin 
                if(readout_counter == N_QUEUES-1) begin
                    readout_counter <= 0;
                end
                else begin
                    readout_counter <= readout_counter + 1;
                end
            end
        end
        else begin
            if(m_req.ready == 1) begin
                if(readout_counter == N_QUEUES-1) begin
                    readout_counter <= 0;
                end
                else begin
                    readout_counter <= readout_counter + 1;
                end
            end
        end
    end
end


genvar i_gen_out;
generate
    for (i_gen_out = 0; i_gen_out < N_QUEUES; i_gen_out++) begin: gen_out
        always_comb begin
            ccq_m_req[i_gen_out].ready = 0;

            if(readout_conter == i_gen_out) begin
                ccq_s_req[i_gen_in].ready  = m_req.ready;
            end
        end
    end
endgenerate

assign m_req.data = ccq_m_req[readout_counter].data;
assign m_req.valid = ccq_m_req[readout_counter].valid;


genvar i_gen;
generate
    for (i_gen = 0; i_gen < N_QUEUES; i_gen++) begin: gen_ccq
        cc_queue inst_ccq (
            .aclk(aclk),
            .aresetn(aresetn),

            .ecn_mark(ecn_mark_queue[i_gen]),
            .ecn_write_rdy(ecn_write_rdy_queue[i_gen]),

            .s_req(ccq_s_req[i_gen]),
            .m_req(ccq_m_req[i_gen])
        );
    end
endgenerate


endmodule
*/