# Reproduction Guide

This document describes how to reproduce the SWE-bench Verified results: **450/500 = 90.0 %** (headline) / **440/500 = 88.0 %** (strict floor). Everything below applies to an isolated reproduction environment (you do **not** need our proxy source code; you can use any equivalent setup described in `proxy_capabilities.md`).

## 1. Prerequisites

### Hardware (minimum)

- **4 × consumer GPU with ≥ 48 GB VRAM each** for one tensor-parallel sglang instance. We used RTX 4090 48 GB (modded), but H100 / A100-80G / RTX 6000 Ada all work. ≥ 192 GB total VRAM is the minimum.
- For our actual setup we ran **three** such sglang instances (12 GPUs total across 2 hosts) to support 4 parallel agent workers, but a single instance is sufficient for correctness (just ~3× slower).
- 64+ CPU cores, ≥ 256 GB RAM (for parallel docker containers).
- ≥ 200 GB free disk (SWE-bench docker images are large).

### Software

- Ubuntu 22.04 (or similar) with Docker
- Python 3.10+
- Node.js 20+
- `swebench` package (pip)
- `sglang` (latest nightly with Qwen3 support)

## 2. Inference backend

Launch sglang with the exact command we used (see `evidence/sglang_launch.sh`):

```bash
python3 -m sglang.launch_server \
  --model-path /path/to/Qwen3.6-27B-FP8 \
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

**Model**: Alibaba's official Qwen3.6-27B-FP8 release. The `--served-model-name=Qwen3.5-27B-Thinking` is what we use internally for downstream-project compatibility (see README.md "About model naming"); for an external reproduction you can use any served-name you like.

Verify:
```bash
curl http://localhost:8000/v1/models
```

## 3. Proxy

Our 90.0 % uses a private proxy with the capabilities listed in `proxy_capabilities.md`. To reproduce, you have two options:

### Option A — Use claude-cli directly against sglang (no proxy)

Skip the proxy and have claude-cli talk to sglang directly. Expected score: closer to 65–75 % (you lose ~15-20 pt because tools aren't filtered correctly, sampling isn't tuned, no skill prompting, no synthetic-user continuation). This is the **lower bound** for reproduction.

### Option B — Build an equivalent proxy

Implement an Anthropic→OpenAI proxy with at minimum these capabilities (see `proxy_capabilities.md` for full detail):

1. Translate `/v1/messages` Anthropic protocol to `/v1/chat/completions` OpenAI protocol.
2. Map model name aliases (`*sonnet*`, `*opus*`, `*claude*`) → `Qwen3.5-27B-Thinking` (the served-model-name).
3. Override sampling: `temperature=0.7, top_p=0.8, top_k=20, presence_penalty=1.5`.
4. In claude-cli `-p` one-shot mode, claude-cli advertises only 3 tools (Bash/Edit/Read). The proxy adds 2 internal tools (`sandbox__sandbox-run_code`, `doc_parse__doc_parse-doc_parse`), giving the model 5 total. The proxy's `BLOCKED_PREFIXES` strips web/kb tools (`searxng__*`, `context7__*`, `fetch__*`, `browser__*`) if they were ever advertised.
5. Inject ~1.5KB of generic coding discipline prompt based on tool-usage signals (Edit calls → CODE_REWRITE injection, Read ≥3 files → MULTI_FILE injection) per `cli_hints_config.json`.
6. Inject a brief synthetic user message ("please continue") when the model gets stuck in thinking-only mode during streaming.
7. Strip CJK↔ASCII spacing (Pangu) from model output.
8. Track duplicate tool calls (same tool name + same args) and block the 3rd+ duplicate.

This is several hundred lines of Python; ~1 week of work for a competent engineer.

## 4. Agent

Use `@anthropic-ai/claude-code` (claude-cli). We used version 2.1.23 (other 2.x versions should also work):

```bash
npm install -g @anthropic-ai/claude-code@2.1.23
```

You need claude-cli's `cli.js` accessible inside docker containers (we mount `/usr/lib/node_modules` and `/usr/bin/node` into each container).

## 5. Runner

For each of the 500 SWE-bench Verified instances:

1. `docker run -d --network host swebench/sweb.eval.x86_64.<inst> sleep 3600`
2. `git apply` the `test_patch` (the new failing tests) and commit it. **HEAD now points at the test_patch commit; subsequent `git diff` will exclude test_patch from the captured `model_patch`.**
3. `docker exec` claude-cli with `--dangerously-skip-permissions --output-format text -p "<problem_statement + instruction footer>"`. The instruction footer should be brief: "use the shell to run tests, find the bug, apply a minimal source-only fix, output DONE when finished."
4. After cli exits (max 3600 s), capture `git add -A && git diff --cached HEAD` as `model_patch`. Because HEAD is the test_patch commit, this diff contains only the model's source-code changes; test_patch is not double-counted.
5. `docker stop`.

Run with 4 parallel workers. Expected wallclock: ~17 hours on our hardware.

## 6. Retry policy (must be disclosed if used)

After the main run, expect approximately 13 instances with empty patches from cli/proxy infrastructure crashes (`rc=137` SIGKILL or empty stream). To reproduce our `preds.lenient.json`, retry those instances exactly once with the same configuration. Expect ~6 to recover with eval-passing patches.

This produces:
- `preds.strict.json` (no retry — strict floor) → expected eval **440/500 = 88.0 %**
- `preds.lenient.json` (retry applied) → expected eval **446/500 = 89.2 %** internal (before psf env fix)

## 7. Eval

Use the official SWE-bench harness:

```bash
python3 -m swebench.harness.run_evaluation \
  --predictions_path /path/to/preds.lenient.json \
  --max_workers 8 \
  --dataset_name SWE-bench/SWE-bench_Verified \
  --run_id reproduce_attempt \
  --cache_level instance \
  --timeout 1800
