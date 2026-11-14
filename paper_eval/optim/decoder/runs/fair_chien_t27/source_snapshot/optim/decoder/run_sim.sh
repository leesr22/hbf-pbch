#!/usr/bin/env bash
set -euo pipefail
root=/home/leesr0222/hbf-pbch-paper-eval-publish/paper_eval
opt="$root/optim/decoder"
variant=${1:?variant}
mode=${2:-stress}
build="$opt/build/${variant}_$mode"
mkdir -p "$build"
sources=("$root/rtl/bch/bch_syndrome.sv" "$root/rtl/bch/bch_bm.sv" "$root/rtl/bch/bch_chien.sv" "$root/rtl/bch/bch_dec.sv")
defs=(+define+DEC_TOP=pbch_dec_$variant +define+PBCH_MODE +define+L_BITS=13 +define+K_BITS=4096 +define+T_BITS=8 +define+R_BITS=104 +define+W_BITS=64)
if [[ $variant == fair_* ]]; then
    t=${variant##*_t}
    case $t in 8) profile=bch_base;; 9) profile=bch_equal_r;; 27) profile=bch_paper_bm2;; esac
    defs=(+define+DEC_TOP=pbch_dec_$variant +define+L_BITS=0 +define+K_BITS=4096 +define+T_BITS=$t +define+R_BITS=$((t*13)) +define+W_BITS=64)
    if [[ $variant == fair_group* ]]; then
        sources=("$opt/bch_syndrome_compact.sv" "$opt/bch_bm_grouped.sv" "$opt/bch_chien_fair_chien_t$t.sv" "$opt/bch_dec_$variant.sv" "$opt/pbch_dec_$variant.sv" "$opt/decoder_pipeline_metrics_tb.sv")
    elif [[ $variant == fair_chien* ]]; then
        sources=("$opt/bch_syndrome_compact.sv" "$opt/bch_bm_compact.sv" "$opt/bch_chien_$variant.sv" "$opt/bch_dec_$variant.sv" "$opt/pbch_dec_$variant.sv" "$opt/decoder_pipeline_metrics_tb.sv")
    elif [[ $variant == fair_fast* ]]; then
        sources=("$opt/bch_syndrome_compressedfast.sv" "$opt/bch_bm_compact.sv" "$root/rtl/bch/bch_chien.sv" "$opt/bch_dec_compressedfast.sv" "$opt/pbch_dec_$variant.sv" "$opt/decoder_pipeline_metrics_tb.sv")
    elif [[ $variant == fair_compressed* ]]; then
        sources=("$opt/bch_syndrome_compact.sv" "$opt/bch_bm_compact.sv" "$root/rtl/bch/bch_chien.sv" "$opt/bch_dec_compressed.sv" "$opt/pbch_dec_$variant.sv" "$opt/decoder_pipeline_metrics_tb.sv")
    else
        sources=("$root/rtl/bch/bch_syndrome.sv" "$opt/bch_bm_shared.sv" "$root/rtl/bch/bch_chien.sv" "$opt/bch_dec_shared.sv" "$opt/pbch_dec_$variant.sv" "$opt/decoder_pipeline_metrics_tb.sv")
    fi
    tb=decoder_pipeline_metrics_tb
    vectors="$root/vectors/study/$profile/w64"
elif [[ $mode == unmask ]]; then
    sources=("$opt/pbch_unmask_rec_direct.sv" "$opt/pbch_unmask_rec_cse.sv" "$opt/unmask_tb.sv")
    tb=unmask_tb
    vectors="$opt/vectors"
