library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity key_pipeline is
    generic(
        KEY_WIDTH : integer := 128;
        KEY_ROUNDS: integer := 11
    );
    port(
        clk        : in  std_logic;
        reset_n    : in  std_logic; 
        keyVal_in  : in  std_logic; -- Key valid
        keyVal_out : out std_logic;
        key_in     : in  std_logic_vector(KEY_WIDTH-1 downto 0);
        key_out    : out std_logic_vector(KEY_ROUNDS*KEY_WIDTH-1 downto 0)
    );
end entity key_pipeline;

architecture RTL of key_pipeline is
    
    -- Internal signals
    type keyVal_array is array (KEY_ROUNDS-1 downto 0) of std_logic;
    type key_array    is array (KEY_ROUNDS-1 downto 0) of std_logic_vector((KEY_WIDTH-1) downto 0);
    
    signal keyVal_pipe : keyVal_array; -- Key valid signal pipeline
    signal key_pipe    : key_array;    -- Key pipeline
    
    -- Internal RAM for round constants
    type ram_type is array(natural range<>) of std_logic_vector(7 downto 0);
    constant rcon: ram_type(0 to 9) := (X"01", X"02", X"04", X"08", X"10", X"20", X"40", X"80", X"1b", X"36");
    
begin
    
    -- Instantiate base key register
    GEN_KEY_BASE: entity work.key_pipe_reg
        generic map (
            KEY_WIDTH => KEY_WIDTH
        )
        port map(
            clk       => clk,
            reset_n   => reset_n,
            dVal_in   => keyVal_in,
            dVal_out  => keyVal_pipe(0),
            data_in   => key_in,
            data_out  => key_pipe(0)
        );
    
    -- Instantiate key expansion pipeline
    GEN_KEY_EXP: for i in 0 to KEY_ROUNDS-1-1 generate
        KEY_X: entity work.key_pipe_stage
            generic map(
                KEY_WIDTH  => KEY_WIDTH
            )
            port map(
                clk        => clk,
                reset_n    => reset_n,
                keyVal_in  => keyVal_pipe(i),
                keyVal_out => keyVal_pipe(i+1),
                key_in     => key_pipe(i),
                key_out    => key_pipe(i+1),
                rnd_const  => rcon(i)
            );
    end generate GEN_KEY_EXP;
    
    -- Key valid out
    keyVal_out <= keyVal_pipe(KEY_ROUNDS-1);
    
    -- Keys out
    

    GEN_KEYS_OUT_4: if (KEY_WIDTH/32)=4 generate
        GEN_4: for i in 0 to KEY_ROUNDS-1 generate
            key_out(i*KEY_WIDTH+(KEY_WIDTH-1) downto i*KEY_WIDTH) <= key_pipe(i);
        end generate GEN_4;
    end generate GEN_KEYS_OUT_4;

    GEN_KEYS_OUT_6: if (KEY_WIDTH/32)=6 generate
        key_out(127 downto 0)   <= key_pipe(0)(191 downto 64);
        key_out(255 downto 128) <= key_pipe(0)(63 downto 0) & key_pipe(1)(191 downto 128);
        key_out(383 downto 256) <= key_pipe(1)(127 downto 0);

        key_out(511 downto 384) <= key_pipe(2)(191 downto 64);
        key_out(639 downto 512) <= key_pipe(2)(63 downto 0) & key_pipe(3)(191 downto 128);
        key_out(767 downto 640) <= key_pipe(3)(127 downto 0);

        key_out(895 downto 768)   <= key_pipe(4)(191 downto 64);
        key_out(1023 downto 896)  <= key_pipe(4)(63 downto 0) & key_pipe(5)(191 downto 128);
        key_out(1151 downto 1024) <= key_pipe(5)(127 downto 0);

        key_out(1279 downto 1152) <= key_pipe(6)(191 downto 64);
        key_out(1407 downto 1280) <= key_pipe(6)(63 downto 0) & key_pipe(7)(191 downto 128);
        key_out(1535 downto 1408) <= key_pipe(7)(127 downto 0);
        
        key_out(1663 downto 1536) <= key_pipe(8)(191 downto 64);
        
    end generate GEN_KEYS_OUT_6;    

    GEN_KEYS_OUT_8: if (KEY_WIDTH/32)=8 generate
        GEN_8: for i in 0 to KEY_ROUNDS-1 generate
            key_out(i*KEY_WIDTH+(KEY_WIDTH-1) downto i*KEY_WIDTH) <= key_pipe(i)(127 downto 0) & key_pipe(i)(255 downto 128);
        end generate GEN_8;
    end generate GEN_KEYS_OUT_8;

end architecture RTL;