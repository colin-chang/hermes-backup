# Model Constraints & API-Verified Parameters

This file records actual API behavior for each ZenMux video model,
independent of the plugin catalog metadata. When the two disagree,
this file and the error message are the ground truth.

## Veo 3.1 Standard (`google/veo-3.1-generate-001`)

**Verified: 2026-05-17**

| Parameter | Plugin Catalog | Actual API | Notes |
|-----------|---------------|------------|-------|
| duration_seconds | (4, 8) — patched | `[4, 6, 8]` only | Error code 3 for unsupported values |
| speed | ~60-180s — patched | 60–187s observed | 8s/1080p took 187s in one test |
| aspect_ratios | 16:9, 9:16, 1:1 | Not yet verified | — |
| resolutions | 720p, 1080p | Not yet verified | — |
| generate_audio | ✅ | ✅ | Works |
| negative_prompt | ❌ | Not yet verified | — |
| modalities | text, image | Not yet verified | — |

### Error Example (duration mismatch)

```
code: 3
message: 'Unsupported output video duration 5 seconds, supported durations are [8,4,6] for feature text_to_video.'
```

This error proved that `duration_seconds=5` is rejected; only `[4, 6, 8]`
are accepted despite the original catalog claiming `(5, 15)`.

### Generation Timeline (8s, 1080p, text-to-video)

- Submit: instant
- Poll every 10s
- Total: ~187s (~3 min)
- Output: video via `operation.response.generated_videos[0].video.uri`
  (signed URL, download within TTL)

## Veo 3.1 Fast (`google/veo-3.1-fast-generate-001`)

**Not yet verified.** Estimated durations based on documentation.

## Veo 3.1 Lite (`google/veo-3.1-lite-generate-001`)

**Not yet verified.** No audio support per catalog.

## Seedance 2.0 (`bytedance/doubao-seedance-2.0`)

**Not yet verified.** Supports negative_prompt per catalog.

## Happy Horse 1.0 (`alibaba/happyhorse-1.0`)

**Not yet verified.** Supports negative_prompt per catalog.

---

## How to Verify a Model's Constraints

1. Submit a generation with a known-good duration (8s)
2. If it fails, read the error message — it usually lists supported values
3. Patch `~/.hermes/plugins/zenmux-video/__init__.py` `_MODELS` dict
4. Update this reference file
5. The plugin's `_build_config` method clamps `duration_seconds` to
   `duration_range`, so keeping the catalog accurate prevents bad requests
