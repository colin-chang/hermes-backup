# ZenMux Model Discovery & Pricing

How to discover available models, their current pricing, and capabilities via ZenMux.

## Primary: Scrape the Models Page

The public page `https://zenmux.ai/models` contains a `<script type="application/ld+json">` block
with `@type: "ItemList"` listing all 152+ models. Each entry has:

- `name` — display name (e.g. "OpenAI: GPT-Image-2")
- `url` — detail page (e.g. `/openai/gpt-image-2`)
- `description` — truncated summary
- `additionalProperty`: `Price`, `Context window`, `Provider`

### Parsing command (Python one-liner):

```bash
curl -s https://zenmux.ai/models | python3 -c "
import sys, json, re
html = sys.stdin.read()
lds = re.findall(r'<script type=\"application/ld\+json\">(.*?)</script>', html, re.DOTALL)
for ld in lds:
    data = json.loads(ld)
    if data.get('@type') == 'ItemList':
        for item in data['itemListElement']:
            props = {p['name']: p['value'] for p in item.get('item', {}).get('additionalProperty', [])}
            print(f\"{item['name']} | {props.get('Price', 'N/A')} | {props.get('Context window', 'N/A')}\")
"
```

### Filter by keyword:

Add `if 'image' in item['name'].lower():` inside the loop to filter by model type.

## Secondary: Individual Model Pages

Each model has a dedicated page at `https://zenmux.ai/<provider>/<model>`:

```bash
curl -s https://zenmux.ai/openai/gpt-image-2 | python3 -c "
import sys, json, re
html = sys.stdin.read()
lds = re.findall(r'<script type=\"application/ld\+json\">(.*?)</script>', html, re.DOTALL)
for ld in lds:
    data = json.loads(ld)
    if data.get('@type') == 'SoftwareApplication':
        print(f\"Name: {data['name']}\")
        for p in data.get('additionalProperty', []):
            print(f\"  {p['name']}: {p['value']}\")
"
```

Returns: Provider, Context window, Supported APIs.

## Caveats

- **Token pricing ≠ per-image cost**: Image models consume tokens differently from text models.
  Resolution matters more than prompt length for image models. Always estimate with actual API test.
- **ZenMux is a proxy**: Pricing on ZenMux pages is ZenMux's own pricing (not necessarily the provider's list price).
- **Model IDs**: ZenMux model IDs (e.g. `openai/gpt-image-2`) map to provider models via internal routing.
  The actual provider model name may differ (e.g. Google models have Nickname labels like "Nano Banana 2").

## Example: Image Model Comparison (2026-06)

| Model ID | ZenMux Price (Input/Output per 1M tokens) | Context | Provider |
|----------|:--:|:--:|:--:|
| `openai/gpt-image-2` | $5.00 / $0 | 10K | OpenAI/Azure |
| `google/gemini-3.1-flash-image` | $0.50 / $3.00 | 65K | Google Vertex |
| `google/gemini-3-pro-image` | $2.00 / $12.00 | 65K | Google Vertex |

Features: None support streaming, function calling, structured outputs, or fine-tuning.
