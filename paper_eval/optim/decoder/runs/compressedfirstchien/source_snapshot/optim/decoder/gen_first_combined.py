#!/usr/bin/env python3
"""Combine measured PBCH-only first-beat simplification with winning BM/Chien."""
from pathlib import Path
OUT=Path(__file__).resolve().parent
for suffix,base in [('compressedfirstchien','compressedchien'),('compressedgroupfirstchien','compressedgroupchien')]:
    core=(OUT/f'bch_dec_{base}.sv').read_text().replace(f'bch_dec_{base}',f'bch_dec_{suffix}').replace('bch_syndrome_compact #(', 'bch_syndrome_pbchfirst #(')
    (OUT/f'bch_dec_{suffix}.sv').write_text(core)
    parent=(OUT/f'pbch_dec_rec_{base}.sv').read_text().replace(f'pbch_dec_rec_{base}',f'pbch_dec_rec_{suffix}').replace(f'bch_dec_{base} #(',f'bch_dec_{suffix} #(')
    (OUT/f'pbch_dec_rec_{suffix}.sv').write_text(parent)
    wrapper=(OUT/f'pbch_dec_{base}.sv').read_text().replace(f'pbch_dec_{base}',f'pbch_dec_{suffix}').replace(f'pbch_dec_rec_{base}',f'pbch_dec_rec_{suffix}')
    (OUT/f'pbch_dec_{suffix}.sv').write_text(wrapper)
