#!/usr/bin/env python3
"""Generate 8-frame exact PBCH streams with a fixed flag count."""

from pathlib import Path
import argparse
import random
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from model.ecc import STUDY_PROFILES  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("count", type=int)
    parser.add_argument("--profile", choices=("pbch_fht", "pbch_paper"),
                        default="pbch_fht")
    args = parser.parse_args()
    if not 0 <= args.count <= 32:
        parser.error("count must be in [0,32]")

    codec = STUDY_PROFILES[args.profile]
    rng = random.Random(0x710000 + args.count)
    rows = []
    for _ in range(8):
        message = rng.getrandbits(codec.k)
        positions = tuple(sorted(rng.sample(range(codec.n), args.count)))
        probe = sum(1 << (codec.n - 1 - p) for p in positions)
        selector, failures = codec.fht_selector(message, positions)
        rows.append((message, probe, codec.encode(message, selector),
                     selector, failures))

    suffix = "" if args.profile == "pbch_fht" else "_%s" % args.profile
    out = ROOT / "vectors" / (
        "throughput%s_flags_%02d" % (suffix, args.count))
    out.mkdir(parents=True, exist_ok=True)
    for filename, bits, field in (("message.hex", codec.k, 0),
                                  ("probe.hex", codec.n, 1),
                                  ("codeword.hex", codec.n, 2)):
        digits = (bits + 3) // 4
        (out / filename).write_text("".join(
            ("%0*x\n" % (digits, row[field])) for row in rows))
    (out / "selector.hex").write_text("".join(
        "%04x\n" % row[3] for row in rows))
    (out / "failures.hex").write_text("".join(
        "%04x\n" % row[4] for row in rows))
    print(out)


if __name__ == "__main__":
    main()
