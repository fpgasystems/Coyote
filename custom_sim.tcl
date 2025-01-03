if {[catch {

# NOTE: this must run only when the project is open!

# this must be run toplevel in the repository! This is respected when build.sh is run
source "base.tcl"

set proj [current_project]
set build_dir      "../hw/build"
set sim_dir        "$build_dir/sim"

# shamelessly copied from the generated sim.tcl from the Coyote build directory
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

# Set 'sources_1' fileset object
set obj [get_filesets sources_1]
set files [list \
 [file normalize "sim"] \
 [file normalize "hw"] \
]
add_files -fileset $obj $files

set_property top tb_user [current_fileset]
set_property top tb_user [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

puts "**** Sim sources set"
puts "****"

# TODO: figure out how this works
########################################################################################################
# Simulation
########################################################################################################

# puts "**** Launching sim ..."
# puts "****"
# 
# launch_simulation
# 
# puts "**** Simulation completed"
# puts "****"


} errorstring]} {
    puts "**** CERR: $errorstring"
    puts "****"
    exit 1
}

exit 0

