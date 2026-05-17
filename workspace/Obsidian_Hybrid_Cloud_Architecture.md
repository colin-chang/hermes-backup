# Obsidian 驱动型混合云架构方案 (Obsidian-Driven Hybrid Cloud Architecture)

**版本:** v1.0  
**日期:** 2026-02-12  
**作者:** Jarvis (for Colin Chang)

---

## 1. 项目愿景 (Vision)

构建一个 **“数字化第二大脑”的分发与变现中心**。
不仅仅是一个静态博客，而是一个集成了**知识管理 (KM)**、**内容变现 (SaaS)**、**会员社区**与**实用工具**的混合型 Web 平台。

*   **核心驱动**: Obsidian (本地 Markdown 知识库)
*   **核心体验**: 静态网站的极致速度 + 动态应用的交互能力
*   **部署策略**: 全球边缘分发 (Cloudflare) + 核心计算 (GCP)
*   **主要目标**: 自动化同步、大陆访问优化、会员/支付系统、成本最小化 (薅羊毛)。

---

## 2. 宏观架构设计 (The Grand Strategy)

系统被划分为三个逻辑层级，通过 Git Ops 自动化串联。

### 2.1 内容层 (Content Layer - Local)
*   **CMS**: **Obsidian** (本地)。
*   **数据源**: Markdown 文件。
*   **控制平面**: YAML Frontmatter (元数据)。
    *   控制权限 (`access: public/private/member`)
    *   控制价格 (`price: 100`)
    *   控制标签/分类
*   **版本控制**: GitHub 私有仓库。

### 2.2 边缘分发层 (Edge Layer - Global)
*   **托管**: **Cloudflare Pages**。
*   **功能**:
    *   托管静态资源 (HTML/CSS/JS/Images)。
    *   处理路由转发。
    *   **WAF**: 基础 DDoS 防护与爬虫拦截。
    *   **CDN**: 全球加速。

### 2.3 核心计算层 (Core Layer - Serverless)
*   **后端 API**: **Google Cloud Run** (Containerized Python/FastAPI or Node.js)。
    *   处理复杂业务：支付回调、爬虫任务、拼车逻辑、私信系统。
    *   利用 GCP 抵用券运行高性能实例。
*   **数据库**: **Google Firestore** (NoSQL)。
    *   存储用户数据、订单、积分、私有文章的加密内容/索引。
*   **身份认证**: **Clerk** 或 **NextAuth** (集成 GitHub/Google 登录)。

---

## 3. 技术栈选型 (Tech Stack)

| 模块 | 推荐技术 | 理由 |
| :--- | :--- | :--- |
| **前端框架** | **Next.js (App Router)** | React 生态标准，支持 SSG (静态) + SSR (动态) 混合渲染，完美适配 Cloudflare。 |
| **内容处理** | **Contentlayer** / **Velite** | 构建时将 Markdown 转换为类型安全的 JSON 数据，支持 MDX 组件。 |
| **后端语言** | **Python (FastAPI)** | 适合处理数据密集型任务、爬虫及后端逻辑，方便大哥维护。部署在 Cloud Run。 |
| **数据库** | **Firestore** | Serverless 文档型数据库，扩容无感，与 GCP 生态结合紧密。 |
| **样式库** | **Tailwind CSS** | 现代、原子化 CSS，开发效率高，打包体积小。 |
| **部署/CI** | **Cloudflare Pages** | 自动化构建流水线，免费额度大，国内访问优于 Vercel。 |

---

## 4. 核心工作流 (Core Workflows)

### 4.1 自动化发布流水线 (The Pipeline)
1.  **写作**: 在 Obsidian 中撰写/修改 Markdown。
2.  **提交**: 使用 Obsidian Git 插件 Commit & Push 到 GitHub。
3.  **触发**: GitHub Webhook 通知 Cloudflare Pages。
4.  **构建 (Build)**:
    *   Cloudflare 拉取代码。
    *   运行 `npm run build`。
    *   **分支逻辑**:
        *   若 `access: public` -> 渲染为静态 HTML。
        *   若 `access: private` -> **跳过静态生成**，提取内容并加密/存储至 Firestore (或仅构建骨架屏)。
5.  **发布**: 自动推送到 Cloudflare Edge Network。

### 4.2 访问控制与动态渲染 (Access Control)
1.  用户访问 `/p/private-doc`。
2.  Cloudflare 返回一个轻量级的 Next.js 骨架屏 (Client Component)。
3.  页面加载后，前端 JS 请求后端 API (Cloud Run)。
4.  API 验证用户 Token (Clerk) 及会员等级。
5.  验证通过 -> 从 Firestore/Private Bucket 拉取 Markdown 内容 -> 前端渲染 MDX。
6.  验证失败 -> 显示“请升级会员”或“购买积分”。

---

## 5. 关键痛点解决方案

### 5.1 中国大陆访问优化
*   **域名**: 避免使用 `.xyz`, `.top` 等易被污染后缀。推荐 `.com` / `.io` / `.me`。
*   **DNS**: 托管在 Cloudflare。
*   **优选 IP (可选)**: 若默认 CF 节点慢，可考虑 SaaS 回源策略（CNAME 到优选 IP 供应商），但增加了维护成本。通常标准 CF Pages 配合移动/联通网络尚可。
*   **资源剥离**: 将大图、视频托管在大陆访问友好的对象存储（如阿里云 OSS 或 腾讯云 COS），仅 HTML/JS 走 Cloudflare。

### 5.2 敏感内容隔离 (Grey Area)
*   **物理隔离**: 破解软件、拼车信息不进入主站的 `sitemap.xml`，避免被 Google 索引导致 DMCA。
*   **权限隔离**: 必须登录且积分等级达到 X 级才可见。
*   **独立部署**: 建议将极其敏感的下载站部分部署在抗投诉 VPS 上，主站仅保留入口链接（或通过 API 隐蔽调用）。

### 5.3 支付与积分
*   **海外**: Stripe (最稳)。
*   **国内**: 
    *   **方案 A (个人)**: 易支付/码支付等聚合渠道（有跑路风险，适合小额）。
    *   **方案 B (正规)**: 注册个体户，接入微信/支付宝原生接口。
    *   **方案 C (避险)**: 仅支持 USDT 或 礼品卡充值。
*   **逻辑**: 支付回调 -> Python 后端 -> 更新 Firestore 用户积分 -> 前端解锁内容。

---

## 6. 成本估算 (Cost Analysis)

*   **Hosting**: Cloudflare Pages (Free Tier 足够)。
*   **Compute**: Google Cloud Run (每月前 200万次请求免费 + $300 抵用券 = **$0**)。
*   **Database**: Firestore (每日 5万次读写免费 = **$0**)。
*   **Auth**: Clerk (每月前 10,000 MAU 免费 = **$0**)。
*   **Domain**: 约 $10 - $15 / 年。
*   **Total**: 几乎为零成本，仅需支付域名费。

---

## 7. 下一步行动 (Phase 1)

1.  初始化 Next.js 项目仓库。
2.  配置 Obsidian 与 GitHub 的同步链路。
3.  在 Cloudflare Pages 上跑通“Hello World”部署。
