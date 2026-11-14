#!/usr/bin/env python3
"""Separate ASAP-input decoder measurements; never overwrite historical results."""
from pathlib import Path
import csv
import math
import re

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
SELECTED = ["original", "compressedfirstchien", "compressedgroupfirstchien",
            "fair_group_t8", "fair_chien_t9", "fair_chien_t27"]
MAPPED_REQUIRED = set(SELECTED[1:])


def metrics(path, frames=25):
    text = path.read_text()
    assert f"PASS pipeline frames={frames} outputs={frames*64}" in text, path
    assert not re.search(r"Fatal:|ERROR", text), path
    gaps = list(map(int, re.findall(r"METRIC start_gap_\d+=(\d+)", text)))
    e2e = list(map(int, re.findall(r"METRIC E2E_frame_\d+=(\d+)", text)))
    assert len(gaps) == frames-1 and len(e2e) == frames, path
    assert len(set(e2e)) == 1, path
    if len(set(gaps)) != 1:
        assert "fair_group_t8" in str(path) and gaps == [68,69]*((frames-1)//2), path
    events = {}
    for frame, event, cycle in re.findall(
            r"TIMELINE frame=(\d+) event=(.*?) cycle=(\d+)", text):
        events[(int(frame), event.replace(" ", ""))] = int(cycle)
    origin = events[(0, "START")]
    timeline = {event: events[(0, event)] - origin for event in
                ["input_first", "input_last", "output_first", "output_last"]}
    timeline["next_START"] = events[(1, "START")] - origin
    return gaps, e2e, timeline


rows = []
for variant in SELECTED:
    rtl_path = OUT / "build" / f"{variant}_pipeline_fast" / "run.log"
    gaps, e2e, timeline = metrics(rtl_path)
    gate_path = OUT / "build" / f"{variant}_gate_pipeline_fast" / "run.log"
    gate_status = "not rerun; original RTL reference"
    if variant in MAPPED_REQUIRED:
        gate_gaps, gate_e2e, gate_timeline = metrics(gate_path)
        assert (gaps, e2e, timeline) == (gate_gaps, gate_e2e, gate_timeline), variant
        gate_status = "PASS, mapped timing-free functional simulation"
    if variant == "fair_group_t8":
        long_rtl = metrics(OUT / "build/fair_group_t8_pipeline_fast129/run.log",129)
        long_gate = metrics(OUT / "build/fair_group_t8_gate_pipeline_fast129/run.log",129)
        assert long_rtl == long_gate
    if variant == "original":
        with (ROOT / "results/paper_hardware/blocks_300mhz_common_width.csv").open() as stream:
            baseline = next(row for row in csv.DictReader(stream)
                            if row["configuration"].startswith("PBCH")
                            and row["block"] == "Decoder")
        area = float(baseline["area_um2"])
    else:
        status = OUT / "runs" / variant / "status.txt"
        assert (status.parent / "netlist.v").stat().st_size > 0
        assert "Thank you..." in (status.parent / "compile.log").read_text()
        data = dict(line.split("=", 1) for line in status.read_text().splitlines() if "=" in line)
        area = float(data["area_um2"])
        assert float(data["slack_ns"]) >= 0
    ge = area / .504
    ii = sum(gaps) / len(gaps)
    throughput = 512 * .3 / ii
    replicas = math.ceil(384 / throughput)
    rows.append(dict(variant=variant,ii_cycles=ii,ii_min_cycles=min(gaps),ii_max_cycles=max(gaps),e2e_cycles=e2e[0],
                     e2e_ns=e2e[0]/.3,throughput_GBps=throughput,
                     replicas=replicas,nand2_ge=ge,total_nand2_ge=ge*replicas,
                     **{f"timeline_{key}_relative_cycle":value for key,value in timeline.items()},
                     rtl_log=str(rtl_path.relative_to(ROOT)),mapped_status=gate_status,
                     mapped_log=str(gate_path.relative_to(ROOT)) if variant in MAPPED_REQUIRED else ""))

with (OUT / "zero_bubble_results.csv").open("w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
for row in rows:
    print(f"{row['variant']}: II={row['ii_cycles']} E2E={row['e2e_cycles']} "
          f"replicas={row['replicas']} total_GE={row['total_nand2_ge']:.3f}")
