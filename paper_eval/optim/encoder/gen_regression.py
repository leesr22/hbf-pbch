#!/usr/bin/env python3
"""Reproducible exact-FWHT integration vectors and recycled-context testbench."""
from pathlib import Path
import argparse
import json
import random
import sys
import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0,str(ROOT))
from model.ecc import STUDY_PROFILES


def golden(codec, message, positions):
    base = codec.base_word(message)
    cols = codec.influence_columns()
    hist = np.zeros(1 << codec.l, dtype=np.int64)
    for p in positions:
        hist[cols[p]] += 1 if (base >> (codec.n-1-p)) & 1 == 0 else -1
    span = 1
    while span < len(hist):
        blocks = hist.reshape(-1,2*span)
        a,b = blocks[:,:span].copy(), blocks[:,span:].copy()
        blocks[:,:span],blocks[:,span:] = a+b,a-b
        span *= 2
    selector = int(np.argmax(hist))
    failures = (len(positions)-int(hist[selector]))//2
    return selector,failures


def vectors(name, flags, count, seed, special=False):
    codec = STUDY_PROFILES['pbch_paper']
    rng = random.Random(seed)
    dest = HERE/'vectors'/name
    dest.mkdir(parents=True,exist_ok=True)
    rows=[]
    for index in range(count):
        f = flags[index % len(flags)]
        message = rng.getrandbits(codec.k)
        if special and index % 5 == 0:
            # Exercise consecutive and selector/parity flags, not just random.
            positions = list(range(min(f,13)))
            positions += list(range(codec.n-(f-len(positions)),codec.n))
        else:
            positions = sorted(rng.sample(range(codec.n),f))
        selector,failures = golden(codec,message,positions[:32])
        if f<=32:
            # Independent direct candidate check and existing model cross-check.
            if index < 6:
                assert (selector,failures)==codec.fht_selector(message,positions)
            base=codec.encode(message,selector)
            assert sum((base>>(codec.n-1-p))&1 for p in positions)==failures
        rows.append(dict(message=message,probe=sum(1<<(codec.n-1-p) for p in positions),codeword=codec.encode(message,selector),selector=selector,failures=failures,flags=f))
    for field,width in [('message',4096),('probe',4213),('codeword',4213),('selector',13),('failures',16),('flags',16)]:
        (dest/f'{field}.hex').write_text(''.join(f'{r[field]:0{(width+3)//4}x}\n' for r in rows))
    (dest/'manifest.json').write_text(json.dumps(dict(seed=seed,count=count,flag_counts=flags,mean_flags=sum(r['flags'] for r in rows)/count),indent=2)+'\n')
    print(dest)


