
########################################################################################################
# USER LAYER
########################################################################################################
puts "[color $clr_flow "** Creating user projects ..."]"
puts "[color $clr_flow "**"]"

for {set i 0}  {$i < $cfg(n_config)} {incr i} {
    for {set j 0}  {$j < $cfg(n_reg)} {incr j} {
        set proj_dir        "$build_dir/$project\_config_$i/user\_c$i\_$j"

        ########################################################################################################
        # Project
        ########################################################################################################
        create_project $project $proj_dir -part $part -force
        set proj [current_project]
        set_property IP_REPO_PATHS $lib_dir [current_fileset]
        update_ip_catalog

        file mkdir "$dcp_dir/config_$i"
        file mkdir "$rprt_dir/config_$i"
        file mkdir "$log_dir/config_$i"

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
        file mkdir "$proj_dir/hdl/ext"
        file mkdir "$proj_dir/hdl/wrappers"
        file mkdir "$proj_dir/xdc"

        # Call write HDL scripts
        proc call_write_hdl {r_path op c_cnfg c_reg} {
            set output [exec /usr/bin/python3 "$r_path/write_hdl.py" $op $c_cnfg $c_reg]
            puts $output
        }
        call_write_hdl $build_dir 2 $i $j

        # Add source files
        add_files "$hw_dir/hdl/shell/user_lback.svh"
        add_files "$hw_dir/hdl/pkg"
        add_files "$hw_dir/hdl/user"
        add_files "$hw_dir/hdl/common"
        add_files "$proj_dir/hdl"
        add_files "$proj_dir/hdl/wrappers"

        # Top level
        set_property "top" design_user_wrapper_$j [current_fileset]

        # Constraints
        add_files -norecurse -fileset [get_filesets constrs_1] "$proj_dir/xdc"
        set_property used_in_implementation false [get_files -of_objects [get_filesets constrs_1]]
        #set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]

        # Create a project-local constraint file to take debugging constraints that we
        # don't want to propagate to the repository.
        file mkdir "$proj_dir/$project.srcs/constrs_1"
        close [ open "$proj_dir/$project.srcs/constrs_1/local.xdc" w ]

        set_property target_constrs_file "$proj_dir/$project.srcs/constrs_1/local.xdc" [current_fileset -constrset]

        # User infrastructure
        source "$scripts_dir/ip_inst/user_infrastructure.tcl" -notrace
        source "$scripts_dir/ip_inst/common_infrastructure.tcl" -notrace

        # Close
        close_project

        # User
        puts "[color $clr_flow "** vFPGA_C$i\_$j project created"]"
        puts "[color $clr_flow "**"]"
    }
}

########################################################################################################
# PACKAGE IP
########################################################################################################
if {$cfg(load_apps) eq 1} {
    source "$build_dir/package.tcl"
}

puts "[color $clr_flow "** User projects created"]"
puts "[color $clr_flow "**"]"



