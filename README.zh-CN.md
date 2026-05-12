# SWE-bench Verified 90.0% / 88.0% — 27B 开源模型 + 单机消费级 GPU

> 中文版. [English version → README.md](README.md)

**两档分数, 完整披露**:

- **90.0% (450/500)** — headline. 单次采样, 含 cli/proxy 进程崩 retry + 4 题 psf 环境补测.
- **88.0% (440/500)** — strict floor. 单次采样, 不 retry, 不补测.

**栈**: **Qwen3.6-27B-FP8** (阿里通义官方开源 FP8 权重; sglang 服务名 `Qwen3.5-27B-Thinking`, 详见下文复现性段) + claude-cli (Anthropic 开源 CLI, `-p` 一次性模式) + 自研 proxy (~47K 行 Python). 待 SWE-bench 官方独立复核.

发布日期: **2026-05-11**

---

## 两档分数

| 档 | 描述 | resolved/500 | 比率 | 比公开 SOTA 79.2% |
|----|------|--------------|------|-------------------|
| **headline** | 单次采样 + 13 题 cli/proxy 进程崩 retry (救回 6) + psf 4 题用真 httpbin.org 重测 | **450/500** | **90.0%** | **+10.8 pt** |
| floor | 严格单次, 不 retry, 不补测 | 440/500 | 88.0% | +8.8 pt |

**披露口径**:
- **cli/proxy 进程崩 retry**: 13 题首跑 patch 为空 (12 题 rc=137 SIGKILL, 1 题模型自残 git clean), 重跑一次救回 6 题. 这是 infrastructure 级 retry, 业界通行.
- **psf 4 题环境补测**: psf__requests-1724/1766/1921/2317 的测试硬编码 `httpbin.org`. 我们 eval 服务器内网, 无外网, 测试 hang 到 timeout. 我们把这 4 题移到家庭带宽机器, 用真 `httpbin.org` 在 swebench.harness 上重跑, **全部 FAIL_TO_PASS 测试通过 (4 题合计 26 个 F2P 测试)**. 详见 [SUBMISSION.md](SUBMISSION.md) §4.1.

---

## 关键技术信息

| | |
|--|--|
| Patch 率 | 496/500 = 99.2% |
| 模型 | **Qwen3.6-27B-FP8** (阿里通义官方权重, 27B 参数, FP8 量化; sglang `--served-model-name=Qwen3.5-27B-Thinking` 对外, 详见复现性段) |
| Agent | `@anthropic-ai/claude-code@2.1.23` (Anthropic 开源 CLI, `-p` 一次性模式) |
| 推理 | sglang 3 实例 × TP=4. **12 张 RTX 4090 改装 48GB 消费级 GPU, 跨 2 台机器**. 无 H100/A100. |
| 自研 proxy | ~47K 行 Python (含测试). 能力清单已披露 ([proxy_capabilities.md](proxy_capabilities.md)), 源码暂未开. |
| 同模型 baseline | 67.8% (r14k_500: 同 27B 模型 + 公开 mini-swe-agent) |
| 工程加成 | **+22.2 pt** (90.0% headline) / +20.2 pt (88.0% floor) — 同模型, 纯工程 |

---

## 反作弊核心

SWE-bench 跑分期间, 模型实际可用的工具**只有 5 个**:

```
Read / Edit / Bash / sandbox__sandbox-run_code / doc_parse__doc_parse-doc_parse
```

- 完全无 WebFetch / WebSearch / context7 / 任何知识库工具
- claude-cli `-p` 一次性模式只 advertise 3 个核心工具 (Bash/Edit/Read)
- proxy `BLOCKED_PREFIXES` strip 掉所有上网工具
- proxy 日志可复验:
  ```
  grep -c '\[BON\]'        → 0 (best-of-N 重试)
  grep -c 'context7'       → 0
  grep -c 'searxng'        → 0
  grep -c 'lightrag'       → 0 (与 SWE-bench 相关全 0)
  ```

SWE-bench 期间 cli=claude 请求 **4110 次**, BON 标记 **0 次**.

模型可做的事: 读源码 → 跑测试 → 改源码. 与人类工程师改 bug 工具链一致.

---

## Ablation: CLI 互换 (qwen-cli vs claude-cli)

