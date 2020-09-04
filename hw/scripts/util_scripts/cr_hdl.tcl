# Adds the block of code to generation script
proc add_block {target} {
    upvar #1 contents cont
    upvar #1 template temp

    set l_idx [lsearch $cont $target]
    set curr [lrange $cont 0 [expr $l_idx-1]]
    set cont [lrange $cont [expr $l_idx+1] end]

    foreach s $curr {
        set s_tmp [concat "append entity \"$s\\n\""]
        lappend temp $s_tmp
    }
}

# Create hdl from template
proc create_hdl_script {f_in} {
	set f [open $f_in]
    set contents [split [read $f] "\n"]
    close $f

    # Template
    set template {}

    # 
    add_block "-- eof"

    # Write out
    set ent_write {}
    append ent_write "lappend template \$entity\n"
    append ent_write "set vho_file \[open hdl.v w]\n"
    append ent_write "foreach line \$template {\n"
    append ent_write "    puts \$vho_file \$line\n"
    append ent_write "}\n"
    append ent_write "close \$vho_file\n"
    lappend template $ent_write

     # Write the script
    set out_file [open "created.v" w]

    foreach line $template {
        puts $out_file $line
    }
    close $out_file
}

create_hdl_script hdl.sv