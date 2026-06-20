# Mattermost Desktop 证书错误诊断

## 典型症状

Mattermost Desktop (macOS) 弹出证书错误：

```
此服务器或消息中嵌入内容的安全证书存在问题。
证书与以前的证书不同。
来源:https://mm.a-nomad.com
出现问题：net::ERR_CERT_COMMON_NAME_INVALID
```

## 诊断清单（按优先级）

### 1. 检查 DNS 解析

```bash
# 系统解析
dig +short mm.a-nomad.com

# 不同 DNS 服务器对比
dig +short mm.a-nomad.com @1.1.1.1    # Cloudflare
dig +short mm.a-nomad.com @8.8.8.8    # Google
```

如果系统解析返回 `198.18.40.137`（Surge 虚拟 IP）但 Cloudflare DNS 返回真实 IP（`104.21.x.x` / `172.67.x.x`），说明流量经过 Surge 虚拟路由。

### 2. 检查 TLS 证书

```bash
echo | openssl s_client -connect mm.a-nomad.com:443 -servername mm.a-nomad.com 2>&1 | openssl x509 -noout -subject -dates -issuer
```

对比真实 Cloudflare IP 的证书：
```bash
echo | openssl s_client -connect 104.21.51.31:443 -servername mm.a-nomad.com 2>&1 | openssl x509 -noout -subject -dates
```

### 3. 检查 Surge 配置

关键差异点：

| 配置项 | 有问题 | 无问题 |
|--------|--------|--------|
| `[MITM] skip-server-cert-verify` | 缺失 | `true` |
| `IP-ASN,13335,DIRECT` 规则 | 存在但被虚拟 IP 绕过 | 配合 DOMAIN 直连规则 |
| `enhanced-mode-by-rule` | `true` + MITM CA 加载 | `false` 或无 MITM 区块 |

### 4. 检查 Mattermost 服务端配置

```bash
cat volumes/app/mattermost/config/config.json | python3 -c "
import sys,json
c=json.load(sys.stdin)
print('SiteURL:', repr(c['ServiceSettings']['SiteURL']))
print('ConnectionSecurity:', repr(c['ServiceSettings']['ConnectionSecurity']))
"
```

`SiteURL` 为空时，Mattermost 依赖 Host 头推断，可能在代理/直连切换时产生不一致。

## 根因

三个因素交叉触发：

1. **Cloudflare SSL 证书轮换**：Universal SSL 证书定期轮换（如 2026-05-08 从旧证书切换到 Google Trust Services WE1 签发的新证书），轮换窗口期部分边缘节点可能短暂提供不完整证书。

2. **Surge DNS 返回虚拟 IP**：`198.18.40.137` 不属于 AS13335，因此 `IP-ASN,13335,DIRECT,no-resolve` 规则无法命中。流量经过 Surge 内部路由 → `[MITM]` CA 证书（即使不解密）改变 TLS 连接处理方式 → `enhanced-mode-by-rule = true` 加剧影响。

3. **Mattermost Desktop (Electron) 证书校验**：客户端检测到证书与缓存不一致，触发 `ERR_CERT_COMMON_NAME_INVALID`。

## 修复方案

### 方案一：Surge `[MITM]` 添加证书跳过

```ini
[MITM]
skip-server-cert-verify = true    # ← 添加此行
ca-passphrase = EC69DB0D
ca-p12 = ...
```

### 方案二：添加显式 DOMAIN 直连规则

在 `[Rule]` 区块顶部（`IP-ASN,13335,DIRECT` 之前）：
```ini
DOMAIN-SUFFIX,a-nomad.com,DIRECT
```

### 方案三：修正 Mattermost `SiteURL`

```json
"ServiceSettings": {
    "SiteURL": "https://mm.a-nomad.com",
    ...
}
```

重启容器：
```bash
docker compose restart mattermost
```
