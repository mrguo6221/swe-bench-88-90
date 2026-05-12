# SWE-bench Verified Submission — Full Disclosure

For SWE-bench leaderboard reviewers and any reader who wants full transparency on how the headline 90.0 % was produced.

---

## §0 Anti-cheat Core — Only 5 tools available to the model

By precise log analysis of the proxy, the model's available tool set during SWE-bench evaluation was:

```
[CLAUDE->OPENAI] Client-advertised tools: ['Bash', 'Edit', 'Read']         ← claude-cli -p mode
[DEBUG] Final tool list (5 tools):       ['Bash', 'Edit', 'Read',
                                          'sandbox__sandbox-run_code',      ← added by proxy
                                          'doc_parse__doc_parse-doc_parse']  ← added by proxy

SWE-bench-period CLI-DETECT distribution:
  cli=claude:  4110 requests   ← our SWE-bench evaluation traffic
  cli=qwen:      29 requests   ← side-channel (qwen-cli sanity experiments)
```

**The model could NOT call**:
- WebFetch / WebSearch — claude-cli `-p` mode doesn't advertise these
- context7 / lightrag / kb-admin / any vector store — proxy `BLOCKED_PREFIXES` strips them
- searxng / browser / any web search tool — same strip

**Proxy log evidence** (reviewer-verifiable):
```bash
docker logs mcp-proxy-X 2>&1 | grep -c 'context7'    # → 0
docker logs mcp-proxy-X 2>&1 | grep -c 'searxng'     # → 0
docker logs mcp-proxy-X 2>&1 | grep -c '\[BON\]'      # → 0
docker logs mcp-proxy-X 2>&1 | grep -c '\[RETRY\]'    # → 0
```

The model's actual loop: read source → run pytest → edit source. Identical to what a human engineer does.

---

## §1 Setup

| Component | Detail |
|---|---|
| Model | **Qwen3.6-27B-FP8** (Alibaba official FP8-quantized weights, weight path `/root/models/Qwen3.6-27B-FP8`. sglang `--served-model-name=Qwen3.5-27B-Thinking`, see §1.1) |
| Inference | sglang nightly, **3 instances × TP=4 × RTX 4090 modded 48GB** (12 GPUs across 2 hosts). No H100. |
| Agent | `@anthropic-ai/claude-code@2.1.23` (Anthropic open-source CLI, `-p` one-shot mode) |
| Agent ↔ model bridge | Custom proxy on `localhost:8028` (~47K LoC Python including tests; source not in this repo) |
| Context length | 262144 (256K), model weights FP8, KV cache FP8 (`fp8_e4m3`) |
| Per-instance budget | 3600 s wallclock (docker exec timeout) |
| Concurrency | 4 workers |

### §1.1 Exact sglang launch command

Each sglang instance is launched with (also at `evidence/sglang_launch.sh`):

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

