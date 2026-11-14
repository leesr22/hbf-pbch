#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
point=$1
build="$root/optim/fwht/build/$point"
mkdir -p "$build"
cd "$build"
vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait -full64 -sverilog \
 -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed -top fwht_compact_tb \
 -o "$build/simv" -Mdir="$build/csrc" \
 "$root/rtl/pbch/fht_max_tree.sv" "$root/rtl/pbch/sparse_signed_sum_tree.sv" \
 "$root/optim/fwht/selector_search_fwht_compact.sv" \
 "$root/optim/fwht/generated/$point.sv" "$root/optim/fwht/generated/${point}_tb.sv" \
 -l "$build/compile.log" > "$build/stdout.log" 2>&1
"$build/simv" +vcs+lic+wait "+VEC_DIR=$root/optim/fwht/generated" -l "$build/run.log" >> "$build/stdout.log" 2>&1
mkdir -p "$root/optim/fwht/results/$point"
cp "$build/run.log" "$root/optim/fwht/results/$point/simulation.log"
tail -4 "$build/run.log"
