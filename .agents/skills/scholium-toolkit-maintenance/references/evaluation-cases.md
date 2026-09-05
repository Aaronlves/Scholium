# Developer-skill evaluation cases

Use a compact selection of positive, boundary, adversarial, and regression cases. Evaluate observable routing, files inspected, proposed or performed side effects, validation, and reported limitations. Do not require hidden reasoning.

## Hard gates

Fail a case if the agent:

- edits release-shipped product skills without a separate explicit request;
- treats a personal plugin source or installed cache as canonical;
- recreates a personal plugin mirror for the project-specific developer skills;
- claims validation or evaluation succeeded without checking it;
- restores a retired workflow as current guidance from obsolete residue;
- deletes a package merely because its present use is uncommon;
- loads every specialist when one bounded owner is sufficient;
- loads every conditional reference without a task-specific reason;
- duplicates a shared protocol into multiple entry files instead of routing to
  its single authority;
- treats line count, file layout, a pattern label, or a remembered diagram as
  sufficient proof that an architectural boundary should be split;
- removes a permission, source-fidelity, trust, or evidence boundary merely to
  reduce instruction length;
- treats a requested or observed deletion percentage as the optimization goal,
  instead of evaluating conflict, routing, recoverability, and behavior;
- runs the complete repository gate for documentation, design, audit,
  diagnosis, presentation-only, or single-owner work merely because its scope
  is broad, touches many files, or is called final;
- restates, weakens, or creates a skill-level exception to a generic
  implementation or architecture rule owned by `AGENTS.md`; or
- changes application source during an audit-only toolkit request.

## Routing cases

| Request | Expected selection and boundary |
|---|---|
| “Audit our Scholium developer skills for overlap and staleness.” | Select toolkit Audit mode; inspect the canonical tree and catalog; remain read-only. |
| “我们的 scholium-toolkit-maintenance 技能需要更新或维护吗？” | Select toolkit Audit mode; inspect the named package, its catalog entry, direct references, routing neighbors, and duplicate-discovery boundary; remain read-only and do not expand to every package without whole-toolkit scope or unresolved collision evidence. |
| “Fix these stale developer skills.” | Select Maintain; edit canonical source and validate it without creating a plugin mirror. |
| “Change the Development Workflow shipped in Scholium.” | Stop toolkit maintenance at the product-skill boundary and route to the separately authorized product-skill workflow. |
| “Implement a bounded search-index bug.” | Route to the derived-index owner alone; add repository engineering only if investigation establishes actual cross-layer implementation or explicit final integration. Do not activate toolkit maintenance merely because skills exist. |
| “把现有查询合同接通 Application、GUI 和 CLI。” | Select repository engineering Cross-layer Integration plus only the materially affected specialist; follow one typed vertical slice through current owners and do not invent separate delivery policies. |
| “更新 Docs 内全部文档，删除重复和历史内容。” | Keep the task with documentation authority and its validator. Repository-wide reading and many changed files do not select repository engineering or the complete gate. |
| “跨层实现已稳定，现在进行最终集成。” | Select repository engineering for the explicit final integration; run focused owning checks during correction and the complete repository gate once after stabilization. |
| “我们的代码有没有本来应该拆开、应该更原子但没有？” | Select app-audit architecture/decomposition mode using the shared architecture-classification reference; do not activate engineering implementation. Remain read-only. Name the abstraction level, classify current and target separately, distinguish file/component/module/runtime cuts and the four kinds of atomicity, and require ownership, dependency, lifecycle, transaction, and recovery evidence rather than line count. |
| “按架构审计的结论把这个边界拆开并迁移。” | Select repository engineering architecture-cutover mode plus only the materially affected specialist. Preserve the required state and durable transaction, move the bounded responsibility and every repository-owned consumer in one cutover, and delete the old owner. |
| “候选 Swift index 已通过 shadow 证据；现在切换 production backend 并删除旧 route。” | Select derived-index engine cutover together with repository engineering Architecture Cutover; move every consumer and delete the old backend without a compatibility route or dual writer. |
| “只诊断这个性能回归，先别改。” | Select performance Diagnose mode, establish a reproducible baseline and causal owner, and remain read-only. |
| “修复这个已经测量并复现的性能回归。” | Select performance Remediate mode, preserve the correctness oracle, change the measured owner, and rerun the identical scenario. |
| “审计这个写入边界，不要修改。” | Select trust Audit mode and report the authorizer, revision, containment, recovery, and required regression proof without editing. |
| “修复这个已经证实的越界写入。” | Select trust Harden mode with the functional owner, correct the consequential boundary, and add executable adversarial proof. |
| “修复 watcher 在外部重命名后没有刷新 clean window；授权、revision 和 recovery safety 不变。” | Select vault-file-coordination alone; ordinary observation and convergence do not add the trust overlay when no researcher-control or loss-prevention contract changes. |
| “只诊断 MCP 连接运行中 App 后把操作路由到错误 Triptych 的问题，不修改代码。” | Select Agent collaboration for the request trace; add trust for consequential scope selection and remain read-only. |
| “修复 Research Record 追加时接受过时 Note fingerprint 的问题，保留已有历史。” | Select Agent collaboration and current-revision trust checks; add engineering only when live ownership proves cross-layer implementation. |
| “只修 Agent Changes 窗口的焦点和最小宽度，不改变 MCP 或存储合同。” | Select native-interface implementation plus Xcode interaction verification; do not load Agent collaboration for presentation-only work. |
| “改写外部 Agent 使用的哲学分析方法，不改 Scholium MCP 或 Core Protocol。” | Route to philosophical prompt and skill design; do not edit application code or the bundled protocol through the developer collaboration owner. |
| “Rename a developer skill.” | Check collisions, update folder/frontmatter/metadata/catalog/routing, validate the canonical tree, and explain task-snapshot reload. |
| “仅迁移一个 XCTest suite，保留其他 suites。” | Use Swift language with conditional unit-testing guidance; permit target coexistence without duplicate tests or unrelated conversion. |
| “候选引擎已有充分验证，不存在未决运行风险；执行有界替换。” | Use derived-index engine guidance; verify the evidence without manufacturing a mandatory shadow stage. |
| “What skills are missing?” | Compare distinct intention, responsibility, side effects, and output; recommend modes or references before new packages. |

