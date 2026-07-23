# Scholium

[English](README.md) | [简体中文](README.zh-Hans.md)

> 一间安静、本地优先的哲学写作室。

哲学很少以完整论证的形态突然降临。它生长在专注的阅读之中：一个从文本里
辨认出的区分，一项动摇熟悉立场的反驳，以及一份反复修改、直到足以独立成立的
回应。Scholium 是一款围绕这种缓慢而真实的研究过程构建的原生 macOS 研究工作台。
研究文档——
而不是仪表盘、任务板或聊天记录——始终位于中心。一个研究领域在
**脉络（Triptych）**中逐渐成形：**分析**保存对来源的研究，**议题**汇集
概念与争论，**写作**则承载研究者自己的论证。

*Scholium* 原指写在文本旁边的注疏。这款应用延续了这种精神：帮助研究者
与来源共同思考，却不取代研究者的作者身份或判断。Markdown 始终是研究者所选
文件夹中普通、可检查的文本；阅读、写作、搜索、关联、评审与恢复这些基本实践
都不依赖 agent。当研究者邀请外部 agent 参与时，Scholium 会为其工作提供明确的
目标与材料、修订检查、来源记录和恢复点，使协助保持有边界、可审查、可恢复。

Scholium 写给那些希望“让软件安静，让思想响亮”的人：专注地阅读与写作，
永不冒充证据的关联，以及记得一个论证如何改变的研究记录。它仍在被认真塑造。
如果您珍视哲学技艺、持久的纯文本档案，以及只协助您而不替您作判断的工具，
我们希望您会喜欢这里。

Scholium 也将成为一个由研究者治理 Agent 参与方法的地方。它安静地保存可以
验证的操作事实，邀请 Agent 报告有边界的学术结果，并且只在研究者主动表达时
记录研究者的判断。它既不要求一份完整的研究心理档案，也不自行编造这样的档案。
方法 Skills 可以被检查、直接编辑、替换或停用；准确来源、权限、来源记录、冲突
与恢复仍由 Scholium 的受保护机制负责。

## 文档

请使用足以回答问题的最小权威集合：

1. [Scholium 规格](Docs/SCHOLIUM_SPEC.md)：产品行为、界面设计、
   Scholarly Editorialism、辅助功能、发布要求和现行决策的唯一目标权威。
2. [实现架构](Docs/IMPLEMENTATION_ARCHITECTURE.md)：模块、运行时、状态所有权
   以及 CodeMirror/WKWebView 边界的从属结构合同。
3. [实现状态](Docs/IMPLEMENTATION_STATUS.md)：当前可达行为、证据、迁移债务与
   尚未完成的验收。
4. 本 README、实际构建调用点、可执行测试和脚本：设置方法与当前可达性的证据。

目标规则不等于实现声明。实际构建调用点、可执行测试与脚本仍是判断当前行为是否
可达的最终证据。

其他操作参考包括 [CSS 片段](Docs/CSS_SNIPPETS.md)、
[第一方 Zotero MCP 传输](Docs/ZOTERO_MCP.md)，以及内置的
[产品技能包](ScholiumCore/Resources/Skills/README.md)。
[Beta 性能基准](Docs/PERFORMANCE_BENCHMARK.md)区分内部回归微基准、
仅场景运行和尚未执行的打包应用 G7 门禁，并定义 RDF-1 及其失败关闭运行器。

## 当前实现

当前构建是一个由编译器强制边界的模块化单体：不可变值与用例协议位于
`ScholiumContracts`，内部 I/O 位于 `ScholiumCore`，macOS 应用与 CLI 共享
一个无界面的 `ScholiumApplication` 层。Core 不是公共产品，两个交付目标都
不能导入它。当前可达行为包括多脉络注册与窗口路由、脉络控制、安全的笔记生命
周期、Comment、当前由 Function 支撑的 Discussion、评析、机器本地的写入前恢复、
完整脉络恢复点、带修订检查的 CLI 直接写入、研究库范围的属性、未分类导入、统一
搜索、受保护的 CSS 片段、仅限 localhost 的 Zotero 读取，以及供外部 Agent
选择使用的第一方 Zotero MCP 服务。Canvas 已从产品中移除。“写作”文件夹仍是
研究者自行管理的普通文件夹；
Scholium 不注册或管理项目。代码所有权请参阅
[实现架构](Docs/IMPLEMENTATION_ARCHITECTURE.md)，精确证据与剩余缺口请参阅
[实现状态](Docs/IMPLEMENTATION_STATUS.md)。