为了排除"90% 是 claude-cli 特化作弊" 的可能, 我们用同样的模型 + 同样的 proxy + 不同的 CLI (qwen-cli, 阿里官方开源) 再跑一遍. **唯一变量是 CLI**:

| | claude-cli (主提交) | qwen-cli (ablation) | Δ |
|---|---|---|---|
| Headline (lenient + psf 真 httpbin) | **90.0%** (450/500) | **87.4%** (437/500) | -2.6 pt |
| Strict floor (无 retry, 无补测) | 88.0% (440/500) | 85.4% (427/500) | -2.6 pt |
| 同模型 mini-swe-agent baseline | 67.8% | 67.8% | = |

两个 CLI 都显著超过同模型 baseline (67.8%) 和公开 SOTA (79.2%). CLI 之间 ~2.6 pt 的差距在各档一致, 来自 claude-cli 的工具表面设计更细 (Edit 工具精度、prompt 格式), **不是任一 CLI 的数据集特化作弊**.

两个 CLI 的失败模式也不同, 这本身就是诊断: claude-cli 的失败多是 infra (cli 进程崩, 12/13); qwen-cli 的失败多是模型行为 (模型说完成但没改文件, 15/16). 两个 CLI 同时跑不出来的 4 题 (`django-10554`, `-16263`, `xarray-7229`, `sympy-22456`) 是 Qwen3.5-27B-Thinking 自身的能力边界, 跟 stack 无关.

完整 ablation 数据、preds 文件、per-instance 报告在 `evidence/ablations/qwen-cli/`.

这一 ablation **不**解决 proxy 透明度问题 (两个 CLI 用的同一个 proxy) 和数据污染问题 (同模型). 它解决的是: 90% 是不是 claude-cli 黑箱. 答案: 不是.

---

## 诚实声明

1. proxy 做了大量工程: 协议转换 (Anthropic↔OpenAI), 工具滤镜, skill 注入 (通用编码纪律, 与 SWE-bench 题目无关), 输出净化, 滥用检测.
2. **没有用** best-of-N. proxy 代码里有 BON 路径, 触发条件 (响应畸形 + think 标签泄漏同时满足) 在跑分期间 0 次命中.
3. proxy 源码暂不在仓库. 意向开源, 条件包括: 多次复测表征方差、扩展评测、内部依赖清理、合规审查、合作伙伴影响评估. 不承诺日期.
4. 3 个月持续工程化, 50+ 次正式 eval, 3 个核心 Qwen 开源模型 (80B Qwen3-Coder-Next / 27B Qwen3.5 / 27B Qwen3.6) + ~40 个 proxy 变体. 大多失败. 不是一次蒙的.
5. **训练数据污染怀疑**: Qwen3 训练截止与 SWE-bench Verified 公开时间有重叠, 模型可能"见过"修复 PR. 这影响所有 LLM, 不只我们. 反污染最硬证据: 同期 80B Qwen3-Coder-Next 在 mini-swe-agent 上稳在 68-72%, 没破过 72%. 只有 27B-Thinking + claude-cli + 特定 proxy 这个精确组合命中 90.0%. 若是污染, 80B 应早就 85%+. 详见 [SUBMISSION.md](SUBMISSION.md) §6.

---

## 复现性

```
最低复现硬件:
  1 台工作站 × 4 张 RTX 4090 改装 48GB (总 ~192GB VRAM)
  sglang 单实例 TP=4
  无 H100 / A100 / B200

我们的实际部署 (只为并发, 不为正确性):
  2 台工作站 × 共 12 张 RTX 4090 改装 48GB
  sglang × 3 实例, 每实例 TP=4
  单实例完全够跑通 — 只是慢 ~3 倍

所有非 proxy 组件全开源:
  sglang (Apache 2.0)
  @anthropic-ai/claude-code (Apache 2.0)
  swebench.harness (官方开源)
  python 3.10, node 20
```

sglang 启动命令 (附 `evidence/sglang_launch.sh`, 全程透明):

