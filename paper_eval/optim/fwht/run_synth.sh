#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
point=$1
export FWHT_ROOT="$root" FWHT_POINT="$point"
mkdir -p "$root/optim/fwht/results/$point" "$root/optim/fwht/work/$point"
exec 9>/tmp/hbf_fht_umc28_dc.lock
flock 9
cd "$root/optim/fwht/work/$point"
dc_shell-xg-t -64bit -f "$root/optim/fwht/synth.tcl" > "$root/optim/fwht/results/$point/compile.log" 2>&1
cat "$root/optim/fwht/results/$point/status.txt"
