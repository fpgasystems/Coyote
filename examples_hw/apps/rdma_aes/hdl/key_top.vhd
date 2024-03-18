library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.rounds.all;

entity key_top is
    generic(
        NPAR      : integer := 2;
        KEY_WIDTH : integer := 128;
        KEY_ROUNDS: integer := 11;
        OPERATION : integer := 0       -- [0-encryption, 1-decryption]
    );
    port(
        clk       : in std_logic;
        reset_n   : in std_logic; 
        stall     : in std_logic;
    -- Key
        key_in    : in  std_logic_vector(KEY_WIDTH-1 downto 0);
        keyVal_in : in  std_logic;
        keyVal_out: out std_logic;
        key_out   : out std_logic_vector(KEY_ROUNDS*KEY_WIDTH-1 downto 0)
    );
end entity key_top;

architecture RTL of key_top is

    type keep_array is array (NPAR-1 downto 0) of std_logic_vector(15 downto 0);

    --variable key_rounds : integer := key_rounds_number(KEY_WIDTH);
    -- Internal signals
    signal key_exp : std_logic_vector(key_rounds_number(KEY_WIDTH)*KEY_WIDTH-1 downto 0);
    signal key_op: std_logic_vector(key_rounds_number(KEY_WIDTH)*KEY_WIDTH-1 downto 0);

begin
    
    -- Instantiate key pipeline
    GEN_KEY_PIPE: entity work.key_pipeline
        generic map(
            KEY_WIDTH   => KEY_WIDTH,
            KEY_ROUNDS  => key_rounds_number(KEY_WIDTH)
        )
        port map(
            clk         => clk,
            reset_n     => reset_n, 
            keyVal_in   => keyVal_in,
            keyVal_out  => keyVal_out,
            key_in      => key_in,
            key_out     => key_exp
        );
    
    -- Gen key depending on the OPERATION
    GEN_KEY_ENC: if OPERATION=0 generate
        key_op <= key_exp;
    end generate GEN_KEY_ENC;

    GEN_KEY_DEC: if OPERATION=1 generate
        GEN_KEY: for i in 0 to encrypt_rounds_number(KEY_WIDTH)+1 generate  --ENC_ROUNDS
            key_op(128*i+127 downto 128*i) <= key_exp((encrypt_rounds_number(KEY_WIDTH)+1-i)*128+127 downto (encrypt_rounds_number(KEY_WIDTH)+1-i)*128);
        end generate GEN_KEY;
    end generate GEN_KEY_DEC;

    key_out <= key_op;
    
end architecture RTL;