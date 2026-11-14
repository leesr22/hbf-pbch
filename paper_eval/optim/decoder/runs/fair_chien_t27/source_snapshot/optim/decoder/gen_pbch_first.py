#!/usr/bin/env python3
"""Use the PBCH stream invariant: its 13-bit selector is the first beat."""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
src=(OUT/'bch_syndrome_compact.sv').read_text().replace('module bch_syndrome_compact #(', 'module bch_syndrome_pbchfirst #(')
old='''            odd_partial_a[update_odd*M +: M] = gf_mul(
                odd_q[update_odd*M +: M], PARTIAL_A_STATE_FACTOR[update_odd*M +: M]);'''
assert old in src
src=src.replace(old,"""            // The only PARTIAL_A beat is the leading selector, whose prior
            // syndrome state is zero. No feedback multiplier is necessary.
            odd_partial_a[update_odd*M +: M] = '0;""")
pos=src.index('endmodule')
src=src[:pos]+'''`ifndef SYNTHESIS
    always @(posedge clk) begin
        if(reset_n && valid_i && ready_o && count_i==PARTIAL_A && seen_q!=0)
            $fatal(1,"PBCH selector fragment must be the first codeword beat");
    end
`endif
'''+src[pos:]
(OUT/'bch_syndrome_pbchfirst.sv').write_text(src)
suffix='compressedfirst'
core=(OUT/'bch_dec_compressed.sv').read_text().replace('bch_dec_compressed',f'bch_dec_{suffix}').replace('bch_syndrome_compact #(', 'bch_syndrome_pbchfirst #(')
(OUT/f'bch_dec_{suffix}.sv').write_text(core)
parent=(OUT/'pbch_dec_rec_compressed.sv').read_text().replace('pbch_dec_rec_compressed',f'pbch_dec_rec_{suffix}').replace('bch_dec_compressed #(',f'bch_dec_{suffix} #(')
(OUT/f'pbch_dec_rec_{suffix}.sv').write_text(parent)
wrapper=(OUT/'pbch_dec_compressed.sv').read_text().replace('pbch_dec_compressed',f'pbch_dec_{suffix}').replace('pbch_dec_rec_compressed',f'pbch_dec_rec_{suffix}')
(OUT/f'pbch_dec_{suffix}.sv').write_text(wrapper)
