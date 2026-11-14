#!/usr/bin/env python3
from pathlib import Path
OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[1]
for suffix,base in [('compressedgroup','compressed'),('compressedgroupchien','compressedchien')]:
    core=(OUT/f'bch_dec_{base}.sv').read_text().replace(f'bch_dec_{base}',f'bch_dec_{suffix}').replace('bch_bm_compact #(','bch_bm_grouped #(')
    (OUT/f'bch_dec_{suffix}.sv').write_text(core)
    parent=(OUT/f'pbch_dec_rec_{base}.sv').read_text().replace(f'pbch_dec_rec_{base}',f'pbch_dec_rec_{suffix}').replace(f'bch_dec_{base} #(',f'bch_dec_{suffix} #(')
    (OUT/f'pbch_dec_rec_{suffix}.sv').write_text(parent)
    wrapper=(OUT/f'pbch_dec_{base}.sv').read_text().replace(f'pbch_dec_{base}',f'pbch_dec_{suffix}').replace(f'pbch_dec_rec_{base}',f'pbch_dec_rec_{suffix}')
    (OUT/f'pbch_dec_{suffix}.sv').write_text(wrapper)
src=(OUT/'bm_equiv_tb.sv').read_text().replace('bm_equiv_tb','bm_group_equiv_tb').replace('bch_bm_compact #(','bch_bm_grouped #(')
(OUT/'bm_group_equiv_tb.sv').write_text(src)
src=(OUT/'run_bm_equiv.sh').read_text().replace('bm_equiv_t','bm_group_equiv_t').replace('bch_bm_compact.sv','bch_bm_grouped.sv').replace('bm_equiv_tb','bm_group_equiv_tb')
(OUT/'run_bm_group_equiv.sh').write_text(src)
