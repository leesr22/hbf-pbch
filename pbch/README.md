# PBCH RTL release

This directory contains the selected PBCH hardware for the HBF study:

- code: `k=4096`, `t=13`, `l=13`, `n=4278`
- encoder: W=256 exact blocked-FWHT search, `MAX_FLAGS=32`
- decoder: W=64 cache-buffer-replay structure
- clock/process: 250 MHz, UMC 28 nm 0.9 V slow library

The PBCH decoder reuses the frozen BCH arithmetic cores under `../bch/rtl/`.
Only PBCH-specific selector removal and the generated PBCH constants are kept
under this directory.

## Hardware results

The encoder is provisioned for the 12.8 GB/s write path. The decoder is
provisioned for the 384 GB/s read path.

| Circuit | Width | Area (um2) | NAND2 GE | II (cycles) | Throughput | Target | Replicas | Replicated area |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Encoder | 256 | 80,146.6 | 159,021 | 75 | 1.707 GB/s | 12.8 GB/s | 8 | 0.641 mm2 |
| Decoder | 64 | 48,924.8 | 97,073 | 71 | 1.803 GB/s | 384 GB/s | 213 | 10.421 mm2 |

Total replicated PBCH area is 11.062 mm2. For comparison, the
reliability-matched BCH(k=4096, t=30) total is 28.400 mm2 under the same
write/read bandwidth targets.

The encoder throughput row uses a fixed eight-flag codeword. Encoder processing
time depends on the retained flag count, while the synthesized hardware area
does not.

## Encoder algorithm

For every retained flagged cell, the encoder forms `(a_i, c_i(0))`. It then
evaluates all 8192 selectors using the exact score

```text
F[s] = sum_i (-1)^(c_i(0) + <a_i,s>)
```

and selects the smallest selector among those with maximum score. This is
mathematically identical to direct exhaustive search for the retained flags.

The 13-bit transform is split into six logical low-bit stages and seven
explicit high-bit butterfly stages. For each of 64 low-selector values, the
sparse flag records directly form a 128-entry partial-H vector. A seven-stage
128-point FWHT then produces 128 exact scores. Repeating this 64 times covers
all `64 x 128 = 8192` selectors without storing an 8192-entry H array.

The first 32 flags in increasing codeword-position order are retained. If more
than 32 flags are present, later flags do not participate in selector search
and `flags_truncated_o` is asserted. There is no dense fallback engine in this
release.

## Directory layout

```text
pbch/
  rtl/
    encoder/    hand-written FWHT encoder blocks
    decoder/    PBCH replay decoder and selector removal
    generated/  frozen encoder/decoder wrappers and GF(2) constants
  sim/
    tb/         self-checking VCS testbenches
    vectors/    frozen encoder, FWHT, and decoder vectors
    results/    checked PASS logs
  syn/
    reports/    frozen Design Compiler area/timing/hierarchy reports
    results/    machine-readable status files
    results.csv selected hardware points and bandwidth provisioning
```

## Simulation

Synopsys VCS R-2020.12-SP1-1 was used for the recorded results.

```bash
cd pbch
sim/run_fwht_search.sh
sim/run_encoder.sh
sim/run_decoder.sh
```

Run all three checks with:

```bash
cd pbch
sim/run_regression.sh
```

The FWHT unit test contains 96 cases checked against direct exhaustive-search
golden selectors and scores. The encoder regression covers 0, 1, 9, 16, 32,
33, 48, and 80 observed flags with randomized output backpressure. The decoder
pipeline test streams 25 frames through the external replay interface.

## Synthesis

Synopsys Design Compiler Q-2019.12-SP5-5 was used for the checked reports.
The laboratory library path can be overridden with `PBCH_TARGET_LIBRARY`.

```bash
cd pbch
syn/run_synthesis.sh enc 250
syn/run_synthesis.sh dec 250
```

New runs are written under `syn/generated_reports/`. Checked reports under
`syn/reports/` are immutable reference results.

## Scope

This is fixed research RTL rather than production-qualified ECC IP. The area
model excludes the external cache buffer, clock tree, global routing,
engine-pool control, and post-layout overhead. The 3 nm figures used in the
paper are analytical die-size scaling estimates, not 3 nm synthesis results.
