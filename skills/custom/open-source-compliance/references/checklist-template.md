# 开源合规检查清单模板

复制此清单到项目 issue 或文档，逐项检查。

## 🔐 凭证脱敏

- [ ] 扫描硬编码凭证（`api_key`, `secret`, `password`, `token`, `private_key`）
- [ ] 云项目 ID 替换为占位符（`your-project-id`）
- [ ] 真实配置文件 → `.gitignore` + 提供 `*.example.json`
- [ ] 密钥文件排除（文件 + 同名目录）
- [ ] 测试脚本脱敏
- [ ] Git 历史无残留凭证（`git log --all --full-history -- '*key*' '*secret*' '*config.json'`）

## 📋 .gitignore

- [ ] 密钥文件（文件 + 目录）
- [ ] 真实配置文件
- [ ] 运行时数据（保留 `.gitkeep`）
- [ ] `.env`
- [ ] 缓存/编译产物
- [ ] IDE/OS 文件

## 📄 合规文档

- [ ] `LICENSE`（MIT / Apache 2.0）
- [ ] `SECURITY.md`（处理凭证的项目必须）
- [ ] `PRIVACY.md`（有 Web UI 或收集数据的项目必须）
- [ ] `CODE_OF_CONDUCT.md`（有社区贡献期望时）

## 📖 README

- [ ] 英文版 `README.md`
- [ ] 中文版 `README.zh-CN.md`
- [ ] 顶部互链切换
- [ ] Quick Start 可直接复制执行
- [ ] 无硬编码凭证或项目 ID

## ✅ 最终验证

- [ ] `git diff --cached | grep '^+' | grep -i <项目ID模式>` 无匹配
- [ ] `git ls-files | grep -E '<敏感文件模式>'` 无匹配
- [ ] `gh repo create` 或 `git push` 成功
- [ ] GitHub 仓库页面无凭证内容
