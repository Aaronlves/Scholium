# Scholium

[English](README.md) | [简体中文](README.zh-Hans.md)

> 面向哲学与人文研究、本地优先、以文档为权威的研究环境。

**当前公开 Beta：**[v0.1.0-beta.8](https://github.com/Aaronlves/Scholium/releases/tag/v0.1.0-beta.8) ·
[下载 Apple 芯片版 Scholium](https://github.com/Aaronlves/Scholium/releases/download/v0.1.0-beta.8/Scholium-v0.1.0-beta.8-macos-arm64.dmg) ·
[下载独立 CLI](https://github.com/Aaronlves/Scholium/releases/download/v0.1.0-beta.8/Scholium-CLI-macos.zip)

Scholium 是一款面向持续哲学与人文研究的原生 macOS 研究环境。它的内容核心是
一套由研究者治理、以文档为权威，并可由一位研究者与获得授权的外部 Agent 共同
维护的学术研究知识库。研究文档——而不是仪表盘、任务板、Agent 对话或记忆存储
——始终是主要界面对象。一个研究领域以**脉络（Triptych）**组织：**分析**保存
来源研究，**议题**汇集概念与争论，**写作**承载研究者自己的论证。

Markdown 始终是研究者所选文件夹中普通、可检查的文本。阅读、写作、搜索、关联、
评审与恢复不依赖 Agent。研究者邀请外部 Agent 时，Scholium 会冻结准确的目标、
材料、修订、方法与权限，使协助保持有边界、可归属、可审查、可恢复。

## 产品定位

Scholium 是学术研究知识库与研究工作台，不是聊天外壳或独立的 Agent 记忆产品。
不同 Agent、不同会话之间的研究连续性来自同一套可检查的文档、来源、研究记录、
方法与研究者明确判断，而不是隐藏的模型状态或平行的私有数据库。因此，这套知识库
可以为 Agent 提供外部长期研究记忆，但 Agent 继承只是使用 Scholium 的一种能力，
不是第二个产品或内容权威。

研究者是知识库的构成性参与者，而不只是审核模型选择保存哪些“记忆”的人。准确
书写、声明范围与限制、Settle、可归属 Discussion、Critique disposition、研究者
评价与主动安排的下一步，各自保留狭窄而明确的语义。后续 Agent 只能依赖相应 owner、
actor、修订、范围和动作语义实际建立的内容。打开、停留、沉默或允许写入不等于
接受、重要性或 belief。

来源主张、解释、Agent 重构、研究者承诺、异议和后续修订保持可区分，不被压成没有
出处的事实或一个统一置信分数。派生搜索索引、关系图快照、缓存、排名与机器摘要是
可删除、可重建的投影；它们可以改善发现与上下文装配，却不能取代准确 Markdown、
来源、研究记录或研究者明确判断的权威。

Scholium 的人工核心不依赖 Obsidian、Zotero 或 Agent。它不是项目管理、文献管理、
永久 AI 聊天工具或完整的 Obsidian 替代品。

## 文档

请使用足以回答问题的最小权威集合：

1. [Scholium 规格](Docs/SCHOLIUM_SPEC.md)是唯一目标权威清单；由它声明的章节分别
   负责产品行为、界面设计、辅助功能、发布要求和现行决策。
2. [实现架构](Docs/IMPLEMENTATION_ARCHITECTURE.md)将任务路由到负责模块、运行时、
   状态与编辑器边界的章节。
3. [实现状态](Docs/IMPLEMENTATION_STATUS.md)将任务路由到当前可达能力与界面、
   开放工作、注明日期的验证证据和尚未完成的验收。
4. 本 README、实际构建、测试和脚本提供设置方法与当前实现证据。

目标文字不等于实现证明。已经完成使命的迁移 Roadmap 与被取代的决策记录保留在
Git 历史中，不再作为平行权威。

仍然独立的任务型操作参考包括：

- [高级 CSS 目标边界](Docs/Specification/07-document-and-research-interface.md#1841-advanced-css-boundary)
- [第一方 Zotero MCP 传输](Docs/ZOTERO_MCP.md)
- [研究方法资源](ScholiumCore/Resources/Skills/README.md)

## 当前实现

Scholium 是一个由编译器强制边界的模块化单体。不可变值与用例协议位于
`ScholiumContracts`；内部仓储、存储、索引、监听与文件系统 I/O 位于
`ScholiumCore`；原生应用与 CLI 共享无界面的 `ScholiumApplication` 层。两个
交付目标都不导入 Core。

当前产品支持独立脉络与窗口、准确来源 Markdown 编辑、搜索与关联、笔记和文件夹
生命周期、外部编辑冲突、恢复点和逐笔记恢复、Settle、统一 Discussion、Critique，
以及带可编辑当前 Skill、包内普通 references 和 philosophical lenses、学术 Profile
的 Research Actions。Search v9 为应用、CLI、研究记录与通过认证的 Research Context 提供同一个
类型明确的检索 owner，支持词法、规范元数据、明确直接关系、YAML summary 与
Record 查询，而不让索引取得研究内容权威。

获得邀请的外部 Agent 可以在本地与一个由研究者创建的 Run 配对，取得有界研究
上下文，请求多文档写入集合，执行按修订核验的直接编辑，提交一个结果，留下便携式
研究记录，并通过独立的新 Run 继续研究。每个脉络的一项协作策略、进程期 Session、
不可复用的写入能力、准确冲突与恢复，以及由一条 Record 拥有的研究者评价共同保持
研究者控制。新建 Analysis 前，独立 CLI 会先向 Scholium 取得当前 Analyses vault、
Settings 必填字段、根目录受管目的地，以及路径／身份／来源
恢复状态；只有 ready 的预检才能开始有后果的创建。Analyze Record 可携带推荐文献。
研究者选择的本地或 Zotero 来源材料继续通过单独验证的证据通道交付；可选的第一方
Zotero MCP 传输继续可用。研究者选择子目录时，先由研究者创建或选择现有 Analysis，
而不是让 Agent 在创建请求中声明路径。

这些路径证明的是当前工程可达性，不表示长期 Agent 继承或哲学研究质量已经通过
产品验收。持续真实研究、辅助技术审查、干净账户 App／CLI 与外部 Agent 验收，
以及方案比较仍是明确的证据门。

研究文档、搁置与纸篓共享同一棵原生 AppKit 文件夹／笔记大纲及浏览逻辑。研究文档
可以创建笔记和文件夹，并保留菜单、键盘、辅助功能与拖动等组织路径；搁置与纸篓内
的笔记仍可正常浏览，放回则是直接且可逆的操作。新建或移动的来源一经持久化提交，
就会立即发布到所属窗口；可丢弃的搜索、图与诊断投影继续在后台刷新。

每篇笔记的研究库限定稳定身份与准确来源指纹分别承担身份和版本职责。因此，重命名
与文件夹移动可以保留编辑器、标签页和研究身份，而每次变更仍会在提交前重新核验
当前来源修订与目标位置。

应用、CLI、交付合同与记录全部使用 Action 身份。受保护的 Local Execution v3
仅作为内部的容纳、修订、完成、冲突与恢复机制。未知的预发布数据保持原字节、
不可见、不解析且不产生授权；产品中没有旧数据入口或兼容命令。

准确证据以及尚未完成的人类、辅助功能、性能、打包和发布工作，请参阅
[实现状态](Docs/IMPLEMENTATION_STATUS.md)。

## 环境要求

运行打包构建需要 macOS 26 或更高版本。当前公开 Beta 仅提供 Apple 芯片
（`arm64`）版本。测试者不需要 Xcode。

构建 Scholium 需要完整 Xcode，以及 `Package.swift` 要求的编译器与 SDK。仓库
解析器会采用明确且有效的 `DEVELOPER_DIR`、完整的 `xcode-select` 选择，或常规
位置中的 Beta/正式版 Xcode。只有重新构建 TypeScript 编辑器 bundle 时才需要
Node.js。

## 构建与测试

请从仓库根目录运行命令。完整仓库门禁为：

```bash
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
DEVELOPER_DIR="$developer_dir" ./Tools/Scripts/verify.sh
```

常用开发命令：

```bash
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
DEVELOPER_DIR="$developer_dir" swift build
DEVELOPER_DIR="$developer_dir" swift test
./Tools/Scripts/run-debug-app.sh
./Tools/Scripts/run-ui-tests.sh smoke
./Tools/Scripts/run-ui-tests.sh complete
```

UI runner 使用一次性 TestVault 副本和仓库内被忽略的 `.build/` 状态。`smoke`
运行规范旅程；`complete` 枚举当前测试套件、只构建一次并串行执行。这些属于自动化
开发检查，不等于人类视觉或辅助技术验收。

修改 `WebEditor/` 后，请重建并验证已检入的 bundle：

```bash
./Tools/Scripts/build-editor.sh
./Tools/Scripts/verify-editor-bundle.sh
```

修改文档清单、规范性章节或 README 链接后，请验证闭合权威集合与本地链接：

```bash
python3 Tools/Scripts/validate-documentation-authority.py
```

升级安全 runner 使用不同的一次性 QA 构建，不接触研究库：

```bash
./Tools/Scripts/verify-qa-upgrade-safety.sh \
  --baseline .build/upgrade/baseline/Scholium-QA.app \
  --candidate .build/qa-runtime/Scholium-QA.app \
  --output .build/upgrade/evidence
```

所有 SwiftPM scratch、Xcode DerivedData、QA 应用、fixture 副本、索引、日志与结果
bundle 都放在仓库内被忽略的 `.build/` 路径下。仓库本身必须位于 Desktop、
Documents、CloudStorage 和其他 File Provider 管理路径之外。

可在 Finder 中使用 `Manage Scholium Development Storage.command`，也可从命令行
检查和清理可重建状态：

```bash
./Tools/Scripts/manage-development-storage.sh report
./Tools/Scripts/manage-development-storage.sh clean-stale
./Tools/Scripts/manage-development-storage.sh clean-all
```

清理命令默认为 dry run；审查准确的 allowlist 目标后才添加 `--delete`。它们不会
删除源码、应用状态、打包构建、脉络文件或便携式 `.scholium/` 数据。

打包性能属于独立发布门禁。规范性阈值、fixture、采样、provenance 与证据要求位于
[规格 §21.4](Docs/Specification/10-release-and-open-decisions.md#214-packaged-performance-gate)；当前结果和缺口
位于实现状态。

## 源码优先的 Beta 分发

源码优先的 Beta 在同一个 GitHub release 页面发布采用 `GPL-3.0-or-later` 的
准确标签源码、注明架构的应用 DMG、独立的 `Scholium-CLI-macos.zip` 以及两者的
SHA-256 校验值。tag、版本和 package provenance 必须一致。应用启用 Sandbox，
不包含也不安装 CLI。打开 DMG 时，Finder 会并列显示 Scholium 与“应用程序”别名，
安装只需执行一次普通拖拽。

当前版本是
[v0.1.0-beta.8](https://github.com/Aaronlves/Scholium/releases/tag/v0.1.0-beta.8)：

- [macOS arm64 版 Scholium 应用 DMG](https://github.com/Aaronlves/Scholium/releases/download/v0.1.0-beta.8/Scholium-v0.1.0-beta.8-macos-arm64.dmg)
  （[SHA-256](https://github.com/Aaronlves/Scholium/releases/download/v0.1.0-beta.8/Scholium-v0.1.0-beta.8-macos-arm64.dmg.sha256)）；
- [独立 Scholium CLI](https://github.com/Aaronlves/Scholium/releases/download/v0.1.0-beta.8/Scholium-CLI-macos.zip)
  （[SHA-256](https://github.com/Aaronlves/Scholium/releases/download/v0.1.0-beta.8/Scholium-CLI-macos.zip.sha256)）；
- [准确标签源码](https://github.com/Aaronlves/Scholium/tree/v0.1.0-beta.8)。

把产物与对应 checksum 文件下载到同一文件夹后，先运行：

```bash
shasum -a 256 -c Scholium-v0.1.0-beta.8-macos-arm64.dmg.sha256
shasum -a 256 -c Scholium-CLI-macos.zip.sha256
```

准确 tag 已通过完整仓库门禁、优化 Release 构建、隔离 CLI 安装与 PATH 启动、
DMG 结构与签名检查以及 package checksum。四个已发布资产随后均从 GitHub 重新下载
并通过 release checksum。发布负责人批准此 Beta 在打包性能、干净账户、视觉和
首次启动 UI 验收仍未完成的情况下发布；这些缺口仍然开放，不计作已经通过的证据。
准确测试数量与边界见[验证证据](Docs/Status/04-verification.md)。

便利版应用没有 Developer ID 签名，也未经过公证。DMG 版本从可信的项目 release
下载并核对校验值后：

1. 打开 DMG；
2. 把 **Scholium** 拖到**应用程序**别名上，然后推出 DMG；
3. 从“应用程序”尝试启动 Scholium 一次；
4. 打开**系统设置 → 隐私与安全性**，选择**仍要打开**；
5. 完成认证并确认**打开**。

对于历史版本 `v0.1.0-beta.6` 的应用 ZIP，请先解压并把 **Scholium** 移到
“应用程序”，再执行第 3–5 步。

不要关闭 Gatekeeper，也不要递归移除 quarantine。准确发布门禁、产物内容、干净
账户验证与未来签名渠道规则维护在
[规格 §21.5](Docs/Specification/10-release-and-open-decisions.md#215-source-first-beta-distribution)。

## 脉络设置

首次启动会要求研究者分别选择**分析**、**议题**和**写作**文件夹。便携式
`.scholium/` 数据位于“写作”旁边，因此 macOS 还会请求访问“写作”所在文件夹；
该访问边界不是第四个研究库。建议三者位于同一父目录，但不作强制要求。

使用**文件 → 新建脉络…**配置另一个研究领域，使用**文件 → 打开脉络**在独立
窗口打开已注册脉络，使用**文件 → 新建窗口**为当前脉络打开另一个独立窗口。
两个脉络不能共享同一个“写作”侧控制目录。

## Scholium CLI

首次启动准备 Agent 时，或之后打开**设置 → 研究指导 → 来源与集成 → Scholium
CLI**，选择**复制 CLI 安装说明**并交给外部 Agent。该说明只授权下载
[官方独立 CLI](https://github.com/Aaronlves/Scholium/releases/latest/download/Scholium-CLI-macos.zip)，
并且只允许在 `~/.local/bin` 下安装可执行文件与相邻资源 bundle；它禁止 `sudo`、
PATH／profile 编辑、替代下载来源和 quarantine 修改。应用不会检查、执行、安装、
更新、移除 CLI，也不会报告 CLI 状态。

源码 checkout 的安装与检查方式：

```bash
Tools/Scripts/install-cli.sh
scholium version --format json
scholium doctor --format json
scholium update --check
scholium update
scholium help action
scholium help agent start
```

CLI 与应用共享脉络、搜索、链接和图路径、工作区目录与关注、准确读取、Discussion
回复、可恢复 Actions、推荐文献、按稳定 Note UUID 执行的 `record list`、按 Record
UUID 执行的 `record read`，以及带修订检查的笔记操作。Record 读取返回便携式
Record owner 及其准确指纹，不创建 Note dossier。修改已有笔记时必须提供
`scholium read --format json` 返回的当前 SHA-256。

`Tools/Scripts/package-app.sh` 会生成独立的 `Scholium-CLI-macos.zip`；其中的
`install.sh` 执行与 Agent 说明一致的用户级安装，不修改 shell 或 macOS 安全配置。
安装后的 CLI 可显式使用 `scholium update --check` 检查官方发行版，或使用
`scholium update` 安装经验证的更新；自更新不在后台运行、不修改 PATH，校验失败时保留现有的
可执行文件与 bundle。

安装后的 `scholium agent` 命令让外部 Agent 通过仅限回环地址的本机桥，与一个由研究者
创建的 Run 配对、获取结构化上下文、申请有界写入、提交一个结果、继续研究并结束
Run。配对码只通过标准输入读取；Scholium 不会启动或监管 Agent。Agent Run 流程由
认证后返回的 [Core Protocol](ScholiumCore/Resources/Skills/Scholium%20System%20Skills/scholium-core-protocol/references/runtime-protocol.md)
唯一拥有，当前 CLI 语法由安装版本的命令帮助拥有。可选 Zotero 传输见
[Zotero MCP](Docs/ZOTERO_MCP.md)。

## 存储与安全

权威研究内容始终保存在研究者选择的 Markdown 文件夹。位于“写作”旁边的小型
便携式 `.scholium/` 控制结构，只保存规格允许的脉络 manifest、便携式设置与
Skills、当前研究者状态、活跃 Discussion 和白名单 Research Records。

Bookmark、绝对路径、窗口 session、索引、保存的查询、受保护执行、恢复、传输
状态、组装后的指令与未知预发布字节保存在本机：

```text
~/Library/Application Support/Scholium/
```

每次权威写入都必须验证容纳边界与预期修订、保留被替换字节、验证目标源码、原子
写入，并在冲突时保留未保存的编辑器 buffer。macOS 文件协调负责与其他参与者协商
访问，描述符相对验证仍是实际写入权威；预写入恢复会保留被中断保存的准确候选内容，
而不会把监听事件或未完成操作当作权威。已配置 File Provider domain 的真实验收仍
明确列在实现状态中。派生的搜索、图、渲染与诊断状态都是可丢弃投影，绝不用于重建
可写源码。

开发测试绝不能使用真实研究库。

## 许可证

除非另有说明，Scholium 原创源码采用
[GNU General Public License, version 3 or later](LICENSE)
（`GPL-3.0-or-later`）。第三方组件保留各自许可证；详见
[第三方声明](THIRD_PARTY_NOTICES.md)。

## 仓库结构

```text
ScholiumContracts/         不可变值、协议与源码语义
ScholiumCore/              内部仓储、索引、监听与 I/O
ScholiumApplication/       应用与 CLI 共享的无界面能力
Scholium/                  原生 macOS 应用与面向人的交互
ScholiumCLI/               CLI 解析、格式化与交付适配
WebEditor/                 TypeScript 与 CodeMirror 源码
Tests/                     Contracts、Core、Application 与 App 测试
UITests/                   隔离的一次性 macOS UI 旅程
Docs/SCHOLIUM_SPEC.md      目标权威清单与阅读路由
Docs/Specification/       规范性产品、界面、辅助功能与发布章节
Docs/IMPLEMENTATION_ARCHITECTURE.md
                           从属架构清单与阅读路由
Docs/Architecture/        模块、运行时、状态、编辑器与交付章节
Docs/IMPLEMENTATION_STATUS.md
                           当前证据清单与阅读路由
Docs/Status/              能力、界面、开放工作与注明日期的证据
Docs/ZOTERO_MCP.md         非规范性的第一方 Zotero 操作指南
Tools/Scripts/             构建、验证、QA、性能与发布工具
```
