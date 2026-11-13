# Final K=4096 paper hardware point

This directory is the self-contained release for the final Outlast hardware
comparison. It contains the four configurations used in the paper-facing
table, their selected RTL, verification collateral, synthesis flow, and
postprocessed results.

## Selected designs

| Profile | Encoder top | Decoder top | Meaning |
|---|---|---|---|
| BCH(`t=8`) | `bch_base_enc_w512` | `bch_base_dec_replay_w64` | Baseline |
| BCH(`t=9`) | `bch_equal_r_enc_w512` | `bch_equal_r_dec_replay_w64` | Equal redundancy |
| BCH(`t=27`) | `bch_paper_enc_w512` | `bch_paper_bm2_dec_replay_w64` | Equal UBER target |
| Outlast (`t=8,l=13`) | `pbch_paper_blockg7_fwht_h7_m32_p128_w512` | `pbch_paper_dec_replay_w64` | Main configuration |

All encoders use `W=512`; all decoders use `W=64`. The BCH(`t=27`) decoder
interleaves two unchanged Berlekamp-Massey lanes to balance the decoder
pipeline. Outlast uses the same parent BCH(`t=8`) decoder plus selector
recovery.

## Directory map

| Path | Contents |
|---|---|
| `model/` | Executable BCH/PBCH reference model |
| `rtl/bch/` | Shared systematic BCH encoder and decoder blocks |
| `rtl/pbch/` | Sparse exact-search encoder and PBCH decoder blocks |
| `rtl/generated/` | Frozen wrappers/constants for the selected points |
| `tb/`, `vectors/` | Self-checking VCS testbenches and deterministic vectors |
| `sim/` | VCS launch scripts |
| `syn/` | Design Compiler flow; library path is configurable |
| `scripts/` | RTL generation and final result/table generation |
| `results/paper_hardware/` | Final CSV, timing summary, PNG, and SVG |
| `docs/` | Architecture, methodology, and result interpretation |

## Verification

The recorded release passed the Python reference tests (`10 passed`) and VCS
regressions for every selected BCH/PBCH encoder and decoder. The W=512
Outlast encoder was additionally checked with 32 flagged cells against the
golden exhaustive-search selector and failure count.

Run the software checks:

```bash
cd paper_eval
pytest -q
```

Representative RTL checks:

```bash
sim/run_study_bch_encoder.sh bch_base 512
sim/run_study_bch_encoder.sh bch_equal_r 512
sim/run_study_bch_encoder.sh bch_paper 512

sim/run_study_decoder.sh bch_base replay 64 pipeline
sim/run_study_decoder.sh bch_equal_r replay 64 pipeline
sim/run_study_decoder.sh bch_paper_bm2 replay 64 pipeline
sim/run_study_decoder.sh pbch_paper replay 64 pipeline

HBF_FHT_PIPE_PROFILE=pbch_paper \
HBF_FHT_PIPE_SEARCH=grouped HBF_FHT_PIPE_GROUP=7 HBF_FHT_HIGH_L=7 \
HBF_FHT_PIPE_LANES=128 HBF_FHT_PIPE_WIDTH=512 \
sim/run_pbch_pipeline_encoder.sh
```

The simulator and synthesis scripts use `+vcs+lic+wait` or a serialized DC
lock, respectively, so transient license contention does not invalidate a run.

## Synthesis

The checked results were synthesized directly at 300 MHz. For example:

```bash
HBF_FHT_RUN_TAG=fair_w512 bash syn/run_study.sh bch_base enc replay 512 300
HBF_FHT_RUN_TAG=fair_w bash syn/run_study.sh bch_base dec replay 64 300
HBF_FHT_RUN_TAG=fair_w512 bash syn/run_study.sh bch_equal_r enc replay 512 300
HBF_FHT_RUN_TAG=fair_w bash syn/run_study.sh bch_equal_r dec replay 64 300
HBF_FHT_RUN_TAG=fair_w512 bash syn/run_study.sh bch_paper enc replay 512 300
HBF_FHT_RUN_TAG=fair_w bash syn/run_study.sh bch_paper_bm2 dec replay 64 300
HBF_FHT_RUN_TAG=fair_w512 bash syn/run_study.sh pbch_paper enc bg7h7_32_128 512 300
HBF_FHT_RUN_TAG=fair_w bash syn/run_study.sh pbch_paper dec replay 64 300
```

Set `HBF_ECC_TARGET_LIBRARY` to a licensed Liberty database before running DC.
Raw proprietary EDA outputs are intentionally not tracked.

After all eight runs complete, rebuild the checked CSV and then the table:

```bash
python3 scripts/build_common_width_hw_results.py
python3 scripts/plot_paper_hardware_table_300mhz.py
```

See [`docs/HARDWARE_EVALUATION.md`](docs/HARDWARE_EVALUATION.md) for the
configuration rationale, architecture details, equations, and interpretation.
