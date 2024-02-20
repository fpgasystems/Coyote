-------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Simple AXI <-> ECI bridge
-- Converts read requests to ECI RLDT messages
-- Converts write requests to ECI RSTT messages
-- Read responses may come reordered
-- 32-byte, 64-byte (both no burst) or 128-byte (2-beat burst) aligned access

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity axi_eci_bridge is
generic (
    ID_WIDTH    : integer range 1 to 5 := 1
);
port (
    clk : in std_logic;

    eci_read_req        : out ECI_CHANNEL;
    eci_read_req_ready  : in  std_logic;

    eci_write_req       : out ECI_CHANNEL;
    eci_write_req_ready : in  std_logic;

    eci_rsp         : in ECI_CHANNEL;
    eci_rsp_ready   : out std_logic;

    p_axi_araddr    : in std_logic_vector(39 downto 0);
    p_axi_arlen     : in std_logic_vector( 7 downto 0);
    p_axi_arsize    : in std_logic_vector( 2 downto 0);
    p_axi_arburst   : in std_logic_vector( 1 downto 0);
    p_axi_arid      : in std_logic_vector (ID_WIDTH-1 to 0) := (others => '0');
    p_axi_arvalid   : in std_logic;
    p_axi_arready   : out std_logic;

    p_axi_rdata     : out std_logic_vector(511 downto 0);
    p_axi_rresp     : out std_logic_vector( 1 downto 0);
    p_axi_rlast     : out std_logic;
    p_axi_rid       : out std_logic_vector (ID_WIDTH-1 to 0);
    p_axi_rvalid    : out std_logic;
    p_axi_rready    : in std_logic;

    p_axi_awaddr    : in std_logic_vector (39 downto 0);
    p_axi_awlen     : in std_logic_vector ( 7 downto 0);
    p_axi_awsize    : in std_logic_vector ( 2 downto 0);
    p_axi_awburst   : in std_logic_vector ( 1 downto 0);
    p_axi_awid      : in std_logic_vector (ID_WIDTH-1 to 0) := (others => '0');
    p_axi_awvalid   : in std_logic;
    p_axi_awready   : out std_logic;

    p_axi_wdata     : in std_logic_vector (511 downto 0);
    p_axi_wstrb     : in std_logic_vector (63 downto 0);
    p_axi_wlast     : in std_logic;
    p_axi_wvalid    : in std_logic;
    p_axi_wready    : out std_logic;

    p_axi_bresp     : out std_logic_vector( 1 downto 0);
    p_axi_bid       : out std_logic_vector (ID_WIDTH-1 to 0);
    p_axi_bvalid    : out std_logic;
    p_axi_bready    : in std_logic
);
end axi_eci_bridge;

architecture behavioural of axi_eci_bridge is

signal ar_req_line  : std_logic_vector(32 downto 0);
signal aw_req_line  : std_logic_vector(32 downto 0);
signal wait_for_bready      : std_logic := '0';

signal eci_read_req_data0_b     : std_logic_vector(63 downto 0);
signal eci_write_req_data0_b    : std_logic_vector(63 downto 0);
signal p_axi_bvalid_b           : std_logic;

begin