else
    if [[ $variant == compressed* ]]; then
        chien="$root/rtl/bch/bch_chien.sv"
        syndrome="$opt/bch_syndrome_compact.sv"
        bm="$opt/bch_bm_compact.sv"
        if [[ $variant == compressedgroup* ]]; then bm="$opt/bch_bm_grouped.sv"; fi
        if [[ $variant == compressedfirst ]]; then syndrome="$opt/bch_syndrome_pbchfirst.sv"; fi
        if [[ $variant == *fast ]]; then syndrome="$opt/bch_syndrome_$variant.sv"; fi
        if [[ $variant == compressedchien ]]; then chien="$opt/bch_chien_csechien.sv"; fi
        if [[ $variant == compressedgroupchien ]]; then chien="$opt/bch_chien_csechien.sv"; fi
        if [[ $variant == compressedchain* || $variant == compressedtrim ]]; then chien="$opt/bch_chien_$variant.sv"; fi
        sources=("$syndrome" "$bm" "$chien" "$opt/bch_dec_$variant.sv" "$opt/pbch_unmask_rec_cseload.sv")
    elif [[ $variant == *linear* ]]; then
        chien="$root/rtl/bch/bch_chien.sv"
        bm="$root/rtl/bch/bch_bm.sv"
        if [[ $variant == compact* ]]; then bm="$opt/bch_bm_compact.sv"; fi
        if [[ $variant == *chien ]]; then chien="$opt/bch_chien_csechien.sv"; fi
        sources=("$opt/bch_syndrome_linear.sv" "$bm" "$chien" "$opt/bch_dec_$variant.sv" "$opt/pbch_unmask_rec_cseload.sv")
    elif [[ $variant == compact* ]]; then
        chien="$root/rtl/bch/bch_chien.sv"
        if [[ $variant == compactchien ]]; then chien="$opt/bch_chien_csechien.sv"; fi
        sources=("$root/rtl/bch/bch_syndrome.sv" "$opt/bch_bm_compact.sv" "$chien" "$opt/bch_dec_$variant.sv" "$opt/pbch_unmask_rec_cseload.sv")
    elif [[ $variant == binary* ]]; then
        chien="$root/rtl/bch/bch_chien.sv"
        if [[ $variant == binarychien ]]; then chien="$opt/bch_chien_csechien.sv"; fi
        sources=("$root/rtl/bch/bch_syndrome.sv" "$opt/bch_bm_binary.sv" "$chien" "$opt/bch_dec_$variant.sv" "$opt/pbch_unmask_rec_cseload.sv")
    elif [[ $variant == shared* ]]; then
        chien="$root/rtl/bch/bch_chien.sv"
        if [[ $variant == sharedchien ]]; then chien="$opt/bch_chien_csechien.sv"; fi
        sources=("$root/rtl/bch/bch_syndrome.sv" "$opt/bch_bm_shared.sv" "$chien" "$opt/bch_dec_$variant.sv" "$opt/pbch_unmask_rec_cse.sv")
    elif [[ $variant == csechien* ]]; then
        sources=("$root/rtl/bch/bch_syndrome.sv" "$root/rtl/bch/bch_bm.sv" "$opt/bch_chien_$variant.sv" "$opt/bch_dec_$variant.sv" "$opt/pbch_unmask_rec_cse.sv")
    else
        sources+=("$opt/pbch_unmask_rec_$variant.sv")
    fi
    sources+=("$opt/pbch_dec_rec_$variant.sv" "$opt/pbch_dec_$variant.sv")
    if [[ $mode == equiv || $mode == functional ]]; then
        if [[ ${chien:-$root/rtl/bch/bch_chien.sv} != "$root/rtl/bch/bch_chien.sv" ]]; then sources+=("$root/rtl/bch/bch_chien.sv"); fi
        tb=decoder_equiv_tb
        if [[ $mode == functional ]]; then tb=decoder_functional_equiv_tb; fi
        sources+=("$root/rtl/bch/bch_syndrome.sv" "$root/rtl/bch/bch_bm.sv" "$root/rtl/bch/bch_dec.sv" "$root/rtl/pbch/pbch_unmask.sv" "$root/rtl/pbch/pbch_dec_replay.sv" "$root/rtl/generated/study_wrappers/pbch_paper_dec_replay_w64.sv" "$opt/$tb.sv")
        vectors="$opt/vectors"
    elif [[ $mode == pipeline ]]; then
        sources+=("$opt/decoder_pipeline_metrics_tb.sv")
        tb=decoder_pipeline_metrics_tb
        vectors="$root/vectors/study/pbch_paper/w64"
    else
        sources+=("$opt/decoder_tb.sv")
        tb=decoder_tb
        vectors="$opt/vectors"
    fi
fi
vcs +warn=noLNX_OS_VERUN +warn=noLINX_KRNL +vcs+lic+wait -full64 -sverilog -timescale=1ns/1ps -LDFLAGS -Wl,--no-as-needed "+incdir+$root" "${defs[@]}" -top "$tb" -o "$build/simv" -Mdir="$build/csrc" "${sources[@]}" -l "$build/compile.log" > "$build/console.log" 2>&1
"$build/simv" +vcs+lic+wait "+VEC_DIR=$vectors" -l "$build/run.log"
if rg -q 'Fatal:|ERROR' "$build/run.log"; then exit 1; fi
rg 'PASS' "$build/run.log"
