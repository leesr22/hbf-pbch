#!/usr/bin/env python3
"""Collect only completed direct DC measurements, never architectural estimates."""
from pathlib import Path
import csv
import math
import re

OUT=Path(__file__).resolve().parent
rows=[]
for status in sorted((OUT/'runs').glob('*/status.txt')):
    variant=status.parent.name
    data=dict(line.strip().split('=',1) for line in status.read_text().splitlines() if '=' in line)
    area=float(data['area_um2']); slack=float(data['slack_ns'])
    ii=70;e2e=188 if variant.startswith('shared') else 172
    if variant.startswith('fair_t'):
        t=int(variant.split('fair_t')[1]);ii=73 if t==27 else 69;e2e=''
    elif variant.startswith('fair_compressed_t'):
        t=int(variant.split('fair_compressed_t')[1]);ii=73 if t==27 else 69;e2e=''
    throughput=512*.3/ii
    replicas=math.ceil(384/throughput)
    row=dict(variant=variant,area_um2=area,nand2_ge=area/.504,slack_ns=slack,ii_cycles=ii,e2e_cycles=e2e,
             throughput_GBps=throughput,replicas=replicas,total_nand2_ge=area/.504*replicas)
    report=(status.parent/'area.rpt').read_text()
    for label,path in [('bm','bm_lanes[0].bm_u'),('chien','chien_u'),('syndrome','syndrome_u')]:
        match=re.search(r'^core/bch_u/'+re.escape(path)+r'\s+([0-9.]+)',report,re.M)
        row[label+'_area_um2']=float(match[1]) if match else ''
    match=re.search(r'^core/unmask_u\s+([0-9.]+)',report,re.M)
    row['unmask_area_um2']=float(match[1]) if match else ''
    rows.append(row)
if rows:
    with (OUT/'results.csv').open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(rows[0]))
        writer.writeheader();writer.writerows(rows)
    for row in rows:
        print(f"{row['variant']:20s} GE={row['nand2_ge']:9.1f} slack={row['slack_ns']:+.4f} II={row['ii_cycles']} E2E={row['e2e_cycles']} total={row['total_nand2_ge']/1e6:.4f}M")
