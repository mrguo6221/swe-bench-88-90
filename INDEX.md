# Repository index

| File | Purpose |
|---|---|
| `README.md` | Project homepage (English, default). Two-tier disclosure 90.0 % / 88.0 %, anti-cheat evidence, reproducibility, contact. |
| `README.zh-CN.md` | Chinese version (same content). |
| `SUBMISSION.md` | Full methodology for leaderboard reviewers: anti-cheat (§0), system config (§1), per-instance flow (§2), retry policy (§3), eval results (§4), 3-month journey (§5), proxy gray-area disclosure (§6), honest caveats (§7), what we do NOT claim (§8), Appendix A — 86-instance recovery deep dive vs gold patches. |
| `REPRODUCE.md` | Step-by-step reproduction instructions for independent verification. |
| `metadata.yaml` | SWE-bench leaderboard submission metadata (model, agent, inference, scores per tier). |
| `proxy_capabilities.md` | What the custom proxy does (capability disclosure only; source code not released). |
| `evidence/preds.lenient.json` | Headline predictions — applies full retry policy. swebench.harness gives 446/500 internal; combined with `manual_eval_psf_real/` → 450/500 = **90.0 %**. |
| `evidence/preds.strict.json` | Strict-floor predictions — no retry of any kind. Expected eval = 440/500 = **88.0 %**. |
| `evidence/report_lenient.json` | Official `swebench.harness.run_evaluation` output on lenient preds. |
| `evidence/manual_eval_psf_real/` | 4 psf__requests instances re-evaluated against real `httpbin.org` (eval host is network-isolated). All FAIL_TO_PASS tests pass. |
| `evidence/sglang_launch.sh` | Exact sglang startup command. |
| `evidence/SHA256SUMS` | SHA-256 checksums for every evidence file. |
| `evidence/ablations/qwen-cli/` | CLI swap ablation — same model + same proxy + qwen-cli instead of claude-cli. 87.4 % headline (vs 90.0 % for claude-cli, -2.6 pt). Confirms result is not claude-cli-specific. Reviewer-facing files (parallel to the main `evidence/*`): |
| `evidence/ablations/qwen-cli/README.md` | Ablation methodology, results table, failure-mode comparison, reproduction. |
| `evidence/ablations/qwen-cli/preds.lenient.json` | qwen-cli headline preds (with retry applied). |
| `evidence/ablations/qwen-cli/preds.strict.json` | qwen-cli strict-floor preds (initial run only, no retry). |
| `evidence/ablations/qwen-cli/report.lenient.json` | Official `swebench.harness` output on lenient preds — 434/500 resolved. |
| `evidence/ablations/qwen-cli/report.strict.json` | Official `swebench.harness` output on initial run — 427/500 resolved. |
| `evidence/ablations/qwen-cli/manual_eval_psf_real/` | 4 `psf__requests` instances re-evaluated against real `httpbin.org` (parallel to the main `manual_eval_psf_real/`). |
| `evidence/ablations/qwen-cli/retry_log/` | `runner.log` (16 retry instances) + `eval.log` (12 retry evals). |
| `evidence/ablations/qwen-cli/SHA256SUMS` | SHA-256 checksums for ablation evidence files. |
| `evidence/timeline.csv` + `timeline_chart.txt` + `experiment_journey.md` | 3-month experiment chronology. |

## What is NOT in this repo

The release on 2026-05-11 is intentionally minimal — focused on the academic submission. The following are intentionally out of scope for this release:

- Community-facing announcements (long-form blog posts, social-media threads, video scripts, media outreach kits, formal review-request email packages) — will be published in follow-up releases over the coming weeks, after community review and stakeholder coordination.
- Full proxy source code — see `proxy_capabilities.md` for the capability disclosure that is sufficient for independent re-implementation.
- The supplementary review materials available to SWE-bench official reviewers (full `cli_hints_config.json`, skill / synthetic-user injection log samples, ~200 lines of key proxy source, 86-instance attribution CSV, optional video walkthrough). Reviewers can request these via the channel listed in `README.md` ("For SWE-bench Official Reviewers" section).
