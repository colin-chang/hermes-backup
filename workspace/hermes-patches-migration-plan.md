# Hermes Patches 迁移计划：从源码 Patch 到上游 PR + 插件化

> 审阅时间：2026-05-19 | 最后更新：2026-05-19 | Patch 脚本：`~/.hermes/scripts/hermes-patches.sh`（1270 行，15 patches）
>
> 📋 **详细开发计划**：[mm-plugin-development-plan.md](./mm-plugin-development-plan.md) — 插件架构设计、接口契约、卡片 UI 设计、迁移步骤、验证清单

## 1. 现状

当前 `hermes-patches.sh` 包含 15 个 patch，每次 `git pull` 更新后必须重新执行。
随着 patch 数量和体积增长，维护成本和脆弱性持续上升。

## 2. Patch 分类

### 🟢 Bug Fix（上游应修）— 10 个

| # | 文件 | 问题 | 本质 |
|---|------|------|------|
| 1 | `hermes_cli/providers.py` | `is_aggregator()` 不识别 `custom:*` | 逻辑遗漏 |
| 2 | `hermes_cli/doctor.py` | vendor-prefix 误报 `custom:*` | 同上 |
| 3a | `hermes_cli/model_switch.py` | §3 `models:` 白名单被忽略，总是拉线上目录 | 逻辑错误 |
| 3b | `hermes_cli/model_switch.py` | §4 同上，custom_providers 分支 | 同上 |
| 4a | `gateway/config.py` | bridging loop 遗漏 `gateway_restart_notification` | 配置键遗漏 |
| 4b | `gateway/config.py` | `from_dict()` 不从 extra fallback 读取 | 同上 |
| 5 | `cron/jobs.py` | `json.dump` 缺 `ensure_ascii=False` → 中文 `\uXXXX` | 国际化 bug |
| 9 | `utils.py` | `yaml.dump` 缺 `allow_unicode=True` → 中文 `\uXXXX` | 同上 |
| 8b | `gateway/run.py` | `_progress_reply_to` 只判断 `Platform.FEISHU`，Mattermost 缺失 → 工具进度回退到频道主会话流 | 逻辑遗漏 |
| 10a | `gateway/run.py` | MEDIA 正则 `MEDIA:\S+` 过宽 | 正则 bug |
| 10b | `gateway/platforms/base.py` | `extract_media()` 的 `\S+` 兜底分支 | 同上 |
| 10c | `gateway/platforms/mattermost.py` | 文件不存在时发噪声消息到频道 | 用户体验 bug |

### 🟠 Feature（自定义功能）— 3 个（含子 patch）

| # | 文件 | 功能 | 代码量 |
|---|------|------|--------|
| 6a-d | `mattermost.py` | `_resolve_root_id()` + 3 处调用替换 | ~50 行 |
| 7a-d | `mattermost.py` | DM 审批基础设施（callback server + 方法 + 生命周期） | ~400 行 |
| 8 | `gateway/run.py` | `send_exec_approval` 传入 `user_id` | 1 行 |

## 3. 分阶段替代方案

### 阶段一：Bug Fix → 提 PR 到上游（消除 10/15 patches）

**收益最大、风险最低。** 这些都是 Hermes 的 bug，不是自定义需求。

**建议的 PR 分组：**

| PR | 包含 Patch | 主题 | 合入概率 |
|----|-----------|------|---------|
| PR-1 | 1, 2, 3a, 3b | `custom:*` provider 聚合器识别 + models 白名单优先 | 高 |
| PR-2 | 4a, 4b | `gateway_restart_notification` 配置桥接修复 | 高 |
| PR-3 | 5, 9 | 中文/Unicode 编码修复（ensure_ascii + allow_unicode） | 高 |
| PR-4 | 10a, 10b, 10c | MEDIA 提取正则收紧 + 静默跳过 | 高 |

**PR 提交策略：**
- 每组 PR 独立，互不依赖
- 描述清楚 bug 复现路径和影响
- 附带最小化测试用例
- PR 合入后从 `hermes-patches.sh` 移除对应 patch

### 阶段二：Mattermost Thread 修复 → 提 PR（消除 patch 6 + 8b）

这是 Mattermost 适配器的两个通用 bug：

**Patch 6 — `_resolve_root_id()`：**
- CRT 模式下 `root_id` 必须指向 thread 根帖子
- 用回复 ID 作为 `root_id` 导致 400 Invalid RootId
- **不限于 DM 审批场景**，任何 thread 内回复都会触发

