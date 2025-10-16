//---------------------------------------------------------------------------
//--  Copyright 2015 - 2017 Systems Group, ETH Zurich
//--  Copyright 2018 - 2019 IMDEA Software Institute, Madrid
//-- 
//--  This hardware module is free software: you can redistribute it and/or
//--  modify it under the terms of the GNU General Public License as published
//--  by the Free Software Foundation, either version 3 of the License, or
//--  (at your option) any later version.
//-- 
//--  This program is distributed in the hope that it will be useful,
//--  but WITHOUT ANY WARRANTY; without even the implied warranty of
//--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//--  GNU General Public License for more details.
//-- 
//--  You should have received a copy of the GNU General Public License
//--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//---------------------------------------------------------------------------


`default_nettype none

// toplevel for the VCU1525 or other devices that have LARGE memories

module muu_Top_Module_LMem512 #(	
	parameter NET_META_WIDTH = 64,
    parameter OPS_META_WIDTH = 56+32+4+4,
	parameter HEADER_WIDTH = 48,	
    parameter VALUE_WIDTH = 512,
    parameter MEMORY_WIDTH = 512,
    parameter KEY_WIDTH = 64,
    parameter HASHTABLE_MEM_SIZE = 20,
    parameter VALUESTORE_MEM_SIZE = 24,
    parameter FILTER_ENABLED=1,
	parameter IS_SIM = 0,
    parameter USER_BITS = 3,
    parameter ENABLE_CHECKPOINTS = 0 // to simplify porting to 512 bits!
)(
	// Clock
	input wire         clk,
	input wire         rst,

	
	// Memcached Request Input
	input  wire [511+64:0] s_axis_tdata,
    input  wire [USER_BITS-1:0] s_axis_tuserid,
	input  wire         s_axis_tvalid,
	input wire 			s_axis_tlast,
	output wire         s_axis_tready,

	// Memcached Response Output
	output wire [511+64:0] m_axis_tdata,
    output  wire [USER_BITS-1:0] m_axis_tuserid,
	output wire         m_axis_tvalid,
	output wire 		m_axis_tlast,
	input  wire         m_axis_tready,

	// HashTable DRAM Connection

	// ht_rd:     Pull Input, 1536b
	input  wire [511:0] ht_rd_data,
	input  wire          ht_rd_valid,
	output wire          ht_rd_ready,

	// ht_rd_cmd: Push Output, 10b
	output wire [63:0] ht_rd_cmd_data,
	output wire        ht_rd_cmd_valid,
	input  wire        ht_rd_cmd_stall,

	// ht_wr:     Push Output, 1536b
	output wire [511:0] ht_wr_data,
	output wire          ht_wr_valid,
	input  wire          ht_wr_stall,

	// ht_wr_cmd: Push Output, 10b
	output wire [63:0] ht_wr_cmd_data,
	output wire        ht_wr_cmd_valid,
	input  wire        ht_wr_cmd_stall,

	// Update DRAM Connection

	// upd_rd:     Pull Input, 1536b
	input  wire [MEMORY_WIDTH-1:0] upd_rd_data,
	input  wire          upd_rd_valid,
	output wire          upd_rd_ready,

	// upd_rd_cmd: Push Output, 10b
	output wire [63:0] upd_rd_cmd_data,
	output wire        upd_rd_cmd_valid,
	input  wire        upd_rd_cmd_stall,

	// upd_wr:     Push Output, 1536b
	output wire [511:0] upd_wr_data,
	output wire          upd_wr_valid,
	input  wire          upd_wr_stall,

	// upd_wr_cmd: Push Output, 10b
	output wire [63:0] upd_wr_cmd_data,
	output wire        upd_wr_cmd_valid,
	input  wire        upd_wr_cmd_stall,

	output wire [63:0] p_rdcmd_data,
	output wire         p_rdcmd_valid,
	input  wire         p_rdcmd_ready,

	input wire [512-1:0]  p_rd_data,
	input wire         p_rd_valid,
	output  wire         p_rd_ready,	

	output wire [512-1:0] p_wr_data,
	output wire         p_wr_valid,
	input  wire         p_wr_ready,

	output wire [63:0] p_wrcmd_data,
	output wire         p_wrcmd_valid,
	input  wire         p_wrcmd_ready,


	output wire [63:0] b_rdcmd_data,
	output wire         b_rdcmd_valid,
	input  wire         b_rdcmd_ready,

	input wire [512-1:0]  b_rd_data,
	input wire         b_rd_valid,
	output  wire         b_rd_ready,	

	output wire [512-1:0] b_wr_data,
	output wire         b_wr_valid,
	input  wire         b_wr_ready,

	output wire [63:0] b_wrcmd_data,
	output wire         b_wrcmd_valid,
	input  wire         b_wrcmd_ready,

    output wire     m_axis_open_connection_TVALID,
    input  wire       m_axis_open_connection_TREADY,
    output wire [47:0]     m_axis_open_connection_TDATA,

    input  wire       s_axis_open_status_TVALID,
    output wire       s_axis_open_status_TREADY,
    input  wire [23:0]      s_axis_open_status_TDATA,



    output wire [512-1:0]  val_to_proc_TDATA,
	output wire         val_to_proc_TVALID,
	output wire         val_to_proc_TLAST,
	input wire         val_to_proc_TREADY,

	output wire [512-1:0]  par_to_proc_TDATA,
	output wire         par_to_proc_TVALID,
	output wire         par_to_proc_TLAST,
	input wire         par_to_proc_TREADY,

	input wire [512-1:0]  val_from_proc_TDATA,
	input wire         val_from_proc_TVALID,
	input wire         val_from_proc_TLAST,
	output wire         val_from_proc_TREADY,

	input wire [0:0]  par_from_proc_TDATA,
	input wire         par_from_proc_TVALID,
	input wire         par_from_proc_TLAST,
	output wire         par_from_proc_TREADY,
	
	output wire [255:0]        debug
);

parameter EXT_META_WIDTH = NET_META_WIDTH+OPS_META_WIDTH+USER_BITS;//163

parameter DOUBLEHASH_WIDTH = 64;
parameter HASH_WIDTH = 32;

parameter SUPPORT_SCANS = 0;

wire [31:0] rdcmd_data;
wire        rdcmd_valid;
wire        rdcmd_stall;
wire        rdcmd_ready;

wire [31:0] wrcmd_data;
wire        wrcmd_valid;
wire        wrcmd_stall;
wire        wrcmd_ready;


wire [39:0] upd_rdcmd_data;
wire        upd_rdcmd_ready;

wire [39:0] upd_wrcmd_data;
wire        upd_wrcmd_ready;

wire [15:0] mreq_data;
wire mreq_valid;
wire mreq_ready;

wire [15:0] mreq_data_b;
wire mreq_valid_b;
wire mreq_ready_b;

wire [31:0] malloc_data;
wire malloc_valid;
wire malloc_failed;
wire malloc_ready;

wire [31:0] free_data;
wire [15:0] free_size;
wire free_valid;
wire free_ready;
wire free_wipe;

wire [31:0] malloc_data_b;
wire [31+1:0] malloc_data_full_b;
wire malloc_valid_b;
wire malloc_failed_b;
wire malloc_ready_b;

wire [31+16+1:0] free_data_full_b;
wire [31:0] free_data_b;
wire [15:0] free_size_b;
wire free_valid_b;
wire free_ready_b;
wire free_wipe_b;

wire [63:0] key_data;
wire key_last;
wire key_valid;
wire key_ready;

wire [EXT_META_WIDTH-1:0] meta_data;
wire meta_valid;
wire meta_ready;


wire [USER_BITS+63:0] tohash_data;
wire tohash_valid;
wire tohash_ready;

wire [1+63:0] tosm_data;
wire tosm_valid;
wire tosm_ready;


wire [DOUBLEHASH_WIDTH-1:0] fromhash_data;
wire fromhash_valid;
wire fromhash_ready;

wire [DOUBLEHASH_WIDTH-1:0] hashaddr_data;
wire hashaddr_valid;
wire hashaddr_ready;

wire[DOUBLEHASH_WIDTH-1:0] secondhash_data;
wire secondhash_valid;
wire secondhash_ready;

wire[DOUBLEHASH_WIDTH-1:0] fromsecondhash_data;
wire fromsecondhash_valid;
wire fromsecondhash_ready;

wire [KEY_WIDTH-1:0] keyfromcmd_data;
wire keyfromcmd_valid;
wire keyfromcmd_ready;

wire [KEY_WIDTH-1:0] keyfromcmd_b_data;
wire keyfromcmd_b_valid;
wire keyfromcmd_b_ready;


wire [EXT_META_WIDTH-1:0] meta_b_data;
wire meta_b_valid;
wire meta_b_ready;


wire [EXT_META_WIDTH-1:0] meta_b2_data;
wire meta_b2_valid;
wire meta_b2_ready;


wire [KEY_WIDTH+EXT_META_WIDTH+DOUBLEHASH_WIDTH-1:0] keywhash_data;
wire keywhash_valid;
wire keywhash_ready;

wire [KEY_WIDTH+EXT_META_WIDTH+DOUBLEHASH_WIDTH-1:0] towrite_b_data;
wire towrite_b_valid;
wire towrite_b_ready;

wire [16+KEY_WIDTH+EXT_META_WIDTH+HEADER_WIDTH-1:0] writeout_data;
wire writeout_valid;
wire writeout_ready;

wire [KEY_WIDTH+EXT_META_WIDTH+HEADER_WIDTH-1:0] writeout_b_data;
wire writeout_b_valid;
wire writeout_b_ready;

wire [KEY_WIDTH+EXT_META_WIDTH+HEADER_WIDTH-1:0] fromset_data;
wire fromset_valid;
wire fromset_ready;

wire [KEY_WIDTH+EXT_META_WIDTH+HEADER_WIDTH-1:0] fromset_b_data;
wire fromset_b_valid;
wire fromset_b_ready;

wire [KEY_WIDTH+EXT_META_WIDTH+DOUBLEHASH_WIDTH-1:0] towrite_data;
wire towrite_valid;
wire towrite_ready;

wire [KEY_WIDTH+EXT_META_WIDTH-1:0] writefb_data;
wire writefb_valid;
wire writefb_ready;


wire [KEY_WIDTH+EXT_META_WIDTH-1:0] writefb_b_data;
wire writefb_b_valid;
wire writefb_b_ready;

wire [KEY_WIDTH+EXT_META_WIDTH+DOUBLEHASH_WIDTH-1:0] feedbwhash_data;
wire feedbwhash_valid;
wire feedbwhash_ready;

wire [VALUE_WIDTH-1:0] value_data;
wire [15:0] value_length;
wire value_last;
wire value_valid;
wire value_ready;
wire value_almost_full;

wire [VALUE_WIDTH+16+1-1:0] value_b_data;
wire [15:0] value_b_length;
wire value_b_last;
wire value_b_valid;
wire value_b_ready;

wire[VALUE_WIDTH-1:0] value_read_data;
wire value_read_valid;
wire value_read_ready;
wire value_read_last;


wire[VALUE_WIDTH-1:0] repldata_data;
wire repldata_valid;
wire repldata_ready;

wire[VALUE_WIDTH-1:0] repldata_preb_data;
wire repldata_preb_valid;
wire repldata_preb_ready;

wire[VALUE_WIDTH-1:0] repldata_b_data;
wire repldata_b_valid;
wire repldata_b_ready;

wire[15:0] replconf_size;
wire[15:0] replconf_count;
wire replconf_valid;
wire replconf_ready;


wire [63:0] setter_rdcmd_data;
wire        setter_rdcmd_valid;
wire        setter_rdcmd_ready;

wire [63:0] scan_rdcmd_data;
wire        scan_rdcmd_valid;
wire        scan_rdcmd_ready;

wire scan_kickoff;
wire scan_reading;
wire scan_mode_on;
wire [31:0] scan_readsissued;
reg [31:0] scan_readsprocessed;
wire scan_valid;
wire[31:0] scan_addr;
wire[7:0] scan_cnt;
wire scan_ready;

wire pe_cmd_ready;
wire pe_cmd_valid;
wire[15:0] pe_cmd_data;
wire[95:0] pe_cmd_meta;

wire [511:0] value_frompipe_data;
wire        value_frompipe_ready;
wire        value_frompipe_valid;
wire        value_frompipe_drop;
wire        value_frompipe_last;

wire [511:0] value_frompred_b_data;
wire        value_frompred_b_ready;
wire        value_frompred_b_valid;

wire value_read_almostfull_int;
reg scan_pause;


wire sh_in_buf_ready;
wire sh_in_ready;
wire sh_in_valid;
wire sh_in_choice;
wire[63+USER_BITS:0] sh_in_data;

wire write_feedback_channel_ready;

reg[31:0]                    input_counter;



wire [KEY_WIDTH+EXT_META_WIDTH+HEADER_WIDTH-1:0] writeout_int_data;
wire [USER_BITS-1: 0] writeout_int_user;
wire writeout_int_valid;
wire writeout_int_ready;

reg [7:0]     rateLimitUser;
reg           rateLimitOutput;


wire [127:0] zkm_data;
wire         zkm_ready;
wire         zkm_valid;

wire [127:0] zkm_b_data;
wire         zkm_b_ready;
wire         zkm_b_valid;

wire[127:0] final_out_data;
wire[7:0] final_out_user;
wire final_out_valid;
wire final_out_ready;
wire final_out_last;

reg sAxisFirst;
reg sAxisSecond;



wire [511+64:0] in_axis_tdata;
wire [USER_BITS-1:0] in_axis_tuserid;
wire         in_axis_tvalid;
wire          in_axis_tlast;
wire         in_axis_tready;

reg decruserValid;
reg[7:0] decruserID;

reg checkpt_first_valid;
reg [3:0] checkpt_first_user;
reg [7:0] checkpt_first_freq;
reg [7:0] checkpt_first_cnt;
reg [15:0] checkpt_first_burst;

reg checkpt_second_valid;
reg [3:0] checkpt_second_user;
reg [7:0] checkpt_second_freq;
reg [7:0] checkpt_second_cnt;
reg [15:0] checkpt_second_burst;

reg checkpt_first_valid_buf;
reg [3:0] checkpt_first_user_buf;
reg [7:0] checkpt_first_freq_buf;
reg [7:0] checkpt_first_cnt_buf;
reg [15:0] checkpt_first_burst_buf;

reg checkpt_second_valid_buf;
reg [3:0] checkpt_second_user_buf;
reg [7:0] checkpt_second_freq_buf;
reg [7:0] checkpt_second_cnt_buf;
reg [15:0] checkpt_second_burst_buf;

reg canBeTokenControl;

reg isReplWrite;
reg [31:0] timeCycles;

wire [31:0] replWriteCycles;
wire replWriteRead;
wire replWriteValid;

nukv_fifogen #(
    .DATA_SIZE(32),
    .ADDR_BITS(8) 
) fifo_repl_times (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(timeCycles),
    .s_axis_tvalid(isReplWrite),
    .s_axis_tready(),
    .s_axis_talmostfull(),
    
    .m_axis_tdata(replWriteCycles),
    .m_axis_tvalid(replWriteValid),
    .m_axis_tready(replWriteRead)
);


always @(posedge clk) begin 
    if(rst) begin
        sAxisFirst <= 1;
        sAxisSecond <= 0;
        rateLimitOutput <= 0;

        checkpt_first_valid <= 0;
        checkpt_second_valid <= 0;

        checkpt_first_valid_buf <= 0;
        checkpt_second_valid_buf <= 0;   

        canBeTokenControl <= 0;     

        timeCycles <= 0;

        isReplWrite <= 0;

    end else begin

        isReplWrite <= 0;

        timeCycles <= timeCycles+1;

        checkpt_first_valid_buf <= checkpt_first_valid;
        checkpt_first_user_buf <= checkpt_first_user;
        checkpt_first_burst_buf <= checkpt_first_burst;
        checkpt_first_cnt_buf <= checkpt_first_cnt;
        checkpt_first_freq_buf <= checkpt_first_freq;
        
        checkpt_second_valid_buf <= checkpt_second_valid;
        checkpt_second_user_buf <= checkpt_second_user;
        checkpt_second_burst_buf <= checkpt_second_burst;
        checkpt_second_cnt_buf <= checkpt_second_cnt;
        checkpt_second_freq_buf <= checkpt_second_freq;            

        checkpt_first_valid <= 0;
        checkpt_second_valid <= 0;

        if (s_axis_tvalid==1 && s_axis_tready==1) begin
            sAxisFirst <= 0;
            sAxisSecond <= sAxisFirst;

            canBeTokenControl <= 0;

            if (sAxisFirst==1 && s_axis_tdata[31:16]==16'h0000) begin
                canBeTokenControl <= 1;
            end

            if (sAxisFirst==1 && s_axis_tdata[31:16]==16'h0100) begin
                isReplWrite <= 1;
            end
        end

        if (s_axis_tlast==1 && s_axis_tvalid==1 && s_axis_tready==1) begin
            sAxisFirst <= 1;
            sAxisSecond <= 0;
        end

        if (sAxisSecond==1 && s_axis_tvalid==1 && s_axis_tready==1) begin
            if (s_axis_tdata[15:0]==16'hBBBB && canBeTokenControl==1) begin
                if (s_axis_tdata[16+:8]==8'h00) begin
                    checkpt_first_valid <= 1;
                    checkpt_first_user <= s_axis_tuserid;
                    checkpt_first_cnt <= s_axis_tdata[24+:8];
                    checkpt_first_freq <= s_axis_tdata[32+:8];
                    checkpt_first_burst <= s_axis_tdata[40+:16];
                end 
                else begin 
                    checkpt_second_valid <= 1;
                    checkpt_second_user <= s_axis_tuserid;
                    checkpt_second_cnt <= s_axis_tdata[24+:8];
                    checkpt_second_freq <= s_axis_tdata[32+:8];
                    checkpt_second_burst <= s_axis_tdata[40+:16];
                end
            end
        end

        rateLimitUser <= in_axis_tuserid; //writeout_int_user;
        rateLimitOutput <= in_axis_tvalid & in_axis_tlast & in_axis_tready;//writeout_int_ready & writeout_int_valid;


    end
end

generate
if (ENABLE_CHECKPOINTS==1) begin

	/*muu_Checkpoint #(
	    .DATA_WIDTH(128),
	    .USER_BITS(USER_BITS),
	    .COST_BITS(3),
	    .TB_DEFAULT_HEADER_SIZE(0)

	) checkpoint_on_netin (

	    .clk(clk),
	    .rst(rst),

	    .in_data(s_axis_tdata),
	    .in_valid(s_axis_tvalid),
	    .in_ready(s_axis_tready),
	    .in_cost(1),
	    .in_user(s_axis_tuserid),
	    .in_first(sAxisFirst),
	    .in_last(s_axis_tlast),

	    .out_data(in_axis_tdata),
	    .out_valid(in_axis_tvalid),
	    .out_ready(in_axis_tready),
	    .out_user(in_axis_tuserid),
	    .out_last(in_axis_tlast),
	    .out_first(),

	    .config_valid(checkpt_first_valid_buf),
	    .config_burst(checkpt_first_burst_buf),
	    .config_user(checkpt_first_user_buf),    
	    .config_updfreq(checkpt_first_freq_buf),
	    .config_updcount(checkpt_first_cnt_buf),

	    //no op count limit needed
	    .decrement_valid(rateLimitOutput),
	    .decrement_user(rateLimitUser)
	);*/
end else begin

    assign in_axis_tdata = s_axis_tdata;
    assign in_axis_tvalid = s_axis_tvalid;
    assign in_axis_tuserid = s_axis_tuserid;
    assign in_axis_tlast = s_axis_tlast;
    assign s_axis_tready = in_axis_tready;
    
end
endgenerate

wire [3:0] reqsplit_debug;

muu_RequestSplit512 #(
    .NET_META_WIDTH(NET_META_WIDTH),
    .OPS_META_WIDTH(OPS_META_WIDTH),
    .USER_BITS(USER_BITS)
    ) splitter (
	.clk(clk),
	.rst(rst),
	.s_axis_tdata(in_axis_tdata),
    .s_axis_tuserid(in_axis_tuserid),
	.s_axis_tvalid(in_axis_tvalid),
	.s_axis_tready(in_axis_tready),
	.s_axis_tlast(in_axis_tlast),


	.key_data(key_data),
	.key_valid(key_valid),
	.key_last(key_last),
	.key_ready(key_ready),

	.meta_data(meta_data),
	.meta_valid(meta_valid),
	.meta_ready(meta_ready),

	.value_data(value_data),
	.value_valid(value_valid),
	.value_length(value_length),
	.value_last(value_last),
	.value_ready(value_ready),
	.value_almost_full(value_almost_full),

	._debug(reqsplit_debug)
);

nukv_fifogen #(
    .DATA_SIZE(65),
    .ADDR_BITS(4)
) fifo_key_toctrl (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata({key_last,key_data}),
    .s_axis_tvalid(key_valid),
    .s_axis_tready(key_ready),
    
    .m_axis_tdata(tosm_data),
    .m_axis_tvalid(tosm_valid),
    .m_axis_tready(tosm_ready)
);

nukv_fifogen #(
    .DATA_SIZE(VALUE_WIDTH+16+1),
    .ADDR_BITS(11) //!!!
) fifo_value (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata({value_last, value_length, value_data}),
    .s_axis_tvalid(value_valid),
    .s_axis_tready(value_ready),
    .s_axis_talmostfull(value_almost_full),
    
    .m_axis_tdata(value_b_data),
    .m_axis_tvalid(value_b_valid),
    .m_axis_tready(value_b_ready)
);

nukv_fifogen #(
    .DATA_SIZE(EXT_META_WIDTH),
    .ADDR_BITS(4)
) fifo_meta_toctrl (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(meta_data),
    .s_axis_tvalid(meta_valid),
    .s_axis_tready(meta_ready),
    
    .m_axis_tdata(meta_b_data),
    .m_axis_tvalid(meta_b_valid),
    .m_axis_tready(meta_b_ready)
);


wire log_add_valid;
wire [31:0] log_add_zxid;
wire [USER_BITS-1:0] log_add_user;
wire [63:0] log_add_key;

wire log_search_valid;
wire log_search_since;
wire [31:0] log_search_zxid;
wire [USER_BITS-1:0] log_search_user;

wire log_found_valid;
wire [63:0] log_found_key;

wire cmd_in_valid_prebuf;
wire [NET_META_WIDTH+OPS_META_WIDTH-1:0] cmd_in_data_prebuf;
wire [63:0] cmd_in_key_prebuf;
wire [USER_BITS-1:0] cmd_in_user_prebuf;
wire cmd_in_ready_prebuf;

wire cmd_in_valid;
wire [NET_META_WIDTH+OPS_META_WIDTH-1:0] cmd_in_data;
wire [63:0] cmd_in_key;
wire [USER_BITS-1:0] cmd_in_user;
wire cmd_in_ready;

wire cmd_out_valid;
wire cmd_out_valid_g;
wire [NET_META_WIDTH+OPS_META_WIDTH-1:0] cmd_out_data;
wire [63:0] cmd_out_key;
wire [USER_BITS-1:0] cmd_out_user;
wire cmd_out_ready;


wire cmd_out_valid_prebuf;
wire [NET_META_WIDTH+OPS_META_WIDTH-1:0] cmd_out_data_prebuf;
wire [63:0] cmd_out_key_prebuf;
wire [USER_BITS-1:0] cmd_out_user_prebuf;
wire cmd_out_ready_prebuf;

wire cmd_out_key_ready;
wire cmd_out_meta_ready;

assign cmd_in_valid_prebuf = meta_b_valid & tosm_valid;
assign meta_b_ready = cmd_in_valid_prebuf & cmd_in_ready_prebuf;
assign tosm_ready = cmd_in_valid_prebuf & cmd_in_ready_prebuf;
assign cmd_in_data_prebuf = meta_b_data;
assign cmd_in_key_prebuf = tosm_data;
assign cmd_in_user_prebuf = meta_b_data[NET_META_WIDTH+OPS_META_WIDTH +: USER_BITS];

fifo_256bit_regslice cmd_in_reg_slice (
  .s_aclk(clk),                // input wire s_aclk
  .s_aresetn(~rst),          // input wire s_aresetn
  .s_axis_tvalid(cmd_in_valid_prebuf),  // input wire s_axis_tvalid
  .s_axis_tready(cmd_in_ready_prebuf),  // output wire s_axis_tready
  .s_axis_tdata({cmd_in_user_prebuf,cmd_in_key_prebuf,cmd_in_data_prebuf}),    // input wire [255 : 0] s_axis_tdata
  .m_axis_tvalid(cmd_in_valid),  // output wire m_axis_tvalid
  .m_axis_tready(cmd_in_ready),  // input wire m_axis_tready
  .m_axis_tdata({cmd_in_user,cmd_in_key,cmd_in_data})    // output wire [255 : 0] m_axis_tdata
);


assign cmd_out_ready = cmd_out_meta_ready & cmd_out_key_ready & keyfromcmd_ready;
assign cmd_out_valid_g = cmd_out_valid & cmd_out_ready & cmd_out_meta_ready & keyfromcmd_ready;

wire log_found_valid_buf;
wire[63:0] log_found_key_buf;

fifo_64bit_regslice log_found_reg_slice (
  .s_aclk(clk),                // input wire s_aclk
  .s_aresetn(~rst),          // input wire s_aresetn
  .s_axis_tvalid(log_found_valid),  // input wire s_axis_tvalid
  .s_axis_tready(),  // output wire s_axis_tready
  .s_axis_tdata(log_found_key),    // input wire [255 : 0] s_axis_tdata
  .m_axis_tvalid(log_found_valid_buf),  // output wire m_axis_tvalid
  .m_axis_tready(1'b1),  // input wire m_axis_tready
  .m_axis_tdata(log_found_key_buf)    // output wire [255 : 0] m_axis_tdata
);


wire m_axis_open_connection_TVALID_buf;
wire m_axis_open_connection_TREADY_buf;
wire [47:0] m_axis_open_connection_TDATA_buf;

fifo_64bit_regslice open_conn_req_reg_slice (
  .s_aclk(clk),                // input wire s_aclk
  .s_aresetn(~rst),          // input wire s_aresetn
  .s_axis_tvalid(m_axis_open_connection_TVALID_buf),  // input wire s_axis_tvalid
  .s_axis_tready(m_axis_open_connection_TREADY_buf),  // output wire s_axis_tready
  .s_axis_tdata(m_axis_open_connection_TDATA_buf),    // input wire [255 : 0] s_axis_tdata
  .m_axis_tvalid(m_axis_open_connection_TVALID),  // output wire m_axis_tvalid
  .m_axis_tready(m_axis_open_connection_TREADY),  // input wire m_axis_tready
  .m_axis_tdata(m_axis_open_connection_TDATA)    // output wire [255 : 0] m_axis_tdata
);

wire s_axis_open_status_TVALID_buf;
wire s_axis_open_status_TREADY_buf;
wire[16:0] s_axis_open_status_TDATA_buf;

fifo_64bit_regslice open_conn_resp_reg_slice (
  .s_aclk(clk),                // input wire s_aclk
  .s_aresetn(~rst),          // input wire s_aresetn
  .s_axis_tvalid(s_axis_open_status_TVALID),  // input wire s_axis_tvalid
  .s_axis_tready(s_axis_open_status_TREADY),  // output wire s_axis_tready
  .s_axis_tdata(s_axis_open_status_TDATA),    // input wire [255 : 0] s_axis_tdata
  .m_axis_tvalid(s_axis_open_status_TVALID_buf),  // output wire m_axis_tvalid
  .m_axis_tready(s_axis_open_status_TREADY_buf),  // input wire m_axis_tready
  .m_axis_tdata(s_axis_open_status_TDATA_buf)    // output wire [255 : 0] m_axis_tdata
);

wire mreq_valid_buf;
wire mreq_ready_buf;
wire[15:0] mreq_data_buf;

fifo_64bit_regslice mreq_reg_slice (
  .s_aclk(clk),                // input wire s_aclk
  .s_aresetn(~rst),          // input wire s_aresetn
  .s_axis_tvalid(mreq_valid_buf),  // input wire s_axis_tvalid
  .s_axis_tready(mreq_ready_buf),  // output wire s_axis_tready
  .s_axis_tdata(mreq_data_buf),    // input wire [255 : 0] s_axis_tdata
  .m_axis_tvalid(mreq_valid),  // output wire m_axis_tvalid
  .m_axis_tready(mreq_ready),  // input wire m_axis_tready
  .m_axis_tdata(mreq_data)    // output wire [255 : 0] m_axis_tdata
);

wire replicate_error_valid;
wire [7:0] replicate_error_opcode;
wire [127:0] replicate_debug_data;

muu_replicate_CentralSM #(

        .USER_BITS(USER_BITS),
        .CMD_WIDTH(NET_META_WIDTH+OPS_META_WIDTH)

    ) replicate_core (

    .clk(clk),
    .rst(rst),

    .cmd_in_valid(cmd_in_valid),
    .cmd_in_data(cmd_in_data),
    .cmd_in_key(cmd_in_key),
    .cmd_in_user(cmd_in_user),
    .cmd_in_ready(cmd_in_ready),

    .cmd_out_valid(cmd_out_valid_prebuf),
    .cmd_out_data(cmd_out_data_prebuf),
    .cmd_out_key(cmd_out_key_prebuf),
    .cmd_out_user(cmd_out_user_prebuf),
    .cmd_out_ready(cmd_out_ready_prebuf),
   
    .log_add_valid(log_add_valid),
    .log_add_zxid(log_add_zxid),
    .log_add_user(log_add_user),
    .log_add_key(log_add_key),

    .log_search_valid(log_search_valid),
    .log_search_since(log_search_since),
    .log_search_user(log_search_user),
    .log_search_zxid(log_search_zxid),
    
    .log_found_valid (log_found_valid_buf),
    .log_found_key(log_found_key_buf),

    .open_conn_req_valid(m_axis_open_connection_TVALID_buf),
    .open_conn_req_ready(m_axis_open_connection_TREADY_buf),
    .open_conn_req_data(m_axis_open_connection_TDATA_buf),

    .open_conn_resp_valid(s_axis_open_status_TVALID_buf),
    .open_conn_resp_ready(s_axis_open_status_TREADY_buf),
    .open_conn_resp_data(s_axis_open_status_TDATA_buf[16:0]),

    .malloc_data(mreq_data_buf),
    .malloc_valid(mreq_valid_buf),
    .malloc_ready(mreq_ready_buf),

    .error_valid(replicate_error_valid),
    .error_opcode(replicate_error_opcode), 

    .debug_out(replicate_debug_data)

    );

fifo_256bit_regslice cmd_out_reg_slice (
  .s_aclk(clk),                // input wire s_aclk
  .s_aresetn(~rst),          // input wire s_aresetn
  .s_axis_tvalid(cmd_out_valid_prebuf),  // input wire s_axis_tvalid
  .s_axis_tready(cmd_out_ready_prebuf),  // output wire s_axis_tready
  .s_axis_tdata({cmd_out_user_prebuf,cmd_out_key_prebuf,cmd_out_data_prebuf}),    // input wire [255 : 0] s_axis_tdata
  .m_axis_tvalid(cmd_out_valid),  // output wire m_axis_tvalid
  .m_axis_tready(cmd_out_ready),  // input wire m_axis_tready
  .m_axis_tdata({cmd_out_user,cmd_out_key,cmd_out_data})    // output wire [255 : 0] m_axis_tdata
);


muu_replicate_LogManager replicate_logm (
    .clk(clk),
    .rst(rst),

    .log_add_valid(log_add_valid),
    .log_add_zxid(log_add_zxid),
    .log_add_user(log_add_user),
    .log_add_key(log_add_key),

    .log_search_valid(log_search_valid),
    .log_search_since(log_search_since),
    .log_search_user(log_search_user),
    .log_search_zxid(log_search_zxid),
    
    .log_found_valid (log_found_valid),
    .log_found_key(log_found_key)
  
);


nukv_fifogen #(
    .DATA_SIZE(EXT_META_WIDTH),
    .ADDR_BITS(7)
) fifo_meta_afterctrl (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata({cmd_out_user,cmd_out_data}),
    .s_axis_tvalid(cmd_out_valid_g),
    .s_axis_tready(cmd_out_meta_ready),
    
    .m_axis_tdata(meta_b2_data),
    .m_axis_tvalid(meta_b2_valid),
    .m_axis_tready(meta_b2_ready)
);

nukv_fifogen #(
    .DATA_SIZE(KEY_WIDTH+USER_BITS),
    .ADDR_BITS(6)
) fifo_key_fromctrltohash (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata({cmd_out_user,cmd_out_key}),
    .s_axis_tvalid(cmd_out_valid_g),
    .s_axis_tready(cmd_out_key_ready),
    
    .m_axis_tdata(tohash_data),
    .m_axis_tvalid(tohash_valid),
    .m_axis_tready(tohash_ready)
);

assign value_b_length = value_b_data[VALUE_WIDTH +: 16];
assign value_b_last = value_b_data[VALUE_WIDTH+16];


wire [31:0] h1addr1;
wire [31:0] h1addr2;
wire [USER_BITS-1:0] h1user;
assign h1user = tohash_data[KEY_WIDTH +: USER_BITS];
assign h1addr1 = {{32-USER_BITS-HASHTABLE_MEM_SIZE{1'b0}},h1user,tohash_data[0 +: HASHTABLE_MEM_SIZE] ^ tohash_data[64-HASHTABLE_MEM_SIZE +: HASHTABLE_MEM_SIZE]};
assign h1addr2 = {{32-USER_BITS-HASHTABLE_MEM_SIZE{1'b0}},h1user,tohash_data[0 +: HASHTABLE_MEM_SIZE] ^ tohash_data[HASHTABLE_MEM_SIZE +: HASHTABLE_MEM_SIZE]};

assign fromhash_valid = tohash_valid;
assign tohash_ready = fromhash_ready;
assign fromhash_data = {h1addr2,h1addr1};

/*
kvs_ht_Hash_v2 #(
        .MEMORY_WIDTH(HASHTABLE_MEM_SIZE)
    ) hash_number_one (
        .clk(clk),
        .rst(rst),

        .in_valid(tohash_valid),
        .in_ready(tohash_ready),
        .in_data(tohash_data[63:0]),
        .in_last(1),

        .out_valid(fromhash_valid),
        .out_ready(fromhash_ready),
        .out_data1(fromhash_data[31:0]),
        .out_data2(fromhash_data[63:32])
    );
/*
wire[31:0] hash_expand_1;
wire[31:0] hash_expand_2;
assign hash_expand_1 = {32'h0,fromhash_data[HASHTABLE_MEM_SIZE-1:0]} ^ {32'h0,fromhash_data[31:HASHTABLE_MEM_SIZE]};
assign hash_expand_2 = {32'h0,fromhash_data[32+HASHTABLE_MEM_SIZE-1:32]} ^ {32'h0,fromhash_data[63:32+HASHTABLE_MEM_SIZE]};
*/

    nukv_fifogen #(
    .DATA_SIZE(DOUBLEHASH_WIDTH),
    .ADDR_BITS(6)
) fifo_from_hash (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(fromhash_data),
    .s_axis_tvalid(fromhash_valid),
    .s_axis_tready(fromhash_ready),
    
    .m_axis_tdata(hashaddr_data),
    .m_axis_tvalid(hashaddr_valid),
    .m_axis_tready(hashaddr_ready)
);



nukv_fifogen #(
    .DATA_SIZE(KEY_WIDTH+USER_BITS),
    .ADDR_BITS(5)
) fifo_key_fromwritetohash2 (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata({writefb_data[KEY_WIDTH+EXT_META_WIDTH-USER_BITS +: USER_BITS],writefb_data[63:0]}),
    .s_axis_tvalid(write_feedback_channel_ready & writefb_valid),
    .s_axis_tready(sh_in_buf_ready),
    
    .m_axis_tdata(sh_in_data),
    .m_axis_tvalid(sh_in_valid),
    .m_axis_tready(sh_in_ready)
);

wire [31:0] h2addr1;
wire [31:0] h2addr2;
wire [USER_BITS-1:0] h2user;
assign h2user = sh_in_data[KEY_WIDTH +: USER_BITS];
assign h2addr1 = {{32-USER_BITS-HASHTABLE_MEM_SIZE{1'b0}},h2user,sh_in_data[0 +: HASHTABLE_MEM_SIZE] ^ sh_in_data[64-HASHTABLE_MEM_SIZE +: HASHTABLE_MEM_SIZE]};
assign h2addr2 = {{32-USER_BITS-HASHTABLE_MEM_SIZE{1'b0}},h2user,sh_in_data[0 +: HASHTABLE_MEM_SIZE] ^ sh_in_data[HASHTABLE_MEM_SIZE +: HASHTABLE_MEM_SIZE]};

assign secondhash_valid = sh_in_valid;
assign sh_in_ready = secondhash_ready;
assign secondhash_data = {h2addr2,h2addr1};

/*
kvs_ht_Hash_v2 #(
        .MEMORY_WIDTH(HASHTABLE_MEM_SIZE)
    ) hash_number_two (
        .clk(clk),
        .rst(rst),

        .in_valid(sh_in_valid),
        .in_ready(sh_in_ready),
        .in_data(sh_in_data[63:0]),
        .in_last(1),

        .out_valid(secondhash_valid),
        .out_ready(secondhash_ready),
        .out_data1(secondhash_data[31:0]),
        .out_data2(secondhash_data[63:32])
    );
/*
wire[31:0] secondhash_expand_1;
wire[31:0] secondhash_expand_2;
assign secondhash_expand_1 = {32'h0,secondhash_data[HASHTABLE_MEM_SIZE-1:0]} ^ {32'h0,secondhash_data[31:HASHTABLE_MEM_SIZE]};
assign secondhash_expand_2 = {32'h0,secondhash_data[32+HASHTABLE_MEM_SIZE-1:32]} ^ {32'h0,secondhash_data[63:32+HASHTABLE_MEM_SIZE]};
*/

nukv_fifogen #(
    .DATA_SIZE(DOUBLEHASH_WIDTH),
    .ADDR_BITS(5)
) fifo_from_hash2 (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(secondhash_data),
    .s_axis_tvalid(secondhash_valid),
    .s_axis_tready(secondhash_ready),
    
    .m_axis_tdata(fromsecondhash_data),
    .m_axis_tvalid(fromsecondhash_valid),
    .m_axis_tready(fromsecondhash_ready)
);



assign keyfromcmd_valid = cmd_out_valid_g;
assign keyfromcmd_data = cmd_out_key;

nukv_fifogen #(
    .DATA_SIZE(KEY_WIDTH),
    .ADDR_BITS(7)
) fifo_keycmd_fromctrl (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(keyfromcmd_data),
    .s_axis_tvalid(keyfromcmd_valid),
    .s_axis_tready(keyfromcmd_ready),
    
    .m_axis_tdata(keyfromcmd_b_data),
    .m_axis_tvalid(keyfromcmd_b_valid),
    .m_axis_tready(keyfromcmd_b_ready)
);





assign keywhash_valid = keyfromcmd_b_valid & hashaddr_valid & meta_b2_valid;
assign keyfromcmd_b_ready = keywhash_ready & keywhash_valid ;
assign hashaddr_ready = keywhash_ready & keywhash_valid;
assign meta_b2_ready = keywhash_ready & keywhash_valid;
assign keywhash_data = {hashaddr_data,meta_b2_data,keyfromcmd_b_data};


assign feedbwhash_data = {fromsecondhash_data, writefb_b_data[KEY_WIDTH+EXT_META_WIDTH-1:0]};//(writefb_b_data[KEY_WIDTH+EXT_META_WIDTH-3]==0 && writefb_b_valid==1) ? writefb_b_data : {fromsecondhash_data, writefb_b_data[KEY_WIDTH+EXT_META_WIDTH-1:0]};

assign feedbwhash_valid = writefb_b_valid & fromsecondhash_valid;//(writefb_b_data[KEY_WIDTH+EXT_META_WIDTH-3]==0 && writefb_b_valid==1) ? writefb_b_valid : writefb_b_valid & fromsecondhash_valid;

assign fromsecondhash_ready = writefb_b_ready; //(writefb_b_data[KEY_WIDTH+EXT_META_WIDTH-3]==0 && writefb_b_valid==1) ? 0 : writefb_b_ready;
assign writefb_b_ready = feedbwhash_ready & writefb_b_valid;

muu_HT_Read #(
        .MEMADDR_WIDTH(HASHTABLE_MEM_SIZE+USER_BITS),
        .KEY_WIDTH(KEY_WIDTH),
        .META_WIDTH(NET_META_WIDTH+OPS_META_WIDTH),
        .USER_BITS(USER_BITS)
    )
    readmodule
(
   	.clk(clk),
   	.rst(rst),

   	.input_data(keywhash_data),
   	.input_valid(keywhash_valid),
   	.input_ready(keywhash_ready),

   	.feedback_data(feedbwhash_data),
   	.feedback_valid(feedbwhash_valid),
   	.feedback_ready(feedbwhash_ready),

   	.output_data(towrite_data),
   	.output_valid(towrite_valid),
   	.output_ready(towrite_ready),

   	.rdcmd_data(rdcmd_data),
   	.rdcmd_valid(rdcmd_valid),
   	.rdcmd_ready(rdcmd_ready)
);

wire[VALUE_WIDTH-1:0] ht_buf_rd_data;
wire ht_buf_rd_ready;
wire ht_buf_rd_valid;


wire[VALUE_WIDTH-1:0] ht_read_data_int;
wire ht_read_valid_int;
wire ht_read_ready_int;

nukv_fifogen #(
    .DATA_SIZE(VALUE_WIDTH),
    .ADDR_BITS(7)
) fifo_ht_rd (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(ht_rd_data),
    .s_axis_tvalid(ht_rd_valid),
    .s_axis_tready(ht_rd_ready),
    .s_axis_talmostfull(),
    
    .m_axis_tdata(ht_read_data_int),
    .m_axis_tvalid(ht_read_valid_int),
    .m_axis_tready(ht_read_ready_int)
);


nukv_fifogen #(
    .DATA_SIZE(VALUE_WIDTH),
    .ADDR_BITS(7)
) fifo_ht_rd2 (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(ht_read_data_int),
    .s_axis_tvalid(ht_read_valid_int),
    .s_axis_tready(ht_read_ready_int),
    
    .m_axis_tdata(ht_buf_rd_data),
    .m_axis_tvalid(ht_buf_rd_valid),
    .m_axis_tready(ht_buf_rd_ready)
);

nukv_fifogen #(
    .DATA_SIZE(KEY_WIDTH+EXT_META_WIDTH+DOUBLEHASH_WIDTH),
    .ADDR_BITS(6)
) fifo_towrite_delayer (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(towrite_data),
    .s_axis_tvalid(towrite_valid),
    .s_axis_tready(towrite_ready),
    
    .m_axis_tdata(towrite_b_data),
    .m_axis_tvalid(towrite_b_valid),
    .m_axis_tready(towrite_b_ready)
);

nukv_fifogen #(
    .DATA_SIZE(KEY_WIDTH+EXT_META_WIDTH),
    .ADDR_BITS(6)
) fifo_feedback_delayer (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(writefb_data),
    .s_axis_tvalid(writefb_valid & write_feedback_channel_ready),
    .s_axis_tready(writefb_ready),
    
    .m_axis_tdata(writefb_b_data),
    .m_axis_tvalid(writefb_b_valid),
    .m_axis_tready(writefb_b_ready)
);

assign write_feedback_channel_ready = writefb_ready & sh_in_buf_ready;


wire writeout_valid_prebuf;
wire writeout_ready_prebuf;
wire[16+KEY_WIDTH+EXT_META_WIDTH+HEADER_WIDTH-1:0] writeout_data_prebuf;

wire [15:0] write_module_debug;

muu_HT_Write #(
    .IS_SIM(IS_SIM),
    .MEMADDR_WIDTH(HASHTABLE_MEM_SIZE+USER_BITS),
    .KEY_WIDTH(KEY_WIDTH),
    .META_WIDTH(NET_META_WIDTH+OPS_META_WIDTH),
    .USER_BITS(USER_BITS)
    ) 
writemodule 
(
	.clk(clk),
	.rst(rst),

	.input_data(towrite_b_data),
	.input_valid(towrite_b_valid),
	.input_ready(towrite_b_ready),

	.feedback_data(writefb_data),
	.feedback_valid(writefb_valid),
	.feedback_ready(write_feedback_channel_ready),

	.output_data(writeout_data_prebuf),
	.output_valid(writeout_valid_prebuf),
	.output_ready(writeout_ready_prebuf),

	.malloc_pointer(malloc_data_b),
	.malloc_valid(malloc_valid_b),
	.malloc_failed(malloc_failed_b),
	.malloc_ready(malloc_ready_b),


	.free_pointer(free_data),
	.free_size(free_size),
	.free_valid(free_valid),
	.free_ready(free_ready),
	.free_wipe(free_wipe),

	.rd_data(ht_buf_rd_data),
	.rd_valid(ht_buf_rd_valid),
	.rd_ready(ht_buf_rd_ready),

	.wr_data(ht_wr_data),
	.wr_valid(ht_wr_valid),
	.wr_ready(~ht_wr_stall),

	.wrcmd_data(wrcmd_data),
	.wrcmd_valid(wrcmd_valid),
	.wrcmd_ready(wrcmd_ready), 

    .debug(write_module_debug)

);    

nukv_fifogen #(
    .DATA_SIZE(49),
    .ADDR_BITS(6)
) fifo_freepointers (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata({free_wipe,free_data,free_size}),
    .s_axis_tvalid(free_valid),
    .s_axis_tready(free_ready),
    
    .m_axis_tdata(free_data_full_b),
    .m_axis_tvalid(free_valid_b),
    .m_axis_tready(free_ready_b)
);
assign free_wipe_b = free_data_full_b[32+16];
assign free_data_b = free_data_full_b[32+16-1:16];
assign free_size_b = free_data_full_b[15:0];

nukv_fifogen #(
    .DATA_SIZE(65),
    .ADDR_BITS(6)
) fifo_mallocpointers (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata({malloc_failed,malloc_data}),
    .s_axis_tvalid(malloc_valid),
    .s_axis_tready(malloc_ready),
    
    .m_axis_tdata(malloc_data_full_b),
    .m_axis_tvalid(malloc_valid_b),
    .m_axis_tready(malloc_ready_b)
);

assign malloc_failed_b = malloc_data_full_b[32];
assign malloc_data_b = malloc_data_full_b[31:0];

wire [31:0] p_rdcmd_data_short;
wire [31:0] p_wrcmd_data_short;
wire [31:0] b_rdcmd_data_short;
wire [7:0]  b_rdcmd_cnt;
wire [31:0] b_wrcmd_data_short;


nukv_fifogen #(
    .DATA_SIZE(16),
    .ADDR_BITS(6)
) fifo_malloc_request (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(mreq_data),
    .s_axis_tvalid(mreq_valid),
    .s_axis_tready(mreq_ready),
    
    .m_axis_tdata(mreq_data_b),
    .m_axis_tvalid(mreq_valid_b),
    .m_axis_tready(mreq_ready_b)
);

 wire malloc_error_valid;
 wire[7:0] malloc_error_state;
 wire[31:0] malloc_stat_size;


nukv_Malloc #(
				.IS_SIM(IS_SIM), 
				.SUPPORT_SCANS(SUPPORT_SCANS),
                .MAX_MEMORY_SIZE(VALUESTORE_MEM_SIZE)
	) 
	mallocmodule
    (
	.clk(clk),
	.rst(rst),

	.req_data(mreq_data_b),
	.req_valid(mreq_valid_b),
	.req_ready(mreq_ready_b),

	.malloc_pointer(malloc_data),
	.malloc_valid(malloc_valid),
	.malloc_failed(malloc_failed),
	.malloc_ready(malloc_ready),

	.free_pointer(free_data_b),
	.free_size(free_size_b),
	.free_valid(free_valid_b),
	.free_ready(free_ready_b),
	.free_wipe(free_wipe_b),

	.p_rdcmd_data(p_rdcmd_data_short),
	.p_rdcmd_valid(p_rdcmd_valid),
	.p_rdcmd_ready(p_rdcmd_ready),

	.p_rd_data(p_rd_data),
	.p_rd_valid(p_rd_valid),
	.p_rd_ready(p_rd_ready),	

	.p_wr_data(p_wr_data),
	.p_wr_valid(p_wr_valid),
	.p_wr_ready(p_wr_ready),

	.p_wrcmd_data(p_wrcmd_data_short),
	.p_wrcmd_valid(p_wrcmd_valid),
	.p_wrcmd_ready(p_wrcmd_ready),


	.b_rdcmd_data(b_rdcmd_data_short),
    .b_rdcmd_cnt(b_rdcmd_cnt),
	.b_rdcmd_valid(b_rdcmd_valid),
	.b_rdcmd_ready(b_rdcmd_ready),

	.b_rd_data(b_rd_data),
	.b_rd_valid(b_rd_valid),
	.b_rd_ready(b_rd_ready),	

	.b_wr_data(b_wr_data),
	.b_wr_valid(b_wr_valid),
	.b_wr_ready(b_wr_ready),

	.b_wrcmd_data(b_wrcmd_data_short),
	.b_wrcmd_valid(b_wrcmd_valid),
	.b_wrcmd_ready(b_wrcmd_ready),

	.scan_start(scan_kickoff),

	.is_scanning(scan_reading),
	.scan_numlines(scan_readsissued),

	.scan_valid(scan_valid),
	.scan_addr(scan_addr),
	.scan_cnt(scan_cnt),
	.scan_ready(scan_ready),

	.scan_pause(SUPPORT_SCANS==1 ? scan_pause : 0),

    .error_memory(malloc_error_valid),
    .error_state(malloc_error_state),
    
    .stat_size(malloc_stat_size)

);

assign scan_mode_on = 0;      

assign b_rdcmd_data ={24'b000000000000000100000001, b_rdcmd_cnt[7:0], 4'b0000, b_rdcmd_data_short[27:0]};
assign b_wrcmd_data ={24'b000000000000000100000001, 8'b00000001, 4'b0000, b_wrcmd_data_short[27:0]};
assign p_rdcmd_data ={24'b000000000000000100000001, 8'b00000001, 4'b0000, p_rdcmd_data_short[27:0]};
assign p_wrcmd_data ={24'b000000000000000100000001, 8'b00000001, 4'b0000, p_wrcmd_data_short[27:0]};

assign ht_rd_cmd_data ={24'b000000000000000100000001, 8'b00000001, 4'b0000, rdcmd_data[27:0]};
assign ht_rd_cmd_valid = rdcmd_valid;
assign rdcmd_ready = ~ht_rd_cmd_stall;

assign ht_wr_cmd_data ={24'b000000000000000100000001, 8'b00000001, 4'b0000, wrcmd_data[27:0]};
assign ht_wr_cmd_valid = wrcmd_valid;
assign wrcmd_ready = ~ht_wr_cmd_stall;




always @(posedge clk) begin
    if (rst) begin
        decruserValid <= 0;
        decruserID <= 0;
    end
    else begin
        decruserValid <= fromset_b_valid & fromset_b_ready;
        decruserID <= fromset_b_data[KEY_WIDTH+EXT_META_WIDTH-USER_BITS +: USER_BITS];
    end 
end

fifo_512bit_regslice write_out_reg_slice (
  .s_aclk(clk),                // input wire s_aclk
  .s_aresetn(~rst),          // input wire s_aresetn
  .s_axis_tvalid(writeout_valid_prebuf),  // input wire s_axis_tvalid
  .s_axis_tready(writeout_ready_prebuf),  // output wire s_axis_tready
  .s_axis_tdata(writeout_data_prebuf),    // input wire [255 : 0] s_axis_tdata
  .m_axis_tvalid(writeout_valid),  // output wire m_axis_tvalid
  .m_axis_tready(writeout_ready),  // input wire m_axis_tready
  .m_axis_tdata(writeout_data)    // output wire [255 : 0] m_axis_tdata
);

generate

if (ENABLE_CHECKPOINTS==1) 
begin
/*
	muu_Checkpoint #(
	    .DATA_WIDTH(KEY_WIDTH+EXT_META_WIDTH+HEADER_WIDTH),
	    .USER_BITS(USER_BITS),
	    .COST_BITS(16)
	) fifo_w_checkpoint (

	    .clk(clk),
	    .rst(rst),

	    .in_data(writeout_data),
	    .in_valid(writeout_valid),
	    .in_ready(writeout_ready),
	    .in_cost(writeout_data[KEY_WIDTH+EXT_META_WIDTH+HEADER_WIDTH +: 16]),
	    .in_user(writeout_data[KEY_WIDTH+EXT_META_WIDTH-USER_BITS  +: USER_BITS]),
	    .in_first(1'b1),
	    .in_last(1'b1),

	    .out_data(writeout_int_data),
	    .out_valid(writeout_int_valid),
	    .out_ready(writeout_int_ready),
	    .out_user(writeout_int_user),
	    .out_first(),
	    .out_last(),

	    .config_valid(checkpt_second_valid_buf),
	    .config_burst(checkpt_second_burst_buf),
	    .config_user(checkpt_second_user_buf),
	    .config_updfreq(checkpt_second_freq_buf),
	    .config_updcount(checkpt_second_cnt_buf),

	    //no op count limit neededwriteout_data
	    .decrement_valid(decruserValid),
	    .decrement_user(decruserID)
	);
	*/
end else begin
	assign writeout_int_data = writeout_data;
	assign writeout_int_valid = writeout_valid;
	assign writeout_int_user = writeout_data[KEY_WIDTH+EXT_META_WIDTH-USER_BITS  +: USER_BITS];
	assign writeout_ready  = writeout_int_ready;
end
endgenerate

nukv_fifogen #(
    .DATA_SIZE(KEY_WIDTH+EXT_META_WIDTH+HEADER_WIDTH),
    .ADDR_BITS(6)
) fifo_write_to_set (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(writeout_int_data),
    .s_axis_tvalid(writeout_int_valid),
    .s_axis_tready(writeout_int_ready),
    
    .m_axis_tdata(writeout_b_data),
    .m_axis_tvalid(writeout_b_valid),
    .m_axis_tready(writeout_b_ready)
);

wire predconf_valid;
wire predconf_scan;
wire predconf_ready;
wire predevalpipe_ready;
wire[NET_META_WIDTH+MEMORY_WIDTH-1:0] predconf_data;

wire predconf_b_valid;
wire predconf_b_scan;
wire predconf_b_ready;
wire[NET_META_WIDTH+MEMORY_WIDTH-1:0] predconf_b_data;
wire[1+NET_META_WIDTH+MEMORY_WIDTH-1:0] predconf_b_fulldata;

assign setter_rdcmd_ready = (scan_mode_on == 1 && SUPPORT_SCANS==1) ? 0 : upd_rdcmd_ready;
assign scan_rdcmd_ready = (scan_mode_on == 1 && SUPPORT_SCANS==1) ? upd_rdcmd_ready : 0;

assign upd_rdcmd_data = (scan_mode_on == 1 && SUPPORT_SCANS==1) ? scan_rdcmd_data : setter_rdcmd_data;
assign upd_rd_cmd_valid = (scan_mode_on == 1 && SUPPORT_SCANS==1) ? scan_rdcmd_valid : setter_rdcmd_valid;

muu_Value_Set #(
    .SUPPORT_SCANS(SUPPORT_SCANS),
    .META_WIDTH(EXT_META_WIDTH),
    .KEY_WIDTH(KEY_WIDTH),
    .HEADER_WIDTH(HEADER_WIDTH)
    ) 
	valuesetter
	(
	.clk(clk),
	.rst(rst),

	.input_data(writeout_b_data),
	.input_valid(writeout_b_valid),
	.input_ready(writeout_b_ready),

	.value_data(value_b_data[VALUE_WIDTH-1:0]),
	.value_valid(value_b_valid),
	.value_ready(value_b_ready),

	.output_data(fromset_data),
	.output_valid(fromset_valid),
	.output_ready(fromset_ready),

	.wrcmd_data(upd_wrcmd_data),
	.wrcmd_valid(upd_wr_cmd_valid),
	.wrcmd_ready(upd_wrcmd_ready),

	.wr_data(upd_wr_data),
	.wr_valid(upd_wr_valid),
	.wr_ready(~upd_wr_stall),

	.rdcmd_data(setter_rdcmd_data) ,
	.rdcmd_valid(setter_rdcmd_valid),
	.rdcmd_ready(setter_rdcmd_ready),

	.pe_valid(predconf_valid),
	.pe_scan(predconf_scan),
	.pe_ready(predconf_ready),
	.pe_data(predconf_data),

	.scan_start(scan_kickoff),
	.scan_mode(scan_mode_on),

    .repl_data_valid(repldata_valid),
    .repl_data_data(repldata_data),
    .repl_data_ready(repldata_ready),

    .repl_conf_valid(replconf_valid),
    .repl_conf_count(replconf_count),
    .repl_conf_size(replconf_size),
    .repl_conf_ready(replconf_ready)

);

nukv_fifogen #(
    .DATA_SIZE(MEMORY_WIDTH+NET_META_WIDTH+1),
    .ADDR_BITS(7)
) fifo_output_conf_pe (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata({predconf_data, predconf_scan}),
    .s_axis_tvalid(predconf_valid),
    .s_axis_tready(predconf_ready),
    
    .m_axis_tdata(predconf_b_fulldata),
    .m_axis_tvalid(predconf_b_valid),
    .m_axis_tready(predconf_b_ready)
);

muu_DataRepeater data_replicator (
    .clk(clk),
    .rst(rst),

    .s_axis_tdata(repldata_data),
    .s_axis_tvalid(repldata_valid),
    .s_axis_tready(repldata_ready),

    .config_count(replconf_count),
    .config_size(replconf_size),
    .config_valid(replconf_valid),
    .config_ready(replconf_ready),

    .m_axis_tdata(repldata_preb_data),
    .m_axis_tvalid(repldata_preb_valid),
    .m_axis_tready(repldata_preb_ready)
);


wire[VALUE_WIDTH-1:0] value_read_data_int;
wire value_read_valid_int;
wire value_read_ready_int;
wire value_read_almostfull_int2;



always @(posedge clk) begin
	if (rst) begin
//		upd_rd_isvalid <= 0;	
		
		scan_pause <= 0;	
	end
	else begin
//		upd_rd_isvalid <= ~upd_rd_empty & upd_rd_read;

        if (scan_readsissued>0 && scan_readsissued-scan_readsprocessed> (IS_SIM==1 ? 3 : 32)) begin
            scan_pause <= 1;            
        end else begin
            scan_pause <= 0;
        end
		
	end
end



nukv_fifogen #(
    .DATA_SIZE(VALUE_WIDTH),
    .ADDR_BITS(7)
) fifo_repldatabuffer (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(repldata_preb_data),
    .s_axis_tvalid(repldata_preb_valid),
    .s_axis_tready(repldata_preb_ready),
    .s_axis_talmostfull(),
    
    .m_axis_tdata(repldata_b_data),
    .m_axis_tvalid(repldata_b_valid),
    .m_axis_tready(repldata_b_ready)
);


nukv_fifogen #(
    .DATA_SIZE(VALUE_WIDTH),
    .ADDR_BITS(6)
) fifo_valuedatafrommemory (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(upd_rd_data),
    .s_axis_tvalid(upd_rd_valid),
    .s_axis_tready(upd_rd_ready),
    .s_axis_talmostfull(value_read_almostfull_int2),
    
    .m_axis_tdata(value_read_data_int),
    .m_axis_tvalid(value_read_valid_int),
    .m_axis_tready(value_read_ready_int)
);

wire[511:0] value_read_data_buf;
wire value_read_ready_buf;
wire value_read_valid_buf;

nukv_fifogen #(
    .DATA_SIZE(VALUE_WIDTH),
    .ADDR_BITS(6)
) fifo_valuedatafrommemory2 (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata(value_read_data_int),
    .s_axis_tvalid(value_read_valid_int),
    .s_axis_tready(value_read_ready_int),
    .s_axis_talmostfull(value_read_almostfull_int),
    
    .m_axis_tdata(value_read_data_buf),
    .m_axis_tvalid(value_read_valid_buf),
    .m_axis_tready(value_read_ready_buf)
);


wire toget_ready;
assign fromset_ready = (scan_mode_on==0 || SUPPORT_SCANS==0) ? toget_ready : 0;
assign pe_cmd_ready =  (scan_mode_on==0 || SUPPORT_SCANS==0) ? 0 : toget_ready;

nukv_fifogen #(
    .DATA_SIZE(KEY_WIDTH+EXT_META_WIDTH+HEADER_WIDTH),
    .ADDR_BITS(7)
) fifo_output_from_set (
    .clk(clk),
    .rst(rst),
    
    .s_axis_tdata((scan_mode_on==0 || SUPPORT_SCANS==0) ? fromset_data : {8'b00001111, pe_cmd_meta[0 +: 88], 1'b0, pe_cmd_data[9:0], 159'd0}),
    .s_axis_tvalid((scan_mode_on==0 || SUPPORT_SCANS==0) ? fromset_valid : pe_cmd_valid),
    .s_axis_tready(toget_ready),
    
    .m_axis_tdata(fromset_b_data),
    .m_axis_tvalid(fromset_b_valid),
    .m_axis_tready(fromset_b_ready)
);

wire cond_valid;
wire cond_ready;
wire cond_drop;

generate
    if (FILTER_ENABLED==0) begin
        //no filters in the project, cuts out whole part
        assign cond_valid = predconf_b_valid;
        assign cond_drop = 0;
        assign predconf_b_ready = cond_ready;

        assign value_read_ready_buf = value_read_ready;
        assign value_read_valid = value_read_valid_buf;
        assign value_read_data = value_read_data_buf;        

    end
    else begin
    
        nukv_Value_Segmenter segmenter (
        .clk(clk),
        .rst(rst),
        .value_data(value_read_data_buf),
        .value_valid(value_read_valid_buf),
        .value_ready(value_read_ready_buf),

        .output_data(val_to_proc_TDATA),
        .output_last(val_to_proc_TLAST),
        .output_valid(val_to_proc_TVALID),
        .output_ready(val_to_proc_TREADY)
   		 );
    
	    assign par_to_proc_TVALID = predconf_b_valid;
	    assign par_to_proc_TLAST = 1;
	    assign par_to_proc_TDATA = predconf_b_fulldata[1 +: 512];
	    assign predconf_b_ready = par_to_proc_TREADY;

	    //The actual processing happens outside of this module. See outgoing signals!

	    assign cond_valid = par_from_proc_TVALID;
	    assign cond_drop = par_to_proc_TDATA == 0 ? 0 : 1;
	    assign par_from_proc_TREADY = cond_ready;

	    nukv_fifogen #(
		    .DATA_SIZE(VALUE_WIDTH),
		    .ADDR_BITS(6)
		) fifo_value_from_proc (
		    .clk(clk),
		    .rst(rst),
		    
		    .s_axis_tdata(val_from_proc_TDATA),
		    .s_axis_tvalid(val_from_proc_TVALID),
		    .s_axis_tready(val_from_proc_TREADY),
		    .s_axis_talmostfull(),
		    
		    .m_axis_tdata(value_read_data),
		    .m_axis_tvalid(value_read_valid),
		    .m_axis_tready(value_read_ready)
		);

    end
endgenerate


muu_Value_Get512 #(
    .SUPPORT_SCANS(SUPPORT_SCANS),
    .META_WIDTH(EXT_META_WIDTH),
    .KEY_WIDTH(KEY_WIDTH),
    .USER_BITS(USER_BITS),
    .HEADER_WIDTH(HEADER_WIDTH)
    ) 
	valuegetter
	(
	.clk(clk),
	.rst(rst),

	.input_data(fromset_b_data),
	.input_valid(fromset_b_valid),
	.input_ready(fromset_b_ready),

	.value_data(value_read_data),//value_frompred_b_data),
	.value_valid(value_read_valid),//value_frompred_b_valid),
	.value_ready(value_read_ready),//value_frompred_b_ready),

    //these are wired up to the predicate configuration, just to ensure that for each GETCOND we get a signal
	.cond_valid(cond_valid),
	.cond_drop(cond_drop),
	.cond_ready(cond_ready), 

    .repl_in_valid(repldata_b_valid),
    .repl_in_data(repldata_b_data),
    .repl_in_ready(repldata_b_ready),

	.output_data(m_axis_tdata),
    .output_user(m_axis_tuserid),
	.output_valid(m_axis_tvalid),
	.output_ready(m_axis_tready),
	.output_last(m_axis_tlast),

	.scan_mode(scan_mode_on),
		    
    .malloc_stat_data(malloc_stat_size)

);

reg firstOutCycle;
reg outputIsReplResp;
reg[31:0] timeCyclesBuf;
reg[31:0] replWriteCyclesBuf;

reg outputErrorHead;

always @(posedge clk) begin 
    if(rst) begin
        firstOutCycle <= 1;
        outputIsReplResp <= 0;
        outputErrorHead <= 0;
    end else begin
        outputIsReplResp <= 0;
        outputErrorHead <= 0;
        timeCyclesBuf <= timeCycles;

        if (m_axis_tvalid==1 && m_axis_tready==1) begin
            firstOutCycle <= 0;

            if (firstOutCycle==1 && m_axis_tdata[16 +:16]==16'h0001 && replWriteValid==1) begin
                //is a repl response
                outputIsReplResp <= 1;
                replWriteCyclesBuf <= replWriteCycles;

            end

            if (firstOutCycle==1 && (m_axis_tdata[15:0]!=16'hFFFF || m_axis_tdata[16 +: 8]> 8'h05)) begin
                outputErrorHead <= 1;
            end

            if (m_axis_tlast==1) begin
                firstOutCycle <= 1;
            end
        end
    end
end
/*
assign replWriteRead = outputIsReplResp;

 assign m_axis_tvalid = (final_out_data[64+:16]==16'h7fff) ? 0 : final_out_valid;
 assign m_axis_tlast = final_out_valid & final_out_last;
 assign m_axis_tdata = outputIsReplResp ? {timeCyclesBuf,replWriteCyclesBuf} : final_out_data;
 assign m_axis_tuserid = final_out_user;
 assign final_out_ready = m_axis_tready;
 */

assign upd_rd_cmd_data ={24'b000000000000000100000001, upd_rdcmd_data[39:32], {32-VALUESTORE_MEM_SIZE{1'b0}}, upd_rdcmd_data[VALUESTORE_MEM_SIZE-1:0]};
assign upd_rdcmd_ready = ~upd_rd_cmd_stall;

assign upd_wr_cmd_data ={24'b000000000000000100000001, upd_wrcmd_data[39:32], {32-VALUESTORE_MEM_SIZE{1'b0}}, upd_wrcmd_data[VALUESTORE_MEM_SIZE-1:0]};
assign upd_wrcmd_ready = ~upd_wr_cmd_stall;

reg[31:0] rdaddr_aux;
reg[191:0] data_aux;




   // -------------------------------------------------
   


   wire [35:0] 				    control0, control1;
   reg [255:0] 			    data;
   reg [255:0] 				    debug_r;
   reg [255:0] 				    debug_r2;
   wire [63:0] 				    vio_cmd;
   reg [63:0] 				    vio_cmd_r;


   always @(posedge clk) begin

        if (rst==1) begin
            input_counter<=0;
        end else begin
            if(debug_r[2:0]==3'b111) begin
                input_counter<= input_counter+1;
            end
        end

      	//data_aux <= {writeout_data[64+163+32 +: 10],towrite_b_data[128 +: 163]};
        //data_aux <= {reqsplit_debug, replicate_debug_data[23:0], 3'd0, replicate_error_valid, replicate_error_opcode, write_module_debug, 5'd0, s_axis_tuserid, s_axis_tdata};
       
       // data_aux <= {m_axis_tdata, write_module_debug, 5'd0, s_axis_tuserid, s_axis_tdata[127: 128-24], s_axis_tdata[63:0]};
       data_aux <= {m_axis_tdata, write_module_debug, s_axis_tdata[127: 128-24], s_axis_tdata[63:0], replicate_error_opcode};

      debug_r[0] <=  s_axis_tvalid  ;
      debug_r[1] <=  s_axis_tready;
      debug_r[2] <=  s_axis_tlast;
      debug_r[3] <=   key_valid ;
      debug_r[4] <=   key_ready;
      debug_r[5] <=    meta_valid;
      debug_r[6] <=    meta_ready;
      debug_r[7] <=    value_valid;
      debug_r[8] <=    value_ready;
      debug_r[9] <=    mreq_valid;
      debug_r[10] <=    mreq_ready;
      debug_r[11] <=    keywhash_valid;
      debug_r[12] <=    keywhash_ready;
      debug_r[13] <=    feedbwhash_valid;
      debug_r[14] <=    feedbwhash_ready;
      debug_r[15] <=    towrite_valid;
      debug_r[16] <=    towrite_ready;
      debug_r[17] <=    rdcmd_valid;
      debug_r[18] <=    rdcmd_ready;
      debug_r[19] <=    writeout_valid;
      debug_r[20] <=    writeout_ready;
      
      ///
      debug_r[21] <=    replconf_valid;
      debug_r[22] <=    replconf_ready;
      debug_r[23] <=    (replconf_size==0 || replconf_count==0 ? 0 : 1);            
      ///
      
      debug_r[24] <=    free_valid;
      debug_r[25] <=    free_ready;
      debug_r[26] <=    ht_buf_rd_valid;
      debug_r[27] <=    ht_buf_rd_ready;
      debug_r[28] <=    ht_wr_valid;
      debug_r[29] <=    ht_wr_stall;
      debug_r[30] <=    wrcmd_valid;
      debug_r[31] <=    wrcmd_ready;
      debug_r[32] <=    writeout_b_valid;
      debug_r[33] <=    writeout_b_ready;
      debug_r[34] <=    value_b_valid;
      debug_r[35] <=    value_b_ready;
      debug_r[36] <=    fromset_valid;
      debug_r[37] <=    fromset_ready;
      debug_r[38] <=    b_rdcmd_valid;
      debug_r[39] <=    b_rdcmd_ready;
      debug_r[40] <=    b_rd_valid;
      debug_r[41] <=    b_rd_ready;
      debug_r[42] <=    upd_rd_cmd_valid;
      debug_r[43] <=    ~upd_rd_cmd_stall;
      debug_r[44] <=    fromset_b_valid;
      debug_r[45] <=    fromset_b_ready;
      debug_r[46] <=    value_read_valid;
      debug_r[47] <=    value_read_ready;
      debug_r[48] <=	upd_wr_cmd_valid;
      debug_r[49] <= 	upd_wr_cmd_stall;
      debug_r[50] <=	upd_wr_valid;
      debug_r[51] <= 	upd_wr_stall;
      debug_r[52] <=    m_axis_tvalid;
      debug_r[53] <=    m_axis_tready;

      debug_r[54] <=    m_axis_tlast;

      debug_r[55] <= 	firstOutCycle;
      
      debug_r[56] <= replicate_error_valid;
      //debug_r[56] <= pred_eval_error;

      debug_r[57] <= malloc_error_valid;

      debug_r[58] <= reqsplit_debug[0];

      debug_r[59] <= 0;

      debug_r[64 +: 192] <= data_aux;


      
      debug_r2 <= debug_r;

      
      
   end

   assign debug = debug_r2;
/*
   
   icon icon_inst(
		  .CONTROL0(control0),
		  .CONTROL1(control1)
		  );
   
   vio vio_inst(
		.CONTROL(control1),
		.CLK(clk),
		.SYNC_OUT(vio_cmd)
		//     .SYNC_OUT()
		);
   
   ila_256 ila_256_inst(
			.CONTROL(control0),
			.CLK(clk),
			.TRIG0(data)
			);
			
 /**/

endmodule

`default_nettype wire
