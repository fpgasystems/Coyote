----------------------------------------------------------------------------------
-- Copyright (c) 2022 ETH Zurich.
-- All rights reserved.
--
-- This file is distributed under the terms in the attached LICENSE file.
-- If you do not find this file, copies can be found by writing to:
-- ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group
-------------------------------------------------------------------------------
-- Handle VC0, VC1 and VC13 messages
-- Translate ECI I/O requests into AXI-Lite requests
-- Handle ECI configuartion registers

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.eci_defs.all;

entity eci_io_bridge_lite is
generic (
    SECOND_LINK_ACTIVE : integer := 1
);
port (
    clk : in std_logic;
    reset : in std_logic;

    -- Link 1 interface
    link1_in            : in ECI_CHANNEL;
    link1_in_ready      : buffer std_logic;
    link1_out           : buffer ECI_CHANNEL;
    link1_out_ready     : in std_logic;

    -- Link 2 interface
    link2_in            : in ECI_CHANNEL;
    link2_in_ready      : buffer std_logic;
    link2_out           : buffer ECI_CHANNEL;
    link2_out_ready     : in std_logic;

    -- AXI Lite master interface IO addr space
    m_io_axil_awaddr  : out std_logic_vector(43 downto 0);
    m_io_axil_awvalid : buffer std_logic;
    m_io_axil_awready : in  std_logic;

    m_io_axil_wdata   : out std_logic_vector(63 downto 0);
    m_io_axil_wstrb   : out std_logic_vector(7 downto 0);
    m_io_axil_wvalid  : buffer std_logic;
    m_io_axil_wready  : in  std_logic;

    m_io_axil_bresp   : in  std_logic_vector(1 downto 0);
    m_io_axil_bvalid  : in  std_logic;
    m_io_axil_bready  : buffer std_logic;

    m_io_axil_araddr  : out std_logic_vector(43 downto 0);
    m_io_axil_arvalid : buffer std_logic;
    m_io_axil_arready : in  std_logic;

    m_io_axil_rdata   : in std_logic_vector(63 downto 0);
    m_io_axil_rresp   : in std_logic_vector(1 downto 0);
    m_io_axil_rvalid  : in std_logic;
    m_io_axil_rready  : buffer std_logic;

    -- AXI Lite slave interface IO addr space
    s_io_axil_awaddr        : in std_logic_vector(43 downto 0);
    s_io_axil_awvalid       : in std_logic;
    s_io_axil_awready       : out std_logic;
    s_io_axil_wdata         : in std_logic_vector(63 downto 0);
    s_io_axil_wstrb         : in std_logic_vector(7 downto 0);
    s_io_axil_wvalid        : in std_logic;
    s_io_axil_wready        : out std_logic;
    s_io_axil_bresp         : out std_logic_vector(1 downto 0);
    s_io_axil_bvalid        : out std_logic;
    s_io_axil_bready        : in std_logic;
    s_io_axil_araddr        : in std_logic_vector(43 downto 0);
    s_io_axil_arvalid       : in std_logic;
    s_io_axil_arready       : out  std_logic;
    s_io_axil_rdata         : out std_logic_vector(63 downto 0);
    s_io_axil_rresp         : out std_logic_vector(1 downto 0);
    s_io_axil_rvalid        : out std_logic;
    s_io_axil_rready        : in std_logic;

    -- ICAP AXI Lite master interface
    m_icap_axi_awaddr   : out std_logic_vector(8 downto 0);
    m_icap_axi_awvalid  : buffer std_logic;
    m_icap_axi_awready  : in  std_logic;

    m_icap_axi_wdata    : out std_logic_vector(31 downto 0);
    m_icap_axi_wstrb    : out std_logic_vector(3 downto 0);
    m_icap_axi_wvalid   : buffer std_logic;
    m_icap_axi_wready   : in  std_logic;

    m_icap_axi_bresp    : in  std_logic_vector(1 downto 0);
    m_icap_axi_bvalid   : in  std_logic;
    m_icap_axi_bready   : buffer std_logic;

    m_icap_axi_araddr   : out std_logic_vector(8 downto 0);
    m_icap_axi_arvalid  : buffer std_logic;
    m_icap_axi_arready  : in  std_logic;

    m_icap_axi_rdata    : in std_logic_vector(31 downto 0);
    m_icap_axi_rresp    : in std_logic_vector(1 downto 0);
    m_icap_axi_rvalid   : in std_logic;
    m_icap_axi_rready   : buffer std_logic
);
end eci_io_bridge_lite;

architecture Behavioral of eci_io_bridge_lite is

-- Registers
signal rlk_lnk_data        : WORDS(1 downto 0);

