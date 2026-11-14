# PBCH area optimization experiments (2026-11-14)

Target: the frozen `pbch_paper` code (`k=4096,t=8,l=13,seed=62`),
UMC28 synthesis at 300 MHz, encoder W512 and decoder W64. No code matrix,
correction capability, selector tie break, or 32-flag supported range is
relaxed. NAND2 GE = mapped standard-cell area / 0.504 um².

Original RTL and published result files are preserved. Each subdirectory
contains independent generators, candidate RTL, verification, and synthesis
artifacts. The measured comparison is generated in
[`results/hardware_comparison.csv`](results/hardware_comparison.csv), with a
[readable table](results/hardware_comparison.png) and
[machine-readable selection](results/summary.json). Standalone submodule area
is never substituted for complete-encoder or complete-decoder area.

## Selected result

The area-oriented recommendation is the **always-full-FWHT** encoder
`strict_piped_h7_c16_d5_crc128` with decoder
`compressedgroupfirstchien`. Both use the original frozen PBCH code.

| Component | Original GE | Optimized GE | Reduction | Replicas |
|---|---:|---:|---:|---:|
| One encoder | 167,067.666 | 88,785.999 | 46.86% | 7 |
| One decoder | 63,697.332 | 42,309.332 | 33.58% | 173 |
| Provisioned encoder + decoder | 12,189,112.098 | 7,941,016.515 | 34.85% | — |

The full-search encoder folds five inner stages into sparse input construction
and retains the final two butterfly stages. It evaluates all 8,192 selectors
without early termination. Its setup slack at 300 MHz is +0.0968151 ns; the
selected decoder's is +0.788075 ns.

The **fair, common-optimized** comparison points (encoders also optimized) are:

| Configuration | Encoder GE | Decoder GE | Provisioned total GE |
|---|---:|---:|---:|
| BCH t=8 | 16,488.666 | 40,665.333 | 7,010,925.859 |
| BCH t=9, same redundancy | 18,240.666 | 47,339.666 | 8,065,983.842 |
| BCH t=27 | 48,797.999 | 165,676.997 | 29,870,657.443 |
| PBCH t=8, l=13, full FWHT | 88,785.999 | 42,309.332 | 7,941,016.515 |

Thus the selected PBCH total is 1.55% below same-redundancy BCH t=9 under
these synthesis and workload assumptions—best described as near-parity,
not as a large technology-independent advantage. It is still 13.27% above
common-optimized BCH t=8. Its encoder alone is larger than BCH's; the
read/write bandwidth asymmetry and smaller decoder make the total close.

### Latency tradeoffs and retained alternatives

| Encoder | Flags 0 / 8 / 32 isolated E2E (cycles) | Workload II | GE / engine |
|---|---:|---:|---:|
| Unchanged original, common testbench | 100 / 117 / 163 | 75.4493 | 167,067.666 |
| Selected full FWHT, C16 / D5 | 124 / 141 / 251 | 75.8836 | 88,785.999 |
| Optional exact early stop | 43 / 53 / 586 | 79.3272 | 51,033.666 |

All three provision 7 encoders on the specified random workload. At 300 MHz
one cycle is 3.333333 ns. Selected flag-8
encoder E2E is 470 ns, versus 390 ns for the remeasured original.

The minimum-GE decoder has E2E 203 cycles / 676.67 ns instead of the original
171 cycles / 570 ns, with unchanged II 69. If original decoder latency is
preferred, use `compressedfirstchien` (43,994.666 GE): the same strict encoder
then gives 8,232,579.180 total GE, **only 2.07% above** fair BCH t=9.
The exact-early-stop encoder plus minimum-GE decoder gives 7,676,750.183 total
GE, but is intentionally separate from the always-full-search recommendation.

BCH t=8's selected decoder has E2E 201 cycles, longer than t=9's 173, because
t=8 can share multipliers without hurting bandwidth whereas t=9 cannot.
This is a deliberate per-code area/latency choice, not a latency typo.

### Conservative full-butterfly alternative

