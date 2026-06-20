# Mattermost Desktop 证书轮换案例

## 问题描述

Mattermost Desktop (Electron) 连接自托管 Mattermost（Cloudflare 代理 + Surge 本地代理）时，间歇性弹出：

```
ERR_CERT_COMMON_NAME_INVALID
证书与以前的证书不同
来源: https://mm.a-nomad.com
```

## Surge 配置特征

触发此问题的 Surge 配置组合：

| 项 | 值 | 为何有关 |
|----|-----|---------|
| `dns-server` | 国内 DNS（223.5.5.5） | 目标域名可能解析到虚拟 IP 而非真实 Cloudflare IP |
| `[MITM] ca-p12` | 有 CA 证书 | 即使无 `hostname` 过滤，CA 加载影响 TLS 转发行为 |
| `enhanced-mode-by-rule` | `true` | 激进模式增加 TLS 层处理 |
| `IP-ASN,13335,DIRECT,no-resolve` | 存在 | 仅匹配真实 Cloudflare IP，**不匹配 Surge 返回的虚拟 IP**（如 `198.18.40.137`） |
| `skip-server-cert-verify` | 缺失 | 上游证书不一致时放大问题 |

## 诊断链

```
用户报告 ERR_CERT_COMMON_NAME_INVALID
  → DNS 诊断：对比系统解析 vs @1.1.1.1 解析
    → 发现系统返回虚拟 IP (198.18.40.137)，CF DNS 返回真实 IP (104.21.x.x)
      → 检查 Surge MITM 配置
        → 发现 CA 存在但 skip-server-cert-verify 缺失
          → 检查 Cloudflare cert 轮换时间线
            → 确认：证书于 May 8 更换，与用户报告时间吻合
```

## 修复组合

```ini
# 1. Surge [MITM] 区块
[MITM]
skip-server-cert-verify = true    # ← 关键修复

# 2. Surge [Rule] 顶部
DOMAIN-SUFFIX,a-nomad.com,DIRECT    # ← 显式直连，优先于 IP-ASN 规则
```

```json
// 3. Mattermost config.json
"ServiceSettings": {
    "SiteURL": "https://mm.a-nomad.com"
}
```

## 与 cloudflare-workers-proxy-case.md 的区别

| 维度 | Workers 代理案例 | 此案例 |
|------|-----------------|--------|
| 根因 | MITM CA 改变 TLS 指纹 → Cloudflare Workers 拒绝 | DNS 虚拟 IP 绕过 IP-ASN → MITM 转发放大证书轮换 |
| 关键差异 | Workers TLS 栈对指纹敏感 | Mattermost Desktop Electron 证书缓存 + 校验 |
| 共同点 | `enhanced-mode-by-rule = true` + `[MITM]` CA 存在 | 同左 |
