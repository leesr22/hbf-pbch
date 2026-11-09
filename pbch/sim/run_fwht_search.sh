#!/usr/bin/env bash
set -euo pipefail

pbch_root=$(cd "$(dirname "$0")/.." && pwd)
build="$pbch_root/sim/build/fwht_search_h7"
vectors="$pbch_root/sim/vectors/fwht_search_regression"
mkdir -p "$build"

vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait \
    -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed \
    -top fwht_search_h7_tb -o "$build/simv" -Mdir="$build/csrc" \
    "$pbch_root/rtl/encoder/fwht_max_tree.sv" \
    "$pbch_root/rtl/encoder/signed_sum_tree.sv" \
    "$pbch_root/rtl/encoder/fwht_search_h7.sv" \
    "$pbch_root/sim/tb/fwht_search_h7_tb.sv" \
    -l "$build/compile.log"

"$build/simv" +vcs+lic+wait "+VEC_DIR=$vectors" -l "$build/run.log"
grep -q "PASS fwht_search_h7 exact regression" "$build/run.log"
