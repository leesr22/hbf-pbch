# Exact PBCH decoder optimization experiments

All experiments target PBCH `k=4096,t=8,l=13`, the **original frozen mask
matrix**, `W=64`, and UMC 28 nm at 300 MHz. The supplied FWHT encoder's code
construction and exhaustive selection objective are unchanged. Every new file
lives in this directory; the original RTL and generators are preserved.

## Selected measured results

Every row below is directly mapped at 300 MHz, not an area extrapolation.
This historical table uses a driver that adds one empty input cycle after
accepted START (first input beat at START+2). `II` is the measured accepted-START
interval with that input schedule and no backpressure, and E2E is the
isolated accepted START to the final accepted payload beat. At 300 MHz a cycle
is 3.333 ns. Replicas meet the 384 GB/s payload-read target.

| Decoder | NAND2 GE | II (cycles) | E2E (cycles / ns) | Replicas | Total GE | Setup slack (ns) |
|---|---:|---:|---:|---:|---:|---:|
| Original PBCH t8,l13 | 63,697.332 | 70 | 172 / 573.3 | 175 | 11,147,033 | +0.6855 |
| PBCH, same latency (`compressedfirstchien`) | 43,994.666 | 70 | 172 / 573.3 | 175 | 7,699,067 | +0.7881 |
| PBCH, best tested total gates (`compressedgroupfirstchien`) | 42,309.332 | 70 | 204 / 680.0 | 175 | 7,404,133 | +0.7881 |
| Fair BCH t8 (`fair_group_t8`) | 40,665.333 | 69 | 202 / 673.3 | 173 | 7,035,103 | +0.7449 |
| Fair BCH t9 (`fair_chien_t9`) | 47,339.666 | 69 | 174 / 580.0 | 173 | 8,189,762 | +0.6798 |
| Fair BCH t27 (`fair_chien_t27`) | 165,676.997 | 73 | 250 / 833.3 | 183 | 30,318,890 | +0.4739 |

The final PBCH decoder reduces gates by **33.58%** while retaining the same
bandwidth and replica count. Its cost is 32 additional latency cycles
(106.7 ns), not reduced throughput. If latency must remain unchanged, the
alternative still saves **30.93%**. Fair BCH t9 also has a smaller-instance
grouped candidate (45,156.332 GE), but its 76-cycle steady interval requires
190 copies and **8,579,703 total GE**, so the non-grouped choice above wins.
Likewise, grouped t27 with three BM lanes needs 178,953.330 GE per engine and
184 engines (average II 73.5), totaling 32.927 MGE, worse than the non-grouped
choice. The two-lane grouped schedule maps to 152,967.664 GE, has average II 110,
and needs 275 engines (42.066 MGE); it is also worse than the selected variant.
These are decoder-only figures; the encoder must be added before comparing
complete ECC provisions. All ablations and t27 trials are in `results.csv`.

The selected source top is `pbch_dec_compressedgroupfirstchien.sv`, with its
hierarchy specified in `synth.tcl`. Complete reports and immutable pre-synthesis
source snapshots are in `runs/compressedgroupfirstchien/`. The original PBCH
reference is the repository's `results/paper_hardware/blocks_300mhz_common_width.csv`.

## Corrected ASAP input timing (separate measurements)

The original pipeline testbench waited for an extra negative edge after START
was deasserted before presenting input beat zero. Removing that *testbench*
idle cycle puts the first accepted codeword beat at START+1. No RTL, mapped
netlist, synthesis constraint, clock frequency, or stream format changes.
The historical table and `results.csv` above remain intact for provenance.
`zero_bubble_results.csv` is the separate, checked measurement set.

| Decoder | II (cycles) | E2E (cycles / ns) | Replicas | Decoder total GE |
|---|---:|---:|---:|---:|
| Original PBCH | 69 | 171 / 570.0 | 173 | 11,019,638 |
| PBCH, same latency | 69 | 171 / 570.0 | 173 | 7,611,077 |
| PBCH, selected grouped BM | 69 | 203 / 676.7 | 173 | 7,319,515 |
| Fair BCH t8 | 68.5 (alternating 68/69) | 201 / 670.0 | 172 | 6,994,437 |
| Fair BCH t9 | 68 | 173 / 576.7 | 170 | 8,047,743 |
| Fair BCH t27 | 72 | 249 / 830.0 | 180 | 29,821,859 |

Each row passes 25 overlapping codewords. Every latency is constant; START gaps
are constant except grouped BCH t8, whose 68/69-cycle alternating gaps have a
68.5-cycle sustained average. All four selected optimized decoders also pass the same sequence
using their actual mapped UMC netlists; every metric and sampled timeline is
identical to RTL. The unchanged-latency PBCH alternative is mapped-checked as
well. Original PBCH uses RTL for this additional timing measurement.
The alternating grouped-BCH-t8 schedule is also checked over **129 overlapping
frames** in both RTL and mapped gates (`pipeline_fast129`); all 128 gaps follow
68,69 exactly, and every accepted-START-to-output latency remains 201 cycles.

