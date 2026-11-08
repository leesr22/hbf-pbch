#!/usr/bin/env bash
set -euo pipefail

bch_root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -ne 1 ]]; then
    echo "usage: $0 <t8|t30>" >&2
    exit 2
fi

case "$1" in
    t8)
        profile=bch_base
        top=bch_base_enc_w512
        r=104
        ;;
    t30)
        profile=bch_target
        top=bch_target_enc_w512
        r=390
        ;;
    *)
        echo "unknown configuration: $1" >&2
        exit 2
        ;;
esac

width=512
build="$bch_root/sim/build/$top"
mkdir -p "$build"

vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait \
    -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed \
    "+incdir+$bch_root" "+define+ENC_TOP=$top" "+define+R_BITS=$r" \
    "+define+W_BITS=$width" -top study_bch_encoder_tb \
    -o "$build/simv" -Mdir="$build/csrc" \
    "$bch_root/rtl/bch/bch_enc.sv" \
    "$bch_root/rtl/generated/$top.sv" \
    "$bch_root/sim/tb/study_bch_encoder_tb.sv" \
    -l "$build/compile.log"

"$build/simv" +vcs+lic+wait \
    "+VEC_DIR=$bch_root/sim/vectors/$profile/w$width" \
    -l "$build/run.log"

grep -q 'PASS BCH encoder' "$build/run.log"
