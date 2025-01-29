/*
    Copyright (c) 2022 ETH Zurich.
    All rights reserved.

    This file is distributed under the terms in the attached LICENSE file.
    If you do not find this file, copies can be found by writing to:
    ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
*/

`ifndef ECIDEFS_SV_INCLUDED
`define ECIDEFS_SV_INCLUDED

package eci_package;

parameter  [1:0]  LOCAL_NODE_ID_FIXED = 2'b01;
parameter  [1:0]  MASTER_NODE_ID      = 2'b00;

typedef struct packed {
    logic [2:0] 		pp;
    logic [2:0] 		bus;
} eci_ppvid_t;

typedef
enum logic [4:0]
{ 		  ECI_IREQ_IOBLD		= 5'b00000,
       	ECI_IREQ_IOBST		= 5'b00010,
       	ECI_IREQ_IOBSTA		= 5'b00011,
       	ECI_IREQ_IOBSTP		= 5'b00100,
       	ECI_IREQ_IOBSTPA	= 5'b00101,
       	ECI_IREQ_IOBADDR	= 5'b00110,
       	ECI_IREQ_IOBADDRA	= 5'b00111,
       	ECI_IREQ_LMTST		= 5'b01000,
       	ECI_IREQ_LMTSTA		= 5'b01001,
       	ECI_IREQ_IAADD		= 5'b10000,
       	ECI_IREQ_IACLR		= 5'b10010,
       	ECI_IREQ_IASET		= 5'b10011,
       	ECI_IREQ_IASWP		= 5'b10100,
       	ECI_IREQ_IACAS		= 5'b10101,
       	ECI_IREQ_SLILD		= 5'b11100,
       	ECI_IREQ_SLIST		= 5'b11101,
       	ECI_IREQ_IDLE		  = 5'b11111
} eci_ireq_cmd_t;

typedef
enum logic [4:0]
{ 	  	ECI_IRSP_IOBRSP		= 5'b00000,
       	ECI_IRSP_IOBACK		= 5'b00001,
       	ECI_IRSP_SLIRSP		= 5'b00010,
       	ECI_IRSP_IDLE	  	= 5'b11111
} eci_irsp_cmd_t;


typedef
     enum logic [3:0]
     { // 1-Byte (halfword)
       ECI_SIZE1_OFFSET0  = 4'h0,
       ECI_SIZE1_OFFSET1  = 4'h1,
       ECI_SIZE1_OFFSET2  = 4'h2,
       ECI_SIZE1_OFFSET3  = 4'h3,
       ECI_SIZE1_OFFSET4  = 4'h4,
       ECI_SIZE1_OFFSET5  = 4'h5,
       ECI_SIZE1_OFFSET6  = 4'h6,
       ECI_SIZE1_OFFSET7  = 4'h7,
       // 2-Byte (singleword)
       ECI_SIZE2_OFFSET0  = 4'h8,
       ECI_SIZE2_OFFSET2  = 4'h9,
       ECI_SIZE2_OFFSET4  = 4'ha,
       ECI_SIZE2_OFFSET6  = 4'hb,
       // 4-Byte (doubleword)
       ECI_SIZE4_OFFSET0  = 4'hc,
       ECI_SIZE4_OFFSET4  = 4'hd,
       // 8-Byte (quadword)
       ECI_SIZE8_OFFSET0  = 4'he,
       // 16-Byte (octaword)
       ECI_SIZE16_OFFSET0 = 4'hf
       } eci_szoff_t;

typedef union packed
{
    // Mem
    //eci_mreq_cmd_t 		mreq;
    //eci_mfwd_cmd_t 		mfwd;
    //eci_mrsp_cmd_t 		mrsp;
    // I/O
    eci_ireq_cmd_t 		ireq;
    eci_irsp_cmd_t 		irsp;
} eci_command_t;

// IOBLD IOBST IOBSTA
// IOBSTP IOBSTPA
// IAADD IASET IACLR
// IASWP IACAS
// SLILD SLIST
typedef struct packed {
    logic [0:0] 		unused0;	// [+01 59]
    eci_ppvid_t 		ppvid;		// [+06 58]
    logic [2:0] 		flid;		// [+03 52]
    logic [1:0] 		el;			// [+02 49] : execution level
    logic 				ns;			// [+01 47] : non-secure
    logic 				be;			// [+01 46]
    logic [7:0] 		did;		// [+08 45]
    logic [32:0] 		addr;		// [+33 37]
    eci_szoff_t 		szoff;		// [+04  4]
} eci_ireq_byte_t;		// request (byte-type)

// IOBRSP SLIRSP
typedef struct packed {
    logic [0:0] 		unused3;	// [+01 59]
    eci_ppvid_t 		ppvid;		// [+06 58]
    logic [2:0] 		flid;		// [+03 52]
    logic [2:0] 		unused2;	// [+03 49] el/ns
    logic 				nxm;		// [+01	46]
    logic [7:0] 		unused1;	// [+08 45] did
    logic [32:0] 		unused0;	// [+33	37] addr
    logic [3:0] 		size;		// [+04	 4]
} eci_irsp_rsp_t;

