#!/usr/bin/env bash
set -euo pipefail

pbch_root=$(cd "$(dirname "$0")/.." && pwd)
repo_root=$(cd "$pbch_root/.." && pwd)
if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <enc|dec> [MHz]" >&2
    exit 2
fi

kind=$1
mhz=${2:-250}
case "$kind" in
    enc) top=pbch_fwht_encoder_w256 ;;
    dec) top=pbch_fht_dec_replay_w64 ;;
    *) exit 2 ;;
esac
[[ $mhz =~ ^[0-9]+$ ]] || exit 2

: "${PBCH_TARGET_LIBRARY:=/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/liberty/logic_synth/um28nchslogl35hsl140f_ssgwc0p9v125c.db}"
: "${DC_CMD:=/usr/synopsys/syn/Q-2019.12-SP5-5/bin/dc_shell-xg-t}"

report_dir="$pbch_root/syn/generated_reports/${top}_${mhz}mhz"
work_dir="$pbch_root/syn/work/${top}_${mhz}mhz"
mkdir -p "$report_dir" "$work_dir"

export PBCH_ROOT="$pbch_root"
export PBCH_REPO_ROOT="$repo_root"
export PBCH_TOP="$top"
export PBCH_KIND="$kind"
export PBCH_CLOCK_MHZ="$mhz"
export PBCH_REPORT_DIR="$report_dir"
export PBCH_TARGET_LIBRARY

(cd "$work_dir" && "$DC_CMD" -64bit -f "$pbch_root/syn/synth_pbch.tcl") \
    >"$report_dir/compile.log" 2>&1

cat "$report_dir/status.txt"
