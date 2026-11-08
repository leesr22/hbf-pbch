set root $::env(BCH_ROOT)
set top $::env(BCH_TOP)
set kind $::env(BCH_KIND)
set mhz $::env(BCH_CLOCK_MHZ)
set report_dir $::env(BCH_REPORT_DIR)

file mkdir $report_dir
set_app_var search_path [list $root "$root/rtl"]
set_app_var target_library [list $::env(BCH_TARGET_LIBRARY)]
set_app_var link_library [concat "*" $target_library]

if {$kind eq "enc"} {
    set sources [list "$root/rtl/bch/bch_enc.sv"]
} else {
    set sources [list \
        "$root/rtl/bch/bch_syndrome.sv" \
        "$root/rtl/bch/bch_bm.sv" \
        "$root/rtl/bch/bch_chien.sv" \
        "$root/rtl/bch/bch_dec.sv"]
}
lappend sources "$root/rtl/generated/$top.sv"

foreach source $sources {
    if {[analyze -format sverilog -define SYNTHESIS $source] == 0} {
        puts stderr "ANALYZE_FAILED $source"
        exit 2
    }
}
if {[elaborate $top] == 0} { exit 3 }
current_design $top
if {[link] == 0} { exit 4 }

set period [expr {1000.0 / double($mhz)}]
create_clock -name clk -period $period [get_ports clk]
set_clock_uncertainty 0.20 [get_clocks clk]
set_input_delay 0.40 -clock clk \
    [remove_from_collection [all_inputs] [get_ports {clk reset_n}]]
set_output_delay 0.40 -clock clk [all_outputs]
set_false_path -from [get_ports reset_n]
set_max_area 0

compile_ultra -no_autoungroup

redirect "$report_dir/check_design.rpt" { check_design }
redirect "$report_dir/area.rpt" { report_area -physical -hierarchy }
redirect "$report_dir/area_hierarchy.rpt" { report_area -hierarchy }
redirect "$report_dir/qor.rpt" { report_qor }
redirect "$report_dir/timing_max.rpt" {
    report_timing -delay_type max -max_paths 20 -nworst 5
}
redirect "$report_dir/references.rpt" { report_reference -hierarchy }

set paths [get_timing_paths -delay_type max -max_paths 1]
set slack [get_attribute $paths slack]
set area_file [open "$report_dir/area.rpt" r]
set area_text [read $area_file]
close $area_file
set area ""
regexp {Total cell area:[[:space:]]+([0-9.]+)} $area_text unused area

set status [open "$report_dir/status.txt" w]
if {$slack >= 0.0} {
    puts $status "result=PASS"
} else {
    puts $status "result=TIMING_FAIL"
}
puts $status "slack_ns=$slack"
puts $status "area_um2=$area"
puts $status "period_ns=$period"
puts $status "top=$top"
close $status
quit
