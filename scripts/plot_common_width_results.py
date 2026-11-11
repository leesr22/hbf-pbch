#!/usr/bin/env python3
"""Plot the selected common-width BCH/PBCH synthesis results."""

from __future__ import annotations

import csv
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import FancyBboxPatch, Rectangle


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "reports" / "figures"

NAVY = "#17212F"
MUTED = "#8993A1"
HEADER = "#E5E7EA"
GRID = "#E4E8ED"
ENCODER = "#326CC5"
DECODER = "#F8C83E"
WHITE = "#FFFFFF"
ROW_ALT = "#FBFCFD"

# TSMC 2025 Annual Report, normalized die-size comparison:
# 28 nm = 0.25, 3 nm = 0.026.
SCALE_28NM_TO_3NM = 0.026 / 0.25


def load_rows() -> list[dict[str, float | int | str]]:
    """Read the six selected rows directly from the checked synthesis CSVs."""
    rows: list[dict[str, float | int | str]] = []
    sources = [ROOT / "bch" / "syn" / "results.csv",
               ROOT / "pbch" / "syn" / "results.csv"]
    for source in sources:
        with source.open(newline="", encoding="utf-8") as handle:
            for raw in csv.DictReader(handle):
                rows.append({
                    "configuration": raw["configuration"],
                    "circuit": raw["circuit"],
                    "width": int(raw["width_bits"]),
                    "area": float(raw["area_um2"]),
                    "ge": float(raw["nand2_ge"]),
                    "throughput": float(raw["throughput_GBps"]),
                    "replicas": int(raw["replicas"]),
                    "replicated_area": float(raw["replicated_area_mm2"]),
                    "total_ge": float(raw["total_nand2_ge"]),
                })
    if len(rows) != 6:
        raise RuntimeError(f"expected six selected rows, found {len(rows)}")
    return rows


def display_config(value: str) -> str:
    return value.replace(" t=", ", t=").replace(" l=", ", l=")


def fmt_area_um2(value: float) -> str:
    return f"{value:,.1f} µm²"


def fmt_area_mm2(value: float) -> str:
    return f"{value:.4f} mm²" if value < 0.01 else f"{value:.3f} mm²"


def fmt_total_ge(value: float) -> str:
    return f"{value / 1_000_000:.3f} M" if value < 100_000 else f"{value / 1_000_000:.2f} M"


