# custom_providers 向后兼容性

## 结论

**旧 `custom_providers` 数组格式仍然被 Hermes 完整支持**，Desktop 写入的 `providers` 字典格式与旧格式**并存读取**。

## 代码证据

`hermes_cli/config.py` 第 3925 行 `get_compatible_custom_providers()`：

```python
def get_compatible_custom_providers(
    config: Optional[Dict[str, Any]] = None,
) -> List[Dict[str, Any]]:
    """Return a deduplicated custom-provider view across legacy and v12+ config.

    ``custom_providers`` remains the on-disk legacy format, while ``providers``
    is the newer keyed schema.  Runtime and picker flows still need a single
    list-shaped view, but we should not materialise that compatibility layer
    back into config.yaml because it duplicates entries in UIs.
    """
```

关键逻辑（第 3962–3970 行）：

```python
# 1. 先读 legacy custom_providers
custom_providers = config.get("custom_providers")
if custom_providers is not None:
    if not isinstance(custom_providers, list):
        return []
    for entry in custom_providers:
        _append_if_new(_normalize_custom_provider_entry(entry))

# 2. 再读新的 providers（转换为兼容格式）
for entry in providers_dict_to_custom_providers(config.get("providers")):
    _append_if_new(entry)

# 3. 合并去重返回
return compatible
```

## 决策指导

- **保留 `custom_providers` 格式**是安全的，不会被废弃
- Desktop 写入 `providers` 格式时，请勿「迁移」——保持旧格式，Hermes 会自动合并读取
- 新旧格式同时存在也不会冲突（函数内部按 `provider_key` + `(name, base_url, model)` 去重）

## 两种格式字段映射

| 旧 (`custom_providers` 数组) | 新 (`providers` 字典) | 说明 |
|------------------------------|----------------------|------|
| `name: zenmux` | 字典 key `zenmux:` | 从数组成员名变为字典键 |
| `base_url: https://...` | `api: https://...` | 键名变化 |
| `model: <name>` | `default_model: <name>` | 默认模型键名变化 |
| `request_timeout_seconds: N` | 无对应 | 旧格式独有字段，Desktop 不写 |
| `models:` | `models:` | 结构相同 |
