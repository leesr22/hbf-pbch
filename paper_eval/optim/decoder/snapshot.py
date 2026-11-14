#!/usr/bin/env python3
"""Retain read-only provenance copies before a synthesis job starts."""
from pathlib import Path
import hashlib
import json
import shutil
import sys

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[1]
run=Path(sys.argv[2]).resolve() if len(sys.argv)>2 else OUT/'runs'/sys.argv[1]
destination=run/'source_snapshot'
if destination.exists():
    raise SystemExit(f'Refusing to overwrite existing provenance: {destination}')
files=list(OUT.glob('*.sv'))+list(OUT.glob('*.py'))+list(OUT.glob('*.tcl'))+list(OUT.glob('*.sh'))
files+=list((ROOT/'rtl/bch').glob('*.sv'))+list((ROOT/'rtl/pbch').glob('*.sv'))+list((ROOT/'rtl/common').glob('*.svh'))
manifest={}
for path in files:
    relative=path.relative_to(ROOT)
    target=destination/relative
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(path,target)
    manifest[str(relative)]=hashlib.sha256(path.read_bytes()).hexdigest()
(run/'source_sha256.json').write_text(json.dumps(manifest,indent=2)+'\n')
