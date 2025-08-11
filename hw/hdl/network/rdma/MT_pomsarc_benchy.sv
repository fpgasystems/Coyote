`timescale 1ns / 1ps

`define DBG_IBV

import lynxTypes::*;

/**
 * @brief   RoCE instantiation
 *
 * RoCE stack
 */
module benchy
(
    input  logic                aclk,
    input  logic                aresetn,

    metaIntf.s                  s_req,
    metaIntf.m                  m_req
);

localparam integer packet_gap = 5; //inverse of marked percentage
localparam integer measurement_gap = 50;


//localparam integer max_timer = 10000000000;

logic[31:0] timer;
logic[31:0] packet_counter;
logic[31:0] packet_gap_counter;



logic running;

logic ecn, ecn_v, ecn_r;

logic[31:0] measurement_gap_timer;

always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        timer <= 0;
        measurement_gap_timer <= 0;
        packet_counter <= 0;
        packet_gap_counter <=0;

        ecn <= 0;
        ecn_v <= 0;
        running <= 0;
        measurement_gap_timer <= 0;
        //measurement_trigger <= 0;

    end
    else begin
        timer <= timer + 1;

        /*if(timer >= max_timer) begin
            timer <= 0;
            measurement_gap_timer <= 0;
            packet_counter <= 0;
            packet_gap_counter <= 0;

            ecn <= 0;
            ecn_v <= 0;
            running <= 0;
            measurement_gap_timer <= 0;
            //measurement_trigger <= 0;
        end*/
        else begin
            measurement_gap_timer <= measurement_gap_timer + 1;
            ecn_v <= 0;
            ecn <= 0;
            if(s_req.valid == 1) begin
                if(running == 0) begin
                    running <= 1;
                    measurement_gap_timer <= 0;
                end

                ecn_v <= 1;

                if(packet_gap_counter < packet_gap) begin
                    ecn <= 0;
                end
                else begin
                    ecn <= 1;
                end
                if(s_req.ready) begin
                    if(packet_gap_counter >= packet_gap) begin
                        packet_gap_counter <= 0;
                    end
                    else begin
                        packet_gap_counter <= packet_gap_counter + 1;
                    end
                    packet_counter <= packet_counter + 1;

                end
            end

            if(measurement_gap_timer >= measurement_gap) begin
                measurement_gap_timer <= 0;
            end
        end

    end
end

ila_testbench_CC inst_ila_testbench_CC(
    .clk(nclk),  
    .probe0(timer),
    .probe1(measurement_gap_timer),
    .probe2(running), 
    .probe3(ecn),
    .probe5(ecn_v),
    .probe6(ecn_r)
); 



cc_queue inst_cc_queue(
    .aclk(aclk),
    .aresetn(aresetn),

    .ecn_mark(ecn),
    .ecn_valid(ecn_v),
    .ecn_ready(ecn_r),


    .s_req(s_req),
    .m_req(m_req)
);




endmodule