# Scholium Agent Recommended Reading 与 Works 动态推荐提案

> 状态：Agent-only 多渠道推荐已进入正式规范并完成本地实现；Works 动态消费者仍是提案
> 日期：2026 年 8 月 27 日  
> 范围：为 Work Write／Critique 提供 Analyses／Topics、为 Topic Synthesize 提供 Analysis-only 推荐，并支持 Agent 按 Note 名动态查询；以后让同一 owner 支持 Works 写作
> 权威边界：本文不是 [SCHOLIUM_SPEC.md](../../Docs/SCHOLIUM_SPEC.md)、[IMPLEMENTATION_ARCHITECTURE.md](../../Docs/IMPLEMENTATION_ARCHITECTURE.md) 或 [IMPLEMENTATION_STATUS.md](../../Docs/IMPLEMENTATION_STATUS.md)。三者分别拥有正式目标、结构与当前证据；本文只保留已采纳设计的解释和未采纳扩展。

## 1. 决策摘要

Scholium 应在 Agent 开始处理 Work 之前，根据当前 Work、selected passage 和 research request，先生成一份小型、可解释的 **Recommended Reading** 目录。目录只包含当前 Triptych 中的 Analyses 和 Topics，并直接提供可执行的批量 exact-read 请求。Agent 因此不必先猜测查询、执行 Search 和筛选结果，但在目录不完整时仍可使用现有 Search。

Topic Synthesize 同样获得初始目录，但候选只能是 Analyses。每个 Search-capable Run 另有 `agent related`：Agent 提供一至四个精确 Note 名称，Application 解析 current seeds，并依多 seed 覆盖、Connection、title／alias 与 Search-owned lexical 顺序动态重排 Analysis／Topic 候选。

将来 Works 写作中的 **Suggested Analyses** 和 **Suggested Topics** 应复用同一候选、排序、理由和 currentness owner。它以当前未保存 editor snapshot 中的选中文本或稳定输入片段为 seed，不另建 UI ranker、长期 profile 或推荐数据库。

本提案选择两个且只有两个新责任：

1. Search owner 新增一个版本化的 **Related-Content Retrieval** 合同，负责把 bounded text seed 检索为 Analyses／Topics 候选；
2. Application 新增一个 `RecommendedReadingCoordinator`，负责权限、种子、多渠道组合、去重、配额、currentness 和交付。

`RecommendedReadingCoordinator` 不是 Agent，不制定研究计划，不判断哲学立场，也不拥有 Search 语义。

## 2. 研究者任务

当前 Agent 已经能够读取 target、selected Materials，并通过 Research Context 搜索和精确阅读当前 Triptych。但它还必须自己回答一个重复出现的发现问题：

> “对当前 Note 或这些指定 Notes，我应该先读哪些 Analyses 和 Topics？”

每个 Agent 都从零开始抽词、拟定 Search query、检查命中和改写查询，会产生四种成本：

- 额外工具调用与延迟；
- 用于搜索过程而非研究判断的 context tokens；
- 不同 Agent 对同一任务产生不一致的发现范围；
- 在当前 Work 已有明确 Connections、标题提及或字词命中时，重复完成 Scholium 本可以确定性完成的发现。

目标不是取消 Agent 的 Search，而是让 Search 从“必须的第一步”变成“推荐目录不足时的后续探索”。

## 3. 当前权威与实现基线

### 3.1 已有能力

