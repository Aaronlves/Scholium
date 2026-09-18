# Scholium

[English](README.md) | [简体中文](README.zh-Hans.md)

> 面向哲学与人文研究、本地优先、以文档为权威的研究环境。

**当前 Core App Beta：**[v0.2.5-beta](https://github.com/Aaronlves/Scholium/releases/tag/v0.2.5-beta) ·
[下载 Apple 芯片版 Scholium](https://github.com/Aaronlves/Scholium/releases/download/v0.2.5-beta/Scholium-v0.2.5-beta-macos-arm64.dmg)

这是当前的 App 单一发行 Beta。UI 与辅助功能验收由发布负责人另行完成；本次发布准备
不将这些检查声明为自动化证据。

Scholium 是一款面向持续哲学与人文研究的原生 macOS 研究环境。它的内容核心是
一套由研究者治理、以文档为权威，并可由一位研究者与获得授权的外部 Agent 共同
维护的学术研究知识库。研究文档——而不是仪表盘、任务板、Agent 对话或记忆存储
——始终是主要界面对象。一个研究领域以**脉络（Triptych）**组织：**分析**保存
来源研究，**议题**汇集概念与争论，**写作**承载研究者自己的论证。

Markdown 始终是研究者所选文件夹中普通、可检查的文本。阅读、写作、搜索、关联、
评审与恢复不依赖 Agent。研究者邀请外部 Agent 时，对话留在 MCP host；Scholium
只通过本机 MCP adapter 提供当前检索与准确 Note 变更，并为已确认变更保存本机
Agent Change 证据。

Core App Beta 的验收结论只覆盖本地人工研究环境。外部 Agent 协作保持为单独的 Preview，直到它们通过自己的验收 profile。

## 产品定位

Scholium 是学术研究知识库与研究工作台，不是聊天外壳或独立的 Agent 记忆产品。
不同 Agent、不同会话之间的研究连续性来自同一套可检查的文档、来源与研究者明确
判断，而不是隐藏的模型状态或平行的私有数据库。

来源、解释、Agent 重构与研究者判断保持可区分。派生索引与呈现不能取代准确
Markdown，写入权限也不等于接受。

Scholium 的人工核心不依赖 Obsidian、Zotero 或 Agent。它不是项目管理、文献管理、
永久 AI 聊天工具或完整的 Obsidian 替代品。

## 文档

- [规格](Docs/SCHOLIUM_SPEC.md)：目标产品行为、界面、辅助功能与发布契约，
  包括 [Design](Design.md)。
- [架构](Docs/IMPLEMENTATION_ARCHITECTURE.md)：模块、状态所有者、事务与编辑器
  边界，不是源码目录册。
- [实现状态](Docs/IMPLEMENTATION_STATUS.md)：简短实现范围、剩余工作和注明日期的
  证据。可达不等于已验收。
- [AGENTS.md](AGENTS.md)：开发与验证规则。

各入口路由到对应章节。README 提供设置方法，不再维护另一份功能清单；被取代的
决策和修改经过由 Git 保存。

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
./Tools/Scripts/lint.sh
./Tools/Scripts/lint.sh --fix
./Tools/Scripts/run-debug-app.sh
./Tools/Scripts/run-ui-tests.sh smoke
./Tools/Scripts/run-ui-tests.sh complete
```

`lint.sh` 使用仓库的 `swift-format` 配置检查 Swift 源码，并在隔离的临时依赖目录中
对 WebEditor 执行类型检查。`--fix` 会先原地格式化 Swift 源码，再执行检查。

UI runner 使用一次性 TestVault 副本和仓库内被忽略的 `.build/` 状态。`smoke`
运行规范旅程；`complete` 构建一次后串行运行保留的关键 UI 测试。两者都不等于
人类视觉或辅助技术验收。每次任务所需的 scoped checks 由 AGENTS.md 规定，
完整门禁不是所有修改的默认步骤。

修改 `WebEditor/` 后，请重建并验证已检入的 bundle：

```bash
./Tools/Scripts/build-editor.sh
./Tools/Scripts/verify-editor-bundle.sh
```

修改文档清单、规范性章节或 README 链接后，请验证闭合权威集合与本地链接：

```bash
python3 Tools/Scripts/validate-documentation-authority.py
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

Scholium.app 是唯一受支持的安装主体。发行从准确且干净的 tag 生成注明架构的
应用 DMG、SHA-256 校验文件、GPL-3.0-or-later 源码和许可声明。签名的连接组件与
Core Protocol 随应用一起更新，不再发行或支持独立 CLI、安装器或自更新程序。

打开 DMG 后，将 Scholium 拖入“应用程序”别名即可安装。安装前核对对应校验文件。
当前源码修改不会改变先前发布的产物；验收范围与产物证据以
[实现状态](Docs/IMPLEMENTATION_STATUS.md)为准。

便利版应用没有 Developer ID 签名，也未经过公证。DMG 版本从可信的项目 release
下载并核对校验值后：

1. 打开 DMG；
2. 把 **Scholium** 拖到**应用程序**别名上，然后推出 DMG；
3. 从“应用程序”尝试启动 Scholium 一次；
4. 打开**系统设置 → 隐私与安全性**，选择**仍要打开**；
5. 完成认证并确认**打开**。

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

打开**设置 → 集成 → Agents & Chat → External Agent Hosts**，可检查应用、bridge 与随附连接组件 的可用状态，
复制对应 host 的设置命令，或在 Finder 中显示捆绑的 Core Protocol Skill。Scholium
只复制命令，不修改 host 配置，也不宣称安装成功。

使用设置中复制的命令，它包含当前应用内连接组件的准确绝对路径，无需单独安装。
原位置更新应用可保留配置；移动应用后，需要重新复制并执行设置命令。

应用必须已经运行，并打开预期脉络。stdio helper 通过只限当前用户且经过认证的本机
bridge 工作；当应用、bridge、所选脉络或当前状态不可用时明确失败，绝不回退到直接
文件系统或无界面 workspace 访问。

当前工具范围以[Agent 协作 §8.3](Docs/Specification/03-agent-collaboration-and-workflows.md#83-tool-contract)
为准，覆盖检索、来源附件、受控笔记操作和 Agent Changes 比较与恢复。
研究问题与讨论使用普通笔记和明确授权，不具有自动记录生命周期。

普通双链可携带由源 Note 拥有的多行 Markdown 注释：
`[[目标]]{{注释}}`。Connect、Search 与 `scholium_list_links` 都保留每次
链接出现的方向、注释、局部上下文与来源位置；它们只公开作者写下的
链接出现，不为其指定关系类别。

## Chat 中使用 Zotero（可选集成）

在 Zotero“设置 → 高级”中启用“允许本机其他应用与 Zotero 通信”。Chat 使用随
Scholium 提供的 `scholium-zotero` 连接搜索、读取和导出 Zotero 内容；在明确确认后，
也可以通过 Zotero 自己的 API/Connector 导入记录和修改条目。不需要安装社区 Zotero
服务、Python 运行时或单独的依赖包。

Zotero 仍是文献库的唯一权威。导入会绑定当前可编辑的库或集合；条目修改必须指定
准确的文献库并提供当前 Zotero 版本。Scholium 不直接访问 Zotero 私有数据库。完整范围
与引用规则见[规范 §15](Docs/Specification/05-integrations-onboarding-and-boundaries.md#15-zotero-integration)。

## 存储与安全

权威研究内容始终保存在研究者选择的 Markdown 文件夹。位于“写作”旁边的小型
便携式 `.scholium/` 控制结构只保存
[§3.3](Docs/Specification/01-foundation-and-triptych.md#33-scholium-and-machine-local-state)列出的控制状态。
研究正文和评析均保持为普通 Markdown，保存恢复数据留在本机。

Bookmark、绝对路径、窗口 session、索引、保存的查询、恢复、本机 bridge 认证、
准确 Agent Change 证据与未知预发布字节保存在本机：

```text
~/Library/Application Support/Scholium/State-v1/
```

写入保持准确来源；并发编辑冲突不会丢弃未保存文本。安全与恢复契约归
[保存与恢复 §14](Docs/Specification/04-connect-search-and-recovery.md#14-save-agent-changes-and-recovery)，
机制归架构，尚未验收的边界归实现状态。

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
ScholiumApplication/       应用与随附组件共享的应用能力
Scholium/                  原生 macOS 应用与面向人的交互
WebEditor/                 TypeScript 与 CodeMirror 源码
Tests/                     Contracts、Core、Application 与 App 测试
UITests/                   隔离的一次性 macOS UI 旅程
Docs/SCHOLIUM_SPEC.md      目标权威清单与阅读路由
Docs/Specification/       规范性产品、界面、辅助功能与发布章节
Docs/IMPLEMENTATION_ARCHITECTURE.md
                           从属架构清单与阅读路由
Docs/Architecture/        模块、运行时、状态、编辑器、呈现与边界章节
Docs/IMPLEMENTATION_STATUS.md
                           当前证据清单与阅读路由
Docs/Status/              剩余工作与当前证据
Tools/Scripts/             构建、验证、QA、性能与发布工具
```