-- AXI read request
ar_req_line <= eci_alias_cache_line_index(p_axi_araddr(39 downto 7));
eci_read_req.data(0) <= eci_read_req_data0_b;
eci_read_req_data0_b <=
    eci_mreq_message(ECI_MREQ_RLDT, resize(p_axi_arid, 5), "0001", '1', ar_req_line, "00") when p_axi_arsize = AXI_SIZE_32 and p_axi_arlen = "00000000" and p_axi_araddr(6 downto 0) = "0000000" else                     -- 1st quarter of a cache line
    eci_mreq_message(ECI_MREQ_RLDT, resize(p_axi_arid, 5), "0010", '1', ar_req_line, "01") when p_axi_arsize = AXI_SIZE_32 and p_axi_arlen = "00000000" and p_axi_araddr(6 downto 0) = "0100000" else                     -- 2nd quarter of a cache line
    eci_mreq_message(ECI_MREQ_RLDT, resize(p_axi_arid, 5), "0100", '1', ar_req_line, "10") when p_axi_arsize = AXI_SIZE_32 and p_axi_arlen = "00000000" and p_axi_araddr(6 downto 0) = "1000000" else                     -- 3rd quarter of a cache line
    eci_mreq_message(ECI_MREQ_RLDT, resize(p_axi_arid, 5), "1000", '1', ar_req_line, "11") when p_axi_arsize = AXI_SIZE_32 and p_axi_arlen = "00000000" and p_axi_araddr(6 downto 0) = "1100000" else                     -- 4th quarter of a cache line
    eci_mreq_message(ECI_MREQ_RLDT, resize(p_axi_arid, 5), "0011", '1', ar_req_line, "00") when p_axi_arsize = AXI_SIZE_64 and p_axi_arlen = "00000000" and p_axi_araddr(6 downto 0) = "0000000" else                     -- first half of a cache line
    eci_mreq_message(ECI_MREQ_RLDT, resize(p_axi_arid, 5), "1100", '1', ar_req_line, "10") when p_axi_arsize = AXI_SIZE_64 and p_axi_arlen = "00000000" and p_axi_araddr(6 downto 0) = "1000000" else                     -- second half of a cache line
    eci_mreq_message(ECI_MREQ_RLDT, resize(p_axi_arid, 5), "1111", '1', ar_req_line, "00") when p_axi_arsize = AXI_SIZE_64 and p_axi_arlen = "00000001" and p_axi_araddr(6 downto 0) = "0000000" else (others => '-');    -- full cache line
eci_read_req.valid <= '1' when p_axi_arvalid = '1' and
    ((p_axi_arsize = AXI_SIZE_32 and p_axi_arlen = "00000000" and p_axi_araddr(4 downto 0) = "00000") or
    (p_axi_arsize = AXI_SIZE_64 and p_axi_arlen = "00000000" and p_axi_araddr(5 downto 0) = "000000") or
    (p_axi_arsize = AXI_SIZE_64 and p_axi_arlen = "00000001" and p_axi_araddr(6 downto 0) = "0000000"))
    else '0';
eci_read_req.vc_no(0) <= not eci_read_req_data0_b(7); 
eci_read_req.vc_no(3 downto 1) <= "011";
eci_read_req.size <= ECI_CHANNEL_SIZE_1;
p_axi_arready <= eci_read_req_ready and p_axi_arvalid;

-- AXI write request
aw_req_line <= eci_alias_cache_line_index(p_axi_awaddr(39 downto 7));
eci_write_req.data(0) <= eci_write_req_data0_b;
eci_write_req_data0_b <=
    eci_mreq_message(ECI_MREQ_RSTT, resize(p_axi_awid, 5), "0001", '1', aw_req_line, "00") when p_axi_awsize = AXI_SIZE_32 and p_axi_awlen = "00000000" and p_axi_awaddr(6 downto 0) = "0000000" else                     -- 1st quarter of a cache line
    eci_mreq_message(ECI_MREQ_RSTT, resize(p_axi_awid, 5), "0010", '1', aw_req_line, "01") when p_axi_awsize = AXI_SIZE_32 and p_axi_awlen = "00000000" and p_axi_awaddr(6 downto 0) = "0100000" else                     -- 2nd quarter of a cache line
    eci_mreq_message(ECI_MREQ_RSTT, resize(p_axi_awid, 5), "0100", '1', aw_req_line, "10") when p_axi_awsize = AXI_SIZE_32 and p_axi_awlen = "00000000" and p_axi_awaddr(6 downto 0) = "1000000" else                     -- 3rd quarter of a cache line
    eci_mreq_message(ECI_MREQ_RSTT, resize(p_axi_awid, 5), "1000", '1', aw_req_line, "11") when p_axi_awsize = AXI_SIZE_32 and p_axi_awlen = "00000000" and p_axi_awaddr(6 downto 0) = "1100000" else                     -- 4th quarter of a cache line
    eci_mreq_message(ECI_MREQ_RSTT, resize(p_axi_awid, 5), "0011", '1', aw_req_line, "00") when p_axi_awsize = AXI_SIZE_64 and p_axi_awlen = "00000000" and p_axi_awaddr(6 downto 0) = "0000000" else                     -- 1st half of a cache line
    eci_mreq_message(ECI_MREQ_RSTT, resize(p_axi_awid, 5), "1100", '1', aw_req_line, "10") when p_axi_awsize = AXI_SIZE_64 and p_axi_awlen = "00000000" and p_axi_awaddr(6 downto 0) = "1000000" else                     -- 2nd half of a cache line
    eci_mreq_message(ECI_MREQ_RSTT, resize(p_axi_awid, 5), "1111", '1', aw_req_line, "00") when p_axi_awsize = AXI_SIZE_64 and p_axi_awlen = "00000001" and p_axi_awaddr(6 downto 0) = "0000000" else (others => '-');    -- full cache line
