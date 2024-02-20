set_property PROBES.FILE {/tmp/bstreams/top.ltx} [get_hw_devices xcu250_0]
set_property FULL_PROBES.FILE {/tmp/bstreams/top.ltx} [get_hw_devices xcu250_0]
set_property PROGRAM.FILE {/tmp/bstreams/top.bit} [get_hw_devices xcu250_0]
program_hw_devices [get_hw_devices xcu250_0]