- Triptych 只含 Analyses、Topics 和 Works；Analyses 与 Topics 明确被设计为可跨 Works 复用的研究资源，见 [Foundation and Triptych](../../Docs/Specification/01-foundation-and-triptych.md)。
- 研究者选择 Action 已授权 Agent 读取任务相关 Triptych 材料；读 Work 不触发 Works 写入政策，见 [Research Actions and Workflows](../../Docs/Specification/03-research-actions-and-workflows.md)。
- `ResearchAuthenticatedRunContext` 已向 Agent 交付 Brief、Result Contract、Bounded Write Set 和 typed `next_actions`。现有 `next_actions` 已能携带完整、可直接执行的 Research Context request，见 [`ResearchAgentConnectionContracts.swift`](../../ScholiumContracts/ResearchAgentConnectionContracts.swift) 和 [`ResearchAgentConnectionOperations.swift`](../../ScholiumApplication/ResearchAgentConnectionOperations.swift)。
- Research Context 已支持 Note discovery、exact Note／section read、direct Relations、Metadata、Records、selected source Material 与窄 researcher-state 检查；它的 Source Reference Envelope 保留 owner、identity、revision、locator、scope、currentness、evidential layer 和 retrieval reason。
- Search contract v10／schema 11 已索引 title、alias、heading、`summary`、body、author、keyword、footnote 和 path，并支持显式 direct-relation query。结果已携带 role、source range、fingerprint、freshness 和 typed match reasons，见 [Connect, Search, and Recovery](../../Docs/Specification/04-connect-search-and-recovery.md) 与 [`SearchProtocolContracts.swift`](../../ScholiumContracts/SearchProtocolContracts.swift)。
- 当前 App 已能在不 flush 或 save 的情况下，从 CodeMirror 取得绑定 editor session 与 revision 的精确内存 source snapshot，供 This Note Search 使用，见 [`ScholiumApp.swift`](../../Scholium/App/ScholiumApp.swift)。
- `summary` 与 `keywords` 是 Analysis、Topic 和 Work 的唯一共享 canonical authored YAML 字段；其他未知 YAML 只无损保留，见 [Metadata and Critique](../../Docs/Specification/11-metadata-and-critique.md)。

### 3.2 Agent-only 实现后尚缺的能力

当前已具备 Related-Content Retrieval contract 3、Graph direct Connection、Search exact title／alias 与加权 lexical、typed candidate-role restriction、Work／Topic 初始目录、`agent related` 多 seed 动态排序、chunked exact-read actions 及 Application coordinator。仍未具备：

- 以 Works 未保存 editor snapshot 驱动的消费者、取消合同和界面；
- 能证明推荐减少额外 Search 但不降低必要阅读召回的评测基线。

### 3.3 不能伪装成已有能力的边界

- 现行 Search 的自由文本语法是 space-as-AND。把完整 Works 段落直接填进 `SearchRequest.query` 不是可接受的 related-content 实现。
- 现行 Search 明确拒绝 `role` query，也没有 Selected Roles 可见 scope。Related-Content contract 3 的 candidate-role restriction 是 typed operation 字段，不是隐藏 query token。
- Research Context 目前只在 Agent 显式 query 后返回证据；本提案不改为无条件全文注入。初始上下文只交付候选目录和可执行 read request，原文仍在 Agent 执行该 request 后由 Research Context 返回。
- vector search、embeddings、AI query interpretation／ranking、automatic relation extraction、multi-hop expansion 和 context assembly 目前均为 deferred。本提案不能在未作 canonical decision 时将它们描述为实现基础。

## 4. 产品行为

### 4.1 Agent 初始目录与按名查询

Work **Write／Critique** 自动获得 Analysis／Topic 候选；Topic **Synthesize** 自动获得 Analysis-only 候选。其他 Action 不自动获得目录，但所有 Search-capable Runs 可按需执行 `agent related --note <name>`，重复 `--note` 最多四次。

Agent 获得初始 authenticated Run Context 时，同时获得：

1. 一份 typed `recommended_reading` directory；
2. 一个或多个 role-accurate `when_needed` exact-read `next_action`；
3. 当候选为 Partial、Unavailable 或 Empty 时，一条明确的现有 Search 后续路线。

`recommended_reading` 只告诉 Agent 哪些 Note 值得先读以及为什么，不携带 Note 全文或机器生成摘要。`next_action` 将所有 current candidates 编码为现成的 Research Context exact-read clauses；Agent 可执行整个 batch，也可依目录只读其中一部分。

这一设计省去的是“搜索和初步筛选”，不是“读原文”。

`agent related` 只接受 current Triptych 中唯一匹配的 title、alias、filename、relative path 或 stable identity。缺失与歧义不猜测；组合结果按命中 seed 数、direct Connection、exact identity、各 seed 内 owner rank 与稳定 identity tie-break 动态排序，不暴露数值分数。

### 4.2 第二切片：Works 写作中的动态候选

在 Agent 候选质量和 owner 稳定后，同一 Coordinator 可接受 `liveWork` seed：

```text
Work identity
editor session ID
editor revision
exact unsaved source fingerprint
selected passage, when present
otherwise one bounded stable input region
```

计算不逐键触发。它在简短 idle debounce 后对最新 editor revision 发起一次异步请求；新 revision 取消旧请求或使旧 response 不可接受。caret movement 本身不触发重算，selection 只在稳定且非空时成为新 seed。

