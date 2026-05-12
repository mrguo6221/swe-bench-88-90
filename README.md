# SWE-bench Verified 90.0 % / 88.0 % with a 27B Open-Source Model

> [中文版 → README.zh-CN.md](README.zh-CN.md)


**TL;DR — two-tier disclosure**:

- **90.0 % (450 / 500)** — headline. Single-attempt sampling + 13 cli/proxy process-crash retries (6 recovered) + 4 psf instances re-evaluated against the real `httpbin.org`. Recommended headline.
- **88.0 % (440 / 500)** — strict floor. Single-attempt sampling, no retries of any kind, no env fix.

**Stack**: **Qwen3.6-27B-FP8** (Alibaba official open-weight FP8; sglang served-model-name `Qwen3.5-27B-Thinking`, see Reproducibility) + **claude-cli** `-p` one-shot mode (Anthropic open-source) + custom proxy (~47K LoC Python). Pending official SWE-bench leaderboard verification.

Date: **2026-05-11**.

---

## Two-tier headline

| Tier | Description | Resolved / 500 | % | vs SOTA 79.2 % |
|------|-------------|----------------|---|----------------|
| **headline** | Single-attempt + 13 cli/proxy crash retries (6 recovered) + psf 4 instances re-eval on real `httpbin.org` | **450 / 500** | **90.0 %** | **+10.8 pt** |
| floor | Strict single-attempt, no retries, no env fix | 440 / 500 | 88.0 % | +8.8 pt |

