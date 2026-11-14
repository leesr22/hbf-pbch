#!/usr/bin/env python3
"""Apply the identical fixed-matrix Chien CSE method to every BCH baseline."""
from pathlib import Path
import json
from gen_chien import make_chien

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[1]
for t,profile in [(8,'bch_base'),(9,'bch_equal_r'),(27,'bch_paper_bm2')]:
    suffix=f'fair_chien_t{t}'
    stats=make_chien(t,4096+13*t,4096,0,(13*t)%64,suffix,8)
    (OUT/f'{suffix}.json').write_text(json.dumps(stats,indent=2)+'\n')
    core=(OUT/'bch_dec_compressed.sv').read_text().replace('bch_dec_compressed',f'bch_dec_{suffix}').replace('bch_chien #(',f'bch_chien_{suffix} #(')
    (OUT/f'bch_dec_{suffix}.sv').write_text(core)
    original=f'{profile}_dec_replay_w64'
    wrapper=(ROOT/f'rtl/generated/study_wrappers/{original}.sv').read_text().replace(f'module {original}',f'module pbch_dec_{suffix}').replace('bch_dec #(',f'bch_dec_{suffix} #(')
    (OUT/f'pbch_dec_{suffix}.sv').write_text(wrapper)
    print(suffix,stats,flush=True)