The full-search implementation need not fold five inner stages to get near
parity. `strict_piped_h7_c16_crc128` keeps **all seven inner butterfly stages**
(`DIRECT_STAGES=0`), costs 107,982.999 GE per encoder, and has setup slack
+0.0592895 ns. Its 16,384-codeword workload still needs 7 encoders. With the
selected decoder its total is **8,075,395.515 GE**, just **0.12% above** fair
BCH t=9. It passes the 256-frame mapped stress test with input bubbles, long
output stalls, overflow cases, and recycled contexts. This is a more
architecturally conservative choice if retaining every inner butterfly stage
is preferred to the selected design's additional exact stage folding.

The cached-C32/D5 exploration (`strict_piped_h7_c32_d5_crc128`) passes RTL
workloads but fails the mapped-netlist mixed/stalled regression. Its synthesis
and failed logs are retained for diagnosis; **it is excluded from verified
alternatives and must not be used as a final result**.

## Experiments

There are 62 completed synthesis runs: 42 complete-engine runs and 20
standalone-module runs (61 distinct measured points plus one BCH t8 rerun
to save mapped-netlist evidence). Completed synthesis does not imply a
candidate passed functional verification; failed explorations are retained
but excluded from final selections.

- `decoder`: replace the fixed mask ROM with its exact degree-32 binary
  recurrence; try shared XOR networks and time-shared BM multipliers.
- `fwht`: exact blocked FWHT with smaller butterfly arrays and time-shared
  histogram lanes; monotonic selector ordering permits exact early termination
  when a perfect masking score is found. All other cases still exhaust the
  complete selector space. Examine full workload tails, not only flag=8.
- `scan`: represent the unchanged mask columns with a small block-start ROM
  and fixed xorshift jump networks, or alternate ROM coding styles.
- `encoder`: integrate mask recurrence, scan lookup and FWHT candidates;
  improve completion backpressure and arbitrate a ready output ahead of an
  unstarted scan. Test recycled contexts and long stalls.

All comparisons distinguish per-engine gates, sustainable throughput, and
replicated total gates. Any shared BCH optimization must also be measured on
the relevant BCH comparison points. Variable-time search results require
the flag-count/position distribution to accompany throughput numbers.

## Verification conventions

- Independent full FWHT or direct exhaustive software golden outputs.
- Exact frozen matrix checked over all codeword positions; decoder masks
  checked over all 8192 selectors and all 4096 payload bits.
- Encoder regressions include random flag=8 workloads, flag counts 0–33,
  selector/parity flag positions, output stalls, and recycled context IDs.
- Decoder regressions include errors 0–8, corrected selector bits, input
  bubbles, and output backpressure.
- Synthesis constraints match the prior study: period 10/3 ns, clock
  uncertainty 0.20 ns, input/output delay 0.40 ns, no reset timing paths.

The recurrence optimizations reproduce the existing fixed pseudo-random
matrix exactly. They do not substitute the older cyclic PBCH mask family.

## Why these changes save gates

### Encoder: exact full search remains the primary comparison

The strict candidates evaluate **every one of the 8,192 selectors**. Their
output codeword, selected mask, maximum masking score, and smallest-selector
tie break match the original exhaustive FWHT. No random sampling, greedy
masking, reduced selector set, or approximate scoring is introduced.

The implementation improvements are:

1. Replace the fixed mask lookup with the exact degree-32 binary recurrence
   of the existing seed-62 matrix, and factor shared XOR terms. The probe-scan
   column lookup uses a small block-start ROM and fixed jump network for the
   same columns.
2. Fold the first `DIRECT_STAGES` inner transform stages into construction of
   the sparse FWHT input. Each contribution includes the corresponding label
   parity, and ordinary butterfly stages compute the remainder. This is the
   exact state after those transform stages, not omitted arithmetic.
3. Use lossless six-bit modular intermediate arithmetic. Only the scores
   +32 and -32 alias; at those extrema every flag contribution has the same
   sign, so the first flag resolves the ambiguity. Restore a seven-bit signed
   score before comparison. This does **not** saturate or clip scores.
