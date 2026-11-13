#!/usr/bin/env python3
"""Render a presentation-style 300-MHz BCH/PBCH hardware table."""

from __future__ import annotations

import csv
from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "results" / "paper_hardware" /
          "blocks_300mhz_common_width.csv")
OUT = ROOT / "results" / "paper_hardware"

TEXT = "#17202A"
MUTED = "#8490A3"
GRID = "#E3E7ED"
HEADER = "#E2E5EA"
ALT = "#F8FAFC"
WHITE = "#FFFFFF"
BLUE = "#2F73D2"
YELLOW = "#F7BE32"

mpl.rcParams.update({
    "font.family": "DejaVu Sans",
    "font.size": 11,
    "svg.fonttype": "none",
})


def load_rows() -> list[dict[str, str]]:
    with SOURCE.open(newline="") as stream:
        return list(csv.DictReader(stream))


def ge_text(value: float) -> str:
    if value >= 1e6:
        return f"{value / 1e6:.3f} M"
    return f"{value:,.0f}"


def draw() -> None:
    rows = load_rows()
    fig = plt.figure(figsize=(14.6, 9.2), facecolor=WHITE)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")

    ax.text(0.018, 0.962, "ECC Hardware Results at 300 MHz",
            ha="left", va="top", fontsize=25, fontweight="medium", color=TEXT)
    ax.text(0.018, 0.916,
            "UMC 28 nm synthesis  ·  Encoder target: 12.8 GB/s  ·  Decoder target: 384 GB/s",
            ha="left", va="top", fontsize=12.5, color=MUTED)

    left, right = 0.018, 0.982
    top, header_h, row_h = 0.862, 0.086, 0.075
    bottom = top - header_h - len(rows) * row_h
    widths = [0.185, 0.160, 0.145, 0.135, 0.140, 0.105, 0.130]
    scale = (right - left) / sum(widths)
    widths = [w * scale for w in widths]
    xs = [left]
    for width in widths:
        xs.append(xs[-1] + width)

    outer = FancyBboxPatch(
        (left, bottom), right - left, top - bottom,
        boxstyle="round,pad=0.002,rounding_size=0.012",
        linewidth=0.9, edgecolor=GRID, facecolor=WHITE,
    )
    ax.add_patch(outer)
    ax.add_patch(Rectangle((left, top - header_h), right - left, header_h,
                           linewidth=0, facecolor=HEADER))

    headers = [
        "Configuration", "Circuit", "Single-circuit\nNAND2 GE",
        "Codeword interval\n(cycles)", "Throughput\n@ 300 MHz",
        "Replicas for\ntarget BW",
        "Total\nNAND2 GE",
    ]
    for index, label in enumerate(headers):
        x = xs[index] + 0.012 * widths[index] if index < 2 else (xs[index] + xs[index + 1]) / 2
        ax.text(x, top - header_h / 2, label,
                ha="left" if index < 2 else "center", va="center",
                fontsize=10.7, fontweight="medium", color=TEXT)

    for index, row in enumerate(rows):
        y_top = top - header_h - index * row_h
        y_bottom = y_top - row_h
        yc = (y_top + y_bottom) / 2
        group = index // 2

        if group % 2 == 0:
            ax.add_patch(Rectangle((left, y_bottom), right - left, row_h,
                                   linewidth=0, facecolor=ALT))
        if index % 2 == 1:
            ax.plot([xs[1], right], [y_top, y_top], color=GRID, lw=0.7)
        if index > 0 and index % 2 == 0:
            ax.plot([left, right], [y_top, y_top], color="#CCD3DC", lw=1.15)

        if index % 2 == 0:
            config = row["configuration"].replace("PBCH(t=8,l=13)", "PBCH(t=8, l=13)")
            ax.text(xs[0] + 0.012 * widths[0], yc - row_h / 2,
                    config, ha="left", va="center", fontsize=11.4,
                    fontweight="medium", color=TEXT)

        block = row["block"]
        color = BLUE if block == "Encoder" else YELLOW
        ax.scatter(xs[1] + 0.033 * widths[1], yc + 0.010,
                   s=42, color=color, edgecolors="none", zorder=4)
        ax.text(xs[1] + 0.083 * widths[1], yc + 0.011, block,
                ha="left", va="center", fontsize=11.2, color=TEXT)
        micro = row["microarchitecture"].split(",", 1)[0]
        ax.text(xs[1] + 0.083 * widths[1], yc - 0.018, micro,
                ha="left", va="center", fontsize=9.5, color=MUTED)

        ge = float(row["NAND2_GE_per_engine"])
        interval = float(row["II_cycles"])
        throughput = float(row["throughput_GBps"])
        replicas = int(row["replicas"])
        total_ge = ge * replicas
        interval_text = f"{int(round(interval))}"
        values = [
            f"{ge:,.0f}", interval_text, f"{throughput:.3f} GB/s",
            f"{replicas:,}", ge_text(total_ge),
        ]
        for column, value in enumerate(values, start=2):
            ax.text((xs[column] + xs[column + 1]) / 2, yc, value,
                    ha="center", va="center", fontsize=10.6, color=TEXT)

    foot = bottom - 0.038
    ax.text(left, foot,
            "All eight blocks were synthesized directly at 300 MHz with common widths: W=512 for every encoder and W=64 for every decoder.",
            ha="left", va="center", fontsize=10.2, color=MUTED)
    ax.text(left, foot - 0.033,
            "Replicas are rounded up to meet each bandwidth target.",
            ha="left", va="center", fontsize=10.2, color=MUTED)
    ax.text(left, foot - 0.066,
            "PBCH encoder throughput is workload-expected at q=0.002.",
            ha="left", va="center", fontsize=10.2, color=MUTED)

    for suffix in ("png", "svg"):
        path = OUT / f"ecc_hardware_table_300mhz_common_width.{suffix}"
        fig.savefig(path, dpi=220, bbox_inches="tight", facecolor=WHITE)
        print(path)
    plt.close(fig)


if __name__ == "__main__":
    draw()