**Patch 8b — `_progress_reply_to` 遗漏 Mattermost：**
- `gateway/run.py:14787` 的 `_progress_reply_to` 条件只判断了 `Platform.FEISHU`
- Mattermost 被遗漏，导致工具进度消息的 `reply_to` 始终为 `None`
- 表现为：工具链调用回退到频道主会话流，而非 Thread 内展示
- 修复：一行代码 — `Platform.FEISHU` → `(Platform.FEISHU, Platform.MATTERMOST)`
- 配套需在 `config.yaml` 的 `mattermost:` section 显式设置 `reply_mode: thread`（因 `.env` 的 `MATTERMOST_REPLY_MODE` 不会被 config bridging loop 桥接）

**建议：** 合并到阶段一的 PR-4，或单独提一个 Mattermost Thread Fix PR。

### 阶段三：DM 审批 + Slash 指令 → 统一 Platform Plugin（消除 patches 7-8）

**架构转型核心。** 将 DM 审批（~400 行）、`/model`、`/new` 指令统一封装为一个 Hermes Platform Plugin。
目标：**零源码修改 + 一个插件覆盖所有 Mattermost 自定义能力。**

#### 插件范围：三合一

| 功能模块 | 描述 | 当前状态 |
|---------|------|---------|
| **DM 审批** | 危险命令二级确认（Allow Once / Session / Always / Deny） | 已通过 patch 7 实现，待迁移入插件 |
| **`/model` 指令** | 当前 session 切换模型，渲染模型选择卡片 | 新功能，通过 Mattermost 自定义 Slash 指令触发 |
| **`/new` 指令** | 重置当前 session 上下文，渲染确认卡片 | 新功能，通过 Mattermost 自定义 Slash 指令触发 |

#### Session 作用域（关键约束）

| 指令 | 作用域 | Thread 模式下 | 扁平模式下 |
|------|--------|-------------|-----------|
| `/model` | 当前 session | ✅ 切换当前 Thread 模型，不影响其他 Thread | ✅ 切换当前 Channel 模型 |
| `/new` | 当前 session | ⚠️ 意义不大（发新消息即可创建新 Thread/新 Session） | ✅ 唯一重置 Session 的方式 |

#### `/model` 和 `/new` 触发方式

由于 Mattermost 客户端在发消息前就拦截 `/` 前缀（未命中内置/自定义指令则报错，消息不送达 Bot），必须走 **Mattermost 自定义 Slash 指令**：

```
用户在 Thread 内输入 /model
  → Mattermost 客户端拦截 → 匹配自定义 Slash 指令
    → POST http://<host>:18065/mm-command
      → Plugin callback server 接收
        → 识别 command=/model
          → 渲染模型选择卡片到当前 Thread
            → 用户点击卡片按钮
              → POST http://<host>:18065/mm-callback
                → Plugin 执行 session 级模型切换
```

> **注意**：Mattermost 自定义 Slash 指令需在 System Console → Integrations 中手动配置。这是**一次性 setup**，不属于持续维护负担。Plugin 只负责接收 POST 后的逻辑。

#### 插件架构（更新后）

```
~/.hermes/plugins/mattermost-approval/
├── plugin.yaml              # name, version, min_hermes_version
├── __init__.py              # register_platform("mattermost", priority=100)
├── adapter.py               # MattermostApprovalAdapter(MattermostAdapter)
├── callback_server.py       # HTTP server (port 18065):
│                            #   /mm-callback  → DM 审批按钮回调
│                            #   /mm-command   → Slash 指令处理 (/model, /new)
├── cards.py                 # 卡片渲染：
│                            #   render_approval_card()
│                            #   render_model_selector_card()
│                            #   render_new_session_confirm_card()
└── models.py                # 模型列表获取 + 合法性校验
```

**plugin.yaml：**
```yaml
name: mattermost-approval
version: 2.0.0
description: >
  Mattermost DM 审批 + /model + /new 指令统一插件。
  覆盖内置 MattermostAdapter，追加 Interactive Message 能力。
kind: platform
requires_env:
  - MATTERMOST_CALLBACK_URL
  - MATTERMOST_CALLBACK_BIND
  - MATTERMOST_CALLBACK_PORT
min_hermes_version: "2.0.0"
```

**callback_server 路由设计：**

| 路由 | 方法 | 来源 | 处理逻辑 |
|------|------|------|---------|
| `/mm-callback` | POST | DM 审批卡片按钮点击 | `_handle_approval_callback()` |
| `/mm-command` | POST | Mattermost 自定义 Slash 指令 | `_handle_slash_command()` → 分发到 `/model` 或 `/new` 处理器 |

**卡片设计要点：**

`/model` 卡片：
- 列出可用模型为按钮（从 `config.yaml` 的 `custom_providers` + 内置 provider 获取）
- 每个模型一个按钮，`action: "cmd_model_switch"`, `context.model_id: "xxx"`
- 按钮风格：当前模型高亮，其余默认

