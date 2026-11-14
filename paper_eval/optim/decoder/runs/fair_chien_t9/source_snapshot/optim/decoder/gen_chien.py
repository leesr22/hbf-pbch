#!/usr/bin/env python3
"""GF(2) CSE in fixed Chien evaluation matrices (shared BCH optimization)."""
from pathlib import Path
import collections
import heapq
import json
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from model.ecc import gf_mul, gf_pow


def cse(masks, inputs, prefix, outputs, max_depth=99):
    terms = [set(i for i in range(len(inputs)) if m>>i&1) for m in masks]
    names, depths = list(inputs), [0]*len(inputs)
    membership = [set() for _ in inputs]
    pairs = collections.Counter()
    for ri,term in enumerate(terms):
        ts = sorted(term)
        for a in ts:
            membership[a].add(ri)
        pairs.update((a,b) for ai,a in enumerate(ts) for b in ts[ai+1:])
    heap = [(-n,a,b) for (a,b),n in pairs.items() if n>1]
    heapq.heapify(heap)
    code=[]
    while heap:
        negcount,a,b=heapq.heappop(heap)
        if pairs.get((a,b),0) != -negcount:
            continue
        depth=max(depths[a],depths[b])+1
        if depth>max_depth:
            continue
        rows=membership[a] & membership[b]
        assert len(rows)==-negcount
        idx=len(names)
        name=f'{prefix}{idx-len(inputs)}'
        code.append(f'    wire {name} = {names[a]} ^ {names[b]};')
        names.append(name)
        depths.append(depth)
        membership.append(rows.copy())
        changes=collections.Counter()
        for ri in rows:
            term=terms[ri]
            for other in term:
                if other != a:
                    changes[tuple(sorted((a,other)))]-=1
                if other != b and other != a:
                    changes[tuple(sorted((b,other)))]-=1
            term.difference_update((a,b))
            for other in term:
                changes[(other,idx)]+=1
            term.add(idx)
        membership[a].difference_update(rows)
        membership[b].difference_update(rows)
        for pair,delta in changes.items():
            pairs[pair]+=delta
            n=pairs[pair]
            if n>1:
                heapq.heappush(heap,(-n,*pair))
    for term,output in zip(terms,outputs):
        expr=' ^ '.join(names[i] for i in sorted(term)) or "1'b0"
        code.append(f'    assign {output} = {expr};')
    stats={'inputs':len(inputs),'outputs':len(outputs),'common_nodes':len(names)-len(inputs),
           'residual_xors':sum(max(0,len(t)-1) for t in terms),
           'max_shared_depth':max(depths)}
    return '\n'.join(code),stats


def make_chien(t,n,k,partial_a,partial_b,suffix,depth):
    w=64;m=13
    inputs=[f'term_q[{j}][{b}]' for j in range(t+1) for b in range(m)]
    masks,outputs=[],[]
    for lane in range(w):
        factors=[gf_pow(2,j*lane) for j in range(t+1)]
        for ob in range(m):
            mask=0
            for j,factor in enumerate(factors):
                for ib in range(m):
                    if gf_mul(1<<ib,factor)>>ob&1:
                        mask|=1<<(j*m+ib)
            masks.append(mask)
            outputs.append(f'eval_matrix[{lane*m+ob}]')
    for count,dest in [(64,'term_full'),(partial_a,'term_partial_a'),(partial_b,'term_partial_b')]:
        for j in range(t+1):
            factor=gf_pow(2,j*count)
            for ob in range(m):
                mask=sum(1<<(j*m+ib) for ib in range(m) if gf_mul(1<<ib,factor)>>ob&1)
                masks.append(mask)
                outputs.append(f'{dest}[{j}][{ob}]')
    equations,stats=cse(masks,inputs,'c',outputs,depth)
    src=(ROOT/'rtl/bch/bch_chien.sv').read_text()
    src=src.replace('module bch_chien #(',f'module bch_chien_{suffix} #(')
    for name in ['term_full','term_partial_a','term_partial_b']:
        src=src.replace(f'reg [M-1:0] {name}',f'wire [M-1:0] {name}')
    begin=src.index('        for (coefficient = 0; coefficient <= T; coefficient = coefficient + 1) begin\n            term_full')
    end=src.index('        for (lane = 0;',begin)
    src=src[:begin]+src[end:]
    begin=src.index("            value = '0;",begin)
    end=src.index('            correction_work',begin)
    src=src[:begin]+"            value = eval_matrix[lane*M +: M];\n"+src[end:]
    pos=src.index('    always @* begin')
    src=src[:pos]+f'    wire [W*M-1:0] eval_matrix;\n{equations}\n\n'+src[pos:]
    (OUT/f'bch_chien_{suffix}.sv').write_text(src)
    return stats


def main():
    for suffix,depth in [('csechien',8),('csechien4',4)]:
        tic=time.monotonic()
        stats=make_chien(8,4213,4109,13,40,suffix,depth)
        core=(ROOT/'rtl/bch/bch_dec.sv').read_text().replace('module bch_dec #(',f'module bch_dec_{suffix} #(').replace('bch_chien #(',f'bch_chien_{suffix} #(')
        (OUT/f'bch_dec_{suffix}.sv').write_text(core)
        parent=(OUT/'pbch_dec_rec_cse.sv').read_text().replace('module pbch_dec_rec_cse #(',f'module pbch_dec_rec_{suffix} #(').replace('bch_dec #(',f'bch_dec_{suffix} #(')
        (OUT/f'pbch_dec_rec_{suffix}.sv').write_text(parent)
        wrapper=(OUT/'pbch_dec_cse.sv').read_text().replace('module pbch_dec_cse',f'module pbch_dec_{suffix}').replace('pbch_dec_rec_cse #(',f'pbch_dec_rec_{suffix} #(')
        (OUT/f'pbch_dec_{suffix}.sv').write_text(wrapper)
        (OUT/f'{suffix}.json').write_text(json.dumps(stats,indent=2)+'\n')
        print(suffix,stats,f'{time.monotonic()-tic:.2f}s',flush=True)


if __name__=='__main__':
    main()
