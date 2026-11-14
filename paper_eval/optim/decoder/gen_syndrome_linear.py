#!/usr/bin/env python3
"""Express GF squaring as its exact binary linear map, not a multiplier."""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
src=(ROOT/'rtl/bch/bch_syndrome.sv').read_text().replace('module bch_syndrome #(', 'module bch_syndrome_linear #(')
pos=src.index('    // Keep the bank packed.')
fn='''    // Squaring in GF(2^M) is linear: (sum a_i*x^i)^2=sum a_i*x^(2i).
    // The original general multiplier expression needlessly obscured this
    // identity from Boolean technology mapping. Every basis image is constant.
    function automatic [M-1:0] gf_square_linear(input [M-1:0] a_i);
        reg [M-1:0] basis;
        reg [M-1:0] result;
        integer bit_index;
        begin
            result='0;
            for(bit_index=0;bit_index<M;bit_index=bit_index+1) begin
                basis={{(M-1){1'b0}},1'b1} << bit_index;
                result=result ^ (gf_mul(basis,basis) & {M{a_i[bit_index]}});
            end
            gf_square_linear=result;
        end
    endfunction

'''
src=src[:pos]+fn+src[pos:]
src=src.replace('gf_square(full_work[index/2])','gf_square_linear(full_work[index/2])')
(OUT/'bch_syndrome_linear.sv').write_text(src)
for suffix,compact,chien in [('linear',False,False),('compactlinear',True,False),('compactlinearchien',True,True)]:
    core=(ROOT/'rtl/bch/bch_dec.sv').read_text().replace('module bch_dec #(',f'module bch_dec_{suffix} #(').replace('bch_syndrome #(', 'bch_syndrome_linear #(')
    if compact:
        core=core.replace('bch_bm #(', 'bch_bm_compact #(')
    if chien:
        core=core.replace('bch_chien #(', 'bch_chien_csechien #(')
    (OUT/f'bch_dec_{suffix}.sv').write_text(core)
    parent=(OUT/'pbch_dec_rec_cseload.sv').read_text().replace('module pbch_dec_rec_cseload #(',f'module pbch_dec_rec_{suffix} #(').replace('bch_dec #(',f'bch_dec_{suffix} #(')
    (OUT/f'pbch_dec_rec_{suffix}.sv').write_text(parent)
    wrapper=(OUT/'pbch_dec_cseload.sv').read_text().replace('module pbch_dec_cseload',f'module pbch_dec_{suffix}').replace('pbch_dec_rec_cseload #(',f'pbch_dec_rec_{suffix} #(')
    (OUT/f'pbch_dec_{suffix}.sv').write_text(wrapper)
