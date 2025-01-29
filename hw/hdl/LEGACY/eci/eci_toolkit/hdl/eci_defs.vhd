-------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

package eci_defs is
    subtype WORD is std_logic_vector(63 downto 0);
    type WORDS is array (integer range <>) of WORD;
    type WORDS_MUX_ARRAY is array (integer range <>) of WORDS(8 downto 0);
    type WORDS_ARRAY is array (integer range <>) of WORDS(16 downto 0);
    type VCS is array (integer range <>) of std_logic_vector(3 downto 0);
    type ECI_TYPE_MASKS is array (integer range <>) of std_logic_vector(4 downto 0);
    type VC_MUX_SIZES is array (integer range <>) of std_logic_vector(2 downto 0);
    type VC_BITFIELDS is array (integer range <>) of std_logic_vector(12 downto 2);
    type CLI_ARRAY is array (integer range <>) of std_logic_vector(32 downto 0);
    subtype ECI_COMMAND is std_logic_vector(4 downto 0);

    constant ECI_IREQ_IOBLD     : ECI_COMMAND := "00000";
    constant ECI_IREQ_IOBST     : ECI_COMMAND := "00001";
    constant ECI_IREQ_IOBSTA    : ECI_COMMAND := "00011";
    constant ECI_IREQ_SLILD     : ECI_COMMAND := "11100";
    constant ECI_IREQ_SLIST     : ECI_COMMAND := "11101";

    constant ECI_IRSP_IOBRSP    : ECI_COMMAND := "00000";
    constant ECI_IRSP_IOBACK    : ECI_COMMAND := "00001";
    constant ECI_IRSP_SLIRSP    : ECI_COMMAND := "00010";
    constant ECI_IRSP_IDLE      : ECI_COMMAND := "11111";

    constant ECI_MREQ_RLDD      : ECI_COMMAND := "00000";
    constant ECI_MREQ_RLDI      : ECI_COMMAND := "00001";
    constant ECI_MREQ_RLDT      : ECI_COMMAND := "00010";
    constant ECI_MREQ_RLDY      : ECI_COMMAND := "00011";
    constant ECI_MREQ_RLDWB     : ECI_COMMAND := "00100";
    constant ECI_MREQ_RLDX      : ECI_COMMAND := "00101";
    constant ECI_MREQ_RC2D_O    : ECI_COMMAND := "00110";
    constant ECI_MREQ_RC2D_S    : ECI_COMMAND := "00111";
    constant ECI_MREQ_RSTT      : ECI_COMMAND := "01000";
    constant ECI_MREQ_RSTY      : ECI_COMMAND := "01001";
    constant ECI_MREQ_RSTP      : ECI_COMMAND := "01010";
    constant ECI_MREQ_REOR      : ECI_COMMAND := "01011";
    constant ECI_MREQ_RADD      : ECI_COMMAND := "01101";
    constant ECI_MREQ_RINC      : ECI_COMMAND := "01110";
    constant ECI_MREQ_RDEC      : ECI_COMMAND := "01111";
    constant ECI_MREQ_RSWP      : ECI_COMMAND := "10000";
    constant ECI_MREQ_RSET      : ECI_COMMAND := "10001";
    constant ECI_MREQ_RCLR      : ECI_COMMAND := "10010";
    constant ECI_MREQ_RCAS      : ECI_COMMAND := "10011";
    constant ECI_MREQ_GINV      : ECI_COMMAND := "10100";
    constant ECI_MREQ_RCAS_O    : ECI_COMMAND := "10101";
    constant ECI_MREQ_RCAS_S    : ECI_COMMAND := "10110";
    constant ECI_MREQ_RSTC      : ECI_COMMAND := "10111";
    constant ECI_MREQ_GSYNC     : ECI_COMMAND := "11000";
    constant ECI_MREQ_RSTC_O    : ECI_COMMAND := "11001";
    constant ECI_MREQ_RSTC_S    : ECI_COMMAND := "11010";
    constant ECI_MREQ_RSMAX     : ECI_COMMAND := "11011";
    constant ECI_MREQ_RSMIN     : ECI_COMMAND := "11100";
    constant ECI_MREQ_RUMAX     : ECI_COMMAND := "11101";
    constant ECI_MREQ_RUMIN     : ECI_COMMAND := "11110";
    constant ECI_MREQ_IDLE      : ECI_COMMAND := "11111";

    constant ECI_MFWD_FLDRO_E   : ECI_COMMAND := "00000";
    constant ECI_MFWD_FLDRO_O   : ECI_COMMAND := "00001";
    constant ECI_MFWD_FLDRS_E   : ECI_COMMAND := "00010";
    constant ECI_MFWD_FLDRS_O   : ECI_COMMAND := "00011";
    constant ECI_MFWD_FLDRS_EH  : ECI_COMMAND := "00100";
    constant ECI_MFWD_FLDRS_OH  : ECI_COMMAND := "00101";
    constant ECI_MFWD_FLDT_E    : ECI_COMMAND := "00110";
    constant ECI_MFWD_FLDX_E    : ECI_COMMAND := "00111";
    constant ECI_MFWD_FLDX_O    : ECI_COMMAND := "01000";
    constant ECI_MFWD_FLDX_EH   : ECI_COMMAND := "01001";
    constant ECI_MFWD_FLDX_OH   : ECI_COMMAND := "01010";
    constant ECI_MFWD_FEVX_EH   : ECI_COMMAND := "01011";
    constant ECI_MFWD_FEVX_OH   : ECI_COMMAND := "01100";
    constant ECI_MFWD_SINV      : ECI_COMMAND := "01101";
    constant ECI_MFWD_SINV_H    : ECI_COMMAND := "01110";
    constant ECI_MFWD_IDLE      : ECI_COMMAND := "11111";

    constant ECI_MRSP_VICD      : ECI_COMMAND := "00000";
    constant ECI_MRSP_VICC      : ECI_COMMAND := "00001";
    constant ECI_MRSP_VICS      : ECI_COMMAND := "00010";
    constant ECI_MRSP_VICDHI    : ECI_COMMAND := "00011";
    constant ECI_MRSP_HAKD      : ECI_COMMAND := "00100";
    constant ECI_MRSP_HAKN_S    : ECI_COMMAND := "00101";
    constant ECI_MRSP_HAKI      : ECI_COMMAND := "00110";
    constant ECI_MRSP_HAKS      : ECI_COMMAND := "00111";
    constant ECI_MRSP_HAKV      : ECI_COMMAND := "01000";
    constant ECI_MRSP_PSHA      : ECI_COMMAND := "01001";
    constant ECI_MRSP_PEMD      : ECI_COMMAND := "01010";
    constant ECI_MRSP_PATH      : ECI_COMMAND := "01011";
    constant ECI_MRSP_PACK      : ECI_COMMAND := "01100";
    constant ECI_MRSP_P2DF      : ECI_COMMAND := "01101";
    constant ECI_MRSP_GSDN      : ECI_COMMAND := "11000";
    constant ECI_MRSP_IDLE      : ECI_COMMAND := "11111";

    constant ECI_MDLD_LNKD      : ECI_COMMAND := "10000";

    type ECI_CHANNEL is record
        data                : WORDS(8 downto 0);
        size                : std_logic_vector(2 downto 0);
        vc_no               : std_logic_vector(3 downto 0);
        valid               : std_logic;
    end record ECI_CHANNEL;

