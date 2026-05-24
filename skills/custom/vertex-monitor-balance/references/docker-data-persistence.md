# Docker 数据持久化 — 路径对齐

## 问题

VertexMonitor 重启/重建 Docker Compose 后，所有计费配置和消费记录丢失。

## 根因

数据写入路径与 volume 挂载路径不一致：

| 组件 | 写入路径 | 挂载路径 | 结果 |
|------|----------|----------|------|
| `store.py` (修复前) | `/app/store.json` | `./data:/app/data` | ❌ 数据写在容器内部，重启即丢 |
| `proxy.py` (修复前) | `/app/store_history.jsonl` | `./data:/app/data` | ❌ 同上 |
| `store.py` (修复后) | `/app/data/store.json` | `./data:/app/data` | ✅ 持久化到宿主机 `./data/` |
| `proxy.py` (修复后) | `/app/data/store_history.jsonl` | `./data:/app/data` | ✅ 同上 |

## 修复

**`store.py`** — 默认存储路径改为 `data/` 子目录：

```python
# 修复前
STORE_PATH = Path(os.environ.get("STORE_PATH", Path(__file__).parent / "store.json"))

# 修复后
_DATA_DIR = Path(__file__).parent / "data"
_DATA_DIR.mkdir(exist_ok=True)
STORE_PATH = Path(os.environ.get("STORE_PATH", _DATA_DIR / "store.json"))
```

**`proxy.py`** — 历史查询路径同步修正：

```python
# 修复前
history_path = Path(__file__).parent / "store_history.jsonl"

# 修复后
history_path = Path(__file__).parent / "data" / "store_history.jsonl"
```

## 验证方法

```bash
# 修改配置
curl -s -X POST http://localhost:8899/api/config \
  -H 'Content-Type: application/json' \
  -d '{"auto_monthly_amount": 12.34}'

# 检查宿主机文件存在
ls -la data/store.json

# 重启
docker compose restart

# 确认配置未丢失
curl -s http://localhost:8899/api/config | grep auto_monthly_amount
```

## 通用原则

Docker volume 挂载的黄金法则：**容器内写入路径必须落在 volume 挂载的目标目录内**。

```yaml
# docker-compose.yml
volumes:
  - ./data:/app/data    # 挂载点

# 代码中写入路径必须匹配
STORE_PATH = Path("/app/data/store.json")   # ✅ 落在 /app/data/ 内
STORE_PATH = Path("/app/store.json")        # ❌ 落在 /app/ 根目录
```
