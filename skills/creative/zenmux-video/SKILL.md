---
name: zenmux-video
description: "Generate video via ZenMux Vertex AI Compatible API — Veo 3.1 (standard/fast/lite), Seedance 2.0, Happy Horse 1.0. Text-to-video and image-to-video through the zenmux-video Hermes plugin or direct google-genai SDK calls."
version: 1.0.0
author: colin-chang
license: MIT
platforms: [macos, linux]
compatibility: "Requires ZENMUX_API_KEY and google-genai SDK in the Hermes venv."
prerequisites:
  env_vars: ["ZENMUX_API_KEY"]
metadata:
  hermes:
    tags:
      - video-generation
      - veo-3.1
      - seedance
      - happyhorse
      - zenmux
      - creative
      - generative-ai
    category: creative
---

# ZenMux Video Generation

Generate video content through the ZenMux Vertex AI Compatible API using
the `zenmux-video` Hermes plugin (preferred) or direct `google-genai` SDK
calls when the plugin tool isn't directly exposed.

## When to Use

- User asks to generate a video from a text prompt
- User asks to animate a still image (image-to-video)
- User mentions Veo, Seedance, or Happy Horse by name
- User asks for cinematic / AI-generated video content

## Supported Models

| Model ID | Display | Speed | Audio | Price | Durations |
|----------|---------|-------|-------|-------|-----------|
| `google/veo-3.1-generate-001` | Veo 3.1 | ~60-180s | ✅ | premium | **4, 6, 8s** |
| `google/veo-3.1-fast-generate-001` | Veo 3.1 Fast | ~30-60s | ✅ | premium | 4, 6, 8s (estimated) |
| `google/veo-3.1-lite-generate-001` | Veo 3.1 Lite | ~20-45s | ❌ | affordable | 4, 6, 8s (estimated) |
| `bytedance/doubao-seedance-2.0` | Seedance 2.0 | ~45-90s | ✅ | premium | TBD |
| `alibaba/happyhorse-1.0` | Happy Horse 1.0 | ~30-60s | ❌ | affordable | TBD |

> **See `references/model-constraints.md`** for per-model API-verified parameters,
> quirks, known mismatches with the plugin catalog, and how to verify constraints
> when the API rejects a parameter value.

## Quick Start

### Via Hermes Plugin (Preferred)

If the `video_gen` tool is available in the agent's toolset, it routes
through the `zenmux-video` plugin automatically:

```
video_gen(prompt="A cat in a garden", model="google/veo-3.1-generate-001", duration=8)
```

### Via Direct SDK Call (Fallback)

When the plugin tool isn't exposed (e.g. in WebUI sessions), call the
`google-genai` SDK directly from the Hermes venv:

```python
from dotenv import load_dotenv
load_dotenv(os.path.expanduser("~/.hermes/.env"))

from google import genai
from google.genai import types

client = genai.Client(
    api_key=os.environ["ZENMUX_API_KEY"],
    vertexai=True,
    http_options=types.HttpOptions(
        api_version="v1",
        base_url="https://zenmux.ai/api/vertex-ai",
    ),
)

config = types.GenerateVideosConfig(
    aspect_ratio="16:9",
    resolution="1080p",
    duration_seconds=8,       # MUST be one of [4, 6, 8] for Veo 3.1
    generate_audio=True,
)

operation = client.models.generate_videos(
    model="google/veo-3.1-generate-001",
    source=types.GenerateVideosSource(prompt="your prompt here"),
    config=config,
)

# Poll until done
import time
while not getattr(operation, "done", False):
    time.sleep(10)
    operation = client.operations.get(operation)

# Extract video
video = operation.response.generated_videos[0].video
if video.uri:
    # Download from URI
    ...
elif video.video_bytes:
    # Save raw bytes
    ...
```

## Workflow: Generate → Poll → Save → Present

1. **Submit** — `client.models.generate_videos()` returns an operation object
2. **Poll** — `client.operations.get(operation)` in a loop until `operation.done`
3. **Extract** — get `video.uri` (download) or `video.video_bytes` (save directly)
4. **Save** — write to `~/.hermes/cache/zenmux_video_{timestamp}.mp4`
5. **Present** — use `MEDIA:/path/to/file.mp4` in the response

Typical generation times:
- Veo 3.1 standard: **60–180 seconds** (can be over 3 min for 8s 1080p)
- Veo 3.1 fast: 30–60 seconds
- Veo 3.1 lite: 20–45 seconds

## Pitfalls

1. **Veo 3.1 duration is NOT arbitrary** — only `[4, 6, 8]` seconds are
   accepted. The API returns `INVALID_ARGUMENT` (code 3) for any other value.
   The plugin catalog's `duration_range` was wrong (said 5–15) and has been
   patched to `(4, 8)`. If the plugin gets reinstalled/reverted, verify the
   `_MODELS` dict in `~/.hermes/plugins/zenmux-video/__init__.py`.

2. **`operation.done` can be `None`** — the SDK may return `done=None` instead
   of `done=False` while processing. Poll loop must check `not getattr(operation, "done", False)`.

3. **No 1-second videos** — users may ask for very short clips; the minimum
   across all Veo 3.1 variants is **4 seconds**. Inform them and use 4s minimum.

4. **Plugin catalog may drift from actual API** — the `_MODELS` metadata in
   `__init__.py` (duration_range, speed, aspect_ratios, resolutions) is
   manually maintained and can become outdated after ZenMux API changes.
   If a generation fails with a constraint error, check the error message
   for the actual supported values and patch the catalog.

5. **API key in `.env`, not in config.yaml** — `ZENMUX_API_KEY` lives in
   `~/.hermes/.env`. When running scripts outside the agent loop, load it
   with `dotenv`.

6. **Venv path** — the Hermes venv is at `~/.hermes/hermes-agent/venv/`
   (not `.venv/`). Activate it before running SDK scripts.

7. **Image-to-video** — pass `image=types.Image(image_bytes=..., mime_type=...)`
   in the `GenerateVideosSource`. Supported by all models except possibly
   some future additions — check `modalities` in the model catalog.

## Model Selection Guide

| Need | Model |
|------|-------|
| Best quality, budget no concern | `google/veo-3.1-generate-001` |
| Good quality, faster turnaround | `google/veo-3.1-fast-generate-001` |
| Budget-friendly, no audio needed | `google/veo-3.1-lite-generate-001` |
| ByteDance model alternative | `bytedance/doubao-seedance-2.0` |
| Cheapest option, simple clips | `alibaba/happyhorse-1.0` |

The prompt keyword "veo" in the user's request triggers Veo 3.1 standard
via the plugin's `_PROMPT_HINTS` mapping. Explicitly specify model to override.

## Verification Checklist

- [ ] `ZENMUX_API_KEY` set in `~/.hermes/.env`
- [ ] `google-genai` SDK installed in `~/.hermes/hermes-agent/venv/`
- [ ] `duration_seconds` is one of the model's supported values
- [ ] Poll loop handles `done=None` gracefully
- [ ] Output saved to `~/.hermes/cache/` and presented with `MEDIA:` prefix