-- one-cycle sizes
    constant ECI_CHANNEL_SIZE_1     : std_logic_vector(2 downto 0) := "000";
    constant ECI_CHANNEL_SIZE_5     : std_logic_vector(2 downto 0) := "010";
    constant ECI_CHANNEL_SIZE_9     : std_logic_vector(2 downto 0) := "011";
-- two-cycle sizes, first cycle
    constant ECI_CHANNEL_SIZE_9_1   : std_logic_vector(2 downto 0) := "100";
-- two-cycle sizes, second cycle
    constant ECI_CHANNEL_SIZE_13_2  : std_logic_vector(2 downto 0) := "110";
    constant ECI_CHANNEL_SIZE_17_2  : std_logic_vector(2 downto 0) := "111";

    type ARRAY_ECI_CHANNELS is array (integer range <>) of ECI_CHANNEL;
    type INT_ARRAY is array (integer range <>) of integer;

-- AXI burst types
    constant AXI_BURST_FIXED    : std_logic_vector(1 downto 0) := "00";
    constant AXI_BURST_INCR     : std_logic_vector(1 downto 0) := "01";
    constant AXI_BURST_WRAP     : std_logic_vector(1 downto 0) := "10";

-- AXI sizes in bytes
    constant AXI_SIZE_1         : std_logic_vector(2 downto 0) := "000"; -- 8 bits
    constant AXI_SIZE_2         : std_logic_vector(2 downto 0) := "001"; -- 16 bits
    constant AXI_SIZE_4         : std_logic_vector(2 downto 0) := "010"; -- 32 bits
    constant AXI_SIZE_8         : std_logic_vector(2 downto 0) := "011"; -- 64 bits
    constant AXI_SIZE_16        : std_logic_vector(2 downto 0) := "100"; -- 128 bits
    constant AXI_SIZE_32        : std_logic_vector(2 downto 0) := "101"; -- 256 bits
    constant AXI_SIZE_64        : std_logic_vector(2 downto 0) := "110"; -- 512 bits
    constant AXI_SIZE_128       : std_logic_vector(2 downto 0) := "111"; -- 1024 bits
