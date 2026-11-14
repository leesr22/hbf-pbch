#!/usr/bin/env bash
set -euo pipefail
root=/home/leesr0222/hbf-pbch-paper-eval-publish/paper_eval
opt="$root/optim/decoder"
t=${1:?t}
build="$opt/build/bm_group_equiv_t$t"
mkdir -p "$build"
vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed "+incdir+$root" +define+T_BITS="$t" -top bm_group_equiv_tb -o "$build/simv" -Mdir="$build/csrc" "$root/rtl/bch/bch_bm.sv" "$opt/bch_bm_shared.sv" "$opt/bch_bm_binary.sv" "$opt/bch_bm_grouped.sv" "$opt/bm_group_equiv_tb.sv" -l "$build/compile.log" > "$build/console.log" 2>&1
"$build/simv" +vcs+lic+wait "+VEC_FILE=$opt/vectors/bm_t$t.mem" -l "$build/run.log"
if rg -q 'Fatal:|ERROR' "$build/run.log"; then exit 1;fi
rg 'PASS' "$build/run.log"
