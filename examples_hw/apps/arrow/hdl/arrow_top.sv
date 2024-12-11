`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

module arrow_top (
    // AXI4L CONTROL
    AXI4L.s                     axi_ctrl,

    // NOTIFY
    metaIntf.m                  notify,

    // DESCRIPTORS
    metaIntf.m                  sq_rd,
    metaIntf.m                  sq_wr,
    metaIntf.s                  cq_rd,
    metaIntf.s                  cq_wr,
    metaIntf.s                  rq_rd,
    metaIntf.s                  rq_wr,

    // HOST DATA STREAMS
    AXI4SR.s                    axis_host_recv [N_STRM_AXI],
    AXI4SR.m                    axis_host_send [N_STRM_AXI],

    // RDMA DATA STREAMS REQUESTER
    AXI4SR.s                    axis_rreq_recv [N_RDMA_AXI],
    AXI4SR.m                    axis_rreq_send [N_RDMA_AXI],

    // RDMA DATA STREAMS RESPONDER
    AXI4SR.s                    axis_rrsp_recv [N_RDMA_AXI],
    AXI4SR.m                    axis_rrsp_send [N_RDMA_AXI],

    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn
);

    // tieoffs
    // NOTE: I could not get notify to work
    //notify.tie_off_m();
    always_comb axis_rreq_recv[0].tie_off_s();
    always_comb axis_rrsp_send[0].tie_off_m();

`include "custom_types.svh"