def make_table(rows: list[dict[str, float | int | str]]) -> None:
    fig = plt.figure(figsize=(25.5, 13.6), dpi=180, facecolor=WHITE)
    ax = fig.add_axes([0.015, 0.03, 0.97, 0.94])
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")

    ax.text(0.006, 0.975, "ECC Hardware Results with Bandwidth Targets",
            ha="left", va="top", fontsize=34, fontweight="medium", color=NAVY)
    ax.text(
        0.006, 0.925,
        "250 MHz  ·  Encoder target: 12.8 GB/s  ·  Decoder target: 384 GB/s  ·  "
        "UMC 28 nm synthesis + TSMC 3 nm scaling estimate",
        ha="left", va="top", fontsize=17, color=MUTED,
    )

    left, right = 0.004, 0.996
    table_top, table_bottom = 0.855, 0.155
    header_h = 0.100
    row_h = (table_top - table_bottom - header_h) / 6

    outer = FancyBboxPatch(
        (left, table_bottom), right - left, table_top - table_bottom,
        boxstyle="round,pad=0.002,rounding_size=0.012",
        linewidth=0.8, edgecolor="#E1E5E9", facecolor=WHITE, zorder=0,
    )
    ax.add_patch(outer)
    header = Rectangle(
        (left, table_top - header_h), right - left, header_h,
        linewidth=0, facecolor=HEADER, zorder=1,
    )
    header.set_clip_path(outer)
    ax.add_patch(header)

    edges = [left, 0.159, 0.265, 0.405, 0.510, 0.635, 0.735, 0.875, right]
    headers = [
        "Configuration",
        "Circuit",
        "Single-circuit area\n3 nm scaled (28 nm)",
        "Single-circuit\nNAND2 GE",
        "Single-circuit\nthroughput",
        "Replicas for\nrequired BW",
        "Total replicated area\n3 nm scaled (28 nm)",
        "Total replicated\nNAND2 GE",
    ]
    for index, title in enumerate(headers):
        x0, x1 = edges[index], edges[index + 1]
        left_aligned = index < 2
        ax.text(
            x0 + 0.009 if left_aligned else (x0 + x1) / 2,
            table_top - header_h / 2,
            title,
            ha="left" if left_aligned else "center",
            va="center",
            fontsize=15.4,
            fontweight="medium",
            color=NAVY,
            linespacing=1.08,
        )

    for group in range(3):
        y_top = table_top - header_h - group * 2 * row_h
        if group % 2 == 0:
            shade = Rectangle(
                (left, y_top - 2 * row_h), right - left, 2 * row_h,
                linewidth=0, facecolor=ROW_ALT, zorder=0.5,
            )
            shade.set_clip_path(outer)
            ax.add_patch(shade)
        if group > 0:
            ax.plot([left, right], [y_top, y_top], color="#C8CED5", lw=1.15, zorder=3)

    for index, row in enumerate(rows):
        y_top = table_top - header_h - index * row_h
        y_bottom = y_top - row_h
        y_mid = (y_top + y_bottom) / 2

        if index % 2 == 1:
            ax.plot([edges[1], right], [y_top, y_top], color=GRID, lw=0.7, zorder=3)
        if index % 2 == 0:
            ax.text(
                edges[0] + 0.009, y_mid - row_h / 2,
                display_config(str(row["configuration"])),
                ha="left", va="center", fontsize=16.8, color=NAVY,
            )

        circuit = str(row["circuit"])
        dot_color = ENCODER if circuit == "Encoder" else DECODER
        ax.scatter(edges[1] + 0.013, y_mid + 0.012, s=54, color=dot_color, zorder=5)
        ax.text(edges[1] + 0.027, y_mid + 0.012, circuit,
                ha="left", va="center", fontsize=17.0, color=NAVY)
        ax.text(edges[1] + 0.027, y_mid - 0.025, f"W = {int(row['width'])}",
                ha="left", va="center", fontsize=15.0, color=MUTED)

        area_28 = float(row["area"])
        replicated_28 = float(row["replicated_area"])
        ax.text((edges[2] + edges[3]) / 2, y_mid + 0.014,
                fmt_area_um2(area_28 * SCALE_28NM_TO_3NM),
                ha="center", va="center", fontsize=16.1, color=NAVY)
        ax.text((edges[2] + edges[3]) / 2, y_mid - 0.022,
                f"(28 nm: {fmt_area_um2(area_28)})",
                ha="center", va="center", fontsize=13.1, color=MUTED)

        values = {
            3: f"{float(row['ge']):,.0f}",
            4: f"{float(row['throughput']):.3f} GB/s",
            5: f"{int(row['replicas']):,}",
            7: fmt_total_ge(float(row["total_ge"])),
        }
        for column, value in values.items():
            ax.text((edges[column] + edges[column + 1]) / 2, y_mid, value,
                    ha="center", va="center", fontsize=15.8, color=NAVY)

        ax.text((edges[6] + edges[7]) / 2, y_mid + 0.014,
                fmt_area_mm2(replicated_28 * SCALE_28NM_TO_3NM),
                ha="center", va="center", fontsize=16.1, color=NAVY)
        ax.text((edges[6] + edges[7]) / 2, y_mid - 0.022,
                f"(28 nm: {fmt_area_mm2(replicated_28)})",
                ha="center", va="center", fontsize=13.1, color=MUTED)

    ax.text(
        0.006, 0.115,
        "Required bandwidth: Encoder 12.8 GB/s; Decoder 384 GB/s  ·  "
        "All encoders W=512; all decoders W=128  ·  Decoder: cache-buffer replay structure",
        ha="left", va="center", fontsize=13.8, color=MUTED,
    )
    ax.text(
        0.006, 0.077,
        "3 nm scaled area = 28 nm synthesized area × (0.026 / 0.25) = ×0.104  ·  "
        "Estimate only; not 3 nm synthesis or P&R",
        ha="left", va="center", fontsize=13.8, color=MUTED,
    )
    ax.text(
        0.006, 0.039,
        "PBCH encoder: 8 flags/codeword, no backpressure  ·  "
        "NAND2 GE: 28 nm logical gate count using 0.504 µm² per gate",
        ha="left", va="center", fontsize=13.8, color=MUTED,
    )

    for suffix in ("png", "svg"):
        fig.savefig(OUT_DIR / f"ecc_hardware_results_common_width.{suffix}",
                    bbox_inches="tight", facecolor=WHITE)
    plt.close(fig)


