# 中文搜索策略：搜索引擎选择指南

## 核心结论

**搜索中文品牌名/产品对比/消费评测时，首选 Google 搜索（覆盖面广、对中文 SEO 索引质量好），配合 OpenCLI 原生中文平台适配器做深入查询。**

---

## 各搜索引擎实测效果（2026-06）

### Google（`opencli google search`）✅ 推荐

- **覆盖面最广**：能搜到知乎/什么值得买/微博/小红书等中文平台的内容页
- **中文品牌名处理**：分词通常正确，但特定新品牌可能被拆开
- **产品对比查询**：对 "500A 301S 区别" 这类复合查询返回可用的结果
- **缺点**：搜索结果中可能包含推广内容

### Brave Search（`opencli brave search`）🔄 备选

- **隐私优先**：不追踪用户，结果中立
- **中文能力**：对中文查询的分词不如 Google 精准
- **适用场景**：Google 返回结果不理想时作为备选

### 其他搜索引擎

| 引擎 | 状态 | 说明 |
|------|------|------|
| Yahoo（Bing 后端） | ⚠️ 中文弱 | Bing 中文分词偶有问题，不推荐中文查询首选 |
| 百度学术 | ⚠️ 场景局限 | 仅搜学术论文 |
| Google 学术 | ⚠️ 场景局限 | 仅搜学术论文 |

---

## OpenCLI 原生中文平台适配器（直接查，绕过搜索引擎）

OpenCLI 有大量可直接查询的中文平台，比搜索引擎二次跳转高效得多：

```bash
# 直接搜平台，无需经过搜索引擎
opencli zhihu search "500A 301S 区别" -f json
opencli xiaohongshu search "蕉内 蕉下 区别" -f json
opencli smzdm search "500A" -f json
opencli weibo search "蕉内" -f json
opencli hupu search "500A" -f json
opencli bilibili search "蕉内 评测" -f json
```

---

## 推荐搜索流程

```
中文消费品牌/产品对比查询？
├── 1. 先直接搜平台（如有相关 adapter）
│     opencli zhihu search "品牌 型号1 型号2 区别" -f json
│     opencli xiaohongshu search "品牌 对比" -f json
│     opencli smzdm search "型号" -f json
├── 2. 平台搜索不够？→ google 搜索补充
│     opencli google search "品牌 型号1 型号2 区别" -f json
├── 3. 需要 Brave 备选？
│     opencli brave search "品牌 对比 评测" -f json
└── 4. 需要全文？→ 用 dokobot 读取目标页面
      dokobot read '<目标URL>' --local
```

---

## 已知限制（中文消费查询场景）

| 平台 | 说明 |
|------|------|
| 京东/天猫 | 需要 JS 渲染 + 登录墙，opencli 站点适配器未覆盖 |
| 1688 | 有 adapter，但某些商品页需要 cookie |

## 经验教训

1. **OpenCLI 原生平台 > 搜索引擎**：知乎/小红书/什么值得买都有原生 adapter，直接用比 Google 搜索 → 点链接快得多
2. **Google 是中文 Web 搜索的务实选择**：比 Bing/Yahoo 的中文分词好，覆盖面广
3. **接受不完美**：中文消费内容生态封闭（登录墙、反爬），很多页面无法直接抓取全文。从搜索 snippet 拼凑信息是务实策略
