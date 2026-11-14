set root $::env(FWHT_ROOT)
set point $::env(FWHT_POINT)
set dir "$root/optim/fwht/results/$point"
file mkdir $dir
set_app_var search_path [list $root "$root/rtl"]
set_app_var target_library [list /media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/liberty/logic_synth/um28nchslogl35hsl140f_ssgwc0p9v125c.db]
set_app_var link_library [concat "*" $target_library]
set_host_options -max_cores 2
foreach source [list "$root/rtl/pbch/fht_max_tree.sv" "$root/rtl/pbch/sparse_signed_sum_tree.sv" "$root/optim/fwht/selector_search_fwht_compact.sv" "$root/optim/fwht/generated/$point.sv"] {
    if {[analyze -format sverilog -define SYNTHESIS $source]==0} {exit 2}
}
if {[elaborate $point]==0} {exit 3}
current_design $point
if {[link]==0} {exit 4}
create_clock -name clk -period 3.333333333 [get_ports clk]
set_clock_uncertainty 0.20 [get_clocks clk]
set_input_delay 0.40 -clock clk [remove_from_collection [all_inputs] [get_ports {clk reset_n}]]
set_output_delay 0.40 -clock clk [all_outputs]
set_false_path -from [get_ports reset_n]
set_max_area 0
compile_ultra -no_autoungroup
redirect "$dir/area.rpt" {report_area -hierarchy}
redirect "$dir/timing.rpt" {report_timing -max_paths 10}
redirect "$dir/check.rpt" {check_design}
set area_file [open "$dir/area.rpt" r]
set area_text [read $area_file]
close $area_file
regexp {Total cell area:[[:space:]]+([0-9.]+)} $area_text unused area
set slack [get_attribute [get_timing_paths -max_paths 1] slack]
set out [open "$dir/status.txt" w]
puts $out "area_um2=$area"
puts $out "ge=[expr {$area/0.504}]"
puts $out "slack_ns=$slack"
close $out
quit
