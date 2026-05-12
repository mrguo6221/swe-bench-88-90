# qwen-cli ablation — psf__requests re-eval with real httpbin.org

Parallel to the main submission's `evidence/manual_eval_psf_real/`, this 
directory contains the 4 `psf__requests` instances re-evaluated against 
real `httpbin.org` on a separate host with internet access (s8845).

This is necessary because the eval host (s66) is on a corporate internal 
network without external internet access. The 4 psf instances' tests 
hardcode calls to `httpbin.org` and would otherwise time out on s66.

## Results (qwen-cli)

| Instance | Outcome |
|---|---|
| psf__requests-1724 | ✓ resolved |
| psf__requests-1766 | ✓ resolved |
| psf__requests-1921 | ✓ resolved |
| psf__requests-2317 | ✗ unresolved |

3 of 4 instances pass when run against real `httpbin.org`. The psf-2317 
failure with qwen-cli is a model-side issue (vs claude-cli, where the 
same instance had F2P-verified-standalone but the full run hung).

## Files

- `eval_report.json` — official `swebench.harness` output on these 4 instances
- `psf__requests-XXXX/` — per-instance: `patch.diff` (the model's patch), 
  `test_output.txt` (pytest output), `report.json` (per-instance result), 
  `run_instance.log` (execution log)
