# Scholium-lite 需求探索记录

## 文档地位

- 日期：2026-09-01 至 2026-09-02
- 状态：已迁回旧 Scholium 的非规范需求探索记录
- 本文只记录本轮对话中已经表达的实际需要、明确决定、现场观察与待探索问题。
- 本文不是产品规范、技术方案或架构批准。它是重新审查并修订旧 Scholium 的输入，不能在未经逐项决定和规范修订的情况下自动覆盖旧仓库的正式产品规范。
- `/Users/jacuqeas73/Desktop/Research/Antelucana/` 是当前整理结果和研究活动证据；`/Users/jacuqeas73/Desktop/Research/Philosophical Reports/` 是整理前状态。二者都不是新产品的需求或架构权威。
- 在后续需求探索中，已经由研究者和 Agent 明确达成一致的实质结论可以自主更新到本文，不必每次另行取得写入指令。该授权只适用于这份探索记录，不扩展到产品规范、代码或研究笔记。

2026-09-02，研究者决定停止把 `/Users/jacuqeas73/Developer/Scholium-lite` 作为独立产品实现方向，将本记录迁回 `/Users/jacuqeas73/Developer/Scholium`，继续完善旧 Scholium。旧 Scholium 因而重新成为唯一继续开发的产品仓库；Scholium-lite 阶段已经确认的真实需要和否决结论用于约束后续简化与修订，但不把旧实现、旧规范或旧概念不经审查地重新批准。

同日，研究者进一步决定继续保持现有 Swift 原生 macOS App，暂不追求跨平台，也不把本地 Web/Node.js 作为当前产品迁移目标。这里的“兼容”只表示：当前已经可用且不与新需要冲突的部分不改，不为追求概念整齐而重写。它不表示兼容旧产品合同、旧数据格式或旧行为；Scholium 尚未投入实际使用，没有需要长期支持的用户数据和既有工作流。任何部分一旦确认需要改变，就应在明确新合同后 clean cutover：同步替换所有仓库内调用、测试和规范，删除被取代的实现、适配器、回退与双轨路径，不留下历史债务。

## 一、实际研究活动

当前研究过程大致如下：

1. 在 Zotero 中阅读文献并摘录。
2. 在主题笔记中组织和消化材料。
3. 为已经分析的论文保存专门的论文分析。
4. 根据主题笔记和论文发展自己的作品。
5. 与 Agent 讨论论文、组织主题笔记、批评或润色作品，并继续发展想法。

当前 Antelucana 使用三个内容区域表达这一过程：

- `Topics`：主题笔记；
- `Analyses`：论文分析；
- `Works`：研究者自己的论证与作品。

研究者已经进一步明确：`Analyses`、`Topics` 和 `Works` 必须成为新产品中三种不同的研究库，而不只是当前文件夹的偶然划分。Scholium 需要知道一篇笔记属于哪个库，并据此采用不同的元数据、检索价值和 Agent 对待方式。当前已经能确定的研究权威差异是：

- `Analyses` 主要用于重构和核验具体论文的概念、论证与作者立场，不能自动代表研究者本人的观点；
- `Topics` 主要用于围绕哲学问题组织、比较和消化材料，也不能仅凭其中的评价性表述就推断研究者立场；
- `Works` 主要承载研究者自己的论证、判断和作品，是理解研究者立场的主要文本来源，Agent 修改时应保留其意图，除非研究者明确要求发展替代论证。

三类库都仍以 Markdown 正文为权威，也都可以在研究者明确指令下被修改。不同对待不表示固定的真值等级或全局搜索排名：一篇 `Analysis`、`Topic` 或 `Work` 的检索价值取决于当前问题和它在论证中的角色。每类库究竟需要哪些元数据、默认检索范围、结果排序、核验要求和修改提示，仍需依据真实任务分别确定。

哲学研究整体没有最终完成状态。一次边界明确的研究活动可以产生一篇笔记和一条简要的学术活动记录，而知识库继续增长和修正。

## 二、核心问题

研究材料数量很多，不同笔记带有不同的结构化字段，Obsidian 难以统一管理。

进一步探索后，研究者明确：当前最主要、最难以由现成 Markdown 编辑器替代的问题，是大型哲学知识库的检索。自定义编辑器、Metadata 右栏、Review、Settle 和带长注释双链仍可能改善工作过程，但它们不是 Scholium-lite 首先需要证明的独特价值。第一优先级是让 Agent 能够在大量、多语言、概念交叠且论证关系复杂的哲学正文中找到真正相关的材料，并区分材料的来源层级、主张内容和论证角色。

因此，现成 Markdown 编辑器可以承担人工阅读、写作与普通文件管理；Scholium-lite 是否需要自有 Web 界面，应取决于检索闭环运行后仍然存在的具体界面缺口，不能为了已经可以由现成软件完成的编辑功能提前开发产品外壳。

研究者随后实际体验了 Zettlr。尽管它在功能上覆盖跨平台 Markdown 编辑、文件夹工作区、Wiki Link、Tags 和 Zotero 引用等基础能力，但其界面观感和交互细节明显不符合研究者的产品标准，因此已经否决“直接使用 Zettlr 作为 Scholium-lite 人工界面”的方向。实际体验推翻了仅根据功能清单作出的可替代性判断。

这不改变大型哲学知识库检索是第一核心问题，但说明“检索能力可以完全寄居在任意现成编辑器中”并不成立。Scholium-lite 仍需要自己的高品质界面；界面应围绕检索后的阅读、正文编辑和研究上下文服务，并继续采用已经批准的旧 Scholium WebEditor 选择性复用方向。Zettlr 不作为第一版界面基础，也不因其开源而自动成为 fork 对象。

Agent 在软件之外工作时，也很难持续掌握知识库的最新状态。索引需要不断保持更新，否则 Agent 不容易有效搜索知识库，并可能需要研究者反复提醒它当前状态。

结构化字段主要服务于 Agent 的检索和理解；研究者主要阅读哲学正文。因此：

- 正文是研究内容的权威来源；
- 结构化字段和索引是辅助 Agent 的派生信息；
- Agent 可以利用派生信息定位材料，但形成判断前应阅读正文；
- 正文与字段或索引冲突时，以正文为准，派生信息应被视为可能过期；
- 现有字段只有在确实帮助 Agent 检索或理解时，才可能在新产品中证明其必要性。

Agent 不需要实时感知文件发生变化，但每次开始新的研究行动时，必须以知识库当前的文件状态为准。由此确认：

- 无论笔记是在应用内还是由其他编辑器新增、修改、移动或删除，下一次研究行动都不能依赖研究者口头提醒来刷新状态；
- 索引、反向链接和带注释双链视图等派生信息，应在行动开始前完成更新或核对；
- 这种机械更新不能成为 Agent 的额外哲学任务，也不能顺带修改研究正文；
- 更新派生信息本身不构成需要写入学术活动记录的实质研究进展；
- 如果无法确认当前状态，Agent 应明确报告不确定性，不能悄悄使用可能过期的索引；
- 不要求文件一有变化就实时推送给已经打开的 Agent 对话，也不因此批准持续监听等具体实现方式。

索引还应包含哪些信息，仍未决定。

## 三、Agent 的研究角色

Agent 应能帮助研究者：

- 分析和讨论论文；
- 组织和消化主题笔记；
- 批评或润色作品；
- 发展研究者的想法；
- 在后续研究中找回过去的讨论，并结合知识库的新内容重新组织和回答问题。

这里的“学习和成长”不是已经确定的模型训练方案。当前确认的最低含义是：Agent 不应在每次会话中从零开始，而应能找回相关讨论，检索后来新增或修改的材料，并据此重新理解问题。过去的讨论是可以重审的研究历史，不是不可修改的结论。

### Agent 与订阅边界

第一版不能要求用户提供按量计费的模型 API Key。实际用户已经订阅 Codex 或 Claude，并希望 Scholium-lite 复用这些已有订阅，而不是要求他们另行开通和支付 API 账户。

因此，先前提出的“由 Scholium-lite 直接调用模型 API并自行实现最小 Agent 循环”已经被明确否决。可行方向应建立在用户本机已经登录的 Codex 或 Claude Agent 能力之上：Scholium-lite 提供专用于哲学研究的知识库、交互和权威边界，而不是重新实现底层通用 Agent。

官方资料确认当前存在相应的程序化入口：Codex App Server 用于把 Codex 的认证、对话、审批和流式 Agent 事件嵌入其他产品，并支持 ChatGPT 订阅登录；Claude Code 可以通过 Agent SDK 或非交互命令提供结构化、流式的 Agent 会话，并可使用 Claude 订阅认证。这里记录的是可行性证据，不批准具体适配层实现，也不假定两个入口具有完全相同的协议或能力。

