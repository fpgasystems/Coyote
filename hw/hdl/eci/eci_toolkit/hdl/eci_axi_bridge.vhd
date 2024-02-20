-------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Simple ECI <-> AXI bridge
-- Full cache lines, 128-byte transfers
-- AXI addresses are unaliased
-- Converts incoming RLDD/RLDX/RLDI requests to AXI read requests
-- Converts incoming VICD messages to AXI write requests

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_axi_bridge is
port (
    clk : in std_logic;

    eci_req         : in ECI_CHANNEL;
    eci_req_ready   : buffer std_logic;
    eci_rsp         : buffer ECI_CHANNEL;
    eci_rsp_ready   : in  std_logic;

    p_axi_arid      : buffer std_logic_vector( 5 downto 0);
    p_axi_araddr    : buffer std_logic_vector(39 downto 0);
    p_axi_arlen     : out std_logic_vector( 7 downto 0);
    p_axi_arsize    : out std_logic_vector( 2 downto 0);
    p_axi_arburst   : out std_logic_vector( 1 downto 0);
    p_axi_arlock    : out std_logic;
    p_axi_arcache   : out std_logic_vector( 3 downto 0);
    p_axi_arprot    : out std_logic_vector( 2 downto 0);
    p_axi_arvalid   : buffer std_logic;
    p_axi_arready   : in std_logic;
    p_axi_rid       : in std_logic_vector( 5 downto 0);
    p_axi_rdata     : in std_logic_vector(511 downto 0);
    p_axi_rresp     : in std_logic_vector( 1 downto 0);
    p_axi_rlast     : in std_logic;
    p_axi_rvalid    : in std_logic;
    p_axi_rready    : buffer std_logic;

    p_axi_awid      : out std_logic_vector ( 5 downto 0);
    p_axi_awaddr    : out std_logic_vector (39 downto 0);
    p_axi_awlen     : out std_logic_vector ( 7 downto 0);
    p_axi_awsize    : out std_logic_vector ( 2 downto 0);
    p_axi_awburst   : out std_logic_vector ( 1 downto 0);
    p_axi_awlock    : out std_logic;
    p_axi_awcache   : out std_logic_vector ( 3 downto 0);
    p_axi_awprot    : out std_logic_vector ( 2 downto 0);
    p_axi_awvalid   : out std_logic;
    p_axi_awready   : in std_logic ;
    p_axi_wdata     : out std_logic_vector (511 downto 0);
    p_axi_wstrb     : out std_logic_vector (63 downto 0);
    p_axi_wlast     : out std_logic;
    p_axi_wvalid    : out std_logic;
    p_axi_wready    : in std_logic;
    p_axi_bid       : in std_logic_vector( 5 downto 0);
    p_axi_bresp     : in std_logic_vector( 1 downto 0);
    p_axi_bvalid    : in std_logic;
    p_axi_bready    : out std_logic
);
end eci_axi_bridge;

architecture behavioural of eci_axi_bridge is

-- Incoming read requests in the clk_eci domain
signal req_line     : std_logic_vector(32 downto 0);
signal req_id       : std_logic_vector(4 downto 0);
signal req_dmask    : std_logic_vector(3 downto 0);
signal req_fillo    : std_logic_vector(1 downto 0);

signal half_cacheline           : WORDS(7 downto 0);
signal full_cacheline           : WORDS(15 downto 0);
signal full_cacheline_aligned   : WORDS(15 downto 0);

signal rsp_phase        : integer := 0;
signal rsp_phase_int    : std_logic_vector(1 downto 0);

signal payload : std_logic_vector(1023 downto 0);

signal rsp_line     : std_logic_vector(32 downto 0);
signal rsp_id       : std_logic_vector(4 downto 0);
signal rsp_axi_id   : std_logic_vector(5 downto 0);
signal rsp_dmask    : std_logic_vector(3 downto 0);
signal rsp_fillo    : std_logic_vector(1 downto 0);

type CLI_ARRAY is array (integer range <>) of std_logic_vector(43 downto 0); -- dmask fillo id line_index
signal cli          : CLI_ARRAY(63 downto 0);
signal cli_used     : std_logic_vector(63 downto 0) := (others => '0');
signal free_cli     : integer;

signal addr         : unsigned(29 downto 0) := (others => '0');

signal p_axi_arvalid_b  : std_logic;
signal p_axi_awvalid_b  : std_logic;
signal p_axi_aw_done    : std_logic := '0';
signal p_axi_wvalid_b   : std_logic;
signal p_axi_w_done     : std_logic := '0';
signal p_axi_wlast_b    : std_logic;

signal got_rldd, got_empty_rldd, got_vicd   : std_logic;

function find_first_zero(m: std_logic_vector) return integer is
begin
    for n in m'reverse_range loop
        if m(n) = '0' then
            return n;
        end if;
    end loop;
    return 0;
end function find_first_zero;

