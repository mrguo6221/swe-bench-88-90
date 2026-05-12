# Ablation: CLI swap (qwen-cli vs claude-cli)

## Purpose

To rule out the possibility that our 90.0 % headline result is specific to claude-cli (i.e., a claude-cli-specific exploitation), we ran the same model and same proxy with a different CLI: **qwen-code** (Alibaba's official open-source CLI for the Qwen family; we refer to it as "qwen-cli" throughout this document and directory names as a generic shorthand).

The agent stack is the only variable:

| Stack | claude-cli (main submission) | qwen-cli (this ablation) |
|---|---|---|
| Model | Qwen3.6-27B-FP8 | Qwen3.6-27B-FP8 (same) |
| sglang served-name | `Qwen3.5-27B-Thinking` | (same) |
| Proxy | `localhost:8028` ~47K LoC | (same) |
| CLI | `@anthropic-ai/claude-code@2.1.23` in `-p` one-shot mode | `qwen-code` (Alibaba official, sometimes called qwen-cli) |
| Hardware | 12 × RTX 4090 modded 48GB across 2 hosts | (same) |
| Eval framework | `swebench.harness.run_evaluation` | (same) |

## Results

| Metric | claude-cli (main) | qwen-cli (this ablation) | Δ |
|---|---|---|---|
| **Strict floor** (no retry, no env fix) | 88.0 % (440/500) | **85.4 %** (427/500) | -2.6 pt |
| Strict + psf real-httpbin env fix | 88.8 % (444/500) | 86.0 % (430/500) | -2.8 pt |
| Lenient (with cli/proxy crash retry) | 89.2 % (446/500) | **86.8 %** (434/500) | -2.4 pt |
| **Headline** (lenient + psf real-httpbin) | **90.0 %** (450/500) | **87.4 %** (437/500) | **-2.6 pt** |
| Same-model mini-swe-agent baseline | 67.8 % (`r14k_500`) | (same) | — |
| Engineering uplift over baseline | +22.2 pt | +19.6 pt | -2.6 pt |

Both CLIs significantly outperform the same-model mini-swe-agent baseline of 67.8 %; the engineering uplift (+19.6 to +22.2 pt) is reproducible across two independent CLI backends from two different vendors. The ~2.6 pt gap between the two CLIs is consistent across all tiers, suggesting it is structural (driven by CLI tool-surface design) rather than dataset-specific.

## What this ablation supports

- The 90.0 % result is not specific to claude-cli. The engineering generalizes to a different CLI from a different vendor (Alibaba's qwen-code).
- Same proxy + same model + different CLI: both significantly clear public SOTA (79.2 %). The proxy's contribution is real and CLI-independent.
- The ~2.6 pt gap between the two CLIs is attributable to claude-cli's finer-grained tool surface (Edit-tool precision, prompt formatting, stricter tool-call discipline), not to dataset-specific exploitation in either CLI.
- Both CLIs fail completely on the same 4 instances (`django-10554`, `-16263`, `xarray-7229`, `sympy-22456`), suggesting these are model capability limits, not stack artifacts.

## What this ablation does not prove (and we don't claim it does)

- This does **not** address the proxy transparency concern. Both CLIs use the same proxy. If the proxy contained a SWE-bench-specific backdoor, both would benefit. Proxy source review remains available to qualified reviewers under Review Terms (see main `README.md`).
- This does **not** address training-data contamination. The same model checkpoint is used for both runs. The cleanest test for contamination is hold-out evaluation on post-training-cutoff benchmarks (planned: SWE-bench Pro when available).

## Failure-mode differences (diagnostic)

The two CLIs fail in different ways on the same problem set:

| Failure mode | claude-cli (main) | qwen-cli (ablation) |
|---|---|---|
| `rc=137` cli process crash (SIGKILL) | 12 | 1 |
| `rc=0` model declares done without producing a patch | 1 | 15 |
| Eval errors (network timeout, test-file modification) | 6 | 6 |

claude-cli's failures are predominantly infrastructure (cli process crashes); qwen-cli's failures are predominantly model behavior (the model declares the task complete without making changes — an agent-loop discipline issue, not a memorization symptom). This pattern is consistent with claude-cli's more disciplined tool-calling design under the `-p` mode.

The 4 instances both CLIs fail completely (`django-10554`, `django-16263`, `pydata__xarray-7229`, `sympy__sympy-22456`) suggest hard limits of Qwen3.5-27B-Thinking on those particular problems, not stack artifacts.

## Retry policy applied symmetrically

For qwen-cli we applied the same single-retry policy as the main claude-cli submission:

- claude-cli: 13 instances retried, 9 produced patches, 6 passed eval
- qwen-cli: 16 instances retried, 12 produced patches, 7 passed eval

The retry-pass rate is comparable (~58-66 % across both CLIs). This is a uniform infrastructure-recovery policy, not a CLI-specific advantage.

## Reproduction

This ablation is reproducible by anyone with the same hardware:

1. Serve `Qwen3.6-27B-FP8` via sglang exactly per `evidence/sglang_launch.sh`.
2. Run the same proxy on `localhost:8028` (capability described in `proxy_capabilities.md`).
3. Use `qwen-code` (Alibaba's official CLI) instead of claude-cli, pointing at the same proxy. Set `ANTHROPIC_BASE_URL=http://localhost:8028` and `--auth-type anthropic`.
4. Run `swebench.harness.run_evaluation` on the resulting preds. For network-isolated eval hosts (like ours), retry the 4 psf instances on a host with `httpbin.org` access (see `manual_eval_psf_real/`).

## Files in this directory

- `preds.lenient.json` — final preds for qwen-cli with retry applied
- `preds.strict.json` — initial run only, no retry (= the baseline for strict-floor comparison)
- `report.lenient.json` — official `swebench.harness` output (constructed from main eval + retry eval), 434 resolved
- `report.strict.json` — official `swebench.harness` output on the initial run, 427 resolved
- `manual_eval_psf_real/` — 4 `psf__requests` instances re-evaluated against real `httpbin.org` (parallel to the main submission's `evidence/manual_eval_psf_real/`)
- `retry_log/` — `runner.log` (the 16 retry instances runtime) + `eval.log` (the 12 retry-eval runtime)
