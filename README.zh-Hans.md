# Scholium

[English](README.md) | [简体中文](README.zh-Hans.md)

> 一间安静、本地优先的哲学写作室。

Scholium 是一款原生 macOS 研究工作台，用于专注阅读、忠实于来源的分析、概念
发展与哲学写作。研究文档——而不是仪表盘、任务板或聊天记录——始终是主要界面
对象。一个研究领域以**脉络（Triptych）**组织：**分析**保存来源研究，**议题**
汇集概念与争论，**写作**承载研究者自己的论证。

Markdown 始终是研究者所选文件夹中普通、可检查的文本。阅读、写作、搜索、关联、
评审与恢复不依赖 Agent。研究者邀请外部 Agent 时，Scholium 会冻结准确的目标、
材料、修订、方法与权限，使协助保持有边界、可归属、可审查、可恢复。

## 文档

请使用足以回答问题的最小权威集合：

1. [Scholium 规格](Docs/SCHOLIUM_SPEC.md)是唯一目标权威清单；由它声明的章节分别
   负责产品行为、界面设计、辅助功能、发布要求和现行决策。
2. [实现架构](Docs/IMPLEMENTATION_ARCHITECTURE.md)将任务路由到负责模块、运行时、
   状态与编辑器边界的章节。
3. [实现状态](Docs/IMPLEMENTATION_STATUS.md)将任务路由到当前可达行为、剩余工作、
   已完成迁移、最新验证基线和尚未完成的验收。
4. 本 README、实际构建、测试和脚本提供设置方法与当前实现证据。

目标文字不等于实现证明。已经完成使命的迁移 Roadmap 与被取代的决策记录保留在
Git 历史中，不再作为平行权威。

仍然独立的任务型操作参考包括：

- [CSS 片段合同](Docs/CSS_SNIPPETS.md)
- [第一方 Zotero MCP 传输](Docs/ZOTERO_MCP.md)
- [研究方法资源](ScholiumCore/Resources/Skills/README.md)

## 当前实现

Scholium 是一个由编译器强制边界的模块化单体。不可变值与用例协议位于
`ScholiumContracts`；内部仓储、存储、索引、监听与文件系统 I/O 位于
`ScholiumCore`；原生应用与 CLI 共享无界面的 `ScholiumApplication` 层。两个
交付目标都不导入 Core。

当前产品支持独立脉络与窗口、准确来源 Markdown 编辑、搜索与关联、笔记和文件夹
生命周期、外部编辑冲突、恢复点和逐笔记恢复、Settle、统一 Discussion、Critique，
以及带可编辑当前 Method、学术 Profile 与 Philosophical Practice 的 Research
Actions。每个脉络只有一项协作策略；本机进程期配对、Run 自有的有界写入集合、
严格 schema-5 便携式 Research Record 与研究者评价，已经取代旧的 Skill 包、常驻
权限和子变更请求 owner。Analyze Record 可携带推荐文献；Zotero 本地只读上下文与
可选的第一方 Zotero MCP 传输继续可用。

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

运行打包构建需要 macOS 26 或更高版本。测试者不需要 Xcode。

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

计划中的首个外部版本是 `v0.1.0-beta.1`：在同一 GitHub release 页面发布采用
`GPL-3.0-or-later` 的准确标签源码、可选的注明架构的 ad-hoc 签名应用 ZIP 和
SHA-256 校验值。应用包含版本匹配的 CLI helper，不单独发布 CLI 资产。

便利版应用没有 Developer ID 签名，也未经过公证。从可信的项目 release 下载并
核对校验值后：

1. 解压 ZIP，并把 **Scholium** 移到“应用程序”；
2. 尝试启动一次；
3. 打开**系统设置 → 隐私与安全性**，选择**仍要打开**；
4. 完成认证并确认**打开**。

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

在打包应用中，打开**设置 → 研究指导 → 来源与集成 → Scholium CLI**并选择
**安装**。Scholium 会把版本匹配的 helper 安装到 `~/.local/bin/scholium`，
验证安装，并提供 PATH 指引而不编辑 shell profile。

源码 checkout 的安装与检查方式：

```bash
Tools/Scripts/install-cli.sh
scholium version --format json
scholium doctor --format json
scholium help action
scholium action prepare --help
```

CLI 与应用共享脉络、搜索、链接和图路径、工作区目录与关注、准确读取、Discussion
回复、可恢复 Actions、推荐文献和带修订检查的笔记操作。修改已有笔记时必须提供
`scholium read --format json` 返回的当前 SHA-256。

`scholium agent mcp serve` 通过 stdio 与私有同用户应用桥，为外部 Agent 提供
协作式运行中笔记变更请求；它既不启动 Scholium，也不授予写权限。准确生命周期见
随应用提供的 [CLI 合同](ScholiumCore/Resources/Skills/Scholium%20System%20Skills/scholium-research-integration/references/cli-contract.md)，
可选 Zotero 传输见 [Zotero MCP](Docs/ZOTERO_MCP.md)。

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
Docs/Status/              可达行为、债务、迁移、证据与开放验收
Docs/CSS_SNIPPETS.md       高级文档样式自定义合同
Docs/ZOTERO_MCP.md         可选的第一方 Zotero 传输指南
Tools/Scripts/             构建、验证、QA、性能与发布工具
```
