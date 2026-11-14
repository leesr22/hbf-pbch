#!/usr/bin/env python3
"""Time-share BM multipliers over three cycles/iteration without changing math."""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
src=(ROOT/'rtl/bch/bch_bm.sv').read_text()
src=src.replace('module bch_bm #(', 'module bch_bm_shared #(')
src=src.replace('reg phase_q;', 'reg [1:0] phase_q;\n    reg [M-1:0] scaled_q [0:T];\n    reg [M-1:0] mul_a [0:T];\n    reg [M-1:0] mul_b [0:T];\n    wire [M-1:0] product [0:T];\n    integer op;')
pos=src.index('    always @(posedge')
shared='''    genvar g;
    generate
        for(g=0;g<=T;g=g+1) begin : multipliers
            assign product[g]=gf_mul(mul_a[g],mul_b[g]);
        end
    endgenerate
    always @* begin
        for(op=0;op<=T;op=op+1) begin
            if(phase_q==0) begin
                mul_a[op]=lambda_q[op]; mul_b[op]=history_q[op];
            end else if(phase_q==1) begin
                mul_a[op]=lambda_q[op]; mul_b[op]=gamma_q;
            end else begin
                mul_a[op]=(op==0) ? {M{1'b0}} : aux_q[op-1];
                mul_b[op]=discrepancy_q;
            end
        end
    end

'''
src=src[:pos]+shared+src[pos:]
src=src.replace("phase_q <= 1'b0;", "phase_q <= 2'd0;")
src=src.replace("phase_q <= 1'b1;", "phase_q <= 2'd1;")
src=src.replace("busy_q && !phase_q", "busy_q && phase_q == 0")
src=src.replace('gf_mul(lambda_q[j], history_q[j])','product[j]')
src=src.replace('''            end else if (busy_q) begin
                for (j = 0; j <= T; j = j + 1) begin''','''            end else if (busy_q && phase_q == 1) begin
                for (j = 0; j <= T; j = j + 1)
                    scaled_q[j] <= product[j];
                phase_q <= 2'd2;
            end else if (busy_q) begin
                for (j = 0; j <= T; j = j + 1) begin''')
src=src.replace('gf_mul(gamma_q, lambda_q[j])','scaled_q[j]')
src=src.replace('gf_mul(discrepancy_q, aux_q[j-1])','product[j]')
src=src.replace("                lambda_q[j] <= '0;", "                lambda_q[j] <= '0;\n                scaled_q[j] <= '0;")
(OUT/'bch_bm_shared.sv').write_text(src)
for suffix,chien in [('shared','original'),('sharedchien','csechien')]:
    core=(ROOT/'rtl/bch/bch_dec.sv').read_text().replace('module bch_dec #(',f'module bch_dec_{suffix} #(').replace('bch_bm #(', 'bch_bm_shared #(')
    if chien != 'original':
        core=core.replace('bch_chien #(', f'bch_chien_{chien} #(')
    (OUT/f'bch_dec_{suffix}.sv').write_text(core)
    parent=(OUT/'pbch_dec_rec_cse.sv').read_text().replace('module pbch_dec_rec_cse #(',f'module pbch_dec_rec_{suffix} #(').replace('bch_dec #(',f'bch_dec_{suffix} #(')
    (OUT/f'pbch_dec_rec_{suffix}.sv').write_text(parent)
    wrapper=(OUT/'pbch_dec_cse.sv').read_text().replace('module pbch_dec_cse',f'module pbch_dec_{suffix}').replace('pbch_dec_rec_cse #(',f'pbch_dec_rec_{suffix} #(')
    (OUT/f'pbch_dec_{suffix}.sv').write_text(wrapper)
