if {[catch {

########################################################################################################

# NOTE: this needs to be run with CWD in in the build directory and with the sim/test.xpr project open
source "base.tcl" -notrace
set proj [current_project]
set sim_dir        "$build_dir/sim"

########################################################################################################
# Set project properties
########################################################################################################
#set_property "board_part" $board_part                      $proj
set_property "default_lib" "xil_defaultlib"                 $proj
set_property "ip_cache_permissions" "read write"            $proj
set_property "ip_output_repo" "$sim_dir/$project.cache/ip"  $proj
set_property "sim.ip.auto_export_scripts" "1"               $proj
set_property "target_language" "Verilog"                    $proj
set_property "simulator_language" "Mixed"                   $proj
set_property "xpm_libraries" "XPM_CDC XPM_MEMORY"           $proj
if {$cfg(en_pr) eq 1} {
    set_property "pr_flow" "1"                              $proj
}

puts "**** Sim properties set"
puts "****"

########################################################################################################
# Create and add source files
########################################################################################################

# Create 'sources_1' fileset (if not found)
if {[string equal [get_filesets -quiet sources_1] ""]} {
  create_fileset -srcset sources_1
}

#!!!ADJUST PATH!!!!
source "$build_dir/../examples/04_user_interrupts/hw/src/init_ip.tcl" -notrace

# add all the simulation files to the project         !!!ADJUST PATH!!!
set obj [get_filesets sources_1]
set files [list \
  [ file normalize "$build_dir/example_04_user_interrupts_config_0/user_c0_0/hdl" ] \
  [ file normalize "$build_dir/../sim"] \
]
add_files -fileset $obj $files

# add wave behaviour            !!!ADJUST WAVEFORM!!!
add_files -fileset sim_1 -norecurse [ file normalize "$build_dir/../sim_files/waveforms/tb_user_behav_04.wcfg"]

# set necessary variables for the simulation
# set_property verilog_define {simMemSegmentsDir=$build_dir/../memory_segments/} [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {5000ns} -objects [get_filesets sim_1]

########################################################################################################

} errorstring]} {
    puts "**** CERR: $errorstring"
    puts "****"
    exit 1
}

exit 0