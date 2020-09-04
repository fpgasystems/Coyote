--*************************************************************************--
--! @file		: fk_top.vhd
--! @project	: Firekite, Single port RAM implementation.
--! 
--! Top level component 
--! 
--! @date		: 10.10.2017.
--*************************************************************************--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.utils.all;

entity fk_top is
	generic(
		BUS_SIZE : integer := 32; -- Avalon bus size
		NCYC : integer := 32 -- Cycl. to exp. noise bits and upd. work vctr.
	);
	port(
		clk : in std_logic;
		reset_n	: in std_logic;
	-- Avalon slave
		avs_Address	: in std_logic_vector(2 downto 0);
		avs_ChipSelect : in std_logic;
		avs_Read : in std_logic;
		avs_Write : in std_logic;
		avs_WriteData : in std_logic_vector(31 downto 0);
		avs_ReadData : out std_logic_vector(31 downto 0);
	-- Avalon master Read
		avm_rd_WaitRequest : in std_logic;
		avm_rd_Read : out std_logic;
		avm_rd_ReadDataValid : in std_logic;
		avm_rd_ReadData : in std_logic_vector(BUS_SIZE-1 downto 0);
		avm_rd_Address : out std_logic_vector(31 downto 0);
		avm_rd_BurstCount : out std_logic_vector(7 downto 0);
	-- Avalon master Write
		avm_wr_WaitRequest : in std_logic;
		avm_wr_Write : out std_logic;
		avm_wr_WriteData : out std_logic_vector(BUS_SIZE-1 downto 0);
		avm_wr_Address : out std_logic_vector(31 downto 0);
		avm_wr_BurstCount : out std_logic_vector(7 downto 0);
	-- Irq
		irq : out std_logic
	);
end entity fk_top;

architecture RTL of fk_top is
	
	-- Constants
	constant NBITS : integer := 4096;
	constant DBITS : integer := 2816;
	constant EBITS : integer := 768;
	constant VBITS : integer := 512;
	
	-- Internal signals
	
	signal start_slv_ctrl : std_logic;
	signal len_slv_ctrl : std_logic_vector(15 downto 0);
	signal src_slv_ctrl	: std_logic_vector(31 downto 0);
	signal dest_slv_ctrl : std_logic_vector(31 downto 0);
	signal mode_slv_ctrl : std_logic_vector(1 downto 0);
	signal done_ctrl_slv : std_logic;
	signal doneIrq_ctrl_slv : std_logic;
	
	signal start_ctrl_dma_rd : std_logic;
	signal src_ctrl_dma_rd : std_logic_vector(31 downto 0);
	signal len_ctrl_dma_rd : std_logic_vector(9 downto 0);
	signal dVal_dma_rd_ctrl : std_logic;
	signal done_dma_rd_ctrl : std_logic;
	signal data_dma_rd_dp : std_logic_vector(BUS_SIZE-1 downto 0);
	
	signal start_ctrl_dma_wr : std_logic;
	signal dest_ctrl_dma_wr : std_logic_vector(31 downto 0);
	signal len_ctrl_dma_wr : std_logic_vector(9 downto 0);
	signal dVal_dma_wr_ctrl : std_logic;
	signal done_dma_wr_ctrl : std_logic;
	signal data_dp_dma_wr : std_logic_vector(BUS_SIZE-1 downto 0);
	
	
	signal ld_key_init_ctrl_dp : std_logic;
	signal ld_v_init_ctrl_dp : std_logic;
	signal ld_v_ctrl_dp : std_logic;
	signal start_key_ctrl_dp : std_logic;
	signal done_key_dp_ctrl : std_logic;
	signal ld_data_ctrl_dp : std_logic;
	signal wr_data_ctrl_dp : std_logic;
	signal rd_data_ctrl_dp : std_logic;
	signal rst_pntr_ctrl_dp : std_logic;
	signal ld_work_ctrl_dp : std_logic;
	signal wr_work_ctrl_dp : std_logic;
	signal rst_work_ctrl_dp : std_logic;
	signal start_init_exp_ctrl_dp : std_logic;
	signal start_exp_ctrl_dp : std_logic;
	signal done_exp_dp_ctrl : std_logic;
	