-- Link 1 request word before buffer
signal link1_in_vc0        : std_logic_vector(63 downto 0);
signal link1_in_vc0_valid  : std_logic;
signal link1_in_vc0_ready  : std_logic;

-- Link 2 request word before buffer
signal link2_in_vc0        : std_logic_vector(63 downto 0);
signal link2_in_vc0_valid  : std_logic;
signal link2_in_vc0_ready  : std_logic;

signal link1_in_vc_mcd        : std_logic_vector(63 downto 0);
signal link1_in_vc_mcd_valid  : std_logic;

signal link2_in_vc_mcd        : std_logic_vector(63 downto 0);
signal link2_in_vc_mcd_valid  : std_logic;

-- Unified request buffer
signal in_vc0          : std_logic_vector(63 downto 0);
signal in_vc0_valid    : std_logic;

signal out_data              : std_logic_vector(63 downto 0);
signal out_vc_no        : std_logic_vector(3 downto 0);
signal out_valid        : std_logic;
signal out_ready        : std_logic;
signal out_link         : std_logic;

signal busy : std_logic; -- Processing a request, not ready to accept a new one

signal request          : WORDS(0 to 1);
signal request_ready    : std_logic_vector(0 to 1);
signal request_link     : std_logic;

signal second_cycle : std_logic; -- Process the second word of a request

-- Choose and use one link to process the whole request
signal active_link      : std_logic;
signal last_active_link : std_logic;
signal hold_link        : std_logic;

signal second_write     : std_logic := '0';
signal out_buffer       : std_logic_vector(63 downto 0);
signal out_buffer_vc_no : std_logic_vector(3 downto 0);

-- convert IOB/SL word size/select
function eci_io_word_to_bitmap(codeword : std_logic_vector(3 downto 0))
    return std_logic_vector is
    variable bitmap : std_logic_vector(7 downto 0);
begin
    case codeword is
        when "0000" => bitmap := "00000001";
        when "0001" => bitmap := "00000010";
        when "0010" => bitmap := "00000100";
        when "0011" => bitmap := "00001000";
        when "0100" => bitmap := "00010000";
        when "0101" => bitmap := "00100000";
        when "0110" => bitmap := "01000000";
        when "0111" => bitmap := "10000000";
        when "1000" => bitmap := "00000011";
        when "1001" => bitmap := "00001100";
        when "1010" => bitmap := "00110000";
        when "1011" => bitmap := "11000000";
        when "1100" => bitmap := "00001111";
        when "1101" => bitmap := "11110000";
        when "1110" => bitmap := "11111111";
        when "1111" => bitmap := "11111111";
    end case;
    return bitmap;
end eci_io_word_to_bitmap;

begin

link1_in_vc0       <= link1_in.data(0);
link1_in_vc0_valid <= link1_in.valid when link1_in.vc_no = "0000" else '0';
link1_in_vc_mcd    <= link1_in.data(0);
link1_in_vc_mcd_valid <= link1_in.valid when link1_in.vc_no = "1101" else '0';
link1_in_ready <=  link1_in_vc0_ready when link1_in.vc_no = "0000" else '1';

link2_in_vc0       <= link2_in.data(0);
link2_in_vc0_valid <= link2_in.valid when link2_in.vc_no = "0000" else '0';
link2_in_vc_mcd    <= link2_in.data(0);
link2_in_vc_mcd_valid <= link2_in.valid when link2_in.vc_no = "1101" else '0';
link2_in_ready <=  link2_in_vc0_ready when link2_in.vc_no = "0000" else '1';

link1_out.data(0) <= out_data;
link2_out.data(0) <= out_data;
link1_out.size  <= ECI_CHANNEL_SIZE_1;
link2_out.size  <= ECI_CHANNEL_SIZE_1;
link1_out.vc_no <= out_vc_no;
link2_out.vc_no <= out_vc_no;
link1_out.valid <= out_valid when out_link = '0' else '0';
link2_out.valid <= out_valid when out_link = '1' else '0';
out_ready <=    link1_out_ready when out_link = '0' else
                link2_out_ready;

active_link <= last_active_link when hold_link = '1' else link2_in_vc0_valid and not link1_in_vc0_valid;
in_vc0 <= link1_in_vc0 when active_link = '0' else link2_in_vc0;
in_vc0_valid <= link1_in_vc0_valid when active_link = '0' else link2_in_vc0_valid;

busy <= request_ready(0) or link1_out.valid or link2_out.valid
    or m_io_axil_arvalid or m_io_axil_rready or m_io_axil_awvalid or m_io_axil_wvalid
    or m_io_axil_bready
    or m_icap_axi_arvalid or m_icap_axi_rready or m_icap_axi_awvalid or m_icap_axi_wvalid
    or m_icap_axi_bready;

