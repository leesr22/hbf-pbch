#!/usr/bin/env python3
"""Monte Carlo exact-search cycle model for real PBCH labels and q=.002.

This estimates core latency, not end-to-end bandwidth: the frontend, context
credit, load and output schedule must still be simulated in the complete RTL.
"""
from pathlib import Path
import math
import json
import random
import sys
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from model.ecc import STUDY_PROFILES

def main():
    codec=STUDY_PROFILES['pbch_paper']
    labels=np.array(codec.influence_columns(),dtype=np.int16)
    rng=np.random.default_rng(20261114)
    samples=1024
    bit_rng=random.Random(20261114)
    base_words=[codec.parent.encode(bit_rng.getrandbits(codec.k)) for _ in range(samples)]
    per_count=[]
    q=.002; n=codec.n
    for count in range(33):
        # Actual code columns and valid encoded base words; flags are unique.
        selected=np.stack([rng.choice(n,size=count,replace=False) for _ in range(samples)])
        selected_labels=labels[selected]
        signs=np.array([[1-2*((base_words[s]>>(n-1-int(p)))&1) for p in selected[s]]
                        for s in range(samples)],dtype=np.int16)
        values=np.zeros((samples,8192),dtype=np.int16)
        np.add.at(values,(np.arange(samples)[:,None],selected_labels),signs)
        step=1
        while step<8192:
            v=values.reshape(samples,-1,step*2)
            a=v[:,:,:step].copy(); b=v[:,:,step:].copy()
            v[:,:,:step]=a+b;v[:,:,step:]=a-b;step*=2
        perfect=values==count
        found=perfect.any(axis=1)
        first=perfect.argmax(axis=1)
        item={'flags':count,'probability':math.comb(n,count)*q**count*(1-q)**(n-count),
              'full_mask_fraction':float(found.mean())}
        for high in (4,5,6,7):
            blocks=np.where(found,first//(1<<high)+1,1<<(13-high))
            for chunk in (4,8,16,32):
                cycles=blocks*max(1,math.ceil(count/chunk))+2
                item[f'h{high}c{chunk}_mean_search']=float(cycles.mean())
                item[f'h{high}c{chunk}_mean_service']=float((cycles+count+3).mean())
        per_count.append(item)
    weighted={}
    for high in (4,5,6,7):
        for chunk in (4,8,16,32):
            key=f'h{high}c{chunk}'
            weighted[key]={s:sum(x['probability']*x[f'{key}_mean_{s}'] for x in per_count)
                           for s in ('search','service')}
    out={'n':n,'q':q,'samples_per_count':samples,'assumptions':'Actual pbch_paper profile columns and random valid encoded words, uniformly sampled unique flagged positions; core-only analytic latency validated separately by RTL.',
         'weighted':weighted,'per_count':per_count}
    (ROOT/'optim/fwht/workload_estimate.json').write_text(json.dumps(out,indent=2)+'\n')
    print(json.dumps(weighted,indent=2))

if __name__=='__main__':main()