`ifdef XILINX_SIMULATOR
    always_comb begin
        sq_rd.data.rsrvd = 0;
        sq_rd.data.host = 0;
        sq_rd.data.actv = 0;
        sq_rd.data.offs = 0;
        sq_rd.data.vfid = 0;
        sq_wr.data.rsrvd = 0;
        sq_wr.data.host = 0;
        sq_wr.data.actv = 0;
        sq_wr.data.offs = 0;
        sq_wr.data.vfid = 0;
    end
`endif

    // some params
    localparam integer NRegs = 32;
    localparam integer AddrLsb = 3;
    localparam integer AddrMsb = 8;

    localparam integer NPipelineStages = 7;

    localparam integer COperNoOp = 0;
    localparam integer COperLocalRead = 1;
    localparam integer COperLocalWrite = 2;
    localparam integer COperLocalTransfer = 3;
    localparam integer COperLocalOffload = 4;
    localparam integer COperLocalSync = 5;
    localparam integer COperRemoteRdmaRead = 6;
    localparam integer COperRemoteRdmaWrite = 7;
    localparam integer COperRemoteRdmaSend = 8;
    localparam integer COperRemoteTcpSend = 9;

    parameter integer StrmCard = 0;
    parameter integer StrmHost = 1;
    parameter integer StrmTcp = 2;
    parameter integer StrmRdma = 3;

    // Register Addresses
    localparam integer RegDescAddr = 0;
    localparam integer RegDescLen = 1;
    localparam integer RegWriteAddr = 2;
    localparam integer RegWriteLen = 3;

    localparam integer RegPcCyclesTotal = 20;
    localparam integer RegPcCyclesWaitingForTransfer = 21;
    localparam integer RegPcCyclesRequesting = 22;
    localparam integer RegPcCyclesReceving = 23;
    localparam integer RegPcCyclesSending = 24;

    localparam integer RegOpcodes = 30;
    localparam integer RegConfig = 31;

    // States
    localparam byte StateIdle = 0;                      // Waiting for the transfer to start
    localparam byte StateReadDesc = 1;                  // no descriptor data, read next word
    localparam byte StateRequestBuffer = 2;             // request next buffer
    localparam byte StateWaitForTransferToEnd = 3;      // wait for the transfer to end
    localparam byte StateNotificationTransfer = 4;      // start the notification transfer
    localparam byte StateWaitNotificationTransfer = 5;  // wait for the notification transfer to end
    localparam byte StateServerWait = 6;                // run as server, only wait for completion

    // interfaces
    metaIntf #(.STYPE(wreq_t)) sq_rd_int(); // internal interface
    metaIntf #(.STYPE(wreq_t)) sq_wr_int(); // internal interface
    metaIntf #(.STYPE(wreq_t)) rq_wr_int(); // internal interface for modifying values
    metaIntf #(.STYPE(wreq_t)) sq_wr_pre(); // intermediate interface after req_mux
    AXI4SR axis_concat_out();


    // signals
    logic [AddrMsb-1:0] axi_ctrl_awaddr;
    logic [AddrMsb-1:0] axi_ctrl_araddr;
    logic ctrl_arready;
    logic ctrl_awready;
    logic ctrl_bvalid;
    logic ctrl_wready;
    logic ctrl_rvalid;
    logic [1:0] ctrl_rresp;
    logic [63:0] ctrl_rdata;

    logic sq_rd_valid;
    logic req_mux_reset;
    logic strm_mux_reset;

    logic axis_host_recv_0_tready;
    logic axis_host_send_0_tvalid;
    logic axis_concat_out_tvalid;
    logic axis_concat_out_tlast;
    logic sq_wr_unenabled_valid;

    // performance counters
    logic [63:0] pc_cycles_total;
    logic [63:0] pc_cycles_waiting_for_transfer;
    logic [63:0] pc_cycles_requesting;
    logic [63:0] pc_cycles_receiving;
    logic [63:0] pc_cycles_sending;


    // control registers
    logic [63:0] read_desc_addr;    // 0
    logic [63:0] read_desc_len;     // 1
    logic [63:0] write_addr;        // 2
    logic [63:0] write_len;         // 3

    // config registers
    logic [63:0] cfg_opcodes;       // 30
    logic [63:0] cfg_register;      // 31

    // flag aliases
    logic cfg_flag_en_notify_transfer;
    logic cfg_flag_en_write;
    logic cfg_flag_en_server;
    logic cfg_flag_local_only;
    logic cfg_flag_custom_addr;
    logic cfg_flag_custom_len;
    logic cfg_flag_rdma_mode;
    logic [31:0] cfg_max_transfer_mask;
    logic [7:0] cfg_max_transfer_len_bits;

    assign cfg_flag_en_notify_transfer = cfg_register[0];
    assign cfg_flag_en_write = cfg_register[1];
    assign cfg_flag_en_server = cfg_register[2];
    assign cfg_flag_local_only = cfg_register[3];
    assign cfg_flag_custom_addr = cfg_register[4];
    assign cfg_flag_custom_len = cfg_register[5];
    assign cfg_flag_rdma_mode = cfg_register[6];
    //assign _ = cfg_register[7];
    assign cfg_max_transfer_len_bits = cfg_register[15:8];
    assign cfg_max_transfer_mask = (32'd1 << cfg_max_transfer_len_bits) - 1;

    // opcodes
    logic [4:0] opcode_local_read;
    logic [4:0] opcode_local_write;
    logic [4:0] opcode_rdma_write;

    assign opcode_local_read = cfg_opcodes[4:0];
    assign opcode_local_write = cfg_opcodes[12:8];
    assign opcode_rdma_write = cfg_opcodes[20:16];


    // descriptor buffer and accompanying registers
    logic [511:0] desc_buffer;
    logic [63:0] n_desc;
    logic [7:0] n_desc_loaded;
    logic [63:0] n_buffers_requested;
    logic [63:0] desc_index;

    // state register
    logic [7:0] state = StateIdle;

    // some flags
    logic start_flag = 0;

    // output of barrel shifter
    logic [511:0] shifted_data;
    logic [63:0] shifted_keep;
    logic [6:0] shifted_offset;
    logic shifted_valid;
    logic shifted_last;
    logic shifted_last_transfer_flag;

    logic pipeline_reset;
    logic tlast_databeat;
    logic computed_last_transfer_flag;
    logic last_tlast_databeat_seen;
    logic [63:0] transfer_counter;
    logic [63:0] byte_counter;
    logic [63:0] byte_counter_plus_64;
    logic [63:0] n_read_transfers;

    logic [511:0] output_register;
    logic [63:0] output_keep;
    logic [6:0] output_offset;

    logic last_data_waiting;

    // assignments
    assign axi_ctrl_awaddr = axi_ctrl.awaddr[AddrMsb+AddrLsb-1:AddrLsb];
    assign axi_ctrl_araddr = axi_ctrl.araddr[AddrMsb+AddrLsb-1:AddrLsb];

    assign cq_rd.ready = 1;
    assign cq_wr.ready = 1;

    always_comb req_mux_reset = aresetn & (state != StateIdle);
    always_comb strm_mux_reset = aresetn & (state != StateIdle);

    assign axi_ctrl.arready = ctrl_arready;
    assign axi_ctrl.awready = ctrl_awready;
    assign axi_ctrl.bvalid = ctrl_bvalid;
    assign axi_ctrl.wready = ctrl_wready;
    assign axi_ctrl.rvalid = ctrl_rvalid;
    assign axi_ctrl.rresp = ctrl_rresp;
    assign axi_ctrl.rdata = ctrl_rdata;

    assign axis_host_recv[0].tready = axis_host_recv_0_tready;
    assign axis_host_send[0].tvalid = axis_host_send_0_tvalid;
    assign axis_concat_out.tlast = axis_concat_out_tlast;

    // tready is used for stepping the pipeline (and enable for the barrel shifter)
    assign axis_host_recv[1].tready = axis_concat_out.tready | ~cfg_flag_en_write;
    assign axis_concat_out.tvalid = axis_concat_out_tvalid & cfg_flag_en_write;

    // mark any tlast databeat on stream 1 (or rrsp_recv 0 if running as server)
    assign tlast_databeat = cfg_flag_en_server
                            ? (axis_host_send[1].tready
                                && axis_host_send[1].tvalid
                                && axis_host_send[1].tlast)
                            : (axis_host_recv[1].tready
                                && axis_host_recv[1].tvalid
                                && axis_host_recv[1].tlast);
    assign byte_counter_plus_64 = byte_counter + 64'd64;

    // instantiate the barrel shifter
    barrel_shifter_axis_512 inst_barrel_shifter(
        .aclk(aclk),
        .aresetn(aresetn & pipeline_reset), // note the additional reset source
        .enable(axis_concat_out.tready | ~cfg_flag_en_write), // enable when recv end is ready

        .data_in(axis_host_recv[1].tdata),
        .keep_in(axis_host_recv[1].tkeep),
        .valid_in(axis_host_recv[1].tvalid),
        .last_in(axis_host_recv[1].tlast),
        .last_transfer_flag_in(computed_last_transfer_flag),

        .data_out(shifted_data),
        .keep_out(shifted_keep),
        .valid_out(shifted_valid),
        .last_out(shifted_last),
        .last_transfer_flag_out(shifted_last_transfer_flag),

        .offset_out(shifted_offset)
    );
    request_splitter inst_splitter_sq_rd (
        .aclk(aclk),
        .aresetn(aresetn),
        .max_len_mask(cfg_max_transfer_mask),

        .req_in(sq_rd_int),
        .req_out(sq_rd)
    );

    // Transfer data from CPU memory to FPGA
    always_comb begin
        sq_rd_int.data.opcode = opcode_local_read;
        sq_rd_int.data.strm = StrmHost; // STREAM_HOST
        sq_rd_int.data.mode = 0;
        sq_rd_int.data.rdma = 0;
        sq_rd_int.data.remote = 0;
        sq_rd_int.data.pid = 0;
        sq_rd_int.data.last = 1;
        sq_rd_int.valid = sq_rd_valid;
    end


    // handle remote requests
    always_comb begin
        rq_wr_int.data.opcode = opcode_local_write; // should always target local memory
        rq_wr_int.data.strm = StrmHost; // should always target local memory
        rq_wr_int.data.mode = rq_wr.data.mode;
        rq_wr_int.data.rdma = 0;
        rq_wr_int.data.remote = 0;
        rq_wr_int.data.pid = rq_wr.data.pid;
        rq_wr_int.data.last = 1; // this MUST be 1, otherwise everything burns
        rq_wr_int.data.dest = 1; // use host memory stream 1
        rq_wr_int.data.len = cfg_flag_custom_addr ? write_len : rq_wr.data.len;
        rq_wr_int.data.vaddr = cfg_flag_custom_len ? write_addr : rq_wr.data.vaddr;
        rq_wr_int.valid = rq_wr.valid; // TODO: handle disabled writes
        rq_wr.ready = rq_wr_int.ready;
    end

    // instantiate request splitters for sq_wr and complete constant assignments
    request_mux inst_req_mux_sq_wr(
        .aclk(aclk),
        .aresetn(req_mux_reset),
        .select(cfg_flag_en_server),
        .intf_in_1(sq_wr_int),
        .intf_in_2(rq_wr_int),
        .intf_out(sq_wr_pre)
    );
    request_splitter inst_splitter_sq_wr (
        .aclk(aclk),
        .aresetn(aresetn),
        .max_len_mask(cfg_max_transfer_mask),

        .req_in(sq_wr_pre),
        .req_out(sq_wr)
    );

    // Transfer data from FPGA to CPU memory
    always_comb begin
        sq_wr_int.data.opcode = cfg_flag_local_only ? opcode_local_write : opcode_rdma_write;
        sq_wr_int.data.strm = cfg_flag_local_only ? StrmHost : StrmRdma;
        sq_wr_int.data.mode = cfg_flag_local_only ? 0 : cfg_flag_rdma_mode;
        sq_wr_int.data.rdma = ~cfg_flag_local_only;
        sq_wr_int.data.remote = ~cfg_flag_local_only;
        sq_wr_int.data.pid = 0;
        sq_wr_int.data.last = 1;
        sq_wr_int.valid = sq_wr_unenabled_valid & cfg_flag_en_write;
    end

    always_comb begin
        notify.valid = 0;
        notify.data.pid = {
            state[2:0],
            tlast_databeat,
            last_data_waiting,
            computed_last_transfer_flag
        };
        notify.data.value = {
            cfg_register[7:0],
            6'd0,
            sq_wr_unenabled_valid,
            axis_concat_out_tvalid,
            n_read_transfers[7:0],
            transfer_counter[7:0]
        };
    end

    // stream multiplexer
    stream_mux inst_stream_mux(
        .aresetn(strm_mux_reset),
        .server(cfg_flag_en_server),
        .local_only(cfg_flag_local_only),
        .host_in(axis_concat_out),
        .rdma_in(axis_rrsp_recv[0]),
        .host_out(axis_host_send[1]),
        .rdma_out(axis_rreq_send[0])
    );

    // compute the last transfer flag
    assign computed_last_transfer_flag =
        (((transfer_counter + 'd1) == n_read_transfers)
                && (n_buffers_requested == n_desc)
                && tlast_databeat)
                || last_tlast_databeat_seen;

    // State Machine
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            // state
            state <= StateIdle;
            // descriptor registers
            n_desc <= 0;
            n_desc_loaded <= 0;
            n_buffers_requested <= 0;
            desc_index <= 0;
            desc_buffer <= 0;
            // internal flags
            // recv stream 0 ready
            axis_host_recv_0_tready <= 0;
            // send stream 0
            axis_host_send[0].tdata <= 0;
            axis_host_send[0].tkeep <= 0;
            axis_host_send[0].tid <= 0;
            axis_host_send[0].tlast <= 0;
            axis_host_send_0_tvalid <= 0;
            // request interface
            sq_wr_unenabled_valid <= 0;
            sq_wr_int.data.dest <= 0;
            sq_wr_int.data.vaddr <= 0;
            sq_wr_int.data.len <= 0;
            sq_rd_valid <= 0;
            sq_rd_int.data.dest <= 0;
            sq_rd_int.data.vaddr <= 0;
            sq_rd_int.data.len <= 0;

            // counting transfers
            n_read_transfers <= 0;

            // pipeline reset is not necessary here (aresetn is another source)
            pipeline_reset <= 1;
        end
        else begin
            case (state)
                StateIdle: begin
                        // reset the pipeline so it is ready for a start
                        pipeline_reset <= 0;

                        // check to see if the transfer should start
                        if (start_flag) begin
                            // disable the pipeline reset
                            pipeline_reset <= 1;
                            // transition
                            if (read_desc_addr != 0) begin
                                if (cfg_flag_en_server) begin
                                    // if this is a server, then setup is easy
                                    state <= StateServerWait;

                                    // server must only wait for the number of rdma transfers
                                    n_read_transfers <= read_desc_len;
                                end
                                else begin
                                    // client mode setup is a little more complicated
                                    state <= StateRequestBuffer;

                                    // prepare descriptor loading state
                                    // divide by 16 (two 8 byte numbers per buffer)
                                    n_desc <= read_desc_len >> 4;
                                    n_desc_loaded <= 0;
                                    n_buffers_requested <= 0;

                                    // create write request
                                    sq_wr_int.data.vaddr <= write_addr;
                                    sq_wr_int.data.len <= write_len;
                                    // Note: stream 1 for host memory, stream 0 for RDMA
                                    sq_wr_int.data.dest <= cfg_flag_local_only ? 1 : 0;
                                    sq_wr_unenabled_valid <= 1;

                                    // create read request for descriptor
                                    sq_rd_int.data.vaddr <= read_desc_addr;
                                    sq_rd_int.data.len <= read_desc_len;
                                    sq_rd_int.data.dest <= 0; // use stream 0 for the descriptor
                                    sq_rd_valid <= 1;

                                    // transfer counting
                                    n_read_transfers <= 0;
                                end
                            end
                            else begin
                                // desc_addr is 0, read from target addr and do not write
                                // calulate the number of transfers that need to happen
                                n_read_transfers <= (
                                    (write_len & ~cfg_max_transfer_mask)
                                    >> cfg_max_transfer_len_bits
                                ) + ((write_len & cfg_max_transfer_mask) != 0);

                                // n_desc must equal n_buffers_requested
                                n_buffers_requested <= 0;
                                n_desc <= 0;

                                // request reads
                                sq_rd_int.data.vaddr <= write_addr;
                                sq_rd_int.data.len <= write_len;
                                sq_rd_int.data.dest <= 1;
                                sq_rd_valid <= 1;

                                // wait for the transfer to end
                                if (~sq_rd_valid) begin
                                    state <= StateWaitForTransferToEnd;
                                end
                            end
                        end
                    end
                StateReadDesc:
                    begin
                        if (axis_host_recv[0].tvalid & axis_host_recv_0_tready) begin
                            axis_host_recv_0_tready <= 0; // transfer done

                            desc_buffer <= axis_host_recv[0].tdata;
                            state <= StateRequestBuffer;
                            case (axis_host_recv[0].tkeep)
                                64'h000000000000ffff: n_desc_loaded <= 1;
                                64'h00000000ffffffff: n_desc_loaded <= 2;
                                64'h0000ffffffffffff: n_desc_loaded <= 3;
                                64'hffffffffffffffff: n_desc_loaded <= 4;
                                default:
                                    $display("only 16, 32, 48 and 64 keep bits are supported");
                            endcase
                        end
                    end
                StateRequestBuffer:
                    begin
                        if (n_desc_loaded == 0 && n_buffers_requested != n_desc) begin
                            axis_host_recv_0_tready <= 1; // ready to read now
                            desc_index <= 0;
                            state <= StateReadDesc;
                        end
                        else begin
                            if (n_buffers_requested == n_desc) begin
                                // transition copy wait state
                                state <= StateWaitForTransferToEnd;
                            end
                            else begin
                                // request the next buffer
                                if (~sq_rd_valid) begin
                                    // book-keeping
                                    n_buffers_requested <= n_buffers_requested + 1;
                                    n_desc_loaded <= n_desc_loaded - 1;
                                    desc_index <= desc_index + 1;

                                    // send read request
                                    sq_rd_int.data.vaddr <= desc_buffer[(desc_index*128 + 0)+:64];
                                    sq_rd_int.data.len <= desc_buffer[(desc_index*128 + 64)+:64];
                                    sq_rd_int.data.dest <= 1; // use stream 1 for data
                                    sq_rd_valid <= 1;

                                    // calculate number of transfers necessary for this buffer
                                    n_read_transfers <= n_read_transfers + (
                                        (
                                            (
                                                desc_buffer[(desc_index*128 + 64)+:64]
                                                 & ~cfg_max_transfer_mask
                                            ) >> cfg_max_transfer_len_bits
                                        ) +
                                        (
                                            (desc_buffer[(desc_index*128 + 64)+:64]
                                             & cfg_max_transfer_mask
                                        )  != 0)
                                        );
                                end
                            end
                        end
                    end
                StateWaitForTransferToEnd:
                    begin

                        // the following is sufficient, since the descriptor must have been written by the last clock cycle
                        if (axis_concat_out_tlast & shifted_last_transfer_flag) begin
                            if (cfg_flag_en_notify_transfer)
                                state <= StateNotificationTransfer;
                            else
                                state <= StateIdle;
                        end
                    end
                StateNotificationTransfer:
                    begin
                        axis_host_send[0].tdata <= {
                            512'd0
                        };
                        axis_host_send[0].tkeep <= 64'hffffffffffffffff;
                        axis_host_send[0].tlast <= 1;
                        axis_host_send[0].tid <= 0;
                        axis_host_send_0_tvalid <= 1;

                        state <= StateWaitNotificationTransfer;
                    end
                StateWaitNotificationTransfer:
                    begin
                        if (axis_host_send_0_tvalid & axis_host_send[0].tready) begin
                            axis_host_send[0].tdata <= 0;
                            axis_host_send[0].tkeep <= 0;
                            axis_host_send[0].tlast <= 0;
                            axis_host_send[0].tid <= 0;
                            axis_host_send_0_tvalid <= 0;

                            state <= StateIdle;
                        end
                    end
                StateServerWait:
                    begin
                        if (n_read_transfers == transfer_counter) begin
                            // transition back to StateIdle once all transfers have completed
                            state <= StateIdle;
                        end
                    end
                default:
                    $display("This should never happen (state: %d)!", state);
            endcase
            // handle valid signal for sq_wr
            if (sq_wr_int.ready & sq_wr_unenabled_valid) begin
                sq_wr_unenabled_valid <= 0;
            end
            // handle valid signal for sq_rd
            if (sq_rd_int.ready & sq_rd_valid) begin
                sq_rd_valid <= 0;
            end
        end
    end

    // copying machine
    always_ff @(posedge aclk) begin
        if (~(aresetn & pipeline_reset)) begin
            axis_concat_out.tdata <= 0;
            axis_concat_out.tkeep <= 0;
            axis_concat_out.tid <= 0;
            axis_concat_out_tlast <= 0;
            axis_concat_out_tvalid <= 0;

            transfer_counter <= 0;
            byte_counter <= 0;

            output_register <= 0;
            output_keep <= 0;
            output_offset <= 0;

            last_data_waiting <= 0;
            last_tlast_databeat_seen <= 0;
            //computed_last_transfer_flag <= 0;
        end
        else begin
            // count completed transfers
            if (tlast_databeat) begin
                transfer_counter <= transfer_counter + 64'd1;
            end
            // compute the last_transfer_flag
            if (((transfer_counter + 'd1) == n_read_transfers)
                && (n_buffers_requested == n_desc)
                && tlast_databeat) begin
                // the next tlast is the last of this invocation
                //computed_last_transfer_flag <= 1;
                last_tlast_databeat_seen <= 1;
            end
//            else if (((transfer_counter + 'd1) != n_read_transfers)
//                || (n_buffers_requested != n_desc)) begin
//                // there are more read transfers to follow
//                computed_last_transfer_flag <= 0;
//            end

            // only only do output when receiver is ready
            if (axis_concat_out.tready | ~cfg_flag_en_write) begin
                // output stage
                if (shifted_valid) begin
                    // only if valid data is coming out of the shifter, the output stage can be updated
                    if ((shifted_keep | output_keep) == 64'hffffffffffffffff) begin
                        // the output register would be full
                        for (int i = 0; i < 64; i++) begin
                            if (output_keep[i]) begin
                                axis_concat_out.tdata[(i*8)+:8] <= output_register[(i*8)+:8];
                            end
                            else begin
                                axis_concat_out.tdata[(i*8)+:8] <= shifted_data[(i*8)+:8];
                            end
                        end
                        axis_concat_out.tkeep <= 64'hffffffffffffffff;
                        axis_concat_out.tid <= 0;

                        // handle the output register
                        for (int i = 0; i < 64; i++) begin
                            if (output_keep[i] & shifted_keep[i])
                                output_register[(8*i)+:8] <= shifted_data[(8*i)+:8];
                            else
                                output_register[(8*i)+:8] <= 0;
                        end
                        output_keep <= output_keep & shifted_keep;

                        axis_concat_out_tvalid <= 1;

                        // handle tlast
                        if (shifted_last_transfer_flag && shifted_last) begin
                            if ((shifted_keep & output_keep) == 0) begin
                                // all remaining data leaves this cycle, so this is last anyway
                                axis_concat_out_tlast <= 1;
                            end
                            else begin
                                // set flag so that next cycle will write output register
                                last_data_waiting <= 1;
                                axis_concat_out_tlast <=
                                    (byte_counter_plus_64 & cfg_max_transfer_mask) == 0;
                            end
                        end
                        else begin
                            axis_concat_out_tlast <=
                                (byte_counter_plus_64 & cfg_max_transfer_mask) == 0;
                        end

                        // update byte counter
                        byte_counter <= byte_counter_plus_64;
                    end
                    else begin
                        // check if this is the last transfer
                        if (shifted_last_transfer_flag && shifted_last) begin
                            // transmit output register and pipeline output directly
                            for (int i = 0; i < 64; i++) begin
                                if (output_keep[i])
                                    axis_concat_out.tdata[(8*i)+:8] <= output_register[(8*i)+:8];
                                else if (shifted_keep[i])
                                    axis_concat_out.tdata[(8*i)+:8] <= shifted_data[(8*i)+:8];
                                else
                                    axis_concat_out.tdata[(8*i)+:8] <= 0;
                            end

                            axis_concat_out.tkeep <= output_keep | shifted_keep;
                            axis_concat_out.tid <= 0;
                            axis_concat_out_tlast <= 1;
                            axis_concat_out_tvalid <= 1;
                        end
                        else begin
                            // only add to output register (no overlap between output and pipeline)
                            for (int i = 0; i < 64; i++) begin
                                if (shifted_keep[i])
                                    output_register[(i*8)+:8] <= shifted_data[(i*8)+:8];
                                else if (output_keep[i])
                                    output_register[(i*8)+:8] <= output_register[(i*8)+:8];
                                else
                                    output_register[(i*8)+:8] <= 0;
                            end
                            // this should not create holes in the output_keep register
                            output_keep <= output_keep | shifted_keep;
                            output_offset <= shifted_offset;

                            axis_concat_out_tvalid <= 0; // this cannot be valid anymore
                        end
                    end
                end
                else begin
                    if (last_data_waiting) begin
                        axis_concat_out.tdata <= output_register;
                        axis_concat_out.tkeep <= output_keep;
                        axis_concat_out.tid <= 0;
                        axis_concat_out_tvalid <= 1;
                        axis_concat_out_tlast <= 1;

                        last_data_waiting <= 0;
                    end
                    else begin
                        axis_concat_out_tvalid <= 0;
                    end
                end
            end
        end
    end

    // handle reading from ctrl registers
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            // reset control registers and state
            ctrl_arready <= 0;
            ctrl_rvalid <= 0;
            ctrl_rresp <= 0;
            ctrl_rdata <= 0;
            ctrl_awready <= 0;
            ctrl_bvalid <= 0;
            ctrl_wready <= 0;
            axi_ctrl.bresp <= 0;
            read_desc_addr <= 0;
            read_desc_len <= 0;
            write_addr <= 0;
            write_len <= 0;
            start_flag <= 0;
            // reset opcode register
            cfg_opcodes <= 64'h0000000000010301; // local_read: 1, local_write: 3, rdma_write: 1
            // reset flag register
            // no notification transfer, enable write
            cfg_register <= 64'h0000000000001302;
        end else begin
            // handle axi_ctrl writes (only if state is StateIdle)
            if (state == StateIdle
                && ctrl_awready && axi_ctrl.awvalid && ctrl_wready && axi_ctrl.wvalid) begin
                case (axi_ctrl_awaddr)
                    RegDescAddr: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            read_desc_addr <= axi_ctrl.wdata;
                            start_flag <= 1; // start the transfer
                        end
                    end
                    RegDescLen: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            read_desc_len <= axi_ctrl.wdata;
                        end
                    end
                    RegWriteAddr: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            write_addr <= axi_ctrl.wdata;
                        end
                    end
                    RegWriteLen: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            write_len <= axi_ctrl.wdata;
                        end
                    end
                    RegOpcodes: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            cfg_opcodes <= axi_ctrl.wdata;
                        end
                    end
                    RegConfig: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            cfg_register <= axi_ctrl.wdata;
                        end
                    end
                    default:
                        $display("This shouldn't happen");
                endcase
            end
            else begin
                start_flag <= 0;
            end
            // handle axi_ctrl reads
            if (ctrl_arready && axi_ctrl.arvalid) begin
                $display("Reading Register: %x", axi_ctrl_araddr);
                case (axi_ctrl_araddr)
                    RegDescAddr: begin
                        ctrl_rdata <= read_desc_addr;
                    end
                    RegDescLen: begin
                        ctrl_rdata <= read_desc_len;
                    end
                    RegWriteAddr: begin
                        ctrl_rdata <= write_addr;
                    end
                    RegWriteLen: begin
                        ctrl_rdata <= write_len;
                    end
                    RegPcCyclesTotal: begin
                        ctrl_rdata <= pc_cycles_total;
                    end
                    RegPcCyclesWaitingForTransfer: begin
                        ctrl_rdata <= pc_cycles_waiting_for_transfer;
                    end
                    RegPcCyclesRequesting: begin
                        ctrl_rdata <= pc_cycles_requesting;
                    end
                    RegPcCyclesReceving: begin
                        ctrl_rdata <= pc_cycles_receiving;
                    end
                    RegPcCyclesSending: begin
                        ctrl_rdata <= pc_cycles_sending;
                    end
                    RegOpcodes: begin
                        ctrl_rdata <= cfg_opcodes;
                    end
                    RegConfig: begin
                        ctrl_rdata <= {
                            state,
                            cfg_register[55:0]
                        };
                    end
                    default:
                        $display("This shouldn't happen");
                endcase
                // always acknowledge
                ctrl_rvalid <= 1;
                ctrl_rresp <= 0;
            end
            // handle AW ready
            if (axi_ctrl.awvalid && ~ctrl_awready) begin
                ctrl_awready <= 1;
            end
            else begin
                ctrl_awready <= 0;
            end
            // handle W ready
            if (axi_ctrl.wvalid && ~ctrl_wready) begin
                ctrl_wready <= 1;
            end
            else begin
                ctrl_wready <= 0;
            end
            // handle AR ready
            if (axi_ctrl.arvalid && ~ctrl_arready) begin
                ctrl_arready <= 1;
            end
            else begin
                ctrl_arready <= 0;
            end
            // handle R valid
            if (axi_ctrl.rready && ctrl_rvalid) begin
                ctrl_rvalid <= 0;
            end

            // handle B valid
            if (ctrl_awready && axi_ctrl.awvalid && ctrl_wready && axi_ctrl.wvalid) begin
                // always acknowledge
                axi_ctrl.bresp <= 0;
                ctrl_bvalid <= 1;
            end
            if (axi_ctrl.bready && ctrl_bvalid) begin
                ctrl_bvalid <= 0;
            end
        end
    end


    // performance monitoring
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            pc_cycles_total <= 0;
            pc_cycles_waiting_for_transfer <= 0;
            pc_cycles_requesting <= 0;
            pc_cycles_receiving <= 0;
            pc_cycles_sending <= 0;
        end
        else begin
            // state related performance counters
            case (state)
                StateIdle: begin
                    if (start_flag) begin
                        // transfer starting, so reset all performance counters
                        pc_cycles_total <= 0;
                        pc_cycles_waiting_for_transfer <= 0;
                        pc_cycles_requesting <= 0;
                        pc_cycles_receiving <= 0;
                        pc_cycles_sending <= 0;
                    end
                end
                StateReadDesc: begin end // this state is not counted, results are derived
                StateRequestBuffer: begin
                    // requesting buffer
                    pc_cycles_requesting <= pc_cycles_requesting + 1;
                end
                StateWaitForTransferToEnd: begin
                    // waiting for the transfer to complete
                    pc_cycles_waiting_for_transfer <= pc_cycles_waiting_for_transfer + 1;
                end
                default: begin
                    $display("Unexpected state for performance counters");
                end
            endcase

            // different performance counters, independent of the state
            if (state != StateIdle) begin
                // well not completely independent
                pc_cycles_total <= pc_cycles_total + 1;

                if (axis_host_recv[1].tvalid && axis_host_recv[1].tready) begin
                    pc_cycles_receiving <= pc_cycles_receiving + 1;
                end
                if (axis_concat_out_tvalid && axis_concat_out.tready) begin
                    pc_cycles_sending <= pc_cycles_sending + 1;
                end
            end
        end
    end

endmodule