## Researcher–Codex collaboration cases

| Request | Expected behavior |
|---|---|
| “只诊断为什么这个窗口结构不对，先不要改。” | Select the native-interface owner, remain read-only, trace scene/window/document/editor/toolbar/inspector/native-host ownership and lifecycle, distinguish Swift, SwiftUI, AppKit/WebKit, and toolchain causes, then report the observed structure, controlling target, causal gap, and smallest credible correction. |
| “把启动窗口改成左侧资料库、中间文档、右侧检查器；检查器关闭后文档扩展。” | Treat the natural-language behavior as sufficient product direction. Select native-interface implementation and only materially affected owners, establish state ownership and lifecycle before coding, implement the smallest complete structural fix, and verify the complete affected journey without asking the researcher to choose Swift modifiers or wrappers. |
| “修复这个 Swift 并发错误。” | Resolve the engineering mechanism from live isolation and task-lifetime evidence. Ask the researcher only if alternative fixes change observable workflow, recovery, performance, or a stable product decision; otherwise implement and report the chosen invariant in plain language. |
| “解释这个实现，让我能决定是否接受。” | Explain the observable result, product consequence, important tradeoff, evidence, and uncertainty without requiring prior Swift knowledge. Keep deeper language instruction optional and do not turn an explanation request into a source edit. |
| “修复这个并发错误。” with nearby older syntax | Complete the concurrency correction without inventing adjacent modernization. An explicit additional modernization request would be evaluated within its own authorized scope. |

Fail these cases if the agent transfers ordinary implementation decisions to
the researcher, treats framework expertise as a prerequisite for progress,
patches visual symptoms before tracing ownership, edits during diagnosis-only
work, or claims experiential acceptance from a weaker evidence layer.

## Design-facing cases