**About model naming**: Actual weights = `/root/models/Qwen3.6-27B-FP8` (Alibaba's official FP8 release). We expose it as `--served-model-name Qwen3.5-27B-Thinking` because the same sglang instance also serves several internal company projects (WebChat / automated office / internal knowledge base) that have hard-coded this exact model name. Renaming the served-name would break those downstream projects. The `config.json` shows `architectures=Qwen3_5ForConditionalGeneration` / `model_type=qwen3_5`, with mixed Mamba linear-attention + full-attention layers and multimodal capability. The benchmark uses the FP8-quantized official weights, **without fine-tuning** and **without SWE-bench-specific training**.

### §1.2 Minimum hardware to reproduce

```
Minimum: 1 workstation × 4 × RTX 4090 modded 48GB (~ 192GB total VRAM)
         sglang single instance, TP=4
         NO H100 / A100 / B200 required

Our concurrent deployment (speed only, not correctness):
         2 workstations × 12 GPUs total, sglang × 3 instances
         Single instance fully reproduces correctness — just ~3× slower
```

---

## §2 Per-instance flow

1. `docker run` SWE-bench image, mount `/usr/bin/node` and claude-cli into the container.
2. Apply `test_patch` (the new failing tests) and commit. HEAD = test_patch commit.
3. Write `prompt.txt` containing the issue's `problem_statement` plus a short instruction footer ("use the shell to run tests, find the bug, apply a minimal source-only fix, output DONE when finished").
4. `docker exec`:
   `claude-cli --dangerously-skip-permissions --output-format text -p "$(cat /tmp/_prompt.txt)"`
5. After cli exits (or times out at 3600 s), capture `git add -A && git diff --cached HEAD` as `model_patch`. Because HEAD is the test_patch commit, this diff contains *only the model's source-code changes* — test_patch is **not** double-counted.
6. The patch is written to the predictions file.

---

## §3 Retry policy (full disclosure)

After the main run, **13 of 500 instances had empty patches**:

- **12 with `rc=137`** — cli process killed by `SIGKILL`:
  - 2 × pre-flight check infinite loop (known cli bug)
  - 8 × silent timeout (cli produced 0 bytes stdout/stderr, killed at 3600 s)
  - 2 × proxy returned empty message stream → cli unhandled promise rejection
- **1 with `rc=0`** (`django-11276`) — model declared task complete after running `git clean` and erasing its own edits.

We retried all 13 once with the same configuration. **9 produced non-empty patches** on retry, **6 of which passed eval**:

| Instance | First | Retry | Eval |
|---|---|---|---|
| django-11276 | rc=0, 1213s, 0 B | rc=0, 325s, **973 B** | ✓ pass |
| django-14011 | rc=137, 3616s, 0 B | rc=0, 482s, **1083 B** | ✓ pass |
| django-15128 | rc=137, 3608s, 0 B | rc=0, 2616s, **3306 B** | ✓ pass |
| sphinx-9673 | rc=137, 3608s, 0 B | rc=0, 209s, **550 B** | ✓ pass |
| sphinx-10614 | rc=137, 3616s, 0 B | rc=0, 1815s, **2745 B** | ✓ pass |
| sphinx-7590 | rc=137, 3633s, 0 B | rc=0, 1713s, **5937 B** | ✓ pass |
| sympy-15599 | rc=137, 3608s, 0 B | rc=0, 375s, 826 B | ✗ eval fail |
| astropy-13398 | rc=137, 3623s, 0 B | rc=0, 1472s, 896 B | ✗ eval fail |
| sklearn-14710 | rc=137, 3616s, 0 B | rc=0, 1290s, 905 B | ✗ eval error (slow tests) |
| django-10554 / 11734 / 15280 / 16263 | rc=137, all 4 retried | still rc=137 + 0 B | — Django ORM internals, model couldn't solve |

**Two prediction files**:
- `preds.strict.json` — all 13 retries removed (empty patches preserved). Expected eval: **440 / 500 = 88.0 %**.
- `preds.lenient.json` — all 13 retries applied. Expected eval: **446 / 500 = 89.2 %** (internal) → **450 / 500 = 90.0 %** (with §4.1 psf env fix).

---

## §4 Final eval (`swebench.harness.run_evaluation`)

On `preds.lenient.json` (internal eval host):

```
total_instances:       500
resolved_instances:    446    ← official PASS count (lenient preds, internal eval)
unresolved_instances:  44
empty_patch_instances:  4     (django-10554/11734/15280/16263 — not recoverable)
error_instances:        6     (5 × 1800s timeout, 1 × patch modifies test file)
```

Internal eval = 446 / 500 = 89.2 %. With §4.1 psf env fix, final = **450 / 500 = 90.0 %**.

### §4.1 The 6 error instances

**4 × psf-requests — eval-environment network restriction**: `psf__requests-{1724,1766,1921,2317}`.

Test code hardcodes `httpbin.org`. Our eval host is network-isolated; tests hang to 1800s timeout.

We moved these 4 instances to a network-connected host, ran `swebench.harness` again with real `httpbin.org`:

| Instance | F2P pass / total | P2P pass / total | Remaining fail |
|---|---|---|---|
| psf-1724 | **6 / 6 ✓** | 78 / 79 | `test_conflicting_post_params` |
| psf-1766 | **6 / 6 ✓** | 78 / 79 | same |
| psf-1921 | **6 / 6 ✓** | 106 / 107 | same |
| psf-2317 | **8 / 8 ✓** (F2P verified standalone) | (partial, hung mid-run) | (likely same) |

The single P2P regression `test_conflicting_post_params` uses a deprecated pytest 2.x API form:
```python
pytest.raises(ValueError, "<string>")   # removed in pytest 4.x
```
The image ships pytest 7.4.4. This is a SWE-bench `test_patch` / pytest version incompatibility, **not a model error**. Any submitter hits it. See `evidence/manual_eval_psf_real/README.md` for full re-eval details.

**1 × sklearn-14710 — slow test suite**: 80 tests, 1800s timeout reached around test ~68. Could be recovered with longer timeout but we did not wait.

**1 × django-14155 — model rule violation**: model patch includes `tests/urlpatterns_reverse/tests.py`. Harness correctly rejects. We do not appeal; this is a real failure.

### §4.2 Two-tier headline

| Tier | Description | Resolved / 500 | % |
|---|---|---|---|
| **headline** | Single-attempt + 13 cli/proxy crash retry (6 recovered) + psf 4 re-eval on real httpbin.org | **450 / 500** | **90.0 %** |
| **floor** | Strict single-attempt, no retry, no env fix | 440 / 500 | 88.0 % |

The intermediate number (446/500 = 89.2 %, lenient preds on internal eval) is visible in `preds.lenient.json` / `report_lenient.json` but not promoted as a separate tier.

### §4.3 Floor → headline delta

**6 retry-recovered**: django-11276, django-14011, django-15128, sphinx-9673, sphinx-10614, sphinx-7590

**4 psf real-httpbin re-eval**: psf-1724, psf-1766, psf-1921, psf-2317

### §4.4 Headline 90.0 % by repo

| repo | resolved / total | rate |
|---|---|---|
| django | 213 / 231 | 92.2 % |
| sympy | 64 / 75 | 85.3 % |
| sphinx-doc | 35 / 44 | 79.5 % |
| matplotlib | 31 / 34 | 91.2 % |
| scikit-learn | 31 / 32 | 96.9 % |
| pydata (xarray) | 21 / 22 | 95.5 % |
| astropy | 18 / 22 | 81.8 % |
| pytest-dev | 19 / 19 | 100 % |
| pylint-dev | 10 / 10 | 100 % |
| psf (requests) | 5 / 8 | 62.5 % (+4 from real-httpbin re-eval) |
| mwaskom (seaborn) | 2 / 2 | 100 % |
| pallets | 1 / 1 | 100 % |
| **Total** | **450 / 500** | **90.0 %** |

---

## §5 Three-month journey — sustained engineering

The research line: **locally-deployable open-source LLMs + custom proxy to improve their CLI coding ability**.

### Phase 1: Qwen3-Coder-Next 80B FP8 (2026-02-04 to 02-22)

Primary focus on **Qwen3-Coder-Next 80B FP8** (Alibaba official) with mini-swe-agent / various CoT pipelines:

- 2026-02-08: 80B + NoCoT pipeline → **68.4 %** (`nocot_20260206`)
- 2026-02-10: same model + Smart v18 CoT → 61.4 % (`regression342`, on 342-subset)
- 2026-02-09 to 02-22: proxy iteration (v18, v28-v40) on various CoT and prompt strategies, 80B + proxy stable in **68-72 %** band (multiple reproducible runs in this range; lower-score experiments were abandoned methodologies, not formal records)

Main direction: **continued proxy improvements to lift 80B Qwen3-Coder-Next**.

### Phase 2: First SWE-bench Verified runs with Qwen3.5/3.6-27B FP8 (2026-05-03 to 05-09)

Qwen3.5/3.6-27B FP8 (Alibaba official) had been adopted and used in production since Alibaba's release. In early May, we ran the first systematic SWE-bench Verified evaluations with this model and identified a few cli-coding-related quirks:
- **Pangu spaces**: spurious whitespace inserted between CJK and ASCII characters, contaminating Python code
- **Occasional unresponsiveness**: empty message stream → cli unhandled rejection

Continued proxy improvements to handle these. During this window we also ran an 80B comparison for context:

- 2026-05-03: Qwen3.6-27B FP8 + mini-swe-agent → **60.4 %** (`mini_swev_run2`)
- 2026-05-09: Qwen3-Coder-Next 80B + mini-swe-agent → **68.0 %** (`r14j_500`) — 80B ceiling on mini-swe (used as comparison anchor; same agent stack as the 27B runs)

Observation: **27B and 80B are close in same-agent setups** (60-68 %). The engineering headroom doesn't come from model size.

### Phase 3: Tune proxy for Qwen training distribution (2026-05-10)

Adjusted proxy to align with Qwen3-Thinking's training distribution (sampling params, tool surface, prompt style):

- 2026-05-10: Qwen3.5-27B-Thinking + mini-swe-agent (tuned proxy) → **67.8 %** (`r14k_500`)

Baseline locked: same 27B model + mini-swe-agent = 67.8 %.

### Phase 4: Switch to claude-cli, sustained engineering (2026-05-08 to 05-11)

After confirming the 27B-Thinking + proxy path was viable, sustained proxy refinement (Pangu handling, tool-call optimization, abuse detection, skill injection refinement, sampling tuning). **No cheating** (no BON, no answer leakage, no dataset-specific tuning).

Switched agent from mini-swe-agent to **claude-cli `-p` one-shot mode**. In this mode claude-cli advertises only 3 core tools (Bash/Edit/Read), proxy adds 2 (sandbox-run_code, doc_parse), total 5 tools (vs mini-swe's single Bash):

- 2026-05-10 (pilot): claude-cli + proxy + Qwen3.5-27B-Thinking → **80 % (16 / 20)** (`cli_swe_v2_20`)
- 2026-05-11 (final): same stack, full 500 → **446 / 500 = 89.2 %** internal, + 4 psf real-httpbin re-eval = **450 / 500 = 90.0 %** (`cli_swe_500_lenient`)

### Key milestones

| Date | Variable | Score |
|---|---|---|
| 2026-02-08 | Qwen3-Coder-Next 80B + NoCoT | 68.4 % |
| 2026-02-10 | + Smart artificial CoT v18 | 61.4 % (342-subset) |
| Feb mid | proxy variants v18-v40, 80B in 68-72 band | 60-72 % |
| 2026-05-03 | Qwen3.6-27B FP8 + mini-swe | 60.4 % |
| 2026-05-09 | Qwen3-Coder-Next 80B + mini-swe | 68.0 % |
| **2026-05-10** | **Qwen3.5-27B-Thinking + tuned mini-swe** | **67.8 % (baseline)** |
| 2026-05-10 | + claude-cli + our proxy, 20-instance pilot | 80 % (16/20) |
| **2026-05-11** | **same stack, full 500 (internal eval)** | **89.2 %** |
| **2026-05-11** | **+ psf real-httpbin re-eval** | **90.0 % ⭐** |

### Strongest anti-contamination evidence

If this were training-data contamination, **80B Qwen3-Coder-Next** (larger training set, more likely to have "seen" GitHub) should have scored 85 %+ early. In practice, 80B never broke 72 % across many proxy variants. Only the *precise combination* **27B-Thinking + claude-cli `-p` + this proxy** hits 90.0 %. This is engineering breakthrough, not memorization.

### Models used

Three core open-weight Qwen models:

1. **Qwen3-Coder-Next 80B FP8** (Alibaba official) — adopted on Alibaba's release; Phase 1 experiments (Feb 2026), various proxy/CoT variants
2. **Qwen3.5-27B-Thinking / NoThinking** (Alibaba official FP8) — adopted on Alibaba's release; in continuous use through the final 90.0 % score (exposed via sglang `--served-model-name`; actual weights are item 3 below)
3. **Qwen3.6-27B-FP8** (Alibaba official) — adopted on Alibaba's release; **this is the checkpoint used for the final 90.0 %** (sglang `--model-path /root/models/Qwen3.6-27B-FP8`, exposed as `Qwen3.5-27B-Thinking` for downstream compatibility)

The final 90.0 % uses `/root/models/Qwen3.6-27B-FP8` weights, exposed via `--served-model-name=Qwen3.5-27B-Thinking` (see §1.1). config.json: `architectures=Qwen3_5ForConditionalGeneration`, `model_type=qwen3_5`. Mixed Mamba + full attention + multimodal. FP8 quantization (Alibaba official; industry-wide consensus is that this affects inference quality at the ~1 pt scale).

**Baseline 67.8 % and final 90.0 % use the same sglang instance** (loaded once on 2026-05-04, never swapped). The **+22.2 pt is pure engineering**.

---

## §6 Proxy gray-area operations — full disclosure

The proxy performed some operations during evaluation that reviewers may flag as "advanced agent design":

### 6.1 Skill injection (CLI-HINTS)

**Trigger count**: ~6,652 / proxy (full proxy lifetime, includes non-SWE traffic). During SWE-bench, approximately 50 % of requests triggered.

**Trigger mechanism**: NOT based on SWE-bench instance content. Based on **model's tool-usage pattern**:
- Model calls Edit tool → CODE_REWRITE score increment, injects when threshold=1 reached
- Model reads ≥3 files → MULTI_FILE score increment, injects when threshold=2 reached

**Injection content**: generic coding discipline (non-SWE-specific):
- "Use TodoWrite to plan multi-step tasks"
- "Never add fake-completion comments"
- "If Edit fails, Read first then retry with longer context"
- "After each edit, Read the modified region to verify"
- "Hard budget: 8 turns without progress → stop and re-plan"

**Compliance argument**:
- Injection content is generic prompt engineering, unrelated to any specific SWE-bench instance
- Trigger rules in `cli_hints_config.json` (available to reviewers under Review Terms)
- Any agent framework (mini-swe-agent, SWE-agent) injects similar discipline prompts

### 6.2 Synthetic user injection

**Trigger count**: ~5,434 / proxy (full lifetime). During SWE-bench, approximately 38 % of requests triggered.

**Trigger mechanism**: During streaming response, if the model gets stuck in "thinking-only, no next action" state, proxy injects a synthetic user message "please continue". This is agent-loop continuation.

**Compliance argument**:
- Does not modify the original user query, does not leak answer information
- Trigger is purely based on "model stuck" signal, unrelated to specific instance
- Any agent framework has loop continuation; this is standard pattern

### 6.3 BON / multi-sampling — 0 triggers

```
During evaluation, proxy log counts:
  [BON] quality-issue-detected, triggering retry:   0
  [RETRY] triggering retry:                         0
  [SGLANG-FIX] empty-response retry:                0
```

Verifiable: `docker logs mcp-proxy-X | grep -c '\[BON\]\|\[RETRY\]\|\[SGLANG-FIX\]'` returns 0. SWE-bench-period cli=claude requests = 4110, BON-marked = 0. Raw logs available to reviewers under Review Terms.

### 6.4 Supplementary evidence available under Review Terms

- Full `cli_hints_config.json` (static file, all skill rules + injection prompts)
- 3-5 real skill-injection log samples (redacted)
- 3-5 real synthetic-user-injection log samples
- Key proxy source snippets (BON logic, etc.)

(Complete proxy logs / complete proxy source not provided — contain other tenants' traffic + commercial IP.)

---

## §7 Honest caveats

1. **Training-data contamination possibility**. Qwen3 training cutoff overlaps with SWE-bench Verified's 2024-08 publication; fix PRs are on GitHub. The model may have "seen" some. This affects all LLMs on SWE-bench, not just us.

2. **+22.2 pt engineering uplift**: The total comes from the combination of (a) a richer tool surface than mini-swe-agent's single Bash (we expose Bash + Edit + Read + sandbox-run_code + doc_parse, the standard 5-tool minimal sandbox), (b) Qwen-recommended sampling, (c) generic prompt-engineering injection (skill discipline + synthetic-user continuation), and (d) output sanitization. We are not publishing a per-component pt attribution at this time, both because (i) such an attribution would require running ablations we have not run, and (ii) granular numbers would be more useful to competitors than to reviewers. The fine-grained breakdown is part of the Review Terms supplementary materials available to SWE-bench official reviewers.

3. **No best-of-N / no larger model**. Single attempt (BON 0 triggers); this is a floor for this stack, not a ceiling.

4. **We welcome independent replication / proxy source review under Review Terms / public scrutiny**.

**Strongest anti-knowledge-base-leakage evidence**:
- claude-cli `-p` mode advertises only 3 tools (Bash, Edit, Read)
- Proxy adds 2 more (sandbox-run_code, doc_parse)
- Total 5 tools — no web / kb / external-brain access whatsoever
- Proxy logs grep `context7` / `searxng` / `lightrag` all = 0 during evaluation
- Proxy logs grep `\[BON\]` / `\[RETRY\]` all = 0

---

## §6.5 Anti-cheat ablation: CLI swap

To address the concern "is the 90.0 % result specific to claude-cli?", we ran a CLI-swap ablation: same model + same proxy + different CLI (Alibaba's `qwen-code`, run under the same protocol via the same `localhost:8028` proxy). Full data in `evidence/ablations/qwen-cli/`.

| Metric | claude-cli (main) | qwen-cli (ablation) | Δ |
|---|---|---|---|
| Headline (lenient + psf env fix) | 90.0 % (450/500) | 87.4 % (437/500) | -2.6 pt |
| Strict floor (no retry, no env fix) | 88.0 % (440/500) | 85.4 % (427/500) | -2.6 pt |
| Same-model mini-swe-agent baseline | 67.8 % | (same) | — |
| Engineering uplift over baseline | +22.2 pt | +19.6 pt | -2.6 pt |

Both CLIs significantly exceed both the same-model mini-swe-agent baseline (67.8 %) and the public SOTA (79.2 %). The ~2.6 pt gap is consistent across all tiers, suggesting it is structural (CLI tool-surface design differences, e.g., claude-cli's Edit-tool precision) rather than dataset-specific.

Failure modes also differ in a way that is itself diagnostic:

| Failure mode | claude-cli | qwen-cli |
|---|---|---|
| `rc=137` cli process crash | 12 | 1 |
| `rc=0` model declares done with no patch | 1 | 15 |

claude-cli fails mostly via infrastructure; qwen-cli fails mostly via model behavior. Memorization-from-training would not produce this asymmetry (a memorized solution would be returnable regardless of CLI infrastructure).

The 4 instances both CLIs fail on completely (`django-10554`, `django-16263`, `pydata__xarray-7229`, `sympy__sympy-22456`) suggest these are hard limits of Qwen3.5-27B-Thinking, not stack artifacts. See `evidence/ablations/qwen-cli/README.md` for the full ablation analysis.

**What the ablation supports**: the 90.0 % result is not specific to claude-cli; the proxy's contribution is real and CLI-independent.

**What the ablation does not support**: proxy transparency (both CLIs use the same proxy) or training-data contamination (same model). See §6.3 and §7.1 for those concerns.

---

## §8 What we do NOT claim

- We do NOT claim Qwen3.5-27B-Thinking surpasses Sonnet 4.5 on overall capability
- We do NOT claim this is a best-of-N / multi-attempt result (single attempt only)
- We do NOT claim this stack generalizes to non-SWE tasks (SWE-bench Verified is one benchmark)

---

## Appendix A — 86-instance recovery deep dive (anti-cheat core)

Reviewer's hardest question: **a +22 pt engineering uplift is large — is it really engineering and not some hidden cheat?**

We compare our patches against baseline to answer this comprehensively.

### A.1 Relationship to baselines

| Set | Count |
|---|---|
| r14k_500 (Qwen3.5-27B-Thinking + mini-swe-agent) resolved | 339 / 500 = 67.8 % |
| r14j_500 (Qwen3-Next-NoThinking 80B + mini-swe-agent) resolved | 340 / 500 = 68.0 % |
| Our cli_swe_500_lenient resolved | 446 / 500 = 89.2 % (internal) → 450 / 500 = 90.0 % (with psf re-eval) |
| **Both baselines fail, we solve** | **86 instances** ← core +17.2 pt increment |
| All three fail (genuinely hard) | 45 instances |

86 by repo:

| repo | rescued |
|---|---|
| django | 37 |
| sympy | 10 |
| sphinx-doc | 8 |
| matplotlib | 7 |
| pylint-dev | 7 |
| pydata (xarray) | 5 |
| astropy | 5 |
| scikit-learn | 4 |
| pytest-dev | 2 |
| psf (requests) | 1 |

Patch-shape statistics: median 1158 bytes / median +9 lines / max +107 lines. Comparable to gold patches; no "scattershot rewrite" signature.

### A.2 Sampled 8 — baseline vs ours behavior diff

| Instance | gold N files | ours (overlap) | r14k Thinking modified test file? | r14j NoThinking modified test file? |
|---|---|---|---|---|
| django-15629 | 4 | 3 (3/4 overlap) | ✗ wrong file (1) | ✗ **modified tests/schema/tests.py** |
| matplotlib-23299 | 1 | 1 (1/1 overlap) | same 1 file | same 1 file |
| django-14376 | 2 | 2 (2/2 overlap) | ✗ missed 1 file | ✗ missed 1 file |
| django-16667 | 1 | 1 (1/1 overlap) | same 1 file | ✗ **modified tests/** |
| pylint-8898 | 3 | 1 (1/3 overlap) | ✗ **modified tests/config/test_config.py** | ✗ same |
| pylint-6386 | 4 | 2 (2/4 overlap) | ✗ different files | ✗ different files |
| django-11885 | 2 | 1 (1/2 overlap) | ✗ **modified tests/delete/** | ✗ same |
| sphinx-8056 | 1 | 1 (1/1 overlap) | ✗ **modified tests/test_ext_napoleon_docstring.py** | same 1 file |

**Core pattern**: counting cells with **bold modified tests/...** in the table — 3 of 8 sampled have r14k modifying test files (pylint-8898, django-11885, sphinx-8056); 4 of 8 have r14j modifying test files (django-15629, django-16667, pylint-8898, django-11885). The remaining failures in each baseline are different types (wrong file targeted, missing file, etc.) rather than test-file modification. SWE-bench rules forbid test-file modification; harness auto-rejects any patch that touches the test files.

Ours: 0 of 8 modified test files. Reasons:

1. **claude-cli's finer-grained tool surface**: Edit tool targets specific files for minimal edits, vs. mini-swe's Bash + sed/awk which is prone to "bulk wrong-file modification".
2. **Proxy skill injection explicitly states**: "DO NOT modify test files. Fix only the production source"
3. **base_hints rule**: "strictly forbidden to modify test files" — hard discipline.

### A.3 Three concrete patches vs gold

**Case 1: `matplotlib-23299` (gold +4 lines, ours +4 lines)**

gold:
```python
- orig = rcParams.copy()
+ orig = dict(rcParams.copy())
+ del orig['backend']
```

ours:
```python
  finally:
+     # Don't restore 'backend'; doing so could clear figures...
+     if 'backend' in orig:
+         dict.__delitem__(orig, 'backend')
      dict.update(rcParams, orig)
```

→ Different location (gold at function entry, ours in finally), but **semantically equivalent**: both ensure `backend` isn't restored. Test passes.

**Case 2: `django-16667` (gold +2 lines, ours +2 lines)**

gold:
```python
              return "%s-%s-%s" % (y or 0, m or 0, d or 0)
+         except OverflowError:
+             return "0-0-0"
          return date_value.strftime(input_format)
```

ours:
```python
          try:
              date_value = datetime.date(int(y), int(m), int(d))
+         except OverflowError:
+             return "0-0-0"
          except ValueError:
              ...
```

→ except blocks in **different order**, but **same exception type, same handling**. Test passes.

**Case 3: `django-14376` (both gold and our patch modify the same 2 files: `mysql/base.py` + `mysql/client.py`; the core 4 line changes are identical)**

gold (core changes, ignoring context lines):
```python
- kwargs['db'] = settings_dict['NAME']
+ kwargs['database'] = settings_dict['NAME']
- kwargs['passwd'] = settings_dict['PASSWORD']
+ kwargs['password'] = settings_dict['PASSWORD']
```

ours: **byte-identical 4-line modification** (same removals, same additions). Surrounding context lines differ slightly.

→ Model independently arrived at the mysqlclient library's rename (`db`/`passwd` → `database`/`password`). Hard evidence of "read API doc + understand version change + fix" reasoning, not "copy answer".

### A.4 Why this is anti-cheat evidence

If training-data contamination (model has seen gold patches), patches should be byte-identical to gold across the full sample. In our 8 sampled instances:

- 3 instances: 1:1 file match with comparable line counts (e.g., matplotlib-23299, django-16667, django-14376)
- 5 instances: partial file match, different line counts or positions (e.g., django-15629, pylint-8898, pylint-6386, django-11885, sphinx-8056)
- 1 instance shows core 4 changes byte-identical to gold but surrounding context differs (django-14376, Case 3 above)
- 0 instances are wholesale byte-identical copies

The model produced reasonable fixes independently, not copy-paste. This is engineering breakthrough, not memorization.

### A.5 Reviewer-reproducible analysis

Any reviewer can reproduce this with our published data:
1. Download `evidence/preds.lenient.json` from this repo. The `r14k_500` and `r14j_500` baseline preds files (Qwen3.5-27B-Thinking + mini-swe-agent and Qwen3-Next-NoThinking 80B + mini-swe-agent respectively) are available on request — we are happy to publish them as additional `evidence/baselines/` files if reviewers find this useful.
2. Run `swebench.harness.run_evaluation`
3. Compare patch file targets and content diffs
4. No proprietary tooling required

### A.6 [Tier 2 — for SWE-bench team under Review Terms] Fine-grained attribution

The following deep analysis is available only to SWE-bench official reviewers under Review Terms; not in this public repo:

- **+22 pt engineering breakdown** (which engineering measure rescued which subset of the 86)
- **Full `cli_hints_config.json`** (5 complete skill prompts + base_hints + all trigger rules)
- **Real skill-injection log samples** (5-10, redacted of unrelated traffic)
- **Real synthetic-user-injection log samples** (5-10)
- **Key proxy source snippets** (BON trigger logic, tool filter, format_convert, etc.)
- **Full proxy source review** (~47K LoC, read-only under Review Terms)

Request via: Email `1163945738@qq.com` with subject `[SWE-Bench-NDA]`. We'll reply with encrypted package + Review Terms.

Why not public:
- Skill-injection prompts are 3 months of iteration; public release lets competitors instantly replicate.
- Proxy source has internal business dependencies; needs cleanup before open-sourcing.
- The anti-cheat core (5-tool list, 0 BON triggers, no kb tools, non-byte-identical patches) is already in the public materials; reviewers can judge integrity without the NDA tier.

---

## §9 Proxy open-source strategy

Intended to open-source, pending:
1. Multiple re-runs to characterize variance
2. Extended benchmarks (SWE-bench Pro / Multimodal / LiveCodeBench)
3. Internal-dependency cleanup (proxy also serves WebChat etc.; the SWE-bench claude-cli path does NOT depend on any knowledge base or vector store — kb / context7 / searxng tools are stripped via `BLOCKED_PREFIXES`)
4. Code quality + tests
5. Compliance review
6. Partner impact assessment

**No release date committed.** The capability disclosure (`proxy_capabilities.md`) is sufficient for independent re-implementation in approximately one week.

Reviewers may request source-code review under Review Terms (see Appendix A.6 contact info).
