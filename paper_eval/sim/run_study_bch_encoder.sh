#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -ne 2 ]]; then
    echo "usage: $0 <bch_base|bch_equal_r|bch_paper> 512" >&2
    exit 2
fi
profile=$1
width=$2
case "$profile" in
    bch_base) r=104 ;;
    bch_equal_r) r=117 ;;
    bch_paper) r=351 ;;
    *) exit 2 ;;
esac
[[ $width == 512 ]] || exit 2

top="${profile}_enc_w${width}"
build="$root/build/vcs_${top}"
mkdir -p "$build"
vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait \
    -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed \
    "+incdir+$root" "+define+ENC_TOP=$top" "+define+R_BITS=$r" \
    "+define+W_BITS=$width" -top study_bch_encoder_tb \
    -o "$build/simv" -Mdir="$build/csrc" \
    "$root/rtl/bch/bch_enc.sv" "$root/rtl/generated/study_wrappers/$top.sv" \
    "$root/tb/study_bch_encoder_tb.sv" -l "$build/compile.log"
"$build/simv" +vcs+lic+wait \
    "+VEC_DIR=$root/vectors/study/$profile/w$width" -l "$build/run.log"
if grep -q 'Fatal:' "$build/run.log" || ! grep -q 'PASS BCH encoder' "$build/run.log"; then
    exit 1
fi