eci_write_req.data(8 downto 1) <= vector_to_words(p_axi_wdata);
eci_write_req.valid <= '1' when p_axi_awvalid = '1' and p_axi_wvalid = '1' and wait_for_bready = '0' and
    ((p_axi_awsize = AXI_SIZE_32 and p_axi_awlen = "00000000" and p_axi_awaddr(4 downto 0) = "00000") or
    (p_axi_awsize = AXI_SIZE_64 and p_axi_awlen = "00000000" and p_axi_awaddr(5 downto 0) = "000000") or
    (p_axi_awsize = AXI_SIZE_64 and p_axi_awlen = "00000001" and p_axi_awaddr(6 downto 0) = "0000000"))
    else '0';
eci_write_req.vc_no(0) <= not eci_write_req_data0_b(7); 
eci_write_req.vc_no(3 downto 1) <= "001";
eci_write_req.size <=
    ECI_CHANNEL_SIZE_5 when p_axi_awsize = AXI_SIZE_32 and p_axi_awlen = "00000000" and p_axi_wlast = '1' else                      -- quarter of a cache line, one beat
    ECI_CHANNEL_SIZE_9 when p_axi_awsize = AXI_SIZE_64 and p_axi_awlen = "00000000" and p_axi_wlast = '1' else                      -- half of a cache line, one beat
    ECI_CHANNEL_SIZE_9_1 when p_axi_awsize = AXI_SIZE_64 and p_axi_awlen = "00000001" and p_axi_wlast = '0' else                    -- full cache line, first beat
    ECI_CHANNEL_SIZE_17_2 when p_axi_awsize = AXI_SIZE_64 and p_axi_awlen = "00000001" and p_axi_wlast = '1' else (others => '-');  -- full cache line, second beat

p_axi_awready <= eci_write_req_ready and p_axi_awvalid and p_axi_wvalid and p_axi_wlast and not wait_for_bready;
p_axi_wready <= eci_write_req_ready and p_axi_awvalid and p_axi_wvalid and not wait_for_bready;
p_axi_bresp <= AXI_RESP_OKAY;
p_axi_bid <= p_axi_awid;
p_axi_bvalid_b <= (eci_write_req_ready and p_axi_awvalid and p_axi_wvalid and p_axi_wlast) or wait_for_bready;
p_axi_bvalid <= p_axi_bvalid_b;

-- ECI read response
eci_rsp_ready <= 
    '1' when eci_rsp.valid = '1' and p_axi_rready = '1' and eci_rsp.size /= ECI_CHANNEL_SIZE_9_1 else '0';
p_axi_rvalid <= '1' when eci_rsp.valid = '1' else '0';
p_axi_rresp <= AXI_RESP_OKAY when eci_rsp.valid = '1' else AXI_RESP_SLVERR;
p_axi_rdata <= words_to_vector(eci_rsp.data(8 downto 1));
p_axi_rid <= eci_message_get_request_id(eci_rsp.data(0))(ID_WIDTH-1 downto 0);
p_axi_rlast <= '0' when eci_rsp.size = ECI_CHANNEL_SIZE_9_1 else '1';

i_process: process(clk)
begin
    if rising_edge(clk) then
        if p_axi_bvalid_b = '1' and p_axi_bready = '0' then
            wait_for_bready <= '1';
        elsif p_axi_bvalid_b = '1' and p_axi_bready = '1' and wait_for_bready = '0' then
            wait_for_bready <= '0';
        end if;
    end if;
end process;

end behavioural;
