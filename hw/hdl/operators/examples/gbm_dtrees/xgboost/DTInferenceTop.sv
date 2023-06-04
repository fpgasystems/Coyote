`timescale 1ns / 1ps
/**
 * User logic wrapper
 * 
 */
module DTInferenceTop (
    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn,

    // AXI4 control
    AXI4Lite.s                  axi_ctrl,

    // AXI4 data
    AXI4.s                      axi_data,

    // AXI4S host
    AXI4S.m                     axis_host_0_src,
    AXI4S.s                     axis_host_0_sink,

    // AXI4S card
    AXI4S.m                     axis_card_0_src,
    AXI4S.s                     axis_card_0_sink
);

/* -- Tie-off unused interfaces and signals ----------------------------- */
//always_comb axi_ctrl.tie_off_s();
always_comb axi_data.tie_off_s();
//always_comb axis_host_0_src.tie_off_m();
//always_comb axis_host_0_sink.tie_off_s();
always_comb axis_card_0_src.tie_off_m();
always_comb axis_card_0_sink.tie_off_s();

/* -- USER LOGIC -------------------------------------------------------- */
localparam [1:0] IDLE           = 2'b00, 
                 READ_TREES     = 2'b01, 
                 WAIT_ALL_TREES = 2'b10, 
                 READ_DATA      = 2'b11;

reg  [1:0]                          reader_state;
reg  [1:0]                          nxt_reader_state;    
wire                                trees_read_done;
wire                                data_read_done;   

wire                                wr_tvalid;
wire                                wr_tready;
wire [511:0]                        wr_tdata;

wire                                rd_tvalid;
wire                                rd_ttype;
wire                                rd_tlast;
wire                                rd_tready;
wire [511:0]                        rd_tdata;      

reg  [31:0]                         sentOutCLs;
wire [31:0]                         next_sentOutCLs;

logic                               ap_start_r              = 1'b0;
logic                               ap_start_pulse_d1       = 1'b0;
wire                                ap_start                      ;
wire [16-1:0]                       tuple_numcls                  ;
wire [8-1:0]                        treeDepth                     ;
wire [8-1:0]                        puTrees                       ;
wire [31:0]                         outputNumCLs;

wire [8-1:0]                        prog_schedule  ;
wire [8-1:0]                        proc_schedule  ;
wire [16-1:0]                       tree_weights_numcls_minus_one;
wire [16-1:0]                       tree_feature_index_numcls_minus_one;

logic [8-1:0]                       num_trees_per_pu_minus_one;
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Parameters on AxiLite            /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

// AXI4-Lite slave interface
engineParams #(
  .C_ADDR_WIDTH ( 64 ),
  .C_DATA_WIDTH ( 64 )
)
inst_control_s_axi (
  .aclk            ( ap_clk           ),
  .areset          ( !aresetn         ),
  .aclk_en         ( 1'b1             ),
  .awvalid         ( axi_ctrl.awvalid ),
  .awready         ( axi_ctrl.awready ),
  .awaddr          ( axi_ctrl.awaddr  ),
  .wvalid          ( axi_ctrl.wvalid  ),
  .wready          ( axi_ctrl.wready  ),
  .wdata           ( axi_ctrl.wdata   ),
  .wstrb           ( axi_ctrl.wstrb   ),
  .arvalid         ( axi_ctrl.arvalid ),
  .arready         ( axi_ctrl.arready ),
  .araddr          ( axi_ctrl.araddr  ),
  .rvalid          ( axi_ctrl.rvalid  ),
  .rready          ( axi_ctrl.rready  ),
  .rdata           ( axi_ctrl.rdata   ),
  .rresp           ( axi_ctrl.rresp   ),
  .bvalid          ( axi_ctrl.bvalid  ),
  .bready          ( axi_ctrl.ready   ),
  .bresp           ( axi_ctrl.bresp   ),
  .ap_start        ( ap_start         ),
  .tuple_numcls    ( tuple_numcls     ),
  .treeDepth       ( treeDepth        ),
  .puTrees         ( puTrees          ),
  .outputNumCLs    ( outputNumCLs     ),
  .prog_schedule   ( prog_schedule    ),
  .proc_schedule   ( proc_schedule    ),     

  .tree_weights_numcls_minus_one        (tree_weights_numcls_minus_one), 
  .tree_feature_index_numcls_minus_one  (tree_feature_index_numcls_minus_one)
);

always @(posedge aclk) begin
  if (~aresetn) begin
    num_trees_per_pu_minus_one    <= 0;  

    ap_start_r                    <= 0;
    ap_start_pulse_d1             <= 0;
  end 
  else begin
    num_trees_per_pu_minus_one    <= puTrees - 1'b1;

    ap_start_r                    <= ap_start;
    ap_start_pulse_d1             <= ap_start_pulse;
  end
end

assign ap_start_pulse = ap_start & ~ap_start_r;
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Decode Input Streams             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

// Reader State 
always@(posedge aclk) begin 
  if(~aresetn) begin
    reader_state <= IDLE;
  end
  else begin 
    reader_state <= nxt_reader_state;
  end
end

always@(*) begin 
    case (reader_state)
      IDLE          : nxt_reader_state = (ap_start_pulse_d1)?  READ_TREES    : IDLE;
      READ_TREES    : nxt_reader_state = (trees_read_done)?    WAIT_ALL_TREES: READ_TREES;
      WAIT_ALL_TREES: nxt_reader_state = READ_DATA;
      READ_DATA     : nxt_reader_state = (data_read_done)?     IDLE          : READ_DATA; 
      default       : nxt_reader_state = IDLE;
    endcase
end

assign trees_read_done = axis_host_0_sink.tlast && axis_host_0_sink.tvalid;
assign data_read_done  = axis_host_0_sink.tlast && axis_host_0_sink.tvalid;


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////                 Engine Core                 /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

// Input Streams
assign rd_tdata  = axis_host_0_sink.tdata;
assign rd_tvalid = axis_host_0_sink.tvalid;
assign rd_tlast  = axis_host_0_sink.tlast;
assign rd_ttype  = reader_state == READ_DATA;

assign axis_host_0_sink.tready = rd_tready;

// Output Stream
assign axis_host_0_src.tdata  = wr_tdata;
assign axis_host_0_src.tkeep  = 64'hffffffffffffffff;
assign axis_host_0_src.tvalid = wr_tvalid;
assign axis_host_0_src.tlast  = next_sentOutCLs == outputNumCLs;

assign wr_tready            = axis_host_0_src.tready;

// Count output numCLs

assign next_sentOutCLs = sentOutCLs + 1'b1;

always@(posedge aclk) begin 
    if(~aresetn) begin
        sentOutCLs <= 0;
    end
    else begin 
        if(sentOutCLs == outputNumCLs) begin
            sentOutCLs <= 0;
        end
        else if(wr_tvalid && wr_tready) begin
            sentOutCLs <= next_sentOutCLs;
        end
    end
end


DTInference DTInference(
  .clk                                  (aclk),
  .rst_n                                (aresetn),
  .start_core                           (ap_start_pulse_d1),
  // parameters
  
  .tuple_numcls                         (tuple_numcls),    
  .tree_weights_numcls_minus_one        (tree_weights_numcls_minus_one), 
  .tree_feature_index_numcls_minus_one  (tree_feature_index_numcls_minus_one),
  .num_trees_per_pu_minus_one           (num_trees_per_pu_minus_one[4:0]), 
  .tree_depth                           (treeDepth[3:0]), 
  .prog_schedule                        (prog_schedule), 
  .proc_schedule                        (proc_schedule),
  // input trees
  .core_in                              (rd_tdata),
  .core_in_type                         (rd_ttype),   
  .core_in_valid                        (rd_tvalid),
  .core_in_last                         (rd_tlast), 
  .core_in_ready                        (rd_tready),
  // output 
  .core_result_out                      (wr_tdata), 
  .core_result_valid                    (wr_tvalid), 
  .core_result_ready                    (wr_tready)
);

endmodule

