#!/usr/bin/env python3
"""Build the fair common-width, direct-300-MHz hardware comparison."""

from __future__ import annotations

import csv
import math
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "results" / "paper_hardware"
NAND2_AREA_UM2 = 0.504
PAYLOAD_BYTES = 512
WRITE_TARGET_GBPS = 12.8
READ_TARGET_GBPS = 384.0
PBCH_N = 4213
FLAG_PROBABILITY = 0.002


def status(run: str) -> dict[str, str]:
    path = ROOT / "syn" / "study_results" / run / "status.txt"
    values = dict(re.findall(r"^([^=]+)=(.*)$", path.read_text(), re.M))
    if values.get("result") != "PASS":
        raise RuntimeError(f"synthesis did not pass: {run}")
    return values


def expected_pbch_encoder_ii() -> float:
    def ii(flags: int) -> int:
        # W=512 shortens capture/replay by three cycles relative to W=256.
        # The exact blocked-FWHT search remains the common-case bottleneck.
        return max(68, 67 + flags, 35 + 2 * flags)

    p = FLAG_PROBABILITY
    pmf = (1.0 - p) ** PBCH_N
    total = pmf * ii(0)
    for flags in range(1, PBCH_N + 1):
        pmf *= ((PBCH_N - flags + 1) / flags) * p / (1.0 - p)
        total += pmf * ii(flags)
        if flags > 100 and pmf < 1e-30:
            break
    return total


BLOCKS = (
    ("BCH(t=8)", "Encoder", "W=512", 9.0,
     "bch_base_enc_w512_fair_w512_300mhz"),
    ("BCH(t=8)", "Decoder", "W=64, BM=1", 69.0,
     "bch_base_dec_replay_w64_fair_w_300mhz"),
    ("BCH(t=9)", "Encoder", "W=512", 9.0,
     "bch_equal_r_enc_w512_fair_w512_300mhz"),
    ("BCH(t=9)", "Decoder", "W=64, BM=1", 69.0,
     "bch_equal_r_dec_replay_w64_fair_w_300mhz"),
    ("BCH(t=27)", "Encoder", "W=512", 9.0,
     "bch_paper_enc_w512_fair_w512_300mhz"),
    ("BCH(t=27)", "Decoder", "W=64, BM=2", 73.0,
     "bch_paper_bm2_dec_replay_w64_fair_w_300mhz"),
    ("PBCH(t=8,l=13)", "Encoder", "W=512", None,
     "pbch_paper_blockg7_fwht_h7_m32_p128_w512_fair_w512_300mhz"),
    ("PBCH(t=8,l=13)", "Decoder", "W=64, BM=1", 70.0,
     "pbch_paper_dec_replay_w64_fair_w_300mhz"),
)


def build() -> list[dict[str, object]]:
    rows = []
    for config, block, microarch, fixed_ii, run in BLOCKS:
        measured = status(run)
        area = float(measured["area_um2"])
        ii = expected_pbch_encoder_ii() if fixed_ii is None else fixed_ii
        throughput = PAYLOAD_BYTES * 300e6 / ii / 1e9
        target = WRITE_TARGET_GBPS if block == "Encoder" else READ_TARGET_GBPS
        replicas = math.ceil(target / throughput - 1e-12)
        ge = area / NAND2_AREA_UM2
        rows.append({
            "configuration": config,
            "block": block,
            "microarchitecture": microarch,
            "frequency_MHz": 300,
            "area_um2": f"{area:.6f}",
            "NAND2_GE_per_engine": f"{ge:.3f}",
            "II_cycles": f"{ii:.6f}",
            "throughput_GBps": f"{throughput:.6f}",
            "bandwidth_target_GBps": f"{target:.1f}",
            "replicas": replicas,
            "total_area_mm2": f"{area * replicas / 1e6:.6f}",
            "aggregate_MGE": f"{ge * replicas / 1e6:.6f}",
            "slack_ns": f"{float(measured['slack_ns']):.6f}",
            "synthesis_basis": "direct 300-MHz synthesis",
            "synthesis_run": run,
        })
    return rows


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rows = build()
    path = OUT / "blocks_300mhz_common_width.csv"
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(path)


if __name__ == "__main__":
    main()
