# macOS Application Support / Group Containers 已知目录映射

## Application Support 目录 → 归属

### Apple 系统组件（排除，不删）

| 目录名 | 归属 |
|--------|------|
| `AddressBook` | 通讯录 |
| `Animoji` | 拟我表情 |
| `App Store` | App Store |
| `AppStateBackupData.data` | 系统备份 |
| `Automator` | 自动操作 |
| `Caches` | 系统缓存 |
| `CallHistoryDB` | 通话记录 |
| `CallHistoryTransactions` | 通话记录事务 |
| `ClipboardAppIcons` | 剪贴板图标 |
| `CloudDocs` | iCloud 文档 |
| `ControlCenter` | 控制中心 |
| `CrashReporter` | 崩溃报告 |
| `DifferentialPrivacy` | 差分隐私 |
| `DiskImages` | 磁盘映像 |
| `Dock` | 程序坞 |
| `FaceTime` | FaceTime |
| `FamilySettings` | 家人共享 |
| `FileProvider` | 文件提供程序 |
| `Knowledge` | Siri 知识库 |
| `MobileSync` | iOS 设备同步 |
| `Music` | 音乐 |
| `ProApps` | 专业 App 共享组件 |
| `RefSrcSymbols` | Xcode 调试符号 |
| `SymbolSourceSymbols` | 符号源 |
| `Symbols` | 系统符号 |
| `SyncServices` | 同步服务 |
| `com.apple.*`（所有） | 系统组件 |
| `contactsd` | 通讯录守护进程 |
| `coreMLCache` | Apple Intelligence ML 模型缓存 |
| `familycircled` | 家人共享守护进程 |
| `homeenergyd` | 家庭能耗 |
| `iCloud` | iCloud |
| `icdd` | iCloud 驱动 |
| `icloudmailagent` | iCloud 邮件代理 |
| `identityservicesd` | Apple ID 服务 |
| `locationaccessstored` | 位置服务 |
| `networkserviceproxy` | 网络代理 |
| `privatecloudcomputed` | 私有云计算 |
| `stickersd` | 贴纸 |
| `summary-events` | 摘要事件 |
| `themes` | 系统主题 |
| `tipsd` | 提示 |

### 第三方 App 映射

| 目录名 | 对应 App | Bundle ID / Team ID |
|--------|----------|---------------------|
| `Adobe` | Adobe 系列（共用） | `JQ525L2MZD` |
| `AlDente` | AlDente | — |
| `BraveSoftware` | Brave Browser | — |
| `CEF` | Chromium Embedded Framework（多 App 共用） | — |
| `Claude` | Claude | — |
| `Claude-3p` | Claude 第三方集成 | — |
| `Code` | Visual Studio Code | — |
| `Doubao` | 豆包 | — |
| `DoubaoIme` | 豆包输入法 | — |
| `GitKraken` | GitKraken | — |
| `GitKrakenCLI` | GitKraken CLI | — |
| `Google` | Google Chrome / 其他 Google 应用 | — |
| `JetBrains` | JetBrains IDE（共用） | — |
| `LarkShell` | 飞书 / Lark | `JBRN9C6V7T` |
| `LaunchOS` | LaunchOS | — |
| `Microsoft` | Microsoft 365 / Visual Studio | — |
| `Microsoft DevDiv` | .NET SDK / VS Code dotnet 扩展 | ⚠️ 即使没有 Office，dotnet 也可能生成此目录 |
| `Microsoft Edge` | Edge 浏览器 | — |
| `Mozilla` | Firefox | — |
| `Obsidian` | Obsidian | — |
| `Ollama` | Ollama | — |
| `PDF Expert` | PDF Expert | `com.readdle.PDFExpert-Mac` |
| `Pixea` | Pixea | — |
| `PopClip` | PopClip | — |
| `PremiumSoft CyberTech` | Navicat Premium | — |
| `Quark` | 夸克 | — |
| `Surge` | Surge | `com.nssurge.surge-mac` |
| `Topaz Labs LLC` | Topaz Video AI | — |
| `Trader Workstation` | IBKR Trader Workstation | — |
| `Vencord` | Vencord（Discord mod） | ⚠️ Vesktop 内置 Vencord，单独安装 Vesktop 后此目录可能仍在使用 |
| `Vesktop` | Vesktop | — |
| `Vivaldi` | Vivaldi Browser | — |
| `WhisperScript` | WhisperScript | — |
| `Xcode` | Xcode | — |
| `YouTube Music Desktop App` | YouTube Music Desktop | — |
| `Zed` | Zed | — |
| `balena-etcher` / `balenaEtcher` | balenaEtcher | — |
| `chrome-devtools-mcp` | Chrome DevTools MCP 工具 | — |
| `cloud-code` | Google Cloud Code | — |
| `dotnet` | .NET SDK | — |
| `obsidian` | Obsidian | — |
| `oss-browser` | 阿里云 OSS Browser | — |
| `vesktop` | Vesktop | — |
| `virtualenv` | Python virtualenv | — |
| `z-library` | Z-Library | — |

## Group Containers 目录 → 归属

### 第三方 App 映射