// IOBACK
typedef struct  packed {
    logic [0:0]               unused5;        // [+01 59]
    eci_ppvid_t               ppvid;          // [+06 58]
    logic [2:0]               unused4;        // [+03 52] flid
    logic [3:0]               unused3;        // [+04 49] el/ns/be
    logic [7:0]               unused2;        // [+08 45] did
    logic [35:3]              unused1;        // [+33 37] addr
    logic [3:0]               unused0;        // [+04  4] size
} eci_irsp_ack_t;

typedef union packed
{
    // Mem
   /* eci_mreq_cblk_t 		mreq_cblk;
    eci_mreq_byte_t 		mreq_byte;
    eci_mreq_bcst_t 		mreq_bcst;
    eci_mfwd_tri_t 			mfwd_tri;
    eci_mfwd_pair_t 		mfwd_pair;
    eci_mrsp_vic_t 			mrsp_vic;
    eci_mrsp_hak_t 			mrsp_hak;
    eci_mrsp_cblk_t 		mrsp_cblk;
    eci_mrsp_byte_t 		mrsp_byte;
    eci_mrsp_bcst_t 		mrsp_bcst;*/
    // I/O
    eci_ireq_byte_t 		ireq_byte;
    //eci_ireq_dma_t 			ireq_dma;
    eci_irsp_ack_t 			irsp_ack;
    eci_irsp_rsp_t 			irsp_rsp;
 } eci_reqinfo_t;


typedef struct packed
{
	eci_command_t	cmd;
	eci_reqinfo_t   info;

} eci_request_t;

typedef struct  packed {
    logic [55:0]              unused;
    logic [1:0]               vl;
    logic [1:0]               pl;
    logic [3:0]               cmd;
} gic_dwnstr_ctrl_ack_t;


parameter [35:0]    ECI_COM_NODE            = 36'h011000000,
                    ECI_WIN_WR_DATA         = 36'h011000040,
                    ECI_WIN_RD_DATA         = 36'h011000050,

                    ECI_COM_LINK0_CTL       = 36'h011000020,
                    ECI_COM_LINK1_CTL       = 36'h011000028,
                    ECI_COM_LINK2_CTL       = 36'h011000030,

                    ECI_TLK0_LNK_DATA       = 36'h011010028,
                    ECI_TLK1_LNK_DATA       = 36'h011012028,
                    ECI_TLK2_LNK_DATA       = 36'h011014028,

                    ECI_RLK0_LNK_DATA       = 36'h011018028,
                    ECI_RLK1_LNK_DATA       = 36'h01101a028,
                    ECI_RLK2_LNK_DATA       = 36'h01101c028,

                    ECI_TLK0_MCD_CTL        = 36'h011010020,
                    ECI_TLK1_MCD_CTL        = 36'h011012020,
                    ECI_TLK2_MCD_CTL        = 36'h011014020,

                    ECI_RLK0_MCD_CTL        = 36'h011018020,
                    ECI_RLK1_MCD_CTL        = 36'h01101a020,
                    ECI_RLK2_MCD_CTL        = 36'h01101c020,

                    ECI_RLK0_ENABLES        = 36'h011018000,
                    ECI_RLK1_ENABLES        = 36'h01101a000,
                    ECI_RLK2_ENABLES        = 36'h01101c000,

                    ECI_PP_RD_DATA          = 36'h0110000d0,

                    ECI_QLM0_CFG            = 36'h01100F800,
                    ECI_QLM1_CFG            = 36'h01100F808,
                    ECI_QLM2_CFG            = 36'h01100F810,
                    ECI_QLM3_CFG            = 36'h01100F818,
                    ECI_QLM4_CFG            = 36'h01100F820,
                    ECI_QLM5_CFG            = 36'h01100F828
                    ;




//------------------------ RSL Registers Definition ----------------------//

typedef struct packed {
    bit [53:0]      unused1;
    bit       cclk_dis;
    bit       loop_back;
    bit       reinit;
    bit       unused0;
    bit       auto_clr;
    bit       drop;
    bit       up;
    bit       valid;
    bit [1:0]   id;
} com_lnkx_ctl_t;


typedef struct packed {
    bit [59:0]      unused;
    bit       fixed_pin;
    bit       fixed;
    bit [1:0]   id;
} com_node_t;


typedef struct packed {
    bit [7:0]       unused;
    bit [55:0]      data;
} tlkx_lnk_data_t;

typedef struct packed {
    bit             rcvd;
    bit [6:0]       unused;
    bit [55:0]      data;
} rlkx_lnk_data_t;

typedef struct packed {
    bit [63:2]      unused;
    bit [1:0]       sort;
} com_dual_sort_t;


typedef struct packed {
    bit [3:0]        ser_low;
    bit [17:0]       unused3;
    bit [9:0]        ser_limit;
    bit              cdr_dis;
    bit [3:0]        unused2;
    bit              trn_rxeq_only;
    bit              timer_dis;
    bit              trn_ena;
    bit [3:0]        ser_lane_ready;
    bit [3:0]        ser_lane_bad;
    bit [8:0]        unused1;
    bit              ser_lane_rev;
    bit              ser_rxpol_auto;
    bit              ser_rxpol;
    bit              ser_txpol;
    bit [1:0]        unused0;
    bit              ser_local;
} qlm_cfg_t;


endpackage
`endif