`/new` 卡片：
- 确认/取消两个按钮
- `action: "cmd_new_confirm"` / `action: "cmd_new_cancel"`
- 在 Thread 模式下可显示提示"Thread 模式下直接发新消息即可创建新会话"

**session 级操作实现：**

模型切换和 session 重置都只影响当前 Mattermost Thread/Channel：
- 通过 callback payload 中的 `channel_id` + `root_id`（Thread 模式）或 `channel_id`（扁平模式）定位 session
- 调用 `_resolve_root_id()` 确保 Thread 场景正确
- 模型切换：修改 session 的 `model` 配置
- Session 重置：调用 `session_store.reset_session()`

#### 阻塞点与解决方案

| 阻塞点 | 说明 | 解决方案 |
|--------|------|---------|
| `run.py` patch 8 | `send_exec_approval` 调用需传入 `user_id`，适配器无法控制调用方 | 给上游提 PR 让调用方自动传入 `source.user_id`；或用 `pre_gateway_dispatch` hook 拦截 |
| `_resolve_root_id` 覆盖 `send()` | 子类覆盖父类方法即可，无需修改源码 | ✅ 插件可解决 |
| callback server 生命周期 | 覆盖 `connect()`/`disconnect()` | ✅ 插件可解决 |
| Mattermost 自定义 Slash 指令配置 | 需 admin 在 System Console 手动配置 | ⚠️ 一次性 setup，非持续维护负担 |
| `/model` 卡片模型列表来源 | 需获取可用模型列表 | 从 `config.yaml` + `_get_available_models()` API 获取 |
| Session 定位 | callback payload 中的 channel_id/root_id 需映射到 session | 复用现有 `build_session_key()` 逻辑 |

### 阶段四：剩余无法插件的 patch → `.pth` Runtime 注入

对于**必须修改调用方代码**的 patch（如 `run.py` 的 `user_id` 传入），
如果上游暂不合入 PR，可用 Python `.pth` 文件实现 runtime monkey-patch：

```
# venv/lib/python3.11/site-packages/hermes_runtime_patches.pth
import hermes_runtime_patches
```

```python
# ~/.hermes/scripts/hermes_runtime_patches.py
"""Runtime monkey-patches — import 时自动注入，不修改源码文件"""
import gateway.run as _run

_original_send_approval = _run.GatewayRunner._send_approval

def _patched_send_approval(self, ..., **kwargs):
    kwargs.setdefault('user_id', source.user_id)
    return _original_send_approval(self, ..., **kwargs)

_run.GatewayRunner._send_approval = _patched_send_approval
```

**优缺点：**
- ✅ 不修改源码文件，升级不覆盖
- ⚠️ 依赖内部 API 稳定性，上游重构可能导致 patch 失效
- ⚠️ 需要在 `.pth` 中引用，增加启动依赖

## 4. 推荐执行路线

```
现在                              短期（2-4周）                    长期
─────                            ──────────────                   ─────
15 patches 脚本             →   提 PR 消除 10 个 bug fix     →   全部合入上游
1238+ 行                        + 1 个 Mattermost Thread PR       零 patch 运行
                                 DM 审批转 platform plugin
                                 剩余 1-2 个用 .pth 注入
```

**优先级：**
1. 🔴 **先提 PR**（patches 1-5, 8b, 9-10c + patch 6）→ 收益最大，可能消除 13/15 patches
2. 🟡 **统一插件开发**（patch 7 + `/model` + `/new`）→ 架构最优雅，一个插件覆盖所有 Mattermost 自定义能力
3. 🟢 **run.py user_id 提 PR 或 .pth**（patch 8）→ 等阶段三验证后决定

详细开发计划见 **[mm-plugin-development-plan.md](./mm-plugin-development-plan.md)**。

## 5. 验证清单

### 插件兼容性验证（阶段三前置）

- [ ] `register_platform(name="mattermost")` 能否覆盖内置适配器？
- [ ] 子类覆盖 `connect()`/`disconnect()` 后，gateway 生命周期是否正常？
- [ ] 插件中的 `send_exec_approval` 是否被 `run.py` 正确发现（`getattr(type(adapter), "send_exec_approval", None)`）
- [ ] 环境变量（`MATTERMOST_CALLBACK_URL` 等）在插件中能否正常读取？
- [ ] `plugins.enabled` 配置是否需要显式添加？

### PR 提交前验证

- [ ] 每个 PR 基于最新 `main` 分支
- [ ] 修改通过 `python -m pytest tests/` 相关测试
- [ ] 修改不影响现有功能（向后兼容）
