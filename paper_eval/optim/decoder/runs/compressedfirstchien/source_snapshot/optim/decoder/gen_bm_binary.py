#!/usr/bin/env python3
"""Exact binary-BCH BM specialization: odd discrepancies are identically zero.

Retains the inversionless algorithm's gamma scaling, hence the locator itself,
not just its roots, matches the reference. The syndrome source enforces
S_(2j)=S_j^2 for every received binary vector, independent of error count.
"""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
src=(OUT/'bch_bm_shared.sv').read_text().replace('module bch_bm_shared #(','module bch_bm_binary #(')
old='''            end else if (busy_q && phase_q == 1) begin
                for (j = 0; j <= T; j = j + 1)
                    scaled_q[j] <= product[j];
                phase_q <= 2'd2;
'''
new='''            end else if (busy_q && phase_q == 1 && iteration_q[0]) begin
                // The odd discrepancy is zero for binary-code syndromes.
                // Preserve gamma scaling so the exact reference locator matches.
                for (j = 0; j <= T; j = j + 1)
                    lambda_q[j] <= product[j];
                aux_q[0] <= '0;
                for (j = 1; j <= T; j = j + 1)
                    aux_q[j] <= aux_q[j-1];
                delta_q <= delta_q + 1;
                for (j = T; j > 0; j = j - 1)
                    history_q[j] <= history_q[j-1];
                history_q[0] <= future_q[0];
                for (j = 0; j < 2*T-2; j = j + 1)
                    future_q[j] <= future_q[j+1];
                future_q[2*T-2] <= '0;
                phase_q <= 2'd0;
                if (iteration_q == 2*T-1) begin
                    for (j = 0; j <= T; j = j + 1)
                        locator_o[j*M +: M] <= product[j];
                    degree_o <= degree_q;
                    busy_q <= 1'b0;
                    done_o <= 1'b1;
                end else begin
                    iteration_q <= iteration_q + 1'b1;
                end
            end else if (busy_q && phase_q == 1) begin
                for (j = 0; j <= T; j = j + 1)
                    scaled_q[j] <= product[j];
                phase_q <= 2'd2;
'''
assert old in src
src=src.replace(old,new)
old="""                    iteration_q <= iteration_q + 1'b1;
                    phase_q <= 2'd0;
"""
assert old in src
src=src.replace(old,"""                    iteration_q <= iteration_q + 1'b1;
                    phase_q <= 2'd1;
""")
(OUT/'bch_bm_binary.sv').write_text(src)
for suffix,chien in [('binary','original'),('binarychien','csechien')]:
    core=(ROOT/'rtl/bch/bch_dec.sv').read_text().replace('module bch_dec #(',f'module bch_dec_{suffix} #(').replace('bch_bm #(', 'bch_bm_binary #(')
    if chien != 'original':
        core=core.replace('bch_chien #(', f'bch_chien_{chien} #(')
    (OUT/f'bch_dec_{suffix}.sv').write_text(core)
    parent=(OUT/'pbch_dec_rec_cseload.sv').read_text().replace('module pbch_dec_rec_cseload #(',f'module pbch_dec_rec_{suffix} #(').replace('bch_dec #(',f'bch_dec_{suffix} #(')
    (OUT/f'pbch_dec_rec_{suffix}.sv').write_text(parent)
    wrapper=(OUT/'pbch_dec_cseload.sv').read_text().replace('module pbch_dec_cseload',f'module pbch_dec_{suffix}').replace('pbch_dec_rec_cseload #(',f'pbch_dec_rec_{suffix} #(')
    (OUT/f'pbch_dec_{suffix}.sv').write_text(wrapper)
