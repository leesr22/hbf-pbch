#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)

"$script_dir/run_encoder.sh" t8
"$script_dir/run_encoder.sh" t30
"$script_dir/run_decoder.sh" t8 pipeline
"$script_dir/run_decoder.sh" t30 pipeline

echo "PASS frozen BCH regression"
