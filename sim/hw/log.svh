`ifndef LOG_SVH
`define LOG_SVH

function string filename_from_path(input string path);
    int i;
 
    for (i = path.len() - 1; i > 0; i = i - 1) begin
        if (path[i] == "/") begin
            i++;
            break;
        end
    end
    return path.substr(i, path.len() - 1);
endfunction

`define DEBUG(MESG) $display("%0t: [DEBUG] %s:%0d: %s", $realtime, filename_from_path(`__FILE__), `__LINE__ , $sformatf MESG);
`define ERROR(MESG) $error("%0t: [ERROR] %s:%0d: %s", $realtime, filename_from_path(`__FILE__), `__LINE__ , $sformatf MESG);
`define FATAL(MESG) $fatal(1, "%0t: [FATAL] %s:%0d: %s", $realtime, filename_from_path(`__FILE__), `__LINE__ , $sformatf MESG);
`define ASSERT(COND, MESG) assert(COND) else $fatal(1, "%0t: [ASSERT] %s:%0d: %s", $realtime, filename_from_path(`__FILE__), `__LINE__ , $sformatf MESG);
`ifdef EN_VERBOSE
    `define VERBOSE(MESG) `DEBUG(MESG)
`else
    `define VERBOSE(MESG) while (0) begin end
`endif

`endif // LOG_SVH
