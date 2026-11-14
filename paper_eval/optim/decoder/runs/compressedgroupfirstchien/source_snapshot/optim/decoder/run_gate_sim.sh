#!/usr/bin/env bash
set -euo pipefail
root=/home/leesr0222/hbf-pbch-paper-eval-publish/paper_eval
opt="$root/optim/decoder"
variant=${1:?variant}
build="$opt/build/${variant}_gate"
library=/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/verilog/3.0/um28nchslogl35hsl140f.v
mkdir -p "$build"
test -s "$opt/runs/$variant/netlist.v"
vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed "+incdir+$root" +define+DEC_TOP=pbch_dec_$variant +define+VIRL_functiononly +define+SNPS_SEQ_DELAY=0 +define+SNPS_COMBO_DELAY=0 +define+SNPS_LAT_DELAY=0 +notimingcheck -top decoder_tb -o "$build/simv" -Mdir="$build/csrc" "$library" "$opt/runs/$variant/netlist.v" "$opt/decoder_tb.sv" -l "$build/compile.log" > "$build/console.log" 2>&1
"$build/simv" +vcs+lic+wait "+VEC_DIR=$opt/vectors" -l "$build/run.log"
if rg -q 'Fatal:|ERROR' "$build/run.log"; then exit 1;fi
rg 'PASS' "$build/run.log"
