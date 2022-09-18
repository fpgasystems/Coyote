import lynxTypes::*;

module regex_req #(
    parameter integer   DBG_ILA = 0
) (
    input  logic        aclk,
    input  logic        aresetn,

    // RDMA
    rdmaIntf.s          fv_sink,

    // Host
    reqIntf.m           bpss_rd_req,

    // Sequence
    metaIntf.m          params,

    // Config
    metaIntf.m          cnfg
);

localparam integer BEAT_LOG_BYTES = AXI_DATA_BITS/8;
localparam integer BEAT_LOG_BITS = $clog2(BEAT_LOG_BYTES);

// -- FSM
typedef enum logic[2:0]  {ST_IDLE, ST_CONFIG_1, ST_CONFIG_2, ST_CONFIG_3, ST_READ} state_t;

// Regs
logic [2:0] state_C, state_N;

logic [511:0] regex_cnfg_C = 0, regex_cnfg_N; 
logic [LEN_BITS-1:0] len_C, len_N;
logic [VADDR_BITS-1:0] lvaddr_C, lvaddr_N;
logic [VADDR_BITS-1:0] rvaddr_C, rvaddr_N;
logic [23:0] qp_C, qp_N;

// Int
logic [23:0] fv_qp;
logic [VADDR_BITS-1:0] fv_rvaddr;
logic [VADDR_BITS-1:0] fv_lvaddr;
logic [31:0] fv_len;
logic [191:0] fv_raw;
logic [63:0] fv_params;

// -- REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
    state_C <= ST_IDLE;
    regex_cnfg_C <= 0;
end
else
    state_C <= state_N;

    regex_cnfg_C <= regex_cnfg_N;
    len_C <= len_N;
    lvaddr_C <= lvaddr_N;
    rvaddr_C <= rvaddr_N;
    qp_C <= qp_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
            if(fv_sink.valid)
                if(fv_params[0]) 
                    state_N = ST_CONFIG_1;
                else 
                    state_N = ST_READ;
		
        ST_CONFIG_1:
            if(fv_sink.valid)
                state_N = ST_CONFIG_2;

        ST_CONFIG_2:
            if(fv_sink.valid)
                state_N = ST_CONFIG_3;

        ST_CONFIG_3:
            if(cnfg.ready)
                state_N = ST_IDLE;

        ST_READ:
            if(bpss_rd_req.ready && params.ready) 
                state_N = ST_IDLE;

	endcase // state_C
end

// -- DP
always_comb begin: DP
    regex_cnfg_N = regex_cnfg_C;
    len_N = len_C;
    lvaddr_N = lvaddr_C;
    rvaddr_N = rvaddr_C;
    qp_N = qp_C;

    // Incoming
    fv_qp = fv_sink.req.qpn;
    fv_rvaddr = fv_sink.req.pkg.base.lvaddr;
    fv_lvaddr = fv_sink.req.pkg.base.rvaddr;
    fv_len = fv_sink.req.pkg.base.len;
    fv_params = fv_sink.req.pkg.base.params;
    fv_raw = fv_sink.req.msg;

    // FV sink
    fv_sink.ready = 1'b0;

    // RD host
    bpss_rd_req.valid = 1'b0;
    bpss_rd_req.req = 0;
    bpss_rd_req.req.vaddr = lvaddr_C;
    bpss_rd_req.req.len = len_C; 
    bpss_rd_req.req.ctl = 1'b1;

    // Params
    params.valid = 1'b0;
    params.data = {qp_C, rvaddr_C};

    // Config intf
    cnfg.valid = 1'b0;
    cnfg.data = regex_cnfg_C;

    // DP fsm
    case(state_C)
        ST_IDLE: begin
            if(fv_sink.valid) begin
                fv_sink.ready = 1'b1;

                if(fv_params[0]) begin
                    regex_cnfg_N[511] = 1'b1;
                    regex_cnfg_N[256+:128] = fv_raw[127:0];
                end
                else begin
                    len_N = fv_len[LEN_BITS-1:0];
                    lvaddr_N = fv_lvaddr;
                    rvaddr_N = fv_rvaddr;
                    qp_N = fv_qp;
                end
            end
        end

        ST_CONFIG_1: begin
            if(fv_sink.valid) begin
                fv_sink.ready = 1'b1;

                regex_cnfg_N[128+:128] = fv_raw[127:0];
            end
        end

        ST_CONFIG_2: begin
            if(fv_sink.valid) begin
                fv_sink.ready = 1'b1;

                regex_cnfg_N[0+:128] = fv_raw[127:0];
            end
        end


        ST_CONFIG_3: begin
            cnfg.valid = 1'b1;
        end

        ST_READ: begin
            if(bpss_rd_req.ready && params.ready) begin
                bpss_rd_req.valid = 1'b1;
                params.valid = 1'b1;
            end
        end 

    endcase // state_C

end

endmodule