```bash
python3 -m sglang.launch_server \
  --model-path /root/models/Qwen3.6-27B-FP8 \
  --served-model-name Qwen3.5-27B-Thinking \
  --tp-size 4 \
  --context-length 262144 \
  --mem-fraction-static 0.85 \
  --kv-cache-dtype fp8_e4m3 \
  --reasoning-parser qwen3 \
  --tool-call-parser qwen3_coder \
  --chunked-prefill-size 4096 \
  --mamba-scheduler-strategy extra_buffer \
  --trust-remote-code \
  --sampling-defaults model
```

**关于模型命名**: 实际权重路径是 `/root/models/Qwen3.6-27B-FP8` (阿里官方 FP8 权重), 通过 sglang `--served-model-name Qwen3.5-27B-Thinking` 对外暴露. 这样做是因为本机 sglang 同时服务公司多个内部项目, 那些项目硬编码了 `Qwen3.5-27B-Thinking` 这个 model name. 我们不改这个对外名以保持下游兼容. config.json (`architectures=Qwen3_5ForConditionalGeneration`, `model_type=qwen3_5`) 显示这是 Qwen3.5 架构的实现, 含 Mamba 混合注意力 + 多模态能力. **跑分用的是 FP8 量化版的官方权重, 不微调, 不做任何 SWE-bench-specific 训练**.

---

## 仓库内容

| 文件 | 用途 |
|------|------|
| `README.md` | 英文 README (默认) |
| `README.zh-CN.md` | 本文档 |
| `SUBMISSION.md` | 给 leaderboard reviewer 的完整披露 (英文) |
| `REPRODUCE.md` | 复现指引 |
| `metadata.yaml` | 元数据 |
| `proxy_capabilities.md` | proxy 能力清单 (源码未公开, 仅能力描述) |
| `evidence/preds.lenient.json` | headline 预测 (含 retry) — 90.0% 基础 |
| `evidence/preds.strict.json` | 严格档预测 (无 retry) — 88.0% 基础 |
| `evidence/report_lenient.json` | swebench.harness 官方 eval 输出 |
| `evidence/manual_eval_psf_real/` | 4 题 psf 真 httpbin.org 重测 |
| `evidence/sglang_launch.sh` | sglang 启动命令完整版 |
| `evidence/SHA256SUMS` | 所有 evidence 文件的加密校验和 |

---

## 联系

- 技术 / 复现讨论: 在本仓库 open issue
- SWE-bench 官方 reviewer: 见下方

## 给 SWE-bench 官方 Reviewer

我们另备补充材料, 在 peer-review 风格的 Review Terms 下提供 (无需正式签字), 含:

- 完整 `cli_hints_config.json` (5 个 skill 完整 prompt + base_hints + 触发规则)
- 5 个真实 skill 注入日志样本 (脱敏)
- 5 个真实 synthetic user 注入日志样本 (脱敏)
- proxy 关键源码片段 (~200 行, 覆盖 BON 触发逻辑 / CLI-DETECT / TOOL-FILTER / skill 评分 / synthetic user 注入)
- 86 题逐题归因 CSV
- **针对具体验证请求录制的屏幕 demo** (3-5 个工作日交付, 配英文字幕)
- 异步邮件 Q&A (48 小时内回复)

**关于形式**: 我们的开发和评估基础设施在公司内网隔离环境 (这也是为什么 4 道 psf__requests 题必须挪到另一台有外网的机器重测 — 见 `evidence/manual_eval_psf_real/`). 直接从内网系统做 live 屏幕分享或视频会议在运维上不可行. 录制 demo 和离线源码 review 是可行的, 录制内容能给 reviewer 跟 live 走查同等的可见性.

**申请方式**: Email `1163945738@qq.com`, 主题含 `[SWE-Bench-NDA]`. 48 小时内回复.

---

## 时间戳

本次发布为 `v0.2`. Commit hash 不可篡改, 提供加密时间戳.

详见 `evidence/SHA256SUMS` (所有 evidence 文件 SHA-256).

---

## 署名

- **机构**: 独立研究 (山东济南). 作者就职于国内某工业集团下属的数字化业务子公司 (业务范围含 IT 服务与 AI 工程). 完整机构信息可在 Review Terms 下向合格 reviewer (例如 SWE-bench 团队) 提供, 详见上面"给 SWE-bench 官方 Reviewer"段.
- **GitHub**: [@mrguo6221](https://github.com/mrguo6221)
- **首次公开**: 2026-05-11
