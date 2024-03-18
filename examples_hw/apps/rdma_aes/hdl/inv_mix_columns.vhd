library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity inv_mix_columns is
    port(
        data_in  : in  std_logic_vector(127 downto 0); 
        data_out : out std_logic_vector(127 downto 0)
    );
end entity inv_mix_columns;

architecture RTL of inv_mix_columns is
    
    -- Internal signals
    type data_array is array (15 downto 0) of std_logic_vector(7 downto 0);
    
    -- x9, xb, xd, xe multiplication
    signal in_array, out_array, in_array_x9, in_array_xb, in_array_xd, in_array_xe: data_array;
    
begin
    
    -- Input generation
    GEN_IN: for i in 15 downto 0 generate
        in_array(15-i) <= data_in(i*8+7 downto i*8);
    end generate GEN_IN;
    
    -- Multiplication
    GEN_M: for i in 15 downto 0 generate
        -- x9
        gf_inst0: entity work.gf_mult
        generic map(
            SELECTION => 9
        )
        port map(
            data_in  => in_array(i),
            data_out => in_array_x9(i)
        );

        -- x11
        gf_inst1: entity work.gf_mult
        generic map(
            SELECTION => 11
        )
        port map(
            data_in  => in_array(i),
            data_out => in_array_xb(i)
        );   
        -- x13
        gf_inst2: entity work.gf_mult
        generic map(
            SELECTION => 13
        )
        port map(
            data_in  => in_array(i),
            data_out => in_array_xd(i)
        );
        -- x14
        gf_inst3: entity work.gf_mult
        generic map(
            SELECTION => 14
        )
        port map(
            data_in  => in_array(i),
            data_out => in_array_xe(i)
        );
    end generate GEN_M;
    
    -- Mixed columns generation
    GEN_MC: for i in 0 to 3 generate
        out_array(4*i)   <= in_array_xe(4*i) xor in_array_xb(4*i+1) xor in_array_xd(4*i+2) xor in_array_x9(4*i+3);
        out_array(4*i+1) <= in_array_x9(4*i) xor in_array_xe(4*i+1) xor in_array_xb(4*i+2) xor in_array_xd(4*i+3);
        out_array(4*i+2) <= in_array_xd(4*i) xor in_array_x9(4*i+1) xor in_array_xe(4*i+2) xor in_array_xb(4*i+3);
        out_array(4*i+3) <= in_array_xb(4*i) xor in_array_xd(4*i+1) xor in_array_x9(4*i+2) xor in_array_xe(4*i+3);
    end generate;
    
    -- Output generation
    GEN_O: for i in 15 downto 0 generate
        data_out(i*8+7 downto i*8) <= out_array(15-i);
    end generate GEN_O;
    
end architecture RTL;