#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
lanes=${HBF_FHT_PIPE_LANES:-128}
width=${HBF_FHT_PIPE_WIDTH:-512}
search=${HBF_FHT_PIPE_SEARCH:-grouped}
profile=${HBF_FHT_PIPE_PROFILE:-pbch_paper}
case "$profile" in
    pbch_paper) top_family="pbch_paper"; default_n=4213; default_vec="$root/vectors/study/pbch_paper_encoder" ;;
    *) echo "unsupported HBF_FHT_PIPE_PROFILE=$profile" >&2; exit 2 ;;
esac
if [[ $search == grouped ]]; then
    high_l=${HBF_FHT_HIGH_L:-7}
    pipe_group=${HBF_FHT_PIPE_GROUP:-7}
    top=${top_family}_blockg${pipe_group}_fwht_h${high_l}_m32_p${lanes}_w${width}
else
    echo "unsupported HBF_FHT_PIPE_SEARCH=$search (use grouped)" >&2
    exit 2
fi
tag=${HBF_FHT_VCS_TAG:-}
vectors=${HBF_FHT_PIPE_VECTORS:-6}
overflow_from=${HBF_FHT_PIPE_OVERFLOW_FROM:-4}
vector_dir=${HBF_FHT_VEC_DIR:-$default_vec}
n_bits=${HBF_FHT_PIPE_N:-$default_n}
build="$root/build/vcs_${top}${tag:+_$tag}"
mkdir -p "$build"

vcs_cmd=${VCS_CMD:-vcs}
"$vcs_cmd" +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait \
    -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed \
    "+incdir+$root" "+define+PBCH_PIPE_TOP=$top" \
    "+define+PBCH_PIPE_W=$width" \
    "+define+PBCH_PIPE_N=$n_bits" \
    "+define+PBCH_PIPE_VECTORS=$vectors" \
    "+define+PBCH_PIPE_OVERFLOW_FROM=$overflow_from" \
    -top pbch_sparse_pipeline_enc_tb \
    -o "$build/simv" -Mdir="$build/csrc" \
    "$root/rtl/pbch/fht_max_tree.sv" \
    "$root/rtl/pbch/sparse_delta_tree.sv" \
    "$root/rtl/pbch/sparse_signed_sum_tree.sv" \
    "$root/rtl/pbch/selector_search_sparse_gray.sv" \
    "$root/rtl/pbch/selector_search_block_fwht.sv" \
    "$root/rtl/pbch/selector_search_block_fwht_grouped.sv" \
    "$root/rtl/pbch/probe_scan.sv" \
    "$root/rtl/pbch/pbch_sparse_pipeline_enc.sv" \
    "$root/rtl/generated/study_wrappers/$top.sv" \
    "$root/tb/pbch_sparse_pipeline_enc_tb.sv" \
    -l "$build/compile.log"

sim_extra=()
if [[ ${HBF_FHT_RANDOM_BP:-0} == 1 ]]; then
    sim_extra+=(+RANDOM_BP)
fi
"$build/simv" +vcs+lic+wait \
    "+VEC_DIR=$vector_dir" "${sim_extra[@]}" -l "$build/run.log"

if grep -q 'Fatal:' "$build/run.log" ||
   ! grep -q 'PASS pbch_sparse_pipeline_enc vectors=' "$build/run.log"; then
    exit 1
fi