4. Fuse histogram construction with the next butterfly group where timing
   permits, removing a register bank; evaluate different histogram circuits
   by synthesis, rather than by source-level operator count.
5. Keep the external encoder interface at W512 while sharing the CRC
   datapath across smaller internal slices. The full-search candidates use
   128-bit CRC work per cycle. Ready/valid backpressure accounts for the
   extra work; W512 does not imply acceptance of a payload beat every cycle.
6. Pipeline the probe-column lookup and fix completion buffering and context
   arbitration so small/fast searches also remain correct under backpressure.

`final_h5_c16_crc256` is a **separate optional exact-early-stop design**, not
the strict paper-faithful primary point. It exits only when a mask reaches
the provable global upper bound (all flags masked); otherwise it finishes
the exhaustive search. This returns the same answer, including tie breaks,
but changes the execution schedule and makes latency depend strongly on the
payload and flag positions. Its lower area must not be described as an
always-full-search implementation.

### Decoder: smaller circuitry for the same code

The decoder reuses the same exact mask recurrence. The shared BCH changes
exploit binary-code syndrome identities, represent finite-field squaring as
an XOR network, compress redundant syndrome storage, and factor common XOR
terms in the Chien evaluation network. The PBCH-specific leading-selector
optimization uses the fact that the first 13-bit selector beat starts from
zero syndrome state. None of these changes the code or correction capability.

Two verified decoder choices are retained:

- `compressedfirstchien`: original II 69 and E2E 171 cycles.
- `compressedgroupfirstchien`: share five GF multipliers across coefficient
  groups; retain II 69, but increase E2E to 203 cycles. Its lower replicated GE
  is the area-oriented choice. The extra 32 cycles are 106.67 ns at 300 MHz.

See [`decoder/README.md`](decoder/README.md) and
[`fwht/README.md`](fwht/README.md) for the algebra and individual ablations.

## Fair comparison and bandwidth accounting

Common changes are evaluated on BCH t=8, t=9, and t=27 as well. Candidate
screening compares **replicated** GE under the same historical input schedule,
not merely single-engine GE. Finalists are then remeasured with the corrected
ASAP input schedule; only those separately RTL/mapped-verified measurements
enter the final comparison. Not every rejected ablation is remeasured with
the ASAP driver. For example, in the original
common-driver ablation, sharing more BCHt9 BM multipliers reduces its
single-engine size but raises its measured interval from 69 to 76 cycles;
190 replicas then cost more than 173 of the larger engine.
That variant is therefore not selected. BCH encoders also receive an exact
CRC common-subexpression experiment.

The final comparison removes one unnecessary testbench input-idle cycle
after decoder START, uniformly across original PBCH and all selected designs.
This changes no hardware or synthesized area. The first input beat is now
accepted at START+1. The resulting sustained intervals are 68.5 cycles for
BCH t8 (alternating 68/69), 68 for BCH t9, 72 for BCH t27, and 69 for PBCH.
They require 172, 170, 180, and 173 decoder replicas, respectively. All selected
optimized variants have matching RTL/mapped-netlist metrics; grouped BCH t8's
alternation is additionally checked over 129 frames. Original PBCH uses RTL
for this remeasurement. `decoder/zero_bubble_results.csv` records these final
measurements; `decoder/results.csv` preserves the historical input schedule.

All totals use 512 useful payload bytes per codeword, 300 MHz, 12.8 GB/s writes,
and 384 GB/s reads:

```
payload throughput = 512 * 0.3 / II = 153.6 / II GB/s
encoder replicas   = ceil(12.8 / throughput)
decoder replicas   = ceil(384  / throughput)
total NAND2 GE     = single-engine NAND2 GE * replicas
```

