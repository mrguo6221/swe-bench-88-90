#!/bin/bash
# sglang launch command used for the SWE-bench Verified 90.0% submission.
#
# Captured live from `ps aux | grep sglang` on 2026-05-11 from the s66 inference host.
# 3 identical instances of this command were run (2 on s66, 1 on s65) for concurrency,
# but a single instance is sufficient to reproduce the score (just ~3x slower).
#
# Hardware requirement (per instance):
#   4 x RTX 4090 modded to 48GB VRAM (consumer-grade, no H100/A100 needed)
#   ~192GB total VRAM per instance
#
# Why --served-model-name is "Qwen3.5-27B-Thinking":
#   The actual model weights at /root/models/Qwen3.6-27B-FP8 are Alibaba's
#   official Qwen3.6-27B FP8 release. The served-model-name is set to
#   "Qwen3.5-27B-Thinking" because the same sglang instance also serves
#   several internal company projects (WebChat, automated office, internal
#   knowledge-base etc) that have hard-coded this model name in their
#   client code. Renaming would break those downstream projects.
#
#   config.json verification:
#     architectures        = Qwen3_5ForConditionalGeneration
#     model_type           = qwen3_5
#     mixed mamba + full attention (linear + standard)
#     multimodal (image_token_id present, language_model_only=false)

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
