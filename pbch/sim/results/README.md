# Recorded simulation results

- `fwht_search_h7_96cases.log`: exact selector/score comparison against direct exhaustive search
- `encoder_w256_random_backpressure.log`: integrated encoder with randomized output backpressure
- `encoder_w256_no_backpressure.log`: integrated encoder throughput run
- `decoder_w64_pipeline.log`: 25-frame cache-buffer-replay decoder pipeline run

All checked logs contain the corresponding `PASS` marker. Re-run them with
`../run_regression.sh`.