type WORD_NO_ARRAY is array (integer range <>) of integer;
function align_cacheline(cacheline: WORDS(15 downto 0); dmask: std_logic_vector(3 downto 0); fillo: std_logic_vector(1 downto 0)) return WORDS is
    variable aligned : WORDS(15 downto 0) := (others => (others => '-'));
    variable i, j, t : integer;
    variable words_no: WORD_NO_ARRAY(0 to 3) := (0, 1, 2, 3); 
begin
    if fillo(0) = '1' then
        t := words_no(0);
        words_no(0) := words_no(1);
        words_no(1) := t; 
        t := words_no(2);
        words_no(2) := words_no(3);
        words_no(3) := t; 
    end if;
    if fillo(1) = '1' then
        t := words_no(0);
        words_no(0) := words_no(2);
        words_no(2) := t; 
        t := words_no(1);
        words_no(1) := words_no(3);
        words_no(3) := t; 
    end if;
    j := 0;
    for i in 0 to 3 loop
        if dmask(words_no(i)) = '1' then
            t := words_no(i);
            aligned(j*4) := cacheline(t*4);
            aligned(j*4 + 1) := cacheline(t*4 + 1);
            aligned(j*4 + 2) := cacheline(t*4 + 2);
            aligned(j*4 + 3) := cacheline(t*4 + 3);
            j := j + 1;
        end if;
    end loop;
    return aligned;
end function align_cacheline;

begin

req_line <= eci_req.data(0)(39 downto 7);
req_id <= eci_req.data(0)(54 downto 50);
req_dmask <= eci_req.data(0)(49 downto 46);
req_fillo <= eci_req.data(0)(6 downto 5);
-- got RLDD or RLDI or RLDX
got_rldd <= '1' when eci_req.valid = '1' and eci_req.vc_no(3 downto 1) = "011" and (eci_req.data(0)(63 downto 59) = ECI_MREQ_RLDD or eci_req.data(0)(63 downto 59) = ECI_MREQ_RLDI or eci_req.data(0)(63 downto 59) = ECI_MREQ_RLDX) and req_dmask /= "0000" else '0';
got_empty_rldd <= '1' when eci_req.valid = '1' and eci_req.vc_no(3 downto 1) = "011" and (eci_req.data(0)(63 downto 59) = ECI_MREQ_RLDD or eci_req.data(0)(63 downto 59) = ECI_MREQ_RLDI or eci_req.data(0)(63 downto 59) = ECI_MREQ_RLDX) and req_dmask = "0000" else '0';
-- got VICD
got_vicd <= '1' when eci_req.valid = '1' and eci_req.vc_no(3 downto 1) = "010" and eci_req.data(0)(63 downto 59) = ECI_MRSP_VICD else '0';

-- first free request id
free_cli <= find_first_zero(cli_used);

p_axi_arid          <= std_logic_vector(to_unsigned(free_cli, 6));
p_axi_araddr        <= eci_unalias_cache_line_index(req_line) & "0000000";
p_axi_arlen         <= "00000001"; -- 2 beats
p_axi_arsize        <= "110"; -- 64 bytes
p_axi_arburst       <= "01"; -- INCR
p_axi_arlock        <= '0';
p_axi_arcache       <= "0000";
p_axi_arprot        <= "000";
p_axi_arvalid_b     <= eci_req.valid and got_rldd and not and_reduce(cli_used);
p_axi_arvalid       <= p_axi_arvalid_b;

rsp_phase_int <= std_logic_vector(to_unsigned(rsp_phase, 2));

p_axi_awid          <= (others => '0');
p_axi_awaddr        <= eci_unalias_cache_line_index(req_line) & "0000000";
p_axi_awlen         <= "00000001"; -- 2 beats
p_axi_awsize        <= "110"; -- 64 bytes
p_axi_awburst       <= "01"; -- INCR
p_axi_awlock        <= '0';
p_axi_awcache       <= "0000";
p_axi_awprot        <= "000";
p_axi_awvalid_b     <= eci_req.valid and got_vicd and not p_axi_aw_done;
p_axi_awvalid       <= p_axi_awvalid_b;

p_axi_wdata         <= words_to_vector(eci_req.data(8 downto 1));
p_axi_wstrb         <= (others => '1');
p_axi_wlast_b       <= '1' when eci_req.size(2 downto 1) = "11" else '0';
p_axi_wlast         <= p_axi_wlast_b;
p_axi_wvalid_b      <= eci_req.valid and got_vicd and not p_axi_w_done;
p_axi_wvalid        <= p_axi_wvalid_b;

p_axi_bready        <= '1';

eci_req_ready       <= (eci_req.valid and not got_rldd and not got_empty_rldd and not got_vicd)
    or (eci_req.valid and got_rldd and p_axi_arready and p_axi_arvalid_b) or to_std_logic(rsp_phase = 1 and eci_rsp_ready = '1' and eci_rsp.size = ECI_CHANNEL_SIZE_1)
    or (eci_req.valid and got_vicd and (not eci_req.size(2) or not eci_req.size(1) or ((p_axi_awvalid_b and p_axi_awready) or p_axi_aw_done)) and ((p_axi_wvalid_b and p_axi_wready) or p_axi_w_done));

