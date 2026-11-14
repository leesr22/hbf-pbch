#!/usr/bin/env python3
"""Extract actual accepted-frame performance from VCS logs."""
from pathlib import Path
import argparse
import json
import math
import re
import statistics

p=argparse.ArgumentParser()
p.add_argument('logs',nargs='+')
p.add_argument('--warmup',type=int,default=16)
a=p.parse_args()
for filename in a.logs:
    text=Path(filename).read_text()
    assert 'PASS pbch_sparse_pipeline_enc vectors=' in text and 'Fatal:' not in text and 'Error:' not in text,filename
    rows=[tuple(map(int,m)) for m in re.findall(r'TIMING frame=(\d+) flags=(\d+) start=(\d+) end=(\d+) e2e=(\d+)',text)]
    if len(rows) <= a.warmup+1:
        print(json.dumps(dict(log=filename,frames=rows),indent=2)); continue
    use=rows[a.warmup:]
    ii=(use[-1][3]-use[0][3])/(len(use)-1)
    starts=(use[-1][2]-use[0][2])/(len(use)-1)
    latency=[r[4] for r in use]
    result=dict(log=filename,frames=len(rows),warmup=a.warmup,mean_flags=statistics.mean(r[1] for r in use),mean_output_interval=ii,mean_start_interval=starts,throughput_GBps=153.6/ii,replicas=math.ceil(ii/12-1e-12),mean_e2e=statistics.mean(latency),min_e2e=min(latency),max_e2e=max(latency))
    print(json.dumps(result,indent=2))
