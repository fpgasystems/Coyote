
`ifndef ECI_GET_NUM_WORDS_IN_PKT_C_SV
`define ECI_GET_NUM_WORDS_IN_PKT_C_SV

import eci_cmd_defs::*;

module eci_get_num_words_in_pkt_c (
    input  eci_word_t eci_command,
    output logic [ECI_PACKET_SIZE_WIDTH-1:0] num_words_in_pkt 
);

   logic [ECI_PACKET_SIZE_WIDTH-1:0] num_words;

   eci_dmask_t this_dmask;
   logic [ECI_SCL_WIDTH-1:0] this_num_scl;

   assign this_dmask   = eci_command.generic_cmd.dmask;
   assign this_num_scl = get_scl_from_dmask( this_dmask );
   
   assign num_words_in_pkt = get_num_words_from_scl( this_num_scl );

endmodule // eci_get_num_words_in_pkt


`endif
