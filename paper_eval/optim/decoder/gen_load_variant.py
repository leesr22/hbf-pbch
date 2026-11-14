#!/usr/bin/env python3
"""Exploit the already-corrected selector beat to preload mask recurrence."""
from pathlib import Path
import re

OUT=Path(__file__).resolve().parent
for base in ['direct','cse']:
    variant=base+'load'
    text=(OUT/f'pbch_unmask_rec_{base}.sv').read_text()
    text=text.replace(f'module pbch_unmask_rec_{base}',f'module pbch_unmask_rec_{variant}')
    text=text.replace('input wire clk, reset_n, start_i,','input wire clk, reset_n, start_i, load_i,')
    text=text.replace('    reg first_q;\n','')
    text=text.replace('wire [31:0] state_now = first_q ? initial_state : state_q;', 'wire [31:0] state_now = state_q;')
    text=re.sub(r'\(\(in_count_i > \d+\) & \((extended\[\d+\])\)\)',r'\1',text)
    text=text.replace("            first_q <= 1'b1;\n",'')
    text=text.replace("            first_q <= 1'b0;\n",'')
    text=text.replace("        end else if (in_valid_i && in_ready_o) begin", "        end else if (load_i) begin\n            state_q <= initial_state;\n        end else if (in_valid_i && in_ready_o) begin")
    (OUT/f'pbch_unmask_rec_{variant}.sv').write_text(text)
    parent=(OUT/f'pbch_dec_rec_{base}.sv').read_text()
    parent=parent.replace(f'pbch_dec_rec_{base}',f'pbch_dec_rec_{variant}').replace(f'pbch_unmask_rec_{base}',f'pbch_unmask_rec_{variant}')
    parent=parent.replace('.selector_i(selector_o), .in_bits_i(parent_bits),', '.selector_i(parent_bits[W-1 -: L]),\n        .load_i(expect_selector_q && parent_valid && parent_ready), .in_bits_i(parent_bits),')
    (OUT/f'pbch_dec_rec_{variant}.sv').write_text(parent)
    wrapper=(OUT/f'pbch_dec_{base}.sv').read_text().replace(f'pbch_dec_{base}',f'pbch_dec_{variant}').replace(f'pbch_dec_rec_{base}',f'pbch_dec_rec_{variant}')
    (OUT/f'pbch_dec_{variant}.sv').write_text(wrapper)
