foreach f $argv { read_verilog -sv $f }
synth_design -top synth_top -part xcu55c-fsvh2892-2L-e -mode out_of_context
