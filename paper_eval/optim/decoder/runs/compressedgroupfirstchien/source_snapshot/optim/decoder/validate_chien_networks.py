#!/usr/bin/env python3
"""Symbolically prove every generated Chien XOR output equals its GF map."""
from pathlib import Path
import re
import sys
OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[1]
sys.path.insert(0,str(ROOT))
from model.ecc import gf_mul,gf_pow

def verify(suffix,t,partial_a,partial_b):
    names={f'term_q[{j}][{b}]':1<<(13*j+b) for j in range(t+1) for b in range(13)}
    names["1'b0"]=0
    results={}
    for line in (OUT/f'bch_chien_{suffix}.sv').read_text().splitlines():
        match=re.fullmatch(r'    wire (c\d+) = (.*);',line)
        output=re.fullmatch(r'    assign ((?:eval_matrix|term_full|term_partial_[ab])\[.*\]) = (.*);',line)
        match=match or output
        if not match: continue
        value=0
        for term in match[2].split(' ^ '): value^=names[term]
        if output: results[match[1]]=value
        else: names[match[1]]=value
    expected={}
    for lane in range(64):
        for ob in range(13):
            value=0
            for j in range(t+1):
                factor=gf_pow(2,j*lane)
                for ib in range(13):
                    if gf_mul(1<<ib,factor)>>ob&1: value|=1<<(13*j+ib)
            expected[f'eval_matrix[{13*lane+ob}]']=value
    for count,dest in [(64,'term_full'),(partial_a,'term_partial_a'),(partial_b,'term_partial_b')]:
        for j in range(t+1):
            factor=gf_pow(2,j*count)
            for ob in range(13):
                expected[f'{dest}[{j}][{ob}]']=sum(1<<(13*j+ib) for ib in range(13) if gf_mul(1<<ib,factor)>>ob&1)
    assert results==expected,(suffix,[k for k,v in expected.items() if results.get(k)!=v][:4])
    print(f'PASS exact symbolic GF(2) matrix {suffix}: {13*(t+1)} inputs, {len(results)} outputs',flush=True)

for suffix in ['csechien','csechien4']: verify(suffix,8,13,40)
for t in [8,9,27]: verify(f'fair_chien_t{t}',t,0,(13*t)%64)
