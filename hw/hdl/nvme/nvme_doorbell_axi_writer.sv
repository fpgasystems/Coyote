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
 * @brief Convert one Coyote doorbell DMA request into an AXI4 MMIO write.
 *
 * Doorbell producers present the address and the data on separate dmaIntf and
 * AXI4-Stream handshakes. This adapter serializes them into one 32-bit narrow
 * AXI4 write. All writes use ID zero and retain AW/W order; B responses may
 * trail up to MAX_OUTSTANDING accepted requests without stalling each write.
 */
module nvme_doorbell_axi_writer #(
    parameter int unsigned MAX_OUTSTANDING = 8
) (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        setup_done,
    output logic        idle, // No buffered request, partial AW/W, or pending B.

    dmaIntf.s           s_dma_req,
    AXI4S.s             s_axis_data,
    AXI4.m              m_axi_mmio
);

    localparam int unsigned AXI_BYTE_LANES = AXI_DATA_BITS / 8;
    localparam int unsigned AXI_LANE_BITS  = $clog2(AXI_BYTE_LANES);
    localparam int unsigned COUNT_BITS = $clog2(MAX_OUTSTANDING + 1);
    // Reserve a credit at request acceptance, before either AXI channel issues.
    logic [COUNT_BITS-1:0] outstanding;
    wire accept_req = s_dma_req.valid && s_dma_req.ready;
    wire accept_b = m_axi_mmio.bvalid && m_axi_mmio.bready;

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_WAIT_DATA,
        ST_SEND_WRITE
    } state_t;

    state_t state;

    logic [63:0]                    address_reg;
    logic [AXI_DATA_BITS-1:0]       write_data_reg;
    logic [AXI_BYTE_LANES-1:0]      write_strobe_reg;
    logic                           aw_pending;
    logic                           w_pending;
    assign idle = (state == ST_IDLE) && (outstanding == 0);

    always_comb begin
        s_dma_req.ready = 1'b0;
        s_dma_req.rsp   = '0;
        s_axis_data.tready = 1'b0;

        m_axi_mmio.awaddr   = address_reg;
        m_axi_mmio.awburst  = 2'b01;
        m_axi_mmio.awcache  = 4'b0000;
        m_axi_mmio.awid     = '0;
        m_axi_mmio.awlen    = 8'd0;
        m_axi_mmio.awlock   = 1'b0;
        m_axi_mmio.awprot   = 3'b000;
        m_axi_mmio.awqos    = 4'b0000;
        m_axi_mmio.awregion = 4'b0000;
        m_axi_mmio.awsize   = 3'd2;
        m_axi_mmio.awvalid  = 1'b0;

        m_axi_mmio.wdata    = write_data_reg;
        m_axi_mmio.wlast    = 1'b1;
        m_axi_mmio.wstrb    = write_strobe_reg;
        m_axi_mmio.wvalid   = 1'b0;

        m_axi_mmio.bready   = aresetn && (outstanding != 0);

        // This adapter only emits writes.
        m_axi_mmio.araddr   = '0;
        m_axi_mmio.arburst  = 2'b01;
        m_axi_mmio.arcache  = 4'b0000;
        m_axi_mmio.arid     = '0;
        m_axi_mmio.arlen    = 8'd0;
        m_axi_mmio.arlock   = 1'b0;
        m_axi_mmio.arprot   = 3'b000;
        m_axi_mmio.arqos    = 4'b0000;
        m_axi_mmio.arregion = 4'b0000;
        m_axi_mmio.arsize   = 3'd0;
        m_axi_mmio.arvalid  = 1'b0;
        m_axi_mmio.rready   = 1'b0;

        case (state)
            ST_IDLE: begin
                // Do not even accept a doorbell until the PL root complex has
                // enumerated and initialized the NVMe controller and queues.
                s_dma_req.ready = aresetn && setup_done && (outstanding < MAX_OUTSTANDING);
            end

            ST_WAIT_DATA: begin
                s_axis_data.tready = 1'b1;
            end

            ST_SEND_WRITE: begin
                m_axi_mmio.awvalid = aw_pending;
                m_axi_mmio.wvalid  = w_pending;
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state            <= ST_IDLE;
            address_reg      <= '0;
            write_data_reg   <= '0;
            write_strobe_reg <= '0;
            aw_pending       <= 1'b0;
            w_pending        <= 1'b0;
            outstanding      <= '0;
        end else begin
            case ({accept_req, accept_b})
                2'b10: outstanding <= outstanding + 1'b1;
                2'b01: outstanding <= outstanding - 1'b1;
                default: ;
            endcase
            case (state)
                ST_IDLE: begin
                    aw_pending <= 1'b0;
                    w_pending  <= 1'b0;

                    if (s_dma_req.valid && s_dma_req.ready) begin
                        address_reg <=
                            {{(64-PADDR_BITS){1'b0}}, s_dma_req.req.paddr};
                        state       <= ST_WAIT_DATA;
                    end
                end

                ST_WAIT_DATA: begin
                    if (s_axis_data.tvalid && s_axis_data.tready) begin
                        // AXI narrow writes place bytes in the lanes selected
                        // by AWADDR. The legacy DMA stream always puts the
                        // 32-bit doorbell value in its lowest four bytes.
                        write_data_reg <=
                            {{(AXI_DATA_BITS-32){1'b0}},
                             s_axis_data.tdata[31:0]}
                            << (address_reg[AXI_LANE_BITS-1:0] * 8);
                        write_strobe_reg <=
                            {{(AXI_BYTE_LANES-4){1'b0}}, 4'hf}
                            << address_reg[AXI_LANE_BITS-1:0];
                        aw_pending <= 1'b1;
                        w_pending  <= 1'b1;
                        state      <= ST_SEND_WRITE;
                    end
                end

                ST_SEND_WRITE: begin
                    if (m_axi_mmio.awvalid && m_axi_mmio.awready)
                        aw_pending <= 1'b0;
                    if (m_axi_mmio.wvalid && m_axi_mmio.wready)
                        w_pending <= 1'b0;

                    if ((!aw_pending || m_axi_mmio.awready) &&
                        (!w_pending  || m_axi_mmio.wready))
                        state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    initial assert (MAX_OUTSTANDING > 0)
        else $fatal(1, "nvme_doorbell_axi_writer: at least one credit is required");
    always_ff @(posedge aclk) begin
        if (aresetn && s_dma_req.valid && s_dma_req.ready) begin
            assert (s_dma_req.req.len == 4)
                else $error("nvme_doorbell_axi_writer: doorbell length must be four bytes");
            assert (s_dma_req.req.paddr[1:0] == 2'b00)
                else $error("nvme_doorbell_axi_writer: doorbell address must be 32-bit aligned");
        end
    end
`endif

endmodule
