#!/usr/bin/env python3
"""Build a traceable comparison from completed, measured synthesis reports.

Does not overwrite the prior paper-hardware tables. Encoder provisioning is
workload-conditioned; no process scaling or hypothetical clock is used.
"""
from pathlib import Path
import argparse
import csv
import hashlib
import importlib.util
import json
import math

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
spec=importlib.util.spec_from_file_location('encoder_results',HERE/'encoder/collect_results.py')
enc=importlib.util.module_from_spec(spec); spec.loader.exec_module(enc)


def read_csv(path):
    with path.open() as f: return list(csv.DictReader(f))


def encoder_row(name,label):
    run=HERE/'encoder/runs'/name
    status=dict(line.split('=',1) for line in (run/'status.txt').read_text().splitlines() if '=' in line)
    assert status['result']=='PASS'
    assert float(status['slack_ns'])>=0,name
    ge=float(status['nand2_ge'])
    performance=enc.timing(enc.workload_log(run))
    assert performance and performance['frames']==16384, name
    gates=[run/f'sim_{tag}/run.log' for tag in ('accepted_gate','gate')]
    assert any(path.exists() and enc.timing(path) for path in gates),f'{name}: missing mapped-netlist regression'
    isolated=enc.timing(run/'sim_isolated/run.log')
    latency=next(r['e2e_cycles'] for r in isolated['isolated'] if r['flags']==8)
    return dict(configuration=label,block='Encoder',W=512,NAND2_GE=ge,
                II_cycles=performance['II_cycles'],II_basis='16384 random payloads; independent flags q=0.002',
                throughput_GBps=performance['throughput_GBps'],replicas=performance['replicas'],
                total_NAND2_GE=ge*performance['replicas'],slack_ns=float(status['slack_ns']),
                E2E_cycles=latency,variant=name,evidence=str(run.relative_to(ROOT)))


def decoder_row(row,label,asap):
    assert float(row['slack_ns'])>=0
    variant=row['variant']
    candidates=[HERE/'decoder/build'/f'{variant}_gate'/'pipeline_stress_pass.log',
                HERE/'decoder/build'/f'{variant}_gate_pipeline_stress'/'run.log',
                HERE/'decoder/build'/f'{variant}_gate_functional'/'run.log']
    checked=[]
    for path in candidates:
        if path.exists():
            log=path.read_text()
            if 'PASS' in log and 'Fatal:' not in log and 'Error:' not in log and 'ERROR' not in log:
                checked.append(path)
    assert checked,f'{variant}: missing completed mapped-netlist validation'
    measured=asap[variant]
    assert measured['mapped_status'].startswith('PASS'),variant
    assert abs(float(row['nand2_ge'])-float(measured['nand2_ge']))<.001,variant
    return dict(configuration=label,block='Decoder',W=64,NAND2_GE=float(row['nand2_ge']),
                II_cycles=float(measured['ii_cycles']),II_basis='ASAP input: first beat at START+1; mapped/RTL matching 25-frame sequence',
                throughput_GBps=float(measured['throughput_GBps']),replicas=int(measured['replicas']),
                total_NAND2_GE=float(measured['total_nand2_ge']),slack_ns=float(row['slack_ns']),
                E2E_cycles=float(measured['e2e_cycles']),variant=row['variant'],
                evidence=f"optim/decoder/runs/{row['variant']}")


def baseline_row(row,label=None):
    latency=row.get('E2E_cycles')
    if latency is None and row['block']=='Encoder' and row['configuration'].startswith('BCH'):
        latency=9  # Rechecked by each mapped/golden BCH encoder regression.
    return dict(configuration=label or row['configuration'],block=row['block'],
                W=512 if row['block']=='Encoder' else 64,NAND2_GE=float(row['NAND2_GE_per_engine']),
                II_cycles=float(row['II_cycles']),II_basis='prior published measurement',
                throughput_GBps=float(row['throughput_GBps']),replicas=int(row['replicas']),
                total_NAND2_GE=float(row['NAND2_GE_per_engine'])*int(row['replicas']),
                slack_ns=float(row['slack_ns']),E2E_cycles=float(latency) if latency is not None else None,
                variant=row['synthesis_run'],evidence='results/paper_hardware/blocks_300mhz_common_width.csv')