Works 界面可显示 **Suggested Analyses** 和 **Suggested Topics**，但本提案不预先决定其 Inspector、Document 或其他位置。界面位置必须在候选质量成立后，通过单独的 canonical interface decision 与完整 Works 写作旅程验证。现在不增加第四个 Inspector mode、空面板或隐式推荐状态。

## 5. 唯一 owner 与数据流

```text
frozen Action / named Note seed      live Works editor seed
            \                         /
             \                       /
              → Related-Content Retrieval ←
                 (Search owner)
                         ↓
           typed Analysis / Topic candidates
                         ↓
             RecommendedReadingCoordinator
          scope · channels · dedupe · quotas · stale
                         ↓
              RecommendedReadingResponse
                /                    \
               /                      \
Agent directory + exact-read request   future Works presentation
               ↓
       explicit Research Context read
               ↓
Agent Context Use testimony + Application validation
```

### 5.1 Search owner：Related-Content Retrieval

Search 需要一个与普通 query grammar 分开的 typed operation。建议的形状是：

```text
RelatedContentRequest
├── bounded source Note + source fingerprint
├── selected-passage and research-request focuses, when present
├── Application-bound Triptych scope
├── candidate roles = Analyses or Analyses + Topics
├── identity and lexical channel budgets
└── request ID / cancellation identity

RelatedContentResponse
├── Search contract and generation
├── Current / Stale / Unavailable / Invalid Seed
├── ordered identity candidates
│   └── exact title / alias mention + seed kind and range
├── ordered lexical candidates
│   └── matched candidate fields + selected/request/source-Note terms
└── limitations and truncation
```

这个 operation 复用当前 Note Search corpus、分词、字段、incremental generation、source mapping 和排序 owner。它不把 seed 改写成可见 Search query，不创建 Saved Search，不更改普通 Search 的三个可见 scope，也不把 `role:` 加入用户 query grammar。

当前版本只做可解释的 exact identity mention 与 lexical retrieval。selected passage 先于 research request，research request 先于完整 source Note；既有 Search 字段权重和 BM25 只在同级之后排序。embedding、LLM query rewriting 和 learned reranking 不得伪装成这个合同的实现细节；若以后引入，必须作为可独立评测、关闭和删除的新版本渠道。

### 5.2 Application owner：RecommendedReadingCoordinator

Coordinator 只负责：

- 验证 source identity、Action eligibility、seed revision、Triptych read scope 和 Workspace generation；
- 获取 source／selected-passage 到候选角色的显式 direct Connections；
- 请求 Related-Content Retrieval；
- 保留渠道 availability 和 typed reasons；
- 按固定 channel precedence 与独立配额组合结果；
- 合并同一 Note 的多个 reasons，但不合并或改写 source ranges；
- 为 current candidates 生成现成的 Research Context exact-read clauses；
- 对 Agent context 与将来 Works 表示返回同一交付中立 response。

Coordinator 不得：

- 解析 Markdown 或抽取关键词；
- 建立索引或 lexical／semantic ranker；
- 生成 Analysis／Topic 摘要；
- 推断支持、反对、重要性、真理或研究者信念；
- 扩大 Triptych 或 Run 可读 scope；
- 把推荐、交付或阅读自动记为 Context Use；
- 将 response 持久化为 Note、Record、Saved Search、profile 或 portable `.scholium/` 状态。

## 6. 候选渠道与排序

### 6.1 当前 Agent-only 渠道

| 层级 | 渠道 | 解释 | 不能推出 |
| --- | --- | --- | --- |
| T0 | scope、role、currentness、availability | 候选资格门，不是相关度分数 | 新内容比旧内容更重要 |
| T1 | Work／passage direct Connection | 保留 relation predicate、direction 和 source occurrence | 关系为真或候选支持 Work |
| T2 | Analysis／Topic title 或 alias 在 seed 中精确出现 | 保留 seed kind、identity kind 与 Work field | 研究者有意建立关系 |
| T3 | Related-Content lexical result | 保留 candidate matched fields、source ranges 和 Search-owned rank reason | 两份 Note 立场相同或构成证据 |

T1–T3 有独立配额：direct Connection 为 4，exact title／alias 为 3，lexical overlap 为 4；最终目录上限为 8。Application 以 T1 → T2 → T3 的固定顺序合并，但不把不同渠道压成一个对研究者或 Agent 可见的“相关度”分数。同一 Note 只出现一次并保留全部 typed reasons。同一 channel 内使用 owner-provided ordering 和稳定 identity／title／path tie-break。

### 6.2 后续渠道

