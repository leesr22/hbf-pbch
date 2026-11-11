# HBF BCH/PBCH hardware

This repository contains the ECC RTL used for the HBF read-disturbance
hardware evaluation.

- [`bch/`](bch/): selected BCH reference and reliability-matched BCH design
- [`pbch/`](pbch/): exact-FWHT PBCH encoder and cache-buffer-replay decoder

The BCH and PBCH releases are kept in separate directories so that their RTL,
simulation collateral, and synthesis reports can be reviewed independently.

## Evaluation point

- Clock/process: 250 MHz, UMC 28 nm 0.9 V slow library
- Write-path target for encoders: 12.8 GB/s
- Read-path target for decoders: 384 GB/s
- Payload: 4096 bits (512 B) per codeword
- Area: pre-layout standard-cell area
- Decoder storage: external cache-buffer replay

The earlier 3.072 TB/s common target is no longer the primary provisioning
point. Encoder and decoder replication now follow their respective HBF write
and read paths.

| Configuration | Encoder area | Decoder area | Total replicated area |
|---|---:|---:|---:|
| BCH(k=4096, t=8) | 0.009 mm2 | 4.280 mm2 | 4.289 mm2 |
| BCH(k=4096, t=30) | 0.028 mm2 | 27.120 mm2 | 27.148 mm2 |
| PBCH(k=4096, t=13, l=13) | 0.718 mm2 | 9.234 mm2 | 9.952 mm2 |

All selected encoders use W=512 and all selected decoders use W=128.  The
decoder BM lane count is balanced to code strength: one lane for BCH(t=8),
four lanes for BCH(t=30), and two lanes for PBCH(t=13,l=13).

The PBCH encoder throughput point uses eight retained flags per codeword. The
RTL supports 0--32 retained flags; if more than 32 are observed, it keeps the
first 32 in codeword order and asserts a truncation flag.

## Result figures

- [`reports/figures/ecc_hardware_results_common_width.png`](reports/figures/ecc_hardware_results_common_width.png): complete hardware-result table
- [`reports/figures/ecc_replicated_area_common_width_28nm.png`](reports/figures/ecc_replicated_area_common_width_28nm.png): total replicated area at 28 nm
- [`reports/figures/ecc_replicated_area_common_width_3nm.png`](reports/figures/ecc_replicated_area_common_width_3nm.png): scaled total replicated area at 3 nm
- [`reports/figures/ecc_single_engine_area_common_width_28nm.png`](reports/figures/ecc_single_engine_area_common_width_28nm.png): one encoder plus one decoder at 28 nm
- [`reports/figures/ecc_single_engine_area_common_width_3nm.png`](reports/figures/ecc_single_engine_area_common_width_3nm.png): scaled one-encoder/one-decoder area at 3 nm

The PNG and SVG versions can be regenerated from the checked synthesis CSVs:

```bash
python3 scripts/plot_common_width_results.py
```
