# Mattermost 插件迁移模式与陷阱

> 记录从 `hermes-patches.sh` 向 `mattermost-enhancer` 插件迁移代码的模式、经验教训和验证清单。

## 1. 迁移原则

### 1.1 哪个能迁、哪个不能

| 修改位置 | 可插件化 | 方式 |
|---------|:---:|------|
| `mattermost.py` — Adapter 方法 | ✅ | 类覆写（`super()` 继承） |
| `mattermost.py` — `__init__` 属性 | ✅ | 子类 `__init__` 覆写 + `super().__init__()` |
| `mattermost.py` — `connect()/disconnect()` | ✅ | 子类覆写生命周期方法 |
| `run.py` — 调用方传参（如 `user_id`） | ❌ | 只能上游 PR 或 `.pth` runtime 注入 |
| `run.py` — 条件判断（如 `Platform.MATTERMOST`） | ❌ | 同上 |
| `base.py` — 正则/通用逻辑 | ❌ | 不影响 Mattermost 专属行为 |

### 1.2 迁移后验证清单

```bash
# 1. 源文件零修改
grep "Hermes Patch" gateway/platforms/mattermost.py     # → 0 matches
grep "_callback_server\|_resolve_root_id" gateway/platforms/mattermost.py  # → 0 matches

# 2. 源文件行数与上游一致
git show a91a57fa5:gateway/platforms/mattermost.py | wc -l  # 852

# 3. hermes-patches.sh 语法正确
bash -n ~/.hermes/scripts/hermes-patches.sh

# 4. 插件方法完整
python3 -c "
import ast
with open('$PLUGIN_DIR/adapter.py') as f:
    tree = ast.parse(f.read())
funcs = {n.name for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
required = {'_resolve_root_id', 'send', '_send_local_file', '_send_url_as_file',
            'send_exec_approval', '_start_callback_server', '_handle_callback',
            'connect', 'disconnect', 'send_typing'}
print('Missing:', required - funcs) if required - funcs else print('All present')
"
```

---

## 2. 方法覆写模式

### 2.1 覆写父类方法时复制完整方法体

当覆写 `send()`/`_send_local_file()`/`_send_url_as_file()` 等方法时，**必须复制父类的完整方法体**（非仅修改差异部分）。原因：

- 父类方法包含完整实现（HTTP 调用、重试逻辑、文件上传等）
- `super()` 调用返回的是**父类版本**，不是我们修改的版本
- 无法用 `super()` + 增量修改的方式实现（父类方法直接 `_api_post`，没有钩子点）

**正确模式**：复制 → 修改差异行 → 添加注释标记修改点：

```python
async def send(self, chat_id, content, reply_to=None, metadata=None):
    """覆写父类 send()：将 root_id 解析为 thread 根帖子 ID."""
    if not content:
        return SendResult(success=True)
    formatted = self.format_message(content)
    chunks = self.truncate_message(formatted, MAX_POST_LENGTH)
    # ... 完整方法体 ...
    if reply_to and self._reply_mode == "thread":
        payload["root_id"] = await self._resolve_root_id(reply_to)  # ← 修改点
```

### 2.2 `_get_thread_root_id` helper 模式

对多处需要 `_resolve_root_id` 的代码，提取为辅助方法避免重复：

```python
async def _get_thread_root_id(self, reply_to: Optional[str]) -> Optional[str]:
    """Resolve reply_to → thread root_id when in thread mode."""
    if reply_to and self._reply_mode == "thread":
        return await self._resolve_root_id(reply_to)
    return None

# 调用处简化为：
root_id = await self._get_thread_root_id(reply_to)
if root_id:
    payload["root_id"] = root_id
```

---

## 3. 双重调用陷阱（P34）

### 3.1 成因

源文件 patch 残留 + 插件覆写 = 同一操作执行两次。

**典型案例 — `connect()`**：
```
插件 connect()
  → super().connect()           # 源文件 connect() 已有 patch → 调用 _start_callback_server()
  → _start_callback_server()    # 插件自己也调 → 第二次启动，端口冲突！
```

### 3.2 预防

