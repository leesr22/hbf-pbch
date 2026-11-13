#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
high_l=${FWHT_HIGH_L:-7}
group=${FWHT_PIPE_GROUP:-2}
tag=${FWHT_VCS_TAG:-}
build="$root/build/vcs_grouped_regression_h${high_l}_g${group}${tag:+_$tag}"
mkdir -p "$build"

python3 "$root/scripts/gen_fwht_search_regression.py"
vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait \
    -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed \
    "+define+FWHT_HIGH_L=$high_l" "+define+FWHT_PIPE_GROUP=$group" \
    -top selector_search_block_fwht_grouped_tb \
    -o "$build/simv" -Mdir="$build/csrc" \
    "$root/rtl/pbch/fht_max_tree.sv" \
    "$root/rtl/pbch/sparse_signed_sum_tree.sv" \
    "$root/rtl/pbch/selector_search_block_fwht_grouped.sv" \
    "$root/tb/selector_search_block_fwht_grouped_tb.sv" \
    -l "$build/compile.log"

"$build/simv" +vcs+lic+wait \
    "+VEC_DIR=$root/vectors/fwht_search_regression" \
    -l "$build/run.log"
grep -q 'PASS grouped exact FWHT regression cases=' "$build/run.log"
