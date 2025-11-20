---------------------------------------------------------------------------
--  Copyright 2015 - 2017 Systems Group, ETH Zurich
-- 
--  This hardware module is free software: you can redistribute it and/or
--  modify it under the terms of the GNU General Public License as published
--  by the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
-- 
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
-- 
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
---------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all;

-------------------------------------------------------------------------------
-- This module is used to filter the input to the hash-table pipeline.
-- It acts as FIFO with a lookup, where the 'find' input is matched to all
-- elements in the queue.
-- The idea is that every write operation is pushed into the filter when
-- entering the pipeline, and popped when the memroy was written.
-- Read operations just need to be checked for address conflicts with the
-- writes, but need  not be stored inside the filter .
-------------------------------------------------------------------------------
entity muu_replicate_CentralSM is
	generic(
		CMD_SESSID_LOC            : integer := 0;
		CMD_SESSID_LEN            : integer := 16;

		CMD_PEERID_LOC            : integer := 88;
		CMD_PEERID_LEN            : integer := 8;

		CMD_TYPE_LOC              : integer := 144;
		CMD_TYPE_LEN              : integer := 8;

		CMD_HTOP_LOC              : integer := 152;
		CMD_HTOP_LEN              : integer := 4;

		CMD_PAYLSIZE_LOC          : integer := 64;
		CMD_PAYLSIZE_LEN          : integer := 16;

		CMD_ZXID_LOC              : integer := 96;
		CMD_ZXID_LEN              : integer := 32;

		CMD_EPOCH_LOC             : integer := 128;
		CMD_EPOCH_LEN             : integer := 16;

		PEER_BITS                 : integer := 3; -- must be +1
		MAX_PEERS                 : integer := 7;
		MAX_OUTSTANDING_REQS_BITS : integer := 10;

		USER_BITS                 : integer := 3;

		CMD_WIDTH                 : integer := 156
	);
	port(
		clk                  : in  std_logic;
		rst                  : in  std_logic;

		cmd_in_valid         : in  std_logic;
		cmd_in_data          : in  std_logic_vector(CMD_WIDTH - 1 downto 0);
		cmd_in_key           : in  std_logic_vector(63 downto 0);
		cmd_in_user          : in  std_logic_vector(USER_BITS - 1 downto 0);
		cmd_in_ready         : out std_logic;

		cmd_out_valid        : out std_logic;
		cmd_out_data         : out std_logic_vector(CMD_WIDTH - 1 downto 0);
		cmd_out_key          : out std_logic_vector(63 downto 0);
		cmd_out_user         : out std_logic_vector(USER_BITS - 1 downto 0);
		cmd_out_ready        : in  std_logic;

		log_add_valid        : out std_logic;
		log_add_zxid         : out std_logic_vector(31 downto 0);
		log_add_user         : out std_logic_vector(USER_BITS - 1 downto 0);
		log_add_key          : out std_logic_vector(63 downto 0);

		log_search_valid     : out std_logic;
		log_search_since     : out std_logic;
		log_search_user      : out std_logic_vector(USER_BITS - 1 downto 0);
		log_search_zxid      : out std_logic_vector(31 downto 0);

		log_found_valid      : in  std_logic;
		log_found_key        : in  std_logic_vector(63 downto 0);

		open_conn_req_valid  : out std_logic;
		open_conn_req_ready  : in  std_logic;
		open_conn_req_data   : out std_logic_vector(47 downto 0);

		open_conn_resp_valid : in  std_logic;
		open_conn_resp_ready : out std_logic;
		open_conn_resp_data  : in  std_logic_vector(16 downto 0);

		malloc_valid         : out std_logic;
		malloc_ready         : in  std_logic;
		malloc_data          : out std_logic_vector(15 downto 0);

		error_valid          : out std_logic;
		error_opcode         : out std_logic_vector(7 downto 0);

		sync_dram            : out std_logic;
		sync_getready        : out std_logic;

		not_leader           : out std_logic;

		dead_mode            : out std_logic;

		debug_out            : out std_logic_vector(127 downto 0)
	);

end muu_replicate_CentralSM;

architecture beh of muu_replicate_CentralSM is
	constant ERRORCHECKING : boolean := true;

	constant OPCODE_SETUPPEER  : integer := 17;
	constant OPCODE_ADDPEER    : integer := 18;
	constant OPCODE_REMOVEPEER : integer := 19;
	constant OPCODE_SETLEADER  : integer := 20;

	constant OPCODE_SETCOMMITCNT  : integer := 25;
	constant OPCODE_SETSILENCECNT : integer := 26;
	constant OPCODE_SETHTSIZE     : integer := 27;

	constant OPCODE_TOGGLEDEAD : integer := 28;

	constant OPCODE_SYNCDRAM : integer := 29;

	constant OPCODE_READREQ    : integer := 0;
	constant OPCODE_WRITEREQ   : integer := 1;
	constant OPCODE_PROPOSAL   : integer := 2;
	constant OPCODE_ACKPROPOSE : integer := 3;
	constant OPCODE_COMMIT     : integer := 4;
	constant OPCODE_SYNCREQ    : integer := 5;
	constant OPCODE_SYNCRESP   : integer := 6;
	constant OPCODE_SYNCCOMMIT : integer := 7;

	constant OPCODE_FAKESYNCREQ    : integer := 12;

	constant OPCODE_UNVERSIONEDWRITE : integer := 31;		
	constant OPCODE_UNVERSIONEDDELETE : integer := 47;

	constant OPCODE_READCONDITIONAL : integer := 64;

    constant OPCODE_FLUSHDATASTORE : integer := 255;

	constant OPCODE_DELWRITEREQ   : integer := 32 + 1;
	constant OPCODE_DELPROPOSAL   : integer := 32 + 2;
	constant OPCODE_DELACKPROPOSE : integer := 32 + 3;

	constant OPCODE_CUREPOCH   : integer := 8;
	constant OPCODE_NEWEPOCH   : integer := 9;
	constant OPCODE_ACKEPOCH   : integer := 10;
	constant OPCODE_SYNCLEADER : integer := 11;

	constant HTOP_IGNORE     : integer := 0;
	constant HTOP_GET        : integer := 1;
	constant HTOP_SETNEXT    : integer := 2;
	constant HTOP_DELCUR     : integer := 3;
	constant HTOP_FLIPPOINT  : integer := 4;
	constant HTOP_SETCUR     : integer := 5;
	constant HTOP_GETRAW     : integer := 6;
	constant HTOP_IGNOREPROP : integer := 7;
	constant HTOP_GETCOND    : integer := 8;
	constant HTOP_FLUSH		 : integer := 16; 
	constant HTOP_SCAN       : integer := 9;
	constant HTOP_SCANCOND   : integer := 10;


	--type Array16Large is array(2**MAX_OUTSTANDING_REQS_BITS-1 downto 0) of std_logic_vector(15 downto 0);

	type Array32 is array (MAX_PEERS downto 0) of std_logic_vector(31 downto 0);
	type Array48 is array (MAX_PEERS downto 0) of std_logic_vector(47 downto 0);
	type Array16 is array (MAX_PEERS downto 0) of std_logic_vector(15 downto 0);	

	type RoleType is (ROLE_LEADER, ROLE_FOLLOWER, ROLE_UNKNOWN);
	type PhaseType is (PH_ELECTION, PH_SYNC, PH_NORMAL, PH_STARTUP);
	type StateType is (ST_WAITOP, ST_HANDLEOP, ST_OPENTCPCONN, ST_SENDTOALL, ST_FINISH_WRITEREQ,
		               ST_CHKQRM_ACKS, ST_CHKQRM_ACKS_2, ST_FINISH_COMMIT, ST_FINISH_COMMIT_LATE, ST_FINISH_COMMIT_DATAFORAPP,
		               ST_WAIT_MEMWRITE, ST_REQUESTSYNC, ST_SENDSYNC, ST_GETLOGSYNC, ST_DRAMSYNC,
		               ST_PROP_LEADER, ST_CHKQRM_PROPS, ST_SENDNEWEPOCH, ST_SENDNEWEPOCH_JOIN, ST_SYNC_ELECTION, 
		               ST_SAYWHOISLEADER, ST_WAITOUTREADY, ST_INITIALIZE_STRUCTS, ST_TIMEOUT_LEADER);

	type ArrayRoleType is array (2**USER_BITS -1  downto 0) of RoleType;
	type ArrayPhaseType is array (2**USER_BITS -1 downto 0) of PhaseType;
	type ArrayStateType is array (2**USER_BITS -1 downto 0) of StateType;

	signal prevRole : ArrayRoleType;
	signal myRole   : ArrayRoleType;
	signal preloadMyRole   : RoleType;
	signal myPhase  : ArrayPhaseType;
	signal preloadMyPhase : PhaseType;
	signal myState  : StateType;

	--type UaArray16Large is array(2**USER_BITS-1 downto 0) of Array16Large;
	type UaArray32 is array (2 ** USER_BITS - 1 downto 0) of Array32;
	type UaArray48 is array (2 ** USER_BITS - 1 downto 0) of Array48;
	type UaArray16 is array (2 ** USER_BITS - 1 downto 0) of Array16;
	type UaArrayBool is array (2 ** USER_BITS - 1 downto 0) of std_logic_vector(MAX_PEERS downto 0);

	type BlArray32 is array (((2 ** USER_BITS) * 2 ** PEER_BITS) - 1 downto 0) of std_logic_vector(31 downto 0);

	--signal clientReqSess : UaArray16Large;
	--signal clientReqZxid : UaArray16Large;

	type UaZxid is array (2 ** USER_BITS - 1 downto 0) of std_logic_vector(CMD_ZXID_LEN - 1 downto 0);
	type Ua32 is array (2 ** USER_BITS - 1 downto 0) of std_logic_vector(31 downto 0);
	type UaEpoch is array (2 ** USER_BITS - 1 downto 0) of std_logic_vector(CMD_EPOCH_LEN - 1 downto 0);

	signal myZxid       : UaZxid;
	signal preloadMyZxid : std_logic_vector(CMD_ZXID_LEN-1 downto 0);
	signal proposedZxid : Ua32;
	signal preloadProposedZxid : std_logic_vector(CMD_ZXID_LEN-1 downto 0);
	signal myEpoch      : UaEpoch;
	signal preloadMyEpoch : std_logic_Vector(CMD_EPOCH_LEN-1 downto 0);
	signal myIPAddr     : Ua32;

	type UaPeerId is array (2 ** USER_BITS - 1 downto 0) of std_logic_vector(PEER_BITS-1 downto 0);

	signal myPeerId             : UaPeerId;	
	signal preloadMyPeerId 	    : std_logic_vector(PEER_BITS-1  downto 0);

	signal leaderPeerId         : UaPeerId;
	signal nextLeaderId         : UaPeerId;
	signal sinceHeardFromLeader : Ua32;
	signal silenceThreshold     : Ua32;
	signal silenceMeasured      : std_logic_vector(2 ** USER_BITS - 1 downto 0);

	type Ua4 is array (2 ** USER_BITS - 1 downto 0) of std_logic_vector(3 downto 0);

	signal voteCount  : Ua4;
	signal votedEpoch : UaEpoch;
	signal preloadVotedEpoch : std_logic_vector(CMD_EPOCH_LEN-1 downto 0);
	signal votedZxid  : Ua32;
	signal preloadVotedZxid : std_logic_vector(CMD_ZXID_LEN-1 downto 0);
	signal syncFrom   : UaPeerId;

	type UaPeerCount is array (2 ** USER_BITS - 1 downto 0) of std_logic_vector(PEER_BITS-1 downto 0);

	
	signal peerIP      : UaArray48;
	signal peerIPNonZero  : UaArrayBool;
	signal preloadPeerIPNZ : std_logic_vector(MAX_PEERS downto 0);
	--signal currPeerIP  : Array48;
	signal peerSessId  : UaArray16;
	signal peerZxidAck : BlArray32;
	signal peerZxidCmt : BlArray32;
	signal peerEpoch   : UaArray32;

	signal preloadPeerZxidAck : std_logic_vector(31 downto 0);
	signal preloadPeerZxidCmt : std_logic_vector(31 downto 0);

	signal peerCount   : UaPeerCount;
	signal peerCountForCommit : UaPeerCount;

	signal preloadPeerCount : std_logic_vector(PEER_BITS-1 downto 0);
	signal preloadPeerCountForCommit : std_logic_vector(PEER_BITS-1 downto 0);

	signal thisPeersAckedZxid : std_logic_vector(CMD_ZXID_LEN - 1 downto 0);
	signal thisPeersCmtdZxid  : std_logic_vector(CMD_ZXID_LEN - 1 downto 0);

	signal inCmdReady       : std_logic;
	signal inCmdOpCode      : std_logic_vector(CMD_TYPE_LEN - 1 downto 0);
	signal inCmdSessId      : std_logic_vector(CMD_SESSID_LEN - 1 downto 0);
	signal inCmdPeerId      : std_logic_vector(CMD_PEERID_LEN - 1 downto 0);
	signal inCmdZxid        : std_logic_vector(CMD_ZXID_LEN - 1 downto 0);
	signal inCmdEpoch       : std_logic_vector(CMD_EPOCH_LEN - 1 downto 0);
	signal inCmdPayloadSize : std_logic_vector(CMD_PAYLSIZE_LEN - 1 downto 0);
	signal inCmdKey         : std_logic_vector(63 downto 0);
	signal inCmdUser        : std_logic_vector(USER_BITS - 1 downto 0);
	signal inCmdUserReg     : std_logic_vector(USER_BITS - 1 downto 0);
	signal inCmdAllData     : std_logic_vector(CMD_WIDTH - 1 downto 0);

	signal inCmdOpCode_I      : std_logic_vector(CMD_TYPE_LEN - 1 downto 0);
	signal inCmdSessId_I      : std_logic_vector(CMD_SESSID_LEN - 1 downto 0);
	signal inCmdPeerId_I      : std_logic_vector(CMD_PEERID_LEN - 1 downto 0);
	signal inCmdZxid_I        : std_logic_vector(CMD_ZXID_LEN - 1 downto 0);
	signal inCmdEpoch_I       : std_logic_vector(CMD_EPOCH_LEN - 1 downto 0);
	signal inCmdPayloadSize_I : std_logic_vector(CMD_PAYLSIZE_LEN - 1 downto 0);
	signal inCmdKey_I         : std_logic_vector(63 downto 0);
	signal inCmdUser_I        : std_logic_vector(USER_BITS - 1 downto 0);

	signal syncZxid        : UaZxid;

	signal preloadSyncZxid : std_logic_vector(CMD_ZXID_LEN - 1 downto 0);
	signal syncMode        : std_logic;
	signal syncPrepare     : std_logic;
	signal syncDramAddress : std_logic_vector(31 downto 0);
	signal htSyncSize      : std_logic_vector(31 downto 0);

	signal connToPeerId    : std_logic_vector(CMD_PEERID_LEN - 1 downto 0);
	signal connToIpAddress : std_logic_vector(31 downto 0);
	signal connToPort      : std_logic_vector(15 downto 0);
	signal connToSessId    : std_logic_vector(15 downto 0);
	signal connToWaiting   : std_logic;

	signal sendOpcode      : std_logic_vector(7 downto 0);
	signal sendPayloadSize : std_logic_vector(15 downto 0);
	signal sendZxid        : std_logic_vector(CMD_ZXID_LEN - 1 downto 0);
	signal sendEpoch       : std_logic_vector(CMD_EPOCH_LEN - 1 downto 0);
	signal sendCount       : std_logic_vector(PEER_BITS-1 downto 0);
	signal sendEnableMask  : std_logic_vector(MAX_PEERS downto 0);

	signal loopIteration   : std_logic_vector(PEER_BITS-1 downto 0);
	signal quorumIteration : std_logic_vector(PEER_BITS-1 downto 0);
	signal quorumIterationMinus1 : std_logic_vector(PEER_BITS-1 downto 0);

	signal commitableCount         : std_logic_vector(PEER_BITS-1 downto 0);
	signal commitableCountTimesTwo : std_logic_vector(PEER_BITS downto 0);

	signal cmdForParallelData  : std_logic_vector(127 downto 0);
	signal cmdForParallelValid : std_logic;

	signal inCmdPayloadSizeP1 : std_logic_vector(15 downto 0);

	signal logFoundSizeP1 : std_logic_vector(15 downto 0);

	signal returnState : StateType;

	signal foundInLog : std_logic;
	signal cmdSent    : std_logic;

	signal sessMemEnable   : std_logic;
	signal sessMemEnableD1 : std_logic;
	signal sessMemEnableD2 : std_logic;
	signal sessMemWrite    : std_logic_vector(0 downto 0);
	signal sessMemAddr     : std_logic_vector(MAX_OUTSTANDING_REQS_BITS - 1 downto 0);
	signal sessMemDataIn   : std_logic_vector(16 + 31 downto 0);
	signal sessMemDataOut  : std_logic_vector(16 + 31 downto 0);

	signal internalClk  : std_logic_vector(31 downto 0);
	signal receiveTime  : std_logic_vector(15 downto 0);
	signal responseTime : std_logic_vector(15 downto 0);

	signal syncModeWaited : std_logic_vector(31 downto 0);

	signal traceLoc : std_logic_vector(7 downto 0);

	signal syncPeerId : std_logic_vector(PEER_BITS-1 downto 0);

	signal isDead : std_logic;

	signal rst_regd : std_logic;

	signal flagLate : std_logic;

	signal init_user_cnt : std_logic_vector(USER_BITS - 1 downto 0);
	signal init_peer_cnt : std_logic_vector(PEER_BITS - 1 downto 0);

	component zk_blkmem_32x1024
		port(
			clka  : in  std_logic;
			--ena : IN STD_LOGIC;
			wea   : in  std_logic_vector(0 downto 0);
			addra : in  std_logic_vector(MAX_OUTSTANDING_REQS_BITS - 1 downto 0);
			dina  : in  std_logic_vector(47 downto 0);
			douta : out std_logic_vector(47 downto 0)
		);
	end component;

	signal isMyPhaseStartup : std_logic;
	signal isMyPhaseNormal : std_logic;
	signal isMyPhaseElection : std_logic;

	signal isMyRoleFollower : std_logic;
	signal isMyRoleLeader : std_logic;

