set pbch_root $::env(PBCH_ROOT)
set repo_root $::env(PBCH_REPO_ROOT)
set top $::env(PBCH_TOP)
set kind $::env(PBCH_KIND)
set mhz $::env(PBCH_CLOCK_MHZ)
set report_dir $::env(PBCH_REPORT_DIR)

file mkdir $report_dir
set_app_var search_path [list $pbch_root $repo_root "$repo_root/bch"]
set_app_var target_library [list $::env(PBCH_TARGET_LIBRARY)]
set_app_var link_library [concat "*" $target_library]

if {$kind eq "enc"} {
    set sources [list \
        "$pbch_root/rtl/encoder/fwht_max_tree.sv" \
        "$pbch_root/rtl/encoder/signed_sum_tree.sv" \
        "$pbch_root/rtl/encoder/fwht_search_h7.sv" \
        "$pbch_root/rtl/encoder/probe_scan.sv" \
        "$pbch_root/rtl/encoder/pbch_encoder.sv"]
} else {
    set sources [list \
        "$repo_root/bch/rtl/bch/bch_syndrome.sv" \
        "$repo_root/bch/rtl/bch/bch_bm.sv" \
        "$repo_root/bch/rtl/bch/bch_chien.sv" \
        "$repo_root/bch/rtl/bch/bch_dec.sv" \
        "$pbch_root/rtl/decoder/pbch_unmask.sv" \
        "$pbch_root/rtl/decoder/pbch_dec_replay.sv"]
}
lappend sources "$pbch_root/rtl/generated/$top.sv"

foreach source $sources {
    if {[analyze -format sverilog -define SYNTHESIS $source] == 0} {
        puts stderr "ANALYZE_FAILED $source"
        exit 2
    }
}
if {[elaborate $top] == 0} { exit 3 }
current_design $top
if {[link] == 0} { exit 4 }
redirect "$report_dir/precheck.rpt" { check_design }

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
