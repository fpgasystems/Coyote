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

//localparam integer Rt_default = 100000;
localparam integer Rt_default = 200;
localparam integer Rc_default = 8192;
localparam integer N_min_time_between_ecn_marks = 12500;
localparam integer K = 13750;
//localparam integer Rai = 6250;
localparam integer Rai = 128;

localparam integer S1 = 128;  // 1 << 8
localparam integer Sg = 8;    // (1/16) << 8
localparam integer F = 5;

localparam integer time_threshhold = 50000;
localparam integer byte_threshhold = 35;

localparam integer Max_Sa_index = 28;
//coarse_grained
//localparam integer Sa_fixed[0:3] = {16, 8, 3, 2};
//finegrained
localparam integer Sa_fixed[0:28] = {256, 241, 228, 218, 209, 201, 194, 188, 182, 178, 173, 170, 166, 163, 161, 158, 156, 154, 152, 150, 148, 147, 146, 144, 143, 142, 141, 140, 139};

//logic[3:0] Sa_index;
logic[4:0] Sa_index;




logic[15:0] Rt;
logic[15:0] Rc;
//logic[63:0] Sa;
logic[23:0] timer;

logic[23:0] timer_send_rate;

logic[23:0] time_of_last_marked_packet;
logic[23:0] time_last_update;

logic[7:0] byte_counter;
logic[15:0] time_counter;

logic[2:0] tC_C; //timecounter counter
logic[2:0] bC_C; //bytecounter counter

logic rate_increase_event;

//debug signals
//logic z_ack_arrives;
//logic z_marked_packet_triggers;
//logic z_alpha_decrease;

//logic z_time_counter_expires;
//logic z_byte_counter_expires;

//logic z_hyper_increase;
//logic z_additive_increase;
//logic z_fast_recovery;

//logic z_next_req_ready;

//simul part
logic[23:0] ecn_timer;
localparam integer ecn_timer_trigger_threshhold = 5000000;
logic ecn_alternator;
logic[15:0] ecn_counter;
//1
//localparam integer Ecn_rates[0:6] = {9999, 1, 9 ,99, 999, 9999};
//2
//localparam integer Ecn_rates[0:6] = {9999, 1, 9, 49 ,99, 999, 9999};
//3
//localparam integer Ecn_rates[0:6] = {9999, 1, 9, 14 , 19, 24, 9999};
//4
localparam integer Ecn_rates[0:7] = {9999, 99, 29, 24, 19, 9, 29, 39};

logic ecn_test_starter;
localparam Ecn_rates_max_index = 7;
logic[2:0] ecn_rates_index;

logic[15:0] ila_readout_timer;
localparam integer Ila_readout_timer_threshhold = 40000;
logic ila_trigger;


metaIntf #(.STYPE(dreq_t)) queue_out ();

