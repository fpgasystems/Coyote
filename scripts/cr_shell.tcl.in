########################################################################################################
# Project
########################################################################################################
puts "[color $clr_flow "** Creating shell project ..."]"
puts "[color $clr_flow "**"]"

set proj_dir        "$build_dir/$project\_shell"

# Create project
create_project $project $proj_dir -part $part -force
set proj [current_project]
set_property IP_REPO_PATHS $lib_dir [current_fileset]
update_ip_catalog

set_msg_config -id {Vivado 12-2924} -suppress
set_msg_config -id {IP_Flow 19-4832} -suppress
set_msg_config -id {BD 41-927} -suppress

file mkdir "$dcp_dir/shell"
file mkdir "$rprt_dir/shell"
file mkdir "$log_dir/shell"

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
file mkdir "$proj_dir/hdl"

# Call write HDL scripts
proc call_write_hdl {r_path op c_cnfg c_reg} {
    set output [exec /usr/bin/python3 "$r_path/write_hdl.py" $op $c_cnfg $c_reg]
    puts $output
}
call_write_hdl $build_dir 1 0 0

# Add source files
add_files "$hw_dir/hdl/pkg"
add_files "$hw_dir/hdl/shell"
add_files "$hw_dir/hdl/mmu"
add_files "$hw_dir/hdl/common"
if {$cfg(en_card) eq 1} {
    add_files "$hw_dir/hdl/stripe"
    add_files "$hw_dir/hdl/cdma/cdma_u"
}
if {$cfg(en_net) eq 1} {
    add_files "$hw_dir/hdl/network/cmac"
    add_files "$hw_dir/hdl/network/stack"
    if {$cfg(en_rdma) eq 1} {
        add_files "$hw_dir/hdl/network/rdma"
    }
    if {$cfg(en_tcp) eq 1} {
        add_files "$hw_dir/hdl/network/tcp"
    }
}
add_files "$proj_dir/hdl"

# Top level
set_property "top" "shell_top" [current_fileset]

# Constraints
add_files -norecurse -fileset [get_filesets constrs_1] "$hw_dir/constraints/$cfg(fdev)/shell/synth"
set_property used_in_implementation false [get_files -of_objects [get_filesets constrs_1]]
#set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]

# Create a project-local constraint file to take debugging constraints that we
# don't want to propagate to the repository.
file mkdir "$proj_dir/$project.srcs/constrs_1"
close [ open "$proj_dir/$project.srcs/constrs_1/local.xdc" w ]

set_property target_constrs_file "$proj_dir/$project.srcs/constrs_1/local.xdc" [current_fileset -constrset]

########################################################################################################
# SHELL INFRASTRUCTURE
########################################################################################################
source "$scripts_dir/ip_inst/shell_infrastructure.tcl" -notrace
source "$scripts_dir/ip_inst/common_infrastructure.tcl" -notrace
if {$cfg(en_card) eq 1} {
    source "$scripts_dir/ip_inst/memory_infrastructure.tcl" -notrace
}
if {$cfg(en_net) eq 1} {
    source "$scripts_dir/ip_inst/network_infrastructure.tcl" -notrace
}

########################################################################################################
# BLOCK DESIGN
########################################################################################################
source "$scripts_dir/bd/cr_ctrl.tcl" -notrace
cr_bd_design_ctrl ""
set_property SYNTH_CHECKPOINT_MODE "Hierarchical" [get_files design_ctrl.bd ]

if {$cfg(en_dcard) eq 1} {
    source "$scripts_dir/bd/cr_ddr.tcl" -notrace
    cr_bd_design_ddr ""
    set_property SYNTH_CHECKPOINT_MODE "Hierarchical" [get_files design_ddr.bd ]
}

if {$cfg(en_hcard) eq 1} {
    if {$cfg(hbm_split) eq 1} {
      source "$scripts_dir/bd/cr_hbm_split.tcl" -notrace 
    } else {
      source "$scripts_dir/bd/cr_hbm.tcl" -notrace 
    }
    cr_bd_design_hbm ""
    set_property SYNTH_CHECKPOINT_MODE "Hierarchical" [get_files design_hbm.bd ]
}

########################################################################################################
# SHELL PROJECT CREATED
########################################################################################################
close_project
puts "[color $clr_flow "** Shell project created"]"
puts "[color $clr_flow "**"]"




