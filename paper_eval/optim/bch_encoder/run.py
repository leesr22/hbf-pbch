#!/usr/bin/env python3
"""Isolated synthesis and original-vector/basis regression for BCH CSE."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("action", choices=("syn", "sim"))
parser.add_argument("t", type=int, choices=(8, 9, 27))
parser.add_argument("--suffix", default="")
args = parser.parse_args()
profiles = {8: ("bch_base", 104), 9: ("bch_equal_r", 117), 27: ("bch_paper", 351)}
profile, r = profiles[args.t]
run = HERE / ("run_t%d%s" % (args.t, args.suffix))
run.mkdir(exist_ok=True)
env = os.environ.copy()
env["BCH_T"] = str(args.t)
env.setdefault("HBF_ECC_TARGET_LIBRARY", "/media/0/LogicLibraries/UMC/28nm/35hs/hsl/svt/latest/liberty/logic_synth/um28nchslogl35hsl140f_ssgwc0p9v125c.db")
env["BCH_RUN_DIR"] = str(run)
vcs = env.get("VCS_BIN", "vcs")
dc = env.get("DC_BIN", "dc_shell-xg-t")


def invoke(command, logfile):
    with logfile.open("w") as log:
        result = subprocess.run(command, cwd=run, env=env, stdout=log, stderr=subprocess.STDOUT)
    output = logfile.read_text()
    if result.returncode or "Fatal:" in output or "Error:" in output:
        print(output[-6000:])
        raise SystemExit(result.returncode or 1)
    return output


if args.action == "syn":
    if (run / "status.txt").exists():
        raise SystemExit("Refusing to overwrite completed synthesis: " + str(run))
    snapshot = run / "source_snapshot"
    snapshot.mkdir(exist_ok=True)
    evidence = {}
    for filename in ("bch_remainder_cse_t%d.sv" % args.t,
                     "bch_encoder_cse_t%d.sv" % args.t,
                     "bch_remainder_cse_t%d_tb.sv" % args.t,
                     "cse_t%d.json" % args.t, "synth.tcl", "gen_cse.py"):
        source_file = HERE / filename
        shutil.copy2(source_file, snapshot / filename)
        evidence[filename] = hashlib.sha256(source_file.read_bytes()).hexdigest()
    (run / "source_sha256.json").write_text(json.dumps(evidence, indent=2) + "\n")
    env["BCH_SRC_DIR"] = str(snapshot)
    invoke([dc, "-64bit", "-f", str(HERE / "synth.tcl")], run / "compile.log")
    print((run / "status.txt").read_text())
else:
    common = [vcs, "+warn=noLNX_OS_VERUN", "+warn=noLINX_KRNL", "-full64",
              "-sverilog", "-timescale=1ns/1ps", "-LDFLAGS", "-Wl,--no-as-needed"]
    source = HERE / ("bch_remainder_cse_t%d.sv" % args.t)
    for kind in ("basis", "vectors"):
        binary = run / ("simv_" + kind)
        if kind == "basis":
            top = "bch_remainder_cse_t%d_tb" % args.t
            files = [source, HERE / (top + ".sv")]
            defines, extra = [], []
            marker = "PASS BCH t="
        else:
            top = "study_bch_encoder_tb"
            files = [source, HERE / ("bch_encoder_cse_t%d.sv" % args.t),
                     ROOT / "tb/study_bch_encoder_tb.sv"]
            defines = ["+define+ENC_TOP=bch_encoder_cse_t%d" % args.t,
                       "+define+R_BITS=%d" % r, "+define+W_BITS=512"]
            extra = ["+VEC_DIR=" + str(ROOT / "vectors/study" / profile / "w512")]
            marker = "PASS BCH encoder"
        invoke(common + defines + ["-top", top, "-o", str(binary),
                                   "-Mdir=" + str(run / (kind + "_csrc"))] +
               list(map(str, files)), run / (kind + "_compile.log"))
        output = invoke([str(binary)] + extra, run / (kind + "_run.log"))
        print(output)
        if marker not in output:
            raise SystemExit("Expected PASS marker missing")