用户应直接向 Codex 或 Claude 完成登录。Scholium-lite 不应要求用户把服务商凭据复制到研究配置或自行保管这些凭据。第一版需要让 Codex 和 Claude 用户都能使用 Scholium 的研究能力；两种接入的实现顺序以及需要达到何种功能一致性，仍待决定。

### 软件间通信与 Handoff

Scholium-lite 不内嵌 Agent 对话。研究者继续在自己已经使用的 Codex 或 Claude 客户端中与 Agent 讨论；Scholium Web 专注于知识库阅读、关系展示、修改审阅和研究状态。

已经批准以本地 MCP 作为主要的软件间通信通道：

- Scholium 本地服务向 Codex 和 Claude 提供同一组研究工具与当前知识库状态；
- Agent 按照用户指令以及 MCP 提供的服务器级说明调用这些工具，完成行动开始时的状态核对、检索正文、读取关系与研究记录，以及实质进展记录；
- Codex 或 Claude 继续负责模型、订阅、对话历史和通用 Agent 循环；
- 采用 MCP 只证明一个固定的 Scholium 通信接口有必要，不批准插件市场或通用插件体系。

MCP 除了暴露工具，还应向 Agent 提供简洁的服务器级说明，用于表达贯穿各工具的研究边界和工作方式，例如：正文是权威来源，搜索结果只是候选材料，Agent 应从概念上扩展多语言查询、进行多轮检索、阅读相关正文并沿链接核验，不能从关键词重合、相似度或主流程度推断哲学关系或正确性。

MCP 说明承担的是 Scholium 工具的共同使用契约，不等同于完整的研究 Skill。第一版不要求 Scholium 捆绑或强制安装统一 Skill；研究者及其朋友可以在自己的 Codex 或 Claude 环境中安装、编写和选择个人 Skill，以形成不同的阅读、分析和写作方法。个人 Skill 负责方法偏好，MCP 负责知识库能力、当前文件状态和共同权威边界。

写入不需要由 Scholium MCP 发放许可、通行证或执行严格的授权校验。研究者在 Agent 对话中给出的明确写入指令就是行动依据；Agent 按照用户指令、MCP 说明以及研究者自行选择的 Skill 调用 Scholium 提供的普通笔记操作。产品不应为了重复验证对话中已经明确的指令而增加额外操作。

Scholium MCP 的核心笔记能力包括：

- 从当前正文和派生索引中搜索笔记；
- 读取笔记正文、来源以及相关双链注释；
- 在指定路径创建普通 Markdown 笔记；
- 写入指定 Markdown 笔记；
- 删除指定笔记。

这些操作只是 Agent 与知识库之间统一的执行通道，不是额外审批层。创建、写入或删除后，Scholium 应机械更新索引和反向视图，向 Web 界面报告受影响文件，保留 Review 所需的变化，并在构成实质研究进展时更新 Record。Agent 绕过 Scholium 产生的外部文件变化仍应在下一次行动开始时被发现，但通过 Scholium MCP 操作是主要路径。

删除必须是可恢复操作：在 macOS 上移入废纸篓，在 Windows 上移入回收站，不执行永久删除。是否需要由 Scholium 提供独立的恢复界面仍未决定。

从 Scholium Web 发起讨论时，使用轻量 Handoff 补充 MCP：

1. Scholium 保存当前笔记、选区、问题和必要语境，并生成短标识；
2. 软件复制一条包含该标识的简短唤醒指令；
3. 研究者把指令粘贴到 Codex 或 Claude；
4. Agent 通过 MCP 读取完整 Handoff，不需要把长篇正文放入剪贴板。

如果 MCP 不可用，可以退化为复制完整且自包含的 Handoff。第一版不依赖某个 Agent 客户端独有的主动推送能力。

Scholium 不能假定自己可以读取 Codex 或 Claude 的完整聊天记录。需要保留的实质研究进展，应由 Agent 按 MCP 说明和用户所选 Skill 调用活动记录工具写回，或由研究者主动 Handoff；这不能扩大为保存全部对话。

## 四、具体检索与讨论案例

示例问题：

> 情绪能否成为理由的奠基？有哪些哲学家支持过类似论点，或者有哪些哲学家明确批评过这种论点？

期望的研究过程是：

1. Agent 在论文分析和主题笔记的正文中寻找相关材料。
2. Agent 总结材料并在对话中回答研究者。
3. 检索不能只依赖关键词，而应判断材料是否真的支持、接近或批评目标论点。
4. “情绪揭示价值”“情绪激发动机”或“情绪本身有理由”等邻近主张，不能未经论证就归为“情绪奠基理由”。
5. Agent 应区分直接支持、相近观点、明确批评以及 Agent 自己的重构，并说明证据不足之处。

日常检索和初步讨论可以直接依据论文分析笔记，不必每次重新打开 Zotero 原文。Agent 应如实表明回答所依据的材料层级，不能把“依据分析笔记”表述为“本次已经核验原文”。

当主题笔记与论文分析对人物立场或论证内容发生实质冲突时，Agent 应主动回到原文核验后再回答。若原文仍不足以解决冲突，应明确保留未决状态。

由此确认的需要是能够定位和核验原始文献；是否必须通过 Zotero 集成实现，尚未决定。

## 五、讨论、写入与研究权威

默认顺序是先检索和讨论，再由研究者决定是否写入。

- 讨论结果不能自动写入 `Topics`、`Analyses` 或 `Works`。
- 是否写入、写入哪篇笔记以及何时写入，都必须听从研究者的明确指令。
- 讨论已经比较成熟，不等于获得了写入授权。
- 未经明确授权，Agent 不应顺带修改可能相关的研究笔记。

简要学术活动记录是一个例外：即使一次活动只有检索和讨论、没有修改研究笔记，只要产生了实质研究进展，也可以自动留下记录。记录写入后，最好明确告知研究者已经创建或更新，并说明位置。

活动记录需要同时服务于两个目的：

1. 让研究者回顾研究进展；
2. 让 Agent 在后续会话中找回讨论，并在新材料基础上继续研究。

更根本的目的，是让研究者和 Agent 都能从讨论中学习并成长。活动记录不能只是操作流水账；它需要保留足以理解研究认识如何变化的内容。

活动记录不需要保存完整对话。凝练总结应足以恢复：当时研究了什么、依据了哪些材料、形成或修正了什么认识、哪些问题仍未解决、修改了哪些文件，以及下次可以从哪里继续。

记录应围绕一个持续的研究问题组织，而不是按每次会话制造新文件。同一个问题可以持续更新一条记录，并在其中按步骤追加多次研究进展。

为避免记录本身变成新的信息负担，只有以下实质进展才触发更新：

- 形成新的研究判断；
- 对已有判断作出重要修正；
- 作出影响后续工作的研究决定；
- 实际修改研究文件。

普通搜索、重复讨论、确认性回复以及没有改变认识的过程不进入活动记录。Record 是研究记忆，不是完整聊天存档或操作日志。其存放位置、与研究问题的关联方式以及后续检索机制仍待探索。

### 真实写入案例：Buck-passing Account

用于探索写入流程的现有主题笔记是：

`/Users/jacuqeas73/Desktop/Research/Antelucana/Topics/4. Fitting Attitude Analysis/3. Reasons-First Approaches/Buck-passing Account.md`

研究者使用这类笔记，是为了更清楚地整理笔记结构、核对哲学内容，并了解具体论文的论证与立场。对这类笔记的 Agent 修改应满足以下需要：

- 在达到合格哲学写作标准的基础上补充知识，不要求模仿研究者的个人措辞或句式；
- 根据论文分析准确判断论文的具体立场；
- 将多篇论文组织为连贯的文献综述，而不是简单堆叠摘要；
- 从研究者的立场出发评价文献，不能把 Agent 自己的立场冒充为研究者的立场。

Agent 可以在获得明确写入授权后直接改写，而不必只提供修改建议。相关文件没有预先设定的绝对禁改范围，但“允许修改”不等于每次都应自动扩散修改。所有实际修改都必须向研究者汇报，并记录在本次活动记录中。

### 合格哲学写作与研究者立场

用于识别合格哲学写作的现有主题笔记是：

`/Users/jacuqeas73/Desktop/Research/Antelucana/Topics/1. Reasons/1. The Nature of Reasons/Zetetic Reasons.md`

该案例显示的质量标准包括：限定概念和问题范围；区分相邻但不同的理由类型和评价对象；准确归属作者立场；分开呈现论点、反例、回应与理论代价；在文献综述基础上作出有理由的评价；形成明确但可修正的工作结论。

