library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity aes_pipe_stage is
    generic(
        OPERATION : integer := 0;              -- [0-encryption, 1-decryption]
        LAST      : boolean := false
    );
    port(
        clk      : in  std_logic;
        reset_n  : in  std_logic;
        stall    : in  std_logic;
        key_in   : in  std_logic_vector(127 downto 0); 
        last_in  : in  std_logic;
        last_out : out std_logic;
        keep_in  : in  std_logic_vector(15 downto 0);
        keep_out : out std_logic_vector(15 downto 0);
        dVal_in  : in  std_logic;
        dVal_out : out std_logic;
        data_in  : in  std_logic_vector(127 downto 0); 
        data_out : out std_logic_vector(127 downto 0)
    );
end entity aes_pipe_stage;

architecture RTL of aes_pipe_stage is
    
    -- Internal signals
    signal data_aes_out : std_logic_vector(127 downto 0);
    
begin
    
    -- Instantiate AES round
    GEN_RND: if LAST = false generate
        GEN_AES_RND: entity work.aes_round 
            generic map(
                OPERATION => OPERATION
            )
            port map(
                key_in   => key_in,
                data_in  => data_in,
                data_out => data_aes_out
            );
    end generate GEN_RND;

    GEN_LAST: if LAST = true generate
        GEN_AES_RND: entity work.aes_round_last
            generic map(
                OPERATION => OPERATION
            )
            port map(
                key_in   => key_in,
                key_last => (others => '0'),
                data_in  => data_in,
                data_out => data_aes_out
            );
    end generate GEN_LAST;

    -- Instantiate Pipe register
    GEN_AES_REG: entity work.pipe_reg
        port map(
            clk      => clk,
            reset_n  => reset_n,
            stall    => stall,
            last_in  => last_in,
            last_out => last_out,
            keep_in  => keep_in,
            keep_out => keep_out,
            dVal_in  => dVal_in,
            dVal_out => dVal_out,
            data_in  => data_aes_out,
            data_out => data_out
        );
    
end architecture RTL;