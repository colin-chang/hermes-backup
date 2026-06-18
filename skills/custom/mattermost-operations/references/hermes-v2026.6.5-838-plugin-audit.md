# Hermes v2026.6.5-838 — mattermost-enhancer 兼容性审计

审计日期：2026-06-13
Hermes 版本：v2026.6.5-838-g202e318cb (origin/main=202e318cb)
上次审计：v2026.6.5-617-g955fa4006 (origin/main=85503dce)
插件版本：mattermost-enhancer（未变更）

---

## 架构变更概览

相对上次审计（v2026.6.5-617），gateway/run.py 有 14 个 commit：

```
202e318cb fix(gateway): sync compression session splits before failures
2a5dc0ef3 fix(slack): make video attachments available to agents (#45512)
7ba5df0d5 feat(billing): /credits command — balance + portal top-up handoff (#44776)
db7714d5f fix(gateway): reset _last_flushed_db_idx when reusing cached agent (#44327)
13650ab7f fix(gateway): audio attachment note no longer steers the agent into punting
e7ae145ac fix(gateway): guide the agent to read attached PDF/DOCX instead of punting
cb29e8a82 refactor(cron): rebrand Cron Recipes → Automation Blueprints
e8b757845 fix(cron-recipes): pre-release hardening
e976faac7 feat(cron-recipes): /cron-recipe <name> seeds a conversational fill
1593ca540 feat(cron): Cron Recipes — parameterized automation templates
9a09ea69f feat(cron): Suggested Cron Jobs
2ecb4e62b Merge remote-tracking branch 'origin/main' into hermes/hermes-6b48295e
bfcc9f92b Merge commit '6110aed9b' into feat/whatsapp-cloud-api
984e6cb5b feat(whatsapp): add WhatsApp Business Cloud API adapter
```

**Bundled Mattermost 插件（`plugins/platforms/mattermost/`）：零变更。**

---

## 一、Shell Patch 双重验证（5 个补丁）

### 维度 A：Check Pattern（修复是否已入上游）

| Patch | 文件 | Check Pattern | grep 匹配数 | 结论 |
|-------|------|--------------|:---:|------|
| P1 | gateway/run.py | `or source.platform == Platform.MATTERMOST` | 0 | ❌ 未合入 |
| P2 | gateway/run.py | `_canonical_entry = self.session_store.get_or_create_session` | 0 | ❌ 未合入 |
| P3 | gateway/run.py | `Gateway intercepted clarify at session guard` | 0 | ❌ 未合入 |
| P4 | gateway/run.py | `Deduplicate.*keep only the most recent` | 0 | ❌ 未合入 |
| P5 | gateway/run.py | `source.platform == Platform.MATTERMOST and not source.thread_id` | 0 | ❌ 未合入 |

### 维度 B：old_string（Patch 是否可命中）

| Patch | old_string 在 origin/main 中存在？ |
|-------|:---:|
| P1 | ✅ YES |
| P2 | ✅ YES |
| P3 | ✅ YES（1 次） |
| P4 | ✅ YES |
| P5 Part A | ✅ YES |
| P5 Part B | ✅ YES |

### 结论

全部 5 个 patch 均未合入上游，old_string 全部可命中。所有 gateway/run.py 的 commit 均未触及 patch 目标区域。

**仅需更新脚本 Header 版本标注**（v2026.6.5-617 → v2026.6.5-838）。

---

## 二、Bundled Adapter 变更对照

### 2.1 `register()` 参数

零变更。与上次审计完全一致。

### 2.2 Enhancer `register_platform` 参数

Bundled 13 参数 vs Enhancer 13 参数 — 全部匹配：

