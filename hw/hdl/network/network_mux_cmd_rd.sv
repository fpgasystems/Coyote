import lynxTypes::*;

module network_mux_cmd_rd (
    input  logic            aclk,
    input  logic            aresetn,
    
    rdmaIntf.s              req_snk,
    reqIntf.m               req_src [N_REGIONS],
    AXI4S.s                 axis_rd_data_snk [N_REGIONS],
    AXI4S.m                 axis_rd_data_src
);

logic [N_REGIONS-1:0] ready_src;
logic [N_REGIONS-1:0] valid_src;
logic ready_snk;
logic valid_snk;
req_t [N_REGIONS-1:0] request_src;
rdma_req_t request_snk;

logic seq_snk_valid;
logic seq_snk_ready;
logic seq_src_valid;
logic seq_src_ready;

logic [N_REQUEST_BITS-1:0] id_snk;
logic [N_REQUEST_BITS-1:0] id_next;
logic [LEN_BITS-1:0] len_snk;
logic [LEN_BITS-1:0] len_next;
logic host_snk;

reqIntf req_que [N_REGIONS] ();

// --------------------------------------------------------------------------------
// -- I/O !!! interface 
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign req_que[i].valid = valid_src[i];
    assign ready_src[i] = req_que[i].ready;
    assign req_que[i].req = request_src[i]; 

    req_queue inst_req_que (.aclk(aclk), .aresetn(aresetn), .req_in(req_que[i]), .req_out(req_src[i])); 
end

assign valid_snk = req_snk.valid;
assign req_snk.ready = ready_snk;
assign request_snk = req_snk.req;
assign id_snk = req_snk.req.id;
assign len_snk = req_snk.req.len[LEN_BITS-1:0];
assign host_snk = req_snk.req.host;

// --------------------------------------------------------------------------------
// -- Mux command
// --------------------------------------------------------------------------------
always_comb begin
    if(host_snk) begin
        seq_snk_valid = seq_snk_ready & ready_src[id_snk] & valid_snk;
        ready_snk = seq_snk_ready & ready_src[id_snk];
    end
    else begin
        seq_snk_valid = seq_snk_ready & valid_snk;
        ready_snk = seq_snk_ready;
    end
end

for(genvar i = 0; i < N_REGIONS; i++) begin
    assign valid_src[i] = ((id_snk == i) && host_snk) ? seq_snk_valid : 1'b0;

    assign request_src[i].vaddr = request_snk.vaddr;
    assign request_src[i].len = request_snk.len;
    assign request_src[i].sync = request_snk.sync;
    assign request_src[i].ctl = request_snk.ctl;
end

queue #(
    .QTYPE(logic [N_REQUEST_BITS+LEN_BITS-1:0])
) inst_seq_que_snk (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(seq_snk_valid),
    .rdy_snk(seq_snk_ready),
    .data_snk({id_snk, len_snk}),
    .val_src(seq_src_valid),
    .rdy_src(seq_src_ready),
    .data_src({id_next, len_next})
);

// --------------------------------------------------------------------------------
// -- Mux data
// --------------------------------------------------------------------------------
localparam integer BEAT_LOG_BITS = $clog2(AXI_DATA_BITS/8);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

logic [N_REQUEST_BITS-1:0] id_C, id_N;
logic [LEN_BITS-BEAT_LOG_BITS:0] cnt_C, cnt_N;
logic [LEN_BITS-BEAT_LOG_BITS:0] n_beats_C, n_beats_N;

logic tr_done; 

logic [LEN_BITS-BEAT_LOG_BITS:0] cnt_req;

logic [AXI_DATA_BITS-1:0] axis_rd_data_src_tdata;
logic [AXI_DATA_BITS/8-1:0] axis_rd_data_src_tkeep;
logic axis_rd_data_src_tlast;
logic axis_rd_data_src_tvalid;
logic axis_rd_data_src_tready;

logic [N_REGIONS-1:0][AXI_DATA_BITS-1:0] axis_rd_data_snk_tdata;
logic [N_REGIONS-1:0][AXI_DATA_BITS/8-1:0] axis_rd_data_snk_tkeep;
logic [N_REGIONS-1:0] axis_rd_data_snk_tlast;
logic [N_REGIONS-1:0] axis_rd_data_snk_tvalid;
logic [N_REGIONS-1:0] axis_rd_data_snk_tready;

// --------------------------------------------------------------------------------
// -- I/O !!! interface 
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_REGIONS; i++) begin
    axis_data_fifo_512 inst_data_que (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(axis_rd_data_snk[i].tvalid),
        .s_axis_tready(axis_rd_data_snk[i].tready),
        .s_axis_tdata(axis_rd_data_snk[i].tdata),
        .s_axis_tkeep(axis_rd_data_snk[i].tkeep),
        .s_axis_tlast(axis_rd_data_snk[i].tlast),
        .m_axis_tvalid(axis_rd_data_snk_tvalid[i]),
        .m_axis_tready(axis_rd_data_snk_tready[i]),
        .m_axis_tdata(axis_rd_data_snk_tdata[i]),
        .m_axis_tkeep(axis_rd_data_snk_tkeep[i]),
        .m_axis_tlast(axis_rd_data_snk_tlast[i])
    );
