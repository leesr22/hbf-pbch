#!/usr/bin/env bash
set -euo pipefail

pbch_root=$(cd "$(dirname "$0")/.." && pwd)
repo_root=$(cd "$pbch_root/.." && pwd)
top=pbch_fht_dec_replay_w128_bm2
build="$pbch_root/sim/build/$top"
mkdir -p "$build"

vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait \
    -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed \
    "+incdir+$repo_root/bch" \
    +define+DEC_TOP=$top +define+K_BITS=4096 +define+L_BITS=13 \
    +define+R_BITS=169 +define+T_BITS=13 +define+W_BITS=128 \
    +define+PBCH_MODE \
    -top study_decoder_pipeline_tb -o "$build/simv" -Mdir="$build/csrc" \
    "$repo_root/bch/rtl/bch/bch_syndrome.sv" \
    "$repo_root/bch/rtl/bch/bch_bm.sv" \
    "$repo_root/bch/rtl/bch/bch_chien.sv" \
    "$repo_root/bch/rtl/bch/bch_dec.sv" \
    "$pbch_root/rtl/decoder/pbch_unmask.sv" \
    "$pbch_root/rtl/decoder/pbch_dec_replay.sv" \
    "$pbch_root/rtl/generated/$top.sv" \
    "$pbch_root/sim/tb/pbch_decoder_pipeline_tb.sv" \
    -l "$build/compile.log"

"$build/simv" +vcs+lic+wait \
    "+VEC_DIR=$pbch_root/sim/vectors/decoder_w128" -l "$build/run.log"
grep -q "PASS pipeline frames=25" "$build/run.log"
