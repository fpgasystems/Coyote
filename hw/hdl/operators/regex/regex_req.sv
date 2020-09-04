import lynxTypes::*;

module regex_req #(
    parameter integer   DBG_ILA = 0
) (
    input  logic        aclk,
    input  logic        aresetn,

    // RDMA
    metaIntf.s          fv_sink,

    // Host
    reqIntf.m           rd_req_user,

    // Sequence
    metaIntf.m          params,

    // Config
    metaIntf.m          cnfg
);

localparam integer BEAT_LOG_BYTES = AXI_DATA_BITS/8;
localparam integer BEAT_LOG_BITS = $clog2(BEAT_LOG_BYTES);

// -- FSM
typedef enum logic[1:0]  {ST_IDLE, ST_CONFIG_1, ST_CONFIG_2, ST_READ} state_t;

// Regs
logic [1:0] state_C, state_N;

logic [511:0] regex_cnfg_C = 0, regex_cnfg_N; 
logic [LEN_BITS-1:0] len_C, len_N;
logic [VADDR_BITS-1:0] laddr_C, laddr_N;
logic [VADDR_BITS-1:0] raddr_C, raddr_N;
logic [23:0] qp_C, qp_N;

// Int
logic [23:0] fv_qp;
logic [VADDR_BITS-1:0] fv_raddr;
logic [VADDR_BITS-1:0] fv_laddr;
logic [31:0] fv_len;
logic [191:0] fv_raw;
/*
if(DBG_ILA == 1) begin
    ila_regex_req inst_req (
        .clk(aclk),
        .probe0(state_C), // 2
        .probe1(raddr_C), // 48
        .probe2(laddr_C), // 48
        .probe3(len_C), // 28
        .probe4(params.valid),
        .probe5(params.ready),
        .probe6(cnfg.valid),
        .probe7(cnfg.ready),
        .probe8(rd_req_user.valid),
        .probe9(rd_req_user.ready),
        .probe10(fv_sink.valid),
        .probe11(fv_sink.ready),
        .probe12(qp_C[5:0]) // 6
    );
end
*/
// -- REG
always_ff @(posedge aclk, negedge aresetn) begin: PROC_REG
if (aresetn == 1'b0) begin
    state_C <= ST_IDLE;
    regex_cnfg_C <= 0;
end
else
    state_C <= state_N;

    regex_cnfg_C <= regex_cnfg_N;
    len_C <= len_N;
    laddr_C <= laddr_N;
    raddr_C <= raddr_N;
    qp_C <= qp_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
            if(fv_sink.valid)
                if(fv_sink.data[255-:8] != 255) 
                    state_N = ST_CONFIG_1;
                else 
                    state_N = ST_READ;
		
        ST_CONFIG_1:
            if(fv_sink.valid)
                state_N = ST_CONFIG_2;

        ST_CONFIG_2:
            if(cnfg.ready) 
                state_N = ST_IDLE;

        ST_READ:
            if(rd_req_user.ready && params.ready) 
                state_N = ST_IDLE;

	endcase // state_C
end

// -- DP
always_comb begin: DP
    regex_cnfg_N = regex_cnfg_C;
    len_N = len_C;
    laddr_N = laddr_C;
    raddr_N = raddr_C;
    qp_N = qp_C;

    // Incoming
    fv_qp = fv_sink.data[5+:24];
    fv_raddr = fv_sink.data[64+:48];
    fv_laddr = fv_sink.data[112+:48];
    fv_len = fv_sink.data[160+:32];
    fv_raw = fv_sink.data[64+:192];

    // FV sink
    fv_sink.ready = 1'b0;

    // RD host
    rd_req_user.valid = 1'b0;
    rd_req_user.req = 0;
    rd_req_user.req.vaddr = laddr_C;
    rd_req_user.req.len = len_C; 
    rd_req_user.req.ctl = 1'b1;

    // Params
    params.valid = 1'b0;
    params.data = {qp_C, len_C, raddr_C};

    // Config intf
    cnfg.valid = 1'b0;
    cnfg.data = regex_cnfg_C;

    // DP fsm
    case(state_C)
        ST_IDLE: begin
            if(fv_sink.valid) begin
                fv_sink.ready = 1'b1;

                if(fv_sink.data[255-:8] != 255) begin
                    regex_cnfg_N[511] = 1'b1;
                    regex_cnfg_N[192+:192] = fv_raw;
                end
                else begin
                    len_N = fv_len[LEN_BITS-1:0];
                    laddr_N = fv_laddr;
                    raddr_N = fv_raddr;
                    qp_N = fv_qp;
                end
            end
        end

        ST_CONFIG_1: begin
            if(fv_sink.valid) begin
                fv_sink.ready = 1'b1;

                regex_cnfg_N[0+:192] = fv_raw;
            end
        end

        ST_CONFIG_2: begin
            cnfg.valid = 1'b1;
        end

        ST_READ: begin
            if(rd_req_user.ready && params.ready) begin
                rd_req_user.valid = 1'b1;
                params.valid = 1'b1;
            end
        end 

    endcase // state_C

end

endmodule