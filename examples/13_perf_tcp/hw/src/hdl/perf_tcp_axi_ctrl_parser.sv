/**
 * This file is part of Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025-2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import lynxTypes::*;

/**
 * perf_tcp_axi_ctrl_parser
 * @brief AXI-Lite register file for the TCP performance benchmark.
 *
 * @note Only used by the client; the server doesn't require any
 * memory-mapped registers, as the connection management is handled
 * in the shell through the software.
 *
 * Register map 
 *   0  (WR)  : start_client — bit[0] starts the client FSM; auto-cleared when FSM leaves idle
 *   1  (WR)  : n_sessions   — number of TCP sessions [15:0]
 *   2  (WR)  : pkg_word_count — payload words per packet [31:0]; payload = PKG_WORD_COUNT * 64 B
 *   3  (WR)  : session_id   — write one SW-opened session ID [15:0] per write;
 *                             each write enqueues one session ID for the client kernel
 *   4  (WR)  : clk_freq     — design clock frequency in Hz [31:0]
 *   5  (WR)  : duration     — benchmark duration in seconds [31:0]
 *   6  (RO)  : client_state — current FSM state of the client HLS kernel [3:0]
 *
 * TCP connections are opened and closed exclusively by host software via
 * cThread::openConnTcp() / closeConnTcp(). The session IDs returned by those
 * calls are injected into the client kernel through register 3.
 */
module perf_tcp_axi_ctrl_parser (
  input  logic                        aclk,
  input  logic                        aresetn,
  AXI4L.s                             axi_ctrl,

  output logic                        start_client,
  output logic [15:0]                 n_sessions,
  output logic [31:0]                 pkg_word_count,
  output logic [31:0]                 clk_freq,
  output logic [31:0]                 duration,
  input  logic [3:0]                  client_state,

  output logic                        sess_id_valid,
  output logic [15:0]                 sess_id_data,
  input  logic                        sess_id_ready
);

/////////////////////////////////////
//          CONSTANTS             //
///////////////////////////////////
localparam integer N_REGS    = 7;
localparam integer ADDR_MSB  = $clog2(N_REGS);
localparam integer ADDR_LSB  = $clog2(AXIL_DATA_BITS/8);
localparam integer AXI_ADDR_BITS = ADDR_LSB + ADDR_MSB;

// Registers for holding the values read from/to be written to the AXI Lite interface
logic [N_REGS-1:0][AXIL_DATA_BITS-1:0] ctrl_reg;
logic ctrl_reg_rden;
logic ctrl_reg_wren;

/////////////////////////////////////
//         REGISTER MAP           //
///////////////////////////////////
localparam int START_CLIENT   = 0;
localparam int N_SESSIONS     = 1;
localparam int PKG_WORD_COUNT = 2;
localparam int SESSION_ID     = 3;
localparam int CLK_FREQ       = 4;
localparam int DURATION       = 5;
localparam int CLIENT_STATE   = 6;

/////////////////////////////////////
//   SESSION-ID INJECTION LOGIC   //
///////////////////////////////////
// Latch session_id written to reg 3 and hold it until the kernel accepts it.
// AXI-Lite transactions are many cycles apart, so a 1-entry pending register
// is sufficient (kernel drains it within a few cycles via its internal FIFO).
logic        sess_id_pending;
logic [15:0] sess_id_pending_data;

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        sess_id_pending      <= 1'b0;
        sess_id_pending_data <= '0;
    end else begin
        if (ctrl_reg_wren && (axi_awaddr[ADDR_LSB+:ADDR_MSB] == SESSION_ID)
                && axi_ctrl.wstrb[0] && axi_ctrl.wstrb[1]) begin
            sess_id_pending      <= 1'b1;
            sess_id_pending_data <= axi_ctrl.wdata[15:0];
        end else if (sess_id_valid && sess_id_ready) begin
            sess_id_pending <= 1'b0;
        end
    end
end

assign sess_id_valid = sess_id_pending;
assign sess_id_data  = sess_id_pending_data;

/////////////////////////////////////
//          REGISTERS             //
///////////////////////////////////
logic [AXI_ADDR_BITS-1:0] axi_awaddr;
logic axi_awready;
logic [AXI_ADDR_BITS-1:0] axi_araddr;
logic axi_arready;
logic [1:0] axi_bresp;
logic axi_bvalid;
logic axi_wready;
logic [AXIL_DATA_BITS-1:0] axi_rdata;
logic [1:0] axi_rresp;
logic axi_rvalid;
logic aw_en;


