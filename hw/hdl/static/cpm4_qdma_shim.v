// CPM4 <-> eQDMA shim for the VCK5000 (Versal VC1902).
//
// Keeps design_static's boundary IDENTICAL to the V80 (CPM5/eQDMA) by converting, entirely
// inside design_static, between the CPM4 (plain QDMA) versal_cips pins and the eQDMA-style
// boundary interfaces the rest of Coyote (static_top, qdma_rd/wr wrappers) consumes.
//
// Boundary interfaces presented (full V80 member sets, matching static_top):
//   m_axis_h2c (display_eqdma, Master)  s_axis_c2h (display_eqdma, Slave)
//   h2c_status (eqdma_qsts, Master)     c2h_status (qdma_c2h_status, Master)
//   dsc_bypass_c2h (qdma_dsc_byp, Slave) dsc_pr (qdma_dsc_byp MM, Slave)
// (dsc_bypass_h2c is connected directly to CPM4 in cr_pci.tcl; its members all exist on CPM4.)
//
// CPM4 gaps bridged: tcrc/ecc (m/s data), pfch_tag (c2h cmd), no_dma (pr), error/last/status_cmp
// (c2h status) do not exist on CPM4 -> defaulted here; qid is 12b on the boundary vs 11b on CPM4
// streams -> width-adapted. Build/timing-oriented; functional semantics refined on the board.
module cpm4_qdma_shim (
  // ===== boundary: H2C data (eQDMA m_axis_h2c, Master out) =====
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c tdata"     *) output wire [511:0] m_axis_h2c_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c tcrc"      *) output wire [31:0]  m_axis_h2c_tcrc,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c tvalid"    *) output wire         m_axis_h2c_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c tlast"     *) output wire         m_axis_h2c_tlast,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c tready"    *) input  wire         m_axis_h2c_tready,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c qid"       *) output wire [11:0]  m_axis_h2c_qid,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c port_id"   *) output wire [2:0]   m_axis_h2c_port_id,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c err"       *) output wire         m_axis_h2c_err,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c mdata"     *) output wire [31:0]  m_axis_h2c_mdata,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c mty"       *) output wire [5:0]   m_axis_h2c_mty,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c zero_byte" *) output wire         m_axis_h2c_zero_byte,

  // ===== boundary: C2H data (eQDMA s_axis_c2h, Slave in) =====
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h tdata"         *) input  wire [511:0] s_axis_c2h_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h tvalid"        *) input  wire         s_axis_c2h_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h tlast"         *) input  wire         s_axis_c2h_tlast,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h tready"        *) output wire         s_axis_c2h_tready,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h tcrc"          *) input  wire [31:0]  s_axis_c2h_tcrc,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h ecc"           *) input  wire [6:0]   s_axis_c2h_ecc,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h mty"           *) input  wire [5:0]   s_axis_c2h_mty,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h ctrl_marker"   *) input  wire         s_axis_c2h_ctrl_marker,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h ctrl_port_id"  *) input  wire [2:0]   s_axis_c2h_ctrl_port_id,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h ctrl_len"      *) input  wire [15:0]  s_axis_c2h_ctrl_len,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h ctrl_qid"      *) input  wire [11:0]  s_axis_c2h_ctrl_qid,
  (* X_INTERFACE_INFO = "xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h ctrl_has_cmpt" *) input  wire         s_axis_c2h_ctrl_has_cmpt,

  // ===== boundary: H2C status (eqdma_qsts, Master out) =====
  (* X_INTERFACE_INFO = "xilinx.com:interface:eqdma_qsts_rtl:1.0 h2c_status vld"     *) output wire         h2c_status_vld,
  (* X_INTERFACE_INFO = "xilinx.com:interface:eqdma_qsts_rtl:1.0 h2c_status rdy"     *) input  wire         h2c_status_rdy,
  (* X_INTERFACE_INFO = "xilinx.com:interface:eqdma_qsts_rtl:1.0 h2c_status op"      *) output wire [7:0]   h2c_status_op,
  (* X_INTERFACE_INFO = "xilinx.com:interface:eqdma_qsts_rtl:1.0 h2c_status data"    *) output wire [63:0]  h2c_status_data,
  (* X_INTERFACE_INFO = "xilinx.com:interface:eqdma_qsts_rtl:1.0 h2c_status qid"     *) output wire [11:0]  h2c_status_qid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:eqdma_qsts_rtl:1.0 h2c_status port_id" *) output wire [2:0]   h2c_status_port_id,

  // ===== boundary: C2H status (qdma_c2h_status, Master out) =====
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_c2h_status_rtl:1.0 c2h_status drop"       *) output wire         c2h_status_drop,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_c2h_status_rtl:1.0 c2h_status error"      *) output wire         c2h_status_error,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_c2h_status_rtl:1.0 c2h_status last"       *) output wire         c2h_status_last,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_c2h_status_rtl:1.0 c2h_status qid"        *) output wire [11:0]  c2h_status_qid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_c2h_status_rtl:1.0 c2h_status status_cmp" *) output wire         c2h_status_status_cmp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_c2h_status_rtl:1.0 c2h_status valid"      *) output wire         c2h_status_valid,

  // ===== boundary: C2H command / descriptor bypass (qdma_dsc_byp, Slave in) =====
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_bypass_c2h addr"     *) input  wire [63:0]  dsc_bypass_c2h_addr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_bypass_c2h error"    *) input  wire         dsc_bypass_c2h_error,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_bypass_c2h func"     *) input  wire [11:0]  dsc_bypass_c2h_func,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_bypass_c2h pfch_tag" *) input  wire [6:0]   dsc_bypass_c2h_pfch_tag,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_bypass_c2h port_id"  *) input  wire [2:0]   dsc_bypass_c2h_port_id,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_bypass_c2h qid"      *) input  wire [11:0]  dsc_bypass_c2h_qid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_bypass_c2h ready"    *) output wire         dsc_bypass_c2h_ready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_bypass_c2h valid"    *) input  wire         dsc_bypass_c2h_valid,

  // ===== boundary: PR MM descriptor (qdma_dsc_byp MM, Slave in) =====
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr radr"     *) input  wire [63:0]  dsc_pr_radr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr wadr"     *) input  wire [63:0]  dsc_pr_wadr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr cidx"     *) input  wire [15:0]  dsc_pr_cidx,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr error"    *) input  wire         dsc_pr_error,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr func"     *) input  wire [11:0]  dsc_pr_func,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr len"      *) input  wire [15:0]  dsc_pr_len,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr mrkr_req" *) input  wire         dsc_pr_mrkr_req,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr no_dma"   *) input  wire         dsc_pr_no_dma,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr port_id"  *) input  wire [2:0]   dsc_pr_port_id,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr qid"      *) input  wire [11:0]  dsc_pr_qid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr ready"    *) output wire         dsc_pr_ready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr sdi"      *) input  wire         dsc_pr_sdi,
  (* X_INTERFACE_INFO = "xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr valid"    *) input  wire         dsc_pr_valid,

  // ================= CPM4 versal_cips side (scalar) =================
  // H2C data (from CPM4, qid 11b)
  input  wire [511:0] cpm_h2c_tdata,
  input  wire         cpm_h2c_tvalid,
  input  wire         cpm_h2c_tlast,
  output wire         cpm_h2c_tready,
  input  wire [10:0]  cpm_h2c_qid,
  input  wire [2:0]   cpm_h2c_port_id,
  input  wire         cpm_h2c_err,
  input  wire [31:0]  cpm_h2c_mdata,
  input  wire [5:0]   cpm_h2c_mty,
  input  wire         cpm_h2c_zero_byte,
  // C2H data (to CPM4, qid 11b)
  output wire [511:0] cpm_c2h_tdata,
  output wire         cpm_c2h_tvalid,
  output wire         cpm_c2h_tlast,
  input  wire         cpm_c2h_tready,
  output wire [5:0]   cpm_c2h_mty,
  output wire [63:0]  cpm_c2h_dpar,
  output wire         cpm_c2h_ctrl_marker,
  output wire [2:0]   cpm_c2h_ctrl_port_id,
  output wire [15:0]  cpm_c2h_ctrl_len,
  output wire [10:0]  cpm_c2h_ctrl_qid,
  output wire         cpm_c2h_ctrl_dis_cmpt,
  // C2H completion stream (to CPM4 dma0_s_axis_c2h_cmpt): one 8B standard-format CMPT record
  // per data packet (the silicon-validated completion mechanism; consumed by the driver's
  // host CMPT ring). Record format per the CED c2h_stub_std_cmp_ent_t:
  // bit0 data_format=0 (standard), bits[11:1] qid, rest user data.
  output wire [127:0] cpm_c2h_cmpt_data,
  output wire [15:0]  cpm_c2h_cmpt_dpar,
  output wire [1:0]   cpm_c2h_cmpt_size,
  output wire         cpm_c2h_cmpt_tlast,
  output wire         cpm_c2h_cmpt_tvalid,
  input  wire         cpm_c2h_cmpt_tready,
  // C2H command / descriptor bypass IN (to CPM4 dma0_c2h_byp_in_st_sim -- SIMPLE bypass).
  // CPM4's byp_in carries no pfch_tag; each byp_in beat must be paired 1:1 with a c2h_byp_out
  // credit (a ring descriptor the engine fetched) -- that pairing recycles the prefetch slot.
  // The address presented is the FPGA-chosen host address (overriding the ring descriptor's),
  // which is proven to DMA correctly on HW.
  output wire [63:0]  cpm_c2h_byp_addr,
  output wire         cpm_c2h_byp_error,
  output wire [11:0]  cpm_c2h_byp_func,
  output wire [2:0]   cpm_c2h_byp_port_id,
  output wire [11:0]  cpm_c2h_byp_qid,
  input  wire         cpm_c2h_byp_ready,
  output wire         cpm_c2h_byp_valid,
  // C2H descriptor bypass OUT (from CPM4 dma0_c2h_byp_out): the credit stream. Each valid ST
  // non-marker beat is one fetched ring descriptor; its content is discarded (address is
  // overridden by the FPGA's). Marker-response / MM beats are dropped without pairing.
  input  wire         cpm_c2h_byp_out_valid,
  input  wire         cpm_c2h_byp_out_mrkr_rsp,
  input  wire         cpm_c2h_byp_out_st_mm,
  input  wire [10:0]  cpm_c2h_byp_out_qid,
  input  wire         cpm_c2h_byp_out_error,
  output wire         cpm_c2h_byp_out_ready,
  // PR MM descriptor (to CPM4) --- no no_dma on CPM4
  output wire [63:0]  cpm_pr_radr,
  output wire [63:0]  cpm_pr_wadr,
  output wire [15:0]  cpm_pr_cidx,
  output wire         cpm_pr_error,
  output wire [11:0]  cpm_pr_func,
  output wire [15:0]  cpm_pr_len,
  output wire         cpm_pr_mrkr_req,
  output wire [2:0]   cpm_pr_port_id,
  output wire [11:0]  cpm_pr_qid,
  input  wire         cpm_pr_ready,
  output wire         cpm_pr_sdi,
  output wire         cpm_pr_valid,
  // C2H status (from CPM4) --- only drop/qid/valid on CPM4
  input  wire         cpm_c2h_sts_drop,
  input  wire [11:0]  cpm_c2h_sts_qid,
  input  wire         cpm_c2h_sts_valid,
  // H2C descriptor-bypass output (from CPM4) --- carries the per-descriptor marker response
  input  wire         cpm_h2c_byp_valid,
  input  wire         cpm_h2c_byp_mrkr_rsp,
  input  wire         cpm_h2c_byp_error,
  input  wire [11:0]  cpm_h2c_byp_qid,
  input  wire [2:0]   cpm_h2c_byp_port_id,
  output wire         cpm_h2c_byp_ready,
  // Clock/reset (QDMA fabric clock domain) -- for the C2H command FIFO
  input  wire         aclk,
  input  wire         aresetn
);

  // ---- H2C data: CPM4 -> boundary (qid zero-extended 11->12; tcrc has no CPM4 source) ----
  assign m_axis_h2c_tdata     = cpm_h2c_tdata;
  assign m_axis_h2c_tvalid    = cpm_h2c_tvalid;
  assign m_axis_h2c_tlast     = cpm_h2c_tlast;
  assign cpm_h2c_tready       = m_axis_h2c_tready;
  assign m_axis_h2c_qid       = {1'b0, cpm_h2c_qid};
  assign m_axis_h2c_port_id   = cpm_h2c_port_id;
  assign m_axis_h2c_err       = cpm_h2c_err;
  assign m_axis_h2c_mdata     = cpm_h2c_mdata;
  assign m_axis_h2c_mty       = cpm_h2c_mty;
  assign m_axis_h2c_zero_byte = cpm_h2c_zero_byte;
  assign m_axis_h2c_tcrc      = 32'b0;

  // ---- C2H data: boundary -> CPM4 (qid truncated 12->11; tcrc/ecc dropped) ----
  // CPM4 checks per-byte ODD parity on the C2H write payload (dpar; ENG_WPL_DATA_PAR_ERR fires
  // otherwise and the engine jams after the first descriptor match -- verified on HW). eQDMA
  // uses tcrc/ecc instead, so the V80 path never needed this. Parity per the CED reference
  // (ST_c2h.sv): dpar[i] = ~(^data[8i+:8]).
  assign cpm_c2h_tdata         = s_axis_c2h_tdata;
  assign cpm_c2h_tvalid        = s_axis_c2h_tvalid;
  assign cpm_c2h_tlast         = s_axis_c2h_tlast;
  assign s_axis_c2h_tready     = cpm_c2h_tready;
  assign cpm_c2h_mty           = s_axis_c2h_mty;
  genvar gi;
  generate
    for (gi = 0; gi < 64; gi = gi + 1) begin : g_c2h_dpar
      assign cpm_c2h_dpar[gi] = ~(^s_axis_c2h_tdata[gi*8 +: 8]);
    end
  endgenerate
  // No markers on data packets (ctrl_marker=1 turns a data packet into a flush token --
  // HW-verified dead end). Completion is signaled via CMPT records instead (below), the
  // mechanism validated on this silicon by the mm_st mini design (qdma_stm_c2h_stub + CMPT).
  assign cpm_c2h_ctrl_marker   = 1'b0;
  assign cpm_c2h_ctrl_port_id  = s_axis_c2h_ctrl_port_id;
  assign cpm_c2h_ctrl_len      = s_axis_c2h_ctrl_len;
  assign cpm_c2h_ctrl_qid      = s_axis_c2h_ctrl_qid[10:0];
  // Completions ENABLED for every packet (dis_cmpt=0): the CPM4 C2H engine's validated
  // operating mode sends one CMPT record per packet (consumed host-side by the driver's CMPT
  // ring). The CMPT stream is generated below.
  assign cpm_c2h_ctrl_dis_cmpt = 1'b0;

  // ---- C2H simple-bypass credit pairing with FPGA-address override (CPM4) ----
  // HW-verified mechanism: each C2H packet needs a descriptor credit. The one-shot credit from
  // the 0x1408 tag arming let exactly ONE packet complete end-to-end (64B landed at the
  // FPGA-chosen address); sustained flow requires recycling the prefetch slot by consuming each
  // c2h_byp_out beat (a ring descriptor the engine fetched on data arrival) and returning a
  // descriptor on byp_in_st_sim. We pair each of Coyote's fabric commands (dsc_bypass_c2h,
  // FPGA-chosen host address) 1:1 with a credit -- the ring descriptor's content is discarded.
  // Ref: Versal CPM Gen4x8 QDMA EP CED, dsc_byp_c2h.sv.
  //
  // Ordering: qdma_wr_wrapper streams a packet's DATA only after its command is accepted, while
  // the engine fetches the ring descriptor (-> credit) only after the packet data arrives.
  // Gating command-accept on the credit would deadlock, so commands are accepted immediately
  // into a small FIFO; only the byp_in beat is gated on the credit. The wrapper is one-packet-
  // at-a-time and the engine processes packets in order, so credits arrive in command order.
  localparam C2H_CF_AW = 4;  // command FIFO depth 16
  reg [63:0] cf_addr    [0:(1<<C2H_CF_AW)-1];
  reg [11:0] cf_qid     [0:(1<<C2H_CF_AW)-1];
  reg [11:0] cf_func    [0:(1<<C2H_CF_AW)-1];
  reg [2:0]  cf_port_id [0:(1<<C2H_CF_AW)-1];
  reg        cf_error   [0:(1<<C2H_CF_AW)-1];
  reg [C2H_CF_AW:0] cf_wr, cf_rd;
  wire cf_empty = (cf_wr == cf_rd);
  wire cf_full  = (cf_wr[C2H_CF_AW-1:0] == cf_rd[C2H_CF_AW-1:0]) && (cf_wr[C2H_CF_AW] != cf_rd[C2H_CF_AW]);

  assign dsc_bypass_c2h_ready = ~cf_full;                          // accept commands immediately
  wire cf_push = dsc_bypass_c2h_valid & ~cf_full;

  // Outstanding-limit semaphore (HW-derived): the armed prefetch slot holds ONE in-flight
  // descriptor. A byp_in beat submitted while the slot is busy is silently lost (verified:
  // ungated byp_in completed exactly packet 1; the rest starved). Fire byp_in only when no
  // descriptor is outstanding; the slot frees on the axis_c2h_status pulse (count drops too,
  // so a dropped packet cannot leak the semaphore).
  reg [3:0] c2h_outst;
  // Slot frees when the packet's CMPT record is accepted by the engine (per-packet, ordered
  // behind the data DMA on PCIe -- the validated completion event on this silicon)
  wire c2h_cmpt_fire;
  wire c2h_sts_pulse = c2h_cmpt_fire;
  wire c2h_byp_fire  = ~cf_empty & (c2h_outst == 4'd0) & cpm_c2h_byp_ready;

  always @(posedge aclk) begin
    if (!aresetn) begin
      cf_wr <= {(C2H_CF_AW+1){1'b0}};
      cf_rd <= {(C2H_CF_AW+1){1'b0}};
      c2h_outst <= 4'd0;
    end else begin
      if (cf_push) begin
        cf_addr   [cf_wr[C2H_CF_AW-1:0]] <= dsc_bypass_c2h_addr;
        cf_qid    [cf_wr[C2H_CF_AW-1:0]] <= dsc_bypass_c2h_qid;
        cf_func   [cf_wr[C2H_CF_AW-1:0]] <= dsc_bypass_c2h_func;
        cf_port_id[cf_wr[C2H_CF_AW-1:0]] <= dsc_bypass_c2h_port_id;
        cf_error  [cf_wr[C2H_CF_AW-1:0]] <= dsc_bypass_c2h_error;
        cf_wr <= cf_wr + 1'b1;
      end
      if (c2h_byp_fire) begin
        cf_rd <= cf_rd + 1'b1;
      end
      case ({c2h_byp_fire, c2h_sts_pulse})
        2'b10:   c2h_outst <= c2h_outst + 1'b1;
        2'b01:   c2h_outst <= (c2h_outst != 4'd0) ? c2h_outst - 1'b1 : 4'd0;
        default: c2h_outst <= c2h_outst;   // both or neither -> net zero
      endcase
    end
  end

  assign cpm_c2h_byp_addr    = cf_addr   [cf_rd[C2H_CF_AW-1:0]];   // FPGA-chosen host address
  assign cpm_c2h_byp_qid     = cf_qid    [cf_rd[C2H_CF_AW-1:0]];
  assign cpm_c2h_byp_func    = cf_func   [cf_rd[C2H_CF_AW-1:0]];
  assign cpm_c2h_byp_port_id = cf_port_id[cf_rd[C2H_CF_AW-1:0]];
  assign cpm_c2h_byp_error   = cf_error  [cf_rd[C2H_CF_AW-1:0]];
  assign cpm_c2h_byp_valid   = ~cf_empty & (c2h_outst == 4'd0);    // one outstanding at a time
  assign cpm_c2h_byp_out_ready = 1'b1;                             // byp_out unused in this mode; discard

  // ---- PR MM descriptor: boundary -> CPM4 (no_dma dropped) ----
  assign cpm_pr_radr     = dsc_pr_radr;
  assign cpm_pr_wadr     = dsc_pr_wadr;
  assign cpm_pr_cidx     = dsc_pr_cidx;
  assign cpm_pr_error    = dsc_pr_error;
  assign cpm_pr_func     = dsc_pr_func;
  assign cpm_pr_len      = dsc_pr_len;
  assign cpm_pr_mrkr_req = dsc_pr_mrkr_req;
  assign cpm_pr_port_id  = dsc_pr_port_id;
  assign cpm_pr_qid      = dsc_pr_qid;
  assign cpm_pr_sdi      = dsc_pr_sdi;
  assign cpm_pr_valid    = dsc_pr_valid;
  assign dsc_pr_ready    = cpm_pr_ready;

  // ---- C2H completion: one CMPT record per packet + synthesized status (CPM4) ----
  // CPM4's axis_c2h_status port does NOT pulse in bypass mode and ST markers kill the data
  // path (both HW-verified). The silicon-validated completion mechanism (mm_st mini design,
  // qdma_stm_c2h_stub + standard qdma-pf driver) is a per-packet CMPT record. The shim
  // generates an 8B standard CMPT after each packet's last data beat; its ACCEPTANCE by the
  // engine (ordered behind the data DMA) is the per-packet completion event driving both the
  // boundary c2h_status pulse (qdma_wr_wrapper's done) and the descriptor-slot semaphore.
  // The record content only needs qid + data_format for the host ring; the driver ignores it.
  reg        cmpt_pend;          // a packet finished data; its CMPT is waiting to be sent
  reg [10:0] cmpt_qid;           // qid of that packet (from ctrl_qid, stable through the packet)
  wire c2h_pkt_last = cpm_c2h_tvalid & cpm_c2h_tready & cpm_c2h_tlast;
  assign c2h_cmpt_fire = cmpt_pend & cpm_c2h_cmpt_tready;

  always @(posedge aclk) begin
    if (!aresetn) begin
      cmpt_pend <= 1'b0;
      cmpt_qid  <= 11'd0;
    end else begin
      if (c2h_pkt_last) begin
        cmpt_pend <= 1'b1;                       // one outstanding packet at a time (semaphore)
        cmpt_qid  <= s_axis_c2h_ctrl_qid[10:0];
      end else if (c2h_cmpt_fire) begin
        cmpt_pend <= 1'b0;
      end
    end
  end

  // 8B standard-format CMPT: bit0 data_format=0, bits[11:1] qid, upper bits unused (zeros).
  wire [127:0] cmpt_rec = {116'b0, cmpt_qid, 1'b0};
  assign cpm_c2h_cmpt_data   = cmpt_rec;
  assign cpm_c2h_cmpt_size   = 2'b00;            // 8B record
  assign cpm_c2h_cmpt_tlast  = 1'b1;             // single-beat record
  assign cpm_c2h_cmpt_tvalid = cmpt_pend;
  // Odd parity per 32-bit word across the beat (unused upper words are zero -> parity 1)
  genvar gp;
  generate
    for (gp = 0; gp < 4; gp = gp + 1) begin : g_cmpt_dpar
      assign cpm_c2h_cmpt_dpar[gp] = ~(^cmpt_rec[gp*32 +: 32]);
    end
  endgenerate
  assign cpm_c2h_cmpt_dpar[15:4] = 12'hFFF;

  // Boundary status pulse on CMPT acceptance
  assign c2h_status_valid      = c2h_cmpt_fire;
  assign c2h_status_qid        = {1'b0, cmpt_qid};
  assign c2h_status_drop       = 1'b0;
  assign c2h_status_error      = 1'b0;
  assign c2h_status_last       = 1'b0;   // unused by qdma_wr_wrapper
  assign c2h_status_status_cmp = 1'b0;   // unused by qdma_wr_wrapper

  // ---- H2C completion: CPM4 dma0_h2c_byp_out (marker response) -> boundary eqdma_qsts ----
  // Coyote's qdma_rd_wrapper flags H2C done on (op==8'h1 && !data[16]), citing PG302 v5.0
  // Table 77 (op=0x1 => H2C-ST) and Table 79 (data[16] => error). In CPM4 QDMA ST
  // descriptor-bypass, every descriptor is submitted with mrkr_req=1 (SOP=EOP), so the H2C
  // engine echoes a marker response on dma0_h2c_byp_out (mrkr_rsp) per completed descriptor.
  // That echo is the fabric-facing completion; map it into the eQDMA qsts fields:
  assign h2c_status_vld     = cpm_h2c_byp_valid & cpm_h2c_byp_mrkr_rsp;
  assign cpm_h2c_byp_ready  = 1'b1;                              // Coyote ties qsts rdy high; always accept
  assign h2c_status_op      = 8'h1;                              // H2C-ST (PG302 Table 77)
  assign h2c_status_data    = {47'b0, cpm_h2c_byp_error, 16'b0}; // data[16] = error (PG302 Table 79)
  assign h2c_status_qid     = cpm_h2c_byp_qid;
  assign h2c_status_port_id = cpm_h2c_byp_port_id;

endmodule