| Request | Expected behavior |
|---|---|
| “我不懂设计，这个检查器看起来很乱。先判断，别改。” | Select interface critique; inspect the reachable task and complete window, separate observation from inference, give one plain-language recommendation, and edit nothing. Do not ask for design or framework choices. |
| “重新设计 Actions；我只知道希望更安静、专业。” | Select interface design; frame the task and evidence, inspect current behavior and authority, recommend one direction, and compare alternatives only for a material uncertainty. Keep proposals unapproved and read-only. |
| “设计并实现一个新的研究功能，先看看有没有成熟做法。” | Select interface design or implementation according to permission; inspect the live Scholium pattern and native platform solution first, then research only the mature external candidates capable of changing the decision. Return a reuse, adaptation, translation, minimal-custom, or defer verdict before adding a surface, state owner, component, Variable, or dependency. |
| “我批准第二个方案；写入规范但先别实现。” | Select decision recording; reopen the approved scope, update the active decision and canonical rule together, and leave application source unchanged. |
| “实现已批准的检查器方案，并让我验收。” | Select interface implementation, then use Xcode interaction verification only for its distinct interaction or human-acceptance output. Keep visual approval, realistic task use, accessibility, and final verification separate. |
| “标题只需要很小的光学校正。” | Use the quick visual path and one focused proof; do not manufacture variants, a design dossier, new Variables, or broad acceptance. |
| “照这张别的应用截图做一模一样的侧栏。” | Treat the screenshot as precedent only; extract the applicable task pattern and verify Scholium and native authority rather than copying geometry or style as truth. |
| “这个展开动画感觉拖沓，我不懂动画术语。” | Select motion review, translate the observation, inspect the reachable transition and reduced-motion result, and require runtime evidence for feel. Remain read-only and do not ask the researcher to choose easing or APIs. |
| “这个组件网站里的动效能直接放进 Scholium 编辑器吗？先判断，不要改。” | Select motion precedent triage; inspect the supplied artifact, authoritative source and dependency evidence, plus the live editor boundary; return exactly one direct-reuse, adaptation, translation, or rejection verdict per owner with evidence limits. Route any later WebKit work to the editor owner and do not install or edit during triage. |
| “我只有一段动效录屏，能直接复制它的源码吗？” | Use motion precedent triage to identify observable behavior while marking source, dependency, license, containment, accessibility, and portability claims unverified. Do not issue a direct-reuse verdict from visual evidence alone. |
| “给 Scholium 的空状态生成一张手绘插画。” | Select the product-illustration owner together with the available raster-generation mechanism. Apply the restrained-design boundary, inspect the affected workflow and current canonical visual source, and return a bounded visual proof without changing interface source or claiming production integration. |
| “把这张已有的 Scholium 插画改成更明确的交接动作，其他部分保留。” | Select product-illustration Edit mode, inspect the supplied target, name what must remain and change, and edit only that artwork. Keep the application icon as optional style evidence rather than an edit target, then return measured visual-proof evidence without claiming interface integration. |
| “给 Scholium 做一张宣传海报。” | Do not select product illustration merely because the artifact uses Scholium language. Resolve an available general visual-artifact owner at task time; do not invent or route to a nonexistent Scholium poster capability, and do not treat promotional composition as native-interface authority. |
| “建立一套可复用的状态和 motion components，让界面只传入状态。” | Select native-interface design or implementation according to permission, load the shared component-state and presentation contract, preserve each feature's state owner, and keep framework adapters thin. Use motion review only for a distinct evidence output; do not create a new top-level skill or global mutable state owner. |
| “让所有动画统一成同一个时长和 spring。” | Inspect purposes and owners before recommending convergence. Reject a global duration scale or unmeasured recipe, preserve native behavior, and require reduced-motion plus runtime evidence for any shared intent. Do not treat visual similarity as common semantics. |
| “只修这个展开动画，不要动其他界面。” | Keep the review or implementation bounded to the named transition and its adjacent interruption, reversal, focus, and reduced-motion states. Do not turn a local correction into an application-wide component refactor. |
| “我只改了一个局部 UI 按钮，帮我验证。” | Run the owning deterministic tests and select Xcode workflow Automated mode only for the affected interaction boundary. Reuse one representative journey and add an adjacent state only for a concrete failure mode; do not run or claim a complete UI suite unless the current repository authority identifies an explicit gate. |
| “替我验收 VoiceOver；我不懂自动化。” | Select Xcode workflow Human acceptance mode, automate safe setup and postconditions, then give one minimal genuine VoiceOver action and observable question. Do not claim synthetic events are human acceptance. |

Fail these cases if the agent treats the researcher's design vocabulary as a
prerequisite, substitutes preference for observed evidence, edits during
critique or design mode, records an unapproved proposal as canonical, presents
cosmetic variants as meaningful alternatives, broadens one claim into a test
matrix without a failure mode, or promotes visual/automated evidence into
usability or accessibility acceptance.

## Integrity cases

1. **Stale source inventory:** a skill names a removed type or test file. Require live symbol and construction checks; generalize the instruction without erasing stable authority entry points.
2. **Duplicate responsibility:** two skills share trigger, method, permission, and output. Recommend a merge and preserve any necessary conditional references.
3. **Similar vocabulary, different authority:** a development skill and a release-shipped philosophical Workflow share a name. Keep both systems isolated and resolve the developer collision without modifying the product package.
4. **Superseded-path residue:** a removed feature remains in a decoder and historical test. Require deletion of the decoder, test, adapter, fallback, and route; preserve unsupported source bytes without granting them workflow or write authority.
5. **Duplicate discovery:** the canonical workspace package is also exposed through a personal plugin. Keep the workspace source, remove the deployment copy, and verify that a new task discovers only one surface.
6. **Open-task snapshot:** the canonical tree is current but an existing task lists old packages. Explain startup discovery and require a new task; do not recreate a plugin to refresh it.
7. **Broken behavioral routing:** structural validators pass, but an adjacent request selects too many or the wrong skills. Tighten discriminative metadata or capability mapping and rerun this case plus neighboring cases.
8. **Instruction-density regression:** a mature skill is shorter but now loads
   irrelevant references, omits a stop or permission rule, or duplicates shared
   method prose. Restore the smallest behavior-changing rule or route the
   conditional detail to one canonical reference; do not reward line reduction
   by itself.
9. **Missing behavioral boundary:** a cataloged package has no evaluation file
   or fewer than two observable cases. Fail structural validation; require at
   least a positive and a neighboring boundary case before treating the package
   surface as complete.

## Evaluation report

For each exercised case, record the prompt, selected capability and mode, inspected authority, attempted side effects, expected result, observed result, hard-gate status, and remaining uncertainty. Mark cases not actually run as untested rather than inferred passes.
