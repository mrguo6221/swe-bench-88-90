# Proxy Capability Disclosure

> The proxy's source code is **not** in this repository. This document lists the proxy's capabilities and, where possible, shows verbatim log markers as evidence. A competent team can re-implement these from this description.

## What the proxy is

A Python aiohttp service listening on `localhost:8028` (fronted by nginx for connection management). It exposes the Anthropic Messages API (`POST /v1/messages`) and forwards to one of three sglang backends serving Qwen3.6-27B-FP8 (sglang `--served-model-name=Qwen3.5-27B-Thinking`).

Approximate size: ~47K lines of Python (including ~3.3K lines of tests and benchmarks). Production code spans `proxy_server.py` (~5K LoC entry / load balancing / admin), `handlers.py` (~10K LoC request lifecycle), `content_proc.py` (~3K LoC response post-processing), `format_convert.py`, `agent_tools.py`, `semantic_router.py`, `load_balancer.py`, `device_mgmt.py`, `error_tracker.py`, `path_cache.py`, and several smaller modules. It is NOT a generic forwarder — it does substantial request/response shaping for coding-agent traffic.

## Important context: claude-cli `-p` one-shot mode

This submission uses `claude-cli --dangerously-skip-permissions --output-format text -p "<prompt>"` — the **one-shot, non-interactive mode**. In this mode, claude-cli advertises only **3 core tools** to the proxy: `Bash`, `Edit`, `Read`. (In contrast, claude-cli's interactive mode advertises ~17 tools.)

The proxy adds 2 more tools (`sandbox__sandbox-run_code`, `doc_parse__doc_parse-doc_parse`), giving the model a final working set of **5 tools** during SWE-bench evaluation.

The proxy's `BLOCKED_PREFIXES` strips all web / knowledge-base tools (`searxng__*`, `context7__*`, `fetch__*`, `browser__*`, `tts__*`, `image_annotate__*`) even if they were ever advertised. None of these tools were available to the model during evaluation.

## Capabilities that fired during the SWE-bench run

The table below shows proxy features that were activated. Trigger counts are from `docker logs` across the 3 active proxy instances over the full proxy lifetime (note: the proxy is shared infrastructure, so total counts include some non-SWE traffic; the *behavior* of each feature is unchanged regardless of caller).

For SWE-bench specifically, `[CLI-DETECT] CLI=claude` appeared **4110 times** — this is the precise SWE-bench evaluation request count.

| Feature | Log marker | Total triggers | What it does |
|---|---|---|---|
| Protocol translation | `[CLAUDE->OPENAI]` | ~44K | Convert Anthropic Messages format ↔ OpenAI Chat Completions format |
| Model alias resolution | `[MODEL]`, `[LENGTH-ROUTER]` | ~64K / ~24K | Map `claude-sonnet-*` / `claude-opus-*` → `Qwen3.5-27B-Thinking` (served-model-name) based on alias config and conversation length |
| Sampling parameter override | `[CLI-SAMPLING]` | ~24K | Force `temperature=0.7, top_p=0.8, top_k=20, presence_penalty=1.5` for Qwen models (Qwen-recommended values) |
| CLI detection | `[CLI-DETECT]` | ~24K total (SWE-bench cli=claude = 4110) | Detect whether caller is claude-cli vs qwen-cli (used by downstream features) |
| **CLI tool filter** | `[CLI-TOOL-FILTER]` | ~44K | In claude-cli `-p` mode, claude-cli advertises only 3 tools (Bash/Edit/Read); proxy adds 2 (`sandbox__sandbox-run_code`, `doc_parse__doc_parse-doc_parse`); final set is 5. The `BLOCKED_PREFIXES` strips all web / knowledge-base tools. |
| **CLI hints / skill injection** | `[CLI-HINTS]` | ~6,652 (total across full proxy lifetime; ~50 % of SWE-bench requests during evaluation triggered) | Score the conversation against `cli_hints_config.json` skill thresholds (based on tool-usage patterns: Edit calls → CODE_REWRITE score, Read ≥3 files → MULTI_FILE score). Inject ~1.5KB of generic prompt-engineering text (TodoWrite discipline, no fake-completion comments, Edit-fail recovery, etc.). **The injected content is generic to coding tasks and is NOT specialized to SWE-bench instances.** |
| **Synthetic user injection** | `[STREAM-CLAUDE] 注入 synthetic user (No-User-Query 兜底)` | ~5,434 (total; ~38 % of SWE-bench requests triggered) | When the model gets stuck in "thinking-only, no next action" state during streaming, inject a brief synthetic user message ("please continue") to nudge the model forward. Does not alter the original user query; does not leak answer information. |
| Tool usage hint | `[TOOL-HINT]` | ~21K | Inject one-line hints suggesting TodoWrite / Task tool usage if the agent appears to be ignoring them (note: under `-p` mode these tools are not in the working set, so the hint is informational only) |
| Sandbox tool enhancement | `[SANDBOX-ENHANCE]` | ~0.9K | When the agent calls `sandbox-run_code`, augment the result with the working directory and a summary header |
| Path cache | `[PATH-CACHE]`, `[PATH-FIX]` | ~44K / ~2.6K | Track file paths the agent has referenced; correct common path mistakes (e.g., `\` vs `/`, redundant absolute paths) |
| Pangu spacing removal | `[PATH-FIX-PANGU]`, `[PATH-FIX-CODE-PANGU]` | ~100 | Strip the unwanted whitespace Qwen sometimes inserts between CJK and ASCII characters in output (Qwen-specific quirk; can corrupt Python identifiers) |
| Tool call abuse detection | (inline; blocks duplicate tool calls) | (count not directly logged) | If the agent calls the same tool with the same parameters multiple times, block the 3rd+ call and return `[BLOCKED] 已多次重复调用此工具且参数相同` to break the loop |
| Multi-backend load balancing | `[CONNECT]` / `[LOAD-BALANCER]` | ~46K | Distribute requests across 3 sglang backends (s66:8007, s66:8009, s65:8007) with weighted round-robin and KV-cache awareness |
| Usage inflation adjustment | `[USAGE-INFLATE]` | ~44K | Adjust the Anthropic-style token usage report to account for cli_window vs actual context length (cosmetic; does not affect generation) |
| WORK-MODE classification | `[WORK-MODE]` | ~2.7K | Classify caller's task as `bug_fix` / `refactor` / `new_code` etc. (used to fine-tune subsequent prompts). **Did not specialize on SWE-bench specifically** — same classifier as other coding tasks. |
| Code verification | `[CODE-VERIFY]` | ~120 | Compile-check Python code blocks in the response; if syntax error, attach a system message asking for correction. (Note: this does NOT trigger a re-sample — see "did NOT fire" below) |

## Capabilities that exist but did NOT fire in this run

To be transparent about Best-of-N concerns:

| Feature | Log marker | Triggers | Notes |
|---|---|---|---|
| **Best-of-N retry** | `[BON]` | **0** across all proxy traffic in this run | Code path exists. Trigger condition is "≥2 malformed-output issues detected" (e.g., unclosed code block + leaked `<think>` tag). This never triggered during SWE-bench evaluation. |
| **Response-quality retry** | `[RETRY]` | **0** | Re-fires the request when `should_retry_response()` finds the answer too short / clearly truncated. Did not fire. |
| **SGLANG-FIX empty retry** | `[SGLANG-FIX]` | **0** | Re-fires if backend returned `content=""` with no tool calls. Did not fire. |

**Verifiable**: `docker logs mcp-proxy-X | grep -c '\[BON\]\|\[RETRY\]\|\[SGLANG-FIX\]'` returns 0. SWE-bench-period cli=claude requests = 4110, BON-triggered = 0. Raw log dumps available to reviewers on request (see "For SWE-bench Official Reviewers" section in README.md).

## Sampling parameters used

```
temperature:       0.7
top_p:             0.8
top_k:             20
presence_penalty:  1.5
max_tokens:        32000   (per turn; conversation can have many turns)
```

These match the values published in Qwen3's model card as "recommended for Thinking mode".

## Final tool set seen by the model during SWE-bench

After `[CLI-TOOL-FILTER]` processing, the agent saw exactly these 5 tools (verbatim from proxy logs across the 4110 cli=claude requests):

```
['Bash',
 'Edit',
 'Read',
 'sandbox__sandbox-run_code',
 'doc_parse__doc_parse-doc_parse']
```

The model could NOT call:
- `WebFetch` / `WebSearch` — claude-cli `-p` mode does not advertise these
- `context7` / `lightrag` / `kb-admin` / any vector store — proxy `BLOCKED_PREFIXES` strips them
- `searxng` / `browser` / any web search — same strip
- `TodoWrite` / `Glob` / `Grep` / `Write` / `Task` / `Skill` — claude-cli `-p` mode does not advertise them (note: the proxy's skill-injection prompt may suggest the model "use TodoWrite for planning", but since the tool is not in the working set, the model can only plan internally)

The model's actual loop: read source → run pytest → edit source. Same toolchain a human engineer uses to fix a bug.

## What the proxy does *not* do

- The proxy does **not** see or condition on SWE-bench-specific information (instance ID, gold patch, expected test names, expected files). Skill injection / hints are pattern matching on the user message and tool-call sequence, identical for any coding task.
- The proxy does **not** sample multiple model completions and pick the best (no temperature-N sampling).
- The proxy does **not** modify the `model_patch` that the agent produces. Patches are captured by the runner via `git diff --cached HEAD` directly inside the docker container.
- The proxy does **not** filter or alter `test_patch` (which is applied to the container by the runner, never seen by the proxy).
- The proxy is **not** specialized for the 500 SWE-bench Verified instances. The same proxy serves an internal WebChat, other coding tools, and general agent traffic.

## Why the proxy moves the needle

The 67.8 % → 90.0 % gap (mini-swe-agent same model → cli + proxy same model = +22.2 pt) is the combined effect of the engineering choices described above:

- richer tool surface than mini-swe-agent's single Bash (the standard 5-tool minimal sandbox: Bash + Read + Edit + sandbox-run_code + doc_parse)
- Qwen-recommended sampling parameters
- generic prompt-engineering injection (skill discipline + synthetic-user continuation)
- output sanitization (Pangu de-space etc.)
- tool-call abuse detection

None of them is best-of-N. None of them is dataset-specific. All are re-implementable from the per-feature descriptions in the table above.

A per-component pt attribution would require running ablations we have not run; we therefore do not publish granular per-feature pt estimates. A finer-grained engineering attribution is available to SWE-bench official reviewers under Review Terms.

## On open-sourcing the proxy

We intend to open-source the proxy once the following conditions are met:

1. **Independent re-evaluation.** Repeat the SWE-bench Verified run multiple times (different seeds, possibly different proxy versions) to characterize variance and confirm the headline number is robust, not a single-run statistical fluke.
2. **Extended-benchmark coverage.** Before releasing, evaluate the same stack on harder benchmarks (full SWE-bench, SWE-bench Pro / Multimodal as they become available, other coding evals like LiveCodeBench).
3. **Internal-only dependencies cleanly separated.** The proxy currently depends on hooks into an unrelated WebChat product, a private knowledge-base service, and other internal-only tooling. (Note: SWE-bench evaluation path does NOT depend on knowledge-base / vector-store calls — `BLOCKED_PREFIXES` strips them — but the proxy code still references those modules and needs cleanup.)
4. **Code quality and test coverage at release standard.** ~3K LoC of tests need to pass cleanly without referencing internal infrastructure.
5. **Legal / compliance review complete.**
6. **Downstream partner impact evaluated.**

The exact timeline depends on the above. We may not be able to commit to a specific release date. **However**, the capability disclosure in this document is intended to be sufficient for an independent team to reimplement the proxy's essential behavior in approximately one week of engineering work.

Reviewers who want to inspect the source code for verification (rather than reuse) can request access via the channel listed in the "For SWE-bench Official Reviewers" section of `README.md`. We will provide source code review under peer-review-style Review Terms.
