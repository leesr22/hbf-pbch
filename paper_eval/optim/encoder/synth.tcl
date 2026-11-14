set root $::env(ENC_OPT_ROOT)
set name $::env(ENC_OPT_NAME)
set opt "$root/optim/encoder"
set top "pbch_encoder_$name"
set report_dir "$opt/runs/$name"
if {[info exists ::env(ENC_OPT_RUN_DIR)]} {set report_dir $::env(ENC_OPT_RUN_DIR)}
file mkdir $report_dir
set_host_options -max_cores 2
set_app_var search_path [list $root "$root/rtl"]
set_app_var target_library [list $::env(HBF_ECC_TARGET_LIBRARY)]
set_app_var link_library [concat "*" $target_library]
source "$report_dir/sources.tcl"
foreach source $sources {
    if {[analyze -format sverilog -define SYNTHESIS $source] == 0} {exit 2}
}
if {[elaborate $top] == 0} {exit 3}
current_design $top
if {[link] == 0} {exit 4}
redirect "$report_dir/precheck.rpt" {check_design}
create_clock -name clk -period [expr {10.0/3.0}] [get_ports clk]
set_clock_uncertainty 0.20 [get_clocks clk]
set_input_delay 0.40 -clock clk [remove_from_collection [all_inputs] [get_ports {clk reset_n}]]
set_output_delay 0.40 -clock clk [all_outputs]
set_false_path -from [get_ports reset_n]
set_max_area 0
compile_ultra -no_autoungroup
redirect "$report_dir/check_design.rpt" {check_design}
redirect "$report_dir/area.rpt" {report_area -physical -hierarchy}
redirect "$report_dir/timing.rpt" {report_timing -delay_type max -max_paths 20}
redirect "$report_dir/qor.rpt" {report_qor}
redirect "$report_dir/constraints.rpt" {report_constraint -all_violators}
set slack [get_attribute [get_timing_paths -delay_type max -max_paths 1] slack]
set fp [open "$report_dir/area.rpt" r]
set area_text [read $fp]
close $fp
regexp {Total cell area:[[:space:]]+([0-9.]+)} $area_text unused area
set fp [open "$report_dir/status.txt" w]
puts $fp "result=[expr {$slack >= 0 ? {PASS} : {TIMING_FAIL}}]"
puts $fp "area_um2=$area"
puts $fp "slack_ns=$slack"
puts $fp "nand2_ge=[expr {$area/0.504}]"
puts $fp "frequency_MHz=300"
puts $fp "library=$::env(HBF_ECC_TARGET_LIBRARY)"
close $fp
write -format verilog -hierarchy -output "$report_dir/netlist.v"
write -format ddc -hierarchy -output "$report_dir/mapped.ddc"
quit
