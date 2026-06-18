---
name: orbstack-setup
description: OrbStack Linux VM 环境配置与排障 — apt 源修复、snapd 替代方案、无头浏览器安装、VS Code Server 扩展配置。当用户在 OrbStack 虚拟机中遇到包管理/浏览器/VS Code 远程开发问题时使用。
tags: [orbstack, apt, browser, vscode-server, headless]
---

# OrbStack Linux VM 环境配置与排障

## 触发条件

用户提到以下任意关键词时加载此 skill：
- OrbStack VM / 虚拟机
- VS Code Server 远程开发
- 在 VM 中安装 Chromium/Chrome/浏览器
- apt update/install 失败（尤其 400 Bad Request）
- snap/snapd 安装失败
- Markdown Preview Enhanced / Puppeteer 需要浏览器
- bashrc 环境变量不生效 / VS Code 插件读不到环境变量 / 交互式守卫

## 核心踩坑点

### 1. apt HTTP 源被 Cloudflare 拦截

**症状**：
```
E: Failed to fetch http://archive.ubuntu.com/ubuntu/dists/noble/InRelease  400 Bad Request
E: The repository '...' is no longer signed.
```

**根因**：部分网络环境下（如中国大陆），Cloudflare 会拦截到 Ubuntu 源的明文 HTTP 请求，返回 400。

**验证**：
```bash
# HTTP 会 400
curl -sI --max-time 5 http://archive.ubuntu.com/ubuntu/dists/noble/InRelease
# HTTPS 正常 200
curl -sI --max-time 5 https://archive.ubuntu.com/ubuntu/dists/noble/InRelease
```

**修复**：将 `/etc/apt/sources.list` 中所有源从 `http://` 改为 `https://`：
```bash
sudo sed -i 's|http://archive.ubuntu.com|https://archive.ubuntu.com|g; s|http://security.ubuntu.com|https://security.ubuntu.com|g' /etc/apt/sources.list
sudo apt update
```

### 2. snapd 在 OrbStack 中不完整

**症状**：
```
error: cannot perform the following tasks:
- Run configure hook of "chromium" snap if present (run hook "configure":
cannot execute snapd tool snap-update-ns: No such file or directory
snap-update-ns failed with code 1
```

**根因**：OrbStack 虚拟机的 Linux 内核缺少 snap 所需的某些功能（如 `snap-update-ns`）。即使 snapd 已安装，snap 包也无法正常工作。Ubuntu 24.04 的 `chromium-browser` 是一个 snap 过渡包，本质是在安装 snap 版 Chromium。

**修复策略**：
- **不要**尝试修复 snapd——这是 OrbStack 内核层面的限制
- **直接卸载** snapd 及相关依赖（节省 ~131MB 磁盘）
- **使用原生 deb 替代方案**

```bash
# 清理失败的 chromium-browser 及 snapd
sudo apt remove --purge -y chromium-browser 2>/dev/null
sudo apt autoremove -y  # 会清理掉 snapd/squashfs-tools/liblzo2-2
```

### 3. 浏览器安装：Google Chrome deb 替代 Chromium snap

在 OrbStack VM 中，推荐用 Google Chrome 官方 deb 源替代 Chromium snap：

```bash
# 添加 Google Chrome 官方源（已修复 apt HTTPS 问题后执行）
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | \
  sudo gpg --dearmor -o /usr/share/keyrings/google-chrome-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] https://dl.google.com/linux/chrome/deb/ stable main" | \
  sudo tee /etc/apt/sources.list.d/google-chrome.list

sudo apt update
sudo apt install -y google-chrome-stable
```

**为什么选 Chrome 而非 Chromium**：
- Chrome 和 Chromium 引擎相同（Blink/V8），对 Puppeteer/VS Code 扩展完全兼容
- Chrome 有原生 deb 包，不依赖 snap
- Chromium 的 PPA 源维护不稳定，版本滞后

### 4. Headless Chrome Wrapper

OrbStack VM 没有桌面环境，需要为 Chrome 添加 headless 参数。创建 wrapper 脚本供 Puppeteer/VS Code 扩展使用：

