######################################################################################
# Resume flow_dyn.tcl from existing checkpoints.
# Only implements missing configs and recombines.
#
# Usage: vivado -mode tcl -source resume_app.tcl -notrace -tclargs <build_hw_dir> <cfg1> [<cfg2> ...]
#   e.g. vivado -mode tcl -source resume_app.tcl -notrace -tclargs /path/to/build_hw 13 14
######################################################################################

if {[catch {

set build_dir [lindex $argv 0]
set missing_cfgs [lrange $argv 1 end]

# Source the base config
source "$build_dir/base.tcl"

puts "** Resume: build_dir = $build_dir"
puts "** Resume: missing configs = $missing_cfgs"

########################################################################################################
# IMPLEMENT MISSING CONFIGS
########################################################################################################
foreach i $missing_cfgs {
    create_project -in_memory -part $part

    puts "** Partial compilation resumed, config $i ..."

    # Load locked shell
    add_file "$dcp_dir/shell_routed_locked.dcp"
    for {set j 0} {$j < $cfg(n_reg)} {incr j} {
        add_files "$dcp_dir/config_$i/user_synthed_c$i\_$j.dcp"
        set cmd "set_property SCOPED_TO_CELLS { inst_shell/inst_dynamic/inst_user_wrapper_$j } \[get_files \"$dcp_dir/config_$i/user_synthed_c$i\_$j.dcp\"]"
        eval $cmd
    }
    add_files -fileset [get_filesets constrs_1] "$hw_dir/constraints/$cfg(fdev)/dynamic/impl"

    # Link design
    set cmd "link_design -mode default -reconfig_partitions { "
    for {set j 0} {$j < $cfg(n_reg)} {incr j} {
        append cmd " inst_shell/inst_dynamic/inst_user_wrapper_$j "
    }
    append cmd " } -part $part -top cyt_top"
    eval $cmd
    write_checkpoint -force "$dcp_dir/config_$i/shell_linked_c$i.dcp"

    # Compilation
    if {$cfg(build_opt) eq 1} {
        opt_design -directive Explore
    } else {
        opt_design
    }
    write_checkpoint -force "$dcp_dir/config_$i/shell_opted_c$i.dcp"

    if {$cfg(build_opt) eq 1} {
        place_design -directive Auto_1
    } else {
        place_design
    }
    write_checkpoint -force "$dcp_dir/config_$i/shell_placed_c$i.dcp"

    if {$cfg(build_opt) eq 1} {
        phys_opt_design -directive AggressiveExplore
    } else {
        phys_opt_design
    }
    write_checkpoint -force "$dcp_dir/config_$i/shell_phys_opted_c$i.dcp"

    if {$cfg(build_opt) eq 1} {
        route_design -directive AggressiveExplore
    } else {
        route_design
    }

    if {$cfg(build_opt) eq 1} {
        phys_opt_design -directive AggressiveExplore
    }

    write_checkpoint -force "$dcp_dir/config_$i/shell_routed_c$i.dcp"

    file mkdir "$rprt_dir/config_$i"
    report_utilization -file "$rprt_dir/config_$i/shell_utilization_c$i.rpt"
    report_route_status -file "$rprt_dir/config_$i/shell_route_status_c$i.rpt"
    report_timing_summary -file "$rprt_dir/config_$i/shell_timing_summary_c$i.rpt"
    report_drc -ruledeck bitstream_checks -name cyt_top -file "$rprt_dir/config_$i/shell_drc_bitstream_checks_c$i.rpt"
    close_project

    puts "** Config $i completed"
}

########################################################################################################
# RECOMBINE
########################################################################################################
puts "** Recombining ..."

open_checkpoint "$dcp_dir/config_0/shell_routed_c0.dcp"
pr_recombine -cell inst_shell
write_checkpoint -force "$dcp_dir/shell_recombined.dcp"
close_project

puts "** Resume completed successfully"

} errorstring]} {
    puts "** CERR: $errorstring"
    exit 1
}

exit 0