| 参数 | Bundled | Enhancer | 状态 |
|------|---------|----------|:---:|
| name | `"mattermost"` | `"mattermost"` | ✅ |
| label | `"Mattermost"` | `"Mattermost (Approval)"` | ✅ |
| adapter_factory | `_build_adapter` | `lambda: MattermostApprovalAdapter` | ✅ |
| check_fn | ✅ | ✅ (自有) | ✅ |
| is_connected | ✅ | ✅ (复用 bundled) | ✅ |
| required_env | ✅ | ✅ | ✅ |
| install_hint | ✅ | ✅ (增强版) | ✅ |
| setup_fn | ✅ | ✅ (复用) | ✅ |
| apply_yaml_config_fn | ✅ | ✅ (复用) | ✅ |
| allowed_users_env | ✅ | ✅ | ✅ |
| allow_all_env | ✅ | ✅ | ✅ |
| cron_deliver_env_var | ✅ | ✅ | ✅ |
| standalone_sender_fn | ✅ | ✅ (复用) | ✅ |
| max_message_length | ✅ | ✅ | ✅ |
| emoji / allow_update_command | ✅ | ✅ | ✅ |

无 `apply_yaml_config_fn` / `standalone_sender_fn` 缺失陷阱。

---

## 三、Adapter 覆写方法签名兼容性

所有 17 个覆写方法与 bundled adapter 签名兼容：

| 方法 | 状态 | 备注 |
|------|:--:|------|
| `connect()` | ✅ | `await super().connect()` |
| `disconnect()` | ✅ | `await super().disconnect()` |
| `_ws_connect_and_listen()` | ✅ | heartbeat 30→15s |
| `send()` | ✅ | footer+root_id+cache+metadata降级 |
| `send_typing()` | ✅ | Thread parent_id |
| `edit_message()` | ✅ | +timeout+空内容防护 |
| `send_image()` | ✅ | +_derive_reply_to |
| `send_image_file()` | ✅ | +metadata 可选参数（后向兼容） |
| `send_document()` | ✅ | +_derive_reply_to |
| `send_video()` | ✅ | +_derive_reply_to |
| `send_voice()` | ✅ | +_derive_reply_to |
| `send_multiple_images()` | ✅ | +Thread root_id |
| `_send_local_file()` | ✅ | +MEDIA静默跳过+root_id |
| `_send_url_as_file()` | ✅ | +root_id |
| `_resolve_root_id()` | ✅ | str→Optional[str]（Liskov放宽） |
| `send_clarify()` | ✅ | MM交互卡片 |
| `send_exec_approval()` | ✅ | enhancer独有 |

### WebSocket MRO 链验证

```
enhancer.connect() → super().connect() [bundled]
  → bundled._ws_loop()
    → self._ws_connect_and_listen() [enhancer, 15s heartbeat]
      → self._handle_ws_event() [bundled]
```

MRO 链完整。Bundled 使用 `self._ws_connect_and_listen()`（非硬编码），enhancer 覆写正常生效。

---

## 四、导入路径

```python
from hermes_plugins.platforms_mattermost.adapter import MattermostAdapter, MAX_POST_LENGTH
from hermes_plugins.platforms_mattermost.adapter import (
    _apply_yaml_config, _is_connected, _standalone_send,
    interactive_setup, MAX_POST_LENGTH,
)
```

路径未变化，fallback 机制仍然有效。

---

## 五、次要发现（非阻塞）

| 发现 | 说明 |
|------|------|
| `_resolve_root_id` 返回类型不一致 | Bundled → `str`，Enhancer → `Optional[str]`。Liskov 兼容（放宽返回值），目前无问题。 |
| `send_image_file` 签名差异 | Enhancer 多一个可选 `metadata` 参数，后向兼容。 |

---

## 六、审计结论

- **Shell Patch**：5/5 仍需要 + 可正常 apply ✅
- **Adapter 覆写**：全部 17 个方法签名兼容 ✅
- **`register_platform` 参数**：13/13 完整 ✅
- **Bundled adapter**：零变更，无需适配 ✅
- **脚本 Header**：已更新版本标注（v2026.6.5-838） ✅

**综合结论：无需任何代码修改。** 所有 patch 可直接 apply，插件完全兼容。