always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        Rt <= Rt_default;
        Rc <= Rc_default;
        //Sa <= S1;
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
        /*
        z_ack_arrives  <= 0;
        z_marked_packet_triggers  <= 0;
        z_alpha_decrease  <= 0;

        z_time_counter_expires  <= 0;
        z_byte_counter_expires  <= 0;

        z_hyper_increase  <= 0;
        z_additive_increase  <= 0;
        z_fast_recovery  <= 0;

        z_next_req_ready  <= 0;
        */
        Sa_index <= 0;


        //simul
        ecn_alternator <= 0;
        ecn_counter <= 0;
        ecn_test_starter <= 0;
        ecn_timer <= 0;
        ecn_rates_index <= 0;
        ila_readout_timer <= 0;
        ila_trigger <= 0;


    end
    else begin
        timer = timer + 1;
        time_counter <= time_counter + 1;
        timer_send_rate <= timer_send_rate + 1;
        
        rate_increase_event <= 0;


        m_req.valid <= 1'b0;
        m_req.data <= queue_out.data;
        queue_out.ready <= 1'b0;

        if(ila_readout_timer >= Ila_readout_timer_threshhold) begin
            ila_readout_timer <= 0;
            ila_trigger = 1;
        end else begin
            ila_readout_timer <= ila_readout_timer + 1;
            ila_trigger = 0;
        end



        //z_ack_arrives  <= 0;
        //z_marked_packet_triggers  <= 0;
        //z_alpha_decrease  <= 0;

        //z_time_counter_expires  <= 0;
        //z_byte_counter_expires  <= 0;

        //z_hyper_increase  <= 0;
        //z_additive_increase  <= 0;
        //z_fast_recovery  <= 0;

        //z_next_req_ready  <= 0;
        if(ecn_test_starter == 1) begin
            

            if(ecn_timer > ecn_timer_trigger_threshhold) begin
                    if(!(ecn_rates_index == Ecn_rates_max_index)) begin
                        ecn_rates_index <= ecn_rates_index + 1;
                    end 
                    ecn_timer <= 0;
            end 
            else begin
                    ecn_timer <= ecn_timer + 1;
            end
        end





        if(ecn_write_rdy) begin
            //===Debug Signal===
            //z_ack_arrives <= 1;

            //==================
            byte_counter <= byte_counter + 1; 

            //======simul======
            ecn_test_starter <= 1;

        
            if(ecn_counter >= Ecn_rates[ecn_rates_index]) begin
                ecn_counter <= 0;
                ecn_alternator = 1;
            end 
            else begin
                ecn_counter <= ecn_counter + 1;
                ecn_alternator = 0;
            end

            
            //===============================

            
            if(ecn_mark == 1'b1 && ecn_alternator == 1) begin    //  Marked Packet arrived    
                if(timer - time_last_update > N_min_time_between_ecn_marks) begin
                    //===Debug Signal===
                    //z_marked_packet_triggers <= 1;
                    //==================
                    Rt <= Rc;
                    
                    if(Rc <= 16384) begin
                        Rc <= (Rc * Sa_fixed[Sa_index]) >> 7;
                    end
                    if(!(Sa_index == 0)) begin
                        Sa_index <= Sa_index - 1;
                    end
                    
                    time_last_update <= timer;

                    time_counter <= 0;
                    byte_counter <= 0;
                    bC_C <= 0;
                    tC_C <= 0;

                end
                time_of_last_marked_packet = timer;
            end
        end

        if (timer - time_of_last_marked_packet > K) begin
                //===Debug Signal===
                //z_alpha_decrease <= 1;
                //==================
                
                
                if(!(Sa_index == Max_Sa_index)) begin
                    Sa_index <= Sa_index + 1;
                end

                time_of_last_marked_packet <= timer;              
        end
        
        if(time_counter > time_threshhold) begin 
            //===Debug Signal===
            //z_time_counter_expires <= 1;
            //==================
            time_counter <= 0;
            rate_increase_event <= 1;
            if(tC_C < F) begin
                tC_C <= tC_C + 1;
            end
        end

        if(byte_counter > byte_threshhold) begin 
            //===Debug Signal===
            //z_byte_counter_expires <= 1;
            //==================
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
                //===Debug Signal===
                //z_hyper_increase <= 1;
                //==================
                    if(Rt + 3 < Rai) begin
                        Rt <= 1;
                    end
                    else begin
                        Rt <= Rt - Rai;
                    end 
                    Rc <= (Rt + Rc) >> 1;
                end
                else begin
                // case Additive Increase
                //===Debug Signal===
                //z_additive_increase <= 1;
                //==================
                    if(Rt + 3 < Rai) begin
                        Rt <= 1;
                    end
                    else begin
                        Rt <= Rt - Rai;
                    end 
                    Rc <= (Rt + Rc) >> 1;
                end
            end else begin
                // case Fast Recovery
                //===Debug Signal===
                //z_fast_recovery <= 1;
                //==================
                Rc <=  (Rt + Rc) >> 1;
            end
        end

        if(Rc < 200) begin
            Rc <= 200;
        end
        if(Rt < 200) begin
            Rt <= 200;
        end

        // CHANGE BACK
        if(timer_send_rate > Rc) begin
        //if(timer_send_rate > 1) begin

            //===Debug Signal===
            //z_next_req_ready <= 1;
            //==================

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
    .probe0(timer),  //24
    .probe1(Rt),     //16
    .probe2(Rc),     //16
    .probe3(Sa_index),     //5
    .probe4(byte_counter),    //8
    .probe5(time_counter),    //16
    .probe6(tC_C),    //3
    .probe7(bC_C),    //3
    .probe8(rate_increase_event),
    .probe9(timer_send_rate), //24
    .probe10(time_last_update), //24
    .probe11(time_of_last_marked_packet), //24

    .probe12(s_req.valid),
    .probe13(s_req.ready),
    .probe14(m_req.valid),
    .probe15(m_req.ready),
    .probe16(queue_out.valid),
    .probe17(queue_out.ready),
    .probe18(ecn_mark),
    .probe19(ecn_write_rdy),/*,

    .probe20(z_ack_arrives),
    .probe21(z_marked_packet_triggers),
    .probe22(z_alpha_decrease),
    .probe23(z_time_counter_expires),
    .probe24(z_byte_counter_expires),
    .probe25(z_hyper_increase),
    .probe26(z_additive_increase),
    .probe27(z_fast_recovery),
    .probe28(z_next_req_ready),*/
    .probe20(ecn_alternator), //1
    .probe21(ecn_counter),   //16
    .probe22(ecn_timer),     //24
    .probe23(ecn_test_starter),
    .probe24(ecn_rates_index),  // 3
    .probe25(ila_readout_timer), //16
    .probe26(ila_trigger)

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



// NO TEST PART



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
//localparam integer RDMA_N_OST = 20;
//localparam integer RDMA_OST_BITS = $clog2(RDMA_N_OST);

localparam integer RDMA_N_OST = 100;
localparam integer RDMA_OST_BITS = $clog2(RDMA_N_OST);

localparam integer RD_OP = 0;
localparam integer WR_OP = 1;

//localparam integer Rt_default = 100000;
localparam integer Rt_default = 200;
localparam integer Rc_default = 8192;
localparam integer N_min_time_between_ecn_marks = 12500;
localparam integer K = 13750;
//localparam integer Rai = 6250;
localparam integer Rai = 128;

localparam integer S1 = 128;  // 1 << 8
localparam integer Sg = 8;    // (1/16) << 8
localparam integer F = 5;

localparam integer time_threshhold = 50000;
localparam integer byte_threshhold = 35;

localparam integer Max_Sa_index = 28;
//coarse_grained
//localparam integer Sa_fixed[0:3] = {16, 8, 3, 2};
//finegrained
localparam integer Sa_fixed[0:28] = {256, 241, 228, 218, 209, 201, 194, 188, 182, 178, 173, 170, 166, 163, 161, 158, 156, 154, 152, 150, 148, 147, 146, 144, 143, 142, 141, 140, 139};

//logic[3:0] Sa_index;
logic[4:0] Sa_index;




logic[15:0] Rt;
logic[15:0] Rc;
//logic[63:0] Sa;
logic[23:0] timer;

logic[23:0] timer_send_rate;

logic[23:0] time_of_last_marked_packet;
logic[23:0] time_last_update;

logic[7:0] byte_counter;
logic[15:0] time_counter;

logic[2:0] tC_C; //timecounter counter
logic[2:0] bC_C; //bytecounter counter

logic rate_increase_event;


metaIntf #(.STYPE(dreq_t)) queue_out ();

always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        Rt <= Rt_default;
        Rc <= Rc_default;
        
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
       

        Sa_index <= 0;


    end
    else begin
        timer = timer + 1;
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
                    
                    if(Rc <= 16384) begin
                        Rc <= (Rc * Sa_fixed[Sa_index]) >> 7;
                    end
                    if(!(Sa_index == 0)) begin
                        Sa_index <= Sa_index - 1;
                    end
                    
                    time_last_update <= timer;

                    time_counter <= 0;
                    byte_counter <= 0;
                    bC_C <= 0;
                    tC_C <= 0;

                end
                time_of_last_marked_packet = timer;
            end
        end

        if (timer - time_of_last_marked_packet > K) begin
                if(!(Sa_index == Max_Sa_index)) begin
                    Sa_index <= Sa_index + 1;
                end
                time_of_last_marked_packet <= timer;              
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
                    if(Rt + 3 < Rai) begin
                        Rt <= 1;
                    end
                    else begin
                        Rt <= Rt - Rai;
                    end 
                    Rc <= (Rt + Rc) >> 1;
                end
                else begin
                    if(Rt + 3 < Rai) begin
                        Rt <= 1;
                    end
                    else begin
                        Rt <= Rt - Rai;
                    end 
                    Rc <= (Rt + Rc) >> 1;
                end
            end else begin
                Rc <=  (Rt + Rc) >> 1;
            end
        end

        if(Rc < 200) begin
            Rc <= 200;
        end
        if(Rt < 200) begin
            Rt <= 200;
        end

        if(timer_send_rate > Rc) begin
        
            m_req.valid <= queue_out.valid;
            queue_out.ready <= m_req.ready;
            if(queue_out.valid && m_req.ready) begin
                timer_send_rate <= 0;
            end

        end


    end
end


queue_meta #(
    .QDEPTH(RDMA_N_OST)
) inst_cq (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(s_req),
    .m_meta(queue_out)
);


endmodule