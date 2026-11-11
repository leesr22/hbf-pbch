# BCH RTL release

This directory contains the selected BCH hardware used in the HBF study.
Both evaluated configurations use the same parameterized encoder and decoder
cores; only generated constants and parameters differ.

## Selected common-width configurations

| Configuration | Circuit | Width | Area (um2) | Throughput (GB/s) | Target (GB/s) | Replicas | Replicated area (mm2) |
|---|---|---:|---:|---:|---:|---:|---:|
| BCH(k=4096, t=8) | Encoder | 512 | 8,635.9 | 14.222 | 12.8 | 1 | 0.009 |
| BCH(k=4096, t=8) | Decoder | 128 | 38,913.5 | 3.507 | 384 | 110 | 4.280 |
| BCH(k=4096, t=30) | Encoder | 512 | 28,013.7 | 14.222 | 12.8 | 1 | 0.028 |
| BCH(k=4096, t=30) | Decoder | 128 | 231,791.6 | 3.282 | 384 | 117 | 27.120 |

All synthesis results use a 250 MHz clock and the UMC 28 nm 0.9 V slow
standard-cell library. Area is pre-layout cell area. Throughput is computed
from the steady-state message initiation interval. NAND2 gate equivalents use
0.504 um2 per NAND2 gate.

Encoder and decoder replication use different system targets because the
encoder is on the program/write path and the decoder is on the sensing/read
path. The previous common 3.072 TB/s normalization is not used in the primary
area totals.

## Architecture

- Encoder: systematic shortened-BCH encoder using a fixed parallel GF(2)
  remainder update.
- Syndrome: computes only odd syndromes; even syndromes are reconstructed by
  repeated squaring.
- Key-equation solver: inversionless Berlekamp-Massey.
- BM interleaving: one lane for t=8 and four lanes for t=30, balancing the
  W=128 syndrome, BM, and Chien pipeline rates.
- Error location/correction: parallel Chien search over each stream beat.
- Decoder pipeline: syndrome, BM, and Chien stages process different codewords
  concurrently.
- Replay: the selected decoder assumes that the sensed codeword can be replayed
  from an external cache buffer after error locations are found.

The long hexadecimal parameters in `rtl/generated/` are compile-time GF(2)
linear transforms for syndrome and Chien processing. They are constants, not
flip-flop arrays.

## Directory layout

```text
bch/
  rtl/
    bch/        parameterized BCH cores
    common/     finite-field helper functions
    generated/  wrappers for the selected synthesis points
  sim/
    tb/         self-checking VCS testbenches
    vectors/    encoder and decoder reference vectors
    results/    checked simulation logs
  syn/
    reports/    checked Design Compiler reports
    results/    machine-readable status files
    results.csv summary of the selected points
```

## Simulation

Synopsys VCS R-2020.12-SP1-1 was used for the recorded results.

```bash
cd bch
sim/run_encoder.sh t8
sim/run_encoder.sh t30
sim/run_decoder.sh t8 pipeline
sim/run_decoder.sh t30 pipeline
```

Run all four selected points with:

```bash
cd bch
sim/run_regression.sh
```

The decoder pipeline test streams 25 frames. Five error patterns with weights
0, 1, an intermediate value, t-1, and t are each repeated five times.

## Synthesis

Synopsys Design Compiler Q-2019.12-SP5-5 was used for the checked reports.
The laboratory library path is the default and can be overridden with
`BCH_TARGET_LIBRARY`.

```bash
cd bch
syn/run_synthesis.sh t8 enc 250
syn/run_synthesis.sh t8 dec 250
syn/run_synthesis.sh t30 enc 250
syn/run_synthesis.sh t30 dec 250
```

New runs are written under `syn/generated_reports/`; the checked-in reports in
`syn/reports/` remain immutable reference results.

## Scope

This is research RTL for the fixed configurations above. It is not a
production-qualified BCH IP. The area model excludes the external cache buffer,
clock tree, global routing, engine-pool control, and post-layout overhead.