```bash
# /usr/local/bin/chrome-headless
sudo tee /usr/local/bin/chrome-headless << 'EOF'
#!/bin/bash
# Headless Chrome wrapper for VS Code Server plugins
# Adds --no-sandbox and --disable-gpu flags needed in OrbStack VMs
/usr/bin/google-chrome-stable \
  --no-sandbox \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-dev-shm-usage \
  "$@"
EOF
sudo chmod +x /usr/local/bin/chrome-headless
```

关键参数说明：
- `--no-sandbox`：OrbStack VM 中 sandbox 命名空间受限，必须关闭
- `--disable-gpu`：无 GPU 的 headless 环境
- `--disable-software-rasterizer`：避免软件渲染 crash
- `--disable-dev-shm-usage`：`/dev/shm` 在容器/VM 中可能太小

### 5. VS Code Server 扩展配置

Markdown Preview Enhanced 等依赖 Puppeteer 的扩展需要知道浏览器路径。

**settings.json**（路径：`~/.vscode-server/data/Machine/settings.json`）：
```json
{
    "markdown-preview-enhanced.ChromePath": "/usr/local/bin/chrome-headless",
    "markdown-preview-enhanced.puppeteerExecutablePath": "/usr/local/bin/chrome-headless",
    "markdown-preview-enhanced.usePuppeteerCore": true
}
```

**环境变量**（追加到 `~/.bashrc`）：
```bash
export PUPPETEER_EXECUTABLE_PATH=/usr/local/bin/chrome-headless
```

配置后需**重连 VS Code Server** 或**重启 VS Code 窗口**使设置生效。

### 6. bashrc 交互式守卫陷阱（⚠️ 高频坑）

**症状**：`~/.bashrc` 里 export 了环境变量（如 `ANTHROPIC_DEFAULT_HAIKU_MODEL`），VS Code 终端里 `echo $VAR` 能读到，但 VS Code Server 启动的进程（Claude Code 插件等）读不到。

**根因**：Ubuntu 默认 bashrc 头部有交互式守卫：

```bash
case $- in
    *i*) ;;        # 交互式 shell → 继续
      *) return;;  # 非交互式 shell → 直接返回，跳过后面所有 export
esac
```

VS Code Server 启动扩展进程时走的是**非交互式 shell**，bashrc 在守卫处就 return 了，后面的环境变量全部被跳过。

**诊断**：
```bash
# 模拟非交互式 shell 看能否读到变量
bash -c 'echo $YOUR_VAR'
# 空 → 被守卫拦截；有值 → 没问题
```

**修复**：把需要给非交互式进程用的环境变量 **移到守卫之前**（bashrc 第 6 行之前）：

```bash
# 1. 备份
cp ~/.bashrc ~/.bashrc.bak.$(date +%Y%m%d)

# 2. 提取环境变量块（假设在第 139 行之后）
sed -n '139,$p' ~/.bashrc > /tmp/env_block.txt

# 3. 删除原位置的环境变量块
sed -i '139,$d' ~/.bashrc

# 4. 插入到第 5 行（守卫注释之后、case 语句之前）
sed -i "5r /tmp/env_block.txt" ~/.bashrc
```

**验证修复**：
```bash
bash -c 'echo $YOUR_VAR'   # 应输出预期值
```

## 验证步骤

```bash
# 1. 验证 Chrome 版本
google-chrome-stable --version

# 2. 验证 headless 模式
google-chrome-stable --headless --no-sandbox --disable-gpu --dump-dom https://example.com | head -3

# 3. 验证 wrapper
chrome-headless --version
```

## 排障顺序（TL;DR）

1. `sudo apt update` → 如 400 Bad Request，修 sources.list（HTTP→HTTPS）
2. 安装 `chromium-browser` → 如 snap 失败，改走 Google Chrome deb
3. 清理 snapd → `apt autoremove`
4. 创建 headless wrapper → `/usr/local/bin/chrome-headless`
5. 配置 VS Code settings + 环境变量 → 重连生效