def fair_encoder_row(original,t,label):
    """Keep the faster/smaller measured option; never assume XOR counts are gates."""
    result=baseline_row(original,label)
    for suffix in ('','_verified'):
        run=HERE/'bch_encoder'/f'run_t{t}{suffix}'
        checks=[run/'status.txt',run/'netlist.v',run/'pipeline_gate/summary.json',
                run/'pipeline_gate/run_stall0.log',run/'pipeline_gate/run_stall1.log']
        if not all(path.exists() for path in checks): continue
        gate=json.loads(checks[2].read_text())
        if not (gate['no_stall_e2e_cycles']==9 and gate['no_stall_ii_cycles']==9 and gate['random_output_stalls_pass']): continue
        if any('PASS mapped/golden BCH' not in path.read_text() or 'ERROR' in path.read_text() or 'Fatal:' in path.read_text() for path in checks[3:]): continue
        status=dict(line.split('=',1) for line in (run/'status.txt').read_text().splitlines() if '=' in line)
        ge=float(status['area_um2'])/0.504
        if float(status['slack_ns'])>=0 and ge<result['NAND2_GE']:
            result.update(NAND2_GE=ge,total_NAND2_GE=ge,slack_ns=float(status['slack_ns']),
                          variant=f'bch_encoder_cse_t{t}',evidence=str(run.relative_to(ROOT)),
                          II_basis='unchanged BCH controller; mapped/golden tests verify II9 and E2E9')
    return result


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--strict',default='strict_piped_h7_c16_d5_crc128')
    p.add_argument('--early',default='final_h5_c16_crc256')
    p.add_argument('--decoder',default='compressedgroupfirstchien')
    p.add_argument('--fast-decoder',default='compressedfirstchien')
    p.add_argument('--from-csv',action='store_true',help='render published CSV without EDA tools or private netlists')
    a=p.parse_args()
    if a.from_csv:
        dest=HERE/'results'
        rows=read_csv(dest/'hardware_comparison.csv')
        for row in rows:
            for key in ('NAND2_GE','II_cycles','E2E_cycles','throughput_GBps','total_NAND2_GE','slack_ns'):
                row[key]=float(row[key])
            for key in ('W','replicas'): row[key]=int(row[key])
        totals=json.loads((dest/'summary.json').read_text())['total_GE']
        plot(rows,totals,dest)
        print('Rendered the published comparison CSV without EDA tools.')
        return
    baseline=read_csv(ROOT/'results/paper_hardware/blocks_300mhz_common_width.csv')
    decoders=read_csv(HERE/'decoder/results.csv')
    asap={r['variant']:r for r in read_csv(HERE/'decoder/zero_bubble_results.csv')}
    by_name={r['variant']:r for r in decoders}
    rows=[]
    for t in (8,9,27):
        label=f'BCH(t={t}), common-optimized'
        rows.append(fair_encoder_row(next(r for r in baseline if r['configuration']==f'BCH(t={t})' and r['block']=='Encoder'),t,label))
        # Broad ablations use the historical common driver. Only candidates
        # additionally verified with the corrected ASAP driver enter this
        # final table; never combine an old interval with a new replica count.
        candidates=[r for r in decoders if r['variant'].startswith('fair_') and r['variant'].endswith(f'_t{t}') and float(r['slack_ns'])>=0 and r['variant'] in asap]
        assert candidates,f'No ASAP-verified fair BCH t={t} result'
        chosen=min(candidates,key=lambda r:float(asap[r['variant']]['total_nand2_ge']))
        rows.append(decoder_row(chosen,label,asap))
    for r in baseline:
        if not r['configuration'].startswith('PBCH'): continue
        original=baseline_row(r,'PBCH(t=8,l=13), original')
        if r['block']=='Encoder':
            # Remeasure the unchanged RTL under the exact same new testbench and
            # workload. Prior figures rounded II to 75 and used another driver.
            run=HERE/'encoder/runs/reference'
            perf=enc.timing(enc.workload_log(run))
            isolated=enc.timing(run/'sim_isolated/run.log')
            latency=next(v['e2e_cycles'] for v in isolated['isolated'] if v['flags']==8)
            original.update(II_cycles=perf['II_cycles'],II_basis='same 16384-frame workload as optimized encoders',
                            throughput_GBps=perf['throughput_GBps'],replicas=perf['replicas'],
                            E2E_cycles=latency,total_NAND2_GE=original['NAND2_GE']*perf['replicas'])
        else:
            measured=asap['original']
            original.update(II_cycles=float(measured['ii_cycles']),
                            II_basis='unchanged RTL, ASAP input with first beat at START+1',
                            throughput_GBps=float(measured['throughput_GBps']),replicas=int(measured['replicas']),
                            E2E_cycles=float(measured['e2e_cycles']),
                            total_NAND2_GE=original['NAND2_GE']*int(measured['replicas']))
        rows.append(original)
    for encoder_name,label in ((a.strict,'PBCH, full exhaustive FWHT'),(a.early,'PBCH, exact early stop')):
        rows.append(encoder_row(encoder_name,label))
        rows.append(decoder_row(by_name[a.decoder],label,asap))
    label='PBCH, full FWHT / original decoder latency'
    rows.append(encoder_row(a.strict,label))
    rows.append(decoder_row(by_name[a.fast_decoder],label,asap))
    dest=HERE/'results';dest.mkdir(exist_ok=True)
    with (dest/'hardware_comparison.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    totals={}
    for row in rows: totals[row['configuration']]=totals.get(row['configuration'],0)+row['total_NAND2_GE']
    bch9=totals['BCH(t=9), common-optimized']
    summary=dict(frequency_MHz=300,encoder_target_GBps=12.8,decoder_target_GBps=384,
                 selected=dict(strict_encoder=a.strict,early_encoder=a.early,decoder=a.decoder,unchanged_latency_decoder=a.fast_decoder),
                 total_GE=totals,relative_to_fair_BCH_t9={k:v/bch9 for k,v in totals.items()})
    (dest/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    alternatives=[]
    for direct in (0,2,3,5):
        name=f'strict_piped_h7_c16'+(f'_d{direct}' if direct else '')+'_crc128'
        row=encoder_row(name,f'Full FWHT, folded inner stages={direct}')
        row.update(folded_inner_stages=direct,butterfly_inner_stages=7-direct,
                   complete_ECC_GE=row['total_NAND2_GE']+float(asap[a.decoder]['total_nand2_ge']))
        row['complete_ECC_relative_to_BCH_t9']=row['complete_ECC_GE']/bch9
        alternatives.append(row)
    with (dest/'full_fwht_alternatives.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(alternatives[0]));writer.writeheader();writer.writerows(alternatives)
    evidence={}
    for row in rows+alternatives:
        variant=row['variant']
        if variant in evidence: continue
        directory=ROOT/row['evidence']
        if not directory.is_dir(): continue
        files={}
        for name in ('status.txt','area.rpt','timing.rpt','netlist.v','source_manifest.json','source_sha256.json'):
            path=directory/name
            if path.exists(): files[str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
        logs=list(directory.glob('sim_*/run.log'))+list(directory.glob('pipeline_gate/*.log'))
        logs+=list((HERE/'decoder/build').glob(f'{variant}_gate*/run.log'))
        logs+=list((HERE/'decoder/build').glob(f'{variant}_gate*/pipeline_stress_pass.log'))
        for path in sorted(set(logs)):
            files[str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
            for name in ('testbench_sha256.json','testbench_snapshot.sv'):
                bench=path.parent/name
                if bench.exists(): files[str(bench.relative_to(ROOT))]=hashlib.sha256(bench.read_bytes()).hexdigest()
        evidence[variant]=files
    (dest/'selected_evidence_sha256.json').write_text(json.dumps(evidence,indent=2)+'\n')
    plot(rows,totals,dest)
    print(json.dumps(summary,indent=2))


def plot(rows,totals,dest):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.patches import FancyBboxPatch
    colors=dict(ink='#1d2939',muted='#7f8ea3',line='#dce3ec',blue='#3077d7',gold='#f5bf2e')
    fig=plt.figure(figsize=(20,13.5),facecolor='white');ax=fig.add_axes([0,0,1,1]);ax.set_axis_off()
    ax.text(.035,.965,'ECC Hardware Optimization — 300 MHz',fontsize=25,color=colors['ink'],va='top')
    ax.text(.035,.925,'W=512 encoders / W=64 decoders   ·   Write target 12.8 GB/s   ·   Read target 384 GB/s',fontsize=13,color=colors['muted'])
    x=[.04,.265,.395,.505,.615,.725,.825,.935]
    headers=['Configuration','Circuit','Single-engine\nNAND2 GE','Codeword interval\n(cycles)','Isolated E2E\n(cycles)','Throughput\n(GB/s)','Replicas','Total\nNAND2 GE']
    top=.87; rowh=.046
    ax.add_patch(FancyBboxPatch((.025,top-.002),.95,.045,boxstyle='round,pad=0.006,rounding_size=0.006',fc='#e5e9ef',ec='none'))
    for i,h in enumerate(headers):ax.text(x[i],top+.02,h,ha='left' if i<2 else 'center',va='center',fontsize=11,color=colors['ink'])
    labels={'BCH(t=8), common-optimized':'BCH(t=8)\nCommon-optimized',
            'BCH(t=9), common-optimized':'BCH(t=9)\nCommon-optimized',
            'BCH(t=27), common-optimized':'BCH(t=27)\nCommon-optimized',
            'PBCH(t=8,l=13), original':'PBCH(t=8, l=13)\nOriginal',
            'PBCH, full exhaustive FWHT':'PBCH(t=8, l=13)\nFull exhaustive FWHT',
            'PBCH, exact early stop':'PBCH(t=8, l=13)\nExact early stop',
            'PBCH, full FWHT / original decoder latency':'PBCH: full FWHT\nOriginal decoder latency'}
    for idx,r in enumerate(rows):
        y=top-(idx+.5)*rowh-.006
        if (idx//2)%2==0:ax.add_patch(FancyBboxPatch((.026,y-rowh/2),.948,rowh,boxstyle='square,pad=0',fc='#f7f9fc',ec='none'))
        if idx%2==0:
            ax.text(x[0],y-rowh/2,labels[r['configuration']],va='center',fontsize=11,color=colors['ink'],linespacing=1.5)
            ax.plot([.026,.974],[y+rowh/2,y+rowh/2],color=colors['line'],lw=.9)
        color=colors['blue'] if r['block']=='Encoder' else colors['gold']
        ax.scatter([x[1]-.012],[y],s=28,color=color,zorder=3)
        ax.text(x[1],y+.006,r['block'],va='center',fontsize=11,color=colors['ink'])
        ax.text(x[1],y-.010,f"W={r['W']}",va='center',fontsize=8.5,color=colors['muted'])
        values=[f"{r['NAND2_GE']:,.0f}",f"{r['II_cycles']:.2f}" if r['block']=='Encoder' and r['configuration'].startswith('PBCH') else f"{r['II_cycles']:g}",f"{r['E2E_cycles']:g}",f"{r['throughput_GBps']:.3f}",str(r['replicas']),f"{r['total_NAND2_GE']/1e6:.3f} M" if r['total_NAND2_GE']>=1e6 else f"{r['total_NAND2_GE']:,.0f}"]
        for i,v in enumerate(values,2):
            ax.text(x[i],y+(.005 if i in (3,4) else 0),v,va='center',ha='center',fontsize=11,color=colors['ink'])
        for i,key in ((3,'II_cycles'),(4,'E2E_cycles')):
            ax.text(x[i],y-.011,f"{r[key]*10/3:.1f} ns",va='center',ha='center',fontsize=8,color=colors['muted'])
    bottom=top-len(rows)*rowh-.05
    notes=['All optimized entries use actual UMC 28 nm synthesis at 300 MHz; NAND2 GE = mapped cell area / 0.504 µm².',
           'PBCH encoder intervals are measured on 16,384 random-payload codewords, with independently flagged positions at q=0.002.',
           'Exact early stop preserves the exhaustive optimum, but its latency depends on payload and flag positions. Full FWHT evaluates all 8,192 selectors.',
           'E2E is measured from accepted START to the last output beat; optimized PBCH encoders use the same isolated 8-flag reference word.',
           'Common optimizations also apply to BCH. Decoder input starts at START+1; BCH t=8 alternates 68/69-cycle intervals (mean 68.5).',
           'External W=512 is retained; internal CRC work is time-shared at 128 bits (full FWHT) or 256 bits (early stop).',
           'External write/replay buffers are excluded, matching the original accounting. Replica counts are workload-conditioned, not worst-case guarantees.']
    for i,note in enumerate(notes):ax.text(.035,bottom-.019*i,note,fontsize=9.1,color=colors['muted'])
    ax.set_xlim(0,1);ax.set_ylim(0,1)
    for suffix in ('png','svg'):fig.savefig(dest/f'hardware_comparison.{suffix}',dpi=180,facecolor='white')
    plt.close(fig)


if __name__=='__main__':main()