以下内容不属于第一版：

- verified prior Context Use 作为独立 continuity reason；
- Analysis 的 citation／co-citation 发现；
- embedding 或其他 semantic similarity；
- LLM query expansion 或 reranking；
- 研究者明确推荐反馈。

每个后续渠道必须有独立 owner、availability、预算、解释、评测和删除路线。打开、滚动、停留、忽略、选择或沉默都不能隐式训练它们。

## 7. 交付合同

### 7.1 Reading seed

```text
RecommendedReadingSeed
├── kind: frozenWorkAction | liveWork
├── Work identity and role
├── seed source fingerprint
├── source range or bounded text region
├── research request, only for frozenWorkAction
├── editor session + revision, only for liveWork
└── request identity
```

`frozenWorkAction` 只来自已准备 Run 的 exact target、selected passage 和 research request。`liveWork` 只来自当前窗口的 exact editor session，不要求先保存 Work，也不成为 Search 或研究历史。

### 7.2 Recommendation response

```text
RecommendedReadingResponse
├── request ID
├── seed identity + fingerprint + range
├── Triptych + authorized scope
├── Search contract + source generation
├── overall and per-channel availability
├── result and byte budgets
├── candidates
│   ├── Analysis | Topic identity
│   ├── title + relative path
│   ├── source fingerprint
│   ├── ordered typed reasons
│   ├── reason-specific source locator or seed field/terms
│   ├── currentness + limitations
│   └── exact-read clause
└── truncation / cancellation state
```

Response 不包含内部数值分数、机器生成摘要、候选全文、absolute path、bookmark、Session secret、跨 Triptych identity 或 write capability。

## 8. Run、Research Context 与 Context Use 生命周期

1. Action preparation 按现行规则 flush 并冻结 current Work target、selected passage、research request 和权限。
2. Run owner 只持久 recommendation seed 所需的已有 frozen Action facts，不持久 response、排名、候选或 preview。
3. 产生 authenticated Run Context 时，Coordinator 对当前 Workspace generation 计算一次 response。失败不伪装为 Empty，也不使 Run 丧失现有 target-read 和 Search 路线。
4. Agent 收到 directory 和 ready-to-send exact-read request。只有 Agent 执行该 request 后，Research Context 才交付精确原文。
5. 每个 exact read 重验 Run、Session、scope、identity、fingerprint 和 locator；变更或缺失返回 Stale／Unavailable，不读取替代文档。
6. Recommendation、directory delivery、exact read 和 Context Use 是四个不同事实。Record 只保存 Agent 明确声明实际使用、且被 Application 对 current owner 验证过的 references。
7. `reload` 依 frozen Work seed 重建 current response；如果 target 已变，仍按现行合同返回 `stale_run`，不为旧 Run 换入新 Work。
8. Continue Research 创建新 Run，并以它自己的 current target、request 和 scope 重新计算；不继承父 Run 的 response、rank、cache 或 availability。
9. End、Session expiry、re-pairing 和 cancellation 沿用现有 Run 生命周期；Coordinator 不得创建第二 Run 或恢复权威。

## 9. Works 实时输入边界

- `liveWork` seed 只存活于请求和当前窗口内存；不写入 Application Support、vault、portable `.scholium/`、Saved Search、Record、log 或 analytics。
- 应用只能向当前 Triptych 的 Search owner 交付 bounded seed；不读取跨 Triptych 内容，不调用网络服务。
- 每个 request 绑定 window、editor session、editor revision 和 source fingerprint。窗口、tab、workspace 或 Note 改变使其取消或不可接受。
- 计算和结果更新不得改变 editor focus、selection、marked text／IME、Undo、scroll、autosave 或 conflict state。
- 显示候选不建立 Connection，不添加 Action Material，不写回 Work，不记录为阅读、使用、重要或研究者接受。
- 第一个 Works UI 不提供隐式训练、全局兴趣 feed 或“AI 相关度”分数。

## 10. 失败与降级

| 状态 | Agent 交付 | 未来 Works 表示 |
| --- | --- | --- |
| Current | 交付 directory 与 exact-read request | 显示 current candidates |
| Empty | 说明当前 seed 没有可解释候选，保留 Search | 诚实的空状态，不生成泛化建议 |
| Partial | 列出可用渠道与 limitation，要求 Agent 必要时 Search | 保留可验证候选并显示缺口 |
| Stale | 不交付可执行旧 read clause；`reload` 或新 Run | 丢弃旧 response 并等待最新 revision |
| Unavailable | 保留 target read 和 Search，说明推荐不可用 | 显示可重试状态，不伪装成零结果 |
| Invalid Seed | 不猜测截断或替代 seed | 等待可用的 selection／输入区域 |

