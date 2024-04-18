`ifndef ECICMDDEFS_SV
`define ECICMDDEFS_SV
//Refer Alexander Hedges code for information - needs more documentation
//works only for Request with response and request without response modules
//Only has ECI_VC_MEMREQ commands

// $enzian/eci/eci_machine_readable/eci_decode.asl

// The eci command typedefs are hand created,
// They must be automaticcally generated from eci_decode.asl
// Need to revisit

package eci_cmd_defs;

   //------Parameters Definitions------//
   parameter ECI_FPGA_NODE_ID = 1;
   parameter ECI_THX_NODE_ID = 0;
   
   parameter ECI_WORD_WIDTH = 64;
   parameter ECI_WORD_SIZE_BYTES = ( ECI_WORD_WIDTH / 8 );

   // Widths of different aspects of ECI command 
   parameter ECI_ADDR_WIDTH   = 40;
   parameter ECI_OPCODE_WIDTH = 5;
   parameter ECI_ID_WIDTH = 5;
   parameter ECI_SZ_WIDTH = 3;
   parameter ECI_STSZ_WIDTH = 4;
   parameter ECI_DMASK_WIDTH = 4;
   parameter ECI_BYTE_STRB_WIDTH = 2;
   
   //This is similar to RReqId, but it is one bit wider, and is used when the home is the requester (both for Request & forwards).
   parameter ECI_HREQID_WIDTH = 6;

   //This Field have the number of response a requester is to expect, 0 = 1
   //response, 1 = 2 responses, 2 = 3 responses, 3 = 4 responses, (4 & above
   //are reserved). Currently with a 4 node system, the max PackCnt should
   //be 2 (i.e. 3 responses).
   parameter ECI_PACKCNT_WIDTH = 3;

   // Cache line parameters 
   parameter ECI_CL_WIDTH = 1024;
   
   // Number of words in a cache line ( 128 bytes )
   parameter ECI_CL_SIZE_BYTES = ( ECI_CL_WIDTH / 8 );
   
   // Number of bytes to be transfered for a cache line 
   // can very between 0 and 128. 
   // The number of bits required to describe this range is given by 
   parameter ECI_CL_LEN_WIDTH  = $clog2( ECI_CL_SIZE_BYTES ) + 1;

   // byte_address[ECI_ADDR_WIDTH-1:ECI_CL_ADDR_LSB] = cache_line_address
   // Align the byte address to cache line address 
   parameter ECI_CL_ADDR_LSB = $clog2(ECI_CL_SIZE_BYTES);
   parameter ECI_CL_INDEX_WIDTH = 33;
   parameter ECI_CL_BYTE_OFFSET_WIDTH = 7;

   // ECI maximum packet size = 16 eci words
   // 1 cmd + 16 data eci words
   parameter ECI_PACKET_SIZE = ( ECI_CL_WIDTH / ECI_WORD_WIDTH ) + 1;
   
   // Number of bits to describe ECI_PACKET_SIZE 
   parameter ECI_PACKET_SIZE_WIDTH = $clog2( ECI_PACKET_SIZE ); // 5
   
   // Number of bits indicating the number of sub cache lines in a packet
   // A sub cache line is 4 eci_words
   // A full cache line can contain 4 valid sub cache lines
   // the validity of a sub cache line is indicated by dmask 
   parameter ECI_SCL_WIDTH = 3;

   // Number of bits indicating the size of PPVID field
   parameter ECI_PPVID_WIDTH = 6;

   parameter ECI_RTAD_WIDTH = 3;

   parameter ECI_TOT_NUM_VCS = 14;

   parameter ECI_TOT_NUM_VCS_WIDTH = $clog2(ECI_TOT_NUM_VCS); // 4

   // 1 CL has maximum of 4 SCLs
   parameter ECI_NUM_SCLS_IN_CL = 4;
   // each SCL is 256 bits wide 
   parameter ECI_SCL_DATA_WIDTH = (ECI_CL_WIDTH/ECI_NUM_SCLS_IN_CL);

   // Home remote node IDs width in bits 
   parameter ECI_NODE_ID_WIDTH = 2;

   // ECI and LCL VCs
   // 14 ECI VCs, 4 local VCs - 18 VCs
   // with 5 bits we can get 32 ECI and LCL VCs. 
   parameter ECI_LCL_TOT_NUM_VCS_WIDTH = $clog2(ECI_TOT_NUM_VCS) + 1; // 5

   //------end Parameters Definitions------//
   
   
   //------ECI commands typedefs------//

   // Generic Types for fields inside the ECI commands and responses 
   typedef logic [ECI_CL_LEN_WIDTH-1:0]     eci_cl_len_t;
   typedef logic [ECI_OPCODE_WIDTH-1:0]     eci_opcode_t;
   typedef logic [ECI_ADDR_WIDTH-1:0] 	    eci_address_t;
   typedef logic [ECI_ID_WIDTH-1:0] 	    eci_id_t;
   typedef logic [ECI_SZ_WIDTH-1:0] 	    eci_sz_t;
   typedef logic [ECI_DMASK_WIDTH-1:0] 	    eci_dmask_t;
   typedef logic [ECI_HREQID_WIDTH-1:0]     eci_hreqid_t;
   typedef logic [ECI_PACKCNT_WIDTH-1:0]    eci_packcnt_t;
   typedef logic [ECI_STSZ_WIDTH-1:0] 	    eci_stsz_t;
   typedef logic [ECI_BYTE_STRB_WIDTH-1:0]  eci_byte_strb_t;
   typedef logic [ECI_PPVID_WIDTH-1:0] 	    eci_ppvid_t;
   typedef logic [ECI_RTAD_WIDTH-1:0] 	    eci_rtad_t;
   typedef logic [ECI_LCL_TOT_NUM_VCS_WIDTH-1:0] eci_vc_size_t;
   typedef logic [ECI_NODE_ID_WIDTH-1:0]     eci_nodeid_t;
   // Describes different ways of accessing
   // a 1024 bit cache line 
   typedef union packed {
      // 1024 bits 
      logic [ECI_CL_WIDTH-1:0] flat;
      // 4*256 (each 256 bit is 1 scl)
      logic [ECI_NUM_SCLS_IN_CL-1:0][ECI_SCL_DATA_WIDTH-1:0] scls;
      // packet size includes header + data 
      logic [ECI_PACKET_SIZE-2:0][ECI_WORD_WIDTH-1:0] words;
   } eci_cl_data_t;
   typedef union packed {
      logic [ECI_ADDR_WIDTH-1:0] flat;
      struct packed {
	 logic [ECI_CL_INDEX_WIDTH-1:0] cl_index;
	 logic [ECI_CL_BYTE_OFFSET_WIDTH-1:0] byte_offset;
      } parts;
   } eci_cl_addr_t;   

   // This is the strucutre of a generic ECI command command
   // TODO revisit 
   typedef struct packed {
      eci_opcode_t opcode;    //63:59	  
      eci_sz_t     sz;        //58:56
      logic 	   xb1;       //55
      eci_id_t     rreq_id;   //54:50	  
      eci_dmask_t  dmask;     //49:46	  
      logic [5:0]  xb6_2;     //45:40
      eci_stsz_t   stsz;      //39:36
      logic [35:0] rest_cmd;
   } generic_cmd_t;

   //Command Type: ECI_CMD_MREQ_LOAD
   // RLDD, RLDT
   // TODO revisit
   typedef struct packed{
      eci_opcode_t     opcode;   // 63:59
      logic [2:0]      xb3;      // 58:56
      logic 	       xb1;      // 55
      eci_id_t         rreq_id;  // 54:50 
      eci_dmask_t      dmask;    // 49:46
      logic 	       ns;       // 45
      logic [4:0]      xb5;      // 44:40
      eci_address_t    address;  // 39:0
   } mreq_load_t;

   // Typedef for ECI Responses 
   //Response Type: ECI_VC_CAT_MRSP
   // PSHA/ PACK/ P2DF
   // TODO Revisit - old  
   typedef struct packed{
      eci_opcode_t     opcode;     //5  63:59
      eci_packcnt_t    pack_cnt;   //3  58:56   
      logic 	       xb1;        //1     55
      eci_id_t         rreq_id;    //5  54:50
      eci_dmask_t      dmask;      //4  49:46
      logic [1:0]      dirty_32;   //2  45:44 
      logic [3:0]      req_unit;   //4  43:40
      logic [1:0]      dirty_10;   //2  39:38
      eci_hreqid_t     hreq_id;    //6  37:32
      logic [31:0]     xb32;       //32 31:0
   } mresp_load_t;

   
   //------ECI_VC_CAT_MREQ Opcodes 0x00000 to 0x11111------// 
   //Typedef for ECI_VC_CAT_MREQ
   // opcodes 0 to 10
   // RSTT/RLDX/RC2D_O/RC2D_S
   typedef struct packed{
      eci_opcode_t  opcode;   //5  63:59
      logic [3:0]   xb4;      //4  58:55
      eci_id_t      rreq_id;  //5  54:50
      eci_dmask_t   dmask;    //4  49:46
      logic         ns;       //1  45
      logic [2:0]   xb3;      //3  44:42
      logic [1:0]   xb2;      //2  41:40   different from ASL because address is only 40 bits
      eci_address_t address;  //40 39:0    combined A + fill from ASL spec to address 	   
   } eci_vc_cat_mreq_0to10_t;

   //Typedef for ECI_VC_CAT_MREQ
   // opcode x11000
   // GSYNC
   typedef struct packed{
      eci_opcode_t opcode;   //5  63:59
      logic [3:0]  xb3;      //4  58:55
      eci_id_t     rreq_id;  //5  54:50
      logic [39:0] xb40;     //40 49:10 
      eci_rtad_t   rtad;     //3  9:7
      logic 	   xb1;      //1  6     Unused 
      eci_ppvid_t  ppvid;    //6  5:0
   } eci_vc_cat_mreq_24_t;
   //------end ECI_VC_CAT_MREQ Opcodes 0x00000 to 0x11111------//


   //------ECI_VC_CAT_MRSP Typedefs------// 
   //Typedef for ECI_VC_CAT_MRSP opcodes 9 and 10
   // ASL spec looks suspicious
   // PEMD/ PSHA
   typedef struct packed{
      eci_opcode_t  opcode;          //5  63:59
      logic 	    nxm;             //1  58
      logic [2:0]   xb3;             //3  57:55
      eci_id_t      rreq_id;         //5  54:50
      eci_dmask_t   dmask;           //4  49:46  dmask is always in 49:46 so good here
      logic 	    xb1;             //1  45
      logic [3:0]   dirty;           //4  44:41  Matches ASL  
      logic 	    xb1_2;           //1  40     Doesnt match ASL, pad so "dirty" bits match ASL
      logic [32:0]  cache_line_index;//33 39:7   Doesnt match ASL, in ASL address is 42 bits not 40
      logic [1:0]   fillo;           //2   6:5
      logic [4:0]   xb5;             //5   4:0
   } eci_vc_cat_mrsp_9to10_t;

   //Typedef for ECI_VC_CAT_MRSP opcodes 0 to 2
   // ECI_MRSP_VICD, ECI_MRSP_VICC, ECI_MRSP_VICS
   typedef struct   packed{
      eci_opcode_t  opcode;          //5  63:59  
      logic [8:0]   xb10;            //9  58:50  dont care
      eci_dmask_t   dmask;           //4  49:46   
      logic         ns;              //1  45     non secure bit 
      logic [4:0]   xb5;             //5  44:40  dont care
      eci_address_t address;         //40 39:0   
   } eci_vc_cat_mrsp_0to2_t;

   //Typedef for ECI_VC_CAT_MRSP opcodes 3 to 8
   // VICDHI, HAKD, HAKN_S, HAKI, HAKS, HAKV
   typedef struct   packed{
      eci_opcode_t  opcode;          //5  63:59
      logic [2:0]   xb3;             //3  58:56
      eci_hreqid_t  hreq_id;         //6  55:50
      eci_dmask_t   dmask;           //4  49:46   
      logic         ns;              //1  45     non secure bit 
      logic [4:0]   xb5;             //5  44:40  dont care
      eci_address_t address;         //40 39:0   
   } eci_vc_cat_mrsp_3to8_t;
   
   //Typedef for ECI_VC_CAT_MRSP opcode 24
   // GSDN
   typedef struct packed{
      eci_opcode_t opcode;           //5  63:59
      logic [12:0] xb12;             //13 58:46 Unused 
      logic 	   ns;               //1  45
      logic [34:0] xb35;             //35 44:10 Unused 
      eci_rtad_t   rtad;             //3  9:7
      logic 	   xb1;              //1  6     Unused 
      eci_ppvid_t  ppvid;            //6  5:0
   } eci_vc_cat_mrsp_24_t;      
   //------end ECI_VC_CAT_MRSP Typedefs------//
   
   // Typedef for ECI_VC_CAT_MFWD opcdes 0 to 15
   // FLDRO_E, FLDRO_O, FLDRS_E, FLDRS_O
   // FLDRS_EH, FLDRS_OH, FLDT_E, FLDX_E, FLDX_O.
   // FLDX_EH, FLDX_OH, FEVX_EH, FEVX_OH,
   // SINV, SINV_H
   typedef struct packed{
      eci_opcode_t opcode;   // 5 63:59
      logic [2:0] xb3;       // 3 58:56
      eci_hreqid_t hreq_id;  // 6 55:50
      eci_dmask_t  dmask;    // 4 49:46
      logic 	   ns;       // 1 45
      logic 	   xb1;      // 1 44
      eci_nodeid_t rnode;    // 2 43:42
      logic [1:0] xb2;       // 2 41:40
      eci_address_t address; // 40 39:0
   } eci_vc_cat_mfwd_0to15_t;
   //------end ECI commands typedefs------//

   // Non ECI commands from local FPGA interfaces.
   // local clean, clean invalidate 
   typedef struct   packed{
      eci_opcode_t opcode;   // 5 63:59
      logic [2:0] xb3;       // 3 58:56
      eci_hreqid_t hreq_id;  // 6 55:50
      eci_dmask_t  dmask;    // 4 49:46
      logic 	   ns;       // 1 45
      logic 	   xb1;      // 1 44
      eci_nodeid_t rnode;    // 2 43:42
      logic [1:0] xb2;       // 2 41:40
      eci_address_t address; // 40 39:0
   } lcl_mfwd_t;

   // Non ECI responses to local FPGA interfaces.
   // local clean ack, clean invalidate ack.
   typedef struct packed{
      eci_opcode_t  opcode;          //5  63:59
      logic [2:0]   xb3;             //3  58:56
      eci_hreqid_t  hreq_id;         //6  55:50
      eci_dmask_t   dmask;           //4  49:46   
      logic         ns;              //1  45     non secure bit 
      logic [4:0]   xb5;             //5  44:40  dont care
      eci_address_t address;         //40 39:0   
   } lcl_mrsp_0to1_t;

   // ECI unlock to local FPGA interface.
   // unlock an address.
   typedef struct packed{
      eci_opcode_t  opcode;          //5  63:59
      logic [2:0]   xb3;             //3  58:56
      eci_hreqid_t  xb6;             //6  55:50
      eci_dmask_t   xb4;             //4  49:46   
      logic         xb1;             //1  45     non secure bit 
      logic [4:0]   xb5;             //5  44:40  dont care
      eci_address_t address;         //40 39:0   
   } lcl_mrsp_2_t;
   

   //------UNION OF TYPES------// 
   
   // Union of different types of ECI commands
   typedef union packed {
      generic_cmd_t generic_cmd;
      //ECI_CMD_MREQ_LOAD
      mreq_load_t mreq_load; //generic

      // Todo - old format bad
      // dont add anymore opcodes below
      // try not to use them in future so migration is easier 
      mreq_load_t rldt;
      mreq_load_t rldd;
      mresp_load_t mresp_load;
      // use psha_new in future
      mresp_load_t psha;

      // New format - good
      // Add opcodes below
      eci_vc_cat_mreq_0to10_t mreq_0to10; //generic
      eci_vc_cat_mreq_0to10_t rldi;
      eci_vc_cat_mreq_0to10_t rstt;
      eci_vc_cat_mreq_0to10_t rldx;
      eci_vc_cat_mreq_0to10_t rc2d_o;
      eci_vc_cat_mreq_0to10_t rc2d_s;
      eci_vc_cat_mreq_24_t    gsync;

      //MRSP
      // opcode 0 to 2
      eci_vc_cat_mrsp_0to2_t  mrsp_0to2; //generic
      eci_vc_cat_mrsp_0to2_t  vicd;
      eci_vc_cat_mrsp_0to2_t  vicc;
      eci_vc_cat_mrsp_0to2_t  vics;
      eci_vc_cat_mrsp_3to8_t  mrsp_3to8; // generic
      eci_vc_cat_mrsp_3to8_t  vicdhi; 
      eci_vc_cat_mrsp_3to8_t  hakd;
      eci_vc_cat_mrsp_3to8_t  hakn_s;
      eci_vc_cat_mrsp_3to8_t  haki; 
      eci_vc_cat_mrsp_3to8_t  haks;
      eci_vc_cat_mrsp_3to8_t  hakv;
      eci_vc_cat_mrsp_24_t    gsdn;

      // opcode 9 10
      eci_vc_cat_mrsp_9to10_t pemd;
      eci_vc_cat_mrsp_9to10_t psha_new;

      //MFWD
      eci_vc_cat_mfwd_0to15_t mfwd_generic; // generic 
      eci_vc_cat_mfwd_0to15_t fevx_eh;
      eci_vc_cat_mfwd_0to15_t sinv_h;

      // Local mfwd clean, clean inv
      lcl_mfwd_t lcl_mfwd_generic; // generic.
      lcl_mfwd_t lcl_clean;
      lcl_mfwd_t lcl_clean_inv;

      lcl_mrsp_0to1_t lcl_mrsp_0to1; // generic.
      lcl_mrsp_0to1_t lcl_clean_ack;
      lcl_mrsp_0to1_t lcl_clean_inv_ack;

      lcl_mrsp_2_t    lcl_mrsp_2; // generic.
      lcl_mrsp_2_t    lcl_unlock;
      
      logic [ ECI_WORD_WIDTH-1:0] eci_word;
   } eci_word_t;
   //------end UNION OF TYPES------//
   
   //------VC types------//
   // E indicates even, O indicates odd
   // odd CL indices come to Even VCs and vice versa
   parameter eci_vc_size_t VC_REQ_WO_DATA_E = 6;
   parameter eci_vc_size_t VC_REQ_WO_DATA_O = 7;
   parameter eci_vc_size_t VC_REQ_W_DATA_E = 2;
   parameter eci_vc_size_t VC_REQ_W_DATA_O = 3;
   parameter eci_vc_size_t VC_RESP_WO_DATA_E = 10;
   parameter eci_vc_size_t VC_RESP_WO_DATA_O = 11;
   parameter eci_vc_size_t VC_RESP_W_DATA_E = 4;
   parameter eci_vc_size_t VC_RESP_W_DATA_O = 5;
   parameter eci_vc_size_t VC_FWD_WO_DATA_E = 8;
   parameter eci_vc_size_t VC_FWD_WO_DATA_O = 9;
   parameter eci_vc_size_t VC_IO_REQ = 0;
   parameter eci_vc_size_t VC_IO_RESP = 1;
   // Local VC types.
   parameter eci_vc_size_t VC_LCL_FWD_WO_DATA_E = 16;
   parameter eci_vc_size_t VC_LCL_FWD_WO_DATA_O = 17;
   parameter eci_vc_size_t VC_LCL_RESP_WO_DATA_E = 18;
   parameter eci_vc_size_t VC_LCL_RESP_WO_DATA_O = 19;
   
   //------end VC types------//
   
   // Type def ECI properties 
   // Each ECI command has a number of properties
   // This is the list of properties 
   typedef struct packed {
      // Each ECI command is associated with a type, check ECI CMD TYPES
      eci_opcode_t eci_cmd_type;
      // Number of words present in a packet is given by this property 
      logic [ ECI_PACKET_SIZE_WIDTH-1:0] num_words_in_pkt;
      // Number of byte strobe words in this command 
      eci_byte_strb_t num_byte_strobe_words;
      // If command is not supported yet/ unknown this property
      // would be set to 1
      logic 				      cmd_undocumented;
      // Number of valid sub cache lines associated wit this command 
      logic [ ECI_SCL_WIDTH-1:0] 	      num_scl_in_pkt;
   } eci_cmd_prop_t;

   //------ECI Commands Opcodes------// 
   localparam ECI_CMD_MREQ_LOAD          = 5'd0;
   localparam ECI_CMD_MREQ_STORE         = 5'd1;
   localparam ECI_CMD_MREQ_PARTIAL_STORE = 5'd2;
   localparam ECI_CMD_MREQ_ATOMIC        = 5'd3;
   localparam ECI_CMD_MREQ_CSWP          = 5'd4;
   localparam ECI_CMD_MREQ_IDLE          = 5'd5;
   localparam ECI_CMD_MFWD_2NODES        = 5'd6;
   localparam ECI_CMD_MFWD_IDLE          = 5'd7;
   localparam ECI_CMD_MRSP_ACK           = 5'd8;
   localparam ECI_CMD_MRSP_WORD          = 5'd9;
   localparam ECI_CMD_MRSP_IDLE          = 5'd10;
   localparam ECI_CMD_IREQ_IOBLD         = 5'd11;
   localparam ECI_CMD_IREQ_IOBST         = 5'd12;
   localparam ECI_CMD_IREQ_IOBDMA        = 5'd13;
   localparam ECI_CMD_IOREQ_LMTST        = 5'd14;
   localparam ECI_CMD_IREQ_IDLE          = 5'd15;
   localparam ECI_CMD_IRSP_IOBRSP        = 5'd16;
   localparam ECI_CMD_IRSP_IOBACK        = 5'd17;
   localparam ECI_CMD_IRSP_IDLE          = 5'd18;
   localparam ECI_CMD_UNDOCUMENTED       = 5'd19;
   localparam ECI_CMD_VC_CAT_MRSP        = 5'd20;
   
   //ECI MREQ Commands
   localparam ECI_CMD_MREQ_RLDD        = 5'b00000;
   localparam ECI_CMD_MREQ_RLDI        = 5'b00001;
   localparam ECI_CMD_MREQ_RLDT        = 5'b00010;
   localparam ECI_CMD_MREQ_RLDY        = 5'b00011;
   localparam ECI_CMD_MREQ_RLDWB       = 5'b00100;
   localparam ECI_CMD_MREQ_RLDX        = 5'b00101;
   localparam ECI_CMD_MREQ_RC2D_O      = 5'b00110;
   localparam ECI_CMD_MREQ_RC2D_S      = 5'b00111;
   localparam ECI_CMD_MREQ_RSTT        = 5'b01000;
   localparam ECI_CMD_MREQ_RSTY        = 5'b01001;
   localparam ECI_CMD_MREQ_RSTP        = 5'b01010;
   localparam ECI_CMD_MREQ_REOR        = 5'b01011;
   localparam ECI_CMD_UNALLOCATED      = 5'b01100;
   localparam ECI_CMD_MREQ_RADD        = 5'b01101;
   localparam ECI_CMD_MREQ_RINC        = 5'b01110;
   localparam ECI_CMD_MREQ_RDEC        = 5'b01111;
   localparam ECI_CMD_MREQ_RSWP        = 5'b10000;
   localparam ECI_CMD_MREQ_RSET        = 5'b10001;
   localparam ECI_CMD_MREQ_RCLR        = 5'b10010;
   localparam ECI_CMD_MREQ_RCAS        = 5'b10011;
   localparam ECI_CMD_MREQ_GINV        = 5'b10100;
   localparam ECI_CMD_MREQ_RCASO       = 5'b10101;
   localparam ECI_CMD_MREQ_RCASS       = 5'b10110;
   localparam ECI_CMD_MREQ_RSTC        = 5'b10111;
   localparam ECI_CMD_MREQ_GSYNC       = 5'b11000;
   localparam ECI_CMD_MREQ_RSTCO       = 5'b11001;
   localparam ECI_CMD_MREQ_RSTCS       = 5'b11010;
   localparam ECI_CMD_MREQ_RSMAX       = 5'b11011;
   localparam ECI_CMD_MREQ_RSMIN       = 5'b11100;
   localparam ECI_CMD_MREQ_RUMAX       = 5'b11101;
   localparam ECI_CMD_MREQ_RUMIN       = 5'b11110;
   localparam ECI_CMD_MREQ_IDLE_OPCODE = 5'b11111;

   //ECI_VC_CAT_MRSP
   localparam ECI_CMD_MRSP_VICD        = 5'b00000;
   localparam ECI_CMD_MRSP_VICC        = 5'b00001;
   localparam ECI_CMD_MRSP_VICS        = 5'b00010;
   localparam ECI_CMD_MRSP_VICDHI      = 5'b00011;
   localparam ECI_CMD_MRSP_HAKD        = 5'b00100;
   localparam ECI_CMD_MRSP_HAKN_S      = 5'b00101;
   localparam ECI_CMD_MRSP_HAKI        = 5'b00110;
   localparam ECI_CMD_MRSP_HAKS        = 5'b00111;
   localparam ECI_CMD_MRSP_HAKV        = 5'b01000;
   localparam ECI_CMD_MRSP_PSHA        = 5'b01001;
   localparam ECI_CMD_MRSP_PEMD        = 5'b01010;
   localparam ECI_CMD_MRSP_GSDN        = 5'b11000;

   //ECI_VC_CAT_MFWD
   localparam ECI_CMD_MFWD_FLDRO_E	= 5'b00000;
   localparam ECI_CMD_MFWD_FLDRO_O	= 5'b00001;
   localparam ECI_CMD_MFWD_FLDRS_E	= 5'b00010;
   localparam ECI_CMD_MFWD_FLDRS_O	= 5'b00011;
   localparam ECI_CMD_MFWD_FLDRS_EH	= 5'b00100;
   localparam ECI_CMD_MFWD_FLDRS_OH	= 5'b00101;
   localparam ECI_CMD_MFWD_FLDT_E	= 5'b00110;
   localparam ECI_CMD_MFWD_FLDX_E	= 5'b00111;
   localparam ECI_CMD_MFWD_FLDX_O	= 5'b01000;
   localparam ECI_CMD_MFWD_FLDX_EH	= 5'b01001;
   localparam ECI_CMD_MFWD_FLDX_OH	= 5'b01010;
   localparam ECI_CMD_MFWD_FEVX_EH	= 5'b01011;
   localparam ECI_CMD_MFWD_FEVX_OH	= 5'b01100;
   localparam ECI_CMD_MFWD_SINV		= 5'b01101;
   localparam ECI_CMD_MFWD_SINV_H	= 5'b01110;
   
   // Local MFWD
   localparam LCL_CMD_MFWD_CLEAN         = 5'b00000;
   localparam LCL_CMD_MFWD_CLEAN_INV     = 5'b00001;

   // Local MRSP 0to1
   localparam LCL_CMD_MRSP_CLEAN_ACK    = 5'b00000;
   localparam LCL_CMD_MRSP_CLEAN_INV_ACK = 5'b00001;

   // Local MRSP 2
   localparam LCL_CMD_MRSP_UNLOCK = 5'b00010;
   
   

   //------end ECI Commands Opcodes------//

   //------ECI Functions------// 
   /*
    * Function to get number of  sub cache lines based on 
    * dmask
    * 
    * a dmask bit of 1 indicates a valid sub cache line 
    * 
    */
   function automatic [ECI_SCL_WIDTH-1:0] get_scl_from_dmask;
      input eci_dmask_t dmask;
      begin
	 case(dmask)
	   4'b0000: get_scl_from_dmask = 3'd0;
	   4'b0001: get_scl_from_dmask = 3'd1;
	   4'b0010: get_scl_from_dmask = 3'd1;
	   4'b0011: get_scl_from_dmask = 3'd2;
	   4'b0100: get_scl_from_dmask = 3'd1;
	   4'b0101: get_scl_from_dmask = 3'd2;
	   4'b0110: get_scl_from_dmask = 3'd2;
	   4'b0111: get_scl_from_dmask = 3'd3;
	   4'b1000: get_scl_from_dmask = 3'd1;
	   4'b1001: get_scl_from_dmask = 3'd2;
	   4'b1010: get_scl_from_dmask = 3'd2;
	   4'b1011: get_scl_from_dmask = 3'd3;
	   4'b1100: get_scl_from_dmask = 3'd2;
	   4'b1101: get_scl_from_dmask = 3'd3;
	   4'b1110: get_scl_from_dmask = 3'd3;
	   4'b1111: get_scl_from_dmask = 3'd4;
	   default: get_scl_from_dmask = 3'd0;
	 endcase // case (dmask)
      end
   endfunction // get_scl_from_dmask

   //get the total number of words in eci packet 
   //1 cmd word + 4 * num_scl data words 
   function automatic [ECI_PACKET_SIZE_WIDTH-1:0] get_num_words_from_scl;
      input [ECI_SCL_WIDTH-1:0] num_scl;
      begin
	 case(num_scl)
	   0:get_num_words_from_scl = 5'd1;
	   1:get_num_words_from_scl = 5'd5;
	   2:get_num_words_from_scl = 5'd9;
	   3:get_num_words_from_scl = 5'd13;
	   4:get_num_words_from_scl = 5'd17;
	   default:get_num_words_from_scl = 5'd1;
	 endcase // case (num_scl)
      end
   endfunction // get_num_words_from_scl

   // Get Number of words in ECI packet from STSZ 
   function automatic [ECI_PACKET_SIZE_WIDTH-1:0] get_num_words_from_stsz;
      input eci_stsz_t in_stsz;
      begin
	 get_num_words_from_stsz = {1'b0,1'b0,in_stsz};
      end
   endfunction // get_num_words_from_stsz

   //cmd + data - total packet size not just data packet size
   function automatic [ECI_PACKET_SIZE_WIDTH-1:0] get_num_words_from_sz;
      input eci_sz_t in_sz;
      case(in_sz)
	0: get_num_words_from_sz = 3;
	1: get_num_words_from_sz = 3;
	2: get_num_words_from_sz = 4;
	3: get_num_words_from_sz = 4;
	4: get_num_words_from_sz = 5;
	5: get_num_words_from_sz = 5;
	6: get_num_words_from_sz = 6;
	7: get_num_words_from_sz = 6;
      endcase // case (in_sz)
   endfunction // get_num_words_from_sz

   // ECI Commands are grouped into a number of types
   // This function is used get the group type of an
   // ECI command given its opcode 
   function automatic eci_opcode_t get_eci_cmd_type;
      input eci_opcode_t cmd_opcode;
      begin
	 case(cmd_opcode)
	   
	   ECI_CMD_MREQ_RLDD:   get_eci_cmd_type        = ECI_CMD_MREQ_LOAD;
	   ECI_CMD_MREQ_RLDI:   get_eci_cmd_type        = ECI_CMD_MREQ_LOAD;
	   ECI_CMD_MREQ_RLDT:   get_eci_cmd_type        = ECI_CMD_MREQ_LOAD;
	   ECI_CMD_MREQ_RLDY:   get_eci_cmd_type        = ECI_CMD_MREQ_LOAD;
	   ECI_CMD_MREQ_RLDWB:  get_eci_cmd_type	= ECI_CMD_MREQ_LOAD;
	   ECI_CMD_MREQ_RLDX:   get_eci_cmd_type        = ECI_CMD_MREQ_LOAD;
	   ECI_CMD_MREQ_RC2D_O: get_eci_cmd_type	= ECI_CMD_MREQ_LOAD;
	   ECI_CMD_MREQ_RC2D_S: get_eci_cmd_type	= ECI_CMD_MREQ_LOAD;
	   
	   ECI_CMD_MREQ_RSTT:   get_eci_cmd_type        = ECI_CMD_MREQ_STORE;
	   ECI_CMD_MREQ_RSTY:   get_eci_cmd_type        = ECI_CMD_MREQ_STORE;
	   
	   ECI_CMD_MREQ_RSTP:   get_eci_cmd_type        = ECI_CMD_MREQ_PARTIAL_STORE;
	   
	   ECI_CMD_MREQ_REOR:   get_eci_cmd_type        = ECI_CMD_UNDOCUMENTED;
	   ECI_CMD_MREQ_RADD:   get_eci_cmd_type        = ECI_CMD_UNDOCUMENTED;
	   ECI_CMD_UNALLOCATED: get_eci_cmd_type	= ECI_CMD_UNDOCUMENTED;
	   
	   ECI_CMD_MREQ_RINC:   get_eci_cmd_type        = ECI_CMD_MREQ_ATOMIC;
	   ECI_CMD_MREQ_RDEC:   get_eci_cmd_type        = ECI_CMD_MREQ_ATOMIC;
	   ECI_CMD_MREQ_RSWP:   get_eci_cmd_type        = ECI_CMD_MREQ_ATOMIC;
	   ECI_CMD_MREQ_RSET:   get_eci_cmd_type        = ECI_CMD_MREQ_ATOMIC;
	   ECI_CMD_MREQ_RCLR:   get_eci_cmd_type        = ECI_CMD_MREQ_ATOMIC;
	   
	   ECI_CMD_MREQ_RCAS:   get_eci_cmd_type        = ECI_CMD_MREQ_CSWP;
	   ECI_CMD_MREQ_GINV:   get_eci_cmd_type        = ECI_CMD_MREQ_CSWP;
	   ECI_CMD_MREQ_RCASO:  get_eci_cmd_type	= ECI_CMD_MREQ_CSWP;
	   ECI_CMD_MREQ_RCASS:  get_eci_cmd_type	= ECI_CMD_MREQ_CSWP;
	   ECI_CMD_MREQ_RSTC:   get_eci_cmd_type        = ECI_CMD_MREQ_CSWP;
	   
	   ECI_CMD_MREQ_GSYNC:  get_eci_cmd_type	= ECI_CMD_UNDOCUMENTED;
	   
	   ECI_CMD_MREQ_RSTCO:  get_eci_cmd_type	= ECI_CMD_MREQ_CSWP;
	   ECI_CMD_MREQ_RSTCS:  get_eci_cmd_type	= ECI_CMD_MREQ_CSWP;
	   
	   ECI_CMD_MREQ_RSMAX:  get_eci_cmd_type	= ECI_CMD_UNDOCUMENTED;
	   ECI_CMD_MREQ_RSMIN:  get_eci_cmd_type	= ECI_CMD_UNDOCUMENTED;
	   ECI_CMD_MREQ_RUMAX:  get_eci_cmd_type	= ECI_CMD_UNDOCUMENTED;
	   ECI_CMD_MREQ_RUMIN:  get_eci_cmd_type	= ECI_CMD_UNDOCUMENTED;
	   
	   ECI_CMD_MREQ_IDLE_OPCODE: get_eci_cmd_type	= ECI_CMD_MREQ_IDLE;

	   default: get_eci_cmd_type			= ECI_CMD_UNDOCUMENTED;
	 endcase // case (cmd_opcode)
      end
   endfunction // get_eci_cmd_type
   
   //number of byte strobes based on packet size
   function automatic [ECI_PACKET_SIZE_WIDTH-1:0] get_num_byte_strobe_words;
      input [ ECI_SCL_WIDTH-1:0] num_scl;
      begin
	 case(num_scl)
	   0:get_num_byte_strobe_words = 5'd0;
	   1:get_num_byte_strobe_words = 5'd1;
	   2:get_num_byte_strobe_words = 5'd1;
	   3:get_num_byte_strobe_words = 5'd2;
	   4:get_num_byte_strobe_words = 5'd2;
	   default:get_num_byte_strobe_words = 5'd0;
	 endcase // case (num_scl)
      end
   endfunction // get_num_byte_strobe_words

   // Generic function to get properties of an ECI command
   // Properties include
   //
   // The Type of ECI command
   // The number of sub cache lines in the packet
   // The number of ECI words in the packet
   // The number of byte strobe words in the packet
   // If the command is a valid command supported by current code
   //
   // Combinational logic 
   localparam NUM_WORDS_FOR_JUST_CMD  = 5'd1;
   localparam NO_BYTE_STROBE_WORDS    = 5'd0;
   localparam NUM_WORDS_JUST_ONE_DATA = 5'd2;
   function automatic eci_cmd_prop_t eci_cmd_prop_extract;
      input eci_word_t eci_cmd;

      eci_opcode_t this_opcode;
      eci_dmask_t  this_dmask;
      eci_stsz_t   this_stsz;
      eci_sz_t     this_sz;
      eci_opcode_t this_type;
      
      logic [ ECI_SCL_WIDTH-1:0]		this_num_scl;
      logic [ ECI_SCL_WIDTH-1:0]		this_num_words_from_scl;
      logic [ ECI_PACKET_SIZE_WIDTH-1:0]	this_num_byte_strobe_words;
      logic [ ECI_PACKET_SIZE_WIDTH-1:0]	this_num_words_from_sz;
      logic [ ECI_PACKET_SIZE_WIDTH-1:0]	this_num_words_from_stsz;

      begin
	 this_opcode = eci_cmd.generic_cmd.opcode;
	 this_type   = get_eci_cmd_type( this_opcode );
	 this_dmask  = eci_cmd.generic_cmd.dmask;
	 this_stsz   = eci_cmd.generic_cmd.stsz;;
	 this_sz     = eci_cmd.generic_cmd.sz;

	 this_num_scl			= get_scl_from_dmask( this_dmask );
	 this_num_words_from_scl	= get_num_words_from_scl( this_num_scl );
	 this_num_byte_strobe_words	= get_num_byte_strobe_words( this_num_scl );
	 this_num_words_from_sz		= get_num_words_from_sz( this_sz );
	 this_num_words_from_stsz       = get_num_words_from_stsz( this_stsz );
	 
	 eci_cmd_prop_extract				= '0;
	 eci_cmd_prop_extract.eci_cmd_type		= this_type;
	 eci_cmd_prop_extract.num_scl_in_pkt		= this_num_scl;
	 eci_cmd_prop_extract.num_byte_strobe_words	= '0;
	 eci_cmd_prop_extract.num_words_in_pkt		= '0;
	 eci_cmd_prop_extract.cmd_undocumented		= '0;

	 case ( this_type )
	   ECI_CMD_MREQ_LOAD: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_MREQ_STORE: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= this_num_words_from_scl;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_MREQ_PARTIAL_STORE: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= this_num_words_from_scl + this_num_byte_strobe_words;
	      eci_cmd_prop_extract.num_byte_strobe_words	= this_num_byte_strobe_words;
	   end
	   ECI_CMD_MREQ_ATOMIC: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_MREQ_CSWP: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= this_num_words_from_sz;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_MREQ_IDLE: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_MFWD_2NODES: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_MFWD_IDLE: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_MRSP_ACK: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= this_num_words_from_scl;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_MRSP_WORD: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_JUST_ONE_DATA;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_MRSP_IDLE: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_IREQ_IOBLD: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_IREQ_IOBST: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_JUST_ONE_DATA;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_IREQ_IOBDMA: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_IOREQ_LMTST: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= this_num_words_from_stsz;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_IREQ_IDLE: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_IRSP_IOBRSP: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= this_num_words_from_stsz;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_IRSP_IOBACK: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   ECI_CMD_IRSP_IDLE: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	   end
	   // Not handling memory responses here need to be enhanced
	   // ECI_CMD_VC_CAT_MRSP: begin
	   //    eci_cmd_prop_extract.num_words_in_pkt             = this_num_words_from_scl;
	   //    eci_cmd_prop_extract.num_byte_strobe_words        = NO_BYTE_STROBE_WORDS;
	   // end
	   ECI_CMD_UNDOCUMENTED:begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	      eci_cmd_prop_extract.cmd_undocumented		= 1;
	   end
	   default: begin
	      eci_cmd_prop_extract.num_words_in_pkt		= NUM_WORDS_FOR_JUST_CMD;
	      eci_cmd_prop_extract.num_byte_strobe_words	= NO_BYTE_STROBE_WORDS;
	      eci_cmd_prop_extract.cmd_undocumented		= 1;
	   end
	   
	 endcase
      end
   endfunction // eci_cmd_prop_extract

   // Function to display command properties 
   function void display_eci_cmd_props;
      input eci_cmd_prop_t eci_cmd_prop;
      begin
	 $display("ECI eci_cmd_type		- %b", eci_cmd_prop.eci_cmd_type);
	 $display("ECI num_words_in_pkt		- %b", eci_cmd_prop.num_words_in_pkt);
	 $display("ECI num_byte_strobe_words	- %b", eci_cmd_prop.num_byte_strobe_words);
	 $display("ECI cmd_undocumented		- %b", eci_cmd_prop.cmd_undocumented);
	 $display("ECI num_scl_in_pkt     	- %b", eci_cmd_prop.num_scl_in_pkt);
      end
   endfunction // display_eci_cmd_props

   function automatic [ECI_ADDR_WIDTH - 1 : 0] eci_alias_address
     (
      input logic [ECI_ADDR_WIDTH-1:0] address_i
      );
      // Compute the aliased address
      // Refer to THX manual or talk to Adamt
      logic [ ECI_ADDR_WIDTH-1:0] 	    aliased_addr_o;
      aliased_addr_o        = '0;
      aliased_addr_o[32:13] = address_i[39:20];
      aliased_addr_o[12:8]  = address_i[19:15] ^ address_i[24:20];
      aliased_addr_o[7:5]   = address_i[14:12] ^ address_i[27:25];
      aliased_addr_o[4:3]   = address_i[11:10] ^ address_i[24:23] ^ address_i[13:12];
      aliased_addr_o[2:0]   = address_i[9:7]   ^ address_i[22:20] ^ address_i[14:12];      
      return( aliased_addr_o );
   endfunction //eci_alias_address

   //------end ECI Functions------//

    function automatic [ECI_CL_INDEX_WIDTH-1:0] eci_alias_cache_line_index
        (
            input logic [ECI_CL_INDEX_WIDTH-1:0] cli
        );
        logic [ECI_CL_INDEX_WIDTH-1:0] aliased_cli;
        aliased_cli[32:13] = cli[32:13];
        aliased_cli[12:8]  = cli[12:8] ^ cli[17:13];
        aliased_cli[7:5]   = cli[7:5] ^ cli[20:18];
        aliased_cli[4:3]   = cli[4:3] ^ cli[17:16] ^ cli[6:5];
        aliased_cli[2:0]   = cli[2:0] ^ cli[15:13] ^ cli[7:5];
        return (aliased_cli);
    endfunction

    function automatic [ECI_CL_INDEX_WIDTH-1:0] eci_unalias_cache_line_index
        (
            input logic [ECI_CL_INDEX_WIDTH-1:0] aliased_cli
        );
        logic [ECI_CL_INDEX_WIDTH-1:0] cli;
        cli[32:13] = aliased_cli[32:13];
        cli[12:8]  = aliased_cli[12:8] ^ aliased_cli[17:13];
        cli[7:5]   = aliased_cli[7:5] ^ aliased_cli[20:18];
        cli[4:3]   = aliased_cli[4:3] ^ aliased_cli[19:18] ^ aliased_cli[17:16] ^ aliased_cli[6:5];
        cli[2:0]   = aliased_cli[2:0] ^ aliased_cli[20:18] ^ aliased_cli[15:13] ^ aliased_cli[7:5];
        return (cli);
    endfunction
    
   function automatic [ECI_PACKET_SIZE_WIDTH-1:0] get_pkt_size_from_dmask
     (
      input eci_dmask_t my_dmask_i
      );
      logic [ECI_PACKET_SIZE_WIDTH-1:0] pkt_size_o;
      logic [ECI_SCL_WIDTH-1:0] 	this_num_scl;
      this_num_scl = eci_cmd_defs::get_scl_from_dmask(.dmask(my_dmask_i));
      pkt_size_o = eci_cmd_defs::get_num_words_from_scl(.num_scl(this_num_scl));
      return(pkt_size_o);
   endfunction : get_pkt_size_from_dmask
   
   // ECI Request, response functions
   function automatic [ECI_LCL_TOT_NUM_VCS_WIDTH-1:0] eci_get_resp_vc
     (
      input logic [ECI_LCL_TOT_NUM_VCS_WIDTH-1:0] req_vc_i,
      input logic [ECI_WORD_WIDTH-1:0] 	      req_i
      );
      // Get response VC given request VC and request opcode

      logic [ECI_LCL_TOT_NUM_VCS_WIDTH-1:0]       vc2;
      logic [ECI_LCL_TOT_NUM_VCS_WIDTH-1:0]       resp_vc_o;
      eci_word_t eci_cmd;
      
      // check softeci eci.c 
      vc2 = req_vc_i & ECI_LCL_TOT_NUM_VCS_WIDTH'('d14);
      
      eci_cmd = eci_word_t'(req_i);
      case(vc2)
	6: begin
	   case(eci_cmd.generic_cmd.opcode)
	     ECI_CMD_MREQ_GINV, ECI_CMD_MREQ_GSYNC: begin
		resp_vc_o = ECI_LCL_TOT_NUM_VCS_WIDTH'('d11);
	     end
	     ECI_CMD_MREQ_RLDD, ECI_CMD_MREQ_RLDX, ECI_CMD_MREQ_RC2D_S: begin
		resp_vc_o = req_vc_i & ECI_LCL_TOT_NUM_VCS_WIDTH'('d5);
	     end
	     default: begin
		$error("Error: Unable to find response VC for req VC %b, opcode %b (instance %m)", req_vc_i, eci_cmd.generic_cmd.opcode);
		$finish;
		resp_vc_o = req_vc_i & ECI_LCL_TOT_NUM_VCS_WIDTH'('d5);
	     end
	   endcase
	end
	
	default: begin
	   $error("Error: Unable to find response VC for req VC %b (instance %m)", req_vc_i);
	   $finish;
	   resp_vc_o = '0;
	end
      endcase // case (req_vc_i)
      
      return(resp_vc_o);
   endfunction : eci_get_resp_vc
   
   function automatic [ECI_WORD_WIDTH-1:0] eci_gen_pemd
     (
      input logic [ECI_WORD_WIDTH-1:0] req_i,
      // gen PEMN (no data) 
      input logic 		       pemn_i
      );
      // Given input RLDD/RLDX/RC2D_S request, generate PEMD response
      // NOTE: currently dmask is either all 0s or all 1s
      // because either no data is sent or full CL is sent 
      eci_word_t eci_cmd;
      eci_word_t eci_resp;
      eci_cmd = eci_word_t'(req_i);
      eci_resp.eci_word = '0;
      eci_resp.pemd.opcode = ECI_CMD_MRSP_PEMD;
      // RLDD/RLDX are type mreq_0to10
      eci_resp.pemd.rreq_id = eci_cmd.mreq_0to10.rreq_id;
      if(pemn_i) begin
	 // PEMN has no data, dmask is all 0
	 eci_resp.pemd.dmask = '0;
      end else begin
	 // PEMD has data so dmask depends on data 
	 // NOTE: TMP always sending full CL 
	 // eci_resp.pemd.dmask = eci_cmd.mreq_load.dmask;
	 eci_resp.pemd.dmask = '1;
      end
      eci_resp.pemd.dirty = '0;
      eci_resp.pemd.cache_line_index = eci_cmd.mreq_0to10.address[ECI_ADDR_WIDTH-1:7];
      eci_resp.pemd.fillo = '0;
      return(eci_resp.eci_word);
   endfunction : eci_gen_pemd

   // General template for mfwd requests from FPGA
   // WARNING: opcode is not filled 
   function automatic [ECI_WORD_WIDTH-1:0] eci_gen_mfwd
     (
      input logic [ECI_HREQID_WIDTH-1:0] hreq_id_i,
      input logic [ECI_DMASK_WIDTH-1:0]  dmask_i,
      input logic 			 ns_i,
      input logic [ECI_ADDR_WIDTH-1:0] 	 addr_i
      );
      eci_word_t mfwd_req;
      eci_address_t cl_addr;
      eci_hreqid_t hreq_id;
      mfwd_req.eci_word = '0;
      // byte offset is cleared to get cl address 
      cl_addr = addr_i & 7'd0;
      // Transactions issued by home can be 6 bits wid
      // home req id 
      // OPCODE NOT FILLED HERE 
      mfwd_req.mfwd_generic.hreq_id = hreq_id_i;
      mfwd_req.mfwd_generic.dmask = eci_dmask_t'(dmask_i);
      mfwd_req.mfwd_generic.ns  = ns_i;
      mfwd_req.mfwd_generic.rnode = eci_nodeid_t'(ECI_FPGA_NODE_ID);
      mfwd_req.mfwd_generic.address = addr_i;
      return(mfwd_req.eci_word);
   endfunction : eci_gen_mfwd

   // Also called fevx_2h.e
   function automatic [ECI_WORD_WIDTH-1:0] eci_gen_fevx_eh
     (
      input logic [ECI_HREQID_WIDTH-1:0] hreq_id_i,
      input logic [ECI_DMASK_WIDTH-1:0]  dmask_i,
      input logic 			 ns_i,
      input logic [ECI_ADDR_WIDTH-1:0] 	 addr_i
      );
      eci_word_t fevx_eh_req;
      // Opcode will not be filled 
      fevx_eh_req.eci_word = eci_gen_mfwd(
					  .hreq_id_i(hreq_id_i),
					  .dmask_i(dmask_i),
					  .ns_i(ns_i),
					  .addr_i(addr_i)
					  );
      // Fill opcode 
      fevx_eh_req.mfwd_generic.opcode = ECI_CMD_MFWD_FEVX_EH;
      return(fevx_eh_req.eci_word);
   endfunction : eci_gen_fevx_eh

   // also called sinv_2h
   function automatic [ECI_WORD_WIDTH-1:0] eci_gen_sinv_h
     (
      input logic [ECI_HREQID_WIDTH-1:0] hreq_id_i,
      input logic [ECI_DMASK_WIDTH-1:0]  dmask_i,
      input logic 			 ns_i,
      input logic [ECI_ADDR_WIDTH-1:0] 	 addr_i
      );
      eci_word_t sinv_h_req;
      // Opcode will not be filled 
      sinv_h_req.eci_word = eci_gen_mfwd(
					  .hreq_id_i(hreq_id_i),
					  .dmask_i(dmask_i),
					  .ns_i(ns_i),
					  .addr_i(addr_i)
					  );
      // Fill opcode 
      sinv_h_req.mfwd_generic.opcode = ECI_CMD_MFWD_SINV_H;
      return(sinv_h_req.eci_word);
   endfunction : eci_gen_sinv_h

   // also called fldrs_2h.e
   function automatic [ECI_WORD_WIDTH-1:0] eci_gen_fldrs_eh
     (
      input logic [ECI_HREQID_WIDTH-1:0] hreq_id_i,
      input logic [ECI_DMASK_WIDTH-1:0]  dmask_i,
      input logic 			 ns_i,
      input logic [ECI_ADDR_WIDTH-1:0] 	 addr_i
      );
      eci_word_t fldrs_eh_req;
      // Opcode will not be filled 
      fldrs_eh_req.eci_word = eci_gen_mfwd(
					  .hreq_id_i(hreq_id_i),
					  .dmask_i(dmask_i),
					  .ns_i(ns_i),
					  .addr_i(addr_i)
					  );
      // Fill opcode 
      fldrs_eh_req.mfwd_generic.opcode = ECI_CMD_MFWD_FLDRS_EH;
      return(fldrs_eh_req.eci_word);
   endfunction : eci_gen_fldrs_eh


   function automatic [ECI_WORD_WIDTH-1:0] eci_gen_psha
     (
      input logic [ECI_WORD_WIDTH-1:0] req_i
      );
      // Response for RLDT, RLDI
      eci_word_t eci_cmd;
      eci_word_t eci_resp;
      eci_cmd = eci_word_t'(req_i);
      eci_resp.eci_word = '0;
      eci_resp.psha_new.opcode = ECI_CMD_MRSP_PSHA;
      // RLDT, RLDI are mreq_0to10 type 
      eci_resp.psha_new.rreq_id = eci_cmd.mreq_0to10.rreq_id;
      eci_resp.psha_new.dmask = '1;
      eci_resp.psha_new.dirty = '0;
      eci_resp.psha_new.cache_line_index = eci_cmd.mreq_0to10.address[ECI_ADDR_WIDTH-1:7];
      eci_resp.psha_new.fillo = '0;
      return(eci_resp.eci_word);
   endfunction : eci_gen_psha

   function automatic [ECI_WORD_WIDTH-1:0] lcl_gen_lcia
     (
      input logic [ECI_WORD_WIDTH-1:0] req_i
      );
      // Respone for LCI.
      eci_word_t eci_cmd;
      eci_word_t eci_resp;
      eci_cmd = eci_word_t'(req_i);
      eci_resp.eci_word = '0;
      eci_resp.lcl_clean_inv_ack.opcode = LCL_CMD_MRSP_CLEAN_INV_ACK;
      eci_resp.lcl_clean_inv_ack.hreq_id = eci_cmd.lcl_clean_inv.hreq_id;
      eci_resp.lcl_clean_inv_ack.dmask = eci_cmd.lcl_clean_inv.dmask;
      eci_resp.lcl_clean_inv_ack.ns = 1'b1; // for now hardcoded to 1. //eci_cmd.lcl_clean_inv.ns; 
      eci_resp.lcl_clean_inv_ack.address = eci_cmd.lcl_clean_inv.address;
      return(eci_resp.eci_word);
   endfunction : lcl_gen_lcia

   function automatic [ECI_WORD_WIDTH-1:0] lcl_gen_lca
     (
      input logic [ECI_WORD_WIDTH-1:0] req_i
      );
      // Respone for LC.
      eci_word_t eci_cmd;
      eci_word_t eci_resp;
      eci_cmd = eci_word_t'(req_i);
      eci_resp.eci_word = '0;
      eci_resp.lcl_clean_ack.opcode = LCL_CMD_MRSP_CLEAN_ACK;
      eci_resp.lcl_clean_ack.hreq_id = eci_cmd.lcl_clean.hreq_id;
      eci_resp.lcl_clean_ack.dmask = '1;
      eci_resp.lcl_clean_ack.ns = eci_cmd.lcl_clean.ns;
      eci_resp.lcl_clean_ack.address = eci_cmd.lcl_clean.address;
      return(eci_resp.eci_word);
   endfunction : lcl_gen_lca
   
   // Include other relevant ECI Functions 
   // Removing include as it causes problems in vivado 2020.1
   // `include "eci_fn_defs.sv"
   // Copying the functions in this file here 
   // Respond with GSYNC for GSDN
   function automatic [(ECI_WORD_WIDTH-1) + 1:0] gsdn_for_gsync
     (
      input logic [ECI_WORD_WIDTH-1:0] req_i
      );
      eci_word_t eci_cmd;
      eci_word_t eci_resp;
      eci_cmd.eci_word = req_i; //casting to eci_word_t
      eci_resp.eci_word = '0;
      if( eci_cmd.generic_cmd.opcode == ECI_CMD_MREQ_GSYNC) begin
	 eci_resp.gsdn.opcode = ECI_CMD_MRSP_GSDN;
	 eci_resp.gsdn.ppvid  = eci_cmd.gsync.ppvid;
	 eci_resp.gsdn.rtad   = eci_cmd.gsync.rtad;
	 eci_resp.gsdn.ns     = 1'b1;  // Non secure 
      end
      return({eci_resp.eci_word});
   endfunction : gsdn_for_gsync
endpackage // eci_cmd_defs
`endif
