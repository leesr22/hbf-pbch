set root [file dirname [file normalize [info script]]]
set block $::env(SCAN_BLOCK)
set top pbch_scan_label_b${block}
set target_library [list /media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/liberty/logic_synth/um28nchslogl35hsl140f_ssgwc0p9v125c.db]
set link_library [concat "*" $target_library]
set_host_options -max_cores 2
set run "$root/syn_b${block}"
file mkdir $run
define_design_lib WORK -path "$run/work"
analyze -format sverilog "$root/${top}.sv"
elaborate $top
current_design $top
link
create_clock -name clk -period 3.333333333333
set_clock_uncertainty 0.20 [get_clocks clk]
set_input_delay 0.40 -clock clk [all_inputs]
set_output_delay 0.40 -clock clk [all_outputs]
set_max_area 0
compile_ultra -no_autoungroup
redirect "$run/area.rpt" {report_area -hierarchy}
redirect "$run/timing.rpt" {report_timing -max_paths 5}
set path [get_timing_paths -max_paths 1]
set area_input [open "$run/area.rpt" r]
set area_text [read $area_input]
close $area_input
regexp {Total cell area:[[:space:]]+([0-9.]+)} $area_text unused cell_area
set result [open "$run/status.txt" w]
puts $result "area_um2=$cell_area"
puts $result "slack_ns=[get_attribute $path slack]"
close $result
quit