-- AXI BRESP and RRESP codes
    constant AXI_RESP_OKAY      : std_logic_vector(1 downto 0) := "00";
    constant AXI_RESP_EXOKAY    : std_logic_vector(1 downto 0) := "01";
    constant AXI_RESP_SLVERR    : std_logic_vector(1 downto 0) := "10";
    constant AXI_RESP_DECERR    : std_logic_vector(1 downto 0) := "11";

    type MOB_LO_VC is record
        data        : WORD;
        vc_no       : std_logic_vector(3 downto 0);
        valid       : std_logic;
    end record MOB_LO_VC;

    function vcs_to_vector(X : VCS)
        return std_logic_vector;
    function eci_unalias_cache_line_index(aliased_cli : std_logic_vector(32 downto 0))
        return std_logic_vector;
    function eci_alias_cache_line_index(cli : std_logic_vector(32 downto 0))
        return std_logic_vector;
    function vector_to_words(X : std_logic_vector)
        return WORDS;
    function words_to_vector(X : WORDS)
        return std_logic_vector;
    function or_reduce(X : std_logic_vector)
        return std_logic;
    function and_reduce(X : std_logic_vector)
        return std_logic;
    function count_bits(X : std_logic_vector)
        return integer;
    function to_std_logic(X : boolean)
        return std_logic;
    function resize(v: std_logic_vector; size : integer) return std_logic_vector;
    function eci_mreq_message(cmd : ECI_COMMAND; request_id : std_logic_vector(4 downto 0); dmask : std_logic_vector(3 downto 0); ns : std_logic; index : std_logic_vector(32 downto 0); fillo : std_logic_vector(1 downto 0))
        return std_logic_vector;
    function eci_mrsp_message(cmd : ECI_COMMAND; nxm : std_logic; request_id : std_logic_vector(4 downto 0); dmask : std_logic_vector(3 downto 0); ns : std_logic; dirty : std_logic_vector(3 downto 0); index : std_logic_vector(32 downto 0); fillo : std_logic_vector(1 downto 0))
        return std_logic_vector;
    function eci_message_get_dmask(header : std_logic_vector(63 downto 0)) return std_logic_vector;
    function eci_message_get_request_id(header : std_logic_vector(63 downto 0)) return std_logic_vector;

    function ECI_FILTER_VC_MASK(vcs : integer) return std_logic_vector;
    function ECI_FILTER_VC_MASK(vcs : INT_ARRAY) return std_logic_vector;
    constant ECI_FILTER_TYPE_UNUSED : std_logic_vector(4 downto 0) := (others => '0');
    constant ECI_FILTER_CLI_UNUSED  : std_logic_vector(32 downto 0) := (others => '0');
    end package;


