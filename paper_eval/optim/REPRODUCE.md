# Reproducing the selected optimization

Run these commands from the repository's `paper_eval/` directory. The
published reports, source snapshots, and pass/fail logs are evidence of the
original runs; the commands below put new synthesis outputs in separate
directories. Do not replace archived source snapshots to make their hashes
match edited scripts.

## Environment

Python 3 with NumPy is needed for vector generation; Matplotlib is needed for
the comparison figure. Synthesis and simulation additionally require your
licensed Synopsys Design Compiler and VCS installations, and licensed UMC
28 nm library files. Those tools, PDK files, compiled simulator binaries,
and mapped netlists are not distributed here.

The original runs used DC Q-2019.12-SP5-5, VCS R-2020.12-SP1-1, and
`um28nchslogl35hsl140f_ssgwc0p9v125c.db`. Keep the same library/corner to
compare the published gate counts; another library may produce different
results. License settings are inherited from your shell, not replaced by
the runners.

```sh
export DC_BIN=/path/to/dc_shell-xg-t
export VCS_BIN=/path/to/vcs
export HBF_ECC_TARGET_LIBRARY=/path/to/um28nchslogl35hsl140f_ssgwc0p9v125c.db
export HBF_ECC_CELL_MODEL=/path/to/um28nchslogl35hsl140f.v
```

If tools are on `PATH`, `DC_BIN` and `VCS_BIN` can be omitted. Historical
encoder JSON files retain original absolute paths as provenance; the live
runner rebases their `/paper_eval/` suffix onto the current checkout. The
historical snapshot manifests and their checksums are not rewritten.

To check the distributed measurements/provenance and redraw the published
figure without EDA tools or private netlists:

```sh
python3 optim/verify_published.py
python3 optim/build_comparison.py --from-csv
```

## Encoder vectors and RTL checks

The large hexadecimal vector arrays are regenerable and need not be stored
in Git. This command preserves the checked-in testbench and generates the
same 16,384-frame workload used by the final comparison:

```sh
python3 optim/encoder/gen_regression.py --vectors-only --count 256 \
  --workload-count 2048 --long-workload-count 16384
```

`q002_long` uses NumPy binomial seed 20261118 and payload/position seed
20261119. Each position is independently flagged with probability 0.002;
the generated binomial count is followed by a uniformly selected subset of
that size. `mixed` covers flag counts 0–33, and `legacy_timing` preserves the
original isolated examples with 0, 8, and 32 flags. Expected codewords are
computed by an independent full software FWHT, with model cross-checks.

```sh
python3 optim/encoder/run.py sim strict_piped_h7_c16_d5_crc128 \
  --snapshot --regression --vectors 16384 \
  --vec-dir optim/encoder/vectors/q002_long --tag reproduce_q002_long \
  --check-busy

python3 optim/encoder/run.py sim strict_piped_h7_c16_d5_crc128 \
  --snapshot --regression --vectors 256 \
  --vec-dir optim/encoder/vectors/mixed --tag reproduce_stress \
  --bp --hold 1500 --input-bubbles --check-busy

python3 optim/encoder/run.py sim strict_piped_h7_c16_d5_crc128 \
  --snapshot --regression --vectors 3 \
  --vec-dir optim/encoder/vectors/legacy_timing --tag reproduce_isolated \
  --isolated --check-busy
```

Use `strict_piped_h7_c16_crc128` for the conservative seven-inner-butterfly
alternative, or `final_h5_c16_crc256` for the separately reported exact
early-stop implementation. Use `reference` without `--snapshot` for the
unchanged original encoder. The final throughput excludes 16 warm-up frames
and uses all remaining intervals, not only one easy flag-8 example.

## Separate encoder synthesis and mapped verification

```sh
python3 optim/encoder/run.py syn strict_piped_h7_c16_d5_crc128 \
  --run-root optim/reproduction/encoder

python3 optim/encoder/run.py sim strict_piped_h7_c16_d5_crc128 \
  --run-root optim/reproduction/encoder --snapshot --gate --regression \
  --vectors 256 --vec-dir optim/encoder/vectors/mixed --tag mapped_stress \
  --bp --hold 1500 --input-bubbles --check-busy
```

The first command refuses to overwrite completed synthesis evidence. For
another run choose a fresh output root. The second command is zero-delay
functional simulation of the newly mapped netlist, not SDF timing signoff.

## Decoder synthesis and final ASAP timing checks

The final table uses the corrected first-beat-at-START+1 driver. The older
`pipeline` mode deliberately remains available to reproduce the historical
one-bubble measurements. Both modes use the same circuit.

```sh
export DEC_RUN_ROOT="$(pwd)/optim/reproduction/decoder"
export DEC_BUILD_ROOT="$(pwd)/optim/reproduction/decoder_sim"

bash optim/decoder/run_synth.sh compressedgroupfirstchien
bash optim/decoder/run_sim.sh compressedgroupfirstchien pipeline_fast
bash optim/decoder/run_gate_sim.sh compressedgroupfirstchien pipeline_fast

DEC_PIPELINE_FRAMES=129 bash optim/decoder/run_sim.sh \
  compressedgroupfirstchien pipeline_stress
DEC_PIPELINE_FRAMES=129 bash optim/decoder/run_gate_sim.sh \
  compressedgroupfirstchien pipeline_stress
```

Repeat for `compressedfirstchien` to retain the original decoder latency.
The fair BCH decoder choices are `fair_group_t8`, `fair_chien_t9`, and
`fair_chien_t27`; run the same commands for each. For BCH t8 additionally
run `DEC_PIPELINE_FRAMES=129` with mode `pipeline_fast129` to observe its
alternating 68/69-cycle intervals. The original PBCH timing reference is
`bash optim/decoder/run_sim.sh original pipeline_fast` (RTL only).

The above pipeline vectors under `vectors/study/` are already tracked. For
the additional 144-frame PBCH functional-equivalence regression:

```sh
python3 optim/decoder/gen_vectors.py
python3 optim/decoder/gen_full_equiv.py
bash optim/decoder/run_sim.sh compressedgroupfirstchien functional
bash optim/decoder/run_gate_sim.sh compressedgroupfirstchien functional
```

## Fair BCH encoders

The generated CSE RTL is included. Use a new suffix to preserve the
published runs, for example:

```sh
python3 optim/bch_encoder/run.py syn 9 --suffix _reproduction
python3 optim/bch_encoder/run.py sim 9 --suffix _reproduction
python3 optim/bch_encoder/run_pipeline.py rtl 9 --suffix _reproduction
python3 optim/bch_encoder/run_pipeline.py gate 9 --suffix _reproduction
```

Repeat for t=8 and t=27. The pipeline checks compare 128 deterministic
payloads both without stalls and with random output stalls.

## Scope of reproducibility

The selected result uses 300 MHz synthesis constraints, useful payload
throughput, and workload-conditioned replication. The [main report](README.md)
explains internal CRC sharing, exact FWHT stage folding, the 32-flag cap,
overflow-policy limitation, exclusion of external buffers, and pre-layout
setup/hold limitations. A successful functional regression does not imply
physical timing closure. Failed candidates, including cached C32/D5, must
not be promoted merely because their synthesis status is PASS.
