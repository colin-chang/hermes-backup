# Cron 脚本 curl 可靠性模式

## 适用场景

`no_agent` 模式的 cron 定时脚本，需要从 GitHub/外部源下载文件时使用。
cron 环境无 GUI、无 TTY，网络波动比交互式 shell 更常见——裸 `curl` 极易因瞬断导致整体失败。

## 标准 curl 重试配置

```bash
# 定义在脚本顶部，所有 curl 调用统一引用
CURL_RETRY="--retry 3 --retry-delay 10 --connect-timeout 15 --max-time 120"
```

参数语义：
- `--retry 3`：失败后自动重试 3 次（覆盖瞬断）
- `--retry-delay 10`：重试间隔 10 秒（避免 GitHub rate-limit 叠加）
- `--connect-timeout 15`：连接阶段超时 15 秒（防范 DNS/TCP 卡死）
- `--max-time 120`：单次调用总超时 120 秒（`--retry` 不计入，每次重试独立计时）

## 应用示例

```bash
# HEAD 探测（--max-time 被 CURL_RETRY 覆盖，所以保留 --max-redirs）
curl -fsIL $CURL_RETRY --max-redirs 5 "$url" >/dev/null 2>&1

# GitHub 页面抓取
curl -fsSL $CURL_RETRY "$TAGS_URL" | sed -n '...' | head -1

# 文件下载
curl -fL -s $CURL_RETRY "$DOWNLOAD_URL" -o "$TMP_FILE"
```

## 搭配 set -euo pipefail

cron 脚本应启用严格模式：

```bash
set -euo pipefail
# -e: 任何命令非零退出立即终止
# -u: 引用未定义变量立即报错
# -o pipefail: 管道中任一命令失败则整体失败
```

**注意事项：**
- 清理步骤（`rm -rf`/`find ... -delete`）应加 `|| true` 容错，避免权限问题导致脚本提前退出
- `trap 'rm -f "$TMP_FILE"' EXIT` 确保临时文件清理

## ⚠️ 陷阱：curl 重试时间 vs cron 超时的隐形冲突

**这是 cron `no_agent` 脚本最常见的隐蔽故障模式。** 表面看脚本逻辑正确、本地测试通过，但 cron 环境中反复超时。

### 问题

`--max-time 120` + `--retry 3` + `--retry-delay 10` 的**单次 curl 调用**累计可耗时：

```
3 × 120s (max-time，每次重试独立计时) + 2 × 10s (retry-delay) = 380s
```

而 cron 调度器对 `no_agent` 脚本的默认超时只有 **120s**。脚本中如果有多处 curl 调用（tags 抓取 → HEAD 探测 → 文件下载），总耗时更容易超出。

### 检测方法

```bash
# 查看 cron output 存档，确认是否超时
cat ~/.hermes/cron/output/<job_id>/<latest>.md
# → "Script timed out after 120s" ← 这就是超时信号

# 手动跑脚本各步骤，测每步耗时
time curl -fsSL --max-time 120 "https://github.com/..." >/dev/null
```

### 修复

**方案 A：缩小 curl 参数，确保最坏情况在 120s 内（推荐）**

```bash
# 以 120s cron timeout 为上限，反推参数：
# 3 次重试 × Ns max-time + 2 × 10s delay < 120s
# → max-time ≤ 33s，取 30s
CURL_RETRY="--retry 3 --retry-delay 10 --connect-timeout 15 --max-time 30"
```

**方案 B：减少重试次数**

```bash
# 2 次重试 + 45s max-time: 2 × 45 + 1 × 10 = 100s < 120s
CURL_RETRY="--retry 2 --retry-delay 10 --connect-timeout 15 --max-time 45"
```

**方案 C：拆分慢操作，大文件下载走独立短超时路径**

下载大文件时用 `--max-time 60`（只给 1 次重试足够），tags 抓取用 `--max-time 15`（小页面秒回）。

### 真实案例

`update-gitlens.sh` 使用 `--max-time 120 --retry 3`，在 GitHub CDN 不稳定时，单次 curl 累计超 120s 被 cron kill：
```
Status: script failed
Script timed out after 120s: /Users/Colin/.hermes/scripts/update-gitlens.sh
```
三次 cron 触发了两次失败（一次 curl(18) partial file，一次超时），改为 `--max-time 30` 后修复。

## 超时故障自愈

cron 任务超过调度器的 `timeout`（常见 120s）会被 kill，
但这通常是下载慢 + 重试叠加导致，而非代码 BUG：
- 单次下载成功 → 脚本干净退出 → 下次 cron 自动跳过（版本已最新）
- 单次下载超时 → 被 kill → 下次 cron 重新尝试下载 + 安装

关键是**不产生残留状态**（半截文件、未清理的临时目录），确保下次运行能正常检测并恢复。

## 完整脚本示例

参见 `~/.hermes/scripts/update-gitlens.sh`（V15-fixed）——
一个典型的 `no_agent` cron 脚本，包含：
1. 统一 `CURL_RETRY` 配置
2. `set -euo pipefail` + `trap` 清理
3. 版本检测 → 条件下载 → 条件同步 → 清理 + 格式化报告
4. 所有 curl 调用均引用 `$CURL_RETRY`
