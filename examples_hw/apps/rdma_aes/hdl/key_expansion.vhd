library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity key_expansion is
    generic(
        KEY_WIDTH : integer := 128  
    );
    port(
        key_in    : in  std_logic_vector(KEY_WIDTH-1 downto 0); 
        key_out   : out std_logic_vector(KEY_WIDTH-1 downto 0); 
        rnd_const : in  std_logic_vector(7 downto 0)
    );
end entity key_expansion;

architecture RTL of key_expansion is
    
    -- Internal signals
    type word_array is array ((KEY_WIDTH/32-1) downto 0) of std_logic_vector(31 downto 0);
    signal key_word : word_array;
    signal key_next : word_array;

    signal key_shift   : std_logic_vector(31 downto 0);
    signal key_s_box_0 : std_logic_vector(31 downto 0); 
    signal key_s_box_4 : std_logic_vector(31 downto 0); 
    signal temp_0      : std_logic_vector(31 downto 0);
    signal temp_4      : std_logic_vector(31 downto 0);
    signal key_temp    : std_logic_vector(KEY_WIDTH-1 downto 0);
    

begin
    
    -- Key words
    GEN_KW: for i in 0 to (KEY_WIDTH/32-1) generate
        key_word(((KEY_WIDTH/32-1))-i) <= key_in(32*i+31 downto 32*i);  --moc:  key_word(((KEY_WIDTH/32-1))-i)
    end generate GEN_KW;
    
    -- Rotate 8 bits
    key_shift <= key_word((KEY_WIDTH/32-1))(23 downto 0) & key_word((KEY_WIDTH/32-1))(31 downto 24);
    
    -- S-box-0: applied at state level for temporal value %(KEY_WIDTH/32) == 0
    GEN_SBOX_0: for i in 0 to 3 generate
        SBOX_0: entity work.s_box_lut port map(
            data_in  => key_shift(i*8+7 downto i*8),
            data_out => key_s_box_0(i*8+7 downto i*8)
        );
    end generate GEN_SBOX_0;
    
    -- Add round constant
    temp_0(31 downto 24) <= key_s_box_0(31 downto 24) xor rnd_const;
    temp_0(23 downto 0)  <= key_s_box_0(23 downto 0);
    
    -- Next key
    -- 0%(KEY_WIDTH/32) == 0 
    key_next(0) <= key_word(0) xor temp_0;
    
    GEN_TEMP_MIDDLE: if (KEY_WIDTH/32)>6 generate
        -- S-box-4: applied at state level for temporal value %(KEY_WIDTH/32) == 4 && (KEY_WIDTH>6)
        GEN_SBOX_4: for i in 0 to 3 generate
            SBOX_4: entity work.s_box_lut port map(
                data_in  => key_next(3)(i*8+7 downto i*8),
                data_out => key_s_box_4(i*8+7 downto i*8)
            );
        end generate GEN_SBOX_4;    
    
        temp_4 <= key_s_box_4 xor key_word(4);      
        key_next(4) <= temp_4;
        
        -- (1-(KEY_WIDTH/32-1))%(KEY_WIDTH/32) != 0
        GEN_NEXT_KEY_4: for i in 0 to (KEY_WIDTH/32-1-1) generate
            GEN_4: if i /= 3 generate
                key_next(i+1) <= key_word(i+1) xor key_next(i);
            end generate GEN_4;
        end generate GEN_NEXT_KEY_4;

    end generate GEN_TEMP_MIDDLE;

    GEN_NEXT_KEY: if (KEY_WIDTH/32)<=6 generate
        GEN_KEY: for i in 0 to (KEY_WIDTH/32-1-1) generate
                key_next(i+1) <= key_word(i+1) xor key_next(i);
        end generate GEN_KEY;
    end generate GEN_NEXT_KEY;
    
    -- Output
    
    GEN_KEY_TEMP_4: if (KEY_WIDTH/32)=4 generate
        key_temp <= key_next(0) & key_next(1) & key_next(2) & key_next(3);
    end generate GEN_KEY_TEMP_4;

    GEN_KEY_TEMP_6: if (KEY_WIDTH/32)=6 generate
        key_temp <= key_next(0) & key_next(1) & key_next(2) & key_next(3) & key_next(4) & key_next(5);
    end generate GEN_KEY_TEMP_6;

    GEN_KEY_TEMP_8: if (KEY_WIDTH/32)=8 generate
        key_temp <= key_next(0) & key_next(1) & key_next(2) & key_next(3) & key_next(4) & key_next(5) & key_next(6) & key_next(7);
    end generate GEN_KEY_TEMP_8;
    
    key_out <= key_temp; 
     
end architecture RTL;