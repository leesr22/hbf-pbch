# Exact compact FWHT experiments

`selector_search_fwht_compact.sv` preserves the selector-search interface and
the exact Walsh-Hadamard score, including the smallest numerical selector tie
break and the first-32-flags/overflow convention. The original RTL is untouched.

The optimization changes only the physical schedule of the FWHT:

* A block evaluates the low `HIGH_L` selector bits by a complete butterfly
  transform. The outer counter enumerates the high selector bits in increasing
  numerical order. Sparse input signs include the outer selector contribution.
* `CHUNK` parallel flag lanes accumulate the block input histogram. Every
  accepted flag is included; 32 flags take four histogram cycles at CHUNK=8.
* `EARLY_EXIT=1` stops on the first block whose best score equals the number of
  flags. That is the global upper bound. Earlier blocks contain only smaller
  selectors, and each block's max tree selects its smallest tied index, so the
  result is identical to a full exhaustive scan. If no perfect score exists,
  every block is evaluated. `EARLY_EXIT=0` always evaluates every block.
* `FUSE_INPUT=1` combines histogram addition and the first butterfly group into
  one combinational path, removing an input register bank, not a mathematical
  transform stage.
* Optional `MODULAR6=1` performs internal additions modulo 64. True scores are
  in [-32,32], so only +32 and -32 have the same six-bit residue. At either
  extreme there must be exactly 32 contributions and they must all have the same
  sign. The first flag's contribution therefore recovers the missing sign.
  Seven-bit exact scores are restored before comparison and output. This is
  lossless arithmetic, not saturation, and MAX_FLAGS remains 32.
* `HIST_STYLE` explores exact encodings of the same ternary histogram sum:
  0 is the original signed balanced tree; 1 uses twice the positive popcount
  minus the active popcount; 2 caches the active count per histogram bucket
  during flag loading (CHUNK=32 only); and 3 sums unsigned `contribution+2`
  values and subtracts `2*CHUNK`. Style 3 uses one balanced tree, without
  duplicating counters or introducing a new register bank. These alternatives
  change no FWHT input or selector decision. Their area benefit must be measured,
  rather than inferred solely from the source-level operator count.
* `DIRECT_STAGES=D` folds the first D butterfly stages into sparse histogram
  construction. A flag contributes to bucket `b` when its upper H-D label bits
  equal the upper H-D bits of b; its sign also includes the parity of the low D
  label bits AND the low D bits of b. This is exactly the state after D ordinary
  FWHT stages, so the remaining H-D butterfly stages produce the identical
  score vector. It reduces bucket comparators and initial butterfly adders,
  without omitting a candidate, changing the schedule, or using an approximate
  score. The implementation requires D<H, retaining butterfly stages. With
  HIST_STYLE=2, occupancy is cached per upper H-D-bit bucket and shared across
  its 2^D lanes, reducing the number of counters to 2^(H-D).

All synthesis points use the same UMC 28 nm SS 0.9 V 125 C library as the paper
baseline, a 3.333333333 ns clock, 0.20 ns uncertainty, 0.40 ns input/output delay,
and `compile_ultra -no_autoungroup`. NAND2 GE is area/0.504. Standalone core
results should not be substituted for whole-encoder results.

Reproduce a point:

```sh
python3 optim/fwht/generate.py --high 5 --chunk 8 --fuse 1 --mod6 1
bash optim/fwht/run_sim.sh fwht_h5_c8_e1_f1_m6
bash optim/fwht/run_synth.sh fwht_h5_c8_e1_f1_m6
```

Simulation initially compares 1,000 cases against independently computed full 8,192-point
FWHT scores and lowest-index argmax. Cases cover every flag count 0 through 33,
duplicate labels, all-positive/all-negative inputs, overflow, random ties,
256 random cases each for counts 0/8/32, and forced selector 8191 including a
score of +32. Simulation logs also report core search cycles.
The final cached C32 D3/D5 and C16 D5 regressions extend this to 1,002 cases,
adding constant spectra whose global maximum is -32 or +32. The original
1,000 vectors and cycle-distribution subsets are unchanged.

`estimate_workload.py` uses the actual pbch_paper mask matrix, random valid
encoded words and unique uniformly selected flag positions to estimate core
search and service cycles under Binomial(4213,0.002). It is a Monte Carlo cycle
model, not a full-encoder throughput simulation. The integrated frontend,
loading, output backpressure and context credit must be measured separately.
Early termination makes latency workload-dependent: count-8 average, the
workload distribution and the count-32 full-scan latency must stay distinct.