这些是哲学写作的质量标准，不是固定章节模板。Agent 可以重组结构和改善表达；产品不需要模仿研究者个人文风。

Agent 对研究者哲学立场的理解主要来自：

- 研究者与 Agent 的明确讨论，以及由此形成的凝练活动记录；
- `Works` 正文中已经形成的论证和判断。

`Topics` 和 `Analyses` 主要记录研究材料，不能仅凭其中的评价性措辞就断定那是研究者的立场。研究者的观点可以随研究继续发展，不应被固化为一个永久不变的用户立场档案。

较早的 `Works` 与近期讨论发生冲突时，Agent 不得按时间顺序机械决定立场。它应指出冲突，分别重构两种立场及理由，评估哪一种在哲学上更可行，并与研究者讨论。Agent 必须区分自己的评价与研究者的既有立场；是否修正立场及写入文件，最终由研究者决定。

### 修改展示、Review 与 Settle

研究者通过 Diff 判断 Agent 的改写，但 Diff 不应以补丁符号、行号或其他技术细节为中心。它应让研究者看清笔记结构、哲学主张、文献归属、评价和措辞发生了什么变化。

应用应汇报所有被修改的文件。研究者查看修改展示后，系统可以自动把该次修改记为 `reviewed`。

`Review` 与 `Settle` 是两个独立维度：

- `Review` 针对某次 Agent 修改，只表示研究者已经看过修改；
- `Review` 是轻量记录，不表示接受、正确、成熟或定稿；
- `Settle` 针对整篇笔记，表示研究者认为它当前已达到比较成熟的状态；
- `Settle` 不表示哲学立场最终确定，笔记可以随着后续变化重新成为 `unsettled`；
- 一篇笔记可以已经 `reviewed`，但仍然是 `unsettled`。

`settled/unsettled` 只能由研究者手动决定。Agent 修改一篇 settled 笔记后，不得自动改变其状态；它可以提醒研究者重新判断成熟度。

## 六、任务边界与负担控制

以前的使用过程给 Agent 安排了过多同时发生的工作，包括：

- 更新可能相关的文档；
- 更新索引；
- 更新结构化字段。

这会使一次研究活动扩张为过大的维护任务。当前确认的约束是：

- 一次 Agent 行动应有清楚边界；
- 新增一篇分析或修改一篇笔记，不应自动触发对所有相关研究文档的修改；
- “尝试发现新材料可能改变哪些旧讨论”可以存在，但只在研究者主动调用时运行，不需要自动发现；
- 机械维护不应挤占 Agent 的主要哲学研究任务。

一个尚未批准的方向是：如果索引能够从正文或文件状态机械重建，就不必把逐项维护索引当作 Agent 的独立推理任务。是否采用这种方式，要在需求明确后再验证。

### 第一阶段实现目标

已经批准的第一个可运行闭环是：

1. 打开一个现有的 Markdown 知识库；
2. 在 Agent 开始行动前核对当前文件状态；
3. Agent 从最新正文中检索相关材料并与研究者讨论；
4. 只有收到明确写入指令后，才修改一篇指定笔记；
5. 用非技术化 Diff 展示这次修改在结构、哲学内容、归属、评价和措辞上的变化；
6. 对实质研究进展和实际修改留下凝练记录。

这个闭环是第一阶段的实现边界，不表示所有已经确认的需求必须在第一段代码中同时完成。`Review`、`Settle` 和带长注释双链可以围绕该闭环逐步加入，但仍是已经确认的产品需要，而不是因此被取消或降为未经批准的设想。

这个闭环本身不规定产品形态、编程语言、框架、索引技术或 Agent 接入方案；产品形态在后续讨论中另行决定如下。

### 已批准的产品形态

Scholium-lite 需要跨平台使用。它主要面向研究者本人及朋友组成的小范围用户，不以进入 Apple App Store 或遵循原生 macOS 应用的严格发布流程为目标。

已经批准采用“由终端命令启动的本地 Web 界面”作为产品形态：

1. 用户在终端运行一个命令；
2. 命令启动只在本机运行的服务；
3. 默认浏览器打开产品界面；
4. 本地服务直接处理研究者指定的 Markdown 知识库；
5. 浏览器负责阅读、关系、修改展示和研究状态等交互，不承担 Agent 对话界面；
6. 同一本地服务通过 MCP 与 Codex 或 Claude 客户端通信。

DeepSeek Harness 是这种启动和使用体验的参考案例。这里只借鉴“从终端启动本地 Web 服务并在浏览器使用”的产品形态，不因此采用或批准 DeepSeek Harness 的代码、插件架构、运行时、技术栈、功能范围或发布方式。

第一版需要支持 macOS 和 Windows。Linux 不属于第一版必须支持和验证的平台；这不排除以后增加支持。

第一版可以要求用户预先安装 Node.js，并通过一条 `npx` 命令启动本地服务和 Web 界面。这种小范围分发方式已经获得接受；第一版不需要同时提供 macOS 或 Windows 的独立安装包、应用商店发布流程或自动更新器。

具体 npm 包名、Node.js 支持版本、编程语言、Web 框架、本地服务、索引技术和 Agent 接入方案仍待决定。

以上跨平台本地 Web 产品形态在 2026-09-02 迁回旧 Scholium 后不再是当前实施方向。当前继续保持 Swift 原生 macOS App；跨平台与 Web 外壳作为以后可以重新评估的方向，不构成当前 canonical specification 的冲突。

### 已批准的编辑器复用方向

Scholium-lite 不从零开发 Markdown 编辑器，已经批准从旧 Scholium 的 `WebEditor` 中选择性复用代码。旧 `WebEditor` 是以 TypeScript 和 CodeMirror 6 实现的浏览器编辑器，已经包含 Markdown 原文精确保留、自定义语法扩展和相关测试，能够作为本地 Web 界面的编辑器基础。旧 Scholium 的相关代码完全由研究者拥有版权，因此不存在由旧仓库自身许可证造成的复用障碍；第三方依赖仍分别遵守其许可证。

这项批准只适用于经过审查后确实服务于新产品需要的编辑器代码，不批准整体迁移旧 `WebEditor`，也不使旧 Scholium 的 Swift/WKWebView 通信、产品架构、界面结构、功能范围或旧 Vector Link 语义成为新版本的默认设计。复用时应保留或改造原文精确保留、CodeMirror 基础、自定义 Markdown 解析框架和必要测试；浏览器通信入口、带长注释双链以及具体显示方式需要按照 Scholium-lite 已确认的需要重新组成。

Scholium-lite 的界面组件体系、布局和视觉风格尚未决定。应先根据真实的阅读、检索、编辑和修改审阅过程确定核心工作界面的信息关系，再选择 Web 框架及组件库，不能因为旧编辑器代码可复用就继承旧 Scholium 的设计。

### 已批准的主界面起点

Scholium-lite 采用文档中心型研究工作台作为主界面的设计起点：

- 中央区域以哲学正文为主，承担阅读与编辑；
- 左侧区域用于在 `Analyses`、`Topics`、`Works`、文件列表和搜索结果之间导航；
- 右侧区域按需显示当前正文的上下文，例如带注释双链、反向链接、修改审阅或笔记状态；
- Agent 对话继续留在 Codex 或 Claude，不进入 Scholium-lite 主界面；
- Diff 是正文的一种临时审阅状态，不长期占据独立区域；
- 搜索结果负责把研究者带到相关段落，但不能取代对完整正文的阅读。

这一布局来自已经确认的研究过程，不是对旧 Scholium Triptych 或其具体面板结构的继承。中央、左侧和右侧区域内部的具体组件与交互仍需分别探索。

视觉方向采用安静、正文优先的学术编辑风格：正文排版和中英文混排质量优先；控件保持克制；状态与元数据退居正文之外；主要通过留白、字重和细微层次组织界面，避免知识图谱、彩色标签、大量卡片以及开发工具或管理后台式的视觉噪音。具体字体、颜色、间距、图标和组件库尚未决定。

### 已批准的中央正文表面

正常阅读和编辑共用同一个 Live Preview 表面，不设置彼此割裂的默认阅读器与编辑器：

- 默认显示经过排版的哲学正文；
- 研究者点击正文即可直接编辑，不需要先进入单独的编辑模式；
- 当前编辑位置显示必要的 Markdown 标记，其他位置保持接近阅读效果；
- 原始 Markdown 正文始终是唯一权威内容，Live Preview 只是对同一正文的交互呈现；
- 提供可切换的完整 Markdown Source 视图，用于检查或精确处理源码，但它不是日常默认界面；
- Agent 修改后的 Review 临时改变中央正文区域的呈现，不另设一套长期并存的编辑器。

