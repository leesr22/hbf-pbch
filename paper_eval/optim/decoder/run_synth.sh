#!/usr/bin/env bash
set -euo pipefail
export DEC_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export DEC_VARIANT=${1:?variant}
export HBF_ECC_TARGET_LIBRARY=${HBF_ECC_TARGET_LIBRARY:-/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/liberty/logic_synth/um28nchslogl35hsl140f_ssgwc0p9v125c.db}
export DEC_RUN_ROOT=${DEC_RUN_ROOT:-$DEC_ROOT/optim/decoder/runs}
run="$DEC_RUN_ROOT/$DEC_VARIANT"
mkdir -p "$run/work"
python3 "$DEC_ROOT/optim/decoder/snapshot.py" "$DEC_VARIANT" "$run"
cd "$run/work"
"${DC_BIN:-dc_shell-xg-t}" -64bit -f "$DEC_ROOT/optim/decoder/synth.tcl" > "$run/compile.log" 2>&1
test -s "$run/status.txt"
cat "$run/status.txt"
