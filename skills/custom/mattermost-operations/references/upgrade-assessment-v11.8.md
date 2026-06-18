# Mattermost v11.8 升级评估记录

> 评估日期：2026-06-17
> 当前版本：11.7.0 (Team Edition, Docker Compose)
> 目标版本：11.8 (Feature Release)
> 结论：**值得升级，非紧急** — 功能零收益但补上 3 个安全补丁，零风险

## 信息来源

- 发布博文：https://mattermost.com/blog/mattermost-v11-8-is-now-available/
- v11 Changelog：https://docs.mattermost.com/product-overview/mattermost-v11-changelog.html
- Important Upgrade Notes：https://docs.mattermost.com/administration-guide/upgrade/important-upgrade-notes.html
- Docker Hub 镜像：`mattermost/mattermost-team-edition:11.8` 已于 2026-06-15 存在

## 新功能（全部 Enterprise Advanced）

| 功能 | Team Edition? |
|------|:---:|
| Classification Banners（分级标记横幅） | ❌ |
| Data Spillage Reporting（数据泄露报告） | ❌ |
| Mobile Ephemeral Mode（移动端数据生命周期） | ❌ |
| Default Channel Categories（预设频道分组） | ❌ |

**Team Edition 功能层面零感知变化。**

## 破坏性变更

- CPA 属性组重命名：`custom_profile_attributes` → `access_control`
- 仅影响使用 CPA 的插件开发者，当前部署不受影响

## 数据库 Schema 变更

全部零停机（metadata-only 或 CONCURRENTLY 操作）：

- `PropertyGroups` 新增 `Version` 列
- `posts.rootid` / `posts.channelid` 统计采样提升至 5000 + ANALYZE
- `channel_type` 枚举新增 'BO'/'BP'
- `PropertyFields` 新增 `LinkedFieldID` 列
- `Recaps` 新增 `ViewedAt` 列
- `Channels` 新增 `Discoverable` 列
- 新建 `ChannelJoinRequests` 表 + 4 个并发索引
- `permission_level` 枚举新增 'admin'

## config.json 变更

新增配置全部 Enterprise 或 Enterprise Advanced 专属，Team Edition 无需处理。

## 安全补丁赶超

11.7.0 错过 3 个安全补丁（11.7.1 / 11.7.2 / 11.7.3），升级到 11.8 一次性补全。

## Go 版本

Go 1.25.x → Go 1.26.3

## Docker Compose 升级命令

```bash
cd /Users/Colin/Developer/Services/Mattermost
# 改 .env: MATTERMOST_IMAGE_TAG=11.7.0 → MATTERMOST_IMAGE_TAG=11.8
docker compose down && docker compose up -d
```
