# ZenMux Model Discovery & Pricing

How to query which models are available through ZenMux, their pricing, and capabilities — without using the Management API.

## Method 1: Public Models Page (no auth)

```bash
curl -s "https://zenmux.ai/models" | python3 -c "
import sys, json, re
html = sys.stdin.read()
lds = re.findall(r'<script type=\"application/ld\+json\">(.*?)</script>', html, re.DOTALL)
for ld in lds:
    data = json.loads(ld)
    if data.get('@type') == 'ItemList':
        for item in data['itemListElement']:
            name = item.get('name','')
            # filter by keyword
            if 'KEYWORD' in name.lower():
                props = {}
                for p in item['item'].get('additionalProperty', []):
                    props[p['name']] = p['value']
                print(f'{name}  |  {props.get(\"Price\",\"N/A\")}  |  {props.get(\"Context window\",\"N/A\")}')
"
```

The page embeds all 152+ models as JSON-LD `<script>` blocks. Key fields per model:
- `name` — display name (e.g. `Anthropic: Claude Fable 5`)
- `url` — detail page on zenmux.ai
- `additionalProperty[Price]` — e.g. `Prompt: $10 / 1M tokens; Completion: $50 / 1M tokens`
- `additionalProperty[Context window]` — e.g. `1,000,000 tokens`
- `description` — 1-2 sentence summary

For per-model detail pages (`/openai/gpt-image-2`), the JSON-LD also includes:
- `additionalProperty[Provider]` — e.g. Azure, Google Vertex
- `additionalProperty[Supported APIs]` — e.g. `imagen,images` or `gemini`

## Method 2: Anthropic Models via API (auth required)

```bash
ZENMUX_KEY=$(security find-generic-password -s 'zenmux-api-key' -a 'colin' -w)
curl -s "https://zenmux.ai/api/anthropic/v1/models" \
  -H "x-api-key: $ZENMUX_KEY" \
  -H "anthropic-version: 2023-06-01" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('data', []):
    print(f\"{m['id']}  (created: {m.get('created_at','?')})\")
"
```

Returns the standard Anthropic `/v1/models` response through ZenMux proxy. Useful for:
- Confirming a model is actually routable
- Checking creation date (new models often have edge-case issues)
- Verifying model ID format (e.g. `anthropic/claude-fable-5` vs `claude-fable-5`)

## Method 3: Official Provider Docs (capability details)

For resolution limits, feature support (inpainting/editing/streaming), and quality benchmarks:

| Provider | Docs URL |
|----------|----------|
| OpenAI models | `https://developers.openai.com/api/docs/models/<model-id>` |
| Google Imagen/Gemini | `https://ai.google.dev/gemini-api/docs/imagen` |
| Anthropic Claude Code settings | `https://docs.anthropic.com/en/docs/claude-code/settings` |

Provider docs are typically SPAs — use `curl -sL` + grep for specific keywords rather than expecting full text extraction.

## Pricing Note

ZenMux per-token pricing ≠ per-image cost. Image models consume tokens proportional to resolution, not prompt length. Rough estimates (verify with actual API `usage` field):

| Resolution | Approx tokens | gpt-image-2 | gemini-3.1-flash-img | gemini-3-pro-img |
|------------|:--:|:--:|:--:|:--:|
| 1K×1K | ~2K | $0.01 | $0.007 | $0.03 |
| 2K×2K | ~5K | $0.025 | $0.02 | $0.07 |
| 4K×4K | ~10K | $0.05 | N/A | $0.14 |
