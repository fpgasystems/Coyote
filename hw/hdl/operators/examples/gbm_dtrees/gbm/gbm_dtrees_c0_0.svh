//
// Gradient boosting decision trees
//

// UL
AXI4SR axis_sink_int ();
AXI4SR axis_src_int ();

axisr_reg inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_0_sink), .m_axis(axis_sink_int));
axisr_reg inst_reg_src (.aclk(aclk), .aresetn(aresetn),  .s_axis(axis_src_int),   .m_axis(axis_host_0_src));

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
wire [16-1:0]                       numFeatures                   ;
wire [8-1:0]                        treeDepth                     ;
wire [8-1:0]                        puTrees                       ;
wire [16-1:0]                       lastOutLineMask               ;
wire [31:0]                         outputNumCLs;

logic [16-1:0]                      num_64bit_words_per_tuple;
logic [8-1:0]                       num_trees_per_pu_minus_one;

logic [31:0]                        num_data_cls;
logic [31:0]                        num_trees_cls;
logic [31:0]                        num_result_cls;

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Parameters on AxiLite            /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

// AXI4-Lite slave interface
gbm_slave inst_control_s_axi (
  .aclk            ( aclk             ),
  .aresetn         ( aresetn          ),
  .axi_ctrl        ( axi_ctrl         ),
  .ap_start        ( ap_start         ),
  .numFeatures     ( numFeatures      ),
  .treeDepth       ( treeDepth        ),
  .puTrees         ( puTrees          ),
  .outputNumCLs    ( outputNumCLs     ),
  .lastOutLineMask ( lastOutLineMask  )
);

always @(posedge aclk) begin
  if (~aresetn) begin
    num_trees_per_pu_minus_one    <= 0;  
    num_64bit_words_per_tuple     <= 0;

    ap_start_r                    <= 0;
    ap_start_pulse_d1             <= 0;
  end 
  else begin
    num_trees_per_pu_minus_one    <= puTrees - 1'b1;
    num_64bit_words_per_tuple     <= numFeatures[7:1] + numFeatures[0];

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

assign trees_read_done = axis_sink_int.tlast && axis_sink_int.tvalid && axis_sink_int.tready;
assign data_read_done  = axis_sink_int.tlast && axis_sink_int.tvalid && axis_sink_int.tready;


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////                 Engine Core                 /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

// Input Streams
assign rd_tdata  = axis_sink_int.tdata;
assign rd_tvalid = axis_sink_int.tvalid;
assign rd_tlast  = axis_sink_int.tlast;
assign rd_ttype  = reader_state == READ_DATA;

assign axis_sink_int.tready = rd_tready && (reader_state == READ_TREES || reader_state == READ_DATA);

// Output Stream
assign axis_src_int.tdata  = wr_tdata;
assign axis_src_int.tkeep  = 64'hffffffffffffffff;
assign axis_src_int.tid    = 0;
assign axis_src_int.tvalid = wr_tvalid;
assign axis_src_int.tlast  = next_sentOutCLs == outputNumCLs;

assign wr_tready         = axis_src_int.tready;

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


DTProcessor DTProcessor(
  .clk                            (aclk),
  .rst_n                          (aresetn),
  .start_core                     (ap_start_pulse_d1),
  // parameters
  
  .tuple_length                   (numFeatures[5:0]),     
  .num_trees_per_pu_minus_one     (num_trees_per_pu_minus_one[4:0]), 
  .tree_depth                     (treeDepth[3:0]), 
  .num_lines_per_tuple            ({2'b00, num_64bit_words_per_tuple[6:0]}), 
  // input trees
  .core_data_in                   (rd_tdata),
  .core_data_in_type              (rd_ttype),   
  .core_data_in_valid             (rd_tvalid),
  .core_data_in_last              (rd_tlast), 
  .core_data_in_ready             (rd_tready),
  // output 
  .last_result_line               ( (next_sentOutCLs == outputNumCLs) ), 
  .last_result_line_mask          (lastOutLineMask[15:0]),
  .core_result_out                (wr_tdata), 
  .core_result_valid              (wr_tvalid), 
  .core_result_ready              (wr_tready)
);

////////////////////////////////////////////////////////////////////////////////////////////////////
// debug counters
always@(posedge aclk) begin 
    if(~aresetn) begin
        num_data_cls   <= 0;
        num_trees_cls  <= 0;
        num_result_cls <= 0;
    end
    else begin 
        //
        if(ap_start_pulse) begin
          num_data_cls   <= 0;
          num_trees_cls  <= 0;
          num_result_cls <= 0;
        end
        else begin 
          //
          if(rd_tvalid && rd_tready && rd_ttype) begin
            num_data_cls   <= num_data_cls  + 1'b1;
          end
          //
          if(rd_tvalid && rd_tready && !rd_ttype) begin
            num_trees_cls   <= num_trees_cls  + 1'b1;
          end
          //
          if(wr_tvalid && wr_tready) begin
            num_result_cls   <= num_result_cls  + 1'b1;
          end
        end
    end
end
