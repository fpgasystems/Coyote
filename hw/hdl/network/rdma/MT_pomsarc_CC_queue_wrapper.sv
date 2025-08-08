import lynxTypes::*;

module cc_queue
(
    input  logic                aclk,
    input  logic                aresetn,

    input  logic                ecn_mark,
    input  logic                ecn_valid,
    output logic                ecn_ready,


    metaIntf.s                  s_req,
    metaIntf.m                  m_req
);

localparam integer RDMA_N_OST = RDMA_N_WR_OUTSTANDING;
localparam integer RDMA_OST_BITS = $clog2(RDMA_N_OST);
localparam integer RD_OP = 0;
localparam integer WR_OP = 1;

localparam integer Rt_default = 100000;
localparam integer Rc_default = 100000;
localparam integer N_min_time_between_ecn_marks = 50;
localparam integer Rai = 50;
localparam integer g = 8;
localparam integer F = 5;

localparam integer time_threshhold = 100;
localparam integer byte_threshhold = 10;

logic[31:0] Rt;
logic[31:0] Rc;
logic[31:0] alpha;
logic[31:0] timer;

logic[31:0] timer_send_rate;

logic[31:0] time_of_last_marked_packet;
logic[31:0] time_last_update;

logic[31:0] byte_counter;
logic[31:0] time_counter;

logic[4:0] step_counter;


//typedef enum logic[2:0]  {ST_IDLE, ST_CALC_SR, ST_ADD_TO_QUEUE} state_t;
logic [2:0] state_C, state_N;
metaIntf #(.STYPE(dreq_t)) queue_in();
metaIntf #(.STYPE(dreq_t)) queue_out();

logic ecn_data;




always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;

        Rt <= Rt_default;
        Rc <= Rc_default;
        alpha <= 1;
        timer <= 0;

        timer_send_rate = 0;

        byte_counter <= 0;
        time_counter <= 0
        
        ecn_ready <= 1;

        step_counter <= 0;


    end
    else begin
        timer <= timer + 1;
        time_counter = time_counter + 1;
        
        ecn_ready <= 1'b0;
        ecn_data <= ecn_mark;

        s_ack.ready <= 1'b0;

        s_req.ready <= 1'b0;
        req_out.valid <= 1'b0;
        req_out.data <= s_req.data;

        if(ecn_valid) begin
                ecn_ready <= 1'b1;
                byte_counter <= bytecounter + 1; 
                if(ecn_data == 1'b1) begin    //  Marked Packet arrived    
                    Rt = Rc;
                    Rc = Rc(1-(alpha/2));
                    alpha = (1-g)*alpha+g;
                end
        end

        if(time_counter >)


        if(s_req.valid & queue_in.ready) begin
            if(timer_send_rate > Rc) begin
                timer_send_rate = 0;
                req_out.valid = 1'b1;
                s_req.ready = 1'b1;
            end
        end


    end
end





/*
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;

        Rt <= Rt_default;
        Rc <= Rc_default;
        alpha <= 1;
        byte_counter <= 0;
        timer <= 0;
        ecn_ready <= 1;
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
        ST_CALC_SR:
            state_N = (ecn_valid) ? ST_CALC_SR : (s_req.valid & queue_in.ready ? ST_ADD_TO_QUEUE : ST_CALC_SR);
        ST_ADD_TO_QUEUE:
            state_N = ST_CALC_SR;

	endcase // state_C
end


always_comb begin: DP

    s_ack.ready = 1'b0;

    s_req.ready = 1'b0;
    req_out.valid = 1'b0;
    req_out.data = s_req.data;

    ecn_ready = 1'b0;
    ecn_data = ecn_mark;

    case(state_C):
        ST_CALC_SR: begin
            if(ecn_valid) begin
                ecn_ready = 1'b1;
                byte_counter = bytecounter + 1; 
                if(ecn_data == 1'b1) begin    //  Marked Packet arrived    
                    Rt = Rc;
                    Rc = Rc(1-(alpha/2));
                    alpha = (1-g)*alpha+g;
                end
            end
        end
        
        ST_ADD_TO_QUEUE: begin
            req_out.valid = 1'b1;
            s_req.ready = 1'b1;   
        end



    endcase

end
*/


queue_meta #(
    .QDEPTH(RDMA_N_OST)
) inst_cq (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(queue_in),
    .m_meta(m_req)
);


endmodule