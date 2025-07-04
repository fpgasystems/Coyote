/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

`timescale 1ns / 1ps

import lynxTypes::*;

module host_req_mux (
    // HOST 
    metaIntf.s                          host_sq,

    metaIntf.m                          host_local_rd,
    metaIntf.m                          host_local_wr,
`ifdef EN_NET
    metaIntf.m                          host_remote_rd,
    metaIntf.m                          host_remote_wr,
`endif 

    input  logic    					aclk,    
	input  logic    					aresetn
);

metaIntf #(.STYPE(dreq_t)) host_sq_int ();
metaIntf #(.STYPE(req_t))  host_local_rd_int ();
metaIntf #(.STYPE(req_t))  host_local_wr_int ();
`ifdef EN_NET
logic remote_strm_1;
logic remote_strm_2;

metaIntf #(.STYPE(dreq_t))  host_remote_rd_int ();
metaIntf #(.STYPE(dreq_t))  host_remote_wr_int ();
`endif 

// Sink reg
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_sq  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_sq), .m_meta(host_sq_int));

`ifdef EN_NET

assign remote_strm_1 = ~(is_strm_local(host_sq_int.data.req_1.strm));
assign remote_strm_2 = ~(is_strm_local(host_sq_int.data.req_2.strm));

always_comb begin
    host_sq_int.ready = 1'b0;

    host_local_rd_int.valid = 1'b0;
    host_local_wr_int.valid = 1'b0;
    host_remote_rd_int.valid = 1'b0;
    host_remote_wr_int.valid = 1'b0;

    host_local_rd_int.data = host_sq_int.data.req_1;
    host_local_rd_int.data.actv = 1'b1;
    host_local_wr_int.data = host_sq_int.data.req_2;
    host_local_wr_int.data.actv = 1'b1;

    host_remote_rd_int.data = host_sq_int.data;
    host_remote_rd_int.data.req_1.actv = 1'b1;
    host_remote_rd_int.data.req_2.actv = 1'b0;
    host_remote_wr_int.data = host_sq_int.data;
    host_remote_wr_int.data.req_1.actv = 1'b0;
    host_remote_wr_int.data.req_2.actv = 1'b1;

    if(host_sq_int.valid) begin
        if(host_sq_int.data.req_1.actv & host_sq_int.data.req_2.actv) begin
            host_sq_int.ready = host_local_rd_int.ready & host_local_wr_int.ready;
    
            host_local_rd_int.valid = host_sq_int.ready;
            host_local_wr_int.valid = host_sq_int.ready;
        end
        else if(host_sq_int.data.req_1.actv) begin // rd, local
            host_sq_int.ready = remote_strm_1 ? (host_remote_rd_int.ready) : (host_local_rd_int.ready);

            host_remote_rd_int.valid = remote_strm_1;
            host_local_rd_int.valid = ~remote_strm_1;
        end
        else if(host_sq_int.data.req_2.actv) begin
            host_sq_int.ready = remote_strm_2 ? (host_remote_wr_int.ready & host_local_rd_int.ready) : (host_local_wr_int.ready);
            
            host_remote_wr_int.valid = remote_strm_2 & !remote_wr_picked_up;
            host_local_rd_int.valid = remote_strm_2 & !local_rd_picked_up;
            host_local_wr_int.valid = ~remote_strm_2;
        end
    end
end

logic remote_wr_picked_up; 
logic local_rd_picked_up; 
always_ff @ (posedge aclk) begin 
    if(!aresetn) begin
        // Basic case: We assume both signals have been picked up
        remote_wr_picked_up <= 0; 
        local_rd_picked_up <= 0; 
    end else begin 
        // Check for the right case of a local_rd & remote_wr double-action 
        if(host_sq_int.valid && host_sq_int.data.req_2.actv && remote_strm_2) begin 
            // In case of synchronicity: Both ready-signals are up, signals where picked up, don't change any settings here:
            if(host_remote_wr_int.ready && host_local_rd_int.ready) begin 
                // Keep signals as they are - in such a case, we don't need to take care specifically
                remote_wr_picked_up <= 0; 
                local_rd_picked_up <= 0;
            end else if(host_remote_wr_int.ready && !host_local_rd_int.ready) begin 
                // Means: Signal has been picked up!
                remote_wr_picked_up <= 1; 
            end else if(!host_remote_wr_int.ready && host_local_rd_int.ready) begin
                // Signal has been picked up! 
                local_rd_picked_up <= 1; 
            end 
        end 
    end 
end 

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_rd  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_local_rd_int), .m_meta(host_local_rd));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_wr  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_local_wr_int), .m_meta(host_local_wr));
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_remote_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(host_remote_rd_int), .m_meta(host_remote_rd));
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_remote_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(host_remote_wr_int), .m_meta(host_remote_wr));

`else

always_comb begin
    host_sq_int.ready = 1'b0;

    host_local_rd_int.valid = 1'b0;
    host_local_wr_int.valid = 1'b0;

    if(host_sq_int.valid) begin
        if(host_sq_int.data.req_1.actv & host_sq_int.data.req_2.actv) begin
            host_sq_int.ready = host_local_rd_int.ready & host_local_wr_int.ready;
            
            host_local_rd_int.valid = host_sq_int.ready;
            host_local_wr_int.valid = host_sq_int.ready;
        end
        else if(host_sq_int.data.req_1.actv) begin
            host_sq_int.ready = host_local_rd_int.ready;

            host_local_rd_int.valid = 1'b1;
        end
        else if(host_sq_int.data.req_2.actv) begin
            host_sq_int.ready = host_local_wr_int.ready;

            host_local_wr_int.valid = 1'b1;
        end
    end
end

assign host_local_rd_int.data = host_sq_int.data.req_1;
assign host_local_wr_int.data = host_sq_int.data.req_2;

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_rd  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_local_rd_int), .m_meta(host_local_rd));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_wr  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_local_wr_int), .m_meta(host_local_wr));

`endif 
    
endmodule