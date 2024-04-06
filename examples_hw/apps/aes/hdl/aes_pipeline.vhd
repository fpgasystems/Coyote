library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity aes_pipeline is
    generic(
        KEY_WIDTH : integer := 128;
        KEY_ROUNDS: integer := 11;
        ENC_ROUNDS: integer := 10;
        OPERATION : integer := 0;          --[0-encryption, 1-decryption]
        MODE      : integer := 0           --[0-ECB, 1-CTR, 2-CBC]
    );
    port(
        clk       : in  std_logic;
        reset_n   : in  std_logic;
        stall     : in  std_logic; 
    -- Key
        key_in    : in  std_logic_vector(KEY_ROUNDS*KEY_WIDTH-1 downto 0);
        last_in   : in  std_logic;
        last_out  : out std_logic;
        keep_in   : in  std_logic_vector(15 downto 0);
        keep_out  : out std_logic_vector(15 downto 0);
    -- Data valid
        dVal_in   : in  std_logic; -- Data valid
        dVal_out  : out std_logic;
    -- Data
        data_in   : in  std_logic_vector(127 downto 0); 
        data_out  : out std_logic_vector(127 downto 0);
    -- CTR
        cntr_in   : in  std_logic_vector(127 downto 0)
    );
end entity aes_pipeline;

architecture RTL of aes_pipeline is
    
    -- Internal signals
    type dVal_array is array ((ENC_ROUNDS) downto 0) of std_logic;
    type data_array is array ((ENC_ROUNDS) downto 0) of std_logic_vector(127 downto 0);
    type last_array is array ((ENC_ROUNDS) downto 0) of std_logic;
    type keep_array is array ((ENC_ROUNDS) downto 0) of std_logic_vector(15 downto 0);

    signal s_data_to_block   : std_logic_vector(127 downto 0);
    signal s_data_from_block : std_logic_vector(127 downto 0);

    signal dVal_pipe : dVal_array; -- Data valid signal pipeline
    signal data_pipe : data_array; -- Data pipeline
    signal last_pipe : last_array;
    signal keep_pipe : keep_array;
    
begin
    
    GEN_EBC: if (MODE = 0) generate
        s_data_to_block   <= data_in;
        s_data_from_block <= data_pipe(ENC_ROUNDS);
    end generate GEN_EBC;

    GEN_CTR: if (MODE = 1) generate
        s_data_to_block   <= data_in;
        s_data_from_block <= cntr_in xor data_pipe(ENC_ROUNDS);
    end generate GEN_CTR;

    GEN_CBC: if (MODE = 2) generate
        -- encryption
        GEN_CBC_EN: if (OPERATION = 0) generate
            s_data_to_block   <= data_in xor cntr_in;
            s_data_from_block <= data_pipe(ENC_ROUNDS);
        end generate GEN_CBC_EN; 
        
        -- decryption
        GEN_CBC_DE: if (OPERATION = 1) generate
            s_data_to_block   <= data_in;
            s_data_from_block <= cntr_in xor data_pipe(ENC_ROUNDS);
        end generate GEN_CBC_DE; 
    end generate GEN_CBC;

    -- Instantiate regular AES stages
    GEN_AES: for i in 0 to ENC_ROUNDS generate
        
        GEN_S0: if i = 0 generate
            S0: entity work.aes_pipe_stage
                generic map(
                    OPERATION => OPERATION
                )
                port map(
                    clk      => clk,
                    reset_n  => reset_n,
                    stall    => stall,
                    key_in   => key_in(255 downto 128), 
                    last_in  => last_in,
                    last_out => last_pipe(0),
                    keep_in  => keep_in,
                    keep_out => keep_pipe(0),
                    dVal_in  => dVal_in,
                    dVal_out => dVal_pipe(0),
                    data_in  => (s_data_to_block xor key_in(127 downto 0)),  
                    data_out => data_pipe(0)
                );
        end generate GEN_S0;
    
        GEN_SX: if i > 0 generate
            SX: entity work.aes_pipe_stage
                generic map(
                    OPERATION => OPERATION,
                    LAST => (i=ENC_ROUNDS)
                )
                port map(
                    clk      => clk,
                    reset_n  => reset_n,
                    stall    => stall,
                    key_in   => key_in(128*(i+1)+127 downto 128*(i+1)), 
                    last_in  => last_pipe(i-1),
                    last_out => last_pipe(i),
                    keep_in  => keep_pipe(i-1),
                    keep_out => keep_pipe(i),
                    dVal_in  => dVal_pipe(i-1),
                    dVal_out => dVal_pipe(i),
                    data_in  => data_pipe(i-1),  
                    data_out => data_pipe(i)
                );
        end generate GEN_SX;
        
    end generate GEN_AES;

    last_out <= last_pipe(ENC_ROUNDS);
    keep_out <= keep_pipe(ENC_ROUNDS);
    dVal_out <= dVal_pipe(ENC_ROUNDS);
    data_out <= s_data_from_block;

end architecture RTL;