The accepted-edge timeline below is relative to the first accepted START:

| Decoder | START | First input | Last input | Next START | First payload output | Last payload output |
|---|---:|---:|---:|---:|---:|---:|
| Original PBCH / same-latency optimized | 0 | 1 | 67 | 69 | 108 | 171 |
| Selected PBCH | 0 | 1 | 67 | 69 | 140 | 203 |
| Selected BCH t8 | 0 | 1 | 66 | 68 | 138 | 201 |
| Selected BCH t9 | 0 | 1 | 66 | 68 | 110 | 173 |
| Selected BCH t27 | 0 | 1 | 70 | 72 | 186 | 249 |

The cycle after the last input beat captures the completed syndrome and clears
syndrome-busy; the next START is accepted one edge after that. Thus the remaining
two-edge gap from last input to next START is a circuit constraint, not the
removed driver bubble. Grouped BCH t8 additionally needs one downstream-pipeline
stall on alternate frames, giving the measured 68/69-cycle pattern. The table
shows the first frame's timeline, not that longer second interval.
Replay remains a separate ready/valid stream, with the
same deterministic response schedule in RTL and mapped measurements.

Reproduce with `bash optim/decoder/run_sim.sh VARIANT pipeline_fast` and
`bash optim/decoder/run_gate_sim.sh VARIANT pipeline_fast` (mapped selected
variants), then `python3 optim/decoder/summarize_zero_bubble.py`.
All evidence lives in distinct `build/VARIANT_pipeline_fast/` and
`build/VARIANT_gate_pipeline_fast/` directories; no earlier logs are overwritten.

## Changes and ablations

- `direct`: reproduce the original mask matrix with a 32-bit linear recurrence.
  The frozen xorshift32 seed62 matrix has recurrence polynomial `0x10486f801`.
  There are **no zero-column replacement exceptions** for this particular
  `l=13` matrix. This is an alternative circuit for the *same* matrix, not a
  new length-13 LFSR code construction.
- `cse`: common-subexpression extraction in that recurrence's XOR network.
- `directload`, `cseload`: initialize recurrence state directly from the
  corrected selector beat. Payload beats are always 64 bits, as in the existing
  wrapper; therefore their unnecessary per-bit count gating is removed.
- `shared`: use one set of `T+1` GF multipliers for three BM phases. This is
  equivalent to the original inversionless algorithm; the extra BM cycles do
  not limit the existing 70-cycle decoder interval, but add 16 cycles to E2E.
- `binary`: binary-code syndromes satisfy `S_(2j)=S_j^2`, and odd-numbered BM
  discrepancies are zero. Use three phases for even iterations and one phase
  for odd iterations, preserving the original `4T` BM cycles and **exact**
  inversionless locator scaling.
- `compact`: also use a `2T`-word circular syndrome history instead of the
  `T+1`-word history plus `2T-1`-word future registers. Wrapped history values
  at negative indices multiply zero locator coefficients. Expose `lambda_q`
  as the completed locator; the parent controller already prevents reuse until
  that result is consumed, so a duplicate output register bank is unnecessary.
- `linear`: express finite-field squaring as its XOR-only linear map instead
  of a generic multiplication with identical operands.
- `compactlinear`: combine compact BM and linear squaring.
- `compressed`: additionally buffer only the independent odd syndromes at the
  syndrome stage output, deriving even values combinationally. The buffered
  odd values remain stable until the next result, preserving the handshake.
- `csechien` and names ending in `chien`: exact GF(2) common-subexpression
  extraction across the Chien evaluation matrix. Selection depends on measured
  synthesis area/timing, not on a logical XOR-count estimate.
- `compressedfirst`: additionally exploit the PBCH-only stream invariant that
  the 13-bit leading selector is the first beat, so its prior syndrome is zero.
  A simulation assertion guards that protocol assumption.
- `compressedtrim`: omit the unused Chien next-state transform after the final
  partial parity beat. The legal stream format is unchanged and asserted.
- `compressedchain4`, `compressedchain8`: exact small-alpha Chien recurrences
  within groups of four/eight parallel lanes, bounding combinational depth.
- `compressedgroupchien`: time-share five GF multipliers across two coefficient
  groups in the compact binary BM core. Its BM work takes 64 instead of 32
  cycles, but the PBCH frame interval remains 70 cycles. E2E rises from 172 to
  204 cycles. This is an explicitly reported area/latency tradeoff.
- `compressedfirstchien`, `compressedgroupfirstchien`: final combinations that
  also include the PBCH-specific leading-selector specialization. The former
  retains the original latency; the latter uses the five-multiplier schedule.
- `compressedfirstfast` and `fair_fast_*`: an exploratory syndrome-final-capture
  change saves one E2E cycle. It does **not** improve the interval with the
  existing driver and is not claimed as a throughput improvement.

Except for the PBCH mask recurrence/preload and leading-selector specialization,
these are **shared BCH optimizations**. A fair final comparison must apply the selected shared changes
to BCH `t=8,t=9,t=27` as well, using each code's needed BM lane count.