任何推荐失败都不改变现有 Action 的 write set、Result、End、recovery 或 Search 能力。

## 11. 明确不建设的东西

本提案不建设：

- 新的 durable memory object、research-handoff packet 或哲学 ontology；
- 第二 Markdown parser、Search index、Graph 或持久 recommendation store；
- 全局 Related Notes UI、feed、第四个 Inspector mode 或新窗口；
- 从点击、打开、滚动、停留、忽略、编辑频率或沉默学习的研究者 profile；
- 把 lexical／semantic similarity 命名为 supports、opposes、accepted、important 或 consensus；
- 自动把候选加入 Materials、Bounded Write Set、Context Use、Connection 或 Work source；
- 无预算的全文注入、隐藏 prompt 拼接或不可检查的研究摘要；
- 第一版的 embeddings、LLM reranking、automatic relation extraction 或外部网络依赖。

## 12. 渐进实施顺序

### Phase 0 — Canonical decision（已完成）

在任何实现前，先批准：

- Work Write／Critique 可含 Analysis／Topic、Topic Synthesize 可含 Analysis-only 非证据性目录；
- Search-capable Run 可按 current Note 名请求动态排序目录；
- Research Context 原文仍只在 Agent 显式执行 exact-read query 后交付；
- Search owner 可新增 typed Related-Content Retrieval，而普通 Search grammar 和可见 scopes 不变；
- 同一候选合同可在后续接受 ephemeral Works editor seed；
- 推荐不建立读取、使用、支持或研究者接受。

Owning canonical chapters 已完成该窄切片决策；本文不取代它们。

### Phase 1 — Related-Content Retrieval contract 3（已完成）

先用 disposable synthetic Triptych 建立 Related-Content Retrieval 的纯合同、clean-rebuild 与 incremental-update 夹具：

- Analysis／Topic／Work source、selected passage 与 research request → 独立 exact identity 和 lexical candidates；
- role restriction、currentness、cancellation 和 bounded result budget；
- 无结果、无效 seed、stale generation 和 provider unavailable 失败关闭。

当前实现复用现有 Note projection、identity metadata 与 FTS，没有第二索引。selected passage、research request、完整 source Note 作为有序 seed groups 保留在 lexical reasons 中。

### Phase 2 — Agent end-to-end slice（已完成本地实现与 owning tests）

将 Coordinator 接入 Write／Critique 与 Synthesize Run context，增加 Graph direct channel、固定跨渠道顺序、独立配额、role-bounded `recommended_reading` 和 exact-read action；`agent related` 复用同一 coordinator，并在 Application 合并一至四个 exact seeds。同一切片覆盖 pairing、direct start、reload、Session、End、Continue、Context Use 和 App／CLI parity。

验收点是：Agent 在不发起 Search 的情况下可批量读取候选；推荐失败时原有 Search 和 Run 生命周期仍完整。

### Phase 3 — Works live seed

复用当前 exact unsaved-editor snapshot 模式，新增 `liveWork` seed 和 per-window cancellation／stale contract。先以无 UI 夹具验证 selection、bounded input region、IME、中英混合输入、大 Work、rapid edits、tab／workspace switch 与多窗口隔离。

只在候选质量和性能达到预设门槛后，再作界面位置决策与 UI 实现。

### Phase 4 — Optional semantic experiment

在 lexical 基线和人类验收稳定后，才离线比较 embedding、contextual retrieval 或 reranking。该实验不改变 T1／T2 结果，不默认进入产品，也不保存研究者行为。

## 13. 验证与验收

### 13.1 Retrieval correctness

- 同一 seed 与 Search generation 产生确定性相同结果；
- clean rebuild 与 incremental update 等价；
- 候选始终只是 current Analyses／Topics；
- 每个 reason 能精确还原实际 retrieval path；
- 每个 locator 能读回同一 fingerprint 的 exact source；
- stale、missing、ambiguous、invalid 和 unavailable 不会产生 current 可读候选；
- 相似文字但立场相反、引用但不支持、同名异义和中英混合表达都有固定夹具。

### 13.2 Agent effectiveness

与现行“只提供 Search template”基线对比：

