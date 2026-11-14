#!/usr/bin/env python3
from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / 'vectors'
sys.path.insert(0, str(ROOT))
from model.ecc import STUDY_PROFILES

OUT.mkdir(exist_ok=True)
codec = STUDY_PROFILES['pbch_paper']
rng = random.Random(0xDEC13)
columns = codec.mask_columns()
(OUT/'columns.mem').write_text(''.join(f'{x:04x}\n' for x in columns))
messages, received, selectors, errors = [], [], [], []
counts = [13] + [64]*65 + [40]
assert sum(counts) == codec.n
for frame in range(144):
    selector = [0,8191]+[1<<i for i in range(13)]
    selector = selector[frame] if frame < len(selector) else rng.randrange(8192)
    message = rng.getrandbits(4096) if frame else 0
    word = codec.encode(message,selector)
    error_count = frame % 9
    positions = rng.sample(range(codec.n),error_count)
    if error_count and frame%2 == 0:
        positions[0] = codec.n-1-(frame%13)
        positions = sorted(set(positions))
        while len(positions)<error_count:
            p=rng.randrange(codec.n)
            if p not in positions:
                positions.append(p)
    for p in positions:
        word ^= 1<<p
    messages.extend((message >> (4096-64*(j+1))) & ((1<<64)-1) for j in range(64))
    seen=0
    for count in counts:
        seen += count
        received.append(((word>>(codec.n-seen)) & ((1<<count)-1)) << (64-count))
    selectors.append(selector)
    errors.append(error_count)
for name,data,digits in [('message',messages,16),('received',received,16),('selector',selectors,4),('errors',errors,1)]:
    (OUT/f'{name}.mem').write_text(''.join(f'{x:0{digits}x}\n' for x in data))
print('Generated 144 frames: errors0..8, 13-bit selector recovery, payloads.')