begin
	
	-- Instantiate Avalon slave unit. Interface.
	SLV: entity work.fk_slave
		port map(
			clk					=> clk,
			reset_n				=> reset_n,
		-- Avalon slave
			avs_Address			=> avs_Address,
			avs_ChipSelect  	=> avs_ChipSelect,
			avs_Read			=> avs_Read,
			avs_Write			=> avs_Write,
			avs_WriteData		=> avs_WriteData,
			avs_ReadData		=> avs_ReadData,
		-- Control
			start				=> start_slv_ctrl,
			len					=> len_slv_ctrl,
			src					=> src_slv_ctrl,
			dest				=> dest_slv_ctrl,
			mode				=> mode_slv_ctrl,
			done				=> done_ctrl_slv,
			doneIrq				=> doneIrq_ctrl_slv,
		-- Irq
			irq					=> irq
		);
	
	-- Instantiate DMA Read unit.
	DMA_RD: entity work.fk_dma_rd
		generic map(
			BUS_SIZE			=> BUS_SIZE
		)
		port map(
			clk 				=> clk,
			reset_n				=> reset_n,
		-- Control
			start				=> start_ctrl_dma_rd,
			src					=> src_ctrl_dma_rd,
			len					=> len_ctrl_dma_rd,
			dVal				=> dVal_dma_rd_ctrl,
			done				=> done_dma_rd_ctrl,
		-- Data
			src_data			=> data_dma_rd_dp,
		-- Avalon master
			avm_WaitRequest 	=> avm_rd_WaitRequest,
			avm_Read			=> avm_rd_Read,
			avm_ReadDataValid 	=> avm_rd_ReadDataValid,
			avm_ReadData		=> avm_rd_ReadData,
			avm_Address			=> avm_rd_Address,
			avm_BurstCount		=> avm_rd_BurstCount
		);
	
	-- Instantiate DMA Write unit.
	DMA_WR: entity work.fk_dma_wr
		generic map(
			BUS_SIZE			=> BUS_SIZE
		)
		port map(
			clk 				=> clk,
			reset_n				=> reset_n,
		-- Control
			start				=> start_ctrl_dma_wr,
			dest				=> dest_ctrl_dma_wr,
			len					=> len_ctrl_dma_wr,
			dVal				=> dVal_dma_wr_ctrl,
			done				=> done_dma_wr_ctrl,
		-- Data
			sink_data			=> data_dp_dma_wr,
		-- Avalon master
			avm_WaitRequest 	=> avm_wr_WaitRequest,
			avm_Write			=> avm_wr_Write,
			avm_WriteData		=> avm_wr_WriteData,
			avm_Address			=> avm_wr_Address,
			avm_BurstCount		=> avm_wr_BurstCount
		);
	
	-- Instantiate Datapath with registers.
	DP: entity work.fk_dp
		generic map(
			NBITS				=> NBITS,
			DBITS				=> DBITS,
			EBITS				=> EBITS,
			VBITS				=> VBITS,
			BUS_SIZE			=> BUS_SIZE,
			NCYC				=> NCYC
		)
		port map(
			clk 				=> clk,
			reset_n 			=> reset_n,
		-- Control
			ld_key_init			=> ld_key_init_ctrl_dp,
			ld_v_init			=> ld_v_init_ctrl_dp,
			ld_v 				=> ld_v_ctrl_dp,
			start_key 			=> start_key_ctrl_dp,
			done_key 			=> done_key_dp_ctrl,
			ld_data				=> ld_data_ctrl_dp,
			wr_data				=> wr_data_ctrl_dp,
			rd_data				=> rd_data_ctrl_dp,
			rst_pntr 			=> rst_pntr_ctrl_dp,
			ld_work				=> ld_work_ctrl_dp,	
			wr_work				=> wr_work_ctrl_dp,
			rst_work			=> rst_work_ctrl_dp,
			start_init_exp		=> start_init_exp_ctrl_dp,
			start_exp 			=> start_exp_ctrl_dp,
			done_exp 			=> done_exp_dp_ctrl,
		-- Data
			sink_data_s			=> data_dma_rd_dp,
			src_data_s			=> data_dp_dma_wr
		);
		
	-- Instantiate Controller.
	CTRL: entity work.fk_ctrl
		generic map(
			NBITS				=> NBITS,
			DBITS				=> DBITS
		)
		port map(
			clk 				=> clk,
			reset_n				=> reset_n,
		-- Control DP
			dp_key_ld_init		=> ld_key_init_ctrl_dp,
			dp_key_ld_v_init	=> ld_v_init_ctrl_dp,
			dp_key_ld_v 		=> ld_v_ctrl_dp,
			dp_key_start 		=> start_key_ctrl_dp,
			dp_key_done 		=> done_key_dp_ctrl,
			dp_ld_data 			=> ld_data_ctrl_dp,
			dp_wr_data 			=> wr_data_ctrl_dp,
			dp_rd_data 			=> rd_data_ctrl_dp,
			dp_rst_pntr 		=> rst_pntr_ctrl_dp,
			dp_ld_work 			=> ld_work_ctrl_dp,
			dp_wr_work 			=> wr_work_ctrl_dp,
			dp_rst_work			=> rst_work_ctrl_dp,
			dp_start_init_exp 	=> start_init_exp_ctrl_dp,
			dp_start_exp 		=> start_exp_ctrl_dp,
			dp_done_exp			=> done_exp_dp_ctrl,
		-- Avalon slave
			avs_start			=> start_slv_ctrl,
			avs_len				=> len_slv_ctrl,
			avs_src				=> src_slv_ctrl,
			avs_dest			=> dest_slv_ctrl,
			avs_mode			=> mode_slv_ctrl,
			avs_done			=> done_ctrl_slv,
			avs_doneIrq			=> doneIrq_ctrl_slv,
		-- Avalon master Read
			avm_rd_start		=> start_ctrl_dma_rd,
			avm_rd_src			=> src_ctrl_dma_rd,
			avm_rd_len			=> len_ctrl_dma_rd,
			avm_rd_dVal			=> dVal_dma_rd_ctrl,
			avm_rd_done			=> done_dma_rd_ctrl,
		-- Avalon master Write
			avm_wr_start		=> start_ctrl_dma_wr,
			avm_wr_dest			=> dest_ctrl_dma_wr,
			avm_wr_len			=> len_ctrl_dma_wr,
			avm_wr_dVal			=> dVal_dma_wr_ctrl,
			avm_wr_done			=> done_dma_wr_ctrl
		);
	
end architecture RTL;
