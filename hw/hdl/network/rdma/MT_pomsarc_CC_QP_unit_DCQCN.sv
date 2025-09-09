import lynxTypes::*;

module cc_queue
(
    input  logic                aclk,
    input  logic                aresetn,

    input  logic                ecn_mark,
    input  logic                ecn_write_rdy,

    metaIntf.s                  s_req,
    metaIntf.m                  m_req
);

//localparam integer RDMA_N_OST = RDMA_N_WR_OUTSTANDING;
localparam integer RDMA_N_OST = 20;
localparam integer RDMA_OST_BITS = $clog2(RDMA_N_OST);
localparam integer RD_OP = 0;
localparam integer WR_OP = 1;

localparam integer Rt_default = 100000;
localparam integer Rc_default = 100000;
localparam integer N_min_time_between_ecn_marks = 12500;
localparam integer K = 13750;
localparam integer Rai = 6250;

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

logic[4:0] tC_C; //timecounter counter
logic[4:0] bC_C; //bytecounter counter

logic rate_increase_event;


metaIntf #(.STYPE(dreq_t)) queue_out ();

always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        Rt <= Rt_default;
        Rc <= Rc_default;
        Sa <= S1;
        timer <= 0;

        timer_send_rate <= 0;

        time_of_last_marked_packet <= 0;
        time_last_update <= 0;

        byte_counter <= 0;
        time_counter <= 0;
        
        bC_C <= 0;
        tC_C <= 0;

        rate_increase_event <= 0;

        m_req.valid <= 1'b0;
        queue_out.ready <= 1'b0;
        m_req.data <= 0;


    end
    else begin
        timer <= timer + 1;
        time_counter <= time_counter + 1;
        timer_send_rate <= timer_send_rate + 1;
        
        rate_increase_event <= 0;


        m_req.valid <= 1'b0;
        m_req.data <= queue_out.data;
        queue_out.ready <= 1'b0;

        if(ecn_write_rdy) begin
            byte_counter <= byte_counter + 1; 
            if(ecn_mark == 1'b1) begin    //  Marked Packet arrived    
                if(timer - time_last_update > N_min_time_between_ecn_marks) begin
                    Rt <= Rc;
                    Rc <= (Rc << 8) / (S1 - (Sa>>1));   
                    Sa <= (((S1-Sg)*Sa)>> 8) + Sg;
                    time_last_update <= timer;

                    time_counter <= 0;
                    byte_counter <= 0;
                    bC_C <= 0;
                    tC_C <= 0;

                end
                time_of_last_marked_packet <= timer;
            end
        end

        if (timer - time_of_last_marked_packet > K) begin
                Sa <= (((S1-Sg)*Sa)>> 8);
        
        end
        
        if(time_counter > time_threshhold) begin 
            time_counter <= 0;
            rate_increase_event <= 1;
            if(tC_C < F) begin
                tC_C <= tC_C + 1;
            end
        end

        if(byte_counter > byte_threshhold) begin 
            byte_counter <= 0;
            rate_increase_event <= 1;
            if(bC_C < F) begin
                bC_C <= bC_C + 1;
            end
        end

        if(rate_increase_event) begin
            if(tC_C >= F || bC_C >= F) begin

                if(tC_C >= F && bC_C >= F) begin
                // case Hyper Increse   
                //replaced by fast recovery
                    Rc <=  (Rt + Rc) >> 1;
                end
                else begin
                // case Additive Increase
                    Rt <= Rt + Rai;
                    Rc <= (Rt + Rc) >> 1;
                end
            end else begin
                // case Fast Recovery
                Rc <=  (Rt + Rc) >> 1;
            end
        end

        // CHANGE BACK
        if(timer_send_rate > Rc) begin
        //if(timer_send_rate > 1) begin
            m_req.valid <= queue_out.valid;
            queue_out.ready <= m_req.ready;
            if(queue_out.valid && m_req.ready) begin
                timer_send_rate <= 0;
            end

        end


    end
end


ila_DCQCN inst_ila_DCQCN(
    .clk(aclk),  
    .probe0(timer),  //32
    .probe1(Rt),     //32
    .probe2(Rc),     //32
    .probe3(Sa),     //32
    .probe4(byte_counter),    //32
    .probe5(time_counter),    //32
    .probe6(TC_C),    //5
    .probe7(BC_C),    //5
    .probe8(rate_increase_event),
    .probe9(timer_send_rate), //32
    .probe10(s_req.valid),
    .probe11(s_req.ready),
    .probe12(m_req.valid),
    .probe13(m_req.ready),
    .probe14(queue_out.valid),
    .probe15(queue_out.ready),
    .probe16(ecn_mark),
    .probe17(ecn_write_rdy)
);


queue_meta #(
    .QDEPTH(RDMA_N_OST)
) inst_cq (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(s_req),
    .m_meta(queue_out)
);


endmodule