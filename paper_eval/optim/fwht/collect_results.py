#!/usr/bin/env python3
"""Collect measured standalone core area, timing and VCS cycle distributions."""
from pathlib import Path
import csv
import json
import re
import statistics

ROOT=Path(__file__).resolve().parent

def quantile(data,q):
    data=sorted(data)
    return data[min(len(data)-1,int(q*len(data)))]

def main():
    workload=json.loads((ROOT/'workload_estimate.json').read_text())
    rows=[]
    for path in sorted((ROOT/'results').glob('*/area.rpt')):
        name=path.parent.name
        m=re.fullmatch(r'fwht_h(\d+)_c(\d+)_e(\d+)(?:_g(\d+))?(_f1)?(_m6)?(?:_hs(\d+))?(?:_d(\d+))?',name)
        if not m: continue
        high,chunk,early=map(int,m.group(1,2,3))
        group=int(m[4] or high);fuse=int(bool(m[5]));mod6=int(bool(m[6]));hist=int(m[7] or 0)
        pipe_count=(high+group-1)//group
        area=float(re.search(r'Total cell area:\s+([\d.]+)',path.read_text())[1])
        status=path.with_name('status.txt')
        if not status.exists():continue
        slack=float(re.search(r'slack_ns=([-\d.]+)',status.read_text())[1])
        row={'point':name,'high_l':high,'chunk':chunk,'early_exit':early,
             'fuse_input':fuse,'modular6':mod6,'histogram_style':hist,'direct_stages':int(m[8] or 0),'pipe_group':group,'area_um2':area,
             'nand2_ge':area/.504,'slack_ns_300mhz':slack,
             'sim_cases':0}
        log=path.with_name('simulation.log')
        if not log.exists():log=ROOT/'build'/name/'run.log'
        if log.exists():
            text=log.read_text()
            passed=re.search(r'PASS compact FWHT .* cases=(\d+)',text)
            if passed:row['sim_cases']=int(passed[1])
            values=[tuple(map(int,x)) for x in re.findall(
                r'case=(\d+) flags=(\d+) search_cycles=(\d+)',text)]
            # Cases136..903 are exactly256 random repetitions each of0/8/32.
            for flags in (0,8,32):
                data=[cy for c,f,cy in values if f==flags and 136<=c<904]
                if data:
                    for key,val in [('mean',statistics.mean(data)),('min',min(data)),
                                    ('p95',quantile(data,.95)),('max',max(data))]:
                        row[f'flag{flags}_search_{key}_cycles']=val
        if early:
            row['q002_mc_mean_core_search_cycles']=workload['weighted'][f'h{high}c{chunk}']['search']-fuse+pipe_count-1
            row['q002_mc_mean_core_service_cycles']=workload['weighted'][f'h{high}c{chunk}']['service']-fuse+pipe_count-1
        else:
            row['q002_mc_mean_core_search_cycles']=sum(
                x['probability']*((1<<(13-high))*max(1,(x['flags']+chunk-1)//chunk)+pipe_count+1-fuse)
                for x in workload['per_count'])
            row['q002_mc_mean_core_service_cycles']=row['q002_mc_mean_core_search_cycles']+4213*.002+3
        rows.append(row)
    fields=list(dict.fromkeys(key for row in rows for key in row))
    with (ROOT/'core_results.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(rows)
    print(json.dumps(rows,indent=2))

if __name__=='__main__':main()
