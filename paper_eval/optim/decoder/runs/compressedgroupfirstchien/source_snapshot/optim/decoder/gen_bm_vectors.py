#!/usr/bin/env python3
from pathlib import Path
import json
import random
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent/'vectors'
sys.path.insert(0,str(ROOT))
from model.ecc import gf_mul,gf_pow

for t in [8,9,27]:
    rng=random.Random(1337+t)
    words=[]
    for case in range(1000):
        syn=[0]*(2*t+1)
        if case<2*t+6:
            # Actual binary error vectors, including uncorrectable >t patterns.
            positions=rng.sample(range(4096+13*t),case)
            for i in range(1,2*t+1):
                for p in positions:
                    syn[i]^=gf_pow(2,i*p)
        else:
            # Every possible odd syndrome tuple is covered probabilistically;
            # even syndromes are exactly the Frobenius-conjugate values.
            for i in range(1,2*t+1):
                syn[i]=rng.randrange(8192) if i%2 else gf_mul(syn[i//2],syn[i//2])
        words.append(sum(x<<(13*i) for i,x in enumerate(syn[1:])))
    (OUT/f'bm_t{t}.mem').write_text(''.join(f'{x:0{(26*t+3)//4}x}\n' for x in words))
print('BM vectors: 1000 each t8,t9,t27, actualerrors0..2t+5 +random Frobenius-consistent sets')
