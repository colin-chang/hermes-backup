# Cloudflare Workers 代理排障案例

## 案例：HeyClicky (workers.dev) 在 cloudflare.conf 失败、forward-proxy.conf 正常

### 目标请求
```
HTTPS → clicker-proxy-v2.farza-0cb.workers.dev
```

### 两个配置的关键差异

#### cloudflare.conf (失败)
- `[MITM]` 区块：已配置 CA 证书，无 `hostname` 过滤器
- 代理：外部订阅节点（VMess/Trojan/SS），来自 `sub.store/download/Cloudflare`
- `IP-ASN,13335,DIRECT,no-resolve`：Cloudflare ASN 直连规则
- `udp-policy-not-supported-behaviour = proxy`：UDP 强制走代理
- `enhanced-mode-by-rule = true`

#### forward-proxy.conf (成功)
- 无 `[MITM]` 区块
- 代理：显式 `LocalUpstream = socks5, 127.0.0.1, 7892`
- 无 Cloudflare IP-ASN 规则
- 无 UDP 策略配置
- `enhanced-mode-by-rule = true`（相同）

### 根因假说排序

1. **MITM CA 证书链 TLS 指纹污染**（最可能）
   - CA 证书存在 → Surge 内部 TLS 中间层行为变化
   - `enhanced-mode-by-rule` 放大效应
   - Cloudflare Workers 边缘对 TLS 指纹敏感

2. **VMess/Trojan WebSocket 帧拆装破坏**（次可能）
   - Workers 域名暗示 WebSocket 代理
   - SOCKS5 纯 TCP 转发不受影响
   - 代理协议封装/解封可能丢失帧边界

3. **IP-ASN,13335 DNS 缓存二次匹配**（可能）
   - `no-resolve` 首次跳过，但 DNS 缓存后的 IP 可触发匹配
   - 请求查看器显示代理，实际 TCP 走 DIRECT

4. **QUIC/HTTP3 UDP 丢包**（较低可能）
   - `udp-policy-not-supported-behaviour = proxy` 强制 UDP 走代理
   - VMess/Trojan 节点可能不处理 UDP 或丢包

### 验证步骤

1. 关 MITM：注释 `[MITM]` 整段 → 重载
2. 关 IP-ASN：注释 `IP-ASN,13335,DIRECT,no-resolve` → 重载
3. 终极测试：`DOMAIN-SUFFIX,workers.dev,🚀 节点选择` 置顶
4. 开 verbose 日志：`loglevel = verbose` 查看 TLS 握手错误
