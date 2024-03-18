library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity data_pipeline is
    generic(
        NPAR      : integer := 2;
        ENC_ROUNDS: integer := 10
    );
    port(
        clk       : in  std_logic;
        reset_n   : in  std_logic;
        stall     : in  std_logic; 
    -- Control
        keep_in   : in  std_logic_vector(NPAR*16-1 downto 0);
        keep_out  : out std_logic_vector(NPAR*16-1 downto 0);
    -- Data
        data_in   : in  std_logic_vector(NPAR*128-1 downto 0); 
        data_out  : out std_logic_vector(NPAR*128-1 downto 0)
    );
end entity data_pipeline;

architecture RTL of data_pipeline is
    
    -- Internal signals
    type dVal_array is array ((ENC_ROUNDS) downto 0) of std_logic;
    type data_array is array ((ENC_ROUNDS) downto 0) of std_logic_vector(NPAR*128-1 downto 0);
    type last_array is array ((ENC_ROUNDS) downto 0) of std_logic;
    type keep_array is array ((ENC_ROUNDS) downto 0) of std_logic_vector(NPAR*16-1 downto 0);

    signal dVal_pipe : dVal_array; -- Data valid signal pipeline
    signal data_pipe : data_array; -- Data pipeline
    signal last_pipe : last_array;
    signal keep_pipe : keep_array;
    
begin
    
    -- Instantiate data stages 
    GEN_DAT: for i in 0 to ENC_ROUNDS generate
        
        GEN_D0: if i = 0 generate
            D0: entity work.pipe_reg
            generic map(
                DATA_WIDTH => NPAR*128
            )
            port map(
                clk      => clk,
                reset_n  => reset_n,
                stall    => stall,
                last_in  => '0',
                last_out => last_pipe(0),
                keep_in  => keep_in,
                keep_out => keep_pipe(0),
                dVal_in  => '1',
                dVal_out => dVal_pipe(0),
                data_in  => data_in,
                data_out => data_pipe(0)
            );
        end generate GEN_D0;
    
        GEN_DX: if i > 0 generate
            DX: entity work.pipe_reg
            generic map(
                DATA_WIDTH => NPAR*128
            )
            port map(
                clk      => clk,
                reset_n  => reset_n,
                stall    => stall,
                last_in  => last_pipe(i-1),
                last_out => last_pipe(i),
                keep_in  => keep_pipe(i-1),
                keep_out => keep_pipe(i),
                dVal_in  => dVal_pipe(i-1),
                dVal_out => dVal_pipe(i),
                data_in  => data_pipe(i-1),  
                data_out => data_pipe(i)
            );
        end generate GEN_DX;
        
    end generate GEN_DAT;

    keep_out <= keep_pipe(ENC_ROUNDS);
    data_out <= data_pipe(ENC_ROUNDS);

end architecture RTL;