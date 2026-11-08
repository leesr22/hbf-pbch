# HBF BCH/PBCH hardware

This repository contains the ECC RTL used for the HBF read-disturbance
hardware evaluation.

- [`bch/`](bch/): frozen BCH reference and reliability-matched BCH design
- `pbch/`: will be added after the PBCH encoder architecture is finalized

The BCH and PBCH releases are kept in separate directories so that their RTL,
simulation collateral, and synthesis reports can be reviewed independently.
