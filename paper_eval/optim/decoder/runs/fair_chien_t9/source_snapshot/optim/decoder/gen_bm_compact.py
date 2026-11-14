#!/usr/bin/env python3
"""Compact syndrome history and remove redundant completed-locator storage."""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
src=(OUT/'bch_bm_binary.sv').read_text().replace('module bch_bm_binary #(','module bch_bm_compact #(')
src=src.replace('output reg  [((T+1)*M)-1:0]   locator_o','output wire [((T+1)*M)-1:0]   locator_o')
src=src.replace('output reg  [DEG_W-1:0]       degree_o','output wire [DEG_W-1:0]       degree_o')
src=src.replace('    reg [M-1:0] history_q [0:T];\n    reg [M-1:0] future_q [0:2*T-2];', '    reg [M-1:0] synd_ring [0:2*T-1];')
src=src.replace('mul_b[op]=history_q[op]', 'mul_b[op]=synd_ring[op]')
src=src.replace("            locator_o <= '0;\n",'').replace("            degree_o <= '0;\n",'')
src=src.replace("\n                history_q[j] <= '0;\n",'\n')
src=src.replace("            for (j = 0; j < 2*T-1; j = j + 1)\n                future_q[j] <= '0;", "            for (j = 0; j < 2*T; j = j + 1)\n                synd_ring[j] <= '0;")
old='''                history_q[0] <= syndromes_i[0 +: M];
                for (j = 1; j <= T; j = j + 1)
                    history_q[j] <= '0;
                for (j = 0; j < 2*T-1; j = j + 1)
                    future_q[j] <= syndromes_i[(j+1)*M +: M];'''
# The reset-only replacement above leaves the initialization line untouched
# because its indentation is different; match the exact original block.
assert old in src
src=src.replace(old,'''                synd_ring[0] <= syndromes_i[0 +: M];
                for (j = 1; j < 2*T; j = j + 1)
                    synd_ring[j] <= syndromes_i[(2*T-j)*M +: M];''')
old='''                for (j = T; j > 0; j = j - 1)
                    history_q[j] <= history_q[j-1];
                history_q[0] <= future_q[0];
                for (j = 0; j < 2*T-2; j = j + 1)
                    future_q[j] <= future_q[j+1];
                future_q[2*T-2] <= '0;'''
assert src.count(old)==2
src=src.replace(old,'''                for (j = 2*T-1; j > 0; j = j - 1)
                    synd_ring[j] <= synd_ring[j-1];
                synd_ring[0] <= synd_ring[2*T-1];''')
src=re.sub(r'                    for \(j = 0; j <= T; j = j \+ 1\)\n                        locator_o\[j\*M \+: M\] <= (?:product\[j\]|lambda_next\[j\]);\n','',src)
src=re.sub(r'                    degree_o <= (?:degree_q|degree_next);\n','',src)
src=src.replace('    assign busy_o = busy_q;', '''    assign busy_o = busy_q;
    assign degree_o = degree_q;
    genvar output_j;
    generate
        for(output_j=0;output_j<=T;output_j=output_j+1) begin : locator_output
            assign locator_o[output_j*M +: M]=lambda_q[output_j];
        end
    endgenerate''')
assert 'history_q' not in src and 'future_q' not in src
(OUT/'bch_bm_compact.sv').write_text(src)
for suffix,chien in [('compact','original'),('compactchien','csechien')]:
    core=(ROOT/'rtl/bch/bch_dec.sv').read_text().replace('module bch_dec #(',f'module bch_dec_{suffix} #(').replace('bch_bm #(', 'bch_bm_compact #(')
    if chien != 'original':
        core=core.replace('bch_chien #(', f'bch_chien_{chien} #(')
    (OUT/f'bch_dec_{suffix}.sv').write_text(core)
    parent=(OUT/'pbch_dec_rec_cseload.sv').read_text().replace('module pbch_dec_rec_cseload #(',f'module pbch_dec_rec_{suffix} #(').replace('bch_dec #(',f'bch_dec_{suffix} #(')
    (OUT/f'pbch_dec_rec_{suffix}.sv').write_text(parent)
    wrapper=(OUT/'pbch_dec_cseload.sv').read_text().replace('module pbch_dec_cseload',f'module pbch_dec_{suffix}').replace('pbch_dec_rec_cseload #(',f'pbch_dec_rec_{suffix} #(')
    (OUT/f'pbch_dec_{suffix}.sv').write_text(wrapper)
