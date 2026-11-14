#!/usr/bin/env bash
set -euo pipefail
scan_dir=$(cd "$(dirname "$0")" && pwd)
cd "$scan_dir"
export SNPSLMD_LICENSE_FILE=27020@semi-lic.skku.edu
export LM_LICENSE_FILE=8224@semi-lic.skku.edu
if [[ $# == 0 ]]; then
    set -- 0 16 64 case
fi
for scan_block in "$@"; do
    export SCAN_BLOCK="$scan_block"
    /usr/synopsys/syn/Q-2019.12-SP5-5/bin/dc_shell-xg-t -64bit \
        -f synth_scan.tcl >"compile_b${scan_block}.log" 2>&1
    cat "syn_b${scan_block}/status.txt"
done
