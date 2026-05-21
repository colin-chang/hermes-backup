# Hermes Patches 迁移计划：从源码 Patch 到上游 PR

> 最后更新：2026-05-22 | Patch 脚本：`~/.hermes/scripts/hermes-patches.sh`（**12 patches**）
>
> 📋 **Mattermost 插件已完成的迁移**：[mm-plugin-development-plan.md](./mm-plugin-development-plan.md)

## 1. 现状

`hermes-patches.sh` 当前 12 个 patch，每次 `git pull` 后需重新执行。

已通过 `mattermost-enhancer` 插件消除 **4 个** Mattermost 补丁，
剩余 12 个 patch：**10 个通用 Bug Fix** + **2 个无法插件化的 run.py Feature**。

```
原 16 个 patch
├── ✅ 4 个已迁移至 mattermost-enhancer 插件
└── ⚠️ 12 个仍需 shell patch
```

## 2. 当前 Patch 清单（每个 Patch 解决什么用户问题）

| # | 文件 | 用户看到的问题 | 类型 |
|---|------|--------------|------|
| 1 | `hermes_cli/providers.py` | 模型列表里塞了 100+ 个模型，乱糟糟的找不到想要的（你的 whitelist 被忽略了） | Bug Fix |
| 2 | `hermes_cli/doctor.py` | `hermes doctor` 报出一堆"模型不匹配"的假警告，以为 Hermes 出 bug 了 | Bug Fix |
| 3a | `hermes_cli/model_switch.py` | 同上——你在 config 里设了 models 白名单，但切换模型时没生效 | Bug Fix |
| 3b | `hermes_cli/model_switch.py` | 同上——custom_providers 里的 models 白名单也被无视了 | Bug Fix |
| 4a | `gateway/config.py` | 明明关了"Gateway 即将关闭"通知，重启时还是收到这条烦人的消息 | Bug Fix |
| 4b | `gateway/config.py` | 同上——从另一个代码路径读取配置时也漏了 | Bug Fix |
| 5 | `cron/jobs.py` | 定时任务的描述里中文全变成了 `\uXXXX` 乱码，完全看不懂写了什么 | Bug Fix |
| 9 | `utils.py` | config.yaml 里的中文注释被保存成 `\uXXXX` 转义符，全变乱码 | Bug Fix |
| 8b | `gateway/run.py` | 在 Thread 里等 AI 干活，中间进度提示全跑到频道里去了，Thread 里一片空白 | Feature |
| 10a | `gateway/run.py` | 聊天里突然冒出一条 `(file not found: /tmp/xxx.png)` 垃圾消息，莫名其妙 | Bug Fix |
| 10b | `gateway/platforms/base.py` | 同上——另一个提取路径的正则也太宽，抓到了假文件路径 | Bug Fix |
| 8 | `gateway/run.py` | 危险命令的审批卡片发不到你的私信，Hermes 不知道该发给谁 | Feature |

## 3. 已迁移至插件的 Patch（不再需要 shell patch）

| Patch | 功能 | 插件中的对应实现 |
|-------|------|----------------|
| 6a-6d | Thread root_id 解析 (`_resolve_root_id`) | `adapter.py`: `_resolve_root_id()`, `send()`, `_send_local_file()`, `_send_url_as_file()` 覆写 |
| 7a-7d | DM 审批基础设施 (~400行) | `adapter.py`: `send_exec_approval()`, `_handle_callback()`, `_start_callback_server()`, `connect()`, `disconnect()` 等 |
| 10c | MEDIA 文件不存在时静默跳过 | `adapter.py`: `_send_local_file()` 覆写 |
| 11 | send_typing Thread 路由 | `adapter.py`: `send_typing()` 覆写 |

## 4. 分阶段替代方案

### 阶段一：Bug Fix → 提 PR 到上游（消除 10/12 patches）

| PR | 包含 Patch | 解决的用户问题 |
|----|-----------|--------------|
| PR-1 | 1, 2, 3a, 3b | 自定义 provider 的模型列表混乱 + doctor 假警告 |
| PR-2 | 4a, 4b | 关不掉"Gateway 即将关闭"的烦人通知 |
| PR-3 | 5, 9 | 中文配置和 cron 描述被存成乱码 |
| PR-4 | 10a, 10b | 聊天里莫名出现 `(file not found: ...)` 垃圾消息 |

### 阶段二：run.py Feature → 提 PR 或 .pth（消除 2/12 patches）

| Patch | 文件 | 用户看到的问题 | 方案 |
|-------|------|--------------|------|
| 8 | `run.py` | 审批卡片发不到私信 | 提 PR 让调用方自动传入 user_id |
| 8b | `run.py` | Thread 里看不到任务进度 | 提 PR 补上 Mattermost 的进度路由 |

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
现在                          短期                         长期
─────                        ──────────                   ─────
12 个 patch 靠脚本撑着   →   提 4 个 PR 消掉 10 个   →   全部合入上游
MM 插件已消掉 4 个           run.py 2 个 PR 或 .pth      彻底告别 shell patch
```
