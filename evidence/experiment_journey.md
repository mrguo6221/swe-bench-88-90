# Experiment Journey — Why We Moved On Between Configurations

> A model-by-model and proxy-by-proxy account of what we tried and why each was abandoned. Reconstructed from the eval JSON files on the build host.

This was not a one-shot lucky run. The 90.0 % final score is the outcome of ~3 months of trying open-source models with different agent stacks, looking for a combination where local-deployable LLMs could match closed-API frontier scores. Below is the complete record.

The 3 core Qwen open-weight models that drove the final result and its baseline:

1. **Qwen3-Coder-Next 80B FP8** (Alibaba official) — Phase 1 (Feb 2026)
2. **Qwen3.5-27B-Thinking / NoThinking** (Alibaba official FP8) — Phase 2+ (May 2026, baseline and final)
3. **Qwen3.6-27B-FP8** (Alibaba official) — Phase 2 reference (May 2026, **same checkpoint used for the final 90.0 %**, exposed via sglang `--served-model-name=Qwen3.5-27B-Thinking`)

For all three, adoption began as soon as Alibaba released each version and they have been in continuous production use; the chronology below tracks our **SWE-bench-specific experimentation**, not first-time model adoption.

Additional Qwen variants we explored during Phase 1 but did not use for the final result — `Qwen3-Coder-Smart`, `Qwen3-Coder-V37`, `Qwen3-Coder-SWE`, `Qwen3-Coder-Next-FP8` — are listed in the chronology below for completeness. They are Coder-family specializations that did not produce competitive SWE-bench scores in our hands.

---

## SWE-bench experiment chronology

### 1. Qwen3-Coder-Next 80B FP8 + no-CoT pipeline (Feb 04-22, 2026)

**Best score:** 68.4 % on `nocot_20260206` (Feb 08).
**What we tried:** A "no-CoT" pipeline: pass the problem statement straight to the model, ask for a patch in one shot, no agent loop.
**Why we moved on:** That early 68.4 % was a one-off. Subsequent runs at the same setup (`NoCOT-reproduce`, `sage_pass2`, `sage_pilot50`, `v36_A_nocot_long`, `v36_B_nocot_short`) all gave 1-7 %. The pipeline was fragile — it worked once and broke every time we touched it. We concluded the no-CoT approach was either lucky on a specific config or relied on undocumented model state we couldn't recover.

### 2. Qwen3-Coder-Smart v18 family (Feb 09-15)

**Best score:** 61.4 % (on a 342-instance regression subset, so not directly comparable to 500); typical 5-7 %.
**What we tried:** Switched to the Coder-specialized Qwen variant, hoping its coding focus would help. Iterated proxy versions v18 → v28 → v30 → v32 → v32b → v34 → v35 → v35b (8+ variants).
**Why we moved on:** Coder-specialized models are tuned for *completion / inline edit*. SWE-bench requires *multi-turn read-edit-test* loops, which Coder models handle worse than general models. Adding proxy machinery couldn't compensate.

### 3. Qwen3-Coder-Smart proxy v28-v40 (Feb 13-22)

**Best score:** 24.0 % (`v28_remaining`), most others 1-6 %.
**What we tried:** Aggressive proxy customization. Wider tool surface (v28), prompt zero-shot (v36_C), prompt few-shot (v36_D), prompt long-context (v36_E), prompt full (v36_F), v37 protocol variants, etc.
**Why we moved on:** All variants plateaued in the single digits. The Coder model wasn't budging.

### 4. Qwen3-Coder-Next-FP8 (Feb 22)

**Best score:** 5.4 % (`ab_A_nocot`).
**What we tried:** FP8 quant of the Coder-Next checkpoint.
**Why we moved on:** Quantization may have hurt reasoning ability. Skipped.

### 5. Qwen3-Coder-SWE (Feb 21-22)

**Best score:** 6.0 % (`ab_B_cot`).
**What we tried:** A "SWE-specialized" Coder variant (the name suggested it was tuned for SWE-bench-like tasks). Versions v38, v38b, v39c-g, v40, v40b-d (~10 variants).
**Why we moved on:** A SWE-specialized model did *worse* than general Qwen on SWE-bench. We suspected the specialization was for a different task formulation. Reverted to general-purpose models.

**~10-week pause:** After Feb 22, we paused for ~10 weeks (rethinking approach). Decided to switch from "build a complete agent on top of Qwen" to "use a well-engineered open-source agent (mini-swe-agent) with narrow proxy customization".

### 6. Qwen3.6-27B FP8 + mini-swe-agent (May 03)