full_cacheline <= vector_to_words(p_axi_rdata) & half_cacheline;
full_cacheline_aligned <= align_cacheline(full_cacheline, rsp_dmask, rsp_fillo);
eci_rsp.data(8 downto 1) <= full_cacheline_aligned(7 downto 0) when rsp_phase = 1 else full_cacheline_aligned(15 downto 8);


eci_rsp.data(0) <= eci_mrsp_message(ECI_MRSP_PEMD, '0', rsp_id, rsp_dmask, '1', "0000", rsp_line, rsp_fillo);

eci_rsp.vc_no(3 downto 1) <= "101" when rsp_dmask = "0000" else "010"; -- choose proper VC based on payload (4 or 10)
eci_rsp.vc_no(0) <= not rsp_line(0); -- choose proper VC based on parity (4 or 5)

eci_rsp.valid <= '1' when (rsp_phase = 1 and p_axi_rvalid = '1' and eci_rsp.size /= ECI_CHANNEL_SIZE_1) or (rsp_phase = 1 and eci_rsp.size = ECI_CHANNEL_SIZE_1) or rsp_phase = 2 else '0';
p_axi_rready <= '1' when rsp_phase = 0 else '0' when rsp_phase = 2 or (rsp_phase = 1 and eci_rsp.size = ECI_CHANNEL_SIZE_1) else eci_rsp_ready;

--- End of DDR read -> ECI TX path
cache_line_numbers : process(clk)
begin
    if rising_edge(clk) then
        if p_axi_arvalid_b = '1' and p_axi_arready = '1' then -- allocate request ID
            cli_used(free_cli) <= '1';
            cli(free_cli) <= req_dmask & req_fillo & req_id & req_line;
            if addr(8 downto 7) = "00" then
                addr <= addr + 384;
            elsif addr(8 downto 7) = "11" then
                addr <= addr - 128;
            elsif addr(8 downto 7) = "10" then
                addr <= addr + 384;
            else -- "01"
                addr <= addr - 128;
            end if;
        end if;

        if p_axi_rvalid = '1' and rsp_phase = 0 then
            rsp_line <= cli(to_integer(unsigned(p_axi_rid)))(32 downto 0);
            rsp_id <= cli(to_integer(unsigned(p_axi_rid)))(37 downto 33);
            rsp_axi_id <= p_axi_rid;
            rsp_fillo <= cli(to_integer(unsigned(p_axi_rid)))(39 downto 38);
            rsp_dmask <= cli(to_integer(unsigned(p_axi_rid)))(43 downto 40);
            half_cacheline <= vector_to_words(p_axi_rdata);
            rsp_phase <= 1;
            case count_bits(cli(to_integer(unsigned(p_axi_rid)))(43 downto 40)) is
                when 1 =>
                    eci_rsp.size <= ECI_CHANNEL_SIZE_5;
                when 2 =>
                    eci_rsp.size <= ECI_CHANNEL_SIZE_9;
                when others =>
                    eci_rsp.size <= ECI_CHANNEL_SIZE_9_1;
            end case;
        elsif got_empty_rldd = '1' and rsp_phase = 0 then
            rsp_line <= req_line;
            rsp_id <= req_id;
            rsp_fillo <= "00";
            rsp_dmask <= "0000";
            rsp_phase <= 1;
            eci_rsp.size <= ECI_CHANNEL_SIZE_1;
        end if;

        if p_axi_rvalid = '1' and eci_rsp_ready = '1' and p_axi_rlast = '1' and rsp_phase = 1 and eci_rsp.size /= ECI_CHANNEL_SIZE_1 then
            if count_bits(rsp_dmask) > 2 then -- 13 or 17 words
                if count_bits(rsp_dmask) = 3 then
                    eci_rsp.size <= ECI_CHANNEL_SIZE_13_2;
                else
                    eci_rsp.size <= ECI_CHANNEL_SIZE_17_2;
                end if;
                rsp_phase <= 2;
            else
                cli_used(to_integer(unsigned(rsp_axi_id))) <= '0';
                rsp_phase <= 0;
            end if;
        elsif eci_rsp_ready = '1' and rsp_phase = 1 and eci_rsp.size = ECI_CHANNEL_SIZE_1 then
            rsp_phase <= 0;
        end if;

        if eci_rsp_ready = '1' and rsp_phase = 2 then -- free request ID
            cli_used(to_integer(unsigned(rsp_axi_id))) <= '0';
            rsp_phase <= 0;
        end if;

        if p_axi_awvalid_b = '1' and p_axi_awready = '1' and (eci_req_ready = '0' or eci_req.size(2 downto 1) /= "11") then
            p_axi_aw_done <= '1';
        end if;
        if p_axi_wvalid_b = '1' and p_axi_wready = '1' and eci_req_ready = '0' and eci_req.size(2 downto 1) = "11" then
            p_axi_w_done <= '1';
        end if;
        if eci_req_ready = '1' and eci_req.size(2 downto 1) = "11" then
            p_axi_aw_done <= '0';
            p_axi_w_done <= '0';
        end if;
    end if;
end process;

end behavioural;
