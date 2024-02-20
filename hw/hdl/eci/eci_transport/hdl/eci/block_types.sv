/*
    Copyright (c) 2022 ETH Zurich.
    All rights reserved.

    This file is distributed under the terms in the attached LICENSE file.
    If you do not find this file, copies can be found by writing to:
    ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
*/

`ifndef BLOCKTYPES_SV_INCLUDED
`define BLOCKTYPES_SV_INCLUDED

package block_types;


parameter BLOCK_WIDTH   = 512;


parameter       TX_ST_BIT   = 6'd51;
parameter       TX_END_BIT  = 6'd44;
parameter       RX_ST_BIT   = 6'd43;
parameter       RX_END_BIT  = 6'd36;
parameter       ACK_BIT     = 6'd60;
parameter       RTRY_BIT    = 6'd53;
parameter       REQ_BIT     = 6'd52;
parameter       CRED_ST_BIT = 6'd59;
parameter       CRED_ND_BIT = 6'd52;

/* Number of 64-bit data words in the blocks */
parameter NUM_BLOCK_DATA_WORDS      = 7;
parameter NUM_BLOCK_DATA_WORDS_BITS = 3;

/* Size of the CRC in bits */
parameter BLOCK_CRC_BITS   = 24;

/**/
parameter CD_LINK_CREDITS  = 32;
parameter MD_LINK_CREDITS  = 256;
parameter CO_LINK_CREDITS  = 32;
parameter MOC_LINK_CREDITS = 32;

parameter CD_CREDIT_INC    = 8;
parameter CO_CREDIT_INC    = 8;
parameter MOC_CREDIT_INC   = 1;

/* VC FIFOs WIDTH */
parameter WORD_WIDTH           = 64;

parameter VC_CO_MAX_SIZE       = 7;
parameter VC_CO_MAX_SIZE_BITS  = 3;
parameter VC_CD_MAX_SIZE       = 7;
parameter VC_CD_MAX_SIZE_BITS  = 3;
parameter VC_IO_MAX_SIZE       = 7;
parameter VC_IO_MAX_SIZE_BITS  = 3;
parameter VC_MCD_MAX_SIZE      = 7;
parameter VC_MCD_MAX_SIZE_BITS = 3;
parameter VC_MXC_MAX_SIZE      = 7;
parameter VC_MXC_MAX_SIZE_BITS = 3;

parameter NUM_CO_VCS           = 6;
parameter NUM_CD_VCS           = 4;
parameter NUM_IO_VCS           = 2;

// MXC
parameter [1:0] MXC_CIC  = 2'd3;
parameter [1:0] MXC_GMR  = 2'd2;
parameter [1:0] MXC_SSO  = 2'd1;
parameter [1:0] MXC_FPA  = 2'd0;
parameter [3:0] MXC_LWA  = 4'd1;
parameter [3:0] MXC_CIC_SZ  = 4'd11;
parameter [3:0] MXC_DMODE = 4'd10;
parameter [3:0] MXC_VALUE0 = 4'd11;

parameter [3:0] DOWNSTREAM_CTRL_CMD = 4'h8;

parameter  [7:0]   RSL_ID      = 8'h7E;


/* different block types */
typedef enum bit[2:0] {
    BTYPE_IDLE = 3'b111,
    BTYPE_LO   = 3'b100,
    BTYPE_HI   = 3'b101,
    BTYPE_SYNC = 3'b110
} Block_Type_t;

typedef struct packed {
    bit [NUM_BLOCK_DATA_WORDS-1:0][63:0]    Data;
    bit [39:0]                              custom_fields;
    bit [23:0]                              Crc24;
} Block_t;

/*
 * Data Block Format
 * Data Blocks use BTYPEs: CRED_LO, and CRED_HI.
 * Credit returns and ACKs are allowed.
 * VCs indicate data usage. Up to 7 valid 64bit words.
 */
typedef struct packed {
    bit [NUM_BLOCK_DATA_WORDS-1:0][63:0]    Data;
    Block_Type_t                            Type;
    bit                                     Ack;
    bit [NUM_BLOCK_DATA_WORDS:0]            Credits;
    bit [NUM_BLOCK_DATA_WORDS-1:0][3:0]     Vcs;
    bit [23:0]                              Crc24;
} DataBlock_t;

/*
 * Sync Block Format
 * BTYPE is SYNC.
 * No credit returns, No block ACKs, No VC info.
 * Data is unused.
 */
typedef struct packed {
    Block_Type_t        Type;
    bit                 Ack;
    bit [5:0]           Zeros;
    bit [1:0]           Req;
    bit [11:0]          Zeros2;
    bit [7:0]           TxSEQ;
    bit [7:0]           RxSEQ;
    bit [23:0]          Crc24;
} SyncBlock_t;


/*
 */
typedef struct packed {
    bit [63:0]    data;
    bit [15:0]    addr;
    bit           valid;
    bit           isWrite;
} SoftRegReq;

typedef struct packed {
    bit [63:0]    data;
    bit           valid;
} SoftRegResp;

endpackage
`endif
