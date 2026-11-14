#!/usr/bin/env python3
"""Compare outputs with the original while replay waits for the slower core."""
from pathlib import Path
OUT=Path(__file__).resolve().parent
src=(OUT/'decoder_equiv_tb.sv').read_text().replace('decoder_equiv_tb','decoder_functional_equiv_tb')
start=src.index('    pbch_paper_dec_replay_w64 reference_u')
tail=src[start:].replace('.replay_valid_i(replay_valid)', '.replay_valid_i(replay_valid && replay_ready)')
src=src[:start]+tail
src=src.replace('''            if({start_ready,code_ready,replay_req,replay_ready,info_valid,done,success,busy} !==
               {reference_start_ready,reference_code_ready,reference_replay_req,reference_replay_ready,reference_info_valid,reference_done,reference_success,reference_busy})''','''            if((start && start_ready && !reference_start_ready) ||
               (code_valid && code_ready && !reference_code_ready) ||
               (replay_valid && replay_ready && !reference_replay_ready) ||
               (info_valid && info_ready)!==(reference_info_valid && info_ready) ||
               done!==reference_done || (done && success!==reference_success))''')
src=src.replace('if(info_valid && ({info_bits', 'if(info_valid && info_ready && ({info_bits')
src=src.replace('PASS cycle-equivalence','PASS replay-aligned functional-equivalence')
src=src.replace('payload/status/control/backpressure','payload/status/backpressure (reference waits for slower BM)')
(OUT/'decoder_functional_equiv_tb.sv').write_text(src)
