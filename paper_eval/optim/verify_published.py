#!/usr/bin/env python3
"""Audit published arithmetic and retained evidence without licensed EDA tools.

This checks recorded evidence, not a fresh RTL or physical timing signoff.
Private mapped netlists and omitted compiler/work products stay on the server.
"""
from pathlib import Path
import csv
import hashlib
import json
import math

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def read_rows(path):
    with path.open() as stream:
        return list(csv.DictReader(stream))


def check_hash(path, expected):
    assert path.is_file(), f'Missing retained source: {path}'
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, path


rows = read_rows(HERE / 'results/hardware_comparison.csv')
alternatives = read_rows(HERE / 'results/full_fwht_alternatives.csv')
summary = json.loads((HERE / 'results/summary.json').read_text())
totals = {}
directories = set()
source_count = 0
for row in rows + alternatives:
    interval = float(row['II_cycles'])
    throughput = 153.6 / interval
    target = 12.8 if row['block'] == 'Encoder' else 384
    replicas = math.ceil(target / throughput - 1e-12)
    # Original BCH encoder entries retain six-decimal CSV formatting.
    assert math.isclose(throughput, float(row['throughput_GBps']), abs_tol=5e-7)
    assert replicas == int(row['replicas']), row
    assert math.isclose(float(row['NAND2_GE']) * replicas,
                        float(row['total_NAND2_GE']), rel_tol=1e-9), row
    assert float(row['slack_ns']) >= 0, row
    directory = ROOT / row['evidence']
    if not directory.is_dir() or directory in directories:
        continue
    directories.add(directory)
    status = dict(line.split('=', 1) for line in (directory / 'status.txt').read_text().splitlines()
                  if '=' in line)
    assert math.isclose(float(status['area_um2']) / .504,
                        float(row['NAND2_GE']), rel_tol=1e-9), directory
    encoder_manifest = directory / 'source_manifest.json'
    if encoder_manifest.exists():
        sources = json.loads(encoder_manifest.read_text())['files']
        for name, digest in sources.items():
            check_hash(directory / 'sources' / Path(name).name, digest)
            source_count += 1
    else:
        sources = json.loads((directory / 'source_sha256.json').read_text())
        for name, digest in sources.items():
            check_hash(directory / 'source_snapshot' / name, digest)
            source_count += 1

for row in rows:
    key = row['configuration']
    totals[key] = totals.get(key, 0) + float(row['total_NAND2_GE'])
for key, value in totals.items():
    assert math.isclose(value, summary['total_GE'][key], rel_tol=1e-12), key
for row in alternatives:
    assert math.isclose(float(row['complete_ECC_relative_to_BCH_t9']),
                        float(row['complete_ECC_GE']) / totals['BCH(t=9), common-optimized'],
                        rel_tol=1e-12)

evidence = json.loads((HERE / 'results/selected_evidence_sha256.json').read_text())
retained = omitted = 0
for files in evidence.values():
    for name, digest in files.items():
        path = ROOT / name
        if path.exists():
            check_hash(path, digest)
            retained += 1
        else:
            omitted += 1

print(f'PASS: {len(rows)} hardware rows, {len(alternatives)} FWHT alternatives, '
      f'{source_count} frozen source hashes, {retained} retained evidence hashes.')
print(f'{omitted} recorded evidence paths are not in this checkout '
      '(private/rebuildable products or superseded logs); hashes are retained.')
print('This audits the recorded results; it does not rerun hardware simulation or synthesis.')