- **永远先回滚源文件**，再让插件接管
- 插件 `connect()`/`disconnect()` 中调用 `super()` 后检查父类是否已有相同逻辑
- 迁移完成后做 smoke test：重启 Gateway 并确认 callback server 只启动一次

---

## 4. `hermes-patches.sh` 修改技巧

### 4.1 大块删除：用 `execute_code` + line slicing

`patch` 工具在 heredoc/f-string 文本上容易损坏。对于 20+ 行的删除，用 Python 脚本：

```python
with open('hermes-patches.sh') as f:
    lines = f.readlines()

# 找到删除边界
start = next(i for i, l in enumerate(lines) if "── 7. gateway" in l)
end = next(i for i, l in enumerate(lines) if "── 8. gateway" in l and i > start)

# 精确删除
del lines[start:end]
with open('hermes-patches.sh', 'w') as f:
    f.writelines(lines)
```

### 4.2 注册表条目同步

每次删除 `apply_all()` 中的 `_do_patch` 块时，**必须同步删除** `_patch_registry` 数组中对应条目，否则 `show_status()` 会报告幽灵 patch。

### 4.3 头部注释更新

迁移完成后更新文件头注释，将已迁移 patch 标记为 `❌`：

```
#   6.  gateway/platforms/mattermost.py   — ❌ _resolve_root_id（已迁移到 mattermost-enhancer 插件）
#   7.  gateway/platforms/mattermost.py   — ❌ DM 审批基础设施（已迁移到 mattermost-enhancer 插件）
```

---

## 5. 回调性能陷阱（P35）

### 5.1 Inline import 导致按钮响应延迟

**现象：** 用户点击 DM 审批按钮后 1-3 秒无响应，重复点击触发 "无效的操作 id" 错误。

**根因：** `_handle_callback()` 函数体内写了 `from tools.approval import resolve_gateway_approval`。每次按钮点击触发回调时，Python 执行模块加载（首次需加载 `tools/approval.py` ~1392 行 + 全局锁/dict 初始化），耗时 1-3 秒。在此期间 MM 客户端等待超时，用户误以为无响应而重复点击。

**修复：** 将 import 移至文件顶部（模块级别）。

```python
# ❌ 错误 — 每次回调都 import
async def _handle_callback(self, payload):
    ...
    from tools.approval import resolve_gateway_approval  # ← 慢！
    count = resolve_gateway_approval(session_key, choice)

# ✅ 正确 — 插件加载时一次性完成
from tools.approval import resolve_gateway_approval  # 文件顶部

async def _handle_callback(self, payload):
    ...
    count = resolve_gateway_approval(session_key, choice)  # 零开销
```

### 5.2 排查方法

在回调路径方法中搜索 inline import：

```bash
grep -n "        from \|        import " adapter.py
```

**能保留的：** stdlib 模块（`os`, `hmac`, `hashlib`, `urllib.parse`）— 首次加载后即缓存，无感知延迟。  
**必须提升的：** 项目内部模块（`tools.approval`, `hermes_cli.*`）— 可能触发大量初始化。

---

## 6. Provider 格式不一致陷阱（P36）

### 6.1 成因

`resolve_provider_config()` 返回的 `provider` 字段使用 bare name（如 `"zenmux"`），但 Gateway 期望的格式是 `"custom:zenmux"`（带 `custom:` 前缀）。Gateway 查找 provider 时找不到 bare name → 回退到默认 provider → 模型切换不生效。

### 6.2 定位方法

检查 Gateway 日志中切换后的覆盖验证：

```python
# 在 _switch_session_model 的验证日志中
logger.info("Model switched: session=%s → %s provider=%s ...", session_key, model_id, verify.get("provider"))
# 如果看到 provider="zenmux" 而非 "custom:zenmux" → bug
```

### 6.3 修复

```python
# ❌ 错误
"provider": name,               # → "zenmux"

# ✅ 正确
"provider": f"custom:{name}",   # → "custom:zenmux"
```

同时兼容双格式匹配的 fallback：

```python
# ❌ 只匹配 exact
if model_cfg.get("provider") == provider_name:

# ✅ 兼容双格式
if model_cfg.get("provider") == provider_name or \
   model_cfg.get("provider") == f"custom:{provider_name}":
```

