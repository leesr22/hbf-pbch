#!/usr/bin/env python3
"""Buffer only independent odd syndromes; reconstruct evens combinationally."""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
src=(OUT/'bch_syndrome_linear.sv').read_text().replace('module bch_syndrome_linear #(', 'module bch_syndrome_compact #(')
src=src.replace('output reg  [(2*T*M)-1:0]     syndromes_o', 'output reg  [(2*T*M)-1:0]     syndromes_o')
src=src.replace('    reg [(T*M)-1:0] odd_q;', '    reg [(T*M)-1:0] odd_q;\n    reg [(T*M)-1:0] odd_result_q;')
src=src.replace("            syndromes_o <= '0;", "            odd_result_q <= '0;")
old='''                for (index = 1; index <= 2*T; index = index + 1) begin
                    if (index[0])
                        full_work[index] = odd_q[((index-1)/2)*M +: M];
                    else
                        full_work[index] = gf_square_linear(full_work[index/2]);
                    syndromes_o[(index-1)*M +: M] <= full_work[index];
                end'''
assert old in src
src=src.replace(old,'                odd_result_q <= odd_q;')
pos=src.index('    always @(posedge clk')
comb='''    // Only T odd syndromes contain independent state. The result bank is
    // held until the next scan completes, exactly like the original 2T bank.
    always @* begin
        for(index=1;index<=2*T;index=index+1) begin
            if(index[0]) full_work[index]=odd_result_q[((index-1)/2)*M +: M];
            else full_work[index]=gf_square_linear(full_work[index/2]);
            syndromes_o[(index-1)*M +: M]=full_work[index];
        end
    end

'''
src=src[:pos]+comb+src[pos:]
(OUT/'bch_syndrome_compact.sv').write_text(src)
for suffix,chien in [('compressed',False),('compressedchien',True)]:
    core=(ROOT/'rtl/bch/bch_dec.sv').read_text().replace('module bch_dec #(',f'module bch_dec_{suffix} #(').replace('bch_syndrome #(', 'bch_syndrome_compact #(').replace('bch_bm #(', 'bch_bm_compact #(')
    if chien: core=core.replace('bch_chien #(', 'bch_chien_csechien #(')
    (OUT/f'bch_dec_{suffix}.sv').write_text(core)
    parent=(OUT/'pbch_dec_rec_cseload.sv').read_text().replace('module pbch_dec_rec_cseload #(',f'module pbch_dec_rec_{suffix} #(').replace('bch_dec #(',f'bch_dec_{suffix} #(')
    (OUT/f'pbch_dec_rec_{suffix}.sv').write_text(parent)
    wrapper=(OUT/'pbch_dec_cseload.sv').read_text().replace('module pbch_dec_cseload',f'module pbch_dec_{suffix}').replace('pbch_dec_rec_cseload #(',f'pbch_dec_rec_{suffix} #(')
    (OUT/f'pbch_dec_{suffix}.sv').write_text(wrapper)