- 首次读到必要 Analysis／Topic 的时间；
- 额外 Search 次数与查询改写次数；
- tool calls、交付 bytes 和 total context tokens；
- gold necessary-source Recall@budget 与 irrelevant-read rate；
- 对作者、立场、异议、证据角色和研究者判断的误归属率；
- Partial／Unavailable 时 Agent 是否能识别目录不完整并继续 Search。

推荐目录只有在“显著减少搜索成本，且必要来源 recall 与归属准确性不降低”时才成立。点击、读取次数或 Agent 主观评价不能单独证明研究收益。

### 13.3 Works human acceptance

未来 Works UI 需要独立人类验收：

- 候选是否在研究者需要时出现，而非持续打断写作；
- 理由是否足以识别错误命中；
- 更新是否保持 focus、selection、IME、Undo 和 scroll；
- keyboard、pointer、Full Keyboard Access、VoiceOver 与 200% interface text 是否都可用；
- 推荐是否增加错误信任、检查负担或对文档主体性的干扰。

Agent effectiveness 不替代 Works UI 验收，UI 可用性也不替代 Agent 的研究质量。

## 14. 已更新的正式权威

本次窄切片已经更新：

1. [Research Actions and Workflows](../../Docs/Specification/03-research-actions-and-workflows.md)：定义 Work Write／Critique、Topic Synthesize 的 role-bounded 目录、exact-read action 与按名 related command；保留显式读取和 Context Use 规则。
2. [Connect, Search, and Recovery](../../Docs/Specification/04-connect-search-and-recovery.md)：定义 contract 3、Graph direct Connection、Search identity／weighted lexical、candidate roles、多 seed Application ordering、budgets、freshness 和 App／CLI 边界；继续 deferred vector／AI ranking。
3. [Implementation Architecture](../../Docs/IMPLEMENTATION_ARCHITECTURE.md)：在 Search owner 与 Research Action owner 的现有边界内记录 Related-Content Retrieval 与 `RecommendedReadingCoordinator`，不新建 runtime 或持久 store。

Works 界面位置获批准时，才更新 [Document and Research Interface](../../Docs/Specification/07-document-and-research-interface.md) 与 [Accessibility and Adaptation](../../Docs/Specification/09-accessibility-and-adaptation.md)；Agent-only 第一切片不预建界面规则。

## 15. 未决定问题

1. `liveWork` 在没有 selection 时应以当前 Markdown block、最近稳定段落，还是受限滑动窗口为 seed？
2. Works UI 应与 Agent 使用同一完整 response，还是由同一 owner 在更小表示预算下取子集？
3. 哪一组非私人哲学 Works／Analyses／Topics 任务可作为人类 gold set？

## 16. 相似机制与适用限制

- [Retrieval-Augmented Generation](https://papers.neurips.cc/paper/2020/file/6b493230205f780e1bc26945df7481e5-Paper.pdf) 证明了“query → 外部可检查材料 → generation”的基本模式，但其 Wikipedia dense index 不是 Scholium 的权威或数据模型。
- [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) 区分了运行前 retrieval 与 Agent 的 just-in-time 探索，并说明 hybrid 方案可用预先发现换取速度，再以按需读取节省 context。这是本提案“directory + exact read”的直接机制先例，不是 Scholium 产品验收证据。
- [ReadAgent](https://deepmind.google/research/publications/74917/) 用 gist memory 与返回原始 passage 的行动管理长文阅读。Scholium 只借用“先给索引性信息，再读原文”，不使用机器 gist 代替 authored source。
- [RepoCoder](https://aclanthology.org/2023.emnlp-main.151.pdf) 表明当前未完成输入可以作为仓库级 retrieval seed，也表明单次 seed 可能不足。它支持保留 Agent 后续 Search，不足以证明代码相似性可等同哲学关系。
- [Contextual Retrieval](https://www.anthropic.com/engineering/contextual-retrieval) 报告了文档级 context、BM25、embeddings 和 reranking 的组合实验。它为后续对照实验提供方法，不授权第一版引入模型生成 chunk context 或向量依赖。
- [Remembrance Agent](https://cdn.aaai.org/Symposia/Spring/1996/SS-96-02/SS96-02-022.pdf) 说明了当前写作文本可驱动少量非打断建议。其持续 cursor-local 监控、数值相关度和广泛个人记忆范围不适用于 Scholium。

这些来源只证明可比较的 retrieval 和 reading 机制。它们都不能证明哲学相关性、来源忠实性或 Scholium 中的人类研究收益。