end

assign axis_rd_data_src.tvalid = axis_rd_data_src_tvalid;
assign axis_rd_data_src.tdata  = axis_rd_data_src_tdata;
assign axis_rd_data_src.tkeep  = axis_rd_data_src_tkeep;
assign axis_rd_data_src.tlast  = axis_rd_data_src_tlast;
assign axis_rd_data_src_tready = axis_rd_data_src.tready;

// REG
always_ff @(posedge aclk, negedge aresetn) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;
end
else
	state_C <= state_N;
    cnt_C <= cnt_N;
    id_C <= id_N;
    n_beats_C <= n_beats_N;
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = (seq_src_ready) ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = tr_done ? (seq_src_ready ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// DP
always_comb begin: DP
    cnt_N = cnt_C;
    id_N = id_C;
    n_beats_N = n_beats_C;
    
    // Transfer done
    tr_done = (cnt_C == n_beats_C) && (axis_rd_data_src_tvalid & axis_rd_data_src_tready);

    seq_src_valid = 1'b0;

    // Last gen (not needed)
    //axis_rd_data_src_tlast = 1'b0;

    case(state_C)
        ST_IDLE: begin
            cnt_N = 0;
            if(seq_src_ready) begin
                seq_src_valid = 1'b1;
                id_N = id_next;
                n_beats_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
            end
        end
            
        ST_MUX: begin
            if(tr_done) begin
                cnt_N = 0;
                if(seq_src_ready) begin
                    seq_src_valid = 1'b1;
                    id_N = id_next;
                    n_beats_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
                end
            end
            else begin
                cnt_N = (axis_rd_data_src_tvalid & axis_rd_data_src_tready) ? cnt_C + 1 : cnt_C;
            end

            //axis_rd_data_src_tlast = (cnt_C == n_beats_C) ? 1'b1 : 1'b0;
        end

    endcase
end

// Mux
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign axis_rd_data_snk_tready[i] = (state_C == ST_MUX) ? ((i == id_C) ? axis_rd_data_src_tready : 1'b0) : 1'b0; 
end

assign axis_rd_data_src_tvalid = (state_C == ST_MUX) ? axis_rd_data_snk_tvalid[id_C] : 1'b0;
assign axis_rd_data_src_tdata = axis_rd_data_snk_tdata[id_C];
assign axis_rd_data_src_tkeep = axis_rd_data_snk_tkeep[id_C];
assign axis_rd_data_src_tlast = axis_rd_data_snk_tlast[id_C];

/*
logic [31:0] cnt_data, cnt_last, cnt_req;

always_ff @(posedge aclk, negedge aresetn) begin
if (aresetn == 1'b0) begin
	cnt_data <= 0;
	cnt_last <= 0;
	cnt_req <= 0;
end
else
	cnt_data <= (axis_rd_data_src.tvalid & axis_rd_data_src.tready) ? cnt_data + 1 : cnt_data;
	cnt_last <= (axis_rd_data_src.tvalid & axis_rd_data_src.tready & axis_rd_data_src.tlast) ? cnt_last + 1 : cnt_last;
	cnt_req <= (req_snk.valid & req_snk.ready) ? cnt_req + 1 : cnt_req;
end


ila_cmd_rd inst_ila_rd (
    .clk(aclk),
    .probe0(state_C),
    .probe1(id_C),
    .probe2(cnt_C),
    .probe3(n_beats_C),
    .probe4(cnt_data),
    .probe5(cnt_last),
    .probe6(cnt_req),
    .probe7(tr_done),
    .probe8(req_snk.valid),
    .probe9(req_snk.ready),
    .probe10(id_snk),
    .probe11(host_snk),
    .probe12(axis_rd_data_snk_tvalid[0]),
    .probe13(axis_rd_data_snk_tready[0]),
    .probe14(axis_rd_data_snk_tlast[0]),
    .probe15(axis_rd_data_snk_tvalid[1]),
    .probe16(axis_rd_data_snk_tready[1]),
    .probe17(axis_rd_data_snk_tlast[1]),
    .probe18(axis_rd_data_snk_tvalid[2]),
    .probe19(axis_rd_data_snk_tready[2]),
    .probe20(axis_rd_data_snk_tlast[2]),
    .probe21(axis_rd_data_src_tvalid),
    .probe22(axis_rd_data_src_tready),
    .probe23(axis_rd_data_src_tlast)
);
*/

endmodule