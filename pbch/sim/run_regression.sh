#!/usr/bin/env bash
set -euo pipefail

pbch_root=$(cd "$(dirname "$0")/.." && pwd)
"$pbch_root/sim/run_fwht_search.sh"
"$pbch_root/sim/run_encoder.sh"
"$pbch_root/sim/run_decoder.sh"