begin
	cmd_in_ready <= inCmdReady;

	inCmdOpCode_I      <= cmd_in_data(CMD_TYPE_LEN - 1 + CMD_TYPE_LOC downto CMD_TYPE_LOC);
	inCmdSessID_I      <= cmd_in_data(CMD_SESSID_LEN - 1 + CMD_SESSID_LOC downto CMD_SESSID_LOC);
	inCmdPeerID_I      <= cmd_in_data(CMD_PEERID_LEN - 1 + CMD_PEERID_LOC downto CMD_PEERID_LOC);
	inCmdZxid_I        <= cmd_in_data(CMD_ZXID_LEN - 1 + CMD_ZXID_LOC downto CMD_ZXID_LOC);
	inCmdEpoch_I       <= cmd_in_data(CMD_EPOCH_LEN - 1 + CMD_EPOCH_LOC downto CMD_EPOCH_LOC);
	inCmdPayloadSize_I <= cmd_in_data(CMD_PAYLSIZE_LEN - 1 + CMD_PAYLSIZE_LOC downto CMD_PAYLSIZE_LOC);
	inCmdKey_I         <= cmd_in_key;
	inCmdUser_I        <= cmd_in_user;

	--logFoundSizeP1 <= (log_found_size(15 downto 0)+7);

	inCmdPayloadSizeP1 <= (inCmdPayloadSize(15 downto 0) + 7);

	commitableCountTimesTwo <= commitableCount(PEER_BITS-1 downto 0) & "0";

	sync_dram     <= syncMode;
	sync_getready <= syncPrepare;

	dead_mode <= isDead;

	isMyPhaseStartup <= '1' when (myPhase(conv_integer(inCmdUser_I)) = PH_STARTUP) else '0';
	isMyPhaseElection <= '1' when (myPhase(conv_integer(inCmdUser_I)) = PH_ELECTION) else '0';
    isMyPhaseNormal <= '1' when (myPhase(conv_integer(inCmdUser_I)) = PH_NORMAL) else '0';

    isMyRoleLeader <= '1' when (myRole(conv_integer(inCmdUser_I)) = ROLE_LEADER) else '0';
    isMyRoleFollower <= '1' when (myRole(conv_integer(inCmdUser_I)) = ROLE_FOLLOWER) else '0';



 
	main : process(clk)
	
	variable quorumIterationVar : std_logic_vector(PEER_BITS-1 downto 0);
	
	begin
		if (clk'event and clk = '1') then
			rst_regd <= rst;

			if (rst_regd = '1') then
				syncMode       <= '0';
				syncPrepare    <= '0';
				syncModeWaited <= (others => '0');
				htSyncSize     <= (others => '0');
				htSyncSize(25) <= '1';

				prevRole <= (others => ROLE_UNKNOWN);
				myRole   <= (others => ROLE_UNKNOWN);
				myPhase  <= (others => PH_STARTUP);
				myState  <= ST_INITIALIZE_STRUCTS;

				myPeerId     <= (others => (others => '0'));
				myZxid       <= (others => (others => '0'));
				myEpoch      <= (others => (others => '0'));
				proposedZxid <= (others => (others => '0'));

				peerCount <= (others => (others => '0'));

				sinceHeardFromLeader <= (others => (others => '0'));
				silenceThreshold     <= (others => (others => '0'));
				silenceMeasured      <= (others => '0');

				voteCount  <= (others => (others => '0'));
				votedEpoch <= (others => (others => '0'));
				syncFrom   <= (others => (others => '0'));
				votedZxid  <= (others => (others => '0'));

				malloc_valid <= '0';

				--for U in 2**USER_BITS-1 downto 0 loop
				--   peerIP(U)	 <= (others =>(others => '0'));
				--   peerSessId(U)	 <= (others =>(others => '0'));
				--   peerZxidAck(U) <= (others =>(others => '0'));
				--   peerZxidCmt(U) <= (others =>(others => '0'));
				--   peerEpoch(U)	 <= (others =>(others => '0'));
				-- end loop;

				init_peer_cnt <= (others => '0');
				init_user_cnt <= (others => '0');

				inCmdReady <= '1';

				error_valid <= '0';

				open_conn_resp_ready <= '1';
				open_conn_req_valid  <= '0';

				log_add_valid    <= '0';
				log_search_valid <= '0';

				cmd_out_valid <= '0';
				foundInLog    <= '0';

				sendEnableMask <= (others => '1');

				sessMemEnable   <= '0';
				sessMemWrite(0) <= '0';

				cmdSent <= '0';

				internalClk <= (others => '0');

				peerCountForCommit  <= (others => (others => '0'));
				cmdForParallelValid <= '0';

				traceLoc <= (others => '0');

				not_leader <= '1';
				isDead     <= '0';

			else
				if (myRole(0) = ROLE_LEADER and myPhase(0) = PH_NORMAL) then
					not_leader <= '0';
				else
					not_leader <= '1';
				end if;

				malloc_valid <= '0';

				internalClk <= internalClk + 1;

				--if (internalClk(19 downto 0) = 0 ) then

				--end if;

				sessMemEnableD2 <= sessMemEnableD1;
				sessMemEnableD1 <= sessMemEnable;
				sessMemEnable   <= '0';
				sessMemWrite(0) <= '0';

				error_valid      <= '0';
				log_add_valid    <= '0';
				log_search_valid <= '0';

				if (cmd_out_ready = '1') then
					cmd_out_valid <= '0';
				end if;

				--if (write_ready='1') then
				--  write_valid <= '0';
				--end if;

				sinceHeardFromLeader <= (others => (others => '0')); --sinceHeardFromLeader +1;

				--	if (syncPrepare='1' or syncMode='1') then
				--	 syncModeWaited <= syncModeWaited+1;
				--    end if;	

				--	if (myState=ST_WAITOP and cmd_in_valid='0' and syncPrepare='1' and syncModeWaited>4096) then
				--	syncPrepare <= '0';
				--	syncMode <= '1';
				--	syncDramAddress <= (others => '0');
				--	syncModeWaited <= (others => '0');
				--	myState <= ST_DRAMSYNC;
				--	inCmdReady <= '0';
				--    end if;

				case myState is
					when ST_INITIALIZE_STRUCTS =>
						init_peer_cnt <= init_peer_cnt + 1;
						if (init_peer_cnt = MAX_PEERS) then
							init_user_cnt <= init_user_cnt + 1;
							init_peer_cnt <= (others => '0');
							if (init_user_cnt = 2 ** USER_BITS - 1) then
								myState <= ST_WAITOP;
							end if;

						end if;

						peerIP(conv_integer(init_user_cnt))(conv_integer(init_peer_cnt))     <= (others => '0');
						peerIPNonZero(conv_integer(init_user_cnt))(conv_integer(init_peer_cnt))     <= '0';
						peerSessId(conv_integer(init_user_cnt))(conv_integer(init_peer_cnt)) <= (others => '0');
						--peerZxidAck(conv_integer(init_user_cnt&init_peer_cnt)) <= (others => '0');
						--peerZxidCmt(conv_integer(init_user_cnt&init_peer_cnt)) <= (others => '0');
						peerEpoch(conv_integer(init_user_cnt))(conv_integer(init_peer_cnt))  <= (others => '0');

					---------------------------------------------------------------------
					-- WAIT OP: wait for next command, perform in
					-- initial checks on it
					---------------------------------------------------------------------
					when ST_WAITOP =>
						traceLoc <= "00000001";

						if (cmd_in_valid = '1' and inCmdReady = '1') then
							inCmdOpCode      <= cmd_in_data(CMD_TYPE_LEN - 1 + CMD_TYPE_LOC downto CMD_TYPE_LOC);
							inCmdSessID      <= cmd_in_data(CMD_SESSID_LEN - 1 + CMD_SESSID_LOC downto CMD_SESSID_LOC);
							inCmdPeerID      <= cmd_in_data(CMD_PEERID_LEN - 1 + CMD_PEERID_LOC downto CMD_PEERID_LOC);
							inCmdZxid        <= cmd_in_data(CMD_ZXID_LEN - 1 + CMD_ZXID_LOC downto CMD_ZXID_LOC);
							inCmdEpoch       <= cmd_in_data(CMD_EPOCH_LEN - 1 + CMD_EPOCH_LOC downto CMD_EPOCH_LOC);
							inCmdPayloadSize <= cmd_in_data(CMD_PAYLSIZE_LEN - 1 + CMD_PAYLSIZE_LOC downto CMD_PAYLSIZE_LOC);
							inCmdKey         <= cmd_in_key;
							inCmdUser        <= cmd_in_user;
							inCmdAllData     <= cmd_in_data;

							preloadMyPeerId    <= myPeerId(conv_integer(cmd_in_user));

							--for PEER in MAX_PEERS downto 0 loop
							--  currPeerIP(PEER) <= peerIP(conv_integer(inCmdUser_I))(PEER);
							--end loop;

							sendEnableMask <= (others => '1');

							case (conv_integer(inCmdOpCode_I(CMD_TYPE_LEN - 1 downto 0))) is

								-- SETUP PEER
								when (OPCODE_SETUPPEER) =>
									traceLoc <= "00000010";

									if (isMyRoleFollower='0' and isMyRoleLeader='0' and isMyPhaseStartup='1' and inCmdPeerId_I /= 0) then
										myState    <= ST_HANDLEOP;
										inCmdReady <= '0';
									else
										error_valid  <= '1';
										error_opcode <= inCmdOpCode_I;
									end if;

								-- SET LEADERSHIP
								when (OPCODE_SETLEADER) =>
									traceLoc <= "00000011";

									if (((isMyRoleFollower='0' and isMyRoleLeader='0' and isMyPhaseStartup='1') or isMyPhaseElection='1') and inCmdPeerId_I /= 0 and myPeerId(conv_integer(inCmdUser_I)) /= 0 and inCmdEpoch_I = 0) then
										myState    <= ST_HANDLEOP;
										inCmdReady <= '0';
									else
										error_valid  <= '1';
										error_opcode <= inCmdOpCode_I;
									end if;

								-- ADD PEER
								when (OPCODE_ADDPEER) =>
									traceLoc <= "00000100";

									if ((isMyPhaseStartup='1' or isMyRoleLeader='1') and inCmdPeerId_I /= myPeerId(conv_integer(inCmdUser_I)) and (inCmdEpoch_I /= 0 or inCmdZxid_I /= 0)) then
										myState    <= ST_HANDLEOP;
										preloadPeerCount <= peerCount(conv_integer(inCmdUser_I));
										inCmdReady <= '0';
									else
										error_valid  <= '1';
										error_opcode <= inCmdOpCode_I;
									end if;

								when (OPCODE_TOGGLEDEAD) =>
									traceLoc <= "10101010";
									isDead   <= not isDead;

								-- SET THE NUMBER OF PEERS USED FOR COMPUTING MAJORITY
								when (OPCODE_SETCOMMITCNT) =>
									traceLoc <= "00000101";
									if (isMyPhaseNormal='1' and isMyRoleLeader='1') then
										peerCountForCommit(conv_integer(inCmdUser_I)) <= inCmdEpoch_I(PEER_BITS-1 downto 0);

									else
										error_valid  <= '1';
										error_opcode <= inCmdOpCode_I;
									end if;

								when (OPCODE_SETSILENCECNT) =>
									traceLoc                                                  <= "00000110";
									silenceThreshold(conv_integer(inCmdUser_I))(17 downto 10) <= inCmdEpoch_I(7 downto 0);
									silenceMeasured(conv_integer(inCmdUser_I))                <= '1';
									sinceHeardFromLeader(conv_integer(inCmdUser_I))           <= (others => '0');

								when (OPCODE_SETHTSIZE) =>
									traceLoc <= "00000110";
								-- htSyncSize <= inCmdEpoch_I(15 downto 0);


								-- WRITE REQUEST
								when (OPCODE_WRITEREQ) =>
									traceLoc <= "00000111";
									if (isMyPhaseNormal='1' and isMyRoleLeader='1') then
										-- if I am the leader, I need to 1) add the request to the
										-- log, 2) send out proposals to the peers 3) wait for acks
										-- from them, and finally commit. The acks are handled "in
										-- parallel" to this operation, and they trigger the commits.
										--

										receiveTime <= internalClk(15 downto 0);

										loopIteration       <= peerCount(conv_integer(inCmdUser_I)) + 2;
										cmdForParallelValid <= '0';
										cmdForParallelData  <= (others => '0');

										myState    <= ST_HANDLEOP;
										inCmdReady <= '0';

									else

										--		    if (prevRole=ROLE_LEADER) then
										--		      cmd_out_valid <= '1';
										--		      cmd_out_data(CMD_PAYLSIZE_LOC+CMD_PAYLSIZE_LEN-1 downto CMD_PAYLSIZE_LOC) <= (others=>'0');
										--		      cmd_out_data(CMD_TYPE_LEN+CMD_TYPE_LOC-1 downto CMD_TYPE_LOC) <= std_logic_Vector(conv_unsigned(69, 8));
										--		      cmd_out_data(CMD_EPOCH_LOC+CMD_EPOCH_LEN-1 downto CMD_EPOCH_LOC) <= (others => '0');
										--		      cmd_out_data(CMD_ZXID_LOC+CMD_ZXID_LEN-1 downto CMD_ZXID_LOC) <= (others => '0');
										--		      cmd_out_data(CMD_PEERID_LEN+CMD_PEERID_LOC-1 downto CMD_PEERID_LOC) <= myPeerId;
										--		      cmd_out_data(CMD_SESSID_LOC+CMD_SESSID_LEN-1 downto CMD_SESSID_LOC) <= inCmdSessID_I;
										--		    end if;

										error_valid  <= '1';
										error_opcode <= inCmdOpCode_I;
									end if;

								when (OPCODE_UNVERSIONEDWRITE) =>
									myState    <= ST_HANDLEOP;
									inCmdReady <= '0';
									
								when (OPCODE_UNVERSIONEDDELETE) =>
                                        myState    <= ST_HANDLEOP;
                                        inCmdReady <= '0';									

								when (OPCODE_ACKPROPOSE) =>
									traceLoc <= "00001000";

									thisPeersAckedZxid <= peerZxidAck(conv_integer(inCmdUser_I(USER_BITS - 1 downto 0) & inCmdPeerId_I(PEER_BITS - 1 downto 0)));
  									thisPeersCmtdZxid  <= peerZxidCmt(conv_integer(inCmdUser_I(USER_BITS - 1 downto 0) & inCmdPeerId_I(PEER_BITS - 1 downto 0)));

									if (isMyPhaseNormal='1' and isMyRoleLeader='1' and proposedZxid(conv_integer(inCmdUser_I)) >= inCmdZxid_I) then										
										
										if (peerZxidAck(conv_integer(inCmdUser_I(USER_BITS - 1 downto 0) & inCmdPeerId_I(PEER_BITS - 1 downto 0))) + 1 = inCmdZxid_I) then
											myState    <= ST_HANDLEOP;
											inCmdReady <= '0';
										else
											error_valid  <= '1';
											error_opcode <= "1000" & inCmdOpCode(3 downto 0);

											-- we'll resend proposals between this and last acked...
											if (inCmdZxid_I <= proposedZxid(conv_integer(inCmdUser_I))) then
												preloadMyZxid      <= myZxid(conv_integer(inCmdUser_I));
												preloadProposedZxid <= proposedZxid(conv_integer(inCmdUser_I));											

												inCmdOpCode      <= std_logic_vector(conv_unsigned(OPCODE_FAKESYNCREQ, 8));
												myState    <= ST_HANDLEOP;
												inCmdReady <= '0';
											end if;

										end if;
									else
										error_valid  <= '1';
										error_opcode <= proposedZxid(conv_integer(inCmdUser_I))(7 downto 0); -- & inCmdOpCode(3 downto 0);

									end if;

								when (OPCODE_SYNCREQ) =>
									traceLoc <= "00001001";

									preloadMyZxid <= myZxid(conv_integer(inCmdUser_I));	
									preloadProposedZxid <= proposedZxid(conv_integer(inCmdUser_I));

									if ((isMyPhaseNormal='1' and isMyRoleLeader='1' and proposedZxid(conv_integer(inCmdUser_I)) >= inCmdZxid_I) or (isMyRoleFollower='1')) then
										myState <= ST_HANDLEOP;
										inCmdReady <= '0';										
									else
										error_valid  <= '1';
										error_opcode <= proposedZxid(conv_integer(inCmdUser_I))(7 downto 0); -- & inCmdOpCode(3 downto 0);

									end if;

								when (OPCODE_PROPOSAL) =>
									traceLoc <= "00001010";

									preloadMyZxid <= myZxid(conv_integer(inCmdUser_I));
									preloadMyEpoch <= myEpoch(conv_integer(inCmdUser_I));

									if (isMyPhaseNormal='1' and isMyRoleFollower='1' and leaderPeerId(conv_integer(inCmdUser_I)) = inCmdPeerId_I) then

										myState <= ST_HANDLEOP;
										inCmdReady <= '0';

									else
										error_valid  <= '1';
										error_opcode <= inCmdOpCode_I;
									end if;

								when (OPCODE_SYNCRESP) =>
									traceLoc <= "00001011";
									if (isMyPhaseNormal='1' and isMyRoleFollower='1' and leaderPeerId(conv_integer(inCmdUser_I)) = inCmdPeerId_I) then
										if (inCmdZxid_I = myZxid(conv_integer(inCmdUser_I)) + 1 and inCmdEpoch_I = myEpoch(conv_integer(inCmdUser_I))) then
											myState    <= ST_HANDLEOP;
											inCmdReady <= '0';

										else
											error_valid  <= '1';
											error_opcode <= "1000" & inCmdOpCode_I(3 downto 0);
										end if;

									else
										error_valid  <= '1';
										error_opcode <= inCmdOpCode_I;
									end if;

								when (OPCODE_COMMIT) =>
									traceLoc <= "00001100";
									if (isMyPhaseNormal='1' and isMyRoleFollower='1' and leaderPeerId(conv_integer(inCmdUser_I)) = inCmdPeerId_I) then
										if (inCmdZxid_I <= myZxid(conv_integer(inCmdUser_I)) and inCmdEpoch_I = myEpoch(conv_integer(inCmdUser_I))) then
											log_search_valid <= '1';
											log_search_since <= '0';
											log_search_zxid  <= inCmdZxid_I;
											log_search_user  <= inCmdUser_I;

											myState    <= ST_HANDLEOP;
											cmdSent    <= '0';
											inCmdReady <= '0';

										else
											error_valid  <= '1';
											error_opcode <= inCmdOpCode_I;

										end if;

									end if;

								when (OPCODE_CUREPOCH) =>
									traceLoc <= "00001101";

									preloadMyPeerId <= myPeerId(conv_integer(inCmdUser_I));
									preloadPeerCount <= peerCount(conv_integer(inCmdUser_I));

									preloadMyPhase <= myPhase(conv_integer(inCmdUser_I));
									preloadMyRole <= myRole(conv_integer(inCmdUser_I));

									myState    <= ST_HANDLEOP;
									inCmdReady <= '0';




								when (OPCODE_NEWEPOCH) =>
									traceLoc <= "00001110";

									preloadMyPeerId <= myPeerId(conv_integer(inCmdUser_I));
									preloadPeerCount <= peerCount(conv_integer(inCmdUser_I));

									myState <= ST_HANDLEOP;
									inCmdReady <= '0';


								when (OPCODE_ACKEPOCH) =>
									traceLoc           <= "00001111";
									--thisPeersAckedZxid <= peerZxidAck(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & inCmdPeerId(PEER_BITS - 1 downto 0)));
									preloadVotedZxid   <= votedZxid(conv_integer(inCmdUser_I));
									preloadVotedEpoch  <= votedEpoch(conv_integer(inCmdUser_I));
									preloadMyZxid      <= myZxid(conv_integer(inCmdUser_I));
									myState            <= ST_HANDLEOP;
									inCmdReady         <= '0';

								when (OPCODE_SYNCLEADER) =>
									traceLoc <= "00010000";
									if (myPhase(conv_integer(inCmdUser_I)) = PH_SYNC and isMyRoleLeader='1') then
										myState    <= ST_HANDLEOP;
										inCmdReady <= '0';

										preloadVotedZxid <= votedZxid(conv_integer(inCmdUser_I));										
										preloadVotedEpoch  <= votedEpoch(conv_integer(inCmdUser_I));

									else
										error_valid  <= '1';
										error_opcode <= inCmdOpCode_I;
									end if;

								when (OPCODE_SYNCDRAM) =>
									traceLoc <= "11001100";

									if (isMyPhaseNormal='1' and isMyRoleFollower='1' and leaderPeerId(conv_integer(inCmdUser_I)) = inCmdPeerId_I) then
										myState    <= ST_HANDLEOP;
										inCmdReady <= '0';

									else
										error_valid  <= '1';
										error_opcode <= inCmdOpCode_I;
									end if;

								-- UNKNOWN/UNHANDLED OP CODE
								when others =>
									error_opcode <= inCmdOpCode_I;

					                if (inCmdOpCode_I /= OPCODE_READREQ and inCmdOpCode_I /= OPCODE_FLUSHDATASTORE and inCmdOpCode_I/=OPCODE_READCONDITIONAL) then
									  error_valid  <= '1';
					                end if;

									if (cmd_in_valid = '1' and inCmdReady = '1') then
										cmd_out_data  <= cmd_in_data;
										cmd_out_key   <= cmd_in_key;
										cmd_out_user  <= cmd_in_user;
										cmd_out_valid <= '1';
										inCmdReady    <= '0';

										if (inCmdOpCode_I = OPCODE_READREQ) then
											cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC) <= std_logic_vector(conv_unsigned(HTOP_GET, CMD_HTOP_LEN));
										end if;

										if (inCmdOpCode_I = OPCODE_READCONDITIONAL) then
											cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC) <= std_logic_vector(conv_unsigned(HTOP_GETCOND, CMD_HTOP_LEN));
										end if;

										myState <= ST_WAITOUTREADY;

									end if;

							end case;

						else
							if ((isMyPhaseNormal='1' or isMyPhaseElection='1') and sinceHeardFromLeader(conv_integer(inCmdUser_I)) > silenceThreshold(conv_integer(inCmdUser_I)) and silenceMeasured(conv_integer(inCmdUser_I)) = '1') then
								-- we need to send the next epoch to the prospective leader -- the next in the order.

								myState <= ST_TIMEOUT_LEADER;
								inCmdReady <= '0';

							end if;

						end if;

					---------------------------------------------------------------------
					-- HANDLE OP: perform changes to the state depending on the opcode
					---------------------------------------------------------------------
					when ST_HANDLEOP =>
						case (conv_integer(inCmdOpCode(CMD_TYPE_LEN - 1 downto 0))) is

							-- SETUP PEER
							when (OPCODE_SETUPPEER) =>
								myPeerId(conv_integer(inCmdUser)) <= inCmdPeerId(PEER_BITS-1 downto 0);

								myEpoch(conv_integer(inCmdUser))    <= (others => '0');
								myEpoch(conv_integer(inCmdUser))(0) <= '1';

								myIPAddr(conv_integer(inCmdUser))             <= inCmdZxid;
								myZxid(conv_integer(inCmdUser))(15 downto 0)  <= inCmdEpoch;
								myZxid(conv_integer(inCmdUser))(31 downto 16) <= (others => '0');

								myState    <= ST_WAITOP;
								inCmdReady <= '1';

								if (myRole(conv_integer(inCmdUser)) /= ROLE_UNKNOWN and myPhase(conv_integer(inCmdUser)) = PH_STARTUP and peerCount(conv_integer(inCmdUser)) /= 0) then
									myPhase(conv_integer(inCmdUser)) <= PH_NORMAL;
								end if;

							-- SET OWN OR OTHER's ROLE
							when (OPCODE_SETLEADER) =>
								if (inCmdPeerId = preloadMyPeerId) then
									prevRole(conv_integer(inCmdUser))     <= myRole(conv_integer(inCmdUser));
									myRole(conv_integer(inCmdUser))       <= ROLE_LEADER;
									proposedZxid(conv_integer(inCmdUser)) <= myZxid(conv_integer(inCmdUser));
									leaderPeerId(conv_integer(inCmdUser)) <= inCmdPeerId(PEER_BITS-1 downto 0);
									if (inCmdPeerId < peerCount(conv_integer(inCmdUser))) then
										nextLeaderId(conv_integer(inCmdUser)) <= inCmdPeerId + 1;
									else
										nextLeaderId(conv_integer(inCmdUser))    <= (others => '0');
										nextLeaderId(conv_integer(inCmdUser))(0) <= '1';
									end if;

								else
									prevRole(conv_integer(inCmdUser)) <= myRole(conv_integer(inCmdUser));
									myRole(conv_integer(inCmdUser))   <= ROLE_FOLLOWER;

									leaderPeerId(conv_integer(inCmdUser)) <= inCmdPeerId(PEER_BITS-1 downto 0);

									if (inCmdPeerId < peerCount(conv_integer(inCmdUser))) then
										nextLeaderId(conv_integer(inCmdUser)) <= inCmdPeerId(PEER_BITS-1 downto 0) + 1;
									else
										nextLeaderId(conv_integer(inCmdUser))    <= (others => '0');
										nextLeaderId(conv_integer(inCmdUser))(0) <= '1';
									end if;

								end if;

								myState    <= ST_WAITOP;
								inCmdReady <= '1';

								if (preloadMyPeerId/= 0 and myPhase(conv_integer(inCmdUser)) = PH_STARTUP and peerCount(conv_integer(inCmdUser)) /= 0) then
									myPhase(conv_integer(inCmdUser)) <= PH_NORMAL;
								end if;

							-- ADD PEER (init connection)
							when (OPCODE_ADDPEER) =>
								if (inCmdPeerId /= 0) then --currPeerIP((conv_integer(inCmdPeerId))) = 0) then

									peerZxidAck(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & inCmdPeerId(PEER_BITS - 1 downto 0))) <= (others => '0');
									peerZxidCmt(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & inCmdPeerId(PEER_BITS - 1 downto 0))) <= (others => '0');

									if (inCmdZxid(31 downto 0) /= 0) then
										myState    <= ST_OPENTCPCONN;
										inCmdReady <= '0';
									else

										-- this is a parallel connection, we just need to remember
										-- which port it is
										peerSessId(conv_integer(inCmdUser))((conv_integer(inCmdPeerId))) <= "1" & inCmdEpoch(14 downto 0);

										myState    <= ST_WAITOP;
										inCmdReady <= '1';
									end if;

									if (peerSessId(conv_integer(inCmdUser))((conv_integer(inCmdPeerId))) = 0) then
										peerCount(conv_integer(inCmdUser))          <= preloadPeerCount + 1;
										peerCountForCommit(conv_integer(inCmdUser)) <= preloadPeerCount + 2; -- adding two because peercount doesn't include myself
									end if;

									peerIP(conv_integer(inCmdUser))((conv_integer(inCmdPeerId))) <= inCmdEpoch(15 downto 0) & inCmdZxid;
									peerIPNonZero(conv_integer(inCmdUser))((conv_integer(inCmdPeerId))) <= '1';

									connToWaiting   <= '0';
									connToIpAddress <= inCmdZxid;
									connToPort      <= inCmdEpoch(15 downto 0);
									connToPeerId    <= inCmdPeerId;

								else
									error_valid  <= '1';
									error_opcode <= inCmdOpCode;
								end if;

							when (OPCODE_WRITEREQ) =>
								log_add_valid <= '1';
								log_add_zxid  <= proposedZxid(conv_integer(inCmdUser)) + 1;
								log_add_user  <= inCmdUser;
								log_add_key   <= inCmdKey;

								sendPayloadSize <= inCmdPayloadSize;
								sendEpoch       <= myEpoch(conv_integer(inCmdUser));
								sendZxid        <= proposedZxid(conv_integer(inCmdUser)) + 1;
								sendOpcode      <= std_logic_vector(conv_unsigned(OPCODE_PROPOSAL, 8));

								returnState <= ST_FINISH_WRITEREQ;

								--for PEER in MAX_PEERS downto 0 loop
								--	currPeerIP(PEER) <= peerIP(conv_integer(inCmdUser))(PEER);
								--end loop;
								inCmdUserReg <= inCmdUser;

								preloadPeerIPNZ <= peerIPNonZero(conv_integer(inCmdUser));


								myState    <= ST_SENDTOALL;
								inCmdReady <= '0';
								sendCount  <= (others => '0');

							when (OPCODE_UNVERSIONEDWRITE) =>
								if (cmd_out_ready = '1' and malloc_ready = '1') then
									cmd_out_data  <= inCmdAllData;
									cmd_out_key   <= inCmdKey;
									cmd_out_user  <= inCmdUser;
									cmd_out_valid <= '1';
									inCmdReady    <= '0';

									cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC) <= std_logic_vector(conv_unsigned(HTOP_SETCUR, CMD_HTOP_LEN));

									malloc_valid <= '1';
									malloc_data  <= inCmdPayloadSize(15 - 3 downto 0) & "000";

									myState    <= ST_WAITOP;
									inCmdReady <= '1';

								end if;

							when (OPCODE_UNVERSIONEDDELETE) =>
								if (cmd_out_ready = '1') then
									cmd_out_data  <= inCmdAllData;
									cmd_out_key   <= inCmdKey;
									cmd_out_user  <= inCmdUser;
									cmd_out_valid <= '1';
									inCmdReady    <= '0';

									cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC) <= std_logic_vector(conv_unsigned(HTOP_DELCUR, CMD_HTOP_LEN));								

									myState    <= ST_WAITOP;
									inCmdReady <= '1';

								end if;

							when (OPCODE_PROPOSAL) =>

								--sinceHeardFromLeader <= (others => '0');

								if (inCmdZxid = preloadMyZxid + 1 and inCmdEpoch = preloadMyEpoch) then
									--myState    <= ST_HANDLEOP;
									--inCmdReady <= '0';								

									if (cmd_out_ready = '1' and malloc_ready = '1') then
										log_add_valid <= '1';
										log_add_zxid  <= inCmdZxid;
										log_add_user  <= inCmdUser;
										log_add_key   <= inCmdKey;

										myZxid(conv_integer(inCmdUser)) <= inCmdZxid;

										cmd_out_valid                                                                 <= '1';
										cmd_out_data(CMD_PAYLSIZE_LOC + CMD_PAYLSIZE_LEN - 1 downto CMD_PAYLSIZE_LOC) <= (others => '0');
										cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC)             <= std_logic_vector(conv_unsigned(OPCODE_ACKPROPOSE, 8));
										cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)          <= inCmdEpoch;
										cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)             <= inCmdZxid;
										cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       			 <= preloadMyPeerId;
										cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC +PEER_BITS)   <= (others=>'0');
										cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC)       <= peerSessId(conv_integer(inCmdUser))(conv_integer(leaderPeerId(conv_integer(inCmdUser)))); --inCmdSessID;
										cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC)             <= std_logic_vector(conv_unsigned(HTOP_SETNEXT, CMD_HTOP_LEN));
										cmd_out_data(CMD_PAYLSIZE_LOC + CMD_PAYLSIZE_LEN - 1 downto CMD_PAYLSIZE_LOC) <= inCmdPayloadSize;
										cmd_out_key                                                                   <= inCmdKey;
	                  					cmd_out_user                                                                  <= inCmdUser;

										malloc_valid <= '1';
										malloc_data  <= inCmdPayloadSize(15 - 3 downto 0) & "000";

										myState    <= ST_WAITOP;
										inCmdReady <= '1';
									end if;

								else
									myState <= ST_REQUESTSYNC;
									---myState      <= ST_HANDLEOP;									
									inCmdReady   <= '0';
									--myState    <= ST_WAITOP;
									--inCmdReady <= '1';

									error_valid  <= '1';
									error_opcode <= "1010" & inCmdOpCode_I(3 downto 0);
								end if;

							when (OPCODE_SYNCRESP) =>
								log_add_valid <= '1';
								log_add_zxid  <= inCmdZxid;
								log_add_user  <= inCmdUser;
								log_add_key   <= inCmdKey;

								myZxid(conv_integer(inCmdUser)) <= inCmdZxid;

								myState    <= ST_WAITOP;
								inCmdReady <= '1';

							when (OPCODE_SYNCREQ) =>
				
								syncZxid(conv_integer(inCmdUser)) <= inCmdZxid;
								preloadSyncZxid <= inCmdZxid;							

								if (myRole(conv_integer(inCmdUser)) = ROLE_FOLLOWER) then
									proposedZxid(conv_integer(inCmdUser)) <= preloadMyZxid;
								end if;

								if (myZxid(conv_integer(inCmdUser)) - inCmdZxid < 128) then
									myState    <= ST_GETLOGSYNC;
									inCmdReady <= '0';
								else
									myState <= ST_WAITOP; --ST_DRAMSYNC;
									--if (syncPrepare = '0') then
									--	syncModeWaited <= (others => '0');
									--	syncPeerId     <= inCmdPeerID(PEER_BITS-1 downto 0);
									--end if;
									--syncPrepare <= '1';

									--WE CAN'T SYNC FROM THAT FAR...
									error_valid <= '1';
									error_opcode <= "10011001";
									inCmdReady <= '1';
								end if;


							when (OPCODE_FAKESYNCREQ) =>

								-- we'll pretend that the request was to sync everything since the last commit!
				
								syncZxid(conv_integer(inCmdUser)) <= peerZxidCmt(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & inCmdPeerId(PEER_BITS - 1 downto 0)))+1;
								preloadSyncZxid <= peerZxidCmt(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & inCmdPeerId(PEER_BITS - 1 downto 0)))+1;					
								
								if (myZxid(conv_integer(inCmdUser)) > peerZxidCmt(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & inCmdPeerId(PEER_BITS - 1 downto 0)))) then
									myState    <= ST_GETLOGSYNC;
									inCmdReady <= '0';
								else
									myState <= ST_WAITOP; --ST_DRAMSYNC;
									--if (syncPrepare = '0') then
									--	syncModeWaited <= (others => '0');
									--	syncPeerId     <= inCmdPeerID(PEER_BITS-1 downto 0);
									--end if;
									--syncPrepare <= '1';

									--WE CAN'T SYNC FROM THAT FAR...
									error_valid <= '1';
									error_opcode <= "11011101";
									inCmdReady <= '1';
								end if;


							when (OPCODE_SYNCDRAM) =>
								log_add_valid <= '1';
								log_add_zxid  <= inCmdZxid;
								log_add_user  <= inCmdUser;
								log_add_key   <= inCmdKey;

								myZxid(conv_integer(inCmdUser)) <= inCmdZxid;

								if (inCmdZxid + 1 = htSyncSize) then
									myZxid(conv_integer(inCmdUser))(15 downto 0) <= inCmdEpoch;
								end if;

								myState    <= ST_WAITOP;
								inCmdReady <= '1';

							when (OPCODE_COMMIT) =>
								if (log_found_valid = '1') then
									foundInLog <= '1';
								end if;

								if ((foundInLog = '1' or log_found_valid = '1') and cmdSent = '0') then
									cmd_out_valid                                                           <= '1';
									--cmd_out_data(CMD_PAYLSIZE_LOC+CMD_PAYLSIZE_LEN-1 downto CMD_PAYLSIZE_LOC) <= log_found_size;
									cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC)       <= (others => '0');
									cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1)                           <= '1'; -- this is to stop the getter from sending an answer
									cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)    <= myEpoch(conv_integer(inCmdUser));
									cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)       <= inCmdZxid;
									cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       			 <= preloadMyPeerId;
									cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC +PEER_BITS)   <= (others=>'0');
									cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC) <= (others => '1');

									cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC) <= std_logic_vector(conv_unsigned(HTOP_FLIPPOINT, CMD_HTOP_LEN));

									cmd_out_key  <= log_found_key;
									cmd_out_user <= inCmdUser;

									-- we need this to route the request to the app logic
									cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1) <= '0';
									cmdSent                                           <= '1';

								end if;

								if (foundInLog = '1' and cmd_out_ready = '1') then
									foundInLog <= '0';
									myState    <= ST_WAITOP;
									inCmdReady <= '1';
									cmdSent    <= '0';
								end if;

							when (OPCODE_ACKPROPOSE) =>

								--this is the dfault behavior...
								myState    <= ST_WAITOP;
								inCmdReady <= '1';

								
								peerZxidAck(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & inCmdPeerId(PEER_BITS - 1 downto 0))) <= inCmdZxid;

								if (thisPeersCmtdZxid = thisPeersAckedZxid) then
									-- this means that we did not send them the commit for
									-- this zxid yet

									loopIteration       <= peerCount(conv_integer(inCmdUser)) + 1;
									cmdForParallelValid <= '0';
									cmdForParallelData  <= (others => '0');

                                    quorumIteration <= peerCount(conv_integer(inCmdUser)) + 1;
									quorumIterationVar := peerCount(conv_integer(inCmdUser)) + 1;
									quorumIterationMinus1 <= peerCount(conv_integer(inCmdUser));
									commitableCount <= (others => '0');

									--for PEER in MAX_PEERS downto 0 loop
									--	currPeerIP(PEER) <= peerIP(conv_integer(inCmdUser))(PEER);
									--end loop;
									inCmdUserReg <= inCmdUser;

									preloadPeerZxidCmt <= peerZxidCmt(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & quorumIterationVar(PEER_BITS - 1 downto 0))); 

									if (inCmdPeerId = peerCount(conv_integer(inCmdUser)) + 1) then
										preloadPeerZxidAck <= inCmdZxid;
									else 
										preloadPeerZxidAck <= peerZxidAck(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & quorumIterationVar(PEER_BITS-1 downto 0)));										
									end if;

									preloadPeerCount <= peerCount(conv_integer(inCmdUser));
									preloadPeerCountForCommit <= peerCountForCommit(conv_integer(inCmdUser));
									preloadMyZxid <= myZxid(conv_integer(inCmdUser));

									preloadPeerIPNZ <= peerIPNonZero(conv_integer(inCmdUser));

									myState    <= ST_CHKQRM_ACKS;
									inCmdReady <= '0';
								end if;

							

							when (OPCODE_ACKEPOCH) =>
								myState    <= ST_WAITOP;
								inCmdReady <= '1';

								if (myRole(conv_integer(inCmdUser)) = ROLE_LEADER and myPhase(conv_integer(inCmdUser)) = PH_SYNC) then
									if (syncFrom(conv_integer(inCmdUser)) = inCmdPeerId(PEER_BITS-1 downto 0)) then
										myState    <= ST_SYNC_ELECTION;
										inCmdReady <= '0';
									else
										if (syncFrom(conv_integer(inCmdUser)) = preloadMyPeerId) then
											myPhase(conv_integer(inCmdUser))         <= PH_NORMAL;
											myEpoch(conv_integer(inCmdUser))         <= preloadVotedEpoch;
											leaderPeerId(conv_integer(inCmdUser))    <= preloadMyPeerId;
											proposedZxid(conv_integer(inCmdUser))    <= preloadVotedZxid;
											silenceMeasured(conv_integer(inCmdUser)) <= '0';
										end if;
									end if;
								end if;

								if (myRole(conv_integer(inCmdUser)) = ROLE_LEADER and myPhase(conv_integer(inCmdUser)) = PH_ELECTION) then
									myPhase(conv_integer(inCmdUser))      <= PH_NORMAL;
									myEpoch(conv_integer(inCmdUser))      <= preloadVotedEpoch;
									leaderPeerId(conv_integer(inCmdUser)) <= preloadMyPeerId;
									proposedZxid(conv_integer(inCmdUser)) <= preloadVotedZxid;
								end if;

								if (myRole(conv_integer(inCmdUser)) = ROLE_LEADER) then
									if (thisPeersAckedZxid <= preloadVotedZxid) then
										peerZxidAck(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & inCmdPeerId(PEER_BITS - 1 downto 0))) <= preloadVotedZxid;
										peerZxidCmt(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & inCmdPeerId(PEER_BITS - 1 downto 0))) <= preloadVotedZxid;
									end if;
								else
									error_valid  <= '1';
									error_opcode <= inCmdOpCode(7 downto 0);
								end if;

							when (OPCODE_SYNCLEADER) =>

								if (inCmdZxid = preloadVotedZxid) then
									myZxid(conv_integer(inCmdUser))          <= preloadVotedZxid;
									proposedZxid(conv_integer(inCmdUser))    <= preloadVotedZxid;
									myPhase(conv_integer(inCmdUser))         <= PH_NORMAL;
									proposedZxid(conv_integer(inCmdUser))    <= preloadVotedZxid;
									silenceMeasured(conv_integer(inCmdUser)) <= '0';
								end if;

								log_add_valid <= '1';
								log_add_zxid  <= inCmdZxid + 1;
								log_add_key   <= inCmdKey;
								log_add_user  <= inCmdUser;

								inCmdReady <= '1';
								myState    <= ST_WAITOP;

							when (OPCODE_CUREPOCH) =>

								inCmdReady <= '1';
								myState    <= ST_WAITOP;

								if (preloadMyPhase = PH_ELECTION) then
									
									prevRole(conv_integer(inCmdUser))     <= preloadMyRole;
									nextLeaderId(conv_integer(inCmdUser)) <= preloadMyPeerId;
									peerEpoch(conv_integer(inCmdUser))(conv_integer(inCmdPeerId))(15 downto 0) <= inCmdEpoch;
									voteCount(conv_integer(inCmdUser)) <= voteCount(conv_integer(inCmdUser)) + 1;

									if (inCmdEpoch > votedEpoch(conv_integer(inCmdUser))) then
										votedEpoch(conv_integer(inCmdUser)) <= inCmdEpoch;
										votedZxid(conv_integer(inCmdUser))  <= inCmdZxid;
										syncFrom(conv_integer(inCmdUser))   <= inCmdPeerId(PEER_BITS-1 downto 0);
									end if;

									if (voteCount(conv_integer(inCmdUser)) + 1 >= preloadPeerCount(PEER_BITS-1 downto 1)) then
										inCmdReady <= '0';
										myState    <= ST_SENDNEWEPOCH;
									end if;

								else 

									--if (myPhase=PH_NORMAL and myRole=ROLE_FOLLOWER) then
									--  inCmdReady <= '0';
									--  myState <= ST_SAYWHOISLEADER;
									--end if;

									if (preloadMyPhase = PH_NORMAL and preloadMyRole = ROLE_LEADER and myEpoch(conv_integer(inCmdUser)) >= inCmdEpoch) then
										inCmdReady <= '0';
										myState    <= ST_SENDNEWEPOCH_JOIN;

									end if;

									if (preloadMyPhase = PH_NORMAL and ((preloadMyRole = ROLE_LEADER and myEpoch(conv_integer(inCmdUser)) < inCmdEpoch) or (preloadMyRole = ROLE_FOLLOWER))) then
										nextLeaderId(conv_integer(inCmdUser)) <= preloadMyPeerId;
										myPhase(conv_integer(inCmdUser))      <= PH_ELECTION;
										prevRole(conv_integer(inCmdUser))     <= preloadMyRole;

										peerEpoch(conv_integer(inCmdUser))(conv_integer(inCmdPeerId))(15 downto 0) <= inCmdEpoch;

										voteCount(conv_integer(inCmdUser)) <= "0001";

										if (myEpoch(conv_integer(inCmdUser)) < inCmdEpoch) then
											votedEpoch(conv_integer(inCmdUser)) <= inCmdEpoch;
											votedZxid(conv_integer(inCmdUser))  <= inCmdZxid;
											syncFrom(conv_integer(inCmdUser))   <= inCmdPeerId(PEER_BITS-1 downto 0);
										else
											votedEpoch(conv_integer(inCmdUser)) <= myEpoch(conv_integer(inCmdUser));
											votedZxid(conv_integer(inCmdUser))  <= preloadMyZxid;
											syncFrom(conv_integer(inCmdUser))   <= preloadMyPeerId;
										end if;

										if (2 >= preloadPeerCount(PEER_BITS-1 downto 1)) then
											inCmdReady <= '0';
											myState    <= ST_SENDNEWEPOCH;
										end if;
									end if;
								end if;

							when (OPCODE_NEWEPOCH) =>

								inCmdReady <= '1';
								myState    <= ST_WAITOP;

								if (inCmdPeerId(PEER_BITS-1 downto 0) = leaderPeerId(conv_integer(inCmdUser))) then
									sinceHeardFromLeader(conv_integer(inCmdUser)) <= (others => '0');
								end if;

								if (myPhase(conv_integer(inCmdUser)) = PH_ELECTION and inCmdPeerId(PEER_BITS-1 downto 0) = nextLeaderId(conv_integer(inCmdUser))) then
									myEpoch(conv_integer(inCmdUser))         <= inCmdEpoch;
									myZxid(conv_integer(inCmdUser))          <= inCmdZxid;
									leaderPeerId(conv_integer(inCmdUser))    <= inCmdPeerId(PEER_BITS-1 downto 0);
									myPhase(conv_integer(inCmdUser))         <= PH_NORMAL;
									prevRole(conv_integer(inCmdUser))        <= myRole(conv_integer(inCmdUser));
									myRole(conv_integer(inCmdUser))          <= ROLE_FOLLOWER;
									silenceMeasured(conv_integer(inCmdUser)) <= '0';

									cmd_out_valid                                                                 <= '1';
									cmd_out_data(CMD_PAYLSIZE_LOC + CMD_PAYLSIZE_LEN - 1 downto CMD_PAYLSIZE_LOC) <= (others => '0');
									cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC)             <= std_logic_vector(conv_unsigned(OPCODE_ACKEPOCH, 8));
									cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)          <= inCmdEpoch;
									cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)             <= inCmdZxid;
									cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       			 <= preloadMyPeerId;
									cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC +PEER_BITS)   <= (others=>'0');
									cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC)       <= peerSessId(conv_integer(inCmdUser))(conv_integer(inCmdPeerId));
									cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC)             <= std_logic_vector(conv_unsigned(HTOP_IGNORE, CMD_HTOP_LEN));
									cmd_out_key                                                                   <= inCmdKey;
                					cmd_out_user                                                                  <= inCmdUser;

								end if;

								if (myPhase(conv_integer(inCmdUser)) = PH_NORMAL and myRole(conv_integer(inCmdUser)) = ROLE_LEADER and inCmdPeerId(PEER_BITS-1 downto 0) > myPeerId(conv_integer(inCmdUser))) then
									if (inCmdPeerId(PEER_BITS-1 downto 0) < preloadPeerCount) then
										nextLeaderId(conv_integer(inCmdUser)) <= inCmdPeerId + 1;
									else
										nextLeaderId(conv_integer(inCmdUser))    <= (others => '0');
										nextLeaderId(conv_integer(inCmdUser))(0) <= '1';
									end if;
									leaderPeerId(conv_integer(inCmdUser)) <= inCmdPeerId(PEER_BITS-1 downto 0);
									prevRole(conv_integer(inCmdUser))     <= myRole(conv_integer(inCmdUser));
									myRole(conv_integer(inCmdUser))       <= ROLE_FOLLOWER;
									myEpoch(conv_integer(inCmdUser))      <= inCmdEpoch;
									myZxid(conv_integer(inCmdUser))       <= inCmdZxid;

									cmd_out_valid                                                                 <= '1';
									cmd_out_data(CMD_PAYLSIZE_LOC + CMD_PAYLSIZE_LEN - 1 downto CMD_PAYLSIZE_LOC) <= (others => '0');
									cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC)             <= std_logic_vector(conv_unsigned(OPCODE_ACKEPOCH, 8));
									cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)          <= inCmdEpoch;
									cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)             <= inCmdZxid;
									cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       			 <= preloadMyPeerId;
									cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC +PEER_BITS)   <= (others=>'0');
									cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC)       <= peerSessId(conv_integer(inCmdUser))(conv_integer(inCmdPeerId));
									cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC)             <= std_logic_vector(conv_unsigned(HTOP_IGNORE, CMD_HTOP_LEN));
									cmd_out_key                                                                   <= inCmdKey;
                					cmd_out_user                                                                  <= inCmdUser;

								--myPhase <= PH_ELECTION;
								--myRole <= ROLE_FOLLOWER;
								end if;

							-- UNKNOWN/UNHANDLED OP CODE
							when others =>
								error_valid  <= '1';
								error_opcode <= "1000" & inCmdOpCode(3 downto 0);

						end case;

					----------------------------------------------------------------------
					-- OPEN CONNECTION
					----------------------------------------------------------------------
					when ST_OPENTCPCONN =>
						open_conn_req_valid <= '0';
						traceLoc            <= "00010010";
						if (open_conn_req_ready = '1' and connToWaiting = '0') then
							open_conn_req_valid <= '1';
							open_conn_req_data  <= connToPort(15 downto 0) & connToIpAddress;

							connToWaiting <= '1';
						end if;

						if (connToWaiting = '1' and open_conn_resp_valid = '1') then
							myState    <= ST_WAITOP;
							inCmdReady <= '1';

							if (open_conn_resp_data(16) = '1') then
								peerSessId(conv_integer(inCmdUser))((conv_integer(connToPeerId))) <= open_conn_resp_data(15 downto 0);

							else
								error_valid  <= '1';
								error_opcode <= inCmdOpCode;
							end if;
						end if;

					---------------------------------------------------------------------
					-- SEND MSG TO ALL PEERS
					---------------------------------------------------------------------
					when ST_SENDTOALL =>
						traceLoc <= "00010011";
						if (cmd_out_ready = '1') then
							if (preloadMyPeerId /= loopIteration and (not (loopIteration = 0)) and sendEnableMask(conv_integer(loopIteration)) = '1') then
								if (returnState = ST_FINISH_COMMIT or returnState = ST_FINISH_COMMIT_LATE) then
									peerZxidCmt(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & loopIteration(PEER_BITS - 1 downto 0))) <= inCmdZxid;
								end if;

								if (loopIteration = peerCount(conv_integer(inCmdUser)) + 2) then
									-- prepare local request first

									cmd_out_valid                                                                 <= '1';
									cmd_out_data(CMD_PAYLSIZE_LOC + CMD_PAYLSIZE_LEN - 1 downto CMD_PAYLSIZE_LOC) <= sendPayloadSize;
									cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC)             <= sendOpcode;
									cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)          <= (others => '0');
									cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)             <= (others => '0');
									cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       <= peerCount(conv_integer(inCmdUser))(PEER_BITS-1 downto 0);
									cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto PEER_BITS + CMD_PEERID_LOC)       <= (others => '0');
									cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC)       <= (others => '0');
									cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC)             <= std_logic_vector(conv_unsigned(HTOP_SETNEXT, CMD_HTOP_LEN));
									cmd_out_key                                                                   <= inCmdKey;
									cmd_out_user                                                                  <= inCmdUser;

								end if;

								if (loopIteration < peerCount(conv_integer(inCmdUser)) + 2 and preloadPeerIPNZ(conv_integer(loopIteration)) = '1') then
									-- if this peer exists

									--if (peerIP(conv_integer(loopIteration))(31 downto 24)/=0) then
									-- the highest byte is non-zero, this is a proper IP. use TCP
									sendCount                                                                     <= sendCount + 1;
									cmd_out_valid                                                                 <= '1';
									cmd_out_data(CMD_PAYLSIZE_LOC + CMD_PAYLSIZE_LEN - 1 downto CMD_PAYLSIZE_LOC) <= sendPayloadSize;
									cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC)             <= sendOpcode;
									cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)          <= sendEpoch;
									cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)             <= sendZxid;
									cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       			 <= preloadMyPeerId;
									cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC +PEER_BITS)   <= (others=>'0');
									cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC)       <= peerSessId(conv_integer(inCmdUser))(conv_integer(loopIteration));
									if (sendOpcode = 2) then
										cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC) <= std_logic_vector(conv_unsigned(HTOP_IGNOREPROP, CMD_HTOP_LEN));
									else
										cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC) <= std_logic_vector(conv_unsigned(HTOP_IGNORE, CMD_HTOP_LEN));
									end if;
									cmd_out_key  <= inCmdKey;
									cmd_out_user <= inCmdUser;

								--		  else
								--		    -- this is a parallel-interface
								--		    cmdForParallelValid <= '1';
								--		    cmdForParallelData(CMD_PAYLSIZE_LOC+CMD_PAYLSIZE_LEN-1 downto CMD_PAYLSIZE_LOC) <= sendPayloadSize;
								--		    cmd_out_data(CMD_TYPE_LEN+CMD_TYPE_LOC-1 downto CMD_TYPE_LOC) <= sendOpcode;
								--		    cmdForParallelData(CMD_EPOCH_LOC+CMD_EPOCH_LEN-1 downto CMD_EPOCH_LOC) <= sendEpoch;
								--		    cmdForParallelData(CMD_ZXID_LOC+CMD_ZXID_LEN-1 downto CMD_ZXID_LOC) <= sendZxid;
								--		    cmdForParallelData(CMD_PEERID_LEN+CMD_PEERID_LOC-1 downto CMD_PEERID_LOC) <= myPeerId;
								--		    cmdForParallelData(CMD_SESSID_LOC+CMD_SESSID_LEN-1 downto CMD_SESSID_LOC) <= cmdForParallelData(CMD_SESSID_LOC+CMD_SESSID_LEN-1 downto CMD_SESSID_LOC) or peerSessId(conv_integer(loopIteration));

								--		  end if;


								end if;
							end if;

							if (loopIteration /= 0) then
								loopIteration <= loopIteration - 1;
							end if;

							if (loopIteration = 0 and cmd_out_ready = '1') then
								if (cmdForParallelValid = '0') then
									myState    <= returnState;
									inCmdReady <= '0';

									if (returnState = ST_WAITOP) then
										inCmdReady <= '1';
									end if;
								else
									sendCount           <= sendCount + 1;
									--cmd_out_valid <= cmdForParallelValid;
									--cmd_out_data <= cmdForParallelData;
									cmdForParallelValid <= '0';
								end if;
							end if;

						end if;

					-----------------------------------------------------------------------
					-- FINISH PROPOSAL SENDING
					-----------------------------------------------------------------------
					when ST_FINISH_WRITEREQ =>
						traceLoc <= "00010100";
						if (malloc_ready = '1') then
							proposedZxid(conv_integer(inCmdUser)) <= proposedZxid(conv_integer(inCmdUser)) + 1;
							myState                               <= ST_WAITOP;
							inCmdReady                            <= '1';

							sessMemEnable   <= '1';
							sessMemWrite(0) <= '1';
							sessMemAddr     <= inCmdUser & sendZxid(MAX_OUTSTANDING_REQS_BITS - USER_BITS - 1 downto 0);
							sessMemDataIn   <= receiveTime(15 downto 0) & sendZxid(15 downto 0) & inCmdSessID(15 downto 0);

							malloc_valid <= '1';
							malloc_data  <= inCmdPayloadSize(15 - 3 downto 0) & "000";
						end if;

					-----------------------------------------------------------------------
					-- FINISH COMMIT SENDING
					-----------------------------------------------------------------------
					when ST_FINISH_COMMIT =>
						--if (cmd_out_ready='1') then
						traceLoc <= "00010101";
						if (sessMemEnable = '0' and sessMemEnableD1 = '0' and sessMemEnableD2 = '0') then
							sessMemEnable   <= '1';
							sessMemWrite(0) <= '0';
							sessMemAddr     <= inCmdUser & inCmdZxid(MAX_OUTSTANDING_REQS_BITS - USER_BITS - 1 downto 0);

							responseTime <= internalClk(15 downto 0);
						end if;

						if (sessMemEnableD2 = '1') then
							if (preloadMyZxid + 1 = inCmdZxid) then
								myZxid(conv_integer(inCmdUser)) <= inCmdZxid;

								--	if (clientReqZxid(ieee.numeric_std.to_integer(ieee.numeric_std.unsigned(sendZxid(MAX_OUTSTANDING_REQS_BITS-1 downto 0))))=inCmdZxid(15 downto 0)) then
								--
								if (sessMemDataOut(31 downto 16) = inCmdZxid(15 downto 0)) then

									-- Removed becuase now that we have the app in there we want to get only 1 response.
									--cmd_out_valid <= '1';		  		  
									log_search_valid <= '1';
									log_search_since <= '0';
									log_search_zxid  <= inCmdZxid;
									log_search_user  <= inCmdUser;
									cmdSent          <= '0';
									myState          <= ST_FINISH_COMMIT_DATAFORAPP;

								else
									error_valid   <= '1';
									error_opcode  <= (others => '1');
									cmd_out_valid <= '0';
									myState       <= ST_WAITOP;
									inCmdReady    <= '1';
								end if;

							--		  cmd_out_valid <= '0';
							--		  cmd_out_data(CMD_PAYLSIZE_LOC+CMD_PAYLSIZE_LEN-1 downto CMD_PAYLSIZE_LOC) <= (others => '0');
							--		  cmd_out_data(CMD_TYPE_LEN+CMD_TYPE_LOC-1 downto CMD_TYPE_LOC) <= (others => '0');
							--		  cmd_out_data(CMD_EPOCH_LOC+CMD_EPOCH_LEN-1 downto CMD_EPOCH_LOC) <= responseTime & sessMemDataOut(47 downto 32);
							--		  cmd_out_data(CMD_ZXID_LOC+CMD_ZXID_LEN-1 downto CMD_ZXID_LOC) <= inCmdZxid;
							--		  cmd_out_data(CMD_PEERID_LEN+CMD_PEERID_LOC-1 downto CMD_PEERID_LOC) <= myPeerId;
							--		  cmd_out_data(CMD_SESSID_LOC+CMD_SESSID_LEN-1 downto CMD_SESSID_LOC) <= sessMemDataOut(15 downto 0);
							--clientReqSess(ieee.numeric_std.to_integer(ieee.numeric_std.unsigned(sendZxid(MAX_OUTSTANDING_REQS_BITS-1 downto 0))));


							else
								error_valid  <= '1';
								error_opcode <= "0100" & inCmdOpCode(3 downto 0);

								myState    <= ST_WAITOP;
								inCmdReady <= '1';
							end if;

						end if;

					--end if;

					when ST_FINISH_COMMIT_DATAFORAPP =>
						traceLoc <= "00010110";
						if (log_found_valid = '1') then
							foundInLog <= '1';
						end if;

						if ((foundInLog = '1' or log_found_valid = '1') and cmdSent = '0' and malloc_ready = '1') then
							cmd_out_key  <= log_found_key;
							cmd_out_user <= inCmdUser;

							cmd_out_valid                                                     <= '1';
							--cmd_out_data(CMD_PAYLSIZE_LOC+CMD_PAYLSIZE_LEN-1 downto CMD_PAYLSIZE_LOC) <= log_found_size;

							--decided whether RESPONSE IS SILENT in the WRITE modules
							cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC) <= (others => '0');
							if (myRole(conv_integer(inCmdUser)) = ROLE_FOLLOWER) then
								cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1) <= '1';
							end if;
							cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)    <= myEpoch(conv_integer(inCmdUser)); --sessMemDataOut(47 downto 32) & myEpoch(15 downto 0); -- RESPONSE TIME DEBUG
							cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)       <= inCmdZxid;
							cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       			 <= preloadMyPeerId;
							cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC +PEER_BITS)   <= (others=>'0');
							cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC) <= sessMemDataOut(15 downto 0);
							cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC)       <= std_logic_vector(conv_unsigned(HTOP_FLIPPOINT, CMD_HTOP_LEN));
							cmdSent                                                                 <= '1';

						--malloc_valid <= '1';
						--malloc_data <= inCmdPayloadSize(15-3 downto 0)&"000";

						end if;

						if (foundInLog = '1' and cmd_out_ready = '1') then
							cmdSent    <= '0';
							foundInLog <= '0';
							myState    <= ST_WAITOP;
							inCmdReady <= '1';
						end if;

					when ST_FINISH_COMMIT_LATE =>
						myState    <= ST_WAITOP;
						inCmdReady <= '1';

					-----------------------------------------------------------------------
					-- CHECK QUORUM FOR ACKS
					-----------------------------------------------------------------------
					when ST_CHKQRM_ACKS =>
						traceLoc <= "00010111";

						if (preloadMyZxid > inCmdZxid - 1) then
							flagLate <= '1';
						else 
							flagLate <= '0';
						end if;

						if (quorumIteration = 0) then

							myState <= ST_CHKQRM_ACKS_2;

						else
							quorumIteration <= quorumIteration - 1;
							quorumIterationMinus1 <= quorumIterationMinus1 - 1;

							preloadPeerZxidAck <= peerZxidAck(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & quorumIterationMinus1(PEER_BITS-1 downto 0)));
							preloadPeerZxidCmt <= peerZxidCmt(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & quorumIterationMinus1(PEER_BITS - 1 downto 0))); 

							if (preloadMyPeerId /= quorumIteration and quorumIteration /= 0) then
								if (preloadPeerIPNZ(conv_integer(quorumIteration)) ='1' and preloadPeerZxidAck > (inCmdZxid - 1) and preloadPeerZxidCmt = (inCmdZxid - 1)) then
									commitableCount <= commitableCount + 1;
								else
									sendEnableMask(conv_integer(quorumIteration)) <= '0';
								end if;
							else
								if (preloadMyPeerId = quorumIteration and preloadMyZxid = inCmdZxid - 1) then
									commitableCount <= commitableCount + 1;
								else
									sendEnableMask(conv_integer(quorumIteration)) <= '0';
								end if;
							end if;
						end if;

					when ST_CHKQRM_ACKS_2 =>

						preloadMyZxid <= myZxid(conv_integer(inCmdUser));

						--for majority need to add 1 to the peercount to count	      
						--ZSOLT
						if ((preloadPeerCount > 1 and commitableCountTimesTwo >= (preloadPeerCountForCommit))
		                   or (preloadPeerCount < 3 and commitableCount >= preloadPeerCount) 
		                    or (commitableCount = 1 and flagLate = '1')) 

						then

							sendPayloadSize <= (others => '0');
							sendZxid        <= inCmdZxid;
							sendEpoch       <= inCmdEpoch;
							sendOpcode      <= std_logic_vector(conv_unsigned(OPCODE_COMMIT, 8));

							for X in 0 to MAX_PEERS loop
								if (sendEnableMask(X) = '1' and preloadMyPeerId /= X) then
								-- moved this assignment into sendtoall
								--peerZxidCmt(conv_integer(inCmdUser(USER_BITS-1 downto 0)&conv_std_logic_vector(X, PEER_BITS))) <= inCmdZxid;
								end if;
							end loop;

							if (commitableCount = 1 and flagLate='1') then
								returnState <= ST_FINISH_COMMIT_LATE;
							else								
								returnState <= ST_FINISH_COMMIT;
							end if;

							myState    <= ST_SENDTOALL;
							inCmdReady <= '0';
							sendCount  <= (others => '0');
						else
							myState        <= ST_WAITOP;
							inCmdReady     <= '1';
							sendEnableMask <= (others => '1');
						end if;



					when ST_WAIT_MEMWRITE =>
						traceLoc <= "00011000";

						myState    <= returnState;
						inCmdReady <= '0';

					when ST_REQUESTSYNC =>
						traceLoc                                                                      <= "00011001";
						cmd_out_valid                                                                 <= '1';
						cmd_out_data(CMD_PAYLSIZE_LOC + CMD_PAYLSIZE_LEN - 1 downto CMD_PAYLSIZE_LOC) <= (others => '0');
						cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC)             <= std_logic_vector(conv_unsigned(OPCODE_SYNCREQ, 8));
						cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)          <= myEpoch(conv_integer(inCmdUser));
						cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)             <= myZxid(conv_integer(inCmdUser)) + 1;
						cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       			 <= preloadMyPeerId;
						cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC +PEER_BITS)   <= (others=>'0');
						cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC)       <= peerSessId(conv_integer(inCmdUser))(conv_integer(leaderPeerId(conv_integer(inCmdUser)))); --inCmdSessID;
						cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC)             <= std_logic_vector(conv_unsigned(HTOP_IGNORE, CMD_HTOP_LEN));
						cmd_out_user                                                                  <= inCmdUser;
						cmd_out_key                                                                   <= inCmdKey;

						myState    <= ST_WAITOP;
						inCmdReady <= '1';
					
					when ST_GETLOGSYNC =>
						traceLoc         <= "00011010";
						log_search_valid <= '1';
						log_search_since <= '0';
						log_search_zxid  <= preloadSyncZxid;
						log_search_user  <= inCmdUser;

						myState <= ST_SENDSYNC;

					when ST_SENDSYNC =>
						traceLoc <= "00011011";
						if (log_found_valid = '1') then
							foundInLog <= '1';
						end if;

						if ((foundInLog = '1' or log_found_valid = '1') and cmdSent = '0') then
							cmd_out_key  <= log_found_key;
							cmd_out_user <= inCmdUser;

							cmd_out_valid <= '1';
							--cmd_out_data(CMD_PAYLSIZE_LOC+CMD_PAYLSIZE_LEN-1 downto CMD_PAYLSIZE_LOC) <= log_found_size;

							if (myRole(conv_integer(inCmdUser)) = ROLE_LEADER) then								
								if (preloadSyncZxid = proposedZxid(conv_integer(inCmdUser))) then
									cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC) <= std_logic_vector(conv_unsigned(OPCODE_PROPOSAL, 8));
								else
									cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC) <= std_logic_vector(conv_unsigned(OPCODE_SYNCRESP, 8));
								end if;
							else
								cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC) <= std_logic_vector(conv_unsigned(OPCODE_SYNCLEADER, 8));
							end if;

							cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC)             <= std_logic_vector(conv_unsigned(HTOP_GETRAW, CMD_HTOP_LEN));

							cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)    <= myEpoch(conv_integer(inCmdUser)); -- RESPONSE TIME DEBUG
							cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)       <= preloadSyncZxid;
							cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       			 <= preloadMyPeerId;
							cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC +PEER_BITS)   <= (others=>'0');
							cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC) <= peerSessId(conv_integer(inCmdUser))(conv_integer(inCmdPeerId)); --inCmdSessID;
							cmdSent                                                                 <= '1';

						end if;

						if (foundInLog = '1' and cmd_out_ready = '1') then
							cmdSent    <= '0';
							foundInLog <= '0';
							if (preloadSyncZxid >= myZxid(conv_integer(inCmdUser)))then --proposedZxid(conv_integer(inCmdUser))) then
								myState    <= ST_WAITOP;
								inCmdReady <= '1';
							else
								myState                                                                                            <= ST_GETLOGSYNC;
								peerZxidAck(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & inCmdPeerId(PEER_BITS - 1 downto 0))) <= preloadSyncZxid;
								peerZxidCmt(conv_integer(inCmdUser(USER_BITS - 1 downto 0) & inCmdPeerId(PEER_BITS - 1 downto 0))) <= preloadSyncZxid;
								syncZxid(conv_integer(inCmdUser))                                                                  <= preloadSyncZxid + 1;
								preloadSyncZxid <= preloadSyncZxid + 1;
							end if;
						end if;

					when ST_PROP_LEADER =>
						traceLoc                                                                      <= "00011100";
						cmd_out_valid                                                                 <= '1';
						cmd_out_data(CMD_PAYLSIZE_LOC + CMD_PAYLSIZE_LEN - 1 downto CMD_PAYLSIZE_LOC) <= (others => '0');
						cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC)             <= std_logic_vector(conv_unsigned(OPCODE_CUREPOCH, 8));
						cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)          <= myEpoch(conv_integer(inCmdUser)) + 1;
						cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)             <= myZxid(conv_integer(inCmdUser));
						cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       			 <= preloadMyPeerId;
						cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC +PEER_BITS)   <= (others=>'0');
						cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC)       <= peerSessId(conv_integer(inCmdUser))(conv_integer(nextLeaderId(conv_integer(inCmdUser))));
						cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC)             <= std_logic_vector(conv_unsigned(HTOP_IGNORE, CMD_HTOP_LEN));
						cmd_out_user                                                                  <= inCmdUser;
						cmd_out_key                                                                   <= inCmdKey;

						sinceHeardFromLeader(conv_integer(inCmdUser)) <= (others => '0'); -- we zero the clock to
						-- make sure we give it
						-- enough time to answer...
						myState                                       <= ST_WAITOP;
						inCmdReady                                    <= '1';

					when ST_SENDNEWEPOCH =>
						traceLoc                              <= "00011101";
						sendPayloadSize                       <= (others => '0');
						sendEpoch                             <= votedEpoch(conv_integer(inCmdUser));
						sendZxid                              <= votedZxid(conv_integer(inCmdUser));
						sendOpcode                            <= std_logic_vector(conv_unsigned(OPCODE_NEWEPOCH, 8));
						myState                               <= ST_SENDTOALL;
						inCmdReady                            <= '0';
						sendCount                             <= (others => '0');
						loopIteration                         <= peercount(conv_integer(inCmdUser)) + 1;
						prevRole(conv_integer(inCmdUser))     <= myRole(conv_integer(inCmdUser));
						myRole(conv_integer(inCmdUser))       <= ROLE_LEADER;
						proposedZxid(conv_integer(inCmdUser)) <= myZxid(conv_integer(inCmdUser));

						myPhase(conv_integer(inCmdUser)) <= PH_SYNC;

						returnState <= ST_WAITOP;

					when ST_SENDNEWEPOCH_JOIN =>
						traceLoc                                                                      <= "00011110";
						cmd_out_valid                                                                 <= '1';
						cmd_out_data(CMD_PAYLSIZE_LOC + CMD_PAYLSIZE_LEN - 1 downto CMD_PAYLSIZE_LOC) <= (others => '0');
						cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC)             <= std_logic_vector(conv_unsigned(OPCODE_NEWEPOCH, 8));
						cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)          <= myEpoch(conv_integer(inCmdUser));
						cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)             <= myZxid(conv_integer(inCmdUser));
						cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       			 <= preloadMyPeerId;
						cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC +PEER_BITS)   <= (others=>'0');
						cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC)       <= peerSessId(conv_integer(inCmdUser))(conv_integer(inCmdPeerId));
						cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC)             <= std_logic_vector(conv_unsigned(HTOP_IGNORE, CMD_HTOP_LEN));
						cmd_out_user                                                                  <= inCmdUser;
						cmd_out_key                                                                   <= inCmdKey;

						myState    <= ST_WAITOP;
						inCmdReady <= '1';

					when ST_SAYWHOISLEADER =>
						traceLoc                                                                      <= "00011111";
						cmd_out_valid                                                                 <= '1';
						cmd_out_data(CMD_PAYLSIZE_LOC + CMD_PAYLSIZE_LEN - 1 downto CMD_PAYLSIZE_LOC) <= (others => '0');
						cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC)             <= std_logic_vector(conv_unsigned(OPCODE_SETLEADER, 8));
						cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)          <= (others => '0');
						cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)             <= (others => '0');
						cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       			 <= leaderPeerId(conv_integer(inCmdUser));
						cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC +PEER_BITS)   <= (others=>'0');
						cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC)       <= peerSessId(conv_integer(inCmdUser))(conv_integer(inCmdPeerId));
						cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC)             <= std_logic_vector(conv_unsigned(HTOP_IGNORE, CMD_HTOP_LEN));
						cmd_out_user                                                                  <= inCmdUser;
						cmd_out_key                                                                   <= inCmdKey;

						myState    <= ST_WAITOP;
						inCmdReady <= '1';

					when ST_SYNC_ELECTION =>
						traceLoc <= "00100000";
						myEpoch  <= votedEpoch;
						if (preloadVotedZxid > preloadMyZxid) then
							cmd_out_valid                                                                 <= '1';
							cmd_out_data(CMD_PAYLSIZE_LOC + CMD_PAYLSIZE_LEN - 1 downto CMD_PAYLSIZE_LOC) <= (others => '0');
							cmd_out_data(CMD_TYPE_LEN + CMD_TYPE_LOC - 1 downto CMD_TYPE_LOC)             <= std_logic_vector(conv_unsigned(OPCODE_SYNCREQ, 8));
							cmd_out_data(CMD_EPOCH_LOC + CMD_EPOCH_LEN - 1 downto CMD_EPOCH_LOC)          <= myEpoch(conv_integer(inCmdUser));
							cmd_out_data(CMD_ZXID_LOC + CMD_ZXID_LEN - 1 downto CMD_ZXID_LOC)             <= preloadVotedZxid;
							cmd_out_data(PEER_BITS + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC)       			 <= leaderPeerId(conv_integer(inCmdUser));
							cmd_out_data(CMD_PEERID_LEN + CMD_PEERID_LOC - 1 downto CMD_PEERID_LOC +PEER_BITS)   <= (others=>'0');
							cmd_out_data(CMD_SESSID_LOC + CMD_SESSID_LEN - 1 downto CMD_SESSID_LOC)       <= peerSessId(conv_integer(inCmdUser))(conv_integer(inCmdPeerId));
							cmd_out_data(CMD_HTOP_LOC + CMD_HTOP_LEN - 1 downto CMD_HTOP_LOC)             <= std_logic_vector(conv_unsigned(HTOP_IGNORE, CMD_HTOP_LEN));
							cmd_out_user                                                                  <= inCmdUser;
							cmd_out_key                                                                   <= inCmdKey;
						else
							prevRole(conv_integer(inCmdUser))     <= myRole(conv_integer(inCmdUser));
							myRole(conv_integer(inCmdUser))       <= ROLE_LEADER;
							proposedZxid(conv_integer(inCmdUser)) <= preloadMyZxid;
							myPhase(conv_integer(inCmdUser))      <= PH_NORMAL;

						end if;
						myState    <= ST_WAITOP;
						inCmdReady <= '1';

					when ST_WAITOUTREADY =>
						if (cmd_out_ready = '1') then
							cmd_out_valid <= '0';
							myState       <= ST_WAITOP;
							inCmdReady    <= '1';

						end if;

					when ST_TIMEOUT_LEADER =>

						myState <= ST_WAITOP;
						inCmdReady <= '1';

						if (myPhase(conv_integer(inCmdUser)) = PH_ELECTION and sinceHeardFromLeader(conv_integer(inCmdUser)) < 2 ** 30) then
							traceLoc <= "00010001";
							-- this was a failed election round...

							if (nextLeaderId(conv_integer(inCmdUser)) = peercount(conv_integer(inCmdUser)) + 1) then
								nextLeaderId(conv_integer(inCmdUser))    <= (others => '0');
								nextLeaderId(conv_integer(inCmdUser))(0) <= '1';
							else
								nextLeaderId(conv_integer(inCmdUser)) <= nextLeaderId(conv_integer(inCmdUser)) + 1;
							end if;

							sinceHeardFromLeader(conv_integer(inCmdUser))     <= (others => '0');
							sinceHeardFromLeader(conv_integer(inCmdUser))(30) <= '1';

							voteCount(conv_integer(inCmdUser)) <= (others => '0');

						end if;

						if (myPhase(conv_integer(inCmdUser)) = PH_NORMAL or sinceHeardFromLeader(conv_integer(inCmdUser)) > 2 ** 30) then
							traceLoc                                        <= "00010010";
							sinceHeardFromLeader(conv_integer(inCmdUser)) <= (others => '0');

							myPhase(conv_integer(inCmdUser))  <= PH_ELECTION;
							prevRole(conv_integer(inCmdUser)) <= myRole(conv_integer(inCmdUser));

							voteCount(conv_integer(inCmdUser)) <= (others => '0');

							votedEpoch(conv_integer(inCmdUser)) <= myEpoch(conv_integer(inCmdUser));
							votedZxid(conv_integer(inCmdUser))  <= myZxid(conv_integer(inCmdUser));
							syncFrom(conv_integer(inCmdUser))   <= myPeerId(conv_integer(inCmdUser));

							if (myPeerId(conv_integer(inCmdUser)) = nextLeaderId(conv_integer(inCmdUser))) then
								-- we wait...
								voteCount(conv_integer(inCmdUser)) <= (others => '0');
							else
								-- now we send our epoch to the proposed leader
								myState    <= ST_PROP_LEADER;
								inCmdReady <= '0';
							end if;
						end if;



					when others =>
				end case;

			end if;

		end if;

	end process;

	debug_out(3 * 8 - 1 downto 0) <= myZxid(conv_integer(inCmdUser))(7 downto 0) & proposedZxid(conv_integer(inCmdUser))(7 downto 0) & traceLoc(7 downto 0);

	--debug_out(111 downto 96) <= (others => '0');

	--debug_out(127 downto 124) <= "0001" when myPhase(conv_integer(inCmdUser)) = PH_NORMAL	 else "1111";
	--debug_out(123 downto 120) <= "0001" when myPhase(conv_integer(inCmdUser)) = PH_ELECTION else "1111";

	--debug_out(119 downto 116) <= "0010" when myRole(conv_integer(inCmdUser)) = ROLE_LEADER	  else "1111";
	--debug_out(115 downto 114) <= "10"   when myRole(conv_integer(inCmdUser)) = ROLE_FOLLOWER else "11";
	--debug_out(113)	    <= '1'    when syncMode = '1' else '0';
	--debug_out(112)	    <= '1'    when syncPrepare = '1' else '0';

	sessmem : zk_blkmem_32x1024
		port map(
			clka  => clk,
			--ena => sessMemEnable,
			wea   => sessMemWrite,
			addra => sessMemAddr,
			dina  => sessMemDataIn,
			douta => sessMemDataOut
		);

end beh;
