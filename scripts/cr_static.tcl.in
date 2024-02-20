########################################################################################################
# Project
########################################################################################################
puts "[color $clr_flow "** Creating static project ..."]"
puts "[color $clr_flow "**"]"

set proj_dir        "$build_dir/$project\_static"

# Check iprepo
if { [file isdirectory $iprepo_dir] } {
	set lib_dir "$iprepo_dir"
} else {
	puts "iprepo directory could not be found."
	#exit 1
}

# Create project
create_project $project $proj_dir -part $part -force
set proj [current_project]
set_property IP_REPO_PATHS $lib_dir [current_fileset]
update_ip_catalog

set_msg_config -id {Vivado 12-2924} -suppress
set_msg_config -id {IP_Flow 19-4832} -suppress

file mkdir "$dcp_dir/static"
file mkdir "$rprt_dir/static"
file mkdir "$log_dir/static"

########################################################################################################
# Set project properties
########################################################################################################
#set_property "board_part" $board_part                      $proj
set_property "default_lib" "xil_defaultlib"                 $proj
set_property "ip_cache_permissions" "read write"            $proj
set_property "ip_output_repo" "$proj_dir/$project.cache/ip" $proj
set_property "sim.ip.auto_export_scripts" "1"               $proj
set_property "target_language" "Verilog"                    $proj
set_property "simulator_language" "Mixed"                   $proj
set_property "xpm_libraries" "XPM_CDC XPM_MEMORY"           $proj

########################################################################################################
# Create and add source files
########################################################################################################
file mkdir "$proj_dir/hdl/static"

# Call write HDL scripts
proc call_write_hdl {r_path op c_cnfg c_reg} {
    set output [exec /usr/bin/python3 "$r_path/write_hdl.py" $op $c_cnfg $c_cnfg]
    puts $output
}
call_write_hdl $build_dir 0 0 0

# Add source files
add_files "$hw_dir/hdl/pkg"
add_files "$hw_dir/hdl/static"
add_files "$proj_dir/hdl/static"

if {$cfg(fdev) eq "enzian"} {
    add_files "$hw_dir/hdl/eci"
    add_files "$hw_dir/enzian_eci_transport/hdl"
    add_files "$hw_dir/enzian_eci_toolkit/hdl"
}

# Top level
set_property "top" "cyt_top" [current_fileset]

# Constraints
add_files -norecurse -fileset [get_filesets constrs_1] "$hw_dir/constraints/$cfg(fdev)/static/synth"
set_property used_in_implementation false [get_files -of_objects [get_filesets constrs_1]]

# Create a project-local constraint file to take debugging constraints that we
# don't want to propagate to the repository.
file mkdir "$proj_dir/$project.srcs/constrs_1"
close [ open "$proj_dir/$project.srcs/constrs_1/local.xdc" w ]

set_property target_constrs_file "$proj_dir/$project.srcs/constrs_1/local.xdc" [current_fileset -constrset]

########################################################################################################
# STATIC INFRASTRUCTURE
########################################################################################################
if {$cfg(fdev) eq "enzian"} {
    source "$scripts_dir/ip_inst/eci_infrastructure.tcl" -notrace
} else {
    source "$scripts_dir/ip_inst/pci_infrastructure.tcl" -notrace
}

########################################################################################################
# STATIC BLOCK DESIGN
########################################################################################################
if {$cfg(fdev) eq "enzian"} {
    source "$scripts_dir/bd/cr_eci.tcl" -notrace
    cr_bd_design_static ""
    set_property SYNTH_CHECKPOINT_MODE "Hierarchical" [get_files design_static.bd ]
} else {
    source "$scripts_dir/bd/cr_pci.tcl" -notrace
    cr_bd_design_static ""
    set_property SYNTH_CHECKPOINT_MODE "Hierarchical" [get_files design_static.bd ]
}


########################################################################################################
# STATIC PROJECT CREATED
########################################################################################################
close_project
puts "[color $clr_flow "** Static project created"]"
puts "[color $clr_flow "**"]"