D-106 已经把研究者治理的 Actions、可直接编辑的 Working Method Skills、分类的
Skills 设置、standing permissions、统一 Discussion 和可移植的双栏 Research
Record 纳入目标规范；它们仍属于迁移工作，不能因为规范已经采用就被描述为当前
可达功能。

## 环境要求

运行打包构建需要 macOS 26 或更高版本。测试者不需要 Xcode。

构建 Scholium 需要完整的 Xcode 安装，以及 `Package.swift` 要求的编译器与
SDK。仓库解析器会依次采用明确且有效的 `DEVELOPER_DIR`、完整的
`xcode-select` 选择，或常规位置中的 Beta/正式版 Xcode。只有重新构建
TypeScript 编辑器 bundle 时才需要 Node.js。

## 构建与测试

请从仓库根目录运行开发命令。

运行完整仓库验证：

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
```

Debug 启动器会在被忽略的 `.build/debug-app/Scholium-Debug.app` 中组装应用，
并通过 LaunchServices 打开。GUI 开发应使用这一入口，让场景启动、恢复、激活和
原生窗口行为运行在真实 app bundle 中；`swift run ScholiumApp` 不适合作为
macOS GUI 宿主。

在隔离窗口 QA 中，可以只读获取最前方 QA 窗口的准确 frame，而不改变窗口：

```bash
./Tools/Scripts/inspect-window-size.sh
```

第一次运行可能需要授予终端辅助功能权限。该探针只读，默认检查
`com.scholium.qa` bundle。

所有 SwiftPM 构建产物、依赖 checkout、编译器索引和测试产物都位于被忽略的
仓库 `.build/` 目录下。这样做是安全的，因为 checkout 本身位于桌面、文稿、
CloudStorage 和其他 File Provider 管理位置之外。不要把构建缓存或索引重定向到
`/tmp`。

### 开发存储

如需检查、打开或清理 Scholium 的开发存储，请在 Finder 中双击
[`Manage Scholium Development Storage.command`](Manage%20Scholium%20Development%20Storage.command)。
原生菜单提供以下操作：

- **显示存储报告**：报告当前 `.build`、过时开发产物和打包构建的大小与准确位置。
- **打开**：在 Finder 中显示 `.build`、临时目录、Xcode DerivedData 或
  `~/Applications/Scholium Builds`。
- **删除过时产物**：移除过时的 Scholium 临时文件、DerivedData、QA 应用，
  以及旧外部构建布局留下的缓存；保留当前仓库的 `.build`。
- **删除所有可重建产物**：移除同一批过时文件以及当前 `.build`。下一次构建会
  按需重新下载依赖、编译并建立索引。

当 Swift、Xcode 或 Scholium 正在运行时，清理器会拒绝执行。删除许可列表只包含
已识别的 Scholium 开发路径；它不会移除源文件、应用状态、打包构建、脉络文件或
便携式 `.scholium/` 数据。

命令行提供相同操作：

```bash
./Tools/Scripts/manage-development-storage.sh report
./Tools/Scripts/manage-development-storage.sh clean-stale
./Tools/Scripts/manage-development-storage.sh clean-all
```

两个清理命令默认都是 dry run：只打印每个候选项和可回收空间，不会删除文件。
请先检查列表，再添加 `--delete`：

```bash
./Tools/Scripts/manage-development-storage.sh clean-stale --delete
./Tools/Scripts/manage-development-storage.sh clean-all --delete
```

可选的外部 agent Zotero 传输由单独构建的 `scholium` CLI 提供。支持的源码安装
路径、agent 配置和受保护的导入合同请参阅 [Zotero MCP](Docs/ZOTERO_MCP.md)。

当 `WebEditor/` 发生变化时：

```bash
./Tools/Scripts/build-editor.sh
./Tools/Scripts/verify-editor-bundle.sh
```

这些脚本会把锁定的 npm 依赖安装到临时存储，而不是同步工作树。仓库内的
`WebEditor/node_modules` 会被拒绝；请将其移除后重新运行仓库脚本。

确定性界面开发只能使用隔离的 QA 应用和一次性 fixture 副本：

```bash
./Tools/Scripts/build-qa-app.sh
./Tools/Scripts/run-ui-tests.sh
```

这些命令使用 bundle identifier 为 `com.scholium.qa` 的
`.build/qa-runtime/Scholium-QA.app`，并复制 `SCHOLIUM_TEST_VAULTS` 所指目录作为一次性
fixture（默认 `~/Desktop/TestVaults`）。它们不会打包发布版本，也不会打开
真实研究库。

采用未来构建之前，请在一个一次性脉络与一个隔离应用 home 上比较旧 QA 应用和
候选应用：

```bash
./Tools/Scripts/verify-qa-upgrade-safety.sh \
  --baseline /tmp/Scholium-Previous-QA.app \
  --candidate .build/qa-runtime/Scholium-QA.app \
  --output /tmp/Scholium-Upgrade-Evidence
