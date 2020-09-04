import lynxTypes::*;

module stride_req #(
    parameter integer   STR_DATA_BITS = AXI_DATA_BITS  
) (
    input  logic        aclk,
    input  logic        aresetn,

    // RDMA
    metaIntf.s          fv_sink,
    metaIntf.m          fv_src,

    // Host
    reqIntf.m           rd_req_user,

    // Sequence
    metaIntf.m          params
);

localparam integer APP_WRITE = 1;
localparam integer BEAT_LOG_BYTES = STR_DATA_BITS/8;
localparam integer BEAT_LOG_BITS = $clog2(BEAT_LOG_BYTES);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_READ} state_t;
logic [0:0] state_C, state_N;

// Regs
logic [31:0] cnt_C, cnt_N;
logic [VADDR_BITS-1:0] laddr_C, laddr_N;
logic [31:0] stride_C, stride_N;
logic [31:0] dwidth_C, dwidth_N;
logic ctl_C, ctl_N;

// Int
logic [VADDR_BITS-1:0] fv_raddr;
logic [VADDR_BITS-1:0] fv_laddr;
logic [31:0] fv_dwidth;
logic [31:0] fv_stride;
logic [31:0] fv_nbytes;

logic [31:0] params_ntr;
logic [31:0] params_dwidth;

// -- REG
always_ff @(posedge aclk, negedge aresetn) begin: PROC_REG
if (aresetn == 1'b0) begin
    state_C <= ST_IDLE;
end
else
    state_C <= state_N;
    cnt_C <= cnt_N;
    laddr_C <= laddr_N;
    stride_C <= stride_N;
    dwidth_C <= dwidth_N;
    ctl_C <= ctl_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = (fv_sink.valid && fv_src.ready && params.ready) ? ST_READ : ST_IDLE;

        ST_READ:
            state_N = rd_req_user.ready ? ((cnt_C == 0) ? ST_IDLE : ST_READ) : ST_READ;

	endcase // state_C
end

// -- DP
always_comb begin: DP
    cnt_N = cnt_C;
    laddr_N = laddr_C;
    stride_N = stride_C;
    dwidth_N = dwidth_C;
    ctl_N = ctl_C;

    // Incoming
    fv_raddr = fv_sink.data[64+:48];
    fv_laddr = fv_sink.data[112+:48];
    fv_dwidth = fv_sink.data[160+:32];
    fv_stride = fv_sink.data[192+:32];
    fv_nbytes = fv_sink.data[224+:32];

    // FV sink
    fv_sink.ready = 1'b0;

    // FV src
    fv_src.valid = 1'b0;

    fv_src.data = 0;
    fv_src.data[0+:5] = APP_WRITE;
    fv_src.data[5+:24] = fv_sink.data[5+:24];
    fv_src.data[64+:48] = 0;
    fv_src.data[112+:48] = fv_raddr;
    fv_src.data[160+:32] = fv_nbytes;

    // RD host
    rd_req_user.valid = 1'b0;

    rd_req_user.req = 0;
    rd_req_user.req.vaddr = laddr_C;
    rd_req_user.req.len = (1 << dwidth_C);
    rd_req_user.req.ctl = ctl_C;

    // Params
    params.valid = 1'b0;
    
    params_dwidth = fv_dwidth;
    params_ntr = (fv_dwidth >= BEAT_LOG_BITS) ? fv_nbytes >> BEAT_LOG_BITS : fv_nbytes >> fv_dwidth;
    params.data = {params_dwidth, params_ntr};

    // DP fsm
    case(state_C)
        ST_IDLE: begin
            if(fv_sink.valid && fv_src.ready && params.ready) begin
                fv_sink.ready = 1'b1;
                fv_src.valid = 1'b1;
                params.valid = 1'b1;

                cnt_N = (fv_nbytes >> fv_dwidth) - 1;
                laddr_N = fv_laddr;
                stride_N = fv_stride;
                dwidth_N = fv_dwidth;
                ctl_N = (cnt_N == 0);
            end
        end

        ST_READ: begin
            if(rd_req_user.ready) begin
                rd_req_user.valid = 1'b1;

                cnt_N = cnt_C - 1;
                laddr_N = laddr_C + stride_C;
                ctl_N = (cnt_N == 0);
            end
        end 

    endcase // state_C

end

endmodule