Live Preview 的具体渲染规则、Source 切换位置和保存时机仍待决定。

迁回旧 Scholium 后，研究者没有取消独立阅读模式。现有 Review、Edit、Source 三模式可以继续保留：Review 负责无编辑干扰的阅读，Edit 提供 Live Preview 式直接编辑，Source 提供完整 Markdown。探索阶段把阅读与编辑合成一个默认表面的设想不再要求替换现有模式。若以后仍需要表达“已经看过某次 Agent 修改”，应避免与阅读模式 Review 混为同一个状态或术语。

### 已批准的 Review 呈现方向

Review 仍以修改后的完整正文为主要阅读对象，不默认采用左右并排比较或面向程序员的红绿补丁：

- 在正文阅读流中克制地标记被修改的句子或段落；
- 研究者点击标记后，可以核对修改前后的准确措辞；
- 变化按“重组论证”“修正作者归属”“增加限定”“调整评价”等有哲学意义的自然单位组织，但不能用概括取代对具体词句的核对；
- 删除的内容在原位置附近折叠，并可按需展开；
- 可以依次跳转到上一处或下一处修改；
- Scholium 机械计算并显示准确的文本差异、涉及文件和修改位置，不自行判断一处修改在哲学上属于什么类型；
- 执行修改的 Agent 将本次修改的哲学意义、主要变化和必要说明写入相应的研究活动 Record；
- Review 中的变化概括是该 Record 相关部分的投影，不另行保存一份可能分叉的修改说明，并应明确其来自 Agent；
- 如果没有相应的 Record 说明，Review 只显示可以由文件版本确定的文本变化，不自动生成哲学概括；
- 研究者完成浏览后，该次修改可以自动记为 `reviewed`，但这不表示接受、正确或 `settled`。

第一版不因此增加逐项“接受修改”的审批流程，因为 Agent 的修改已经写入正文。是否需要撤销整次修改、恢复旧版本或只恢复局部内容，仍待另行决定。

某篇笔记的 Review 上下文同时提供与该笔记明确关联的 Record 历史，但不把“当前修改”和“历史”分成两个区块：

- 相关 Record 步骤按照记录时间从新到旧排列；
- 每项只显示 Record 名称、记录时间和一小段内容，并可表明该步骤是否实际修改了当前笔记；
- 最新一项尚未被研究者看过的关联记录获得轻量提示，不另设置顶的“待审修改”区域；
- 点击一项后，在中央区域打开完整 Record 并定位到相应步骤；如果该步骤修改了当前笔记，可以由此进入该笔记对应的准确文本变化；
- 时间线只收录明确关联该笔记的实质 Record 步骤，不能根据关键词或语义相似度猜测关联；
- 同一个持续更新的 Record 可以因多个实质步骤在时间线中出现多次；一个步骤明确涉及多篇笔记时，也可以出现在这些笔记各自的历史中；
- 列表内容始终是 Record 的投影，不复制保存另一份摘要；笔记移动或改名后，已有历史关联不应丢失。

Record 因此需要能够作为正式页面在中央区域阅读。Record 的具体存储格式以及是否允许研究者直接编辑，仍待决定。

迁回旧 Scholium 后，某篇笔记中投影完整 Record 历史和最新未读提示不属于近期需要。Record 本身仍需要大幅重新设计，但不要求先改变现有独立 Records 窗口或把 Record 历史加入 Document Review。

### 已批准的右侧上下文呈现

右侧上下文区域借鉴 Zotero 条目右栏的组织方式：使用一个可滚动的纵向区域，将不同内容组织为依次排列、可分别展开或收起的区块，而不是要求研究者在互斥的上下文标签之间切换。这里借鉴的是信息呈现和交互方式，不照搬 Zotero 的文献字段、功能范围或视觉细节。

已经确认的呈现原则是：

- 每个区块使用清楚但克制的标题，可以显示必要的数量或状态提示；
- Metadata 以字段名与字段值组成的纵向列表呈现，字段名弱化、内容值突出，长内容自然换行；
- 区块可以单独收起，使正文仍然是主要视觉对象；
- 笔记状态、Metadata、关系以及 Review/Record 历史可以按照这种方式成为右栏中的不同区块；
- 具体区块顺序和默认展开状态可以随 `Analyses`、`Topics`、`Works` 的实际用途不同，但三类库各自需要哪些字段仍待探索。

Zotero 截图中出现的 Abstract、Attachments、Notes、Related、Tags 等区块不因此自动进入 Scholium-lite。字段是否允许原位编辑、空字段在日常阅读时是否隐藏、Metadata 的具体存储位置以及哪些字段允许自动生成，仍待决定。

Zotero 式可折叠区块仍可作为 Metadata 呈现参考，但不再要求替换现有 Overview/Connect Inspector 模式，也不要求取消独立 Research Records 窗口。Sidebar–Document–Apparatus 骨架与当前研究任务相容，继续保留。

`Analyses` 的右侧信息需要显示两类 Metadata：

- 与被分析文献有关的学术元数据；
- 与这篇 Analysis 笔记自身有关的修改时间、当前 Settle 状态及相应时间等生命周期信息。

“学术元数据”具体包含哪些字段仍待通过真实 Analysis 确定。Analysis 的创建时间没有研究意义，不需要为了产品完整性把它作为研究 Metadata 持久化或突出显示；如果底层文件系统恰好提供该时间，也只能作为普通技术信息。修改时间是否只计算正文变化、笔记重新变为 `unsettled` 后如何保留历次 Settle 时间，仍未决定。索引重建或其他机械维护不能被误记为研究正文的修改时间。

`Analyses` 的书目 Metadata 不由 Scholium-lite 独立管理。Zotero 是题名、作者、年份、出版物、卷期页码、DOI、出版社等书目数据的管理者；Scholium 保存 Analysis 与 Zotero 条目以及必要时与具体来源附件的稳定关联，并在右栏只读投影 Zotero 当前数据。书目修改回到 Zotero 完成。如果 Zotero 暂时不可用，可以显示明确标注时间与非权威地位的上次读取缓存。

这一边界不表示 Zotero 数据已经得到原文核验。PDF 或出版物原文仍是书目信息最终核验依据；Analysis 正文或相应 Record 可以记录 Zotero 数据与原文的差异，Scholium 不得用 Zotero 投影静默覆盖这些判断。一个 Analysis 也可能只分析书籍中的具体章节或某个版本，因此它仍需要保存足以指向实际分析对象和具体来源的关联信息。

除各库特有的信息外，`Analyses`、`Topics` 和 `Works` 的右栏都需要显示：

- 对当前笔记内容的简要总结；
- 描述当前笔记内容的关键词或标签。

这里的总结和标签属于笔记层级，不是原论文的 Abstract 或作者提供的 Keywords。它们主要帮助研究者与 Agent 迅速理解、筛选和找回笔记；仍是正文的辅助投影，不能取代正文或在冲突时取得更高权威。其生成、修改、存储和过期提示方式仍待决定。

### 已批准的左侧导航结构

左侧导航以三个研究库及其真实文件结构为基础：

- `Analyses`、`Topics` 和 `Works` 是三个固定且清楚区分的库入口，不合并成依靠标签区分的单一文件列表；
- 进入一个库后，显示该库真实的文件夹层级和笔记；
- 对文件夹或笔记进行新建、改名和移动时，结果直接反映到磁盘上的 Markdown 知识库结构；
- 搜索可以跨越三个库，但每条结果必须明确显示所属库，不能因为统一检索而消除三类材料的研究权威差异；
- 从搜索结果打开笔记后，仍能看见它在原库和文件夹层级中的位置；
- 左侧不加入统计卡片、知识图谱或活动信息流。

文件树的具体交互、排序、最近笔记、收藏和搜索入口形式仍待决定。

## 七、概念检索与哲学判断

围绕“情绪能否成为理由的奠基”进行的检索实验表明，文件名和少量关键词不足以找到哲学上相关的材料。`emotion`、`affect`、`desire`、具体情绪类型和 `attitude` 可能属于同一概念邻域；`fittingness`、`value`、`good`、`blame`、`criticizability` 等概念也可能从不同方向触及同一问题。

检索不能被理解为把中文问题翻译成一组英语同义词。研究者会使用多种语言讨论哲学，Agent 应从概念和论证关系出发跨语言寻找材料。概念邻近不等于同义，关键词重合也不等于正在回答同一个问题。

Agent 需要进一步判断：

