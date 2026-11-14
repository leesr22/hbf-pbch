#!/usr/bin/env python3
"""Run an isolated optimization synthesis or RTL simulation."""
from pathlib import Path
import argparse
import json
import os
import subprocess
import hashlib
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
p = argparse.ArgumentParser()
p.add_argument('action', choices=['syn','sim'])
p.add_argument('name')
p.add_argument('--vectors',type=int,default=6)
p.add_argument('--overflow-from',type=int,default=4)
p.add_argument('--vec-dir',default=str(ROOT/'vectors/study/pbch_paper_encoder'))
p.add_argument('--bp',action='store_true')
p.add_argument('--tag',default='')
p.add_argument('--regression',action='store_true')
p.add_argument('--isolated',action='store_true')
p.add_argument('--hold',type=int,default=0)
p.add_argument('--check-busy',action='store_true')
p.add_argument('--input-bubbles',action='store_true')
p.add_argument('--snapshot',action='store_true',help='simulate the immutable synthesis source snapshot')
p.add_argument('--gate',action='store_true',help='functional mapped-netlist simulation with UMC cells, no SDF')
p.add_argument('--run-root',type=Path,default=HERE/'runs',
               help='separate output root for reruns; archived synthesis is never overwritten')
a = p.parse_args()
cfg = json.loads((HERE/f'{a.name}.json').read_text())

def checkout_source(source):
    """Rebase historical source paths without modifying provenance manifests."""
    path = Path(source)
    if '/paper_eval/' in str(path):
        return ROOT / str(path).split('/paper_eval/', 1)[1]
    return path if path.is_absolute() else ROOT / path

run = a.run_root.resolve()/a.name
run.mkdir(parents=True,exist_ok=True)
env = os.environ.copy()
if a.action == 'syn':
    if (run/'status.txt').exists() or (run/'source_manifest.json').exists():
        raise SystemExit('Refusing to overwrite synthesis evidence; choose a new --run-root: '+str(run))
    env.update(ENC_OPT_ROOT=str(ROOT),ENC_OPT_NAME=a.name,ENC_OPT_RUN_DIR=str(run))
    env.setdefault('HBF_ECC_TARGET_LIBRARY','/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/liberty/logic_synth/um28nchslogl35hsl140f_ssgwc0p9v125c.db')
    work = run/'work'
    work.mkdir(exist_ok=True)
    snapshot = run/'sources'
    snapshot.mkdir(exist_ok=True)
    manifest = dict(config=cfg, files={})
    source_paths=[]
    for source in cfg['sources']:
        path=checkout_source(source)
        target=snapshot/path.name
        shutil.copy2(path,target)
        source_paths.append(target)
        manifest['files'][source]=hashlib.sha256(target.read_bytes()).hexdigest()
    (run/'sources.tcl').write_text('set sources [list '+ ' '.join('{'+str(s)+'}' for s in source_paths)+']\n')
    (run/'source_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    with (run/'compile.log').open('w') as log:
        r = subprocess.run([env.get('DC_BIN','dc_shell-xg-t'),'-64bit','-f',str(HERE/'synth.tcl')],cwd=work,env=env,stdout=log,stderr=subprocess.STDOUT)
    if r.returncode or not (run/'status.txt').exists():
        print((run/'compile.log').read_text()[-5000:])
        raise SystemExit(r.returncode or 1)
    print((run/'status.txt').read_text())
else:
    build = run/('sim'+('_'+a.tag if a.tag else ''))
    build.mkdir(exist_ok=True)
    binary = build/'simv'
    bench = HERE/'regression_tb.sv' if a.regression else ROOT/'tb/pbch_sparse_pipeline_enc_tb.sv'
    bench_snapshot=build/'testbench_snapshot.sv'
    shutil.copy2(bench,bench_snapshot)
    (build/'testbench_sha256.json').write_text(json.dumps({str(bench):hashlib.sha256(bench_snapshot.read_bytes()).hexdigest()},indent=2)+'\n')
    bench=bench_snapshot
    sources=list(map(str,map(checkout_source,cfg['sources'])))
    if a.snapshot:
        manifest=json.loads((run/'source_manifest.json').read_text())
        sources=[str(run/'sources'/Path(s).name) for s in manifest['config']['sources']]
        for original,expected in manifest['files'].items():
            assert hashlib.sha256((run/'sources'/Path(original).name).read_bytes()).hexdigest()==expected
    extra=[]
    if a.gate:
        sources=[env.get('HBF_ECC_CELL_MODEL','/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/verilog/3.0/um28nchslogl35hsl140f.v'),str(run/'netlist.v')]
        extra=['+define+VIRL_functiononly','+define+SNPS_SEQ_DELAY=0','+define+SNPS_COMBO_DELAY=0','+define+SNPS_LAT_DELAY=0','+notimingcheck']
    cmd = ['vcs','+warn=noLNX_OS_VERUN','+warn=noLINX_KRNL','+vcs+lic+wait','-full64','-sverilog','-timescale=1ns/1ps','-LDFLAGS','-Wl,--no-as-needed',f'+incdir+{ROOT}',f'+define+PBCH_PIPE_TOP={cfg["top"]}','+define+PBCH_PIPE_W=512','+define+PBCH_PIPE_L=13','+define+PBCH_PIPE_N=4213',f'+define+PBCH_PIPE_VECTORS={a.vectors}',f'+define+PBCH_PIPE_OVERFLOW_FROM={a.overflow_from}','-top','pbch_sparse_pipeline_enc_tb','-o',str(binary),'-Mdir='+str(build/'csrc')]+extra+sources+[str(bench)]
    cmd[0] = env.get('VCS_BIN', 'vcs')
    with (build/'compile.log').open('w') as log:
        r = subprocess.run(cmd,cwd=build,env=env,stdout=log,stderr=subprocess.STDOUT)
    if r.returncode:
        print((build/'compile.log').read_text()[-5000:]); raise SystemExit(r.returncode)
    cmd = [str(binary),'+vcs+lic+wait',f'+VEC_DIR={Path(a.vec_dir).resolve()}'] + (['+RANDOM_BP'] if a.bp else [])
    if a.isolated: cmd.append('+ISOLATED')
    if a.hold: cmd.append(f'+HOLD_CYCLES={a.hold}')
    if a.check_busy: cmd.append('+CHECK_BUSY')
    if a.input_bubbles: cmd.append('+INPUT_BUBBLES')
    with (build/'run.log').open('w') as log:
        r = subprocess.run(cmd,cwd=build,env=env,stdout=log,stderr=subprocess.STDOUT)
    output = (build/'run.log').read_text()
    if len(output)>8000:
        print(f'Full simulation output: {build/"run.log"}\n'+output[-8000:])
    else:
        print(output)
    if r.returncode or 'Fatal:' in output or 'Error:' in output or 'PASS pbch_sparse_pipeline_enc vectors=' not in output:
        raise SystemExit(r.returncode or 1)
