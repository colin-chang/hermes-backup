# CC Switch + Codex Desktop 认证架构

> 分析日期：2026-06-21  
> CC Switch 版本参考：v3.16.3  
> 源码参考：`src-tauri/src/codex_config.rs`

## 核心认知

**CC Switch 接管了 Codex 的 API 路由（模型请求走第三方），但没有接管 Codex Desktop 的身份认证流程（OAuth 登录仍直连 OpenAI）。**

## CC Switch 接管 Codex 的实际操作

CC Switch 只修改一个文件：`~/.codex/config.toml`

```toml
model_provider = "zenmux"
model = "deepseek/deepseek-v4-pro"

[model_providers.zenmux]
name = "ZenMux"
wire_api = "responses"
requires_openai_auth = true          # ← 关键字段
base_url = "http://127.0.0.1:15721/v1"
experimental_bearer_token = "PROXY_MANAGED"
```

CC Switch **有意不写 `~/.codex/auth.json`**，只写 `config.toml`。这是源码中的设计决策——保护用户 ChatGPT 登录态不被第三方 provider 覆盖。

## `requires_openai_auth = true` 的含义

CC Switch 源码注释：`requires_openai_auth` routes auth to the ChatGPT login in `auth.json`

- **为 true** → Codex 必须通过 `auth.json` 中的 OAuth 凭据或 API Key 认证
- **为 false** → Codex 可以无认证启动（纯 API Key 模式）
- CC Switch 对第三方 provider 的预设模板中，此字段默认 `true`

## Codex CLI vs Desktop App 认证流程差异

```
Codex CLI 启动：
  config.toml → experimental_bearer_token → 直连 base_url
  ✅ auth.json 不存在也能工作（CC Switch proxy 注入 token）

Codex Desktop App 启动：
  Electron 启动 → 检查 requires_openai_auth → 查找 auth.json
  → auth.json 不存在 → 弹出 OAuth 登录窗口
  ❌ 登录流程绕过 CC Switch 代理，直连 OpenAI 服务器
```

Desktop App 是一个完整的 Electron 应用，有独立的 GUI OAuth 登录流程，这个流程发生在任何 API 调用之前，不受 CC Switch 代理控制。

## 为什么 Claude Code / Hermes 没有这个问题

| 工具 | CC Switch 接管方式 | 认证机制 |
|------|-------------------|---------|
| Claude Code | `~/.claude/settings.json`（API key + base_url） | 纯 API Key，无 OAuth 登录 |
| Hermes | `~/.hermes/config.yaml`（custom_providers） | 纯 API Key，无 OAuth 登录 |
| Codex Desktop | `~/.codex/config.toml` | **有独立 OAuth 登录流程** |

## 解决方案

### 方案 A（推荐）：登录一次 OpenAI 账号，生成 auth.json

1. 在 CC Switch 中切换到 Codex 官方 provider（`OpenAI Official`）
2. 打开 Codex Desktop → 完成 OpenAI 登录（免费账号即可）
3. 登录成功后 `~/.codex/auth.json` 被写入（包含 OAuth tokens）
4. 回到 CC Switch，切换回第三方 provider
5. 此后 `auth.json` 一直存在，Desktop 不再弹登录

CC Switch FAQ 印证：「How do I switch back to official login? Add an official provider, run the Log out / Log in flow, then switch back.」

### 方案 B：手动设置 `requires_openai_auth = false`

修改 `~/.codex/config.toml` 中 `[model_providers.zenmux]` 下的 `requires_openai_auth = false`。取决于 Codex Desktop 版本是否允许无认证启动。

### 方案 C：只用 Codex CLI

`codex exec` 命令不需要 GUI 登录，CC Switch proxy token 注入直接生效。

## 排障诊断命令

```bash
# 检查 config.toml 中的关键字段
grep -E 'requires_openai_auth|model_provider|experimental_bearer_token' ~/.codex/config.toml

# 检查 auth.json 是否存在
ls -la ~/.codex/auth.json

# 检查 CC Switch 中 Codex 的活跃 provider
python3 -c "
import sqlite3, json
conn = sqlite3.connect('$HOME/.cc-switch/cc-switch.db')
cur = conn.cursor()
cur.execute('SELECT id, name, category, is_current FROM providers WHERE app_type=?', ('codex',))
for r in cur.fetchall():
    print(f'id={r[0]} | name={r[1]} | cat={r[2]} | current={r[3]}')
conn.close()
"
```

