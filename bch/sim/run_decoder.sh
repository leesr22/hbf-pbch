#!/usr/bin/env bash
set -euo pipefail

bch_root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <t8|t30> [single|pipeline]" >&2
    exit 2
fi

mode=${2:-pipeline}
case "$mode" in single|pipeline) ;; *) exit 2 ;; esac

case "$1" in
    t8)
        profile=bch_base
        top=bch_base_dec_replay_w128
        r=104
        t=8
        width=128
        ;;
    t30)
        profile=bch_target
        top=bch_target_dec_replay_w64
        r=390
        t=30
        width=64
        ;;
    *)
        echo "unknown configuration: $1" >&2
        exit 2
        ;;
esac

if [[ $mode == pipeline ]]; then
    tb=study_decoder_pipeline_tb
else
    tb=study_decoder_tb
fi

build="$bch_root/sim/build/${top}_${mode}"
mkdir -p "$build"

vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait \
    -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed \
    "+incdir+$bch_root" "+define+DEC_TOP=$top" "+define+K_BITS=4096" \
    "+define+L_BITS=0" "+define+R_BITS=$r" "+define+T_BITS=$t" \
    "+define+W_BITS=$width" -top "$tb" \
    -o "$build/simv" -Mdir="$build/csrc" \
    "$bch_root/rtl/bch/bch_syndrome.sv" \
    "$bch_root/rtl/bch/bch_bm.sv" \
    "$bch_root/rtl/bch/bch_chien.sv" \
    "$bch_root/rtl/bch/bch_dec.sv" \
    "$bch_root/rtl/generated/$top.sv" \
    "$bch_root/sim/tb/${tb}.sv" \
    -l "$build/compile.log"

"$build/simv" +vcs+lic+wait \
    "+VEC_DIR=$bch_root/sim/vectors/$profile/w$width" \
    -l "$build/run.log"

if [[ $mode == pipeline ]]; then
    grep -q 'PASS pipeline frames=25' "$build/run.log"
else
    grep -q 'PASS decoder' "$build/run.log"
fi
