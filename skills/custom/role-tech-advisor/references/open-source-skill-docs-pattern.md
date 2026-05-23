# 开源项目文档模板

> 本文件记录技术顾问角色下开源发布的标准文档组合。
> 适用于 Skill、插件、CLI 工具等任何对外发布的项目。

## 必含文件清单

| 文件 | 语言 | 说明 |
|------|------|------|
| `README.md` | 英文（主） | 架构图、快速开始、FAQ |
| `README.zh-CN.md` | 中文 | 与 README.md 对等，非机翻 |
| `LICENSE` | 英文 | MIT，版权行写 `<year> <project> contributors` |
| `SECURITY.md` | 英文 | 攻击面分析、端口安全、依赖审计 |
| `PRIVACY.md` | 英文 | 数据流向、权限说明、删除指南 |
| `.gitignore` | — | macOS 缓存、日志、IDE 文件 |

## 编辑流程

1. **先编辑中文版**（`README.zh-CN.md` 等），与用户确认内容
2. **中文定稿后再同步英文**（`README.md`），不提前写英文
3. 英文版不是中文版的逐字翻译——结构对齐，措辞地道

## README 结构约定

```
# 项目名

> 一句话描述（含 emoji 标签 + 适用平台）

badge 行（License / Platform / Type）

---

[语言切换链接]

## 这是什么？
## 架构（ASCII 图）
## 快速开始
### 前置条件
### 安装/启动
### 使用示例
## 核心能力/方法
## 为什么不用 X？（对比弃用方案）
## 文档索引（表格）
## 安全性（要点列表）
## 平台支持
## 许可证
## 常见问题（Q&A）
```

## Skill 特有约定

- 主标题下添加 `🧩 **macOS AI Agent Skill**` 等标签
- 明确列出兼容的 Agent 平台（Hermes/Claude Code/OpenCode/Codex）
- "Agent 兼容性" 表格说明各平台集成方式
- 平台特化内容归档到 `references/<platform>/`