## CC Switch 架构速览

```
CC Switch Desktop App (Tauri 2)
├── 前端 (React + TypeScript)
└── 后端 (Rust)
    ├── ProviderService → 管理 7 个工具的 provider 配置
    ├── ProxyService → 本地代理（127.0.0.1:15721）热切换 + 格式转换
    ├── ConfigService → 原子写入配置文件
    └── 数据库 → ~/.cc-switch/cc-switch.db (SQLite)

每个工具的接管方式：
  Claude Code   → ~/.claude/settings.json
  Claude Desktop → ~/Library/Application Support/Claude/claude_desktop_config.json
  Codex         → ~/.codex/config.toml + ~/.codex/auth.json
  Gemini CLI    → ~/.gemini/settings.json
  OpenCode      → ~/.opencode/config.json
  OpenClaw      → AGENTS.md + SOUL.md
  Hermes        → ~/.hermes/config.yaml
```

## 相关源码要点（CC Switch `codex_config.rs`）

- **`write_codex_live_for_provider()`**：非官方 provider + `preserve_codex_official_auth_on_switch()` 开启时，只写 `config.toml`，不写 `auth.json`
- **`prepare_codex_provider_live_config()`**：把 `auth.OPENAI_API_KEY` 转为 `config.toml` 中的 `experimental_bearer_token`
- **`extract_codex_experimental_bearer_token()`**：从 config 中提取 bearer token，优先 `model_providers.<active>.experimental_bearer_token`，fallback 顶级 `experimental_bearer_token`

---

## 模型切换失效问题（登录正常但模型列表只有 1 个）

> 补充日期：2026-06-21

### 症状

CC Switch Proxy 关闭后，Codex Desktop 能正常启动（绕过登录），但模型选择器只显示一个模型（`config.toml` 中 `model=` 指定的那个），无法切换。

### 根因：`model_catalog_json` 相对路径

Codex 的模型发现有三层优先级：

```
① models_cache.json（在线拉取缓存）    → 不存在（从未生成）
② 在线从 Provider API 拉取模型列表      → 未触发/格式不匹配
③ model_catalog_json 静态 catalog 文件  → 相对路径解析失败
```

CC Switch 写入的 `config.toml` 中：

```toml
model_catalog_json = "cc-switch-model-catalog.json"   # 相对路径
```

Codex Desktop 启动时 CWD 不是 `~/.codex/`，相对路径解析到错误位置 → catalog 未被加载 → 模型列表回退到只有 `model=` 指定的默认模型。

用 `codex debug models` 验证：若输出模型数 = 1 且 `context_window` 是 GPT-5.5 模板默认值（400K），说明 catalog 没被加载。加载后 `context_window` 会匹配 catalog 中的实际值。

### 修复

将 `model_catalog_json` 改为**绝对路径**：

```toml
model_catalog_json = "/Users/Colin/.codex/cc-switch-model-catalog.json"
```

验证：`codex debug models` 输出 11 个模型，`context_window` 与 catalog 一致。

### CC Switch Proxy 的角色

Proxy 开启时，模型发现走完全不同的路径——Proxy **拦截** `model/list` RPC 请求，直接读取 catalog JSON 并返回完整列表。这是为什么 Proxy 模式下模型切换正常、直连模式反而失效。

### 诊断命令

```bash
# 查看 Codex 当前加载的模型列表
/Applications/Codex.app/Contents/Resources/codex debug models

# 查看模型 catalog 中有多少模型
python3 -c "
import json
with open('/Users/Colin/.codex/cc-switch-model-catalog.json') as f:
    data = json.load(f)
print(f'Models in catalog: {len(data[\"models\"])}')
"

# 分析 Codex 模型发现日志
python3 -c "
import sqlite3
conn = sqlite3.connect('$HOME/.codex/logs_2.sqlite')
cur = conn.cursor()
cur.execute('''SELECT ts, level, target, feedback_log_body 
               FROM logs 
               WHERE target LIKE '%models_manager%'
               ORDER BY id DESC LIMIT 20''')
for row in cur.fetchall():
    print(f'[{row[0]}] [{row[1]}] {row[2]}: {row[3][:200] if row[3] else \"(empty)\"}')
conn.close()
"
```
