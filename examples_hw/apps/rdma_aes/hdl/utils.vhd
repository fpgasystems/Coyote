library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--package utils is
--    function bitlength(number : integer) return positive;
--
--end package utils;

--package body utils is
--
--    -- purpose: returns the minimum # of bits needed to represent the input number
--    function bitlength(number : integer) return positive is
--        variable acc : positive := 1;
--        variable i   : natural := 0;
--    begin
--    	if number = 0 or number = -1 then
--    		return 1;
--    	else
--	        while True loop
--	            if acc > number then
--	                return i;
--	            end if;
--	
--	            acc := acc * 2;
--	            i   := i + 1;
--	        end loop;
--	    end if;
--    end function bitlength;
--
--end package body utils;

package rounds is
    function key_rounds_number (key_width:integer) return integer;
    function encrypt_rounds_number (key_width:integer) return integer;
end package rounds;

package body rounds is
    function key_rounds_number (key_width:integer) return integer is
    begin
        case key_width is
            when 128    => return 11;   -- 128*11/128 = 11
            when 192    => return 9;    -- 128*13/192 = 9
            when 256    => return 8;    -- 128*15/256 = 8
            when others => return 11;
        end case;
    end function;

    function encrypt_rounds_number (key_width:integer) return integer is
    begin
        case key_width is
            when 128    => return  9;  -- 10(total rounds)-1(final round) = 9
            when 192    => return 11;  -- 12(total rounds)-1(final round) = 11
            when 256    => return 13;  -- 14(total rounds)-1(final round) = 13
            when others => return  9;
        end case;
    end function;
end package body rounds;