/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */


`timescale 1ns/1ps

import lynxTypes::*;

/**
 * @brief   NVMe config slave
 *
 * AXI-Lite register bank: device/queue setup, permissions, and the FPGA BAR base.
 */
module nvme_cnfg_slave (
    input  logic                    aclk,
    input  logic                    aresetn,

    AXI4L.s                         s_nvme_cnfg,

    metaIntf.m                      m_update_tbl,
    metaIntf.m                      m_perm_update,

    output logic [63:0]             fpga_bar_base
    );

    // Constants
    localparam integer N_REGS = 14;
    localparam integer ADDR_MSB = $clog2(N_REGS);
    localparam integer ADDR_LSB = $clog2(AXIL_DATA_BITS/8);
    localparam integer AXI_ADDR_BITS = ADDR_LSB + ADDR_MSB;

    // Register map (byte offsets: index * 8)
    //   --- Device info registers ---
    //   0x00  FPGA_BAR_BASE_REG
    //   0x08  RSVD0
    //   0x10  DEV_ID
    //   0x18  NSID
    //   0x20  LBAF
    //   0x28  NSZE
    //   0x30  DOORBELL_BASE
    //   0x38  VALID_NVME_INFO   (W1S trigger: bit0=valid, bit1=reset_queue)
    //   --- Permission registers ---
    //   0x40  PERM_REGION_ID
    //   0x48  PERM_DEV_ID
    //   0x50  PERM_LBA_OFFSET
    //   0x58  PERM_LBA_SIZE
    //   0x60  PERM_VALID        (W1S trigger: bit0=write to perm table)
    localparam int unsigned FPGA_BAR_BASE_REG   = 0;
    localparam int unsigned RSVD0               = 1;
    localparam int unsigned DEV_ID              = 2;
    localparam int unsigned NSID                = 3;
    localparam int unsigned LBAF                = 4;
    localparam int unsigned NSZE                = 5;
    localparam int unsigned DOORBELL_BASE       = 6;
    localparam int unsigned VALID_NVME_INFO     = 7;
    localparam int unsigned PERM_REGION_ID      = 8;
    localparam int unsigned PERM_DEV_ID         = 9;
    localparam int unsigned PERM_LBA_OFFSET     = 10;
    localparam int unsigned PERM_LBA_SIZE       = 11;
    localparam int unsigned PERM_VALID          = 12;

    // Registers
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

    logic [N_REGS-1:0][AXIL_DATA_BITS-1:0] ctrl_reg;
    logic ctrl_reg_wren, ctrl_reg_rden;

    // Write process
    assign ctrl_reg_wren = axi_wready && s_nvme_cnfg.wvalid && axi_awready && s_nvme_cnfg.awvalid;

    always_ff @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            ctrl_reg           <= '0;
            m_update_tbl.valid <= 1'b0;
            m_update_tbl.data  <= '0;
            m_perm_update.valid <= 1'b0;
            m_perm_update.data  <= '0;
        end
        else begin
            // Clear valid when handshake completes
            if (m_update_tbl.valid && m_update_tbl.ready) begin
                m_update_tbl.valid <= 1'b0;
            end
            if (m_perm_update.valid && m_perm_update.ready) begin
                m_perm_update.valid <= 1'b0;
            end

            if (ctrl_reg_wren) begin
                case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
                    FPGA_BAR_BASE_REG,
                    RSVD0,
                    DEV_ID,
                    NSID,
                    LBAF,
                    NSZE,
                    DOORBELL_BASE,
                    PERM_REGION_ID,
                    PERM_DEV_ID,
                    PERM_LBA_OFFSET,
                    PERM_LBA_SIZE: begin
                        for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                            if (s_nvme_cnfg.wstrb[i]) begin
                                ctrl_reg[axi_awaddr[ADDR_LSB+:ADDR_MSB]][(i*8)+:8] <= s_nvme_cnfg.wdata[(i*8)+:8];
                            end
                        end
                    end

                    VALID_NVME_INFO: begin
                        for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                            if (s_nvme_cnfg.wstrb[i]) begin
                                ctrl_reg[VALID_NVME_INFO][(i*8)+:8] <= s_nvme_cnfg.wdata[(i*8)+:8];
                            end
                        end

                        // Trigger device info update
                        if (s_nvme_cnfg.wdata[0]) begin
                            m_update_tbl.data.dev_id      <= ctrl_reg[DEV_ID][N_NVME_BITS-1:0];
                            m_update_tbl.data.nsid        <= ctrl_reg[NSID][NSID_BITS-1:0];
                            m_update_tbl.data.lbaf        <= ctrl_reg[LBAF][LBAF_BITS-1:0];
                            m_update_tbl.data.nsze        <= ctrl_reg[NSZE][63:0];
                            m_update_tbl.data.sq_db_addr  <= ctrl_reg[DOORBELL_BASE][63:0];
                            m_update_tbl.data.valid       <= 1'b1;
                            m_update_tbl.data.reset_queue <= s_nvme_cnfg.wdata[1];
                            m_update_tbl.valid            <= 1'b1;
                        end
                    end

                    PERM_VALID: begin
                        for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
                            if (s_nvme_cnfg.wstrb[i]) begin
                                ctrl_reg[PERM_VALID][(i*8)+:8] <= s_nvme_cnfg.wdata[(i*8)+:8];
                            end
                        end

                        // Trigger permission update
                        if (s_nvme_cnfg.wdata[0]) begin
                            m_perm_update.data.region_id  <= ctrl_reg[PERM_REGION_ID][REGION_ID_BITS-1:0];
                            m_perm_update.data.dev_id     <= ctrl_reg[PERM_DEV_ID][N_NVME_BITS-1:0];
                            m_perm_update.data.lba_offset <= ctrl_reg[PERM_LBA_OFFSET][63:0];
                            m_perm_update.data.lba_size   <= ctrl_reg[PERM_LBA_SIZE][63:0];
                            m_perm_update.valid           <= 1'b1;
                        end
                    end

                    default: begin
                        // no-op
                    end
                endcase
            end
        end
    end

    // Read process
    assign ctrl_reg_rden = axi_arready & s_nvme_cnfg.arvalid & ~axi_rvalid;

    always_ff @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_rdata <= '0;
        end
        else begin
            axi_rdata <= '0;
            if (ctrl_reg_rden) begin
                if (axi_araddr[ADDR_LSB+:ADDR_MSB] < N_REGS)
                    axi_rdata <= ctrl_reg[axi_araddr[ADDR_LSB+:ADDR_MSB]];
                else
                    axi_rdata <= '0;
            end
        end
    end

    // Output assignment
    always_comb begin
        fpga_bar_base = ctrl_reg[FPGA_BAR_BASE_REG][63:0];
    end

    // Standard AXI-Lite control
    assign s_nvme_cnfg.awready = axi_awready;
    assign s_nvme_cnfg.arready = axi_arready;
    assign s_nvme_cnfg.bresp   = axi_bresp;
    assign s_nvme_cnfg.bvalid  = axi_bvalid;
    assign s_nvme_cnfg.wready  = axi_wready;
    assign s_nvme_cnfg.rdata   = axi_rdata;
    assign s_nvme_cnfg.rresp   = axi_rresp;
    assign s_nvme_cnfg.rvalid  = axi_rvalid;

    // awready and awaddr
    always_ff @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_awready <= 1'b0;
            axi_awaddr  <= '0;
            aw_en       <= 1'b1;
        end
        else begin
            if (~axi_awready && s_nvme_cnfg.awvalid && s_nvme_cnfg.wvalid && aw_en) begin
                axi_awready <= 1'b1;
                aw_en       <= 1'b0;
                axi_awaddr  <= s_nvme_cnfg.awaddr[AXI_ADDR_BITS-1:0];
            end
            else begin
                if (s_nvme_cnfg.bready && axi_bvalid) begin
                    aw_en <= 1'b1;
                end
                axi_awready <= 1'b0;
            end
        end
    end

    // wready
    always_ff @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_wready <= 1'b0;
        end
        else begin
            if (~axi_wready && s_nvme_cnfg.awvalid && s_nvme_cnfg.wvalid && aw_en)
                axi_wready <= 1'b1;
            else
                axi_wready <= 1'b0;
        end
    end

    // bresp
    always_ff @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_bvalid <= 1'b0;
            axi_bresp  <= 2'b0;
        end
        else begin
            if (axi_awready && s_nvme_cnfg.awvalid && ~axi_bvalid && axi_wready && s_nvme_cnfg.wvalid) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b0;
            end
            else begin
                if (s_nvme_cnfg.bready && axi_bvalid)
                    axi_bvalid <= 1'b0;
            end
        end
    end

    // arready and araddr
    always_ff @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_arready <= 1'b0;
            axi_araddr  <= '0;
        end
        else begin
            if (~axi_arready && s_nvme_cnfg.arvalid) begin
                axi_arready <= 1'b1;
                axi_araddr  <= s_nvme_cnfg.araddr[AXI_ADDR_BITS-1:0];
            end
            else begin
                axi_arready <= 1'b0;
            end
        end
    end

    // rvalid and rresp
    always_ff @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b0;
        end
        else begin
            if (axi_arready && s_nvme_cnfg.arvalid && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b0;
            end
            else begin
                if (axi_rvalid && s_nvme_cnfg.rready)
                    axi_rvalid <= 1'b0;
            end
        end
    end

    // ILA Debug
// `define EN_ILA_NVME_CNFG_SLAVE
`ifdef EN_ILA_NVME_CNFG_SLAVE
    ila_nvme_cnfg_slave inst_ila_nvme_cnfg_slave (
        .clk    (aclk),
        // AXI write channel
        .probe0 (s_nvme_cnfg.awvalid),                  // 1
        .probe1 (s_nvme_cnfg.awready),                  // 1
        .probe2 (s_nvme_cnfg.awaddr),                   // AXIL_ADDR_BITS
        .probe3 (s_nvme_cnfg.wvalid),                   // 1
        .probe4 (s_nvme_cnfg.wready),                   // 1
        .probe5 (s_nvme_cnfg.wdata[31:0]),              // 32
        // AXI read channel
        .probe6 (s_nvme_cnfg.arvalid),                  // 1
        .probe7 (s_nvme_cnfg.arready),                  // 1
        // m_update_tbl
        .probe8 (m_update_tbl.valid),                   // 1
        .probe9 (m_update_tbl.ready),                   // 1
        .probe10(m_update_tbl.data.dev_id),             // N_NVME_BITS (4)
        // m_perm_update
        .probe11(m_perm_update.valid),                  // 1
        .probe12(m_perm_update.ready),                  // 1
        .probe13(m_perm_update.data.region_id),         // REGION_ID_BITS
        .probe14(m_perm_update.data.dev_id),            // N_NVME_BITS (4)
        // Internal
        .probe15(ctrl_reg_wren),                        // 1
        .probe16(fpga_bar_base)                         // 64
    );
`endif

endmodule
