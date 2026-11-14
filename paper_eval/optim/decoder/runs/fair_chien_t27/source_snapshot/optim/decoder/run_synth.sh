#!/usr/bin/env bash
set -euo pipefail
export DEC_ROOT=/home/leesr0222/hbf-pbch-paper-eval-publish/paper_eval
export DEC_VARIANT=${1:?variant}
export HBF_ECC_TARGET_LIBRARY=/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/liberty/logic_synth/um28nchslogl35hsl140f_ssgwc0p9v125c.db
run="$DEC_ROOT/optim/decoder/runs/$DEC_VARIANT"
mkdir -p "$run/work"
python3 "$DEC_ROOT/optim/decoder/snapshot.py" "$DEC_VARIANT"
cd "$run/work"
dc_shell-xg-t -64bit -f "$DEC_ROOT/optim/decoder/synth.tcl" > "$run/compile.log" 2>&1
test -s "$run/status.txt"
cat "$run/status.txt"
