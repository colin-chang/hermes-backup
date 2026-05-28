# 加拿大事务顾问角色专属记忆

> 本文件存储加拿大事务角色的领域知识，由 Agent 在对话中自动更新。
> 与全局 MEMORY.md 互补：共性事实 → 全局；移民/税务/本地生活 → 本文件。

## 移民政策更新

### OINP 硕士通道 2026 年抽签记录与关闭确认（2026.05.22 调研）

**抽签时间线：**
| 日期 | 类别 | ITA 数量 | 备注 |
|------|------|---------|------|
| 2026.03.18 | Masters + PhD Graduate | 900+ | 首次；此前停摆近1.5年（上次 2024.09.17） |
| 2026.04.22 | Masters + PhD Graduate | 918 | Profile 截止 2026.04.20；多家媒体称可能为最后一轮 |
| 截至 05.22 | — | 无公告 | 理论窗口 05.27-28，概率 30-40% |

**通道关闭确认：**
- 2026年5月30日起，全部 9 个现行 OINP 类别永久关闭，替换为 4 个新整合通道（安省监管变更已通过）
- 来源：immigration.ca、CIC News (2026.03)、Liberty Immigration、Ontario .ca Program Updates
- **对本案影响：家庭 2026 年 9 月登陆，晚于关闭日期，OINP 硕士通道不适用**

**合规障碍发现（已官方验证，2026.05 法条编号更正）：**
- OINP 硕士通道居住要求（来源：[O.Reg 422/17 s.8(3)](https://www.ontario.ca/laws/regulation/170422)，2026年5月 e-Laws 现行合并文本。⚠️ 旧版编号 8.4+8.7 已被合并为单一 Section 8(3)）：
  - **Section 8(3) 原文（由 `and` 连接为整体）**：*"must have lawfully resided in Ontario for at least one of the last two years before the date of making the application **and**, at the time of making the application, must be lawfully residing in Ontario or residing outside of Canada"*
  - 前半段（历史居住）：过去2年内在安省累计住满12个月 → ✅ 滑铁卢13个月满足
  - 后半段（申请时居住地）：提交申请时必须住在安省或加拿大境外，**不得住其他省** → ❌ 蒙特利尔（魁省）不满足
- 法律效果不变：虽是单一法条，但 `and` 连接的两部分均须满足

## 税务案例与经验

### CRA Direct Deposit 政策（2026.05 确认）
- **2026年1月5日起 CRA 推行强制 Direct Deposit**（来源：Westhill CI 税务公告），不再优先邮寄纸质支票
- **首次报税者例外**：即使设置了 Direct Deposit，CRA 可能因身份验证（Identity Verification）而邮寄纸质支票作为首笔退款
- 政府支票（Receiver General Cheques）**永不过期**（never stale-dated），与普通商业支票不同
- 若收到身份验证信（Review Letter），需提交护照/签证/SIN 确认信，验证通过后所有后续退款自动 Direct Deposit

### Direct Deposit 设置三条路径（2026.05 实测确认）

| 方式 | 速度 | 门槛 |
|------|------|------|
| 🥇 银行App/网银 | 下一个工作日 | 需有加拿大银行账户（开户当天即可） |
| 🥈 邮寄纸质表单 | 长达3个月+ | 需 void cheque |
| 🥉 CRA My Account | 下一个工作日 | ❌ 首次报税者不可用（需已有报税记录） |

> ⚠️ **2026年关键变更**：CRA 已废除电话设置 DD 功能。官方页面明确： "You can **no longer** sign up for or update your direct deposit information by telephone."
>
> ⚠️ **首次报税者关键限制**：注册 CRA My Account 需提供「最近一次报税的核定金额（过去两年内）」。从未在加拿大报过税的人无法在线注册。ScotiaBank 确认："To get a CRA My Account, you need to file your taxes and receive a notice of assessment from the CRA."

**路径一：通过银行（首次报税者唯一快速方案）**
- 不是登录 CRA，是登录**银行自己的 App/网银**，在银行系统里绑定 CRA
- CRA 官网： "The fastest way to sign up... is online with your bank or in your CRA account"
- 操作：银行App内搜 "CRA" 或 "Direct Deposit" → 按提示填 SIN + 选接收账户
- 各银行路径缩写见 `references/cra-direct-deposit-banks.md`

**路径二：邮寄表单（兜底）**
- 表单：Canada Direct Deposit Enrolment Form
- 下载：https://www.canada.ca/en/public-services-procurement/services/payments-to-from-government/direct-deposit/individuals-canada/enrolment-form.html
- 必附 void cheque，处理最长3个月

**路径三：CRA My Account（需先报税）**
- 网址：canada.ca/my-cra-account
- 注册需：SIN + 出生日期 + 邮编 + 最近一次报税金额（验证身份）
- 首次报税后收到 Notice of Assessment 才可注册
- 登录后：Profile → Direct Deposit → Edit → 填入银行信息 → 下一个工作日生效

### 加拿大银行账户关键信息
- Transit Number：5位（分行代码）
- Institution Number：3位（银行代码）
- Account Number：7-12位（个人账号）
- 三者在支票底部的格式：`[支票号] ⑆ [Transit] ⑉ [Institution] ⑆ [Account]`

## 本地生活经验

### 支持手机拍照存支票（Mobile Cheque Deposit）的加拿大银行
| 类型 | 银行 |
|------|------|
| 五大行 | TD、RBC、BMO、Scotiabank、CIBC |
| 国家银行 | National Bank |
| 线上银行 | Tangerine、Simplii Financial、EQ Bank |
| 数字银行 | Wealthsimple、Neo Financial、KOHO、PC Financial |
| 信用合作社 | Coast Capital Savings |

- 操作流程：银行App → Deposit/存入支票 → 拍正反面 → 输入金额 → 提交
- 到账时间：通常1-5工作日，RBC/BMO/TD 部分支持即时到账

## 跨国家移民对比研究

### 西班牙数字游民签证 vs 加拿大路径 对比结论（2026.05.28）

**触发：** 用户询问西班牙 DNV 政策细节，并深入对比巴塞罗那 vs 多伦多四维（气候/成本/教育/移民）。

**核心数据（2026）：**
- 收入门槛：主申 €2,849/月 + 配偶 €1,068/月 + 子女 €356/月 = 三人家庭需 €4,273/月
- 永居：5年（加拿大1-2年）；入籍：10年+放弃原国籍
- Beckham Law：24%统一税率6年，境外收入免税（YouTube 收入全免 🔥）
- Barcelona vs Toronto 生活成本：整体便宜 ~8%，公交月票便宜 77%
- 气候：BCN 2,500h日照 vs YYZ 2,070h，1月温差 16-18°C

**Hawkins 家庭适配结论：**
- 加权评分：加拿大 7.9 vs 西班牙 5.7（权重：移民确定性40%+职业发展25%+气候15%+育儿10%+成本10%）
- 妻子方向：加拿大完胜（CFA+Montreal期货工作已就绪，西班牙金融业小）
- 你的方向：西班牙略优（YouTube=数字游民完美匹配），但移民确定性太差
- **推荐策略：加拿大为主线 → PR后（2028-2029）西班牙DNV为第二居所/冬季避寒Plan B**

📁 详细对比数据、官方来源速查表已归档至 `references/cross-country-immigration-research.md` 西班牙章节。

## 申请进度追踪
<!-- Agent: 在此记录各项移民/签证申请的当前状态和关键节点 -->

## 决策记录
<!-- Agent: 在此记录重要的移民/定居决策 -->
