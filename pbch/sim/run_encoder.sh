#!/usr/bin/env bash
set -euo pipefail

pbch_root=$(cd "$(dirname "$0")/.." && pwd)
top=pbch_fwht_encoder_w512
build="$pbch_root/sim/build/$top"
mkdir -p "$build"

vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait \
    -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed \
    +define+PBCH_TOP=$top +define+PBCH_W=512 \
    -top pbch_encoder_tb -o "$build/simv" -Mdir="$build/csrc" \
    "$pbch_root/rtl/encoder/fwht_max_tree.sv" \
    "$pbch_root/rtl/encoder/signed_sum_tree.sv" \
    "$pbch_root/rtl/encoder/fwht_search_h7.sv" \
    "$pbch_root/rtl/encoder/probe_scan.sv" \
    "$pbch_root/rtl/encoder/pbch_encoder.sv" \
    "$pbch_root/rtl/generated/$top.sv" \
    "$pbch_root/sim/tb/pbch_encoder_tb.sv" \
    -l "$build/compile.log"

"$build/simv" +vcs+lic+wait +RANDOM_BP \
    "+VEC_DIR=$pbch_root/sim/vectors/encoder_max32" \
    -l "$build/run.log"
grep -q "PASS pbch_fwht_encoder MAX_FLAGS=32" "$build/run.log"