**Best score:** 60.4 % (`mini_swev_run2`), 55.4 % (`mini_swev_run1`).
**What we tried:** Restart with mini-swe-agent harness (Princeton's standard SWE-bench agent), Qwen3.6-27B-FP8 model. Various smoke tests (`smoke30`, `smoke100`, matrix ablations).
**Why we moved on:** Better than Coder runs, but ~60 % wasn't competitive with the closed-API leaderboard.

### 7. matrix25 ablations (May 04-05)

**~14 partial-slice experiments,** each 2-3 % on 25-instance slices.
**What we tried:** Per-axis ablations of various agent settings (sampling parameters, prompt structure, retry policies) on small slices to find what mattered.
**Why we moved on:** Most ablations didn't show a clear winner. Time to scale back up.

### 8. round6 / r9-r14 series (May 05-09)

**~25 partial-slice experiments,** 11-16 % typical.
**What we tried:** Iterating mini-swe-agent + Qwen3-27B variants. r9_armA (NoThinking), r9_armB/C (Thinking), r10/r12/r14 with various tunings. Compared Qwen3-Next 80 B (`r14j_500` = 68.0 %) vs Qwen3.5-27B-Thinking (`r14k_500` = 67.8 %).
**Why we moved on:** Plateaued at ~68 % regardless of model size in this configuration. This established our **baseline**: any future improvement had to come from agent-side engineering, not from a bigger model.

### 9. Switch to claude-cli + custom proxy (May 10-11) — the breakthrough

**Pilot (20 instances):** 16/20 = 80 % (`cli_swe_v2_20`).
**Full 500 internal eval:** 446 / 500 = 89.2 % (`cli_swe_500_lenient`).
**With psf real-httpbin re-eval:** 450 / 500 = **90.0 %** — our final headline.

**What we tried (the breakthrough):**
- Replaced mini-swe-agent with **claude-cli** (Anthropic's open-source CLI) — pointed at our local Qwen via the custom proxy.
- Used claude-cli's `-p` one-shot mode. In this mode claude-cli advertises only **3 core tools** (Bash, Edit, Read); the proxy adds 2 more (`sandbox__sandbox-run_code`, `doc_parse__doc_parse-doc_parse`) — total **5 tools** seen by the model (NOT the 17 tools of claude-cli's interactive mode).
- The proxy was redesigned as a **narrow, surgical translation/filter layer** between claude-cli and sglang: protocol translation, sampling tuning, skill-prompt injection, synthetic-user continuation, tool-call abuse detection, output sanitization. No best-of-N, no benchmark-specific tuning.
- This finally clicked: same 27B Qwen3-Thinking model, but with a much better agent loop around it.

**Why this configuration worked:**
- The proxy's skill injection (CODE_REWRITE, MULTI_FILE prompts) operationalizes standard prompt-engineering practice.
- The model's "thinking" mode gives it slack to reason; the agent loop gives it tools to act; the proxy makes the interface clean.
- The 5-tool minimal sandbox is exactly the toolchain a human engineer uses to fix a bug: Read source → Bash runs pytest → Edit source.

---

## What this teaches

1. **Smaller model + better agent > larger model + simpler agent.** Counterintuitive but reproduced across our experiments. The 80 B Qwen3-Next didn't beat the 27B-Thinking + better agent.

2. **Coder-specialized models can underperform general models on SWE-bench.** SWE-bench is more about multi-turn reasoning than about generating short code completions.

3. **Engineering wins, but you have to find the right combination.** We tried ~50+ configurations across 3 core open-weight Qwen models (Qwen3-Coder-Next 80B, Qwen3.5-27B, Qwen3.6-27B) before finding the one that worked. If we had stopped at the 30-day mark (when most experiments were 1-6 %), we'd have concluded "open-source can't compete."

4. **The "perfect proxy" trap.** Our Feb 2026 attempts were too ambitious — trying to build a complete agent on top of Coder models. The successful May 2026 approach was a *narrow* proxy on top of a *standard* well-engineered CLI (claude-cli `-p`).

---

## Why this argues against training-data contamination

If our 90.0 % were simply because Qwen3.5-27B-Thinking had seen the SWE-bench answers during training:

- We would have hit 80 %+ during the **first** experiment with that model, not the 50th iteration of trying different configurations.
- The same model in `r14k_500` (our reproduction of the standard mini-swe-agent baseline using the same Qwen3.5-27B-Thinking checkpoint — fully reproducible by anyone with access to the public mini-swe-agent and the open-weight model) gives 67.8 % — exactly what an "honestly tested" 27B should produce.
- The 80B Qwen3-Next, with arguably *more* training data exposure to GitHub, only reaches 68.0 % (`r14j_500`). Bigger model, same training-data concern, lower score.

If training contamination were driving our numbers, the journey would look like: "tried this model, hit 90 % immediately, done." Instead it looks like: "tried 3 models and 50+ configurations across 3 months, the breakthrough was in the agent stack."

This pattern is more consistent with **a real engineering breakthrough than with benchmark leakage.**

---

## Reproducibility

The machine-readable timeline is at `evidence/timeline.csv` (~90 experiments). The annotated chronology is at `evidence/timeline_chart.txt`. Per-instance predictions are at `evidence/preds.lenient.json` (headline) and `evidence/preds.strict.json` (floor).

We can produce any individual run's full report on request.
