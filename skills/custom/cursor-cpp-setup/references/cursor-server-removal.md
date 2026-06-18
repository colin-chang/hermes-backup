# Cursor Server 彻底卸载指南

从远程服务器彻底移除 Cursor Server 的步骤。

## 一键卸载

SSH 到远程服务器后执行：

```bash
pkill -f cursor-server 2>/dev/null
rm -rf ~/.cursor-server ~/.local/bin/cursor
ps aux | grep -i cursor | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null
echo "✅ Cursor Server 已卸载"
```

## 关键路径

| 路径 | 内容 | 说明 |
|------|------|------|
| `~/.cursor-server/` | Server 本体 + 扩展 + 数据 | **必删** |
| `~/.cursor-server/data/Machine/settings.json` | 远程 settings | 想迁移配置先备份这个 |
| `~/.local/bin/cursor` | CLI 软链接 | 新版可能有，通常不存在 |

## 验证

```bash
ls ~/.cursor-server        # → No such file or directory
ps aux | grep -i cursor | grep -v grep  # → 空输出
```

## 注意事项

- Cursor Server 按**用户**安装，多用户服务器需逐用户清理
- 进程清理后重启服务器最干净，但 `pkill` 通常足够
- 下次用 Cursor Remote SSH 连接时会自动重装 Server，无需手动恢复
