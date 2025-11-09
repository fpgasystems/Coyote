import lynxTypes::*;


// defines wether simulated ECN markings should be generated and also add test readout signals as ILAs
`define CC_TEST

module cc_queue
(
    input  logic                aclk,
    input  logic                aresetn,

    input  logic                ecn_mark,
    input  logic                ecn_write_rdy,

    metaIntf.s                  s_req,
    metaIntf.m                  m_req
);


//============ DCQCN PARAMETERS ================
//(Test setup parameters after the ifdef CC_TEST)

//defines the queue size
//localparam integer RDMA_N_OST = RDMA_N_WR_OUTSTANDING;
localparam integer RDMA_N_OST = 20;

//Send Rate default values (do not set too low or rounding might prevent rate increases (~100 cycles should be safe))
//IMPORTANT: send rate is expressed here as the number of cycles between two packets, higher Rc/Rt -> lower send rate
//Same with R_MIN below
localparam integer Rt_default = 200;
localparam integer Rc_default = 8192;

localparam integer R_MIN = 200;

//R_CAP is the maximum after which Rc/Rt will no longer be increased. Current value is just chosen to fit nicely in the simulation
localparam integer R_CAP = 16384;

//Time interval after a rate decrease in which no further rate decrease can happen (to give the network some time to adjust to new rate)
localparam integer N_min_time_between_ecn_marks = 12500;
//Timeout values for the lowering of the rate reduction factor (num cycles needs to be higher than N_min_time_between_ecn_marks)
localparam integer K = 13750;

//constant values by which send rate is adjusted in an additive rate increase step (higher value can be chosen for the hyper increase phase)
localparam integer R_ADDITIVE_INCREASE = 128;
localparam integer R_HYPER_INCREASE = 128;

//precision of rate reduction factor (do not change without changing all Sa values)
localparam integer Sg = 7;  

//Number of steps of recovery steps before additive rate increase sets in
localparam integer F = 5;

//time out values for the time and byte counter in num cycles and num packets respectively
localparam integer time_threshhold = 50000;
localparam integer byte_threshhold = 35;

//Precomputed Rate reduction factors
localparam integer Max_Sa_index = 28;
localparam integer Sa_fixed[0:28] = {256, 241, 228, 218, 209, 201, 194, 188, 182, 178, 173, 170, 166, 163, 161, 158, 156, 154, 152, 150, 148, 147, 146, 144, 143, 142, 141, 140, 139};

//================================================


logic[4:0] Sa_index;

logic[15:0] Rt;
logic[15:0] Rc;
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

`ifdef CC_TEST 


//============ TEST PARAMETERS ================

//number of cycles after ECN rate is changed to the next entry in the ECN_rates list 
localparam integer ecn_timer_trigger_threshhold = 5000000;

// List containing ECN rates during a test run, value indicates number of non marked packets after a marked packet.

//1
//localparam integer Ecn_rates[0:6] = {9999, 1, 9 ,99, 999, 9999};
//2
//localparam integer Ecn_rates[0:6] = {9999, 1, 9, 49 ,99, 999, 9999};
//3
//localparam integer Ecn_rates[0:6] = {9999, 1, 9, 14 , 19, 24, 9999};
//4
//localparam integer Ecn_rates[0:7] = {9999, 99, 29, 24, 19, 9, 29, 39};
//5
localparam integer Ecn_rates[0:15] = {9999, 99, 29, 24, 19, 9, 29, 39, 39, 99, 99, 149, 149,199,199,9999};
//needs to be number of different ECN rate steps - 1
localparam Ecn_rates_max_index = 15;

// trigger interval for ila_trigger signal to view results in Vivado
localparam integer Ila_readout_timer_threshhold = 40000;

//================================================

logic[23:0] ecn_timer;
logic ecn_alternator;
logic[15:0] ecn_counter;
logic ecn_test_starter;

logic[2:0] ecn_rates_index;

logic[15:0] ila_readout_timer;

logic ila_trigger;


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

            
            if(ecn_alternator == 1) begin    //  Marked Packet arrived    
                if(timer - time_last_update > N_min_time_between_ecn_marks) begin
                    
                    Rt <= Rc;
                    
                    if(Rc <= R_CAP) begin
                        Rc <= (Rc * Sa_fixed[Sa_index]) >> Sg;
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
                
                    if(Rt + 3 < R_HYPER_INCREASE) begin
                        Rt <= 1;
                    end
                    else begin
                        Rt <= Rt - R_HYPER_INCREASE;
                    end 
                    Rc <= (Rt + Rc) >> 1;
                end
                else begin
                    if(Rt + 3 < R_ADDITIVE_INCREASE) begin
                        Rt <= 1;
                    end
                    else begin
                        Rt <= Rt - R_ADDITIVE_INCREASE;
                    end 
                    Rc <= (Rt + Rc) >> 1;
                end
            end else begin
                Rc <=  (Rt + Rc) >> 1;
            end
        end

        if(Rc < R_MIN) begin
            Rc <= R_MIN;
        end
        if(Rt < R_MIN) begin
            Rt <= R_MIN;
        end

        // CHANGE BACK
        if(timer_send_rate > Rc) begin
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
    .probe19(ecn_write_rdy),

    .probe20(ecn_alternator), //1
    .probe21(ecn_counter),   //16
    .probe22(ecn_timer),     //24
    .probe23(ecn_test_starter),
    .probe24(ecn_rates_index),  // 3
    .probe25(ila_readout_timer), //16
    .probe26(ila_trigger)

);


`else

// NO TEST PART

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
                    
                    if(Rc <= R_CAP) begin
                        Rc <= (Rc * Sa_fixed[Sa_index]) >> Sg;
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
                    if(Rt + 3 < R_HYPER_INCREASE) begin
                        Rt <= 1;
                    end
                    else begin
                        Rt <= Rt - R_HYPER_INCREASE;
                    end 
                    Rc <= (Rt + Rc) >> 1;
                end
                else begin
                    if(Rt + 3 < R_ADDITIVE_INCREASE) begin
                        Rt <= 1;
                    end
                    else begin
                        Rt <= Rt - R_ADDITIVE_INCREASE;
                    end 
                    Rc <= (Rt + Rc) >> 1;
                end
            end else begin
                Rc <=  (Rt + Rc) >> 1;
            end
        end

        if(Rc < R_MIN) begin
            Rc <= R_MIN;
        end
        if(Rt < R_MIN) begin
            Rt <= R_MIN;
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


`endif





queue_meta #(
    .QDEPTH(RDMA_N_OST)
) inst_cq (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(s_req),
    .m_meta(queue_out)
);



endmodule