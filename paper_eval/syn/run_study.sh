#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -ne 5 ]]; then
    echo "usage: $0 <bch_base|bch_equal_r|bch_paper|bch_paper_bm2|pbch_paper> <enc|dec> <replay|bg7h7_32_128> <512|64> <MHz>" >&2
    exit 2
fi
profile=$1
kind=$2
variant=$3
width=$4
mhz=$5
case "$profile" in bch_base|bch_equal_r|bch_paper|bch_paper_bm2|pbch_paper) ;; *) exit 2 ;; esac
case "$kind" in enc|dec) ;; *) exit 2 ;; esac
[[ $mhz =~ ^[0-9]+$ ]] || exit 2

if [[ $kind == enc ]]; then
    [[ $width == 512 ]] || exit 2
    if [[ $profile == pbch_paper ]]; then
        [[ $variant == bg7h7_32_128 ]] || exit 2
        top="pbch_paper_blockg7_fwht_h7_m32_p128_w512"
    else
        case "$profile" in bch_base|bch_equal_r|bch_paper) ;; *) exit 2 ;; esac
        [[ $variant == replay ]] || exit 2
        top="${profile}_enc_w${width}"
    fi
else
    [[ $width == 64 && $variant == replay ]] || exit 2
    case "$profile" in bch_base|bch_equal_r|bch_paper_bm2|pbch_paper) ;; *) exit 2 ;; esac
    top="${profile}_dec_${variant}_w${width}"
fi

export HBF_FHT_ROOT="$root" HBF_FHT_TOP="$top" HBF_FHT_PROFILE="$profile"
export HBF_FHT_KIND="$kind" HBF_FHT_VARIANT="$variant"
export HBF_FHT_WIDTH="$width" HBF_FHT_CLOCK_MHZ="$mhz"
export HBF_FHT_RUN_TAG="${HBF_FHT_RUN_TAG:-}"
: "${HBF_ECC_TARGET_LIBRARY:?set HBF_ECC_TARGET_LIBRARY to the target Liberty .db file}"
export HBF_ECC_TARGET_LIBRARY
dc_cmd=${DC_CMD:-dc_shell-xg-t}
tag=${HBF_FHT_RUN_TAG}
run="${top}${tag:+_$tag}_${mhz}mhz"
if [[ ${HBF_FHT_SKIP_DONE:-0} == 1 && -s "$root/syn/study_results/$run/status.txt" ]]; then
    cat "$root/syn/study_results/$run/status.txt"
    exit 0
fi
mkdir -p "$root/syn/study_reports/$run" "$root/syn/study_results/$run" \
         "$root/syn/study_work/$run"
run_dc() {
    (cd "$root/syn/study_work/$run" &&
        "$dc_cmd" -64bit -f "$root/syn/synth_study.tcl") \
        >"$root/syn/study_reports/$run/compile.log" 2>&1
}

if [[ ${HBF_FHT_NO_LOCK:-0} == 1 ]]; then
    # Intended only for small points when the server and license pool have
    # enough headroom; the exact-FHT points remain serialized by default.
    run_dc
else
    exec 9>/tmp/hbf_fht_umc28_dc.lock
    flock 9
    # A separately authorized small-point run may have completed while this
    # process waited behind a large FHT job.
    if [[ ${HBF_FHT_SKIP_DONE:-0} == 1 && -s "$root/syn/study_results/$run/status.txt" ]]; then
        cat "$root/syn/study_results/$run/status.txt"
    else
        run_dc
    fi
fi
cat "$root/syn/study_results/$run/status.txt"