```

该门禁会生成 BOM、CRLF、LF、无末尾换行、注释、未知及多行 YAML、Unicode/CJK
和空笔记案例。它会在启动前及每个应用运行后记录路径、字节大小、SHA-256、权限
和修改时间；只要“分析”“议题”或“写作”中的任何文件发生变化就会失败。
便携式 `.scholium/` 的变化同样会失败，除非相应路径已在
`Tools/Fixtures/qa-upgrade-portable-allowlist.txt` 中明确审查。日志、manifest
和两个 `.xcresult` bundle 会保留在指定的证据目录。相同 app hash 下通过只能
证明测试 harness 有效；版本间证据需要不同的基线和候选构建。

打包、签名、公证和分发属于独立的发布工作，不属于日常验证。

## 源码优先的 Beta 分发

计划中的首个外部构建是 `0.1.0-beta.1`：在同一 GitHub release 页面发布采用
`GPL-3.0-or-later` 的公开标签源码，以及可选的 ad-hoc 签名 Scholium app ZIP
和 SHA-256 校验值。公开 Beta 不单独提供 CLI 资产；应用内包含版本匹配的
Scholium CLI helper，研究者可从“研究指导”中明确选择安装到本机。

便利版应用没有 Developer ID 签名，也未经过公证。测试者不需要 Xcode，但首次
尝试启动后必须前往 **系统设置 → 隐私与安全性 → 仍要打开**，批准可信下载。
Developer ID 和公证仍是可选的未来分发改进。准确门禁与安装说明请参阅
[Beta 发布指南](Docs/BETA_RELEASE.md)。

## 脉络设置

首次启动会要求研究者分别选择 **分析**、**议题**和**写作**文件夹。由于便携式
`.scholium/` 数据位于“写作”旁边，macOS 还会一次性请求访问“写作”所在的
文件夹；这是访问边界，不是第四个研究库。建议将三者置于同一父目录，但不作强制
要求。之后可通过 Scholium 设置中的**管理脉络…**添加或更改完整脉络。

使用**文件 → 新建脉络…**配置另一个完整研究领域；使用**文件 → 打开脉络**在
独立窗口中打开已注册脉络；使用**文件 → 新建窗口**为当前脉络打开另一个独立
窗口。每个脉络始终只包含分析、议题和写作；“写作”的子文件夹不是应用管理的
项目。

每个脉络都需要独立的“写作”父目录，因为便携式 `.scholium/` 控制目录位于
“写作”旁边。若两个脉络的“写作”文件夹会共享同一控制目录，Scholium 将拒绝
配置。

研究者界面与 CLI 只使用当前的三研究库脉络合同。预发布版本的角色别名与位置式
搜索语法不再接受。

## Scholium CLI

在打包应用中，打开**设置 → 研究指导 → 技能 → 高级 → Scholium CLI**并选择
**安装**。Scholium 会把版本匹配的 helper 安装到 `~/.local/bin/scholium`，
报告当前 PATH 能否发现该目录，并提供 PATH 设置命令，而不编辑 shell 文件。

随应用提供的 [Scholium CLI 合同](ScholiumCore/Resources/Skills/Scholium%20System%20Skills/scholium-research-integration/references/cli-contract.md)
定义准确的 agent 生命周期与失败行为。[Zotero MCP 指南](Docs/ZOTERO_MCP.md)
说明可选的第一方 Zotero 传输。本 README 仍是面向人的简明安装入口。

从源码 checkout 本地构建并安装当前 CLI：

```bash
chmod +x Tools/Scripts/install-cli.sh
Tools/Scripts/install-cli.sh
```

请直接检查可用命令，不要依赖可能过时的示例：

```bash
scholium version --format json
scholium doctor --format json
scholium help function
scholium function prepare --help
```

CLI 支持检查已注册研究库、共享搜索、链接、图路径、规范工作区目录和关注输出、
精确读取、对话回复、可恢复的研究功能、推荐文献，以及带修订检查的直接笔记操作。
JSON Function 结果包含类型化的后续动作；恢复时使用 `function show`，变更过的
“发展”或“修订”运行完成后使用 `function prepare-fidelity`。修改现有笔记必须
提供 `scholium read --format json` 返回的当前 SHA-256。

隔离测试 CLI：

```bash
SCHOLIUM_HOME=/tmp/scholium-cli-check swift run \
  scholium --help
