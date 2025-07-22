library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package utils is
    function bitlength(number : integer) return positive;

end package utils;

package body utils is

    -- purpose: returns the minimum # of bits needed to represent the input number
    function bitlength(number : integer) return positive is
        variable acc : positive := 1;
        variable i   : natural := 0;
    begin
    	if number = 0 or number = -1 then
    		return 1;
    	else
	        while True loop
	            if acc > number then
	                return i;
	            end if;
	
	            acc := acc * 2;
	            i   := i + 1;
	        end loop;
	    end if;
    end function bitlength;

end package body utils;