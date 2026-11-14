set root $::env(DEC_ROOT)
set opt "$root/optim/decoder"
set variant $::env(DEC_VARIANT)
set top "pbch_dec_$variant"
set report_dir "$opt/runs/$variant"
file mkdir $report_dir
set_host_options -max_cores 2
set_app_var search_path [list $root "$root/rtl"]
set_app_var target_library [list $::env(HBF_ECC_TARGET_LIBRARY)]
set_app_var link_library [concat "*" $target_library]
if {[string match "fair_group*" $variant]} {
    regexp {_t([0-9]+)$} $variant unused t
    set sources [list "$opt/bch_syndrome_compact.sv" "$opt/bch_bm_grouped.sv" "$opt/bch_chien_fair_chien_t$t.sv" "$opt/bch_dec_$variant.sv" "$opt/$top.sv"]
} elseif {[string match "fair_chien_t*" $variant]} {
    set sources [list "$opt/bch_syndrome_compact.sv" "$opt/bch_bm_compact.sv" "$opt/bch_chien_$variant.sv" "$opt/bch_dec_$variant.sv" "$opt/$top.sv"]
} elseif {[string match "fair_fast_t*" $variant]} {
    set sources [list "$opt/bch_syndrome_compressedfast.sv" "$opt/bch_bm_compact.sv" "$root/rtl/bch/bch_chien.sv" "$opt/bch_dec_compressedfast.sv" "$opt/$top.sv"]
} elseif {[string match "fair_compressed_t*" $variant]} {
    set sources [list "$opt/bch_syndrome_compact.sv" "$opt/bch_bm_compact.sv" "$root/rtl/bch/bch_chien.sv" "$opt/bch_dec_compressed.sv" "$opt/$top.sv"]
} elseif {[string match "compressed*" $variant]} {
    set chien "$root/rtl/bch/bch_chien.sv"
    set syndrome "$opt/bch_syndrome_compact.sv"
    set bm "$opt/bch_bm_compact.sv"
    if {[string match "compressedgroup*" $variant]} {set bm "$opt/bch_bm_grouped.sv"}
    if {[string match "*first*" $variant]} {set syndrome "$opt/bch_syndrome_pbchfirst.sv"}
    if {[string match "*fast" $variant]} {set syndrome "$opt/bch_syndrome_$variant.sv"}
    if {[string match "*chien" $variant]} {set chien "$opt/bch_chien_csechien.sv"}
    if {[string match "compressedchain*" $variant] || $variant eq "compressedtrim"} {set chien "$opt/bch_chien_$variant.sv"}
    set sources [list $syndrome $bm $chien "$opt/bch_dec_$variant.sv" "$opt/pbch_unmask_rec_cseload.sv" "$opt/pbch_dec_rec_$variant.sv" "$opt/$top.sv"]
} elseif {[string match "*linear*" $variant]} {
    set chien "$root/rtl/bch/bch_chien.sv"
    set bm "$root/rtl/bch/bch_bm.sv"
    if {[string match "compact*" $variant]} {set bm "$opt/bch_bm_compact.sv"}
    if {[string match "*chien" $variant]} {set chien "$opt/bch_chien_csechien.sv"}
    set sources [list "$opt/bch_syndrome_linear.sv" $bm $chien "$opt/bch_dec_$variant.sv" "$opt/pbch_unmask_rec_cseload.sv" "$opt/pbch_dec_rec_$variant.sv" "$opt/$top.sv"]
} elseif {[string match "compact*" $variant]} {
    set chien "$root/rtl/bch/bch_chien.sv"
    if {$variant eq "compactchien"} {set chien "$opt/bch_chien_csechien.sv"}
    set sources [list "$root/rtl/bch/bch_syndrome.sv" "$opt/bch_bm_compact.sv" $chien "$opt/bch_dec_$variant.sv" "$opt/pbch_unmask_rec_cseload.sv" "$opt/pbch_dec_rec_$variant.sv" "$opt/$top.sv"]
} elseif {[string match "binary*" $variant]} {
    set chien "$root/rtl/bch/bch_chien.sv"
    if {$variant eq "binarychien"} {set chien "$opt/bch_chien_csechien.sv"}
    set sources [list "$root/rtl/bch/bch_syndrome.sv" "$opt/bch_bm_binary.sv" $chien "$opt/bch_dec_$variant.sv" "$opt/pbch_unmask_rec_cseload.sv" "$opt/pbch_dec_rec_$variant.sv" "$opt/$top.sv"]
} elseif {[string match "fair_t*" $variant]} {
    set sources [list "$root/rtl/bch/bch_syndrome.sv" "$opt/bch_bm_shared.sv" "$root/rtl/bch/bch_chien.sv" "$opt/bch_dec_shared.sv" "$opt/$top.sv"]
} elseif {[string match "shared*" $variant]} {
    set chien "$root/rtl/bch/bch_chien.sv"
    if {$variant eq "sharedchien"} {set chien "$opt/bch_chien_csechien.sv"}
    set sources [list "$root/rtl/bch/bch_syndrome.sv" "$opt/bch_bm_shared.sv" $chien "$opt/bch_dec_$variant.sv" "$opt/pbch_unmask_rec_cse.sv" "$opt/pbch_dec_rec_$variant.sv" "$opt/$top.sv"]
} elseif {[string match "csechien*" $variant]} {
    set sources [list "$root/rtl/bch/bch_syndrome.sv" "$root/rtl/bch/bch_bm.sv" "$opt/bch_chien_$variant.sv" "$opt/bch_dec_$variant.sv" "$opt/pbch_unmask_rec_cse.sv" "$opt/pbch_dec_rec_$variant.sv" "$opt/$top.sv"]
} else {
    set sources [list "$root/rtl/bch/bch_syndrome.sv" "$root/rtl/bch/bch_bm.sv" "$root/rtl/bch/bch_chien.sv" "$root/rtl/bch/bch_dec.sv" "$opt/pbch_unmask_rec_$variant.sv" "$opt/pbch_dec_rec_$variant.sv" "$opt/$top.sv"]
}
foreach source $sources {
    if {[analyze -format sverilog -define SYNTHESIS $source] == 0} {exit 2}
}
if {[elaborate $top] == 0} {exit 3}
current_design $top
if {[link] == 0} {exit 4}
create_clock -name clk -period [expr {10.0/3.0}] [get_ports clk]
set_clock_uncertainty 0.20 [get_clocks clk]
set_input_delay 0.40 -clock clk [remove_from_collection [all_inputs] [get_ports {clk reset_n}]]
set_output_delay 0.40 -clock clk [all_outputs]
set_false_path -from [get_ports reset_n]
set_max_area 0
compile_ultra -no_autoungroup
redirect "$report_dir/check_design.rpt" {check_design}
redirect "$report_dir/area.rpt" {report_area -physical -hierarchy}
redirect "$report_dir/timing.rpt" {report_timing -delay_type max -max_paths 10}
redirect "$report_dir/qor.rpt" {report_qor}
set slack [get_attribute [get_timing_paths -delay_type max -max_paths 1] slack]
set fp [open "$report_dir/area.rpt" r]
set area_text [read $fp]
close $fp
regexp {Total cell area:[[:space:]]+([0-9.]+)} $area_text unused area
set fp [open "$report_dir/status.txt" w]
puts $fp "area_um2=$area"
puts $fp "slack_ns=$slack"
puts $fp "nand2_ge=[expr {$area/0.504}]"
close $fp
write -format verilog -hierarchy -output "$report_dir/netlist.v"
quit