## Direct synthesis

`bash optim/decoder/run_synth.sh VARIANT` runs one actual Design Compiler job,
using at most two cores, `compile_ultra -no_autoungroup`, 0.20 ns clock
uncertainty and 0.40 ns input/output delays. Logs, area hierarchy, timing,
checks and mapped netlists are retained in `runs/VARIANT/`.

`python3 optim/decoder/summarize.py` collects only completed measurements into
`results.csv`. NAND2 GE uses the existing reference area 0.504 um². Payload
throughput is `512 bytes × 300 MHz / II`; decoder provisioning is the ceiling
of 384 GB/s divided by that throughput. The cache/replay storage boundary is
identical to the original comparison.

`fair_compressed_t*` applies compact BM and compressed syndromes to BCH.
`fair_chien_t*` additionally applies the same Chien CSE to each BCH code's own
matrix. `fair_group_t*` additionally shares multipliers across two coefficient
groups; `fair_group3_t27` has three BM lanes instead of two. The grouped tradeoff
must be ranked by **total GE after replication**, not by single-circuit GE:
BCH t9's steady interval rises to 76 cycles; t27 with two lanes averages 110,
and with three lanes averages 73.5. Pipeline latencies may vary under queueing.
The CSV reports isolated E2E as well as minimum/maximum pipeline E2E and obtains
steady II from the final 12 measured intervals (whole scheduling periods).

## Verification

- The mask generator checks the recurrence against all 4096 original columns.
- VCS checks **all 8192 selectors at all 4096 payload positions** (33,554,432
  bit comparisons per implementation), with stalls, for direct, CSE, and
  final selector-preloaded CSE representations (`build/cseload_unmask/run.log`).
- Full decoder stress vectors cover 144 frames, randomized selectors/messages,
  errors 0–8 including selector errors, input bubbles and output backpressure.
- The 25-frame pipeline regression measures every initiation interval. Grouped
  t27 schedules are additionally measured over 257 frames, confirming their
  steady 74/146 or 73/73/74/74 interval patterns.
- Final PBCH variants and selected BCH t8/t9 variants additionally pass 129
  overlapping frames with simultaneous input bubbles and long backpressure
  bursts, exercising filled inter-frame context buffers.
- `validate_chien_networks.py` symbolically reconstructs every generated CSE
  output and compares its complete GF(2) linear map with the reference. This
  covers every possible locator value for PBCH and BCH t8/t9/t27, not only the
  sampled decoder vectors.
- BM equivalence compares the **complete locator polynomial and degree**, not
  only decoded correctable messages, against the original RTL for 1000 sets
  each at `t=8,t=9,t=27`. These include actual binary error patterns 0–`2t+5`
  and random odd syndromes with Frobenius-consistent even syndromes.
- Full decoder cycle equivalence also covers 144 frames containing 0–64 errors
  and entirely random invalid words. It compares controls, valid output bits,
  selectors, success/failure, error counts and backpressure against the
  original complete decoder, so beyond-`t` behavior is preserved.
- Grouped BM also passes exact locator/degree tests at t8, t9, and t27. A
  replay-aligned full decoder comparison lets the original wait for the slower
  candidate before replay, then compares accepted payloads, selector, status,
  and error counts on the same 144 invalid-word cases. This is functional,
  not latency-equivalence, verification.
- Selected mapped netlists are simulated with the UMC standard-cell Verilog
  models, zero functional delays, and timing checks disabled. This validates
  synthesis functionality, **not** post-layout timing or SDF signoff.
- A separate 25-frame no-stall mapped run directly confirms II/E2E for all
  four selected decoders: BCH t8 69/202, t9 69/174, t27 73/250, and PBCH 70/204.
  These logs are `build/VARIANT_gate_pipeline/run.log`.
- Both final PBCH mapped netlists also pass replay-aligned comparison against
  the original RTL on all 144 invalid-word cases, including errors 0–64 and
  random invalid words. This preserves beyond-correction-capability behavior,
  not just successful error correction.
- Selected BCH t8/t9/t27 and final PBCH mapped netlists also pass 129 overlapping
  frames with simultaneous input bubbles and long output stalls. The streaming
  testbench holds START and data valid until actual rising-edge acceptance;
  an earlier `wait(start_ready)` followed by a fixed pulse could react to a
  combinational delta-cycle glitch in a mapped netlist and falsely time out.
  That driver issue was corrected, and the RTL and gate-level stress metrics
  agree. The failing historical log and subsequent pass logs are retained.

Simulation logs are in `build/VARIANT_MODE/run.log` and
`build/bm_equiv_tT/run.log`. Gate-level overlapping stress logs from the final
validation are also retained as `build/VARIANT_gate/pipeline_stress_pass.log`.
The t27 run uses `build/fair_chien_t27_gate_pipeline_stress/run.log`.
The unchanged-latency candidates retain 70 cycles between codewords and 172
cycles from accepted START to the final payload beat.