def bench():
    text=(ROOT/'tb/pbch_sparse_pipeline_enc_tb.sv').read_text()
    text=text.replace('    integer results_seen;', '''    integer in_flight;
    integer frame_for_context [0:7];
    integer flags [0:VECTORS-1];
    integer end_cycle [0:VECTORS-1];
    integer hold_cycles;
    integer hold_start;
    reg isolated, input_bubbles;
    integer results_seen;''')
    text=text.replace('if (message_context < VECTORS)', 'if (frame_for_context[message_context] >= 0 && frame_for_context[message_context] < VECTORS)')
    text=text.replace('messages[message_context][', 'messages[frame_for_context[message_context]][')
    text=text.replace('            wait (start_ready);', '''            if (index >= 8) wait (observed_done[index-8]);
            if (isolated && index > 0) wait (observed_done[index-1]);
            wait (start_ready);''')
    text=text.replace('            context_id = index[2:0];', '            context_id = index[2:0];\n            frame_for_context[index%8] = index;')
    text=text.replace('result_index = result_context;', 'result_index = frame_for_context[result_context];')
    text=text.replace('if (result_index >= `PBCH_PIPE_OVERFLOW_FROM)', 'if (flags[result_index] > 32)')
    text=text.replace('                $display("PASS result=', '                end_cycle[result_index] = cycle_count;\n                $display("PASS result=')
    text=text.replace('out_ready <= !random_backpressure ||\n                         (ready_lfsr[1:0] != 2\'b00);', '''out_ready <= !(cycle_count >= hold_start && cycle_count < hold_start+hold_cycles) &&
                         (!random_backpressure || ready_lfsr[1:0] != 2'b00);''')
    text=text.replace('        random_backpressure = $test$plusargs("RANDOM_BP");', '''        random_backpressure = $test$plusargs("RANDOM_BP");
        isolated = $test$plusargs("ISOLATED");
        input_bubbles = $test$plusargs("INPUT_BUBBLES");
        if (!$value$plusargs("HOLD_CYCLES=%d",hold_cycles)) hold_cycles=0;
        if (!$value$plusargs("HOLD_START=%d",hold_start)) hold_start=40;
        for (index=0;index<8;index=index+1) frame_for_context[index]=-1;
        $readmemh({vector_dir,"/flags.hex"},flags);''')
    text=text.replace('        for (index = 1; index < VECTORS; index = index + 1)', '''        for (index=0; index<VECTORS; index=index+1)
            $display("TIMING frame=%0d flags=%0d start=%0d end=%0d e2e=%0d",index,flags[index],start_cycle[index],end_cycle[index],end_cycle[index]-start_cycle[index]);
        for (index = 1; index < VECTORS; index = index + 1)''')
    text=text.replace('#2000000;', '#200000000;')
    text=text.replace("            start = 1'b1;\n            start_cycle[index] = cycle_count;", "            start = 1'b1;\n            do @(posedge clk); while (!start_ready);\n            start_cycle[index] = cycle_count;")
    text=text.replace("                data_bits = '0;", "                data_valid = 1'b0;\n                if (input_bubbles) repeat ((index*17+seen/64)%4) @(negedge clk);\n                data_bits = '0;")
    text=text.replace("                probe_bits = '0;", "                probe_valid = 1'b0;\n                if (input_bubbles) repeat ((index*13+seen/64)%3) @(negedge clk);\n                probe_bits = '0;")
    pos=text.index('    task send_data')
    text=text[:pos]+'''    // Optional interface audit: completion must never be indicated by a
    // transient low busy while a started codeword is still outstanding.
    reg stalled_previous;
    reg [W-1:0] stalled_bits;
    reg [COUNT_W-1:0] stalled_count;
    reg stalled_last;
    reg [2:0] stalled_context;
    always @(posedge clk) begin
        if (!reset_n) stalled_previous <= 0;
        else begin
            if (stalled_previous && (!out_valid || out_bits !== stalled_bits ||
                out_count !== stalled_count || out_last !== stalled_last ||
                result_context !== stalled_context))
                $fatal(1,"output changed while stalled");
            stalled_previous <= out_valid && !out_ready;
            stalled_bits <= out_bits;
            stalled_count <= out_count;
            stalled_last <= out_last;
            stalled_context <= result_context;
        end
    end
    always @(posedge clk) begin
        if (!reset_n) in_flight <= 0;
        else begin
            if ($test$plusargs("CHECK_BUSY") && in_flight > 0 && !busy)
                $fatal(1,"busy deasserted with %0d codewords outstanding",in_flight);
            case ({start && start_ready, out_valid && out_ready && out_last})
                2'b10: in_flight <= in_flight + 1;
                2'b01: in_flight <= in_flight - 1;
                default: in_flight <= in_flight;
            endcase
        end
    end

'''+text[pos:]
    (HERE/'regression_tb.sv').write_text(text)


if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--count',type=int,default=256)
    p.add_argument('--workload-count',type=int,default=2048)
    p.add_argument('--long-workload-count',type=int,default=0,
                   help='also generate the published q002_long workload (16384 frames)')
    p.add_argument('--vectors-only',action='store_true',
                   help='keep the checked-in regression testbench unchanged')
    a=p.parse_args()
    if not a.vectors_only:
        bench()
    vectors('random8',[8],a.count,20261114)
    vectors('mixed',list(range(34)),a.count,20261115,True)
    vectors('timing',[0,8,32],3,20261114)
    counts=np.random.default_rng(20261116).binomial(4213,.002,size=a.workload_count).tolist()
    vectors('q002',counts,a.workload_count,20261117)
    if a.long_workload_count:
        counts=np.random.default_rng(20261118).binomial(4213,.002,size=a.long_workload_count).tolist()
        vectors('q002_long',counts,a.long_workload_count,20261119)
    # Keep the previously reported flag-0/8/32 example words reproducible.
    source=ROOT/'vectors/study/pbch_paper_encoder'
    dest=HERE/'vectors/legacy_timing'
    dest.mkdir(parents=True,exist_ok=True)
    repeat=HERE/'vectors/repeated8'
    repeat.mkdir(parents=True,exist_ok=True)
    for field in ['message','probe','codeword','selector','failures']:
        lines=(source/f'{field}.hex').read_text().splitlines()
        (dest/f'{field}.hex').write_text('\n'.join(lines[i] for i in (0,2,3))+'\n')
        (repeat/f'{field}.hex').write_text((lines[2]+'\n')*128)
    (dest/'flags.hex').write_text('0000\n0008\n0020\n')
    (repeat/'flags.hex').write_text('0008\n'*128)