def make_chart(
    rows: list[dict[str, float | int | str]],
    *,
    replicated: bool,
    area_scale: float,
    process_label: str,
    y_max: float,
    y_step: float,
    filename: str,
) -> None:
    configs: list[str] = []
    areas: dict[str, dict[str, float]] = {}
    for row in rows:
        config = str(row["configuration"])
        if config not in configs:
            configs.append(config)
            areas[config] = {}
        area_28nm = (float(row["replicated_area"]) if replicated else
                     float(row["area"]) / 1_000_000)
        areas[config][str(row["circuit"])] = area_28nm * area_scale

    enc = [areas[config]["Encoder"] for config in configs]
    dec = [areas[config]["Decoder"] for config in configs]
    totals = [encoder + decoder for encoder, decoder in zip(enc, dec)]

    fig = plt.figure(figsize=(16.2, 10.4), dpi=180, facecolor=WHITE)
    ax = fig.add_axes([0.08, 0.235, 0.89, 0.615])
    area_kind = "Total Replicated" if replicated else "Single-Engine"
    process_suffix = " (Scaled)" if area_scale != 1.0 else ""
    fig.text(
        0.08, 0.94,
        f"{area_kind} ECC Area — {process_label}{process_suffix}",
        ha="left", va="top", fontsize=25, fontweight="medium", color=NAVY,
    )
    if replicated:
        context = "Write: 12.8 GB/s  ·  Read: 384 GB/s  ·  "
    else:
        context = "One encoder engine + one decoder engine  ·  "
    process_context = (
        "Analytical area scaling: 0.026 / 0.25 = 0.104"
        if area_scale != 1.0 else "UMC 28 nm pre-layout cell area"
    )
    fig.text(
        0.08, 0.885,
        context + process_context,
        ha="left", va="top", fontsize=13, color=MUTED,
    )

    x = list(range(len(configs)))
    width = 0.48
    ax.set_axisbelow(True)
    ax.yaxis.grid(True, color=GRID, linewidth=1.0, zorder=0)
    ax.xaxis.grid(False)
    ax.bar(x, enc, width=width, color=ENCODER, edgecolor="none", zorder=3)
    ax.bar(x, dec, width=width, bottom=enc, color=DECODER, edgecolor="none", zorder=3)

    ticks = [index * y_step for index in range(int(round(y_max / y_step)) + 1)]
    ax.set_ylim(0, y_max)
    ax.set_yticks(ticks)
    tick_digits = 3 if y_max < 0.1 else (2 if y_max < 1 else 1)
    ax.set_yticklabels([f"{tick:.{tick_digits}f} mm²" for tick in ticks],
                       fontsize=11, color=MUTED)
    ax.tick_params(axis="y", length=0, pad=10)
    ax.tick_params(axis="x", length=0, pad=14)
    y_label = "Total replicated area (mm²)" if replicated else "Single-engine area (mm²)"
    ax.set_ylabel(y_label, fontsize=14, color=NAVY, labelpad=18)
    ax.set_xticks(x)
    ax.set_xticklabels(
        ["BCH(k=4096,\nt=8)", "BCH(k=4096,\nt=30)", "PBCH(k=4096,\nt=13, l=13)"],
        fontsize=12.2, color=NAVY,
    )

    for spine in ax.spines.values():
        spine.set_color("#D9DEE4")
        spine.set_linewidth(1.0)

    for index, (encoder, decoder, total) in enumerate(zip(enc, dec, totals)):
        value_digits = 4 if y_max < 0.1 else 3
        ax.text(index, encoder + decoder / 2,
                f"Decoder {decoder:.{value_digits}f}",
                ha="center", va="center", fontsize=11.3, color=NAVY,
                fontweight="medium", zorder=5)
        if replicated:
            # Encoder replication is tiny at the write target, so use a blue
            # direct label above the segment rather than enlarging the mark.
            encoder_digits = 4 if encoder < 0.1 else 3
            encoder_y = max(encoder + y_max * 0.011, y_max * 0.020)
            ax.text(index, encoder_y, f"Encoder {encoder:.{encoder_digits}f}",
                    ha="center", va="bottom", fontsize=11.0, color=ENCODER,
                    fontweight="medium", zorder=5)
        else:
            ax.text(index, encoder / 2,
                    f"Encoder {encoder:.{value_digits}f}",
                    ha="center", va="center", fontsize=10.7, color=WHITE,
                    fontweight="medium", zorder=5)
        ax.text(index, total + y_max * 0.031,
                f"Total {total:.{value_digits}f} mm²",
                ha="center", va="bottom", fontsize=12.2, color=NAVY,
                fontweight="medium", zorder=5)

    handles = [
        Line2D([0], [0], marker="s", color="none", markerfacecolor=ENCODER,
               markeredgecolor="none", markersize=10, label="Encoder"),
        Line2D([0], [0], marker="s", color="none", markerfacecolor=DECODER,
               markeredgecolor="none", markersize=10, label="Decoder"),
    ]
    fig.legend(handles=handles, loc="lower center", bbox_to_anchor=(0.535, 0.052),
               ncol=2, frameon=False, fontsize=12.5, handletextpad=0.5,
               columnspacing=1.7)
    fig.text(
        0.535, 0.018,
        ("3 nm areas are analytical scaling estimates from UMC 28 nm synthesis; "
         "not 3 nm synthesis or P&R." if area_scale != 1.0 else
         "UMC 28 nm pre-layout standard-cell synthesis area."),
        ha="center", va="center", fontsize=10.5, color=MUTED,
    )

    for suffix in ("png", "svg"):
        fig.savefig(OUT_DIR / f"{filename}.{suffix}",
                    bbox_inches="tight", facecolor=WHITE)
    plt.close(fig)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rows = load_rows()
    make_table(rows)
    make_chart(rows, replicated=True, area_scale=SCALE_28NM_TO_3NM,
               process_label="3 nm", y_max=3.5, y_step=0.5,
               filename="ecc_replicated_area_common_width_3nm")
    make_chart(rows, replicated=True, area_scale=1.0,
               process_label="28 nm", y_max=35.0, y_step=5.0,
               filename="ecc_replicated_area_common_width_28nm")
    make_chart(rows, replicated=False, area_scale=SCALE_28NM_TO_3NM,
               process_label="3 nm", y_max=0.032, y_step=0.005,
               filename="ecc_single_engine_area_common_width_3nm")
    make_chart(rows, replicated=False, area_scale=1.0,
               process_label="28 nm", y_max=0.32, y_step=0.05,
               filename="ecc_single_engine_area_common_width_28nm")
    print(OUT_DIR / "ecc_hardware_results_common_width.png")
    print(OUT_DIR / "ecc_replicated_area_common_width_3nm.png")
    print(OUT_DIR / "ecc_replicated_area_common_width_28nm.png")
    print(OUT_DIR / "ecc_single_engine_area_common_width_3nm.png")
    print(OUT_DIR / "ecc_single_engine_area_common_width_28nm.png")


if __name__ == "__main__":
    main()