| 目录名 | 对应 App | Bundle ID/Team ID |
|--------|----------|-------------------|
| `243LU875E5.groups.com.apple.podcasts` | Apple Podcasts | — |
| `43B53CMF9D.com.netease.163music` | 网易云音乐 | `43B53CMF9D` |
| `4C6364ACXT.com.parallels.*` | Parallels Desktop | `4C6364ACXT` |
| `4K6FWZU8C4.group.cn.better365` | Better365 系列（BetterZip Setapp版） | ⚠️ 与 BetterZip 直接版 team ID `79RR9LPM2N` 不同 |
| `5A4RE8SF68.com.tencent.xinWeChat` | 微信 | `5A4RE8SF68` |
| `5HD2ARTBFS.com.canva.canvaeditor` | Canva | `5HD2ARTBFS` |
| `6N38VWS5BX.ru.keepcoder.Telegram*` | Telegram | `6N38VWS5BX` |
| `79RR9LPM2N.group.com.macitbetter.betterzip*` | BetterZip 直接版 | `79RR9LPM2N` |
| `7L3ARZ2SN3.com.eusoft.eudic` | 欧路词典 | `7L3ARZ2SN3` |
| `88L2Q4487U.com.tencent.WeWorkMac*` | 企业微信 | `88L2Q4487U` |
| `8DKG4XB37M.group.com.nektony.MacCleaner-PRO-SIII` | MacCleaner Pro / Cleaner | `8DKG4XB37M` |
| `9699UND7H5.group.com.netease.mumu.nemux` | 网易 MuMu 模拟器 | `9699UND7H5` |
| `HUAQ24HBR6.dev.orbstack` | OrbStack | `HUAQ24HBR6` |
| `JBRN9C6V7T.com.larksuite.macos.lark` | 飞书/Lark | `JBRN9C6V7T` |
| `JQ525L2MZD.com.adobe.*` | Adobe CC 全家桶（共用） | `JQ525L2MZD` ⚠️ 安装任意 Adobe 产品都保留全部 |
| `PTN9T2S29T.com.apple.VAWorkspace*` | Final Cut Pro / Motion / Compressor | — |
| `SY64MV22J9.com.raycast.macos.shared` | Raycast | `SY64MV22J9` |
| `UBF8T346G9.*` | Microsoft Office / Teams / OneDrive 全套 | `UBF8T346G9` |
| `UQ8HT4Q2XM.Mattermost.Desktop` | Mattermost | `UQ8HT4Q2XM` |
| `W6L39UYL6Z.group.com.IdeasOnCanvas.MindNode` | MindNode | `W6L39UYL6Z` |
| `EQHXZ8M8AV.com.google.one` | Google One | — |
| `FN2V63AD2J.com.tencent` | 腾讯系共用数据 | — |
| `group.com.apple.*`（所有） | Apple 系统组件 | **排除，不删** |
| `group.com.eusoft.eudic` | 欧路词典 | — |
| `group.com.google.common` | Google 共用数据 | — |
| `group.com.liguangming.Shadowrocket` | Shadowrocket | — |
| `group.is.workflow.shortcuts` | 快捷指令 | — |

## ~/Library 根级文件映射

根目录下的裸文件（非子目录）通常是不规范放置，需要逐个溯源。

| 文件名 | 归属 | 说明 |
|--------|------|------|
| `.DS_Store` | macOS 系统 | Finder 元数据，自动重建 |
| `.localized` | macOS 系统 | 本地化标记，勿删 |
| `GroupContainersAlias` | macOS 系统 | → Group Containers 的符号链接 |
| `0f44d..._MPDB.sqlite` | **Surge** | Mixpanel 分析数据库，含 `$app_release`/`MacFeature.SystemProxy` 等字段 |
| `SGMRuleCounter.sqlite` (+ shm/wal) | **Surge** | SGM = SurGe Mac，规则命中计数器（Clash 规则集匹配统计） |
| `Preference` | **Royal TSX** | Apple Binary Plist，含 `SUFeedURL: royaltsx-v6.royalapps.com` + MS AppCenter 数据 |
| `com.sensorsdata.analytics.mini.SensorsAnalyticsSDK.message-v2.plist` | **神策数据 SDK** | 小程序埋点 SDK，实际是 SQLite 数据库（非 plist），表 `dataCache` |
| `snowplowEvents.sqlite` | 未知 App | Snowplow 分析事件，events 表为空则可删 |

## Application Support 补充映射

| 目录名 | 对应 App | 说明 |
|--------|----------|------|
| `Softdeluxe` | Softdeluxe 软件 | 25 MB，若 App 列表无匹配则可删 |
| `WorkBuddyExtension` | 未知扩展 | ~1 MB，通常为残留 |
| `com.bugsnag.Bugsnag` | Bugsnag 错误监控 | 若未独立安装则为残留 |
| `com.afs.adf.PeaSpotify` | Spotify 相关插件 | 未安装 Spotify 则残留 |
| `nomic.ai` | Nomic / GPT4All | 未安装则残留 |
| `io.sentry` | Sentry | 若未独立安装则为残留 |
| `gogcli` | GOG 游戏平台 | 未安装则残留 |
| `LexarUSBENC` | Lexar U盘加密工具 | 未安装则残留 |
| `583749.cmlicense` | 未知许可证文件 | 无法溯源则可删 |
| `wpkdata` | 未知 | 无法溯源则可删 |

## Group Containers 补充映射

| 目录名 | 对应 App | 说明 |
|--------|----------|------|
| `group.com.microsoft.BingWallpaper` | Bing 壁纸 | 若未安装则可删 |
| `X2JNK7LY8J.lv` / `X2JNK7LY8J.ve` | 未知 App | 各 4 KB，可能是视频/图像处理软件残留 |