hold_link <= busy or second_cycle; -- keep reading from the same link

process_vcs : process(clk)
    variable address : std_logic_vector(43 downto 0);
begin
    if rising_edge(clk) then
        if reset = '1' then
            link1_in_vc0_ready <= '0';
            link2_in_vc0_ready <= '0';

            request_ready <= "00";

            second_cycle <= '0';

            m_io_axil_awvalid <= '0';
            m_io_axil_wvalid  <= '0';
            m_io_axil_bready  <= '0';
            m_io_axil_arvalid <= '0';
            m_io_axil_rready  <= '0';

            m_icap_axi_awvalid <= '0';
            m_icap_axi_wvalid  <= '0';
            m_icap_axi_bready  <= '0';
            m_icap_axi_arvalid <= '0';
            m_icap_axi_rready  <= '0';

            second_write <= '0';
        else
            last_active_link <= active_link;

            if link1_in_vc_mcd_valid = '1' then -- incoming link 1 discovery message
                rlk_lnk_data(0) <= "10000000" & link1_in_vc_mcd(58 downto 3);
            end if;
            if link2_in_vc_mcd_valid = '1' then -- incoming link 2 discovery message
                rlk_lnk_data(1) <= "10000000" & link2_in_vc_mcd(58 downto 3);
            end if;

            if busy = '0' and in_vc0_valid = '1' and link1_in_vc0_ready = '0' and link2_in_vc0_ready = '0' then -- there is a request
                if active_link = '0' then
                    link1_in_vc0_ready <= '1';
                else
                    link2_in_vc0_ready <= '1';
                end if;
                if second_cycle = '0' then -- first word
                    if in_vc0(63 downto 59) = ECI_IREQ_IOBLD or
                        in_vc0(63 downto 59) = ECI_IREQ_SLILD then -- IO read
                        request(0) <= in_vc0;
                        request_ready <= "10";
                        request_link <= active_link;
                    elsif in_vc0(63 downto 59) = ECI_IREQ_IOBST or
                        in_vc0(63 downto 59) = ECI_IREQ_IOBSTA or
                        in_vc0(63 downto 59) = ECI_IREQ_SLIST then -- IO write
                        request(0) <= in_vc0;
                        second_cycle <= '1';
                    end if;
                else
                    request(1) <= in_vc0;
                    request_ready <= "11";
                    request_link <= active_link;
                    second_cycle <= '0';
                end if;
            end if;

            if link1_in_vc0_ready = '1' or link2_in_vc0_ready = '1' then
                link1_in_vc0_ready <= '0';
                link2_in_vc0_ready <= '0';
            end if;

            if request_ready = "10" then -- load
                if request(0)(63 downto 59) = ECI_IREQ_IOBLD then -- prepare a response
                    out_data <= ECI_IRSP_IOBRSP & "0" & request(0)(57 downto 49) & "0" & X"000000000000";
                else
                    out_data <= ECI_IRSP_SLIRSP & "000" & X"00000000000000";
                end if;
                out_vc_no <= X"1";
                second_write <= '1';

                address := request(0)(44 downto 4) & "000";
                if unsigned(address) < X"7E000000000" or unsigned(address) >= X"80000000000" then -- send READ to the AXI
                    m_io_axil_araddr <= address(43 downto 0);
                    m_io_axil_arvalid <= '1';
                    m_io_axil_rready <= '1';
                elsif unsigned(address) >= X"7EFFFFFFE00" then -- ICAP port
                    m_icap_axi_araddr <= address(8 downto 0);
                    m_icap_axi_arvalid <= '1';
                    m_icap_axi_rready <= '1';
                else -- internal registers
                    case address is
                        when X"7E011000000" =>
                            out_buffer <= X"0000000000000005";
                        when X"7E011000020" =>
                            out_buffer <= X"000000000000000c";
                        when X"7E011000028" =>
                            out_buffer <= X"0000000000000026";
                        when X"7E011000030" =>
                            if SECOND_LINK_ACTIVE = 1 then
                                out_buffer <= X"000000000000000c";
                            else
                                out_buffer <= X"0000000000000026";
                            end if;
                        when X"7E011018028" =>
                            out_buffer <= rlk_lnk_data(0);
                        when X"7E01101c028" =>
                            out_buffer <= rlk_lnk_data(1);
                        when others =>
                            out_buffer <= X"0000DEADBEEF0000";
                    end case;
                    out_valid <= '1';
                    out_link <= request_link;
                    out_buffer_vc_no <= X"1";
                end if;
                request_ready <= "00";
            elsif request_ready = "11" then -- store
                if request(0)(63 downto 59) = ECI_IREQ_IOBSTA then
                    out_data <= ECI_IRSP_IOBACK & "0" & request(0)(57 downto 49) & "0" & X"000000000000"; -- prepare ACK
                    out_vc_no <= X"1";
                end if;
                address := request(0)(44 downto 4) & "000";
                if unsigned(address) < X"7E000000000" or unsigned(address) >= X"80000000000" then -- send WRITE to the AXI
                    m_io_axil_awaddr <= address(43 downto 0);
                    m_io_axil_awvalid <= '1';
                    m_io_axil_wdata <= request(1);
                    m_io_axil_wvalid <= '1';
                    m_io_axil_wstrb <= eci_io_word_to_bitmap(request(0)(3 downto 0));
                    m_io_axil_bready <= '1';
                elsif unsigned(address) >= X"7EFFFFFFE00" then -- ICAP port
                    m_icap_axi_awaddr <= address(8 downto 0);
                    m_icap_axi_awvalid <= '1';
                    m_icap_axi_wdata <= request(1)(31 downto 0);
                    m_icap_axi_wvalid <= '1';
                    m_icap_axi_wstrb <= eci_io_word_to_bitmap(request(0)(3 downto 0))(3 downto 0);
                    m_icap_axi_bready <= '1';
                else -- internal registers
                    case address is
                        when X"7E011010028" =>
                            out_data <= ECI_MDLD_LNKD & request(1)(55 downto 0) & "000";
                            out_vc_no <= X"d";
                            out_link <= '0';
                            out_valid <= '1';
                        when X"7E011014028" =>
                            out_data <= ECI_MDLD_LNKD & request(1)(55 downto 0) & "000";
                            out_vc_no <= X"d";
                            out_link <= '1';
                            out_valid <= '1';
                        when others =>
                    end case;
                    if request(0)(63 downto 59) = ECI_IREQ_IOBSTA then
                        out_link <= request_link;
                        out_valid <= '1'; -- send ACK
                    end if;
                end if;
                request_ready <= "00";
            end if;

            -- processing a request
            if out_valid = '1' and out_ready = '1' then -- message sent
                if second_write = '1' then
                    out_data <= out_buffer;
                    out_vc_no <= out_buffer_vc_no;
                    second_write <= '0';
                else
                    out_valid <= '0';
                end if;
            end if;

            if m_io_axil_arvalid = '1' and m_io_axil_arready = '1' then -- AXI read address sent
                m_io_axil_arvalid <= '0';
            end if;
            if m_io_axil_rvalid = '1' and m_io_axil_rready = '1' then -- AXI read data received
                m_io_axil_rready <= '0';
                out_buffer <= m_io_axil_rdata;
                out_link <= request_link;
                out_valid <= '1';
            end if;
            if m_io_axil_awvalid = '1' and m_io_axil_awready = '1' then -- AXI write address sent
                m_io_axil_awvalid <= '0';
            end if;
            if m_io_axil_wvalid = '1' and m_io_axil_wready = '1' then -- AXI write data sent
                m_io_axil_wvalid <= '0';
                m_io_axil_wstrb <= "00000000";
            end if;

            if m_icap_axi_arvalid = '1' and m_icap_axi_arready = '1' then -- AXI read address sent
                m_icap_axi_arvalid <= '0';
            end if;
            if m_icap_axi_rvalid = '1' and m_icap_axi_rready = '1' then -- AXI read data received
                m_icap_axi_rready <= '0';
                out_buffer <= x"00000000" & m_icap_axi_rdata;
                out_link <= request_link;
                out_valid <= '1';
            end if;
            if m_icap_axi_awvalid = '1' and m_icap_axi_awready = '1' then -- AXI write address sent
                m_icap_axi_awvalid <= '0';
            end if;
            if m_icap_axi_wvalid = '1' and m_icap_axi_wready = '1' then -- AXI write data sent
                m_icap_axi_wvalid <= '0';
                m_icap_axi_wstrb <= "0000";
            end if;

            if (m_io_axil_bvalid = '1' and m_io_axil_bready = '1')
                or (m_icap_axi_bvalid = '1' and m_icap_axi_bready = '1') then -- AXI write ack received
                if request(0)(63 downto 59) = ECI_IREQ_IOBSTA then -- send ACK
                    out_vc_no <= X"1";
                    out_link <= request_link;
                    out_valid <= '1';
                end if;
                m_io_axil_bready <= '0';
            end if;
        end if;
    end if;
end process;

end Behavioral;