**注意：** `session.py` 中已有另一版 `_resolve_provider_for_model()`，它正确使用了 `f"custom:{name}"`。`models.py` 中的 `resolve_provider_config()` 是实际被 adapter 调用的版本，两个文件的实现不一致导致了这个问题。

---

## 7. `_pending_model_notes` 时序陷阱（P37）

### 7.1 成因

`_switch_session_model()` 中，`old_model` 的读取发生在 `_session_model_overrides` 写入**之后**：

```python
# ❌ 错误顺序
runner._session_model_overrides[session_key] = {..., "model": "B", ...}  # 写入新值
old_model = self._get_current_model_from_key(session_key)  # 读到 "B"
# → _pending_model_notes 注入："switched from B to B" — 无意义！
```

### 7.2 症状

LLM 收到 "switched from B to B" 的 note，忽略该提示并继续报告旧模型名。用户看到 `/model` 切换后询问模型，LLM 回答的还是切换前的模型名。多次切换后正常（因为此时 override 持久化，后续切换的新旧模型确实不同）。

### 7.3 修复

将 `old_model` 读取**提前**到 override 写入之前（必须在 if/else 分支外）：

```python
# ✅ 正确顺序
old_model = self._get_current_model_from_key(session_key) or "(default)"  # 先读旧值
if prov_cfg:
    runner._session_model_overrides[session_key] = {...}  # 后写新值
else:
    runner._session_model_overrides[session_key] = {...}
# → _pending_model_notes 注入："switched from A to B" — 正确！
```

**关键约束：** `old_model` 必须在 `if prov_cfg:` / `else:` 两条分支**之前**读取，否则任一条分支写入覆盖后 `old_model` 都会读到新值。

---

## 8. 当前迁移状态

| Patch | 文件 | 功能 | 状态 |
|-------|------|------|:---:|
| 6a-d | `mattermost.py` | `_resolve_root_id` | ✅ 插件 `send/_send_local/_send_url` 覆写 |
| 7a-d | `mattermost.py` | DM 审批基础设施 | ✅ 插件 `send_exec_approval` 等 |
| 10c | `mattermost.py` | MEDIA 静默跳过 | ✅ 插件 `_send_local_file` 覆写 |
| 11 | `mattermost.py` | send_typing Thread 路由 | ✅ 插件 `send_typing` 覆写 |
| 8b | `run.py` | progress reply 进 Thread | ✅ 插件 `send()` metadata.thread_id 降级已覆盖 |
| 8 | `run.py` | send_exec_approval user_id | ⚠️ 无法插件化（调用方在 run.py） |

**`mattermost.py` 源码：零修改** ✅
**`hermes-patches.sh`：12 patches**（原 16，移除 4 个 Mattermost patch）

---

## 9. Patch 标签人性化（新增）

### 9.1 问题

原有 registry 标签是代码级描述（如 `"providers.py (is_aggregator)"`），`check` 输出对非开发者不友好：

```
✓ providers.py (is_aggregator)
✓ run.py (user_id 传入审批)
✗ mattermost.py (send_typing Thread) — 未应用
```

### 9.2 改造

将 registry 和 `_do_patch` 标签改为功能影响描述：

```
✓ 自定义 provider (custom:*) 被误判为非聚合器
✓ Mattermost DM 审批缺少 user_id 参数
```

### 9.3 对应关系

| 代码描述 | → 功能描述 |
|---------|-----------|
| `providers.py (is_aggregator)` | 自定义 provider (custom:*) 被误判为非聚合器 |
| `doctor.py (vendor-prefix)` | 自定义 provider 触发 vendor-prefix 假阳性警告 |
| `model_switch.py (Section 3)` | 模型切换忽略 config.yaml §3 models 白名单 |
| `run.py (user_id 传入审批)` | Mattermost DM 审批缺少 user_id 参数 |
| `run.py (MEDIA 工具结果扫描)` | MEDIA 正则过宽导致误匹配非文件路径 |

### 9.4 清理规则

每次从 `apply_all()` 移除 `_do_patch` 块时：
1. 同步删除 `_patch_registry` 对应条目
2. 更新文件头注释（标记为 `❌ 已迁移至插件`）
3. 运行 `bash -n` + `hermes-patches.sh check` 确认无语法错误和幽灵 patch