PBCH throughput is measured on the **same 16,384-codeword workload** for the
original and optimized encoders: random payloads, independently flagged
positions with q=0.002, and 16 warm-up frames excluded from steady-state
intervals. This q is the flagged-cell probability (ideal probing at defect
RBER 10^-3), not the residual bit-error rate. Replica counts are conditioned
on this workload; they are not worst-case guarantees for every legal input.
The full-search C16 architecture still takes another histogram pass when a
codeword has more than 16 flagged cells. The exact-early-stop design has
additional data-dependent search time, so repeatedly encoding one easy
flag=8 word is not a valid substitute for the workload measurement.

The same isolated original reference words with 0, 8, and 32 flags are used to
report START-to-last-accepted-output latency. E2E and codeword interval are
distinct. Rerunning the unchanged original encoder with the new handshake
testbench gives 100/117/163 cycles; the old table's 115-cycle flag-8 figure came
from a different driver. The new table uses the common-driver 117-cycle
reference, not 115. Its original workload interval is 75.449 cycles, previously
displayed rounded to 75; the required replica count remains 7.

## Evidence and limits

- Complete encoder regression uses independent exhaustive software results,
  not only a second copy of the optimized RTL. Final points also receive
  mapped-netlist tests with input bubbles, long output stalls, overflow cases,
  recycled context IDs, and busy/ready/data-stability assertions.
- Decoder checks include all 33,554,432 selector/payload-mask bit combinations,
  exact BM locator/degree equivalence for t8/t9/t27, symbolic Chien-network
  equivalence, and full-decoder correctable and invalid-word regressions.
- Selected decoder mapped netlists also pass overlapping 129-frame stress
  tests. Initial mapped tests exposed a **testbench** START-acceptance race;
  holding START until a real clock-edge handshake resolved it without an RTL
  change. The old failure and corrected PASS logs are retained.
- Each selected synthesis has an immutable source snapshot and
  SHA256 manifest. This avoids attributing a later source edit to an earlier
  area report. Mapped simulation uses UMC functional models with zero cell
  delays; it is not post-layout/SDF timing signoff.
- All area reductions are actual UMC 28 nm synthesis measurements under the
  same 300 MHz constraints. There is no 3 nm area or clock extrapolation.
  Reported slack is pre-layout **maximum/setup** slack. The original flow's
  generic clock uncertainty also applies to hold; pre-layout hold violations
  remain and are not repaired by CTS/hold fixing in this study. Positive setup
  slack and functional gate simulation are not full physical timing closure.
- External replay/cache and write-context buffers remain excluded, matching
  the original hardware boundary. These totals are not a complete controller
  or base-die area estimate. Near-parity in provisioned total gates does not
  mean that a single PBCH encoder is as small as a single BCH encoder.
- The existing 32-flag cap and overflow reporting are unchanged. This work
  does not solve the system policy for overflow. At q=0.002,
  P[Bin(4213,q)>32] is approximately 1.095e-10. Treating every such event as an
  uncorrectable frame would contribute about 2.60e-14 to FER/n, above 10^-16;
  a reliability claim for the finite-cap hardware still needs a justified
  fallback/overflow policy. Neither the rare-event probability nor the
  workload-sized replica count is a proof of the paper's UBER target.

## Reproduce and inspect

Run commands from `paper_eval/` with the existing Synopsys/UMC environment.

```sh
python3 optim/decoder/summarize.py
python3 optim/decoder/summarize_zero_bubble.py
python3 optim/encoder/collect_results.py
# Use the selected names in optim/results/summary.json:
python3 optim/build_comparison.py --strict STRICT_ENCODER \
  --decoder compressedgroupfirstchien --fast-decoder compressedfirstchien

# Simulate the immutable sources used for the selected encoder synthesis:
python3 optim/encoder/run.py sim STRICT_ENCODER --snapshot --regression \
  --vectors 16384 --vec-dir optim/encoder/vectors/q002_long --tag q002_long \
  --check-busy
```

Each synthesis directory contains its timing/area reports and source evidence;
`encoder/results.csv`, `decoder/results.csv`, and `fwht/core_results.csv`
retain unsuccessful tradeoffs as well as winners. The original published
results are not overwritten by this optimization study.
