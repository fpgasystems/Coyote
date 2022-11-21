import lynxTypes::*;

module regex_data2 #(
    parameter integer   DBG = 0
) (
    input  logic        aclk,
    input  logic        aresetn,

    // RDMA
    AXI4S.s             axis_card_sink,
    AXI4S.m             axis_rdma_src,
    
    // Config
    metaIntf.s          cnfg
);

localparam integer BEAT_LOG_BYTES = AXI_DATA_BITS/8;
localparam integer BEAT_LOG_BITS = $clog2(BEAT_LOG_BYTES);

AXI4S axis_regex_in ();
logic regex_out_valid;
logic regex_out_ready;
logic regex_match;

AXI4S axis_que_in ();
AXI4S axis_que_out ();

logic last_C, last_N;
logic found_C, found_N;

// -- REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
    last_C <= 1'b0;
    found_C <= 'X;
end
else
    last_C <= last_N;
    found_C <= found_N;
end

// -- Datapath input
always_comb begin: DP_IN
    // Data in
    axis_card_sink.tready = axis_que_in.tready & axis_regex_in.tready;
    
    axis_que_in.tvalid = axis_card_sink.tvalid & axis_card_sink.tready;
    axis_regex_in.tvalid = axis_card_sink.tvalid & axis_card_sink.tready;

    axis_que_in.tdata = axis_card_sink.tdata;
    axis_que_in.tkeep = axis_card_sink.tkeep;
    axis_que_in.tlast = axis_card_sink.tlast;
    axis_regex_in.tdata = axis_card_sink.tdata;
    axis_regex_in.tkeep = axis_card_sink.tkeep;
    axis_regex_in.tlast = axis_card_sink.tlast;
end

// -- Datapath output
always_comb begin: DP_OUT
    last_N = last_C;
    found_N = found_C;
    
    // Data out
    axis_que_out.tready = 1'b0;

    axis_rdma_src.tvalid = 1'b0; 
    axis_rdma_src.tdata = axis_que_out.tdata;
    axis_rdma_src.tkeep = axis_que_out.tkeep;
    axis_rdma_src.tlast = axis_que_out.tlast;
    
    // Regex
    regex_out_ready = 1'b0;
    
    if(last_C) begin       
        axis_rdma_src.tvalid = 1'b1;
        axis_rdma_src.tlast = 1'b1;
        axis_rdma_src.tdata = 0;
        axis_rdma_src.tdata[0+:1] = found_C;
        axis_rdma_src.tkeep = ~0;

        if(axis_rdma_src.tready) begin
            last_N = 1'b0;
        end     
    end
    else begin
        if(axis_que_out.tlast) begin
            if(regex_out_valid) begin
                axis_que_out.tready = axis_rdma_src.tready;
                axis_rdma_src.tvalid = axis_que_out.tvalid;
                axis_rdma_src.tlast = 1'b0;

                if(axis_rdma_src.tvalid & axis_rdma_src.tready) begin
                    regex_out_ready = 1'b1;
                    found_N = regex_match;
                    last_N = 1'b1;
                end 
            end 
       end
       else begin
            axis_que_out.tready = axis_rdma_src.tready;
            axis_rdma_src.tvalid = axis_que_out.tvalid;
        end 
    end

end


// Matcher
regex_top inst_regex (
    .clk(aclk),
    .rst(~aresetn),

    .config_data(cnfg.data),
    .config_valid(cnfg.valid),
    .config_ready(cnfg.ready),
    
    .input_data(axis_regex_in.tdata),
    .input_valid(axis_regex_in.tvalid),
    .input_last(axis_regex_in.tlast),
    .input_ready(axis_regex_in.tready),

    .found_loc(regex_match),
    .found_valid(regex_out_valid),
    .found_ready(regex_out_ready)
);

// Data queue
axis_data_fifo_512_1kD inst_data_que (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(axis_que_in.tvalid),
    .s_axis_tready(axis_que_in.tready),
    .s_axis_tdata(axis_que_in.tdata),
    .s_axis_tkeep(axis_que_in.tkeep),
    .s_axis_tlast(axis_que_in.tlast),
    .m_axis_tvalid(axis_que_out.tvalid),
    .m_axis_tready(axis_que_out.tready),
    .m_axis_tdata(axis_que_out.tdata),
    .m_axis_tkeep(axis_que_out.tkeep),
    .m_axis_tlast(axis_que_out.tlast)
);

//if(DBG == 1) begin
    ila_regex_data2 inst_data (
        .clk(aclk),
        .probe0(axis_card_sink.tvalid),
        .probe1(axis_card_sink.tready), 
        .probe2(axis_card_sink.tlast), 
        .probe3(axis_regex_in.tvalid),
        .probe4(axis_regex_in.tready), 
        .probe5(axis_regex_in.tlast), 
        .probe6(axis_que_in.tvalid),
        .probe7(axis_que_in.tready), 
        .probe8(axis_que_in.tlast), 
        .probe9(axis_que_out.tvalid),
        .probe10(axis_que_out.tready), 
        .probe11(axis_que_out.tlast), 
        .probe12(axis_rdma_src.tvalid),
        .probe13(axis_rdma_src.tready), 
        .probe14(axis_rdma_src.tlast), 
        .probe15(last_C), // 1
        .probe16(found_C), // 1
        .probe17(regex_out_valid),
        .probe18(regex_out_ready),
        .probe19(regex_match)
    );
//end

endmodule