- 一个观点是在说明情绪呈现理由、事实支持情绪、情绪构成价值或 import，还是在主张情绪奠基理由；
- 两个观点处于动机、显著性、价值、拟合性、理由、规范力量、权威或可批评性等哪个解释层级；
- 材料对当前问题是直接支持、先驱或启发、邻近观点、反向解释、明确反对，还是只构成间接压力；
- 一段材料在论证中承担定义、前提、结论、反例、批评、回应、让步或背景等什么角色。

哲学知识不能套用“冲突即淘汰”的处理方式：

- 观点之间存在冲突或差异，不因此使其中一方自动失效；
- 主流程度不能作为正确性的替代标准；
- 使用不同概念或理论框架，不意味着双方必然在讨论完全不同的问题；
- 使用相同词语，也不意味着双方具有相同的问题和主张。

Agent 应先在各自理论框架中重构观点，再判断它们是否共享解释对象、在哪些层面重叠、是否形成解释竞争或间接压力，以及是否真正不相容。内部矛盾、无效推论、缺乏支持的前提和错误归属仍然可以受到批评，但不能以单纯的差异、非主流地位或关键词不一致代替哲学评价。

索引或检索产生的语义关系只是帮助阅读的线索，不是对观点真假的裁决。最终判断必须回到相关正文，并保留异议、限定和不确定性。

第一版已经决定不要求用户下载本地语义模型。概念检索采用 Agent 主导的逐步检索：Scholium 自动维护轻量的正文索引、标题与章节目录和链接图；Codex 或 Claude 从问题本身形成跨语言的概念邻域和多组查询，经 MCP 反复搜索、阅读命中段落、修正查询并沿链接继续核验。底层文本检索只负责提供候选材料，概念扩展和哲学判断由用户已经订阅的 Agent 完成。

本地向量模型和 QMD 不进入第一版的必需依赖，也不能成为朋友使用 Scholium 的额外下载门槛。如果真实使用后来证明 Agent 主导的逐步检索仍存在重要且稳定的遗漏，可以再把较小的本地语义检索作为可选增强进行验证。

## 八、带长注释的双链

研究者所说的“向量链接”原本是带有语义的双链，例如 `A supports B` 或 `A opposes B`。进一步讨论后确认，普遍维护稳定的句子级双端锚点在技术上和操作上都过于复杂，也会重新增加维护负担。

当前接受的替代方式，是让一次双链出现携带自由的长注释：

```markdown
[[目标笔记]]{{关于这一次引用的长注释}}
```

长注释可以使用多行 Markdown：

```markdown
[[Helm - Emotions and Practical Reason]]{{
Helm 的 import 理论可以启发较弱的实践关切主张，
但不能直接支持情绪奠基理由的强主张。
}}
```

已经确认的含义和边界是：

- 注释属于这一次双链出现，而不是目标笔记的永久属性；
- 注释可以自由说明支持、反对、限定、继承、类比、解释差距或其他更复杂的关系，不强制压缩成固定关系类型；
- Agent 在阅读相关笔记时，根据局部正文和注释临时解释关系，不预存一个被视为权威的 `supports` 或 `opposes` 标签；
- 来源笔记中的双链与注释是唯一权威内容；
- 阅读来源笔记时，长注释显示为双链旁的可展开小标记；
- 被链接笔记可以显示同一注释的只读反向视图，并保留来源笔记和局部语境；
- 在目标处编辑时，应回到来源处的同一份内容，而不是产生第二份注释；
- 修改来源注释只算修改来源文件，不能把目标笔记记为被修改；
- Agent 阅读目标笔记时，必须区分目标正文、目标主动链接出去的注释，以及其他笔记传入的注释，不能把传入注释误认为目标笔记自身表达的立场。

普通脚注与这种双链注释保持独立，脚注快捷操作不应与 `[[目标]]{{注释}}` 发生语法或交互冲突。当前确认的是研究者需要的表达方式及权威边界，不因此批准具体解析器、存储结构或界面架构。

## 九、现场观察，不是需求

对 Antelucana 的只读检查得到以下快照：

- Markdown 文件共 610 个；
- `Topics` 中有 199 个 Markdown 文件；
- `Analyses` 中有 265 个 Markdown 文件；
- `Works` 中有 146 个 Markdown 文件；
- `Works` 中有 63 个以 ` 2.md` 结尾的文件，均与对应的不带 ` 2` 的文件逐字相同。

这些数字和重复文件只描述当前材料状态。尚不能据此判断重复产生的原因，也不能把它们归因于 Agent、索引或某种产品设计。

针对示例问题对 `Topics` 与 `Analyses` 所做的只读检索还得到以下观察：

- 仅从文件名可以发现 29 个候选文件；
- 使用初步的情绪与理由概念词族，会命中 464 个文件中的 421 个；
- 使用较直接的关系表达，会命中 108 个文件；
- 扩展到 affect、desire、具体情绪、attitude、fittingness、value、good、blame 和 criticizability 等邻域后，会命中 464 个文件中的 450 个。

这说明单纯扩大关键词集合会迅速从遗漏转为噪音，不能替代对正文和论证角色的判断。

此外，264 篇论文分析的结构化 `dissertation_role` 字段均为空，但正文都包含 `Source-role classification`；其中 186 篇正文还明确写有负面使用边界。这进一步说明，当前材料中有用的论证角色主要存在于正文，不能假定结构化字段已经表达了这些信息。

对 `Analyses` frontmatter 的进一步只读审计显示：265 个 Markdown 文件中，1 个是无 frontmatter 的 `README.md`，其余 264 篇正式 Analysis 几乎完全共享一套 29 个顶层字段，只有 1 篇额外带有 `tags`。其中：

- `dissertation_role`、`dissertation_claim_links`、`dissertation_updated_at` 和 `revision_relation` 在 264 篇中全部为空，`secondary_clusters` 只有 1 篇非空；
- `primary_level` 和 `primary_cluster` 与文件所在路径完全一致，可以由路径推导；
- `record_type` 与 `schema_version` 在所有 Analysis 中完全相同；
- 262 篇的 `created` 都是同一天，全部 264 篇的 `updated` 都是同一天，反映的是批量整理而不是有研究意义的笔记历史；
- 72 篇没有 `zotero_item_key`，121 篇没有 `zotero_attachment_key`，同时存在多篇章节 Analysis 共用一个 Zotero 书籍条目的情况；
- `audit.status` 和 `audit.checks.structure_complete` 在所有 Analysis 中都为通过，`audit.checks.human_reviewed` 在 262 篇中为真，但另一个 `status` 字段只有 30 篇为 `reviewed`，说明旧状态字段之间没有清楚的一致含义；
- 264 篇正文都已经包含 Reference、Rating 和 Source-role classification，许多还包含来源说明、证据核验、后续线索与未决问题；旧 frontmatter 中若干简化字段因而不能替代正文里的限定。

这些观察只用于判断新产品需要，不授权批量修改或删除现有 Analysis frontmatter。

## 十、尚未决定

以下事项仍需继续通过真实研究活动探索：

- 活动记录的存放位置、问题关联方式以及后续检索机制；
- 索引究竟需要表达什么，以及何时算“最新”；
- 哪些结构化字段真正改善 Agent 的检索；
- Agent 如何呈现对过去判断的修正；
- 原始文献的访问方式；
- `Topics`、`Analyses`、`Works` 各自需要哪些元数据、检索规则、核验要求和修改提示；
- 普通的、没有长注释的正文双链在关系发现中应承担什么作用；
- 带长注释双链的具体编辑、展开和反向展示方式；
- npm 包名、Node.js 支持版本以及其他具体技术架构；
- 核心工作界面的信息关系、组件体系和视觉风格；
- 轻量 Handoff 的具体内容、触发方式和降级格式。

在 Scholium-lite 独立探索阶段，SwiftUI、原生 macOS App、完整 Triptych 框架、managed Metadata、旧 Research Records、多种固定 Research Actions、旧 Zotero 填充流程和插件体系都没有自动获得批准。迁回旧 Scholium 后，研究者明确重新保留 Swift 原生 macOS App、现有三库与界面骨架；其余项目仍需按本记录中的最新结论分别审查。

## 十一、迁回后的现行规范对照

本节记录 2026-09-02 对本探索记录与旧 Scholium 当前 canonical specification 的只读对照。它不修改正式目标，也不把探索结论描述为已经实现。后续每项替代决定必须进入其唯一 owning chapter，并在同一规范切片中删除被替代规则。

### 基本一致，可以作为继续工作的基础

