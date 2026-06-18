---
name: surge-config-troubleshooting
description: 诊断 Surge 代理配置问题 —— 对比分析两个配置文件找出特定应用无法走代理的根因，覆盖 MITM TLS 干扰、IP-ASN 规则、代理协议差异、UDP/QUIC 处理。
category: custom
---

# Surge 配置排障

当 Surge 某个配置文件下特定应用/域名无法正常工作，但另一个配置文件正常时，使用本技能的方法论进行系统性对比分析。

## 触发条件

- Surge 下某个应用/域名无法正常访问，但换配置文件后正常
- 两个配置都能科*学上网，但特定服务有差异
- 用户要求对比分析 Surge 配置文件

## 排障流程

### 1. 并排对比两个配置文件

重点检查以下差异点（按影响概率排序）：

| 差异项 | 检查位置 | 影响 |
|--------|---------|------|
| `[MITM]` 区块 | 全局 MITM 配置 | **最高优先级** —— 即使无 `hostname` 过滤器，CA 证书存在也会改变 Surge 的 TLS 处理行为 |
| `[Proxy]` 显式声明 vs 订阅节点 | 代理类型 | SOCKS5 本地代理 vs VMess/Trojan 外部节点 —— 协议栈差异影响 WebSocket/TLS |
| `IP-ASN` 规则 | Rule 区块 | `no-resolve` 标记 + DNS 缓存可能导致规则二次匹配，意外 DIRECT |
| `udp-policy-not-supported-behaviour` | General 区块 | 强制 UDP 走代理时 QUIC/HTTP3 可能被破坏 |
| `enhanced-mode-by-rule` | General 区块 | 与 MITM 组合时影响 TLS 连接处理 |

### 2. 逐假说验证

按以下优先级验证：

**假说 A: MITM CA 证书 TLS 干扰**
- 表现：应用连接失败或静默超时，但浏览器访问正常
- 验证：注释掉整个 `[MITM]` 区块 → 重载配置 → 测试
- 根因：CA 证书即使不激活解密，也会改变 Surge 对 HTTPS CONNECT 的 TLS 中间层处理，导致 TLS 指纹变化。Cloudflare Workers 前端对 TLS 指纹更敏感。

**假说 B: 代理协议与目标协议不兼容**
- 表现：WebSocket 服务或 gRPC 服务走 VMess/Trojan 失败，走 SOCKS5 正常
- 验证：对比 `[Proxy]` 区块 —— 直接声明 vs 订阅下载
- 根因：VMess/Trojan 对 WebSocket 帧的封装/解封可能破坏帧边界；SOCKS5 纯 TCP 转发无此问题

**假说 C: IP-ASN 规则 DNS 缓存污染**
- 表现：Surge 请求查看器显示走代理，但实际连接走 DIRECT
- 验证：注释掉 `IP-ASN,13335,DIRECT,no-resolve` → 重载 → 测试
- 根因：`no-resolve` 虽跳过首次域名请求，但 DNS 缓存后的 IP 可能触发规则二次匹配

**假说 D: UDP/QUIC 处理差异**
- 表现：支持 HTTP/3 的服务连接失败
- 验证：移除 `udp-policy-not-supported-behaviour = proxy` → 重载 → 测试
- 根因：UDP 走 VMess/Trojan 代理节点时可能丢包，QUIC fallback 到 TCP 可恢复

### 3. 终极测试

为目标域名添加显式规则，绕过所有 RULE-SET 和 FINAL：

```ini
# 添加到 Rule 区块最顶部
DOMAIN-SUFFIX,workers.dev,🚀 节点选择
```

## 关键参考

- Surge MITM 文档：无 `hostname` 过滤器时 HTTPS 连接仅转发 TCP 流，不做解密
- `enhanced-mode-by-rule = true`：启用后 MITM 相关行为更激进
- `IP-ASN + no-resolve`：域名请求首次跳过，但 DNS 缓存可能触发后续匹配
- Cloudflare Workers (`*.workers.dev`)：使用 Cloudflare TLS 栈，对 TLS 指纹和 WebSocket 帧时序敏感

## 输出格式

分析结果分层输出：
1. 核心差异表（5 列：差异项 / 配置A / 配置B / 影响 / 优先级）
2. 根因分析（按概率排序，每个假说包含：推测 / 机理 / 验证方法）
3. 可执行的排查步骤（可直接复制粘贴的命令或配置修改）
