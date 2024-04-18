########################################################################################################
# STATIC LAYER SYNTHESIS 
########################################################################################################
puts "[color $clr_flow "** Starting static layer synthesis ..."]"
puts "[color $clr_flow "**"]"
open_project "$build_dir/$project\_static/$project.xpr"
update_compile_order

reset_run synth_1
launch_runs -jobs $cfg(cores) -verbose synth_1
wait_on_run synth_1
open_run synth_1
write_checkpoint -force "$dcp_dir/static/static_synthed.dcp"
report_utilization -file "$rprt_dir/static/static_synthed.rpt"

########################################################################################################
# STATIC LAYER SYNTHESIZED
########################################################################################################
close_project
