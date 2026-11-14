#!/usr/bin/env bash
set -euo pipefail
root=/home/leesr0222/hbf-pbch-paper-eval-publish/paper_eval
opt="$root/optim/decoder"
variant=${1:?variant}
mode=${2:-stress}
build="$opt/build/${variant}_gate"
library=/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/verilog/3.0/um28nchslogl35hsl140f.v
mkdir -p "$build"
test -s "$opt/runs/$variant/netlist.v"
tb=decoder_tb
vectors="$opt/vectors"
defs=(+define+DEC_TOP=pbch_dec_$variant)
if [[ $variant == fair_* ]]; then
    t=${variant##*_t}
    case $t in 8) profile=bch_base;; 9) profile=bch_equal_r;; 27) profile=bch_paper_bm2;; esac
    tb=decoder_pipeline_metrics_tb
    vectors="$root/vectors/study/$profile/w64"
    defs+=(+define+L_BITS=0 +define+K_BITS=4096 +define+T_BITS=$t +define+R_BITS=$((13*t)) +define+W_BITS=64 +define+PIPELINE_FRAMES=${DEC_PIPELINE_FRAMES:-25})
    if [[ $mode == pipeline_stress ]]; then defs+=(+define+STRESS_PIPELINE); fi
fi
vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed "+incdir+$root" "${defs[@]}" +define+VIRL_functiononly +define+SNPS_SEQ_DELAY=0 +define+SNPS_COMBO_DELAY=0 +define+SNPS_LAT_DELAY=0 +notimingcheck -top "$tb" -o "$build/simv" -Mdir="$build/csrc" "$library" "$opt/runs/$variant/netlist.v" "$opt/$tb.sv" -l "$build/compile.log" > "$build/console.log" 2>&1
"$build/simv" +vcs+lic+wait "+VEC_DIR=$vectors" -l "$build/run.log"
if rg -q 'Fatal:|ERROR' "$build/run.log"; then exit 1;fi
rg 'PASS' "$build/run.log"
