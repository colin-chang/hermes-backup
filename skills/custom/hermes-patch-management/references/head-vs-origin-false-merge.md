# 假合入案例：HEAD vs origin/main 误判

## 背景

2026-05-28 对 `hermes-patches.sh` 和 `hermes-mattermost-enhancer.sh` 做全面审计：
两个脚本共标记 5+ 个 patch 为 "✅ 上游已合入"，声称无需再打。

## 验证过程

```bash
cd ~/.hermes/hermes-agent

# 本地 HEAD 已 apply 过所有 patch → grep 全部命中 → 误以为上游合入了
git show HEAD:hermes_cli/providers.py | grep -c 'startswith.*"custom:"'
# → 1 (命中！但这是因为本地打过 patch)

# 用 origin/main 重新验证 → 真相大白
git show origin/main:hermes_cli/providers.py | grep -c 'startswith.*"custom:"'
# → 0 (上游根本没这个修复！)
```

## 误标清单

| Patch | 脚本声称 | origin/main 实测 |
|-------|---------|-----------------|
| providers.py custom: aggregator | - | ❌ 0 匹配 |
| doctor.py custom: vendor-prefix | - | ❌ 0 匹配 |
| model_switch.py (3a) | - | ❌ 0 匹配 |
| model_switch.py (3b) | - | ❌ 0 匹配 |
| cron/jobs.py ensure_ascii | - | ❌ 0 匹配 |
| P50 commentary merge | - | ❌ 0 匹配 |
| P53 ghost fence | - | ❌ 0 匹配 |
| P55 fallback reply_to | ✅ 上游已合入 | ❌ 0 匹配 |
| P1 DM user_id | - | ❌ 0 匹配 |
| P2 progress thread | - | ❌ 0 匹配 |
| P3 clarify session | - | ❌ 0 匹配 |
| P4 clarify guard | - | ❌ 0 匹配 |
| P5 session dedup | - | ❌ 0 匹配 |

**全部 13 个 patch，0 个在上游。**

## 根因

脚本 Header 的 "已消除/已合入" 注释是手动维护的，没有自动化验证。
每次 `hermes-patches.sh check` 只检查本地 HEAD，不检查 `origin/main`。
操作者看到 "all applied" → 以为上游修了 → 更新 Header 注释。

## 修复

1. 验证流程中 `git show HEAD:<file>` → `git show origin/main:<file>`
2. Header 标注验证时间和基准 commit
3. 脚本 check 命令增加 `--upstream` 模式自动对比 origin/main
