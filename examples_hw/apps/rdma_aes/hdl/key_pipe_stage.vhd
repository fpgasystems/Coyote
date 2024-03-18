library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity key_pipe_stage is
    generic(
        KEY_WIDTH  : integer := 128
    );
    port(
        clk        : in  std_logic;
        reset_n    : in  std_logic;
        keyVal_in  : in  std_logic; -- Key valid signal
        keyVal_out : out std_logic;
        key_in     : in  std_logic_vector(KEY_WIDTH-1 downto 0);
        key_out    : out std_logic_vector(KEY_WIDTH-1 downto 0);
        rnd_const  : in  std_logic_vector(7 downto 0)
    );
end entity key_pipe_stage;

architecture RTL of key_pipe_stage is
    
    -- Internal signals
    signal key_exp : std_logic_vector(KEY_WIDTH-1 downto 0);
    
begin
    
    -- Instantiate Key expansion
    GEN_KEY_EXP: entity work.key_expansion
        generic map(
            KEY_WIDTH => KEY_WIDTH
        )
        port map(
            key_in    => key_in,
            key_out   => key_exp,
            rnd_const => rnd_const
        );
        
    -- Instantiate Pipe register
    GEN_AES_REG: entity work.key_pipe_reg
        generic map(
            KEY_WIDTH => KEY_WIDTH
        )
        port map(
            clk       => clk,
            reset_n   => reset_n,
            dVal_in   => keyVal_in,
            dVal_out  => keyVal_out,
            data_in   => key_exp,
            data_out  => key_out
        );
    
end architecture RTL;