| 探索结论 | 现行规范 | 判断 |
| --- | --- | --- |
| 继续使用 Swift 原生 macOS App，暂不考虑跨平台 | [Foundation §2.1](../../Docs/Specification/01-foundation-and-triptych.md#21-research-document-first)、[Release §21.5](../../Docs/Specification/10-release-and-open-decisions.md#215-source-first-beta-distribution) | 一致。Scholium-lite 阶段的本地 Web/Windows 方向已暂停，不再要求平台重写。 |
| Markdown 正文是研究内容权威；索引、Metadata、关系和渲染只是辅助或投影 | [Foundation §2.1](../../Docs/Specification/01-foundation-and-triptych.md#21-research-document-first)、[Notes §5.2](../../Docs/Specification/02-notes-and-file-operations.md#52-authored-yaml-and-scholium-metadata)、[Search §13](../../Docs/Specification/04-connect-search-and-recovery.md#13-search-and-attention) | 基本一致。旧规范的精确字节、外部变化、冲突和恢复边界应保留。 |
| `Analyses`、`Topics`、`Works` 是三个不同研究库，真实文件夹层级保持可见 | [Foundation §3](../../Docs/Specification/01-foundation-and-triptych.md#3-the-scholium-triptych)、[Library §18.3](../../Docs/Specification/06-interface-shell-and-library.md#183-library-and-search) | 核心一致。旧规范额外附加的 Triptych 注册、窗口恢复和控制状态仍需分别证明，不能由“三库必要”自动推出。 |
| 三类库具有不同研究角色，Agent 不能把 Analysis 或 Topic 自动当成研究者立场 | [Foundation §§2.3、3.1](../../Docs/Specification/01-foundation-and-triptych.md#23-authorship-and-provenance)、[Work §11.1](../../Docs/Specification/03-research-actions-and-workflows.md#111-researcher-governed-works) | 部分一致。现行规范已有作者和库角色边界，但尚未充分表达 `Works` 是研究者立场的主要文本来源，以及 Topic/Analysis 中的评价不能自动归属于研究者。 |
| Agent 是外部参与者，Scholium 不成为永久聊天或嵌入式 Agent runtime | [Foundation §2.2](../../Docs/Specification/01-foundation-and-triptych.md#22-researcher-responsibility-and-optional-agent-access)、[Boundaries §17](../../Docs/Specification/05-integrations-onboarding-and-boundaries.md#17-permanent-boundaries-and-deferred-capabilities) | 基本一致。冲突在具体通信、权限和工作流机器，而不在“外部 Agent”原则。 |
| 行动开始时必须看到当前文件状态；派生索引不可成为第二权威 | [Search §13](../../Docs/Specification/04-connect-search-and-recovery.md#13-search-and-attention)、[Save §14](../../Docs/Specification/04-connect-search-and-recovery.md#14-save-agent-changes-and-recovery) | 基本一致。现行规范已有 generation、fingerprint、Limited/Stale/Unavailable 和外部变化边界。 |
| 不把本地向量模型、embedding 或自动关系推断作为第一版依赖 | [Search §13](../../Docs/Specification/04-connect-search-and-recovery.md#13-search-and-attention) | 一致。现行规范明确排除 vector search、embedding、AI ranking 和自动关系抽取。 |
| 删除笔记必须进入系统垃圾桶／废纸篓并可恢复 | [System Trash §6](../../Docs/Specification/02-notes-and-file-operations.md#6-system-trash-deletion-and-temporary-application-cleanup) | 一致。当前继续面向 macOS，现有 system Trash 边界可以保留。 |
| 界面正文优先、三区域、克制、学术编辑风格，避免卡片墙和管理后台感 | [Interface §§18.1–18.2](../../Docs/Specification/06-interface-shell-and-library.md#181-interface-principles)、[Design §19](../../Design.md#19-scholarly-editorialism-and-design-variables) | 高度一致。继续保留 Swift/macOS、Scholarly Editorialism、Sidebar–Document–Apparatus、文档主位和现有设计系统；具体质量问题以后依据实际界面逐项修正。 |
| Review、Edit、Source 提供独立阅读、Live Preview 编辑和完整源码 | [Notes §5.1](../../Docs/Specification/02-notes-and-file-operations.md#51-document-modes-and-yaml)、[Document §18.4](../../Docs/Specification/07-document-and-research-interface.md#184-document-modes-context-and-metadata) | 迁回后决定保留。探索中的“单一阅读编辑表面”不再要求取消无干扰阅读模式。 |
| Overview/Connect Inspector、独立 Records 窗口和 Sidebar–Document–Apparatus 骨架 | [Interface §18.2](../../Docs/Specification/06-interface-shell-and-library.md#182-workspace-shell-and-document-tabs)、[Research Interface §18.5](../../Docs/Specification/07-document-and-research-interface.md#185-contextual-research-and-actions) | 可以保留，不再列为当前需要替换的界面合同。 |
| 三类笔记都需要 authored `summary` 和 `keywords/tags` | [Metadata Appendix A](../../Docs/Specification/11-metadata-and-critique.md#shared-authored-yaml) | 一致。现行规范已经把 `summary` 和 `keywords` 设为三库共享的 authored YAML。 |

### 部分一致，但现行设计明显超过已证明需要

| 领域 | 已有可保留部分 | 需要缩减或重新证明的部分 |
| --- | --- | --- |
| Search | 一个 current source corpus、字段命中理由、范围、来源位置、freshness、App/CLI 同一 owner | Saved Searches、Attention、Related-Content 自动目录、完整可见 grammar 和大量状态是否都属于第一阶段尚未证明。核心缺口反而是外部 Agent 能经 MCP 多轮查询、读段落、修正查询和沿链接核验。 |
| Agent 写入 | 精确身份、预期 revision、原子写入、readback、冲突、Diff 和可恢复 Undo | Session、Run、Activity Ledger、transaction lease、Result Contract 和 per-Action capability machine 远重于“用户在 Agent 对话中的明确指令即授权”这一已确认需要。安全写入不能与重复审批混为一谈。 |
| Zotero | localhost read-only API、稳定 Analysis binding、bibliographic data 不等于论文内容或哲学证据 | `Link and Fill`、独立可编辑的完整书目 Metadata、Refresh 冲突处理和 Run adapter 超出已确认边界。探索结论只要求绑定具体条目／附件并只读投影 Zotero 数据。 |
| Diff/Undo | 保存准确的修改前后版本、逐文件结果、Earlier Revision 和直接恢复路线 | 现行 Agent Changes 可以继续作为比较基础。非技术化呈现仍可改进，但 Record 投影、未读历史和 durable reviewed 状态暂不需要。 |
| 界面骨架 | Sidebar—Document—Apparatus、Overview/Connect Inspector、独立 Records 窗口与旧 WebEditor 均可继续使用 | 不做结构性替换。Action rail、Notifications 或局部细节只有在真实使用暴露问题时才单独评估。 |
| Skills | 方法内容由研究者拥有、Skill 不拥有平台权限 | 固定 Action—Skill Registration、bundled method 套件、Profile 和 Result field 体系过于庞大。探索只确认个人 Skill 可选安装，MCP 负责共同工具边界。 |

### 与已确认探索结论明确冲突，需要替换现行目标

| 冲突 | 现行规范 | 探索结论 |
| --- | --- | --- |
| Agent 通信 | GUI/CLI pairing、Run-bound Session、Application API 和独立 Scholium CLI | 本地 MCP 是 Codex/Claude 的主要通信通道；Agent 对话留在用户已有客户端，不要求模型 API Key，也不内嵌聊天。 |
| Action 模型 | Analysis/Topic/Work 各有固定 Discuss/Analyze/Synthesize/Write/Critique/Check Fidelity，Run 是唯一工作对象 | 多种 Research Actions、Profiles 和固定 Action 注册未重新证明必要。一次工作只需用户问题、MCP 工具、个人 Skill 和明确写入指令。 |
| Record 单位 | 每个 Discussion 或 Action Run 最终产生一个不可变 Research Record | Record 围绕持续研究问题组织，可以在同一条内按实质步骤追加；只有新判断、重要修正、研究决定或文件修改才更新，不保存全部对话或普通操作。 |
| Settle 变化 | 任意后续保存或 Agent 修改自动使当前 revision 成为 Not Settled | `settled/unsettled` 只由研究者手动决定。Agent 修改后可以提醒重新判断，但不能自动改变状态。 |
| 关系语法 | `+[[B]]`、`-[[B]]`、`?[[B]]` 是唯一 Vector Link，预先编码 supports/opposes/incompatible | 固定 Vector Link 被否决，改为一次链接出现携带自由长注释：`[[B]]{{...}}`。关系由 Agent 结合局部正文和注释解释，不能把标签当作哲学事实。 |
| Analysis 书目 Metadata | Scholium 维护完整、可编辑、可由 Zotero 填充的 managed bibliographic catalog | Zotero 管理书目 Metadata；Scholium 只保存条目／附件关联、自己的研究状态和必要来源边界，右栏只读投影 Zotero。 |
| 第一阶段重点 | 当前 Beta/1.0 规范同时推进完整 Actions、Records、Metadata、Zotero、通知、恢复与发布 | 继续使用现有 Swift App，不整体重建；当前能用且不冲突的部分保持不变。对确认需要改变的 Action/Run、Record、Settle、Vector Link 和书目 Metadata 分别明确新合同并 clean cutover，不保留旧路径。 |

### 探索后新增、现行规范尚未充分表达

- 检索必须支持 Agent 从哲学概念和论证关系出发进行跨语言、多轮查询，而不是把问题翻译为同义词集合或只扩大关键词。
- Agent 需要区分定义、前提、结论、反例、批评、回应、让步和背景，并区分直接支持、相邻观点、反向解释、明确反对和间接压力；Search 只提供候选，不承担这些哲学判断。
- 哲学观点之间的冲突、非主流地位和概念差异都不能自动作为无效、错误或完全无关的依据。
- `Analyses`、`Topics`、`Works` 对研究者立场具有不同证据意义；这首先应进入 release-shipped Core Protocol 对 Agent 的共同说明。较早 Work 与近期讨论冲突时，Agent 应重构双方、评价可行性并与研究者讨论，不能按时间机械选择。
- Scholium 仍只机械建立准确文本 Diff；Record 投影式 Review 历史、最新未读提示和 durable reviewed 状态暂不需要。
- 带长注释双链的注释属于来源处的单次链接出现；目标处只显示同一内容的只读反向投影，不能形成第二份权威副本。
- Zettlr 已经经过实际体验并因界面与交互细节不符合标准而被否决，不能再以功能清单把它当成直接替代或自动 fork 基础。

### 仍未决定，不能在修订中擅自补全

- 轻量索引的具体实现、字段和“行动开始时最新”的技术判据；
- `Topics`、`Analyses`、`Works` 各自保留哪些最小 Metadata 与检索规则；
- Record 的存储格式、持续步骤结构和是否允许直接编辑；
- Agent Changes 的非技术化改进与整次／局部恢复方式；现有 Review/Edit/Source 模式和保存机制暂不因本轮探索改变；
- 带长注释双链的解析、编辑、展开和反向展示细节；
- 新 Record 合同如何取代现有 Run-Record 合同，并删除旧格式和旧路径；
- 新的关系链接和 Zotero 书目投影如何分别取代旧 Vector Link 与 managed bibliographic Metadata，而不保留双重语义。

### 建议的规范修订顺序

1. 保持 Swift/macOS、WebEditor、Sidebar–Document–Apparatus、Review/Edit/Source、Inspector 和 Records 窗口不变；只检查它们是否确实阻碍已经批准的新需要，不做预防性重写。
2. 先做边界最小且不要求 UI 重构的产品修订：在 Core Protocol 中表达三库证据意义和哲学检索方法边界；确定 MCP 如何复用现有 Search 和精确读写 owner。
3. 为 CLI pairing、固定 Actions、Run 权限机器设计一个完整替代合同后，再进行一次有界 cutover；不得留下两套并行授权模型。
4. 分别设计并批准 Record、手动 Settle、新的带长注释双链和 Zotero-only 书目投影；每项在合同明确后同步修改 canonical specification、实现、调用者与测试，并删除被替代路径。
5. 只有真实问题要求时才修改现有界面骨架和视觉系统；不要把需求探索变成全应用重写。

### 已批准的下一修订边界

研究者批准上述必要性判断与修订顺序。下一步只定义“通用 Scholium MCP + 新 Core Protocol”的完整替代合同：以用户在外部 Agent 对话中的指令作为任务和写入依据，让 MCP 复用现有 current-state、Search、精确读取、创建、修改、系统废纸篓、Diff、Undo 和恢复能力；删除固定 Research Actions、Action Profiles、Pairing、Session、Run、Result Contract 及其并行入口。现有 Swift/macOS、三库、文件与索引基础、WebEditor、Review/Edit/Source、Sidebar–Document–Apparatus、Inspector 和独立 Records 窗口不因这一切换而改变。

这项批准只确定下一份替代合同的范围和 clean-cutover 原则，尚未批准具体 MCP 工具 schema、进程通信、安装方式、Core Protocol 文本、正式规范补丁或代码实现。Record、Settle、带长注释双链和 Zotero-only 书目投影仍是后续独立切换，不混入第一份合同。

研究者随后批准了这份替代合同的第一层产品定义：

- Scholium MCP 与 Core Protocol 是两个独立所有者。MCP 是只负责当前知识库能力和文件安全的应用 adapter；Core Protocol 是指导 Agent 如何检索、判断和使用这些能力的官方精简 Skill。用户自己的哲学方法 Skill 可以另外安装，不能由 MCP 或 Core Protocol 固定为 Action 类型。
- 第一版 MCP 的最小能力是：确认当前 Triptych／文件／索引状态，检索笔记，读取完整正文或相关段落，读取 Connections，创建笔记，依据当前 fingerprint 修改笔记，以及移入 macOS 系统废纸篓。Record、Settle、reviewed 状态、Action、Result 和“完成任务”不进入这一工具集合。
- MCP 没有 Run、Session、Pairing、Action 类型或持续权限。是否应该写入由用户在外部 Agent 对话中的指令和 Core Protocol 决定；Scholium 只执行路径范围、当前 revision、并发冲突、原子写入和 readback 等数据安全检查。
- 搜索结果、Metadata 和 Connections 只提供候选与定位，不构成哲学证据或关系判断。Agent 应从问题形成跨语言概念邻域并进行多轮检索，在形成判断前读取相关正文。
- Core Protocol 负责三库的证据意义、正文权威、来源／重构／评价／研究者立场的区分、默认只读、明确写入指令、禁止无关扩散修改，以及修改后的学术说明。Record 规则在新的 Record 合同批准后再加入。
- 第一版 MCP 只在 Scholium App 正在运行时可用。App 是 live workspace、编辑器保存和当前索引的唯一进程所有者；MCP helper 只与它通信，不启动第二套 headless workspace。App 未运行时明确返回不可用并提示启动 Scholium，不静默启动或降级到直接文件访问。

研究者随后把上述合同中的技术细节委托给 Codex 决定。下面的决定是下一次 canonical specification clean cutover 的设计输入，不表示当前代码已经实现，也不授权在本步骤修改正式规范或应用代码。

### 委托决定的 MCP 技术合同

#### 进程、传输与依赖

- 继续使用现有已安装的 `scholium` 可执行文件，不新增常驻 daemon 或第二套 workspace runtime。新的 stdio 入口是 `scholium mcp serve`；Codex 或 Claude 每次连接时启动这个短生命周期进程。
- `scholium mcp serve` 只把 MCP 请求转交给正在运行的 Scholium App。它不直接打开 Triptych、扫描文件或读写 Markdown。App 未运行、目标 Triptych 未打开或 App 无法形成 current snapshot 时，工具返回明确错误，不静默启动 App，也不退回现有 CLI 的直接文件操作。
- helper 与 App 复用现有的 `127.0.0.1`、current-user-only Application Support secret 和 challenge-response 机制。该 secret 只证明本机传输对端属于当前 Scholium 进程，不是研究写入许可，不产生 Pairing、Session、Run 或持续 Agent 身份。
- 旧 `scholium agent …` 命令族及其 Pairing／Session／Run wire contract 在正式切换时删除。仍有独立用途且不依赖旧 Action 模型的普通 CLI 命令可以保留；Core Protocol 不把它们当作 MCP 的回退路径。依赖旧 Action／Run／Record 合同的 CLI 命令随各自 owner 的切换删除或替换。
- 不为第一版增加 Swift MCP SDK 依赖。现有 Zotero MCP 已经具备经过测试的 JSON-RPC、stdio framing、结构化结果和协议协商；实现时把其中通用部分一次性改名并抽取为内部 MCP transport/server 基础，由 Zotero MCP 与新的 Scholium MCP 共用，不能复制出第二套协议实现。官方 Swift SDK 可以在现有实现出现真实协议缺口时再重新评估。
- 服务器协商当前实现已经支持的 MCP `2025-11-25`，并保留 `2024-11-05` 客户端兼容协商。第一版只声明静态 `tools` 能力；不暴露 Resources、Prompts、Sampling、Roots、Elicitation 或实验性 Tasks，也不以 MCP Task 重新创造 Run。
- Codex 与 Claude 获得完全相同的七个工具、schema、错误和行为；差异只存在于客户端的安装命令。不得为任一客户端增加私有工具名或旁路。

#### 唯一工具集合

| 工具 | 输入要点 | 成功结果要点 |
| --- | --- | --- |
| `scholium_workspace_status` | 可选 `triptych_id` | 当前打开的 Triptych；目标的三库状态、文件数、`workspace_generation`、Search generation 与 source-manifest hash；是否已经 current |
| `scholium_search_notes` | `triptych_id`、`query`；可选 `roles`、`limit`、`offset` | 按现有 Search owner 排序的候选段落；每项带 Note 身份、库角色、路径、fingerprint、命中字段／理由、snippet 与正文位置；不返回哲学相关性分数 |
| `scholium_read_note` | `triptych_id`、`note_id`；可选 `start_line`、`line_count` | 对应 current fingerprint 的精确 Markdown 片段、行范围和下一页位置；重复调用可以读完整篇笔记 |
| `scholium_list_links` | `triptych_id`、`note_id`、`direction`；可选 `limit`、`offset` | incoming／outgoing 的原始链接出现、来源与目标身份、原始 markup 和来源位置；不输出 `supports` 等 Agent 推断关系 |
| `scholium_create_note` | `triptych_id`、`role`、精确 `relative_path`、`body`；可选 `summary`、`keywords` | 新 Note 的稳定身份、三库角色、路径、fingerprint 和 `change_id` |
| `scholium_update_note` | `triptych_id`、`note_id`、`expected_fingerprint`、`mode`、`content` | before／after fingerprint、路径、`change_id` 与 readback 结果 |
| `scholium_trash_note` | `triptych_id`、`note_id`、`expected_fingerprint` | 已移入 macOS 系统废纸篓的 Note 身份、原路径与 `change_id` |

工具合同的进一步约束如下：

- 对外库角色只使用 `analyses`、`topics`、`works`，不暴露现有内部的 `source_corpus`、`topic_knowledge`、`draft_project` 名称。
- 除 `scholium_workspace_status` 外，所有工具都要求明确的 `triptych_id`。status 在仅有一个打开的 Triptych 时可以自动选中并核对它；有多个时返回候选并要求 Agent／研究者明确选择，不使用“最近窗口”或“前台窗口”猜测。
- Note 以稳定 UUID `note_id` 定位，路径只是可读位置。身份未解析或有冲突时可以返回搜索候选，但不得按路径猜测写入或删除。
- fingerprint 统一为 `{sha256, byte_count}`。所有写入和删除都要求完整的 `expected_fingerprint`；stale 时必须重新读取，不能自动覆盖。
- `scholium_update_note.mode` 只有 `body` 与 `source`。`body` 是默认路线，只替换正文并逐字节保留 YAML envelope、BOM、换行风格及其他未改范围；`source` 替换完整 Markdown，只在用户明确要求修改 YAML 或完整 source 时由 Core Protocol 允许调用。MCP server 不另行索要通行证。
- 每次 update 只作用于一篇 Note，不支持跨文件 batch。研究者明确要求多篇时，Agent 分别调用并分别报告；不会由一次修改自动扩散到相关笔记、Metadata、链接、Record 或 Settle。
- create 的路径必须是目标角色库内的相对 `.md` 路径；不接受绝对路径或 `..`，路径已占用时失败，不自动改名。缺省 `summary` 和 `keywords` 生成当前最小 authored YAML 的空值，不创建 Analysis 书目 Metadata。
- trash 只处理单篇 Note，只调用系统废纸篓，不提供永久删除或文件夹递归删除。
- Search 沿用一个权威 query grammar：query 不改变 scope，`roles` 才决定三库范围；默认 20 项、最多 100 项，沿用现有 16,384 UTF-16 code-unit／64 query-token 上限。结果给出命中理由和位置而不输出伪精确的哲学相关性分数。
- read 默认从第 1 行读取 200 行，单次最多 1,000 行并受 256 KiB UTF-8 结果上限约束；结果必须说明是否完整及下一起始行。内部 App bridge frame 上限在切换时统一提高为 2 MiB，以容纳现有 512 KiB Note 上限和 JSON framing，而不是降低可编辑文档上限。
- create、update 和 trash 各形成一个由 App 保存的 `change_id`，只用于现有准确 Diff、Earlier Revision／Undo 和修改位置导航。它不是 Run、Record、研究完成状态或 Agent 修改说明；哲学意义上的变化概括仍由 Agent 在对话中报告。

#### Currentness、结果与失败语义

- Core Protocol 在一次研究任务首次访问知识库前调用 `scholium_workspace_status`。App 先完成已经在排队的编辑器保存，核对外部文件变化，并使 Search generation 对应同一 source manifest；只有此后才返回 `current: true`。这不会产生研究 Record，也不会修改 Agent 未被授权修改的正文。
- 每次 search、read 和 link 调用仍自行检查 currentness；status 不是随后读取旧 snapshot 的许可证。文件在两次调用之间改变时，后一次返回新的 generation／fingerprint，Agent 按新状态继续。
- 写入只以 Note fingerprint 做 compare-and-swap；workspace generation 不充当整库写锁。App 继续负责 dirty editor、外部修改、原子替换、readback 和跨窗口协调。
- 每个工具的 `structuredContent` 根节点都是 object，同时提供内容相同的 JSON text block，便于不同 MCP host 使用。tool definition 同时声明 `inputSchema`、`outputSchema` 和 `additionalProperties: false`；成功结果含 `schema_version: 1` 与 `status: "ok"`。
- 可预期的领域失败使用正常 `tools/call` 结果、`isError: true` 和共同错误对象 `{schema_version, status: "failed", code, message, recovery}`；JSON-RPC 解析错误或未知方法才使用 protocol error。第一版固定错误码为 `app_unavailable`、`workspace_selection_required`、`workspace_not_ready`、`not_found`、`ambiguous`、`path_occupied`、`stale_revision`、`conflict`、`invalid_request`、`operation_uncertain` 和 `internal_error`。
- helper 在请求已发送但没有收到结果时返回 `operation_uncertain`，禁止自动重试 mutation。Agent 应重新调用 status／read，确认目标 fingerprint 或路径状态后再判断是否需要新的写入。
- read-only 四工具声明 MCP `readOnlyHint: true`、`destructiveHint: false`、`idempotentHint: true`、`openWorldHint: false`。create 声明非只读、非 destructive、非 idempotent；update 与 trash 声明非只读、destructive、非 idempotent。annotations 只是客户端提示，不承担授权。

#### 安装与 Core Protocol

- Scholium 的 Agent Integration 设置只显示 App／bridge／CLI 是否可用，并提供“复制 Codex 设置命令”“复制 Claude 设置命令”和“显示 Core Protocol 文件夹”。第一版不自动编辑 Codex 或 Claude 的配置。
- 两个客户端都按 user scope 注册同一个本地 stdio server `scholium`，命令指向已验证的绝对 `scholium` 可执行文件并传入 `mcp serve`。Codex 使用 `codex mcp add scholium -- <absolute-scholium-path> mcp serve`；Claude 使用 `claude mcp add --scope user scholium -- <absolute-scholium-path> mcp serve`。App 生成真实绝对路径，文档不依赖 shell 的 `~` 展开。
- Core Protocol 作为 release-bundled、普通文件夹形式的 `scholium-core-protocol` Skill 分发；Scholium 只显示客户端相应的 user-scope 安装说明，不强行覆盖用户已有 Skill。研究者和朋友可以另外安装自己的方法 Skill。
- MCP initialize 的短说明只表达工具事实：先检查 workspace status、正文是权威、Search／Metadata／Links 是候选、mutation 要求 current fingerprint、App 不判断聊天授权。完整研究行为属于 Core Protocol。
- Core Protocol 的最小强制内容是：任务首次访问先取得 current status；从问题本身形成跨语言概念邻域并多轮检索；形成判断前读取正文；区分 primary text、Analysis、Topic、Work、过去讨论与 Agent 重构；不能从关键词、相似度、主流性、冲突或概念差异直接推出哲学关系或有效性；Topic 与 Analysis 对论文归属或论证内容发生实质冲突时主动回到可用原文核验，仍不能解决时明确保留不确定性；默认只读，只有用户明确指定创建／修改／移入废纸篓时才作用于相应目标；不得顺带更新相关文档、Metadata、链接、Record 或 Settle；stale／conflict 时重新读取，`operation_uncertain` 时先核验而不盲目重试；mutation 后报告文件、位置以及由 Agent 作出的学术变化说明。

这一技术合同已经把工具、schema 语义、transport、安装与 Codex／Claude 一致性决定到足以起草正式规范的程度。仍需下一步单独完成的是：把它写入 owning canonical chapters，明确要删除的旧合同和仓库调用者；这一步不能与代码实现混在同一未经审阅的变更中。
