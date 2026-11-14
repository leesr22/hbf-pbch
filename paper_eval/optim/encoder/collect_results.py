#!/usr/bin/env python3
"""Collect actual mapped areas and independently measured encoder service rates.

Exploration points are not automatically recommendations: final source and
interface verification must be checked separately. Workload averages are not
worst-case bandwidth guarantees.
"""
from pathlib import Path
import csv
import json
import math
import re
import statistics

HERE=Path(__file__).resolve().parent


def timing(path, warmup=16):
    path=Path(path).resolve()
    text=path.read_text()
    if 'PASS pbch_sparse_pipeline_enc vectors=' not in text or 'Fatal:' in text or 'Error:' in text:
        return None
    rows=[tuple(map(int,m)) for m in re.findall(r'TIMING frame=(\d+) flags=(\d+) start=(\d+) end=(\d+) e2e=(\d+)',text)]
    if len(rows)<warmup+2:
        return dict(frames=len(rows),isolated=[dict(flags=r[1],e2e_cycles=r[4],e2e_ns=r[4]*10/3) for r in rows])
    rows=rows[warmup:]
    ii=(rows[-1][3]-rows[0][3])/(len(rows)-1)
    start_ii=(rows[-1][2]-rows[0][2])/(len(rows)-1)
    return dict(frames=len(rows)+warmup,mean_flags=statistics.mean(r[1] for r in rows),
                II_cycles=ii,start_II_cycles=start_ii,throughput_GBps=153.6/ii,
                replicas=math.ceil(ii/12-1e-12),mean_e2e_cycles=statistics.mean(r[4] for r in rows),
                max_e2e_cycles=max(r[4] for r in rows),source=str(path.relative_to(HERE.parents[1])))


def workload_log(run):
    checked=Path(run)/'sim_q002_long_checked/run.log'
    if checked.exists() and timing(checked): return checked
    return Path(run)/'sim_q002_long/run.log'


def collect():
    result=[]
    for status in sorted((HERE/'runs').glob('*/status.txt')):
        run=status.parent
        values=dict(line.split('=',1) for line in status.read_text().splitlines() if '=' in line)
        row=dict(variant=run.name,area_um2=float(values['area_um2']),NAND2_GE=float(values['nand2_ge']),
                 slack_ns=float(values['slack_ns']),timing_met=float(values['slack_ns'])>=0)
        cfg_path=run/'source_manifest.json'
        cfg=json.loads(cfg_path.read_text())['config'] if cfg_path.exists() else json.loads((HERE/f'{run.name}.json').read_text())
        row.update({key:cfg.get(key) for key in ('high','chunk','early','fuse','modular','crc_width','direct_load')})
        for workload in ('q002_long','q002','random8','repeated8','isolated'):
            path=workload_log(run) if workload=='q002_long' else run/f'sim_{workload}/run.log'
            if path.exists():
                measured=timing(path)
                if measured:
                    for key,value in measured.items():
                        if key!='isolated': row[f'{workload}_{key}']=value
                    if 'replicas' in measured: row[f'{workload}_total_GE']=row['NAND2_GE']*measured['replicas']
        result.append(row)
    fields=list(dict.fromkeys(key for row in result for key in row))
    with (HERE/'results.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=fields); writer.writeheader(); writer.writerows(result)
    (HERE/'results.json').write_text(json.dumps(result,indent=2)+'\n')
    for row in result:
        tag='q002_long' if f'q002_long_II_cycles' in row else 'q002'
        print(row['variant'],f"{row['NAND2_GE']:.1f} GE",f"slack {row['slack_ns']:+.4f}",
              f"II {row.get(tag+'_II_cycles','-')} replicas {row.get(tag+'_replicas','-')}")


if __name__=='__main__': collect()
