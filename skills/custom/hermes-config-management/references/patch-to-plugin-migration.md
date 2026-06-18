# Shell Patch → Adapter Override 迁移方法论

> 判断哪些 shell patch 可以迁移到 Hermes Platform Plugin 的 adapter override 中。

## 判断框架

逐项分析每个 patch 需要回答两个问题：

| 问题 | 判断依据 |
|------|---------|
| **修改的是哪个文件？** | adapter 方法 → 可迁移；gateway/run.py 内部逻辑 → 需深入分析 |
| **有没有对应的适配器方法可 override？** | 有 → 可迁移；无 → 不可迁移 |

## 三类不可迁移的 Gateway 内部逻辑

以下场景即使修改 `gateway/run.py`，也无法迁移到 adapter override：

| 类别 | 示例 | 原因 |
|------|------|------|
| **变量赋值** | `_progress_reply_to`、`_progress_thread_id` | Gateway 内部变量，适配器无法干预其构造 |
| **消息调度** | clarify 查找、session 创建前拦截 | 发生在任何适配器方法调用之前 |
| **生命周期** | auto-resume 去重 | Gateway 启动阶段执行，适配器尚未初始化 |

## 两类可迁移的适配器方法

| 类别 | 示例 | 迁移方式 |
|------|------|---------|
| **发送方法** | `send_exec_approval()`、`send_multiple_images()` | Override 方法，添加缺失的参数/逻辑 |
| **路由方法** | `send()`、`send_clarify()` | Override 方法，从 metadata/target 中补全路由信息 |

## 实战案例：Mattermost Enhancer

### P1（DM 审批 user_id）→ 可迁移

- **原 patch**：Gateway 调用 `send_exec_approval()` 时注入 `user_id=source.user_id`
- **迁移**：Enhancer 的 `send_exec_approval()` override 已有 `_get_user_id_from_channel()` 降级方案
- **结论**：Gateway patch 是性能优化（省一次 API 调用），功能已由 adapter 完整覆盖

### P6（批量图片 Thread 路由）→ 可迁移

- **原 patch**：修改 bundled adapter 的 `send_multiple_images()`，注入 `root_id`
- **迁移**：Enhancer 完整 override `send_multiple_images()`，含 `_get_thread_root_id()` + `root_id` 注入
- **结论**：Enhancer override 比 shell patch 更完善，shell patch 可移除

### P2-P5、P7 → 不可迁移

全部修改 `_handle_message_with_agent()` 内部逻辑，无对应适配器方法。

## 迁移检查清单

1. [ ] 确认 Enhancer adapter 已完整覆盖该功能
2. [ ] 回退 shell patch 的目标文件
3. [ ] 从 shell 脚本中移除：apply 函数 + check_status + header 注释 + verified list
4. [ ] 更新 README（中英文）：Bug 表实现方式 + FAQ + 安装步骤
5. [ ] 运行 `check` 确认 5/5（无遗漏）
6. [ ] 重启 Gateway
