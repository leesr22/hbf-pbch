#!/usr/bin/env python3
"""Full cycle-level reference comparison also covers uncorrectable words."""
from pathlib import Path
import random
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
from model.ecc import STUDY_PROFILES

codec=STUDY_PROFILES['pbch_paper']
rng=random.Random(14359)
rows=[]
for frame in range(144):
    word=codec.encode(rng.getrandbits(4096),rng.randrange(8192))
    if frame<100:
        for pos in rng.sample(range(codec.n),frame%65): word^=1<<pos
    else:
        word=rng.getrandbits(codec.n)
    seen=0
    for count in [13]+[64]*65+[40]:
        seen+=count
        rows.append(((word>>(codec.n-seen))&((1<<count)-1))<<(64-count))
(OUT/'vectors/received_invalid.mem').write_text(''.join(f'{x:016x}\n' for x in rows))
text=(OUT/'decoder_tb.sv').read_text().replace('module decoder_tb;', 'module decoder_equiv_tb;')
pos=text.index('    always @(posedge clk) begin')
ref='''    wire reference_start_ready,reference_code_ready,reference_replay_req,reference_replay_ready;
    wire [63:0] reference_info_bits;
    wire [6:0] reference_info_count;
    wire reference_info_valid,reference_done,reference_success,reference_busy;
    wire [12:0] reference_selector;
    wire [3:0] reference_error_count;
    pbch_paper_dec_replay_w64 reference_u(.clk(clk),.reset_n(reset_n),.start_i(start),.start_ready_o(reference_start_ready),
       .code_bits_i(code_bits),.code_count_i(code_count),.code_valid_i(code_valid),.code_ready_o(reference_code_ready),
       .replay_req_o(reference_replay_req),.replay_bits_i(replay_bits),.replay_count_i(replay_count),.replay_valid_i(replay_valid),.replay_ready_o(reference_replay_ready),
       .info_bits_o(reference_info_bits),.info_count_o(reference_info_count),.info_valid_o(reference_info_valid),.info_ready_i(info_ready),.selector_o(reference_selector),
       .done_o(reference_done),.success_o(reference_success),.error_count_o(reference_error_count),.busy_o(reference_busy));
    always @(posedge clk) begin
        if(reset_n) begin
            if({start_ready,code_ready,replay_req,replay_ready,info_valid,done,success,busy} !==
               {reference_start_ready,reference_code_ready,reference_replay_req,reference_replay_ready,reference_info_valid,reference_done,reference_success,reference_busy})
                $fatal(1,"control/status inequivalence frame=%0d cycle=%0d",frame,cycle);
            if(info_valid && ({info_bits,info_count,selector} !== {reference_info_bits,reference_info_count,reference_selector}))
                $fatal(1,"payload/selector inequivalence frame=%0d cycle=%0d",frame,cycle);
            if(done && error_count!==reference_error_count) $fatal(1,"error count inequivalence");
        end
    end
'''
text=text[:pos]+ref+text[pos:]
text=text.replace('''            if(info_count!==64 || info_bits!==message_mem[frame*64+outputs]) $fatal(1,"payload frame=%0d beat=%0d",frame,outputs);
            if(selector!==selector_mem[frame]) $fatal(1,"selector frame=%0d expected=%h got=%h",frame,selector_mem[frame],selector);
''','')
text=text.replace('/received.mem','/received_invalid.mem')
text=text.replace('''            if(!success || error_count!==errors_mem[frame] || outputs!=64) $fatal(1,"status frame=%0d errors=%0d expected=%0d outputs=%0d",frame,error_count,errors_mem[frame],outputs);
''','')
text=text.replace('PASS decoder frames=%0d random selectors errors0..8 input bubbles/output backpressure','PASS cycle-equivalence frames=%0d errors0..64 andrandominvalidwords, payload/status/control/backpressure')
(OUT/'decoder_equiv_tb.sv').write_text(text)
