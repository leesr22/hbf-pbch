#!/usr/bin/env python3
"""Same grouped BM candidate for all BCH baselines (including a 3-lane t27)."""
from pathlib import Path
OUT=Path(__file__).resolve().parent
for t in [8,9,27]:
    base=f'fair_chien_t{t}'
    for variant,lanes in [(f'fair_group_t{t}',2 if t==27 else 1)]+([(f'fair_group3_t{t}',3)] if t==27 else []):
        core=(OUT/f'bch_dec_{base}.sv').read_text().replace(f'bch_dec_{base}',f'bch_dec_{variant}').replace('bch_bm_compact #(','bch_bm_grouped #(')
        (OUT/f'bch_dec_{variant}.sv').write_text(core)
        source=(OUT/f'pbch_dec_{base}.sv').read_text().replace(f'pbch_dec_{base}',f'pbch_dec_{variant}').replace(f'bch_dec_{base} #(',f'bch_dec_{variant} #(')
        if t==27: source=source.replace('.BM_LANES(2)',f'.BM_LANES({lanes})')
        (OUT/f'pbch_dec_{variant}.sv').write_text(source)
