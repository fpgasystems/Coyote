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

localparam integer S1 = 128;  // 1 << 8
localparam integer Sg = 8;    // (1/16) << 8
localparam integer F = 5;

localparam integer time_threshhold = 100;
localparam integer byte_threshhold = 10;



logic[31:0] Rt;
logic[31:0] Rc;
logic[31:0] Sa;
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
        Rt <= Rt_default;
        Rc <= Rc_default;
        Sa <= S1;
        timer <= 0;

        timer_send_rate = 0;

        byte_counter <= 0;
        time_counter <= 0;
        
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
            byte_counter <= byte_counter + 1; 
            if(ecn_data == 1'b1) begin    //  Marked Packet arrived    
                if(timer - time_last_update > N_min_time_between_ecn_marks) begin
                    Rt <= Rc;
                    Rc <= (Rc << 8) / (S1 - (Sa>>1));   
                    Sa <= (((S1-Sg)*Sa)>> 8) + Sg;
                    time_last_update <= timer;
                end
                time_of_last_marked_packet <= timer;
            end
        end

        if (timer - time_of_last_marked_packet > N_min_time_between_ecn_marks) begin
                Sa <= (((S1-Sg)*Sa)>> 8);
        
        end

        if(time_counter >= F || byte_counter >= F) begin

            if(time_counter >= F && byte_counter >=F) begin
            // case Hyper Increse   
            //replaced by fast recovery
                Rc =  (Rt + Rc) >> 1;

                time_counter <= 0;
                byte_counter <= 0;
            end
            else begin
            // case Additive Increase
                Rt <= Rt + Rai;
                Rc <= (Rt + Rc) >> 1;
                if(time_counter >= F)begin
                    time_counter <= 0;
                end
                else begin
                    byte_counter <= 0;
                end
            end
        else begin
            // case Fast Recovery
            Rc =  (Rt + Rc) >> 1;
        end


        if(s_req.valid & queue_in.ready) begin
            if(timer_send_rate > Rc) begin
                timer_send_rate <= 0;
                req_out.valid <= 1'b1;
                s_req.ready <= 1'b1;
            end
        end


    end
end
end



queue_meta #(
    .QDEPTH(RDMA_N_OST)
) inst_cq (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(queue_in),
    .m_meta(m_req)
);


endmodule