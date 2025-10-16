// ==============================================================
// Vivado(TM) HLS - High-Level Synthesis from C, C++ and SystemC v2019.2 (64-bit)
// Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
// ==============================================================
`timescale 1ns/1ps
module user_krnl_control_s_axi
#(parameter
    C_S_AXI_ADDR_WIDTH = 7,
    C_S_AXI_DATA_WIDTH = 32
)(
    input  wire                          ACLK,
    input  wire                          ARESET,
    input  wire                          ACLK_EN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] AWADDR,
    input  wire                          AWVALID,
    output wire                          AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] WDATA,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] WSTRB,
    input  wire                          WVALID,
    output wire                          WREADY,
    output wire [1:0]                    BRESP,
    output wire                          BVALID,
    input  wire                          BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] ARADDR,
    input  wire                          ARVALID,
    output wire                          ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0] RDATA,
    output wire [1:0]                    RRESP,
    output wire                          RVALID,
    input  wire                          RREADY,
    output wire                          interrupt,
    output wire                          ap_start,
    input  wire                          ap_done,
    input  wire                          ap_ready,
    input  wire                          ap_idle,
    output wire [63:0]                   runForCycles,
    output wire [63:0]                   axi00_ptr0,
    output wire [63:0]                   axi01_ptr0,
    output wire [63:0]                   axi02_ptr0,
    output wire [63:0]                   axi03_ptr0
);
//------------------------Address Info-------------------
// 0x00 : Control signals
//        bit 0  - ap_start (Read/Write/COH)
//        bit 1  - ap_done (Read/COR)
//        bit 2  - ap_idle (Read)
//        bit 3  - ap_ready (Read)
//        bit 7  - auto_restart (Read/Write)
//        others - reserved
// 0x04 : Global Interrupt Enable Register
//        bit 0  - Global Interrupt Enable (Read/Write)
//        others - reserved
// 0x08 : IP Interrupt Enable Register (Read/Write)
//        bit 0  - Channel 0 (ap_done)
//        bit 1  - Channel 1 (ap_ready)
//        others - reserved
// 0x0c : IP Interrupt Status Register (Read/TOW)
//        bit 0  - Channel 0 (ap_done)
//        bit 1  - Channel 1 (ap_ready)
//        others - reserved
// 0x10 : Data signal of runForCycles
//        bit 31~0 - runForCycles[31:0] (Read/Write)
// 0x14 : Data signal of runForCycles
//        bit 31~0 - runForCycles[63:32] (Read/Write)
// 0x18 : reserved
// 0x1c : Data signal of axi00_ptr0
//        bit 31~0 - axi00_ptr0[31:0] (Read/Write)
// 0x20 : Data signal of axi00_ptr0
//        bit 31~0 - axi00_ptr0[63:32] (Read/Write)
// 0x24 : reserved
// 0x28 : Data signal of axi01_ptr0
//        bit 31~0 - axi01_ptr0[31:0] (Read/Write)
// 0x2c : Data signal of axi01_ptr0
//        bit 31~0 - axi01_ptr0[63:32] (Read/Write)
// 0x30 : reserved
// 0x34 : Data signal of axi02_ptr0
//        bit 31~0 - axi02_ptr0[31:0] (Read/Write)
// 0x38 : Data signal of axi02_ptr0
//        bit 31~0 - axi02_ptr0[63:32] (Read/Write)
// 0x3c : reserved
// 0x40 : Data signal of axi03_ptr0
//        bit 31~0 - axi03_ptr0[31:0] (Read/Write)
// 0x44 : Data signal of axi03_ptr0
//        bit 31~0 - axi03_ptr0[63:32] (Read/Write)
// 0x48 : reserved
// (SC = Self Clear, COR = Clear on Read, TOW = Toggle on Write, COH = Clear on Handshake)

//------------------------Parameter----------------------
localparam
    ADDR_AP_CTRL             = 7'h00,
    ADDR_GIE                 = 7'h04,
    ADDR_IER                 = 7'h08,
    ADDR_ISR                 = 7'h0c,
    ADDR_RUNFORCYCLES_DATA_0 = 7'h10,
    ADDR_RUNFORCYCLES_DATA_1 = 7'h14,
    ADDR_RUNFORCYCLES_CTRL   = 7'h18,
    ADDR_AXI00_PTR0_DATA_0   = 7'h1c,
    ADDR_AXI00_PTR0_DATA_1   = 7'h20,
    ADDR_AXI00_PTR0_CTRL     = 7'h24,
    ADDR_AXI01_PTR0_DATA_0   = 7'h28,
    ADDR_AXI01_PTR0_DATA_1   = 7'h2c,
    ADDR_AXI01_PTR0_CTRL     = 7'h30,
    ADDR_AXI02_PTR0_DATA_0   = 7'h34,
    ADDR_AXI02_PTR0_DATA_1   = 7'h38,
    ADDR_AXI02_PTR0_CTRL     = 7'h3c,
    ADDR_AXI03_PTR0_DATA_0   = 7'h40,
    ADDR_AXI03_PTR0_DATA_1   = 7'h44,
    ADDR_AXI03_PTR0_CTRL     = 7'h48,
    WRIDLE                   = 2'd0,
    WRDATA                   = 2'd1,
    WRRESP                   = 2'd2,
    WRRESET                  = 2'd3,
    RDIDLE                   = 2'd0,
    RDDATA                   = 2'd1,
    RDRESET                  = 2'd2,
    ADDR_BITS         = 7;


//------------------------Local signal-------------------
    reg  [1:0]                    wstate = WRRESET;
    reg  [1:0]                    wnext;
    reg  [ADDR_BITS-1:0]          waddr;
    wire [31:0]                   wmask;
    wire                          aw_hs;
    wire                          w_hs;
    reg  [1:0]                    rstate = RDRESET;
    reg  [1:0]                    rnext;
    reg  [31:0]                   rdata;
    wire                          ar_hs;
    wire [ADDR_BITS-1:0]          raddr;
    // internal registers
    reg                           int_ap_idle;
    reg                           int_ap_ready;
    reg                           int_ap_done = 1'b0;
    reg                           int_ap_start = 1'b0;
    reg                           int_auto_restart = 1'b0;
    reg                           int_gie = 1'b0;
    reg  [1:0]                    int_ier = 2'b0;
    reg  [1:0]                    int_isr = 2'b0;
    reg  [63:0]                   int_runForCycles = 'b0;
    reg  [63:0]                   int_axi00_ptr0 = 'b0;
    reg  [63:0]                   int_axi01_ptr0 = 'b0;
    reg  [63:0]                   int_axi02_ptr0 = 'b0;
    reg  [63:0]                   int_axi03_ptr0 = 'b0;

//------------------------Instantiation------------------

//------------------------AXI write fsm------------------
assign AWREADY = (wstate == WRIDLE);
assign WREADY  = (wstate == WRDATA);
assign BRESP   = 2'b00;  // OKAY
assign BVALID  = (wstate == WRRESP);
assign wmask   = { {8{WSTRB[3]}}, {8{WSTRB[2]}}, {8{WSTRB[1]}}, {8{WSTRB[0]}} };
assign aw_hs   = AWVALID & AWREADY;
assign w_hs    = WVALID & WREADY;

// wstate
always @(posedge ACLK) begin
    if (ARESET)
        wstate <= WRRESET;
    else if (ACLK_EN)
        wstate <= wnext;
end

// wnext
always @(*) begin
    case (wstate)
        WRIDLE:
            if (AWVALID)
                wnext = WRDATA;
            else
                wnext = WRIDLE;
        WRDATA:
            if (WVALID)
                wnext = WRRESP;
            else
                wnext = WRDATA;
        WRRESP:
            if (BREADY)
                wnext = WRIDLE;
            else
                wnext = WRRESP;
        default:
            wnext = WRIDLE;
    endcase
end

// waddr
always @(posedge ACLK) begin
    if (ACLK_EN) begin
        if (aw_hs)
            waddr <= AWADDR[ADDR_BITS-1:0];
    end
end

//------------------------AXI read fsm-------------------
assign ARREADY = (rstate == RDIDLE);
assign RDATA   = rdata;
assign RRESP   = 2'b00;  // OKAY
assign RVALID  = (rstate == RDDATA);
assign ar_hs   = ARVALID & ARREADY;
assign raddr   = ARADDR[ADDR_BITS-1:0];

// rstate
always @(posedge ACLK) begin
    if (ARESET)
        rstate <= RDRESET;
    else if (ACLK_EN)
        rstate <= rnext;
end

// rnext
always @(*) begin
    case (rstate)
        RDIDLE:
            if (ARVALID)
                rnext = RDDATA;
            else
                rnext = RDIDLE;
        RDDATA:
            if (RREADY & RVALID)
                rnext = RDIDLE;
            else
                rnext = RDDATA;
        default:
            rnext = RDIDLE;
    endcase
end

// rdata
always @(posedge ACLK) begin
    if (ACLK_EN) begin
        if (ar_hs) begin
            rdata <= 1'b0;
            case (raddr)
                ADDR_AP_CTRL: begin
                    rdata[0] <= int_ap_start;
                    rdata[1] <= int_ap_done;
                    rdata[2] <= int_ap_idle;
                    rdata[3] <= int_ap_ready;
                    rdata[7] <= int_auto_restart;
                end
                ADDR_GIE: begin
                    rdata <= int_gie;
                end
                ADDR_IER: begin
                    rdata <= int_ier;
                end
                ADDR_ISR: begin
                    rdata <= int_isr;
                end
                ADDR_RUNFORCYCLES_DATA_0: begin
                    rdata <= int_runForCycles[31:0];
                end
                ADDR_RUNFORCYCLES_DATA_1: begin
                    rdata <= int_runForCycles[63:32];
                end
                ADDR_AXI00_PTR0_DATA_0: begin
                    rdata <= int_axi00_ptr0[31:0];
                end
                ADDR_AXI00_PTR0_DATA_1: begin
                    rdata <= int_axi00_ptr0[63:32];
                end
                ADDR_AXI01_PTR0_DATA_0: begin
                    rdata <= int_axi01_ptr0[31:0];
                end
                ADDR_AXI01_PTR0_DATA_1: begin
                    rdata <= int_axi01_ptr0[63:32];
                end
                ADDR_AXI02_PTR0_DATA_0: begin
                    rdata <= int_axi02_ptr0[31:0];
                end
                ADDR_AXI02_PTR0_DATA_1: begin
                    rdata <= int_axi02_ptr0[63:32];
                end
                ADDR_AXI03_PTR0_DATA_0: begin
                    rdata <= int_axi03_ptr0[31:0];
                end
                ADDR_AXI03_PTR0_DATA_1: begin
                    rdata <= int_axi03_ptr0[63:32];
                end
            endcase
        end
    end
end


//------------------------Register logic-----------------
assign interrupt    = int_gie & (|int_isr);
assign ap_start     = int_ap_start;
assign runForCycles = int_runForCycles;
assign axi00_ptr0   = int_axi00_ptr0;
assign axi01_ptr0   = int_axi01_ptr0;
assign axi02_ptr0   = int_axi02_ptr0;
assign axi03_ptr0   = int_axi03_ptr0;

// int_ap_start
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_start <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AP_CTRL && WSTRB[0] && WDATA[0])
            int_ap_start <= 1'b1;
        else if (ap_ready)
            int_ap_start <= int_auto_restart; // clear on handshake/auto restart
    end
end

// int_ap_done
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_done <= 1'b0;
    else if (ACLK_EN) begin
        if (ap_done)
            int_ap_done <= 1'b1;
        else if (ar_hs && raddr == ADDR_AP_CTRL)
            int_ap_done <= 1'b0; // clear on read
    end
end

// int_ap_idle
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_idle <= 1'b0;
    else if (ACLK_EN) begin
            int_ap_idle <= ap_idle;
    end
end

// int_ap_ready
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_ready <= 1'b0;
    else if (ACLK_EN) begin
            int_ap_ready <= ap_ready;
    end
end

// int_auto_restart
always @(posedge ACLK) begin
    if (ARESET)
        int_auto_restart <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AP_CTRL && WSTRB[0])
            int_auto_restart <=  WDATA[7];
    end
end

// int_gie
always @(posedge ACLK) begin
    if (ARESET)
        int_gie <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_GIE && WSTRB[0])
            int_gie <= WDATA[0];
    end
end

// int_ier
always @(posedge ACLK) begin
    if (ARESET)
        int_ier <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_IER && WSTRB[0])
            int_ier <= WDATA[1:0];
    end
end

// int_isr[0]
always @(posedge ACLK) begin
    if (ARESET)
        int_isr[0] <= 1'b0;
    else if (ACLK_EN) begin
        if (int_ier[0] & ap_done)
            int_isr[0] <= 1'b1;
        else if (w_hs && waddr == ADDR_ISR && WSTRB[0])
            int_isr[0] <= int_isr[0] ^ WDATA[0]; // toggle on write
    end
end

// int_isr[1]
always @(posedge ACLK) begin
    if (ARESET)
        int_isr[1] <= 1'b0;
    else if (ACLK_EN) begin
        if (int_ier[1] & ap_ready)
            int_isr[1] <= 1'b1;
        else if (w_hs && waddr == ADDR_ISR && WSTRB[0])
            int_isr[1] <= int_isr[1] ^ WDATA[1]; // toggle on write
    end
end

// int_runForCycles[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_runForCycles[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_RUNFORCYCLES_DATA_0)
            int_runForCycles[31:0] <= (WDATA[31:0] & wmask) | (int_runForCycles[31:0] & ~wmask);
    end
end

// int_runForCycles[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_runForCycles[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_RUNFORCYCLES_DATA_1)
            int_runForCycles[63:32] <= (WDATA[31:0] & wmask) | (int_runForCycles[63:32] & ~wmask);
    end
end

// int_axi00_ptr0[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_axi00_ptr0[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AXI00_PTR0_DATA_0)
            int_axi00_ptr0[31:0] <= (WDATA[31:0] & wmask) | (int_axi00_ptr0[31:0] & ~wmask);
    end
end

// int_axi00_ptr0[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_axi00_ptr0[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AXI00_PTR0_DATA_1)
            int_axi00_ptr0[63:32] <= (WDATA[31:0] & wmask) | (int_axi00_ptr0[63:32] & ~wmask);
    end
end

// int_axi01_ptr0[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_axi01_ptr0[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AXI01_PTR0_DATA_0)
            int_axi01_ptr0[31:0] <= (WDATA[31:0] & wmask) | (int_axi01_ptr0[31:0] & ~wmask);
    end
end

// int_axi01_ptr0[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_axi01_ptr0[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AXI01_PTR0_DATA_1)
            int_axi01_ptr0[63:32] <= (WDATA[31:0] & wmask) | (int_axi01_ptr0[63:32] & ~wmask);
    end
end

// int_axi02_ptr0[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_axi02_ptr0[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AXI02_PTR0_DATA_0)
            int_axi02_ptr0[31:0] <= (WDATA[31:0] & wmask) | (int_axi02_ptr0[31:0] & ~wmask);
    end
end

// int_axi02_ptr0[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_axi02_ptr0[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AXI02_PTR0_DATA_1)
            int_axi02_ptr0[63:32] <= (WDATA[31:0] & wmask) | (int_axi02_ptr0[63:32] & ~wmask);
    end
end

// int_axi03_ptr0[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_axi03_ptr0[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AXI03_PTR0_DATA_0)
            int_axi03_ptr0[31:0] <= (WDATA[31:0] & wmask) | (int_axi03_ptr0[31:0] & ~wmask);
    end
end

// int_axi03_ptr0[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_axi03_ptr0[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AXI03_PTR0_DATA_1)
            int_axi03_ptr0[63:32] <= (WDATA[31:0] & wmask) | (int_axi03_ptr0[63:32] & ~wmask);
    end
end

// int_axi02_ptr0[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_axi02_ptr0[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AXI02_PTR0_DATA_0)
            int_axi02_ptr0[31:0] <= (WDATA[31:0] & wmask) | (int_axi02_ptr0[31:0] & ~wmask);
    end
end

// int_axi02_ptr0[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_axi02_ptr0[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AXI02_PTR0_DATA_1)
            int_axi02_ptr0[63:32] <= (WDATA[31:0] & wmask) | (int_axi02_ptr0[63:32] & ~wmask);
    end
end

// int_axi03_ptr0[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_axi03_ptr0[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AXI03_PTR0_DATA_0)
            int_axi03_ptr0[31:0] <= (WDATA[31:0] & wmask) | (int_axi03_ptr0[31:0] & ~wmask);
    end
end

// int_axi03_ptr0[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_axi03_ptr0[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AXI03_PTR0_DATA_1)
            int_axi03_ptr0[63:32] <= (WDATA[31:0] & wmask) | (int_axi03_ptr0[63:32] & ~wmask);
    end
end


//------------------------Memory logic-------------------

endmodule
