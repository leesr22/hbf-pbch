#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
opt="$root/optim/decoder"
run_root=${DEC_RUN_ROOT:-$opt/runs}
variant=${1:?variant}
mode=${2:-stress}
build="${DEC_BUILD_ROOT:-$opt/build}/${variant}_gate"
if [[ $mode != stress ]]; then build="${build}_$mode"; fi
library=${HBF_ECC_CELL_MODEL:-/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/verilog/3.0/um28nchslogl35hsl140f.v}
mkdir -p "$build"
test -s "$run_root/$variant/netlist.v"
tb=decoder_tb
vectors="$opt/vectors"
defs=(+define+DEC_TOP=pbch_dec_$variant)
extra_sources=()
if [[ $variant == fair_* ]]; then
    t=${variant##*_t}
    case $t in 8) profile=bch_base;; 9) profile=bch_equal_r;; 27) profile=bch_paper_bm2;; esac
    tb=decoder_pipeline_metrics_tb
    vectors="$root/vectors/study/$profile/w64"
    defs+=(+define+L_BITS=0 +define+K_BITS=4096 +define+T_BITS=$t +define+R_BITS=$((13*t)) +define+W_BITS=64 +define+PIPELINE_FRAMES=${DEC_PIPELINE_FRAMES:-25})
    if [[ $mode == pipeline_stress ]]; then defs+=(+define+STRESS_PIPELINE); fi
elif [[ $mode == pipeline || $mode == pipeline_stress || $mode == pipeline_fast* ]]; then
    tb=decoder_pipeline_metrics_tb
    vectors="$root/vectors/study/pbch_paper/w64"
    defs+=(+define+PBCH_MODE +define+L_BITS=13 +define+K_BITS=4096 +define+T_BITS=8 +define+R_BITS=104 +define+W_BITS=64 +define+PIPELINE_FRAMES=${DEC_PIPELINE_FRAMES:-25})
    if [[ $mode == pipeline_stress ]]; then defs+=(+define+STRESS_PIPELINE); fi
elif [[ $mode == functional ]]; then
    tb=decoder_functional_equiv_tb
    extra_sources=("$root/rtl/bch/bch_syndrome.sv" "$root/rtl/bch/bch_bm.sv" "$root/rtl/bch/bch_chien.sv" "$root/rtl/bch/bch_dec.sv" "$root/rtl/pbch/pbch_unmask.sv" "$root/rtl/pbch/pbch_dec_replay.sv" "$root/rtl/generated/study_wrappers/pbch_paper_dec_replay_w64.sv")
fi
if [[ $mode == pipeline_fast* ]]; then defs+=(+define+ZERO_START_BUBBLE +define+TRACE_TIMELINE); fi
"${VCS_BIN:-vcs}" +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed "+incdir+$root" "${defs[@]}" +define+VIRL_functiononly +define+SNPS_SEQ_DELAY=0 +define+SNPS_COMBO_DELAY=0 +define+SNPS_LAT_DELAY=0 +notimingcheck -top "$tb" -o "$build/simv" -Mdir="$build/csrc" "$library" "$run_root/$variant/netlist.v" "${extra_sources[@]}" "$opt/$tb.sv" -l "$build/compile.log" > "$build/console.log" 2>&1
"$build/simv" +vcs+lic+wait "+VEC_DIR=$vectors" -l "$build/run.log"
if rg -q 'Fatal:|ERROR' "$build/run.log"; then exit 1;fi
rg 'PASS' "$build/run.log"
