######################################################################################
# Partial bitgen: generate bitstreams only for configs that have checkpoints.
# Skips missing configs instead of failing.
#
# Usage: vivado -mode tcl -source partial_bitgen.tcl -notrace -tclargs <build_hw_dir>
######################################################################################

if {[catch {

set build_dir [lindex $argv 0]
source "$build_dir/base.tcl"

file mkdir "$bit_dir"

########################################################################################################
# PER-CONFIG PARTIAL BITSTREAMS
########################################################################################################
set generated 0
for {set i 0} {$i < $cfg(n_config)} {incr i} {
    set dcp_path "$dcp_dir/config_$i/shell_routed_c$i.dcp"
    if {![file exists $dcp_path]} {
        puts "** SKIP config $i: checkpoint not found"
        continue
    }
    puts "** Generating bitstream for config $i ..."
    open_checkpoint $dcp_path
    file mkdir "$bit_dir/config_$i"
    for {set j 0} {$j < $cfg(n_reg)} {incr j} {
        write_bitstream -force -no_binary_bitfile -bin_file -cell "inst_shell/inst_dynamic/inst_user_wrapper_$j" "$bit_dir/config_$i/vfpga_c$i\_$j.bit"
        write_debug_probes -quiet -force -cell "inst_shell/inst_dynamic/inst_user_wrapper_$j" "$bit_dir/config_$i/vfpga_c$i\_$j.ltx"
    }
    close_project
    incr generated
}

########################################################################################################
# RECOMBINE + SHELL_TOP
########################################################################################################
if {$cfg(build_shell) eq 1} {
    puts "** Recombining from config 0 ..."
    open_checkpoint "$dcp_dir/config_0/shell_routed_c0.dcp"
    pr_recombine -cell inst_shell
    write_checkpoint -force "$dcp_dir/shell_recombined.dcp"

    write_bitstream -force -bin_file -no_binary_bitfile -cell "inst_shell" "$bit_dir/shell_top.bit"
    write_debug_probes -force -quiet -cell "inst_shell" "$bit_dir/shell_top.ltx"

    write_bitstream -force -no_partial_bitfile "$bit_dir/cyt_top.bit"
    write_debug_probes -no_partial_ltxfile -force "$bit_dir/cyt_top.ltx"
    close_project
}

puts ""
puts "** Partial bitgen complete: $generated configs generated"
puts ""

} errorstring]} {
    puts "** CERR: $errorstring"
    exit 1
}

exit 0
