#!/usr/bin/env python3
"""Read-only diagnostic simulation of the immutable cached-C32 mapped design."""
from pathlib import Path
import subprocess
import sys

here=Path(__file__).resolve().parent
root=here.parents[2]
run=root/'optim/encoder/runs/strict_piped_h7_c32_d5_crc128'
build=here/'build'
build.mkdir(exist_ok=True)
sources=['/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/verilog/3.0/um28nchslogl35hsl140f.v',str(run/'netlist.v')]
cmd=['vcs','+warn=noLNX_OS_VERUN','+warn=noLINX_KRNL','+vcs+lic+wait','-full64','-sverilog','-timescale=1ns/1ps','-LDFLAGS','-Wl,--no-as-needed',f'+incdir+{root}','+define+PBCH_PIPE_TOP=pbch_encoder_strict_piped_h7_c32_d5_crc128','+define+PBCH_PIPE_W=512','+define+PBCH_PIPE_L=13','+define+PBCH_PIPE_N=4213','+define+PBCH_PIPE_VECTORS=256','+define+PBCH_PIPE_OVERFLOW_FROM=4','-top','pbch_sparse_pipeline_enc_tb','-o',str(build/'simv'),'-Mdir='+str(build/'csrc'),'+define+VIRL_functiononly','+define+SNPS_SEQ_DELAY=0','+define+SNPS_COMBO_DELAY=0','+define+SNPS_LAT_DELAY=0','+notimingcheck']+sources+[str(here/'tb.sv')]
with (build/'compile.log').open('w') as log:
    result=subprocess.run(cmd,cwd=build,stdout=log,stderr=subprocess.STDOUT)
if result.returncode:
    print((build/'compile.log').read_text()[-4000:]);sys.exit(result.returncode)
cmd=[str(build/'simv'),'+vcs+lic+wait',f'+VEC_DIR={root}/optim/encoder/vectors/mixed','+RANDOM_BP','+HOLD_CYCLES=1500','+CHECK_BUSY','+INPUT_BUBBLES']
with (build/'run.log').open('w') as log:
    result=subprocess.run(cmd,cwd=build,stdout=log,stderr=subprocess.STDOUT)
output=(build/'run.log').read_text()
print(output)
# This VCS build returns zero even for $fatal; never mislabel that as success.
sys.exit(result.returncode or (1 if 'Fatal:' in output or 'Error:' in output else 0))
