#!/usr/bin/env python3
"""Golden-vector RTL/mapped checks; preserves original study vector files."""
from pathlib import Path
import argparse
import json
import os
import random
import subprocess
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT))
from model.ecc import STUDY_PROFILES

p=argparse.ArgumentParser()
p.add_argument('mode',choices=('rtl','gate'))
p.add_argument('t',type=int,choices=(8,9,27))
p.add_argument('--suffix',default='')
a=p.parse_args()
codec=STUDY_PROFILES[{8:'bch_base',9:'bch_equal_r',27:'bch_paper'}[a.t]]
run=HERE/('run_t%d%s'%(a.t,a.suffix))
build=run/('pipeline_'+a.mode)
build.mkdir(parents=True,exist_ok=True)
vectors=build/'vectors'
vectors.mkdir(exist_ok=True)
rng=random.Random(20261114+a.t)
payloads=[0,(1<<4096)-1,1,1<<4095,int('a'*1024,16),int('5'*1024,16)]
payloads += [rng.getrandbits(4096) for _ in range(128-len(payloads))]
message_lines=[]
code_lines=[]
mask=(1<<512)-1
for message in payloads:
    beats=[(message>>(4096-512*(i+1)))&mask for i in range(8)]
    message_lines += ['%0128x'%v for v in beats]
    word=codec.encode(message)
    parity=(word&((1<<codec.r)-1))<<(512-codec.r)
    code_lines += ['%0128x'%v for v in beats+[parity]]
(vectors/'messages.mem').write_text('\n'.join(message_lines)+'\n')
(vectors/'codewords.mem').write_text('\n'.join(code_lines)+'\n')
env=os.environ.copy()
vcs=env.get('VCS_BIN','vcs')
binary=build/'simv'
cmd=[vcs,'+warn=noLNX_OS_VERUN','+warn=noLINX_KRNL','-full64','-sverilog',
     '-timescale=1ns/1ps','-LDFLAGS','-Wl,--no-as-needed',
     '+define+ENC_TOP=bch_encoder_cse_t%d'%a.t,'+define+R_BITS=%d'%codec.r,
     '-top','encoder_pipeline_tb','-o',str(binary),'-Mdir='+str(build/'csrc')]
if a.mode=='gate':
    netlist=run/'netlist.v'
    if not netlist.exists(): raise SystemExit('Missing mapped netlist: '+str(netlist))
    cmd += ['+define+VIRL_functiononly','+define+SNPS_SEQ_DELAY=0',
            '+define+SNPS_COMBO_DELAY=0','+define+SNPS_LAT_DELAY=0','+notimingcheck',
            env.get('HBF_ECC_CELL_MODEL','/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/verilog/3.0/um28nchslogl35hsl140f.v'),str(netlist)]
else:
    cmd += [str(HERE/('bch_remainder_cse_t%d.sv'%a.t)),
            str(HERE/('bch_encoder_cse_t%d.sv'%a.t))]
cmd += [str(HERE/'encoder_pipeline_tb.sv')]
def invoke(command,path):
    with path.open('w') as out:
        result=subprocess.run(command,cwd=build,env=env,stdout=out,stderr=subprocess.STDOUT)
    output=path.read_text()
    if result.returncode or 'Error:' in output or 'Fatal:' in output:
        print(output[-8000:]);raise SystemExit(result.returncode or 1)
    return output
invoke(cmd,build/'compile.log')
for stalled in (0,1):
    output=invoke([str(binary),'+VEC_DIR='+str(vectors),'+STALL=%d'%stalled],build/('run_stall%d.log'%stalled))
    if 'PASS mapped/golden' not in output: raise SystemExit(output)
    print(output)
(build/'summary.json').write_text(json.dumps(dict(mode=a.mode,t=a.t,frames_per_mode=128,
    total_codewords=256,no_stall_e2e_cycles=9,no_stall_ii_cycles=9,
    golden_model='model.ecc.BCH.encode',random_output_stalls_pass=True),indent=2)+'\n')
