# ZenMux Management API Reference

Source: https://docs.zenmux.ai/guide/quickstart (fetched 2026-05-19)

## Authentication

All Management endpoints require a **Management API Key** (not the regular `sk-ss-v1-` API Key).

```
Authorization: Bearer $ZENMUX_MANAGEMENT_API_KEY
```

Create at: ZenMux Console → Management

---

## Subscription Detail

```
GET https://zenmux.ai/api/v1/management/subscription/detail
```

Response (Ultra plan example):

```json
{
  "success": true,
  "data": {
    "plan": {
      "tier": "ultra",
      "amount_usd": 200,
      "interval": "month"
    },
    "account_status": "healthy",
    "quota_5_hour": {
      "max_flows": 800,
      "used_flows": 57.2,
      "remaining_flows": 742.8,
      "usage_percentage": 0.0715
    },
    "quota_7_day": {
      "max_flows": 6182,
      "used_flows": 416.11,
      "remaining_flows": 5765.89
    }
  }
}
```

### Plan Tiers (Builder Plan)

| Plan  | Price    | 5h Flows | Weekly Flows | Monthly Flows | USD Value | Multiplier |
|-------|----------|----------|--------------|---------------|-----------|------------|
| Free  | $0/mo    | 5        | 38.64        | 165.6         | $5.44     | -          |
| Pro   | $20/mo   | 50       | 213.37       | 914.443       | $30.03    | 1.50x      |
| Max   | $100/mo  | 300      | 1,280.22     | 5,486.659     | $180.15   | 1.80x      |
| Ultra | $200/mo  | 800      | 3,413.921    | 14,631.091    | $480.40   | 2.40x      |

---

## PAYG Balance

```
GET https://zenmux.ai/api/v1/management/payg/balance
```

Response:

```json
{
  "success": true,
  "data": {
    "currency": "usd",
    "total_credits": 482.74,
    "top_up_credits": 35.00,
    "bonus_credits": 447.74
  }
}
```

---

## Flow Rate

```
GET https://zenmux.ai/api/v1/management/flow_rate
```

Response:

```json
{
  "success": true,
  "data": {
    "currency": "usd",
    "base_usd_per_flow": 0.03283,
    "effective_usd_per_flow": 0.03283
  }
}
```

---

## Generation Detail

```
GET https://zenmux.ai/api/v1/management/generation?id=<generation_id>
```

Response (partial):

```json
{
  "api": "chat.completions",
  "generationId": "gen_01abc123def456",
  "model": "openai/gpt-4o",
  "generationTime": 3200,
  "latency": 500,
  "nativeTokens": {
    "completion_tokens": 128,
    "prompt_tokens": 32,
    "total_tokens": 160
  },
  "usage": 0.0052
}
```

**Note:** Billing data (usage, ratingResponses) available 3-5 min after request. Token counts are synchronous.

---

## API Protocols (Model Calling)

These use the **regular API Key** (`sk-ss-v1-*`), NOT the Management Key.

| Protocol              | Base URL                              | Compatible SDK     |
|-----------------------|----------------------------------------|--------------------|
| OpenAI Chat Completions | `https://zenmux.ai/api/v1`           | OpenAI SDK         |
| OpenAI Responses       | `https://zenmux.ai/api/v1`           | OpenAI SDK         |
| Anthropic Messages     | `https://zenmux.ai/api/anthropic`    | Anthropic SDK      |
| Google Gemini          | `https://zenmux.ai/api/vertex-ai`    | Google GenAI SDK   |

Model slug format: `provider/model-name` (e.g., `google/gemini-3.1-pro-preview`)