package body eci_defs is
    function vcs_to_vector(X : VCS)
        return std_logic_vector is
        variable i : integer;
        variable tmp : std_logic_vector((X'high+1)*4-1 downto 0);
    begin
        for i in 0 to X'high loop
            tmp(i*4+3 downto i*4) := X(i);
        end loop;
        return tmp;
    end vcs_to_vector;

    function vector_to_words(X : std_logic_vector)
        return WORDS is
        variable i : integer;
        variable tmp : WORDS((X'length/64)-1 downto 0);
    begin
        for i in 0 to (X'length/64)-1 loop
            tmp(i) := X(i*64+63+X'low downto i*64+X'low);
        end loop;
        return tmp;
    end vector_to_words;

    function words_to_vector(X : WORDS)
        return std_logic_vector is
        variable i : integer;
        variable tX: WORDS(X'length-1 downto 0) := X; -- aligning
        variable tmp : std_logic_vector((tX'high+1)*64-1 downto 0);
    begin
        for i in 0 to tX'high loop
            tmp(i*64+63 downto i*64) := tX(i);
        end loop;
        return tmp;
    end words_to_vector;

    function eci_unalias_cache_line_index(aliased_cli : std_logic_vector(32 downto 0))
        return std_logic_vector is
        variable cli : std_logic_vector(32 downto 0);
    begin
        cli(32 downto 13) := aliased_cli(32 downto 13);
        cli(12 downto 8)  := aliased_cli(12 downto 8) xor aliased_cli(17 downto 13);
        cli(7 downto 5)   := aliased_cli(7 downto 5) xor aliased_cli(20 downto 18);
        cli(4 downto 3)   := aliased_cli(4 downto 3) xor aliased_cli(19 downto 18) xor aliased_cli(17 downto 16) xor aliased_cli(6 downto 5);
        cli(2 downto 0)   := aliased_cli(2 downto 0) xor aliased_cli(20 downto 18) xor aliased_cli(15 downto 13) xor aliased_cli(7 downto 5);
        return cli;
    end eci_unalias_cache_line_index;

    function eci_alias_cache_line_index(cli : std_logic_vector(32 downto 0))
        return std_logic_vector is
        variable aliased_cli : std_logic_vector(32 downto 0);
    begin
        aliased_cli(32 downto 13) := cli(32 downto 13);
        aliased_cli(12 downto 8) := cli(12 downto 8) xor cli(17 downto 13);
        aliased_cli(7 downto 5) := cli(7 downto 5) xor cli(20 downto 18);
        aliased_cli(4 downto 3) := cli(4 downto 3) xor cli(17 downto 16) xor cli(6 downto 5);
        aliased_cli(2 downto 0) := cli(2 downto 0) xor cli(15 downto 13) xor cli(7 downto 5);
        return aliased_cli;
    end eci_alias_cache_line_index;

    function or_reduce(X : std_logic_vector) return std_logic is
        variable i : integer;
    begin
        for i in X'low to X'high loop
            if X(i) = '1' then
                return '1';
            end if;
        end loop;
        return '0';
    end or_reduce;

    function and_reduce(X : std_logic_vector) return std_logic is
        variable i : integer;
    begin
        for i in X'low to X'high loop
            if X(i) = '0' then
                return '0';
            end if;
        end loop;
        return '1';
    end and_reduce;

    function count_bits(X : std_logic_vector) return integer is
        variable i, no : integer;
    begin
        no := 0;
        for i in X'low to X'high loop
            if X(i) = '1' then
                no := no + 1;
            end if;
        end loop;
        return no;
    end count_bits;

    function to_std_logic(X : boolean) return std_logic is
    begin
        if X then
            return '1';
        else
            return '0';
        end if;
    end to_std_logic;

    function resize(v: std_logic_vector; size : integer) return std_logic_vector is
        variable r : std_logic_vector(size-1 downto 0) := (others => '0');
    begin
        r(v'length-1 downto 0) := v;
        return r;
    end function;

    function eci_mreq_message(cmd : ECI_COMMAND; request_id : std_logic_vector(4 downto 0); dmask : std_logic_vector(3 downto 0); ns : std_logic; index : std_logic_vector(32 downto 0); fillo : std_logic_vector(1 downto 0)) return std_logic_vector is
        variable message : std_logic_vector(63 downto 0);
    begin
        message := cmd & "0000" & request_id & dmask & ns & "00000" & index & fillo & "00000";
        return message;
    end eci_mreq_message;
    
    function eci_mrsp_message(cmd : ECI_COMMAND; nxm : std_logic; request_id : std_logic_vector(4 downto 0); dmask : std_logic_vector(3 downto 0); ns : std_logic; dirty : std_logic_vector(3 downto 0); index : std_logic_vector(32 downto 0); fillo : std_logic_vector(1 downto 0)) return std_logic_vector is
        variable message : std_logic_vector(63 downto 0);
    begin
        message := cmd & nxm & "000" & request_id & dmask & ns & dirty & "0" & index & fillo & "00000";
        return message;
    end eci_mrsp_message;
    
    function eci_message_get_dmask(header : std_logic_vector(63 downto 0)) return std_logic_vector is
        variable dmask : std_logic_vector(3 downto 0);
    begin
        dmask := header(49 downto 46);
        return dmask;
    end eci_message_get_dmask;

    function eci_message_get_request_id(header : std_logic_vector(63 downto 0)) return std_logic_vector is
        variable request_id : std_logic_vector(4 downto 0);
    begin
        request_id := header(54 downto 50);
        return request_id;
    end eci_message_get_request_id;

    function ECI_FILTER_VC_MASK(vcs : integer) return std_logic_vector is
        variable mask : std_logic_vector(12 downto 2) := (others => '0');
    begin
        mask(vcs) := '1';
        return mask;
    end;
    
    function ECI_FILTER_VC_MASK(vcs : INT_ARRAY) return std_logic_vector is
        variable i : integer;
        variable mask : std_logic_vector(12 downto 2) := (others => '0');
    begin
        for i in vcs'LOW to vcs'HIGH loop
            mask(vcs(i)) := '1';
        end loop;
        return mask;
    end;
end package body eci_defs;
