#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "usage: $0 <bch_base|bch_equal_r|bch_paper_bm2|pbch_paper> replay 64 [single|pipeline]" >&2
    exit 2
fi
profile=$1
storage=$2
width=$3
mode=${4:-single}
case "$profile" in
    bch_base) k=4096; l=0; r=104; t=8 ;;
    bch_equal_r) k=4096; l=0; r=117; t=9 ;;
    bch_paper_bm2) k=4096; l=0; r=351; t=27 ;;
    pbch_paper) k=4096; l=13; r=104; t=8 ;;
    *) exit 2 ;;
esac
[[ $storage == replay ]] || exit 2
[[ $width == 64 ]] || exit 2
case "$mode" in single|pipeline) ;; *) exit 2 ;; esac

top="${profile}_dec_${storage}_w${width}"
build="$root/build/vcs_${top}_${mode}"
mkdir -p "$build"
defines=("+define+DEC_TOP=$top" "+define+K_BITS=$k" "+define+L_BITS=$l"
         "+define+R_BITS=$r" "+define+T_BITS=$t" "+define+W_BITS=$width")
if [[ $profile == pbch_paper ]]; then defines+=(+define+PBCH_MODE); fi

sources=(
    "$root/rtl/bch/bch_syndrome.sv" "$root/rtl/bch/bch_bm.sv"
    "$root/rtl/bch/bch_chien.sv" "$root/rtl/bch/bch_dec.sv"
    "$root/rtl/bch/codeword_replay_buffer.sv" "$root/rtl/bch/bch_dec_buffered.sv"
    "$root/rtl/pbch/pbch_unmask.sv" "$root/rtl/pbch/pbch_dec_replay.sv"
    "$root/rtl/pbch/pbch_dec_buffered.sv"
    "$root/rtl/generated/study_wrappers/$top.sv"
)
if [[ $mode == pipeline ]]; then
    sources+=("$root/tb/study_decoder_pipeline_tb.sv")
    tb_top=study_decoder_pipeline_tb
else
    sources+=("$root/tb/study_decoder_tb.sv")
    tb_top=study_decoder_tb
fi

vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait -full64 -sverilog \
    -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed "+incdir+$root" \
    "${defines[@]}" -top "$tb_top" -o "$build/simv" -Mdir="$build/csrc" \
    "${sources[@]}" -l "$build/compile.log"
"$build/simv" +vcs+lic+wait "+VEC_DIR=$root/vectors/study/$profile/w$width" \
    -l "$build/run.log"

# VCS can report a testbench $fatal while still returning a zero process code.
if grep -q 'Fatal:' "$build/run.log"; then
    exit 1
fi
if [[ $mode == pipeline ]]; then
    grep -q 'PASS pipeline frames=25' "$build/run.log"
else
    grep -q 'PASS decoder' "$build/run.log"
fi
