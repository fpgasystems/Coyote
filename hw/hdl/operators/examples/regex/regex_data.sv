import lynxTypes::*;

module regex_data #(
    parameter integer   DBG = 0
) (
    input  logic        aclk,
    input  logic        aresetn,

    // RDMA
    AXI4S.s             axis_card_sink,
    AXI4S.m             axis_rdma_src,

    // Command
    rdmaIntf.m          fv_src,

    // Sequence
    metaIntf.s          params,
    
    // Config
    metaIntf.s          cnfg
);

localparam integer BEAT_LOG_BYTES = AXI_DATA_BITS/8;
localparam integer BEAT_LOG_BITS = $clog2(BEAT_LOG_BYTES);

// -- FSM
typedef enum logic[1:0]  {ST_IDLE, ST_SEND, ST_DROP} state_t;
logic [1:0] state_C, state_N;

logic [31:0] cnt_C, cnt_N;
logic drop_sent_C, drop_sent_N;
logic drop_read_C, drop_read_N;

logic [VADDR_BITS-1:0] params_raddr;
logic [LEN_BITS-1:0] params_len;
logic [23:0] params_qp;

AXI4S axis_regex_in ();
logic regex_out_valid;
logic regex_out_ready;
logic regex_match;

AXI4S axis_que_in ();
AXI4S axis_que_out ();

// -- REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
    state_C <= ST_IDLE;
end
else
    state_C <= state_N;
    cnt_C <= cnt_N;
    drop_sent_C <= drop_sent_N;
    drop_read_C <= drop_read_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
            if(regex_out_valid && params.ready && fv_src.ready) begin
                if(regex_match) begin
                    state_N = ST_SEND;
                end
                else begin
                    state_N = ST_DROP;
                end
            end 

        ST_SEND:
            if((cnt_C == 0) && (axis_que_out.tready & axis_que_out.tvalid))
                state_N = ST_IDLE;

        ST_DROP:
            if(drop_read_C && drop_sent_C)
                state_N = ST_IDLE;

	endcase // state_C
end

// -- DP
always_comb begin: DP
    cnt_N = cnt_C;
    drop_sent_N = drop_sent_C;
    drop_read_N = drop_read_C;

    // Params
    params.ready = 1'b0;
    params_raddr = params.data[0+:VADDR_BITS];
    params_len = params.data[VADDR_BITS+:LEN_BITS];
    params_qp = params.data[VADDR_BITS+LEN_BITS+:24];

    // Regex
    regex_out_ready = 1'b0;

    // FV
    fv_src.valid = 1'b0;
    fv_src.req = 0;
    fv_src.req.opcode = APP_WRITE;
    fv_src.req.qpn = params_qp;
    fv_src.req.pkg.base.lvaddr = 0;
    fv_src.req.pkg.base.rvaddr = params_raddr;
    fv_src.req.pkg.base.len = 0;

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

    // Data out
    axis_que_out.tready = 1'b0;

    axis_rdma_src.tvalid = 1'b0; 
    axis_rdma_src.tdata = axis_que_out.tdata;
    axis_rdma_src.tkeep = axis_que_out.tkeep;
    axis_rdma_src.tlast = axis_que_out.tlast;

    case(state_C) 
        ST_IDLE: begin
            if(regex_out_valid && params.valid && fv_src.ready) begin
                regex_out_ready = 1'b1;
                params.ready = 1'b1;
                fv_src.valid = 1'b1;
                
                if(regex_match) begin
                    fv_src.req.pkg.base.len = params_len;
                end
                else begin
                    fv_src.req.pkg.base.len = 64;                    
                end
                
                cnt_N = (params_len - 1) >> BEAT_LOG_BITS;
                drop_sent_N = 1'b0;
                drop_read_N = 1'b0;
            end
        end

        ST_SEND: begin
            axis_que_out.tready = axis_rdma_src.tready;
            axis_rdma_src.tvalid = axis_que_out.tvalid;

            if(axis_que_out.tready & axis_que_out.tvalid) begin
                cnt_N = cnt_C - 1;
            end
        end 

        ST_DROP: begin
            axis_que_out.tready = ~drop_read_C;

            if(axis_que_out.tready & axis_que_out.tvalid) begin
                cnt_N = cnt_C - 1;
            end

            if((cnt_C == 0) && (axis_que_out.tready & axis_que_out.tvalid)) begin
                drop_read_N = 1'b1;
            end

            if(~drop_sent_C) begin
                axis_rdma_src.tvalid = 1'b1;
                axis_rdma_src.tdata[15:0] = 0;
                axis_rdma_src.tkeep = 64'hF;
                axis_rdma_src.tlast = 1'b1;
            end

            if(axis_rdma_src.tvalid & axis_rdma_src.tready) begin
                drop_sent_N = 1'b1;
            end
        end 

    endcase // state_C

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

if(DBG == 1) begin
    ila_regex_data inst_data (
        .clk(aclk),
        .probe0(state_C), // 2
        .probe1(cnt_C), // 32
        .probe2(drop_sent_C), 
        .probe3(drop_read_C),
        .probe4(params_raddr), // 48
        .probe5(params_len), // 28
        .probe6(params_qp[5:0]), // 6
        .probe7(axis_regex_in.tvalid),
        .probe8(axis_regex_in.tready),
        .probe9(axis_regex_in.tlast),
        .probe10(regex_out_valid),
        .probe11(regex_out_ready),
        .probe12(regex_match),
        .probe13(axis_que_out.tvalid),
        .probe14(axis_que_out.tready),
        .probe15(axis_que_out.tlast),
        .probe16(params.valid),
        .probe17(params.ready),
        .probe18(cnfg.valid),
        .probe19(cnfg.ready),
        .probe20(fv_src.valid),
        .probe21(fv_src.ready),
        .probe22(axis_card_sink.tvalid),
        .probe23(axis_card_sink.tready),
        .probe24(axis_card_sink.tlast),
        .probe25(axis_rdma_src.tvalid),
        .probe26(axis_rdma_src.tready),
        .probe27(axis_rdma_src.tlast),
        .probe28(cnfg.data), // 512
        .probe29(axis_card_sink.tdata) // 512
    );
end

endmodule