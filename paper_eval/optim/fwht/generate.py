#!/usr/bin/env python3
"""Generate reproducible standalone DSE wrappers and exhaustive-reference tests."""
from pathlib import Path
import random
import argparse
ROOT=Path(__file__).resolve().parent

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--high',type=int,default=5)
    ap.add_argument('--chunk',type=int,default=8)
    ap.add_argument('--early',type=int,default=1)
    ap.add_argument('--fuse',type=int,default=0)
    ap.add_argument('--mod6',type=int,default=0)
    ap.add_argument('--hist',type=int,default=0)
    ap.add_argument('--direct',type=int,default=0)
    ap.add_argument('--group',type=int,default=0)
    ap.add_argument('--skip-vectors',action='store_true')
    args=ap.parse_args()
    name=f'fwht_h{args.high}_c{args.chunk}_e{args.early}'+(f'_g{args.group}' if args.group else '')+('_f1' if args.fuse else '')+('_m6' if args.mod6 else '')+(f'_hs{args.hist}' if args.hist else '')+(f'_d{args.direct}' if args.direct else '')
    d=ROOT/'generated'; d.mkdir(exist_ok=True)
    (d/f'{name}.sv').write_text(f'''module {name} (
input wire clk,reset_n,start_i,
output wire start_ready_o,
input wire [12:0] label_i,
input wire base_is_zero_i,add_valid_i,
output wire add_ready_o,
input wire finish_i,
output wire [12:0] selector_o,
output wire signed [13:0] best_score_o,
output wire overflow_o,done_o,busy_o
);
selector_search_fwht_compact #(.HIGH_L({args.high}),.CHUNK({args.chunk}),.EARLY_EXIT({args.early}),.FUSE_INPUT({args.fuse}),.MODULAR6({args.mod6}),.HIST_STYLE({args.hist}),.DIRECT_STAGES({args.direct}),.PIPE_GROUP({args.group or args.high})) core(.*);
endmodule
''')
    if args.skip_vectors:
        case_count=len((d/'counts.hex').read_text().splitlines())
        tb=(ROOT/'tb.sv.in').read_text().replace('@TOP@',name).replace('@CASES@',str(case_count))
        (d/f'{name}_tb.sv').write_text(tb)
        print(name)
        return
    rng=random.Random(20261114)
    cases=[]
    # Every flag count, signed edge values, duplicate labels, ties, overflow.
    for count in range(34):
        for mode in range(4):
            labels=[rng.randrange(8192) for _ in range(count)]
            signs=[rng.randrange(2) for _ in range(count)]
            if mode==0: labels=[0]*count
            if mode==1: labels=[1<<(i%13) for i in range(count)]
            if mode==2: signs=[1]*count
            if mode==3: signs=[0]*count
            cases.append((labels,signs))
    for count in (0,8,32):
        for _ in range(256):
            cases.append(([rng.randrange(8192) for _ in range(count)],
                          [rng.randrange(2) for _ in range(count)]))
    for _ in range(96):
        count=rng.randrange(34)
        cases.append(([rng.randrange(32) for _ in range(count)],
                      [rng.randrange(2) for _ in range(count)]))
    # Replace two non-distribution cases with the last numerical selector:
    # independent basis constraints force 8191, including the +32 recovery.
    cases[-2]=([1<<i for i in range(13)],[0]*13)
    cases[-1]=([1<<(i%13) for i in range(32)],[0]*32)
    # Constant Walsh spectra exercise signed output extrema, including the
    # uncommon case where even the global maximum is -32.
    cases.extend([([0]*32,[0]*32),([0]*32,[1]*32)])
    fields={k:[] for k in ['counts','labels','positive','selectors','scores']}
    for labels,signs in cases:
        hist=[0]*8192
        for label,sign in zip(labels[:32],signs[:32]): hist[label]+=1 if sign else -1
        step=1
        while step<8192:
            for begin in range(0,8192,step*2):
                for j in range(begin,begin+step):
                    a,b=hist[j],hist[j+step]; hist[j]=a+b; hist[j+step]=a-b
            step*=2
        score=max(hist); selector=hist.index(score)
        fields['counts'].append(len(labels))
        fields['labels'].append(sum(v<<(13*i) for i,v in enumerate(labels)))
        fields['positive'].append(sum(v<<i for i,v in enumerate(signs)))
        fields['selectors'].append(selector); fields['scores'].append(score&0x7f)
    for key,values in fields.items():
        (d/f'{key}.hex').write_text(''.join(f'{v:x}\n' for v in values))
    tb=(ROOT/'tb.sv.in').read_text().replace('@TOP@',name).replace('@CASES@',str(len(cases)))
    (d/f'{name}_tb.sv').write_text(tb)
    print(name)

if __name__=='__main__': main()
