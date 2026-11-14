set root [file dirname [file normalize [info script]]]
set t $::env(BCH_T)
set top bch_encoder_cse_t${t}
set target_library [list /media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/liberty/logic_synth/um28nchslogl35hsl140f_ssgwc0p9v125c.db]
set link_library [concat "*" $target_library]
set_host_options -max_cores 2
set run "$root/run_t${t}"
file mkdir $run
define_design_lib WORK -path "$run/work"
set source_dir $root
if {[info exists ::env(BCH_SRC_DIR)]} {set source_dir $::env(BCH_SRC_DIR)}
analyze -format sverilog -define SYNTHESIS [list "$source_dir/bch_remainder_cse_t${t}.sv" "$source_dir/bch_encoder_cse_t${t}.sv"]
elaborate $top
current_design $top
link
create_clock -name clk -period 3.333333333333 [get_ports clk]
set_clock_uncertainty 0.20 [get_clocks clk]
set_input_delay 0.40 -clock clk [remove_from_collection [all_inputs] [get_ports {clk reset_n}]]
set_output_delay 0.40 -clock clk [all_outputs]
set_false_path -from [get_ports reset_n]
set_max_area 0
compile_ultra -no_autoungroup
redirect "$run/check_design.rpt" {check_design}
redirect "$run/area.rpt" {report_area -hierarchy}
redirect "$run/timing.rpt" {report_timing -max_paths 5}
redirect "$run/constraints.rpt" {report_constraint -all_violators}
set path [get_timing_paths -max_paths 1]
set area_input [open "$run/area.rpt" r]
set area_text [read $area_input]
close $area_input
regexp {Total cell area:[[:space:]]+([0-9.]+)} $area_text unused cell_area
set result [open "$run/status.txt" w]
puts $result "area_um2=$cell_area"
puts $result "slack_ns=[get_attribute $path slack]"
puts $result "nand2_ge=[expr {$cell_area/0.504}]"
close $result
write -format verilog -hierarchy -output "$run/netlist.v"
write -format ddc -hierarchy -output "$run/mapped.ddc"
quit