```

## 存储与安全

权威研究内容始终保留在所选 Markdown 研究库中。机器本地的评审、对话、恢复点、
索引、已存搜索及其他设备状态位于：

```text
~/Library/Application Support/Scholium/
```

“写作”旁的小型便携式 `.scholium/` 目录只保存：脉络 manifest、脉络本地设置、
属性配置、评析配置与关联、身份映射、未分类 Markdown，以及研究者在
`.scholium/skills/<skill-id>/` 下直接管理的技能包。每个包都包含 `SKILL.md`，
并可包含受限的单层 `references/` 或 `templates/` 资源。这里不保存项目注册表、
bookmark、绝对路径、密码、索引、窗口会话或私人评审历史。

每次应用对权威内容的写入都必须验证路径包含关系与预期修订，保留先前字节，验证
frontmatter，执行原子写入，并在不丢弃编辑器缓冲区的前提下报告冲突。派生的搜索、
图、渲染和诊断状态都可丢弃，绝不能反向重建可写源文本。

开发测试不得使用真实研究库。请将 `SCHOLIUM_TEST_VAULTS` 指向非私人 fixture
根目录；无需 UI harness 的测试则使用生成的一次性研究库。

## 许可证

除非另有说明，Scholium 的原创源代码采用
[GNU General Public License version 3 或更高版本](LICENSE)
（`GPL-3.0-or-later`）。第三方组件仍采用各自的许可证；详见
[第三方声明](THIRD_PARTY_NOTICES.md)。

## 仓库结构

```text
ScholiumContracts/         不可变值、协议、源文本语义、错误
ScholiumCore/              内部仓库、存储、索引、watcher、I/O
ScholiumApplication/       无界面运行时与能力实现
Scholium/                  macOS 应用与面向人的交互
ScholiumCLI/               CLI 解析、格式化与 Contracts handler
WebEditor/                 TypeScript 与 CodeMirror 源码
Tests/ScholiumContractsTests/
                           合同与边界测试
Tests/ScholiumCoreTests/   Core 单元与集成测试
Tests/ScholiumApplicationTests/
                           运行时、操作、事件与交付一致性测试
Tests/ScholiumAppTests/    窗口组合与界面架构测试
UITests/                   隔离的 macOS UI 测试
Docs/SCHOLIUM_SPEC.md      产品、界面与发布目标权威
Docs/IMPLEMENTATION_STATUS.md
                           当前证据与迁移账本
Docs/IMPLEMENTATION_ARCHITECTURE.md
                           模块、运行时、状态与编辑器所有权
Docs/CSS_SNIPPETS.md       支持的文档样式自定义合同
ScholiumCore/Resources/Skills/README.md
                           内置产品技能架构与证据边界
Docs/BETA_RELEASE.md       源码优先的 Beta 政策与发布门禁
Tools/Scripts/             构建、验证、QA 与发布脚本
Docs/PERFORMANCE_BENCHMARK.md
                           RDF-1 fixture 与打包应用 G7 协议
```
