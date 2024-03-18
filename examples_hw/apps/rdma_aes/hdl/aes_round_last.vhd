library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity aes_round_last is
    generic(
        OPERATION : integer := 0    -- [0-encryption, 1-decryption]
    );
    port(
        key_in   : in  std_logic_vector(127 downto 0); 
        key_last : in  std_logic_vector(127 downto 0); 
        data_in  : in  std_logic_vector(127 downto 0); 
        data_out : out std_logic_vector(127 downto 0)
    );
end entity aes_round_last;

architecture RTL of aes_round_last is
    
    -- Internal signals
    signal data_step_one   : std_logic_vector(127 downto 0);
    signal data_step_two   : std_logic_vector(127 downto 0);
   
begin
    
    -- Encryption
    GEN_ENC: if OPERATION = 0 generate
        -- S-box stage
        GEN_SBOX: for i in 0 to 15 generate
            SBOX: entity work.s_box_lut port map(
                data_in  => data_in(8*i+7 downto 8*i),
                data_out => data_step_one(8*i+7 downto 8*i)
            );
        end generate GEN_SBOX;
        
        -- Shift row
        GEN_SROW: entity work.shift_rows port map(
            data_in  => data_step_one,
            data_out => data_step_two
        );
        
    end generate GEN_ENC;

    -- Decryption
    GEN_DEC: if OPERATION = 1 generate
        -- Inverse Shift row
        GEN_INV_SROW: entity work.inv_shift_rows port map(
            data_in  => data_in,
            data_out => data_step_one
        );

        -- Inverse S-box stage
        GEN_INV_SBOX: for i in 0 to 15 generate
            INV_SBOX: entity work.inv_s_box_lut port map(
                data_in  => data_step_one(8*i+7 downto 8*i),
                data_out => data_step_two(8*i+7 downto 8*i)
            );
        end generate GEN_INV_SBOX;
            
    end generate GEN_DEC;
    
    -- Last add round key
    data_out <= data_step_two xor key_in;
    
end architecture RTL;