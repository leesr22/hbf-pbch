#!/usr/bin/env python3
"""Capture final syndrome directly on the final accepted beat (one less cycle)."""
from pathlib import Path

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[1]
for suffix, original in [('compressedfast','compact'),('compressedfirstfast','pbchfirst')]:
    name=f'bch_syndrome_{suffix}'
    src=(OUT/f'bch_syndrome_{original}.sv').read_text().replace(f'bch_syndrome_{original}',name)
    src=src.replace('    reg finish_q;\n','').replace('busy_q && !finish_q','busy_q')
    src=src.replace("            finish_q <= 1'b0;\n",'').replace("                finish_q <= 1'b0;\n",'')
    old='''                if (seen_q + count_i == N)
                    finish_q <= 1'b1;
            end else if (finish_q) begin
                odd_result_q <= odd_q;
                busy_q <= 1'b0;
                    done_o <= 1'b1;'''
    # Whitespace after replacing a nested line is not significant; match the
    # original post-replacement text exactly to avoid silent partial edits.
    start=src.index('                if (seen_q + count_i == N)')
    end=src.index("                done_o <= 1'b1;",start)+len("                done_o <= 1'b1;")
    src=src[:start]+'''                if (seen_q + count_i == N) begin
                    if (count_i == W) odd_result_q <= odd_full;
                    else if (count_i == PARTIAL_A) odd_result_q <= odd_partial_a;
                    else odd_result_q <= odd_partial_b;
                    busy_q <= 1'b0;
                    done_o <= 1'b1;
                end'''+src[end:]
    (OUT/f'{name}.sv').write_text(src)
    core=(OUT/'bch_dec_compressed.sv').read_text().replace('bch_dec_compressed',f'bch_dec_{suffix}').replace('bch_syndrome_compact #(',f'{name} #(')
    (OUT/f'bch_dec_{suffix}.sv').write_text(core)
    parent=(OUT/'pbch_dec_rec_compressed.sv').read_text().replace('pbch_dec_rec_compressed',f'pbch_dec_rec_{suffix}').replace('bch_dec_compressed #(',f'bch_dec_{suffix} #(')
    (OUT/f'pbch_dec_rec_{suffix}.sv').write_text(parent)
    wrapper=(OUT/'pbch_dec_compressed.sv').read_text().replace('pbch_dec_compressed',f'pbch_dec_{suffix}').replace('pbch_dec_rec_compressed',f'pbch_dec_rec_{suffix}')
    (OUT/f'pbch_dec_{suffix}.sv').write_text(wrapper)
for t,profile in [(8,'bch_base'),(9,'bch_equal_r'),(27,'bch_paper_bm2')]:
    original=f'{profile}_dec_replay_w64'
    variant=f'fair_fast_t{t}'
    source=(ROOT/f'rtl/generated/study_wrappers/{original}.sv').read_text().replace(f'module {original}',f'module pbch_dec_{variant}').replace('bch_dec #(', 'bch_dec_compressedfast #(')
    (OUT/f'pbch_dec_{variant}.sv').write_text(source)
