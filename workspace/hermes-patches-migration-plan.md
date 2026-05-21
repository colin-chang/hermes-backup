# Hermes Patches 迁移计划：从源码 Patch 到上游 PR

> 最后更新：2026-05-22 | Patch 脚本：`~/.hermes/scripts/hermes-patches.sh`（**12 patches**）
>
> 📋 **Mattermost 插件已完成的迁移**：[mm-plugin-development-plan.md](./mm-plugin-development-plan.md)

## 1. 现状

`hermes-patches.sh` 当前 12 个 patch，每次 `git pull` 后需重新执行。

已通过 `mattermost-enhancer` 插件消除 **4 个** Mattermost 补丁（patch 6, 7, 10c, 11），
剩余 12 个 patch 全部为通用 Bug Fix + 2 个无法插件化的 `run.py` 调用方修改。

```
原 16 个 patch
├── ✅ 4 个已迁移至 mattermost-enhancer 插件
└── ⚠️ 12 个仍需 shell patch
```

## 2. 当前 Patch 清单（对齐 `hermes-patches.sh check` 输出）

| # | 文件 | 影响 | 类型 |
|---|------|------|------|
| 1 | `hermes_cli/providers.py` | 自定义 provider (custom:*) 被误判为非聚合器 | Bug Fix |
| 2 | `hermes_cli/doctor.py` | 自定义 provider 触发 vendor-prefix 假阳性警告 | Bug Fix |
| 3a | `hermes_cli/model_switch.py` | 模型切换忽略 config.yaml §3 models 白名单 | Bug Fix |
| 3b | `hermes_cli/model_switch.py` | 模型切换忽略 custom_providers §4 models 白名单 | Bug Fix |
| 4a | `gateway/config.py` | gateway_restart_notification 配置桥接遗漏 | Bug Fix |
| 4b | `gateway/config.py` | gateway_restart_notification 无法从 extra 回退读取 | Bug Fix |
| 5 | `cron/jobs.py` | Cron job 存储中文被转义为 \uXXXX | Bug Fix |
| 9 | `utils.py` | YAML 写入中文被转义为 \uXXXX | Bug Fix |
| 8b | `gateway/run.py` | Mattermost 工具进度消息不进 Thread | Feature (run.py) |
| 10a | `gateway/run.py` | MEDIA 正则过宽导致误匹配非文件路径 | Bug Fix |
| 10b | `gateway/platforms/base.py` | MEDIA 提取正则 \S+ 兜底分支过宽 | Bug Fix |
| 8 | `gateway/run.py` | Mattermost DM 审批缺少 user_id 参数 | Feature (run.py) |

## 3. 已迁移至插件的 Patch（不再需要 shell patch）

| Patch | 功能 | 插件中的对应实现 |
|-------|------|----------------|
| 6a-6d | Thread root_id 解析 (`_resolve_root_id`) | `adapter.py`: `_resolve_root_id()`, `send()`, `_send_local_file()`, `_send_url_as_file()` 覆写 |
| 7a-7d | DM 审批基础设施 (~400行) | `adapter.py`: `send_exec_approval()`, `_handle_callback()`, `_start_callback_server()`, `connect()`, `disconnect()` 等 |
| 10c | MEDIA 文件不存在时静默跳过 | `adapter.py`: `_send_local_file()` 覆写 |
| 11 | send_typing Thread 路由 | `adapter.py`: `send_typing()` 覆写 |

## 4. 分阶段替代方案

### 阶段一：Bug Fix → 提 PR 到上游（消除 8/12 patches）

| PR | 包含 Patch | 主题 |
|----|-----------|------|
| PR-1 | 1, 2, 3a, 3b | `custom:*` provider 聚合器识别 + models 白名单优先 |
| PR-2 | 4a, 4b | `gateway_restart_notification` 配置桥接修复 |
| PR-3 | 5, 9 | 中文/Unicode 编码修复（ensure_ascii + allow_unicode） |
| PR-4 | 10a, 10b | MEDIA 提取正则收紧 |

### 阶段二：run.py Feature → 提 PR 或 .pth（消除 2/12 patches）

| Patch | 文件 | 问题 | 方案 |
|-------|------|------|------|
| 8 | `run.py` | `send_exec_approval` 缺 `user_id` 参数 | 提 PR 让调用方自动传入 `source.user_id` |
| 8b | `run.py` | `_progress_reply_to` 遗漏 Mattermost | 提 PR 补上 `Platform.MATTERMOST` 判断 |

> 这两个修改的是 `run.py` 调用方代码，插件无法触及。如上游不合入，可用 `.pth` runtime 注入替代 shell patch。

## 5. `.pth` Runtime 注入（plan B）

Python 启动时扫描 `site-packages/*.pth`，逐行执行。利用 `import` 副作用可 monkey-patch 任意模块：

```
~/.hermes/venv/lib/.../site-packages/hermes_mm_patches.pth
─────────────────────────────────────────────
import hermes_mm_patches
```

```python
# ~/.hermes/scripts/hermes_mm_patches.py
import gateway.run as _run

# Patch 8: 补 user_id
_orig = _run.GatewayRunner._some_method
def _patched(self, source, ...):
    ...
_run.GatewayRunner._some_method = _patched
```

| | Platform Plugin | `.pth` Runtime 注入 |
|---|---|---|
| 原理 | 官方 `register_platform` API | Python import 副作用 |
| 可达范围 | 仅适配器方法 | **任意模块**（含 `run.py`） |
| 稳定性 | ✅ 有版本契约 | ⚠️ 依赖内部实现细节 |
| 失败影响 | 回退到内置适配器 | 可能阻止 Gateway 启动 |

## 6. 推荐执行路线

```
现在                         短期（2-4周）                 长期
─────                       ──────────────                ─────
12 patches              →   提 4 个 PR 消除 10 个    →   全合入上游
MM 插件 4 个已迁移          run.py 2 个提 PR/.pth      零 patch 运行
```
