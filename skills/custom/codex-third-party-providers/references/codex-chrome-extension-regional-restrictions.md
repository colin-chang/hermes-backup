# Codex Chrome Extension — Regional Restrictions

## Problem

Installing the Codex Chrome extension from Chrome Web Store fails with:
- **中文**: "此商品无法购买或下载"
- **English**: "This item cannot be purchased or downloaded"

## Root Cause

OpenAI set **regional availability gating** in the Chrome Web Store developer console. The restriction is bound to the **Google account's registered country**, not the network IP — VPN alone may not be enough.

**Affected regions**: Mainland China, Hong Kong, EU, Switzerland, and other non-whitelisted countries.

**Extension ID**: `hehggadaopoacecdllhhajmbjkdcmjag`
**Store URL**: `https://chromewebstore.google.com/detail/codex/hehggadaopoacecdllhhajmbjkdcmjag`

## Workarounds (macOS)

### 1. Direct CRX download via Google Update Service ⭐ (safest — pulls from Google CDN)

Google's extension update service has no regional restrictions at the CRX delivery layer:

```
https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3&x=id%3Dhehggadaopoacecdllhhajmbjkdcmjag%26uc
```

Paste in Chrome address bar → downloads `.crx` file → rename to `.zip` → extract → load unpacked.

### 2. Sideload via Developer Mode

```bash
# Download CRX, extract, load as unpacked extension
curl -L -o /tmp/codex.crx "<crx_url>"
mkdir -p ~/codex-extension/
cd ~/codex-extension/
unzip /tmp/codex.crx
# Chrome → chrome://extensions/ → Developer Mode ON → "Load unpacked" → select ~/codex-extension/
```

### 3. VPN + Google account country change

1. Connect to US VPN
2. Change Google Pay profile country to US
3. Clear browser cache, retry Chrome Web Store

If account country can't be changed, create a new US-region Google account.

## GitHub Issues

- `openai/codex#21700` (21 comments, open)
- `openai/codex#29102`, `#27397`

OpenAI has not provided an official offline installer or commented on the regional restriction.