/////////////////////////////////////
//         WRITE PROCESS          //
///////////////////////////////////
assign ctrl_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        ctrl_reg <= 0;
    end else begin
        // Auto-clear start_client once the client FSM leaves idle
        if (client_state != 0) ctrl_reg[START_CLIENT] <= '0;

        if (ctrl_reg_wren) begin
            case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
                START_CLIENT:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if (axi_ctrl.wstrb[i]) begin
                    ctrl_reg[START_CLIENT][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end
                N_SESSIONS:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if(axi_ctrl.wstrb[i]) begin
                    ctrl_reg[N_SESSIONS][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end
                PKG_WORD_COUNT:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if(axi_ctrl.wstrb[i]) begin
                    ctrl_reg[PKG_WORD_COUNT][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end
                // SESSION_ID (reg 3) is handled by the injection logic above; no ctrl_reg storage needed.
                CLK_FREQ:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if(axi_ctrl.wstrb[i]) begin
                    ctrl_reg[CLK_FREQ][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end
                DURATION:
                for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                    if(axi_ctrl.wstrb[i]) begin
                    ctrl_reg[DURATION][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
                    end
                end
                default: ;
            endcase
        end
    end
end

assign ctrl_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;

/////////////////////////////////////
//         READ PROCESS           //
///////////////////////////////////
always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        axi_rdata <= 0;
    end else begin
        if (ctrl_reg_rden) begin
            axi_rdata <= 0;
            case (axi_araddr[ADDR_LSB+:ADDR_MSB])
                CLIENT_STATE:
                    axi_rdata[31:0] <= client_state;
                default: ;
            endcase
        end
    end
end


/////////////////////////////////////
//       OUTPUT ASSIGNMENT        //
///////////////////////////////////
always_comb begin
    start_client    = ctrl_reg[START_CLIENT][0];
    n_sessions      = ctrl_reg[N_SESSIONS][15:0];
    pkg_word_count  = ctrl_reg[PKG_WORD_COUNT][31:0];
    clk_freq        = ctrl_reg[CLK_FREQ][31:0];
    duration        = ctrl_reg[DURATION][31:0];
end

/////////////////////////////////////
//     STANDARD AXI CONTROL       //
///////////////////////////////////
// NOT TO BE EDITED

// I/O
assign axi_ctrl.awready = axi_awready;
assign axi_ctrl.arready = axi_arready;
assign axi_ctrl.bresp = axi_bresp;
assign axi_ctrl.bvalid = axi_bvalid;
assign axi_ctrl.wready = axi_wready;
assign axi_ctrl.rdata = axi_rdata;
assign axi_ctrl.rresp = axi_rresp;
assign axi_ctrl.rvalid = axi_rvalid;

// awready and awaddr
always_ff @(posedge aclk) begin
    if ( aresetn == 1'b0 )
    begin
        axi_awready <= 1'b0;
        axi_awaddr <= 0;
        aw_en <= 1'b1;
    end
    else
    begin
        if (~axi_awready && axi_ctrl.awvalid && axi_ctrl.wvalid && aw_en)
        begin
            axi_awready <= 1'b1;
            aw_en <= 1'b0;
            axi_awaddr <= axi_ctrl.awaddr;
        end
        else if (axi_ctrl.bready && axi_bvalid)
        begin
            aw_en <= 1'b1;
            axi_awready <= 1'b0;
        end
        else
        begin
            axi_awready <= 1'b0;
        end
    end
end

// arready and araddr
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_arready <= 1'b0;
      axi_araddr  <= 0;
    end
  else
    begin
      if (~axi_arready && axi_ctrl.arvalid)
        begin
          axi_arready <= 1'b1;
          axi_araddr  <= axi_ctrl.araddr;
        end
      else
        begin
          axi_arready <= 1'b0;
        end
    end
end

// bvalid and bresp
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_bvalid  <= 0;
      axi_bresp   <= 2'b0;
    end
  else
    begin
      if (axi_awready && axi_ctrl.awvalid && ~axi_bvalid && axi_wready && axi_ctrl.wvalid)
        begin
          axi_bvalid <= 1'b1;
          axi_bresp  <= 2'b0;
        end
      else
        begin
          if (axi_ctrl.bready && axi_bvalid)
            begin
              axi_bvalid <= 1'b0;
            end
        end
    end
end

// wready
always_ff @(posedge aclk) begin
  if (aresetn == 1'b0 )
    begin
      axi_wready <= 1'b0;
    end
  else
    begin
      if (~axi_wready && axi_ctrl.wvalid && axi_ctrl.awvalid && aw_en )
        begin
          axi_wready <= 1'b1;
        end
      else
        begin
          axi_wready <= 1'b0;
        end
    end
end

// rvalid and rresp
always_ff @(posedge aclk) begin
  if ( aresetn == 1'b0 )
    begin
      axi_rvalid <= 0;
      axi_rresp  <= 0;
    end
  else
    begin
      if (axi_arready && axi_ctrl.arvalid && ~axi_rvalid)
        begin
          axi_rvalid <= 1'b1;
          axi_rresp  <= 2'b0;
        end
      else if (axi_rvalid && axi_ctrl.rready)
        begin
          axi_rvalid <= 1'b0;
        end
    end
end

endmodule
