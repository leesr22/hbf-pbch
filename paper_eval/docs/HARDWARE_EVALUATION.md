# Hardware evaluation methodology and results

## 1. Why these four configurations

The release deliberately separates three different comparison questions.

1. **Baseline cost:** BCH(`t=8`) is the conventional 104-parity-bit reference
   used throughout the paper.
2. **Equal redundancy:** Outlast (`t=8,l=13`) uses 104 BCH parity bits and 13
   selector bits, for 117 redundant bits. BCH(`t=9`) also uses 117 parity
   bits, so this pair isolates the hardware cost of Outlast at a common code
   rate.
3. **Common reliability target:** At `RBER_error=1e-5`,
   `RBER_defect=1e-3`, ideal probing, and target `UBER=1e-16`, the analytical
   evaluation requires 247 bits beyond the BCH(`t=8`) baseline. Therefore
   the minimum BCH point is `(104+247)/13=27`. Outlast requires only 13 added
   selector bits and retains `t=8`, giving `t=8,l=13`.

The third comparison means that both are the minimum configurations meeting
the same target under the stated channel model. It does not claim identical
numerical UBER outside that point. Outlast (`t=8,l=13`) is also the main
configuration used by the probing-voltage calibration and read-budget
evaluation, so a separate larger-`l` hardware point is unnecessary.

## 2. Implemented microarchitecture

### BCH

- Systematic, shortened primitive binary BCH over `GF(2^13)`.
- `W=512` encoder updates the remainder in parallel and accepts one 4,096-bit
  payload every 9 cycles.
- `W=64` decoder pipelines syndrome generation, inversionless
  Berlekamp-Massey, parallel Chien search/correction, and external-buffer
  replay across different codewords.
- BCH(`t=27`) uses two BM lanes; the `t=8` and `t=9` decoders use one.

### Outlast

- Parent BCH is the same `t=8`, 104-parity-bit code used by the baseline.
- The 13-bit selector space is exhaustively evaluated without storing a dense
  8,192-entry score array.
- The selector is factored into 7 high bits and 6 low bits. For each low
  selector, the implementation constructs a sparse 128-entry histogram from
  the flagged positions and applies the seven high-bit FWHT butterfly stages.
- Up to 32 flagged positions are retained. The transform score arithmetic is
  signed 7-bit, which covers the exact `[-32,+32]` range. At or below the cap,
  the selected codeword is exactly the same as direct exhaustive search.
- If a word contains more than 32 flags, the first 32 in codeword order are
  optimized and the result asserts overflow. This behavior is fully exposed
  by the RTL interface rather than silently claiming an exact result.
- `W=512` changes capture and replay width only; it does not approximate the
  search objective.

## 3. Throughput and bandwidth provisioning

For a 512-B payload at 300 MHz, single-engine throughput is

```
throughput = 512 B * 300 MHz / codeword_interval.
```

The encoder target is 12.8 GB/s and the decoder target is 384 GB/s. Replicas
are always rounded up. The Outlast encoder interval depends on the flagged
cell count. The reported value is the expectation at `q=0.002`, corresponding
to ideal probing with `RBER_defect=1e-3`:

```
E[flags] = 4213 * 0.002 = 8.426 flags/codeword
E[interval] = 75.426 cycles.
```

The figure rounds this interval to 75 cycles for readability, while the CSV
retains 75.426217 and uses that exact expectation for throughput and replicas.

## 4. Synthesis method

- UMC 28-nm, 0.9-V slow, 125 C standard-cell Liberty view
- Direct 300-MHz (`3.333 ns`) synthesis
- 0.20-ns clock uncertainty and 0.40-ns I/O delays
- Mapped cell area divided by the library NAND2 area, 0.504 um2, to report GE
- Pre-layout synthesis only; no placement-and-route result and no 3-nm area
  extrapolation

Every selected block has positive setup slack at 300 MHz. The Outlast encoder
is the tightest point at +0.103 ns, so 300 MHz is an achieved timing point, not
an assumed process scaling benefit.

## 5. Final per-block results

| Configuration | Circuit | W | NAND2 GE | Interval | GB/s | Replicas | Total GE |
|---|---|---:|---:|---:|---:|---:|---:|
| BCH(`t=8`) | Encoder | 512 | 17,135 | 9 | 17.067 | 1 | 17,135 |
| BCH(`t=8`) | Decoder | 64 | 53,682 | 69 | 2.226 | 173 | 9.287 M |
| BCH(`t=9`) | Encoder | 512 | 19,009 | 9 | 17.067 | 1 | 19,009 |
| BCH(`t=9`) | Decoder | 64 | 60,447 | 69 | 2.226 | 173 | 10.457 M |
| BCH(`t=27`) | Encoder | 512 | 49,616 | 9 | 17.067 | 1 | 49,616 |
| BCH(`t=27`) | Decoder | 64 | 230,668 | 73 | 2.104 | 183 | 42.212 M |
| Outlast (`t=8,l=13`) | Encoder | 512 | 167,068 | 75.426 avg. | 2.036 | 7 | 1.169 M |
| Outlast (`t=8,l=13`) | Decoder | 64 | 63,697 | 70 | 2.194 | 175 | 11.147 M |

Combined, bandwidth-provisioned totals are:

| Configuration | Total NAND2 GE | Interpretation |
|---|---:|---|
| BCH(`t=8`) | 9.304 M | Baseline only; does not meet the reference disturbed-channel target |
| BCH(`t=9`) | 10.476 M | Equal redundancy |
| BCH(`t=27`) | 42.262 M | Minimum BCH meeting the reference UBER target |
| Outlast (`t=8,l=13`) | 12.317 M | Main Outlast configuration |

Therefore:

- Outlast is **17.6% larger** than equal-redundancy BCH(`t=9`). This is the
  cost of the exact-search write path after bandwidth provisioning.
- Outlast is **70.9% smaller** than BCH(`t=27`), the minimum BCH point that
  meets the same UBER target at the reference channel condition.
- Outlast is 32.4% larger than the BCH(`t=8`) baseline, but that baseline is
  not a reliability-equivalent alternative at `RBER_defect=1e-3`.

## 6. Verification evidence

- Python reference-model suite: 10 tests passed.
- All selected BCH encoder/decoder wrappers pass self-checking VCS vectors.
- The Outlast encoder matches the direct exhaustive-search selector and masked
  failure count for 0--32 retained flags, including a dedicated 32-flag stress
  run at `W=512`.
- All eight synthesis points report positive setup slack at 300 MHz; exact
  values are in `results/paper_hardware/timing_summary.csv`.

The checked result CSV is the source of truth for table calculations. PNG and
SVG are generated presentation artifacts and contain no additional data.