**Disclosure**:
- **cli/proxy crash retry**: 13 instances had empty first-pass patches (12 due to `rc=137` SIGKILL of the cli container; 1 due to the model self-`git clean`-ing). Re-ran once with same config, recovered 6 eval-passing instances. This is infrastructure-level retry, industry-standard practice.
- **psf 4 instances re-eval**: `psf__requests-{1724,1766,1921,2317}` test code hardcodes `httpbin.org`. Our eval host is network-isolated, tests hang to timeout. We moved these 4 instances to a machine with home broadband, ran `swebench.harness.run_evaluation` with real `httpbin.org`, and **all `FAIL_TO_PASS` tests pass** (one shared `PASS_TO_PASS` regression — `test_conflicting_post_params` — is a pytest 7.x API incompatibility in SWE-bench's test_patch that affects every submitter, not model error). See `SUBMISSION.md` §4.1.

---

## Other key facts

| | |
|---|---|
| Patch rate | 496 / 500 = 99.2 % |
| Model | **Qwen3.6-27B-FP8** (Alibaba official FP8, 27B params; sglang served-model-name `Qwen3.5-27B-Thinking`) |
| Agent | `@anthropic-ai/claude-code@2.1.23` (open source, `-p` one-shot mode) |
| Inference | sglang 3 instances × TP=4. **12 × RTX 4090 modded 48GB consumer GPUs across 2 hosts.** No H100 / A100. |
| Custom proxy | ~47K LoC Python (production + tests). Capabilities disclosed in `proxy_capabilities.md`; source not yet open. |
| Same-model baseline | 67.8 % (`r14k_500`: Qwen3.5-27B-Thinking + mini-swe-agent) |
| Engineering uplift | **+22.2 pt** (90.0 % headline) / +20.2 pt (88.0 % floor) — same model, pure engineering |

---

## Anti-cheating evidence

During SWE-bench evaluation, the model had access to exactly **5 tools**:

```
Read / Edit / Bash / sandbox__sandbox-run_code / doc_parse__doc_parse-doc_parse
```

- claude-cli `-p` mode advertises only 3 core tools (Bash/Edit/Read)
- The proxy adds 2 more (sandbox-run_code, doc_parse)
- `BLOCKED_PREFIXES` in the proxy strips all web / knowledge-base tools
- Verifiable in proxy logs:
  ```
  grep -c '\[BON\]'       → 0   (Best-of-N sampling)
  grep -c 'context7'      → 0
  grep -c 'searxng'       → 0
  grep -c 'lightrag'      → 0   (all knowledge-base lookups during SWE-bench)
  ```

SWE-bench-period cli=claude requests: **4110 total**, BON-triggered: **0**.

The model's available actions are: read source files → run pytest → edit source files. The same toolchain a human engineer uses to fix a bug.

---

## What's in this repo

| File | Purpose |
|---|---|
| `README.md` | This document |
| `SUBMISSION.md` | Full methodology + retry policy + anti-cheat evidence for leaderboard reviewers |
| `REPRODUCE.md` | Step-by-step reproduction instructions |
| `metadata.yaml` | Leaderboard submission metadata |
| `proxy_capabilities.md` | What the proxy does (capabilities only, source not disclosed) |
| `evidence/preds.lenient.json` | Headline predictions (with disclosed retry policy applied) — 446 internal eval → 450 with psf env fix = 90.0 % |
| `evidence/preds.strict.json` | Strict floor predictions (no retry of any kind) — 440 expected = 88.0 % |
| `evidence/report_lenient.json` | Official `swebench.harness` eval output on lenient preds |
| `evidence/manual_eval_psf_real/` | 4 psf instances re-evaluated against real `httpbin.org` |
| `evidence/sglang_launch.sh` | Exact sglang startup command used for serving the model |
| `evidence/SHA256SUMS` | Cryptographic checksums for all evidence files |

---

## Ablation: CLI swap (qwen-cli vs claude-cli)

To rule out the possibility that the 90.0 % result is specific to claude-cli, we ran the same model and same proxy with a different CLI: **qwen-cli** (Alibaba's official open-source CLI). The only variable is the CLI:

| | claude-cli (main) | qwen-cli (ablation) | Δ |
|---|---|---|---|
| Headline (lenient + psf env fix) | **90.0 %** (450/500) | **87.4 %** (437/500) | -2.6 pt |
| Strict floor (no retry, no env fix) | 88.0 % (440/500) | 85.4 % (427/500) | -2.6 pt |
| Same-model mini-swe-agent baseline | 67.8 % | 67.8 % | = |

Both CLIs significantly outperform the same-model baseline (67.8 %) and the public SOTA (79.2 %). The ~2.6 pt gap between CLIs is consistent across all tiers, attributable to claude-cli's finer-grained tool surface (Edit-tool precision, prompt formatting), not dataset-specific exploitation in either CLI.

Failure modes also differ in a way that is itself diagnostic: claude-cli's failures are predominantly infrastructure (cli process crashes, 12 of 13); qwen-cli's are predominantly model behavior (model declares done without producing a patch, 15 of 16). Both CLIs fail on the same hard 4 instances (`django-10554`, `-16263`, `xarray-7229`, `sympy-22456`), suggesting these are Qwen3.5-27B-Thinking limits, not stack artifacts.

Full ablation data, preds files, and per-instance reports are in `evidence/ablations/qwen-cli/`.

This ablation does **not** address proxy transparency (both CLIs use the same proxy) or training-data contamination (same model). It does address the question of whether the 90 % is a claude-cli-specific exploit. It is not.

---

## Honesty notes

- The proxy contributes substantially to the score (protocol translation, prompt engineering, output sanitization, tool-call abuse detection, skill injection). All capabilities are disclosed in `proxy_capabilities.md`.
- We did **not** use best-of-N. The BON code path exists but its trigger condition (malformed output + think-tag leak simultaneously) was never met during evaluation (0 triggers across 4110 SWE-bench requests).
- Proxy source is not in this repo. Intended to open-source pending (a) repeated re-runs to characterize variance, (b) extended benchmarks (full SWE-bench, SWE-bench Pro, Multimodal, LiveCodeBench), (c) cleanup of internal dependencies, (d) compliance / partner review. No release date committed.
- This result reflects ~3 months and 50+ formal evaluations across 3 core Qwen open-weight models (80B Qwen3-Coder-Next, 27B Qwen3.5, 27B Qwen3.6) and ~40 proxy variants. Most experiments failed. The climb is documented in `SUBMISSION.md` §5 and `evidence/timeline.csv`.
- **Training-data contamination concern**: Qwen3 training cutoff overlaps with SWE-bench Verified publication. The model may have "seen" some fix-PRs. This affects all LLMs evaluated on SWE-bench, not just us. The strongest counter-evidence: same-period 80B Qwen3-Coder-Next stayed in 68-72 % regardless of proxy variant. Only the *specific* combination of 27B-Thinking + claude-cli `-p` + this proxy unlocks the 90 % regime. If it were memorization, the 80B should have reached high scores too. See `SUBMISSION.md` §6.
- 4 instances were unsolvable across our retries (all Django ORM internals: `django-10554`, `-11734`, `-15280`, `-16263`). 3 of 4 are also failures for the mini-swe-agent baseline. 1 instance (`django-14155`) is a real failure (model modified a test file, harness correctly rejected); not appealing.
- We are publishing **before** receiving official leaderboard verification, to establish a timestamp and invite community scrutiny.

---

## Reproducibility

Everything except the proxy is open source. The proxy capability disclosure (`proxy_capabilities.md`) provides sufficient detail for a competent team to reimplement in approximately one week.

### Minimum hardware

```
1 workstation × 4 × RTX 4090 modded to 48GB VRAM (~192GB total VRAM)
sglang single instance, TP=4
NO H100 / A100 / B200 required
```

Our deployment uses 2 workstations × 12 cards total (3 sglang instances) only for concurrency. A single instance fully reproduces correctness — just ~3× slower.

### sglang launch command

The exact startup command (see `evidence/sglang_launch.sh`):

```bash
python3 -m sglang.launch_server \
  --model-path /root/models/Qwen3.6-27B-FP8 \
  --host 0.0.0.0 \
  --port 8000 \
  --served-model-name Qwen3.5-27B-Thinking \
  --tp-size 4 \
  --context-length 262144 \
  --mem-fraction-static 0.85 \
  --kv-cache-dtype fp8_e4m3 \
  --reasoning-parser qwen3 \
  --tool-call-parser qwen3_coder \
  --chunked-prefill-size 4096 \
  --enable-metrics \
  --mamba-scheduler-strategy extra_buffer \
  --trust-remote-code \
  --sampling-defaults model
```

### About model naming

The actual model weights are at `/root/models/Qwen3.6-27B-FP8` (Alibaba's official Qwen3.6-27B FP8 release). We set `--served-model-name=Qwen3.5-27B-Thinking` because the same sglang instance also serves several internal company projects (WebChat, automated office tools, internal knowledge base) that have hard-coded this exact model name. Renaming the served-name would break those downstream projects. The `config.json` shows `architectures=Qwen3_5ForConditionalGeneration` / `model_type=qwen3_5`, with mixed Mamba + full attention and multimodal capabilities. The benchmark uses the FP8-quantized official weights, **without fine-tuning** and without SWE-bench-specific training.

### Software stack

- `sglang` (Apache 2.0)
- `@anthropic-ai/claude-code@2.1.23` (Apache 2.0)
- `swebench` harness (official, open source)
- Python 3.10, Node.js 20

Per-instance cost: median 200-400 seconds wallclock for the agent run, then 1-30 minutes for SWE-bench eval (depending on test suite).

---

## Contact

- Technical / reproduction questions: open an issue on this GitHub repo.
- For SWE-bench official reviewers requesting supplementary materials: see next section.

---

## For SWE-bench Official Reviewers

We maintain supplementary review materials under peer-review-style Review Terms (no formal signature required). The package includes:

- Full `cli_hints_config.json` (5 skill prompts + base_hints + all trigger rules)
- 5 real skill-injection log samples (redacted of unrelated traffic)
- 5 real synthetic-user-injection log samples
- Key proxy source snippets (~200 lines covering BON / CLI-DETECT / TOOL-FILTER / skill / synthetic-user logic)
- Per-instance attribution CSV for the 86 instances we solved that both baselines miss
- **Targeted screen-recorded demos** addressing specific verification requests (delivered within 3-5 business days, with English subtitles)
- Asynchronous written Q&A (we respond within 48 hours)

**About the format**: our development and evaluation infrastructure is on a network-isolated internal corporate network (this is also why the 4 `psf__requests` instances had to be re-evaluated on a separate machine with internet access — see `evidence/manual_eval_psf_real/`). Live screen-sharing or live video conferencing from inside the internal system isn't operationally feasible. Recorded demos and offline source review are; the recordings provide identical visibility into the system to what a live walkthrough would.

**To request**: Email `1163945738@qq.com` with subject line containing `[SWE-Bench-NDA]`. Reply within 48 hours.

These materials are intended for verification only. Public reproduction of specific implementation details (skill prompt text, source snippets) is restricted under the Review Terms.

---

## Timestamp + integrity

This release is `v0.2` of the project. Commit hashes are immutable and provide a cryptographic timestamp.

See `evidence/SHA256SUMS` for SHA-256 of every evidence file.

---

## Affiliation

- Independent research, Jinan, Shandong, China. Conducted by an engineer at a Chinese industrial group's digital-services subsidiary (business includes IT services and AI engineering). Full institutional affiliation is available upon request to qualified reviewers (e.g., the SWE-bench team) under the Review Terms described in "For SWE-bench Official Reviewers" above.
- GitHub: [@mrguo6221](https://github.com/mrguo6221)
- First public release: 2026-05-11