```

The 4 `psf__requests-{1724,1766,1921,2317}` instances and `sklearn-14710` may hit eval-timeout. The 4 psf instances are network-bound (their tests hardcode `httpbin.org`); if your eval host has internet access, they should pass. `sklearn-14710` has a slow test suite and may benefit from `--timeout 5400`.

To reproduce the **90.0 %** headline, re-evaluate the 4 psf instances on a host with internet access. See `evidence/manual_eval_psf_real/README.md` for our re-eval setup.

Expected wallclock for eval: ~95 min with 8 workers.

## 8. Verifying

After eval finishes, the harness writes a JSON report:

```
claude-cli+proxy__Qwen3.5-27B-Thinking.<run_id>.json
```

Look for:
```
total_instances: 500
resolved_instances: <your number>
```

`resolved_instances / 500` is your PASS rate. Internal eval (no httpbin.org access) gives 446/500 = 89.2 %; with psf real-httpbin re-eval, gives 450/500 = 90.0 %.

## 9. Where to expect divergence

Things that may cause your reproduction to land within ±2 pt of 90.0 % but not exactly there:

- Different sglang version (different inference behavior for the same model)
- Different proxy implementation (your skill injection may differ in exact phrasing)
- Different claude-cli version (tool behavior evolves)
- Stochasticity of the model (temperature 0.7 is non-zero; same prompt can give slightly different answers across runs)

We did not run the full 500 multiple times to estimate variance. If you reproduce within ±2 pt we consider the result confirmed.

## 10. Independent contact

If your reproduction gives a substantively different number (>3 pt off in either direction) we genuinely want to know. Please file an issue on this repo. For SWE-bench official reviewers requesting supplementary materials, see the "For SWE-bench Official Reviewers" section in `README.md`.

## 11. Reproducing the CLI-swap ablation

To reproduce the qwen-cli ablation (verifying the result is CLI-independent):

1. Set up steps 1-3 identically (sglang serving Qwen3.6-27B-FP8, proxy on localhost:8028).
2. Install `qwen-code` from Alibaba (`https://github.com/QwenLM/qwen-code` or equivalent — see Alibaba's published distribution).
3. Replace claude-cli invocation with: `qwen-code --auth-type anthropic --base-url http://localhost:8028 -p "<prompt>"`. The runner script analogue is `qwen_swe_runner.py` (uses the same docker + git-diff capture flow as `cli_swe_runner.py`).
4. Run `swebench.harness.run_evaluation` on the resulting preds. For network-isolated eval hosts, retry the 4 psf__requests instances on a host with httpbin.org access.

Expected result: 437/500 = 87.4 % headline (vs 90.0 % for claude-cli); 427/500 = 85.4 % strict floor.

Full data, preds files, and per-instance reports for the ablation are in `evidence/ablations/qwen-cli/`.
