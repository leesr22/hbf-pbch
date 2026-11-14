#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
for t,profile in [(8,'bch_base'),(9,'bch_equal_r'),(27,'bch_paper_bm2')]:
    original=f'{profile}_dec_replay_w64'
    variant=f'fair_t{t}'
    source=(ROOT/f'rtl/generated/study_wrappers/{original}.sv').read_text()
    source=source.replace(f'module {original}',f'module pbch_dec_{variant}')
    source=source.replace('bch_dec #(', 'bch_dec_shared #(')
    if t==27:
        source=source.replace('.BM_LANES(2)', '.BM_LANES(3)')
    (OUT/f'pbch_dec_{variant}.sv').write_text(source)
    variant=f'fair_compressed_t{t}'
    source=(ROOT/f'rtl/generated/study_wrappers/{original}.sv').read_text()
    source=source.replace(f'module {original}',f'module pbch_dec_{variant}')
    source=source.replace('bch_dec #(', 'bch_dec_compressed #(')
    (OUT/f'pbch_dec_{variant}.sv').write_text(source)
