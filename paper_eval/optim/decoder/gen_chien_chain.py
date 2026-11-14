#!/usr/bin/env python3
"""Exact blockwise Chien recurrence; skip unused final partial-beat feedback."""
from pathlib import Path

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[1]
for suffix,group in [('compressedtrim',0),('compressedchain4',4),('compressedchain8',8)]:
    name=f'bch_chien_{suffix}'
    src=(ROOT/'rtl/bch/bch_chien.sv').read_text().replace('module bch_chien #(',f'module {name} #(')
    src=src.replace('    reg [M-1:0] term_partial_b [0:T];\n','')
    src=src.replace('''            term_partial_b[coefficient] = gf_mul(
                term_q[coefficient], ADVANCE_PARTIAL_B[coefficient*M +: M]);\n''','')
    src=src.replace('''                    else
                        term_q[coefficient] <= term_partial_b[coefficient];''','''                    // The only other beat is the final parity fragment.
                    // Its next Chien state is never consumed by this frame.
                    else
                        term_q[coefficient] <= term_q[coefficient];''')
    if group:
        pos=src.index('    always @* begin')
        network=f'''    // Reuse the small alpha^j step between nearby parallel lanes.
    // Restart every {group} lanes to bound the combinational dependency depth.
    wire [M-1:0] lane_term [0:W-1][0:T];
    genvar gl,gc;
    generate for(gl=0;gl<W;gl=gl+1) begin: parallel_lanes
        for(gc=0;gc<=T;gc=gc+1) begin: coefficients
            if(gl%{group}==0) begin: seed
                assign lane_term[gl][gc]=gf_mul(term_q[gc],LANE_FACTOR[(gl*(T+1)+gc)*M +: M]);
            end else begin: recurrence
                assign lane_term[gl][gc]=gf_mul(lane_term[gl-1][gc],LANE_FACTOR[((T+1)+gc)*M +: M]);
            end
        end
    end endgenerate

'''
        src=src[:pos]+network+src[pos:]
        src=src.replace('''value = value ^ gf_mul(term_q[coefficient],
                    LANE_FACTOR[(lane*(T+1)+coefficient)*M +: M]);''','''value = value ^ lane_term[lane][coefficient];''')
        src=src.replace('''term_q[coefficient], ADVANCE_FULL[coefficient*M +: M]''','''lane_term[W-1][coefficient], LANE_FACTOR[((T+1)+coefficient)*M +: M]''')
        # Leading selector advancement can also reuse its last evaluation lane.
        if '.sv' in name: raise AssertionError(name)
    pos=src.index('endmodule')
    src=src[:pos]+'''`ifndef SYNTHESIS
    always @(posedge clk) begin
        if(reset_n && replay_valid_i && replay_ready_o &&
           replay_count_i!=W && replay_count_i!=PARTIAL_A &&
           seen_q+replay_count_i!=N)
            $fatal(1,"Partial-B beat must be the final parity fragment");
    end
`endif
'''+src[pos:]
    (OUT/f'{name}.sv').write_text(src)
    core=(OUT/'bch_dec_compressed.sv').read_text().replace('bch_dec_compressed',f'bch_dec_{suffix}').replace('bch_chien #(',f'{name} #(')
    (OUT/f'bch_dec_{suffix}.sv').write_text(core)
    parent=(OUT/'pbch_dec_rec_compressed.sv').read_text().replace('pbch_dec_rec_compressed',f'pbch_dec_rec_{suffix}').replace('bch_dec_compressed #(',f'bch_dec_{suffix} #(')
    (OUT/f'pbch_dec_rec_{suffix}.sv').write_text(parent)
    wrapper=(OUT/'pbch_dec_compressed.sv').read_text().replace('pbch_dec_compressed',f'pbch_dec_{suffix}').replace('pbch_dec_rec_compressed',f'pbch_dec_rec_{suffix}')
    (OUT/f'pbch_dec_{suffix}.sv').write_text(wrapper)
