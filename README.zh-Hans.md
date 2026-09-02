# Scholium

[English](README.md) | [简体中文](README.zh-Hans.md)

> 面向哲学与人文研究、本地优先、以文档为权威的研究环境。

**当前公开 Core App Beta：**[v0.1.1-beta1](https://github.com/Aaronlves/Scholium/releases/tag/v0.1.1-beta1) ·
[下载 Apple 芯片版 Scholium](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-v0.1.1-beta1-macos-arm64.dmg) ·
[作为 Agent 协作 Preview 下载独立 CLI](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-CLI-macos.zip)

Scholium 是一款面向持续哲学与人文研究的原生 macOS 研究环境。它的内容核心是
一套由研究者治理、以文档为权威，并可由一位研究者与获得授权的外部 Agent 共同
维护的学术研究知识库。研究文档——而不是仪表盘、任务板、Agent 对话或记忆存储
——始终是主要界面对象。一个研究领域以**脉络（Triptych）**组织：**分析**保存
来源研究，**议题**汇集概念与争论，**写作**承载研究者自己的论证。

Markdown 始终是研究者所选文件夹中普通、可检查的文本。阅读、写作、搜索、关联、
评审与恢复不依赖 Agent。研究者邀请外部 Agent 时，对话留在 MCP host；Scholium
只通过本机 MCP adapter 提供当前检索与准确 Note 变更，并为已确认变更保存本机
Agent Change 证据。

Core App Beta 的验收结论只覆盖本地人工研究环境。外部 Agent 协作与独立安装的
CLI 保持为单独的 Preview，直到它们通过自己的验收 profile。

## 产品定位

Scholium 是学术研究知识库与研究工作台，不是聊天外壳或独立的 Agent 记忆产品。
不同 Agent、不同会话之间的研究连续性来自同一套可检查的文档、来源与研究者明确
判断，而不是隐藏的模型状态或平行的私有数据库。

研究者是知识库的构成性参与者，而不只是审核模型选择保存哪些“记忆”的人。准确
书写、声明范围与限制、Settle、Critique disposition 与主动安排的下一步，各自
保留狭窄而明确的语义。打开、阅读、沉默或允许写入不等于接受、重要性或 belief。

来源主张、解释、Agent 重构、研究者承诺、异议和后续修订保持可区分，不被压成没有
出处的事实或一个统一置信分数。派生搜索索引、关系图快照、缓存、排名与机器摘要是
可删除、可重建的投影；它们可以改善发现与上下文装配，却不能取代准确 Markdown、
来源或研究者明确判断的权威。

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
- [Scholium Core Protocol](ScholiumCore/Resources/Skills/Scholium%20System%20Skills/scholium-core-protocol/SKILL.md)

## 当前实现

Scholium 是一个由编译器强制边界的模块化单体。不可变值与用例协议位于
`ScholiumContracts`；内部仓储、存储、索引、监听与文件系统 I/O 位于
`ScholiumCore`；原生应用与 CLI 共享无界面的 `ScholiumApplication` 层。两个
交付目标都不导入 Core。

当前产品支持独立脉络与窗口、准确来源 Markdown 编辑、搜索与关联、Note 与文件夹
操作、外部编辑冲突、中断保存恢复、Settle、Critique、Zotero，以及固定的本机 MCP
协作面。Search 始终是供应用、CLI 与 MCP adapter 共用的可丢弃 Note-only 投影。

已安装的 `scholium` 可执行文件通过 `scholium mcp serve` 启动 stdio server。它只把
外部 MCP host 连接到当前正在运行的 Scholium App；不会启动应用、打开无界面
workspace，或直接读取脉络文件。首版只提供 workspace status、Note 搜索／读取／链接，
以及明确的创建／更新／移至系统纸篓操作。稳定 Note 身份、fingerprint compare-and-swap、
编辑器 flush、原子写入与 readback、派生一致性仍由应用拥有。

每个已确认 MCP 变更只生成一条本机 Agent Change 准确修订证据。Agent Changes 支持
比较与满足条件的更新直接 Undo；它们不是聊天、权限、审查、接受、Settlement 或
Research Records。Research Record 与 Handoff 的替代合同在另行决策前保持不可用。

发行版只捆绑精简的 Scholium Core Protocol Skill。研究者自己的 method Skills 位于
外部 Agent host；Scholium 不注册、检查或执行它们。这些路径只证明工程可达性，不
证明人类验收或普遍的哲学充分性。

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

打包性能采用严格的 G7 基线门禁。规格 §21.3 规定何时需要完整 campaign；影响性能的
Beta 只运行受影响的 packaged series。规范性阈值、fixture、采样、provenance 与证据
要求位于
[规格 §21.4](Docs/Specification/10-release-and-open-decisions.md#214-packaged-performance-gate)；当前结果和缺口
位于实现状态。

## 源码优先的 Beta 分发

源码优先的 Core App Beta 在同一个 GitHub release 页面发布采用
`GPL-3.0-or-later` 的准确标签源码、注明架构的应用 DMG 及其 SHA-256 校验值。
Agent Collaboration Preview 可另外发布版本匹配的独立 `Scholium-CLI-macos.zip` 及其校验值。
每个实际发布的产物都必须与 tag 和 package provenance 一致。应用启用 Sandbox，
不包含也不安装 CLI。打开 DMG 时，Finder 会并列显示 Scholium 与“应用程序”别名，
安装只需执行一次普通拖拽。

当前版本是
[v0.1.1-beta1](https://github.com/Aaronlves/Scholium/releases/tag/v0.1.1-beta1)：

- [macOS arm64 版 Scholium 应用 DMG](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-v0.1.1-beta1-macos-arm64.dmg)
  （[SHA-256](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-v0.1.1-beta1-macos-arm64.dmg.sha256)）；
- [独立 Scholium CLI](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-CLI-macos.zip)
  （[SHA-256](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-CLI-macos.zip.sha256)）；
- [准确标签源码](https://github.com/Aaronlves/Scholium/tree/v0.1.1-beta1)。

把产物与对应 checksum 文件下载到同一文件夹后，先运行：

```bash
shasum -a 256 -c Scholium-v0.1.1-beta1-macos-arm64.dmg.sha256
shasum -a 256 -c Scholium-CLI-macos.zip.sha256
```

准确 tag 已通过完整仓库门禁、优化 Release 构建、隔离 CLI 安装与 PATH 启动、
DMG 结构与签名检查、package checksum 以及固定 5 + 30 的打包性能门禁。四个已发布
资产随后均从 GitHub 重新下载并通过 release checksum。该版本采用的是当时有效的固定
采样规则；当前开发改用规格 §21.4 的有界、预先声明协议。完整自动化 UI 运行加上聚焦的
干净账户闭合验证建立了 88 项功能通过证据；环境没有提供 VoiceOver 时，可选的
VoiceOver 服务自动化仍为条件性跳过。§20 所定义的有界真人 VoiceOver、键盘、IME 与
视觉适应检查仍然开放，不计作已经通过的证据。准确测试数量与边界见
[验证证据](Docs/Status/04-verification.md)。

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

## Scholium MCP 设置

打开**设置 → 研究指导 → Agent 集成**，可检查应用、bridge 与 CLI 的可用状态，
复制对应 host 的设置命令，或在 Finder 中显示捆绑的 Core Protocol Skill。Scholium
只复制命令，不修改 host 配置，也不宣称安装成功。

源码 checkout 可先构建或安装 CLI，再用其绝对路径注册：

```bash
Tools/Scripts/install-cli.sh
codex mcp add scholium -- "$PWD/.build/cli-prefix/bin/scholium" mcp serve
claude mcp add scholium --scope user -- "$PWD/.build/cli-prefix/bin/scholium" mcp serve
```

应用必须已经运行，并打开预期脉络。stdio helper 通过只限当前用户且经过认证的本机
bridge 工作；当应用、bridge、所选脉络或当前状态不可用时明确失败，绝不回退到直接
文件系统或无界面 workspace 访问。

当前协作界面恰好发布十个 tools：`scholium_workspace_status`、
`scholium_search`、`scholium_read_note`、`scholium_read_record`、
`scholium_list_links`、`scholium_create_note`、`scholium_update_note`、
`scholium_trash_note`、`scholium_record_progress` 与
`scholium_correct_record_step`。不暴露 MCP Resources、Prompts、Agent
Sessions、Research Actions 或 Handoff。Research Record 是由 Agent 维护的
署名研究历史，不代表研究者接受，也不是 Note 写入权威。

普通双链可携带由源 Note 拥有的多行 Markdown 注释：
`[[目标]]{{注释}}`。Connect、Search 与 `scholium_list_links` 都保留每次
链接出现的方向、注释、局部上下文与来源位置；它们只公开作者写下的
链接出现，不为其指定关系类别。

## 存储与安全

权威研究内容始终保存在研究者选择的 Markdown 文件夹。位于“写作”旁边的小型
便携式 `.scholium/` 控制结构只保存规格允许的脉络 manifest、便携式设置、稳定
身份、Metadata、Settlement、Critique 与恢复状态。

Bookmark、绝对路径、窗口 session、索引、保存的查询、恢复、本机 bridge 认证、
准确 Agent Change 证据与未知预发布字节保存在本机：

```text
~/Library/Application Support/Scholium/State-v1/
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