`collect_results.py` produces `core_results.csv` from completed DC reports and
VCS logs. Cycle statistics describe the SEARCH phase only, from finish to done,
not whole-codeword encoder latency. The separate core Monte Carlo estimate is
included for selecting candidates, not as a replacement for full-system RTL
measurements. `EARLY_EXIT=0` rows offer the strict always-full-exhaustive-search
control; these still have flag-count-dependent histogram cycles when CHUNK<32.

## Measured strict-search shortlist

All rows below perform the complete 8,192-candidate search. Areas are standalone
selector-core cell areas, not complete encoders. See `core_results.csv` and the
per-point `results/` reports for the full measured sweep.

| Core configuration | Area (µm²) | NAND2 GE | 300 MHz slack (ns) | SEARCH cycles, flags 0/8/32 |
|---|---:|---:|---:|---:|
| H7 C32, fused/mod6, signed histogram | 49,188.551737 | 97,596.33 | +0.0750432 | 65 / 65 / 65 |
| H7 C16, fused/mod6, signed histogram | 38,826.815852 | 77,037.33 | +0.0467656 | 65 / 65 / 129 |
| H7 C16, fused/mod6, biased histogram | 38,150.615838 | 75,695.67 | +0.0468450 | 65 / 65 / 129 |
| H7 C32, cached occupancy, D0 | 40,662.383804 | 80,679.33 | +0.0795441 | 65 / 65 / 65 |
| H7 C32, cached occupancy, D3 | 33,455.687785 | 66,380.33 | +0.0641878 | 65 / 65 / 65 |
| H7 C32, cached occupancy, D5 | 29,556.911766 | 58,644.67 | +0.0208671 | 65 / 65 / 65 |

The D5 cached core is 46.48% smaller than the original 55,222.6078 µm² grouped
FWHT core. It retains two butterfly stages and uses four shared occupancy
counters. The D3 and D5 cached cores pass the expanded 1,002-case regression.
Their positive slack is a pre-layout synthesis result, not a routed timing
guarantee. The complete encoder must independently meet timing and include
input scan, codeword buffers, output masking, and backpressure handling.

The early-exit alternatives remain separate options. They are mathematically
exact but workload-dependent; they must not be described as evaluating every
candidate on every frame. Full-encoder results live in the encoder experiment
directory and supersede standalone-core estimates for bandwidth provisioning.

## Final mapped-netlist audit: cached C32 D5 excluded

The cached-occupancy (`HIST_STYLE=2`) C32 D5 **full encoder is not a verified
candidate**. Its RTL regressions pass, but functional UMC-cell mapped-netlist
simulation reproducibly fails. The measured standalone area/timing above is
retained as experimental evidence, not a usable final hardware result. The
selected C16 D5 encoder does not use cached occupancy and passes its independent
mapped regression; its status is unaffected.

The original failing gate test and the corrected accepted-START testbench are
byte-identical. Re-running 256 mixed frames, random output backpressure, a
1,500-cycle output hold, input bubbles, and busy checks under the separate
`sim_accepted_gate` tag reproduces the first-frame failure at 6,202 ns:

```sh
python3 optim/encoder/run.py sim strict_piped_h7_c32_d5_crc128 \
  --regression --vectors 256 --vec-dir optim/encoder/vectors/mixed \
  --bp --hold 1500 --check-busy --input-bubbles --snapshot \
  --gate --tag accepted_gate
```

The read-only diagnostic in `gate_audit/` narrows the failure to initialization
of the mapped cached counters. On the first zero-flag frame, search START is
accepted at cycle 59 and FINISH at cycle 60. The mapped bucket counters' observed
low bits remain X after START (cycles 60--67), despite the RTL clear-on-START
assignment. The search best score becomes X at cycle 63, and search DONE at
cycle 126 returns an X selector and score. Consequently all 4,213 output bits
are X when the held output is consumed. This happens inside the search before
output backpressure is released; it is not an accepted-START or scoreboard
problem. The evidence establishes a mapped initialization/X-propagation failure,
not a numerical FWHT disagreement. Whether it is gate-level X pessimism from
feedback reconvergence or a physical reset/logic defect has not been proved.
No RTL, synthesis snapshot, or mapped netlist was changed to mask the issue;
the candidate remains excluded pending a separately verified fix.

Evidence: `../encoder/runs/strict_piped_h7_c32_d5_crc128/sim_accepted_gate/run.log`
and `gate_audit/diagnostic.log`. No additional synthesis was performed for this
audit.
