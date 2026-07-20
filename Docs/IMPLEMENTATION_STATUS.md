# Scholium Implementation Status

**Audited:** 2026-07-20
**Target authority:** [SCHOLIUM_SPEC.md](SCHOLIUM_SPEC.md)
**Scope:** current reachability, verification evidence, migration debt, and open
acceptance only. This ledger cannot redefine the target specification.

## Reachable target behavior

| Area | Current reachable boundary |
| --- | --- |
| Triptych and storage | Multiple registered Triptychs with independently chosen Analyses, Topics, and Works; one Triptych per window, independent windows, portable `.scholium` control state beside Works, and machine/derived state in Application Support. The atomic v2 registry does not import the retired single-workspace registry. |
| Exact source | `NoteDocument`, targeted YAML edits, transactional autosave, readback, external-conflict handling, and traversal/symlink rejection preserve authoritative Markdown. Current roles re-encode canonically; malformed or unknown current fields fail without rewriting source. |
| Lifecycle and deletion | Create, duplicate, move/rename, Set Aside, Trash, exact-path Put Back, and permanent deletion route through `VaultRepository`; `Set Aside/<path>` moves to canonical `Trash/<path>`. Deletion removes the note, current Work Critique, versions, identity, associated research records, and affected checkpoints. A durable journal restores pre-commit state or completes post-commit privacy cleanup; a concurrently recreated path is preserved for explicit recovery. |
| Move and import | Confirmed moves preflight destination and incoming-link revisions, rewriting only links resolved identically by supplied and fresh graphs. Stable identity and app records follow confirmed moves or reconciled external renames; ambiguity requires confirmation. Unclassified import copies the original, remains editable, and classifies into any vault. Multi-file failures roll back revision-safe exact bytes; incomplete cross-filesystem rollback produces an external recovery record and visible recovery surface. |
| Review and Critique | Analyses/Topics have fingerprint-bound Human Review, required concise Review Note, drafts, and anchored Comments; no whole-note Comment fallback exists. Works have one attributed current Critique under `Works/Critiques`, read-only in Scholium but externally editable. It may move only within Critiques/Set Aside/Trash and cannot be duplicated as another current Critique. Provenance and findings bind the target fingerprint and navigate only unambiguous passages. Earlier-round chronology and Accept/Reject/Rebut dispositions remain unimplemented. |
| Research Functions | The editor Strip exposes the role-valid function sets from the specification. Typed panels fix Target and choose read-only Materials, scope, Comments, and Fidelity checks; removed omnibus/duplicate entry points stay unreachable. Dialogue is nonmutating unless promoted. Develop, Revise, Manuscript, and Critique checkpoint; Review and Fidelity do not. |
| Conditional methods and Fidelity | A same-run read-only preflight persists the normal run, checkpoint, and Dialogue/Critique record; `function select-resources` finalizes explicit resources, including an empty base-only selection, without changing their identities. Write runs record the exact final revision as Awaiting Fidelity and accept only a validated independent child; direct outcomes are rejected, missing checks are Unverified, changed inputs become stale, and exact evidence keys reuse committed audits without implying background agent execution. |
| Recovery and chronology | Self-contained external checkpoints support latest-ten automatic retention, manual retention, comparison, selective/full restore, and Finder access; pre-restore safety creation cannot evict its source. Research Record is a separate nonmodal utility for Human Review, anchored Comments, Dialogue, current Critique association, and provenance—not checkpoints. Reopen/Inspector independence and both localization catalogs are automated; live tab-following and manual localized accessibility remain open. |
| Application and CLI | GUI and CLI use the same Application capabilities and trust rules. Each CLI invocation creates one snapshot runtime; existing-note mutations require current SHA-256. App/CLI import only Contracts and Application, Core stays internal, one live app runtime has one accepted event subscription, and per-window controllers own independent document/research presentation state. |
| Connections, Search, and Attention | One workspace `GraphSnapshot` owns canonical Vector-Link v1 resolution; neutral/transitive paths never become evidence and legacy typed syntax remains exact with diagnostics. Shared SQLite FTS5 covers GUI/CLI and Unicode/CJK. Attention is limited to the specified structural, review-currency, connection, explicit-reliance, metadata, and identity conditions; items are dismissible, duration is Triptych-local (default seven days), and deadlines are machine-local. |
| Editor | CodeMirror Source/Live Preview and sanitized Read use bundled document fonts, protected snippets, callouts, footnotes, semantic tables, a pinned offline KaTeX runtime, and one bounded internal-preview presentation. Read and inactive Live tables share one stylesheet, semantic header cells, column alignment, local horizontal overflow, and inline Markdown projection; entering a Live table reveals exact source. Read and Live footnotes share one stylesheet, numbered references, first-reference ordinals, logical-direction spacing, a semantic end section, and preserved nested list/quotation/fenced-code blocks, including nested callout/table/math components; activating a Live endnote reveals its exact definition source. The same safe fragment adapter renders only the requested footnote definition in its preview. Read and Live also share semantic color/rhythm variables, document measure/scale/inset configuration, Callout CSS, mathematics, and preview styling. Swift resolves neutral/Vector-Link preview authority from the canonical graph; Read uses hover/focus, Live uses Command-hover plus a context-menu route. The typed identity/generation-checked bridge performs full-buffer reconciliation, exact CRLF and Unicode preservation, bounded recovery, deterministic content-process reload, and fingerprint-bound semantic scroll restoration with a normalized fallback. After first editor allocation, one persistent Host keeps committed Read and the retained CodeMirror surface mounted; presentation changes only visibility, interaction, accessibility exposure, and focus. Focused commands target only the active session. TypeScript, WKWebView, and isolated QA cover exact transforms, guarded structures, undo/redo, semantic parity, math, tables, footnotes, previews, mode chrome, semantic scroll reconstruction, recovery, commit-before-Search, byte-exact dirty-buffer recovery, and retained Host state; real assistive technology, text services, CJK IME, appearance, visual parity, retained-surface memory, and sustained performance remain open. |
| Properties and Zotero | Per-vault profiles control order, editable allowlists, and disclosure; `research_unit` has a role-neutral Research Status editor. Zotero is localhost-only/read-only. Inspector lookup follows the specified identity order, refuses ambiguity, shows only the current Analysis item or unique items from outgoing linked Analyses, excludes backlinks/transitive/library-wide data, and offers only Open in Zotero—never attachment enumeration/opening. |
| Product Skills | Protected typed resources reject traversal/symlink escape; package revisions cover all bounded resources and assembly records only loaded conditional resources. Exactly five Workflow packages remain; Dialogue is System infrastructure and Human Review has no Skill. Source Analyzer (`analyze`, no Research Function), APA 7 verification, and Prose Control are opt-in copy-on-adoption Researcher Skills, not automatic or universal authorities. Core Protocol makes packages philosophy-facing, truth-pursuing without claiming automatic truth, fidelity-caring, and knowledge-base-constructing; CLI/file/metadata/MCP remain subordinate mechanisms. |
| Research Guidance | Compatible Triptych Skills may replace, supplement, or contribute exact Practices to a function through revision-checked bindings; the Strip sees no package IDs. Citation Fidelity requires an explicit package/style binding. Opted-in local Skills support full-package proposal, comparison, validation, attributed evaluation, confirmation, atomic replacement, snapshots, and guarded recovery using descriptor-relative no-follow I/O; bundled packages remain immutable. |
| Dialogue and MCP | Dialogue persists per-Triptych defaults and an immutable request-time response contract: Academic Outcome is mandatory and five modules optional; Practices cannot change scope or permissions. The external Zotero MCP descriptor is separate from the built-in reader; ordinary status reports configuration and only explicit `--probe` runs the read-only initialization lifecycle. |

## Adopted boundaries with remaining acceptance work

| Boundary | Implemented evidence | Still open |
| --- | --- | --- |
| Localization | English default; complete `Localizable.xcstrings`/`Interface.xcstrings` zh-Hans tables; compiler-synchronized typed formats; validation of coverage, placeholders, state, and compilation; outer app bundle exposes both languages. Packaged zh-Hans QA covered Bootstrap, vault/Library/Attention labels, and native accessibility localization. Research content, paths, exact Markdown, and Skill names remain verbatim. | Researcher terminology review, long labels, and broader manual accessibility. |
| Beta app handoff | Copies immutable instructions before explicit app choice, stores one app-wide security bookmark, opens the app with no research arguments, and offers Copy Only, Choose Another, and Forget. Focused tests cover ordering, cancel/failure, replacement, forgetting, and persistence. | Packaged sandbox launch, Full Keyboard Access, VoiceOver, localization, and visual acceptance. |
| 1.0 Codex handoff | Target requires a new task at the exact root with locator-only composer, explicit researcher submission, copy fallback, and no execution claim. | No availability/root checks, new-task adapter, composer, or Codex acceptance exist. Run with Codex remains a separate 2.0 decision. |
| Research Status | Role-neutral targeted editor preserves absent/declared/invalid states and unrelated bytes. New Analysis offers Declare Now/Not Yet; Not Yet writes nothing and blocks only Complete Review. Focused tests exist; existing notes are not migrated. | Final visual, accessibility, and repository verification. |
| Time and Analysis metadata | Creation/modification times are app History, absent from default profiles and repository mutations; existing timestamps remain exact custom YAML. Debate Importance is an optional 0–10 whole number paired with exact Debate Scope, has no pass grade, and replaces Project Relevance only in typed defaults. | No migration or normalization of existing custom keys. |
| Long-source analysis | One source-level Analysis can accumulate bounded units through Research Status. Source Analyzer is an independent copy-on-adoption Skill, not a Workflow/Strip action; note mutation remains separately authorized. | Dedicated long-source progress presentation. |
| Recommended Bibliography | Fixed across Library scopes; records survive non-Analysis selection, support goals/purpose, retain prior results on refresh failure, accept zero results, discriminate conservatively, and persist atomically without Markdown/Zotero mutation. Controller, CLI, and disposable UI automation cover routing/transport. | Preparation still binds an Analysis rather than the Triptych; philosophical value and genuine spoken VoiceOver remain researcher-owned acceptance. |
| Protected Skill IDs | A colliding Triptych package stays visible, invalid, and recoverable; the bundled package remains authoritative. | Researcher must rename or delete the collision. |

## Removed from the reachable target UI

- Proposal/Revision review sheets.
- Research Task and Research Session sheets.
- Agent Assessment and the removed Agent Review surface.
- Active-note HTML/PDF export.
- Canvas has been removed from the product, active state, and window decoder.
- Optional Zotero data-folder/SQLite access.
- Additional-vault and All Notes presentation.
- Generated `_index.md`, `_agent-index.json`, and `_agent-context.json` paths.

The obsolete Proposal, Research Session, workflow-bridge/readiness/lint,
pre-release Review store, and Add Dated Reference implementations have been
removed from the app, Core, and CLI. Unsupported pre-release app state is not
read into the current interface. This clean cutover never authorizes deleting
or rewriting researcher Markdown, unknown YAML, or unrecognized Triptych files.

## Current interface consolidation

| Area | Consolidated current state and evidence |
| --- | --- |
| Ownership and tokens | The app follows the architecture's scoped controllers, typed presentation, stable document sessions, metadata authority, and semantic tokens. Automated architecture tests cover native/WebKit palette parity, appearance, relationship variants, contrast floors, purpose-named typography, 28pt preferred/20pt minimum custom targets, and exclusion of production glass/material APIs. The retired AppKit editor source and its production construction path are removed. |
| Workspace shell | One native Library–Document–Inspector split remains stable across content changes. A per-window `WorkspaceWindowCoordinator` now receives the exact `NSWindow` and split directly, owns delegate/toolbar/explicit visibility intents, and registers readiness plus flushing with an application-injected lifecycle registry; the former singleton split registry, notifications, delayed reconciliation, width publication, and post-open sizing path are removed. AppKit owns resize, divider, compression, automatic Sidebar collapse, Inspector transition, fullscreen, and frame restoration. Both peripheral visibilities mirror native collapsed state without continuous model-driven reassertion. Workspace, Bootstrap, and Research Record no longer impose the old unverified minima or fixed top-safe-area bypass. The Swift 6.4 target build and twelve focused lifecycle/isolation tests pass, including route-identity restoration, exact readiness, delegate restoration, split isolation, and native-host safe-area propagation. A 2026-07-20 researcher-operated isolated QA journey moved and continuously resized the native Workspace from its 1180 × 760 initial frame to the system-permitted 368 × 363 outer frame while retaining reachable split surfaces. Fullscreen, automatic-collapse recovery, and the complete adaptation matrix remain open. |
| Bootstrap and tabs | Bootstrap and Workspace use nonoptional Codable scene routes whose `windowID` is the sole session identity. Bootstrap is presented/nonrestored; Workspace is suppressed-by-default/restored. Scene replacement waits for the exact destination's native readiness and retains the source on failure, cancellation, or early unregister. Product code no longer changes activation policy, delays activation, or fronts every window; `run-debug-app.sh` assembles a real Debug bundle in `.build/` and launches it through LaunchServices. Clean-account, restored-session, Dock/New Window, and failure UI journeys must be rerun after this migration. The no-note Document is plain. Native Sidebar routes replace Collapse Note. Production Document tabs use an inner `NSTabViewController` and retain the shell; equal-width selection/close are integrated, but final visual and replacement automation remain open. Back/Forward, Recents, and Quick Open remain absent. |
| Document region | Document occupies the native split's remaining width and height without a component minimum. Read stays mounted and the retained CodeMirror surface is allocated once; Live Preview and Source reconfigure that one state. There is no separate Editor window or floating Metadata/Properties surface. Read, Live Preview, and Source consume one Swift-owned provisional measure, scrolling top inset, responsive threshold, trailing space, text-scale, and typography block. The stale 92pt floating-context clearance and two unused Read block-start variables are removed. Exact values remain implementation evidence pending the Editor adaptation matrix. |
| Library | One native Filter menu owns review, integrity, metadata, property, order, and action choices. Debate Importance sorting requires one exact scope and leaves unrated Analyses last. Role-appropriate secondary metadata remains compact. Unclassified is a centered classification surface; Set Aside and Trash use mutually exclusive opaque panels without changing Library geometry. |
| Search | One compact overlay exposes This Note/This Vault/Triptych before typing; exact identity fields outrank body. `Command-F` temporarily selects This Note, dismissal restores unchanged ordinary scope and rejects stale work, and presentation first flushes the editor. Focused tests cover scopes, results/no-results, geometry, cancellation, stale-result rejection, and commit-before-Search. No vector, embedding, AI-ranking, or chat path is reachable. |
| Research surfaces | The bottom Strip is note-only, nonoverlapping, compact-width complete, and menu/keyboard equivalent; `Command-Shift-D` opens Dialogue and `Command-R` opens role-valid Review/Critique. Materials stay inside the typed panel with fixed Target/revision; Human Review shares Dialogue without Materials. Research Record is a suppressed, nonrestored `UtilityWindow`; each Workspace publishes its model with native scene focus, the app scene observes that focused object, and the Utility root receives the current value. The old presentation coordinator, custom model key, generation counter, and manual model registry are removed. A focused two-Workspace UI journey verifies note-following; real localized assistive-technology acceptance remains open. |
| Visual system | Scholium-owned surfaces are opaque planes with fine semantic rules; native controls retain native state and sizing. Automated journeys cover responsive widths, Search, Properties/Inspector, light/dark Strip, 200% document text, and the canonical journey. They do not close real Increase Contrast, Reduce Transparency/Motion, inactive-window, mixed-script, or assistive-technology acceptance. |
| Derived state and paths | Graph publication no longer blocks activation or lexical Search. The last good snapshot remains visible as current/stale/failed with affected-vault evidence; post-commit refresh failure never invites mutation retry. Inventory/FSEvents derive contained relative paths from normalized URL components, preserving equivalent macOS paths and role behavior. |
| Conflicts | Comparison binds full editor/disk sources to visible SHA-256 and byte counts, labels sides without authorship inference, restores editor focus, and defaults to Compare Changes. Reload is destructive and valid only for the displayed disk revision; a new disk change requires a fresh comparison. Reload uses incremental projection, not full-vault rescan. |
| Upgrade safety | The fail-closed baseline/candidate gate uses a disposable byte-hostile Triptych, isolated home, explicit portable-state allowlist, and retained manifests/`.xcresult`. One distinct-build run preserved path, size, SHA-256, permissions, and modification time for all 195 authoritative files. |

Manual accessibility and visual acceptance remains incomplete. Automated
responsive journeys pass at 1380, 1080, and 900pt and at 200% document text.
One researcher-operated isolated QA journey passed continuous native movement
and resize from 1180 × 760 to a 368 × 363 outer frame; this evidence does not
treat a Sidebar snapshot as a state oracle or claim the remaining language,
text-size, fullscreen, IME, or assistive-technology matrix.

## Remaining completion work

### Editor special-topic execution plan (2026-07-20 baseline)

This is a migration over the reachable editor, not a replacement project.
`MarkdownSemanticDocument`, `MarkdownEditingDialect`, the checked Swift mirror,
the retained CodeMirror session, sanitized Read renderer, canonical graph, and
existing callout/footnote/table support remain the starting implementation.
The former proposal to introduce a separate `ScholiumRenderDocument` is
superseded because it would duplicate the existing semantic projection.

The 2026-07-20 current-tree audit also supersedes several literal steps from
the earlier pasted proposal:

| Proposed step | Current decision and evidence |
| --- | --- |
| Add `ScholiumRenderDocument` | Superseded. Extend `MarkdownSemanticDocument`; no second semantic authority is introduced. |
| Upgrade the bridge to v3 | Implemented when the wire contract gained the bounded, numeric-only performance snapshot. Identity/generation checks, mathematics, previews, presentation, recovery, focus/blur, and diagnostics now share the same versioned dispatcher. |
| Pin KaTeX 0.18.0 | Superseded by the reviewed locked 0.18.1 package, local runtime, CSS, fonts, notices, and reproducible build. |
| Replace table line styling | Implemented for inactive Live tables in this slice: a direct `StateField` block widget emits semantic table DOM and shares `tables.css` with Read. Richer parity remains subject to visual and assistive-technology acceptance. |
| Replace callout line styling | Implemented for inactive Live callouts: a direct block widget emits the same semantic callout DOM and consumes the same protected component CSS as Read; entering the construct reveals exact source. Named footnote-definition ranges remain owned by the footnote widget so nested projections do not overlap. |
| Replace footnote line styling | Implemented for the common named/repeated/inline/multiline dialect: a direct Live `StateField` shares `footnotes.css`, numbered references, and a semantic end section with Read, while exact-source activation is covered by real WKWebView automation. Richer nested-block parity and human visual/assistive-technology acceptance remain open. |
| Keep Read and editor surfaces alive | Implemented with release acceptance still open. After first allocation, `DocumentEditorHost` keeps committed Read and the CodeMirror surface mounted; mode changes alter visibility, interaction, accessibility exposure, and focus without dismantling either surface. `NoteContentView` directly observes the persistent session so Source/Live changes invalidate immediately without waiting for pointer movement. Focused lifecycle tests pass. The 50-transition/51-sample process-memory handshake is implemented, but the current retained artifacts contain no complete series; the scenario and packaged Release gates remain required. |
| Add `EditorScrollAnchor` | Implemented. The retained document session owns a fingerprint-bound source offset, semantic block bounds, relative position, and normalized fallback; typed CodeMirror and source-located Read adapters restore it, reject stale revisions, and are covered by real WKWebView reconstruction tests. Human visual continuity acceptance remains open. |
| Adopt the proposal's p95 numbers | Not approved product gates. Internal metrics are regression evidence; canonical G7 still requires approved thresholds and the exact packaged Release app on R1. |

The requirement-by-requirement audit against the Editor special-topic plan is
kept explicit so partial implementation cannot be mistaken for cutover:

| Phase / gate | Current state | Evidence still required |
| --- | --- | --- |
| Phase 0 — specification and baseline | Product rules, ownership, shared presentation variables, deterministic RDF-1, and automated current-tree baselines are recorded. | Exact packaged Release performance baseline, final mixed-script fixture/captures, and approved thresholds remain open. |
| Phase 1 — one syntax contract | Automated Gate complete. `MarkdownEditingDialect` v2 serializes callout, Vector-Link, case-sensitive named/inline footnote, continuation/ordinal, and mathematics rules. The one CodeMirror language uses the official YAML-frontmatter wrapper plus typed Wiki/Vector-Link, footnote, callout, inline/display-mathematics, highlight, and Obsidian-comment nodes. Ten specialized fixtures plus two base-syntax fixtures compare Swift/Lezer meanings and exact UTF-16 ranges across the supported CommonMark/GFM block and inline catalog, BOM, LF/CRLF, decomposed Unicode, emoji, CJK, Arabic/Hebrew, and no-final-newline source. Contracts now exposes the shared base inline nodes; block spans consistently exclude terminal line endings and task prose begins after its marker. The malformed catalog is explicit: incomplete inline footnote, wikilink, highlight, callout, and inline-math markers remain ordinary exact source, while structurally unclosed block mathematics and comments fail closed. | Every future syntax addition or parser upgrade must extend these shared fixtures before either renderer consumes it; no current Phase 1 evidence item remains open. |
| Phase 2 — Host, variables, components | Retained Host, shared variables/CSS, semantic callout/table/footnote/math/preview components, and the five-scenario computed-style/geometry matrix are implemented. | Screenshot and human side-by-side approval, mixed-script wrapping, real system-setting propagation, and user-theme acceptance remain open. |
| Phase 3 — rendering and mode state | Source/Live retain one state; Source owns gutters; Live hides closed frontmatter and now fails closed with an accessible Source instruction for an unclosed BOM/LF/CRLF opening. The real WK journey preserves the leading BOM through Live/Source. Stable editor sessions also retain their identity-bound save address while selection and snapshots are temporarily absent, preventing ordinary navigation or scope refresh from misclassifying a valid dirty buffer as unavailable. Table, callout, and footnote fields reuse cached semantic presentations for selection-only transactions and safely map offsets for bounded ordinary insertions outside indexed constructs; structural, multiline, boundary/interior, and deletion edits still rebuild conservatively. Live projection consumers now use the complete tree returned by CodeMirror's parse-completion transaction and rebuild on parse-tree-only updates, preventing the initial partial raw projection from remaining stale until pointer or selection activity. A real WKWebView journey proves inactive and active-source transitions for mathematics, callouts, tables, and footnotes without changing the exact buffer. The visible single-footnote-preview/external-conflict XCU journey passed on 2026-07-20. | Real IME and human visual acceptance remain open. |
| Phase 4 — previews | Graph-authoritative bounded link/Vector-Link previews and single-definition footnote previews are implemented with stale and containment guards plus non-hover routes. Native context menus pass their exact AppKit click coordinate through a typed, identity/generation-checked request so CodeMirror resolves the clicked link or footnote rather than a stale Swift selection mirror. The isolated XCU journey proves a dirty-buffer single-footnote preview is visible immediately before an external disk revision, is dismissed when conflict recovery takes focus, and does not change conflict or dirty-buffer ownership. | Visual acceptance for every relationship role, unavailable wording, and real keyboard/VoiceOver behavior remain open. |
| Phase 5 — performance and cutover | Metrics, deterministic stress fixture, strict runner, exact WebKit-process attribution, and the app-owned retained-memory handshake exist. Unlocked isolated-QA runs produced one-sample diagnostic latency results for all four non-Editor journeys. The retained memory artifacts contain only incomplete 3- or 5-sample prefixes, so no 50-transition convergence claim is retained. | Complete the scenario memory series, add visible Editor latency actions, improve measured latency, then obtain gate approval and run the 5-warm-up/30-sample packaged Release protocol; complete UI green, human IME/accessibility, and removal/cutover audit also remain open. |

Design is a parallel acceptance track, not a post-editor polish phase. Every
slice records its object/ownership boundary, primary task flow, ready/empty/
loading/stale/error/conflict/recovery states as applicable, narrow/ordinary/
wide and 200%-text behavior, keyboard/focus/assistive-technology routes, and
hostile-content fixtures. Shared grid values are promoted only when they name
a stable semantic alignment or document relationship; screenshot coordinates
and a universal numbered spacing scale do not become authority. Exact visual
rhythm remains provisional until the real component passes this matrix.

The first concrete matrix is binding for the mathematics slice:

| Condition | Required Read behavior | Required Live behavior | Evidence before cutover |
| --- | --- | --- | --- |
| Ready, valid expression | Shared component emits local KaTeX HTML plus MathML; exact source range remains attached. | The same component replaces only an inactive construct; entering the construct reveals exact Markdown. | Swift semantic/source-span tests, TypeScript runtime tests, real WebKit visual and selection journey. |
| Empty document or no math | No math DOM, remote request, delayed layout owner, or empty-state chrome is added. | No math decorations or whole-document rescan is added to ordinary typing. | Empty fixture and editor projection metric. |
| Runtime unavailable or loading | A stable document-colored loading or failure surface remains visible; it never impersonates the final Read/Live typography. | Source mode remains the exact-source recovery route; editing, save, undo, and mode switching continue when the retained editor is available. | Missing-resource fixture and process-recovery journey. |
| Unsupported or malformed input | Delimiter failures remain ordinary source with a diagnostic; renderer failures retain escaped source with non-color-only error treatment. | The source construct remains editable; the widget never swallows or rewrites it. | Malformed, oversized, hostile, escaped, code, HTML, comment, and YAML fixtures. |
| Stale revision, external conflict, or Web process recovery | The committed fingerprint continues to own Read and no rendered output becomes writable authority. | Existing dirty-buffer/conflict ownership remains unchanged; recovered WebKit reloads the same checked Swift mirror and mode. | Existing conflict suite plus one math-bearing recovery fixture. |
| Narrow width and 200% text | Display math scrolls locally in the inline direction rather than widening or clipping the Document; inline math wraps only at surrounding prose boundaries. | The same overflow rule applies without moving the caret or editor viewport. | 900-point, ordinary, wide, mixed-script, and 200%-text captures. |
| Keyboard and assistive technology | MathML is exposed; source remains available through mode/navigation routes and failure text is announced without hover. | Arrow/click navigation reveals source, Source mode remains exact, and no pointer-only action is required. | Full Keyboard Access and VoiceOver human acceptance; automation is supporting evidence only. |

The preview slice uses the same design discipline:

| Condition | Required behavior | Current automated evidence | Still open |
| --- | --- | --- | --- |
| Resolved neutral or Vector Link | Swift supplies one graph-authoritative, fingerprint-bound, inert excerpt; relationship and fragment stay visible without becoming evidence. | Catalog tests reject broken edges; protocol and real WebKit tests render the exact preview at the selected source span. | Visual comparison of every relationship role in Read and Live. |
| Footnote reference | Only the referenced definition and its bounded continuation lines appear; the complete footnote section never becomes preview content. | TypeScript fixtures cover exact definition selection, continuation, missing IDs, and definition exclusion. | Mixed-script and very long footnote visual acceptance. |
| Empty, ambiguous, broken, external, oversized, or unavailable | No stale or guessed content appears; ordinary link activation and exact editing remain available. | Graph builder fails closed, bridge validation bounds counts/ranges/strings, and preview content removes interactive descendants. | Researcher-facing wording review for unavailable keyboard requests. |
| Stale source/graph, conflict, or Web process recovery | Source fingerprint and graph generation reject late catalogs; previews remain disposable and cannot alter conflict ownership. | `NoteContentView` generation/fingerprint guards plus complete Swift conflict/recovery tests. | One disposable external-conflict UI journey with a visible preview before conflict. |
| Narrow width, 200% text, contrast, and transparency | One shared popover clamps or flips inside the viewport, scrolls locally, wraps hostile content, and has non-translucent/high-contrast variants. | Shared protected CSS and frontend architecture tests cover the variables and media-query fallbacks. | Captures at 900 points and 200% text under real system settings. |
| Keyboard and assistive technology | Read focus shows the same preview; Live offers a context-menu route at the insertion point; Escape closes without changing source or selection. | Typed nonmutating `showPreview` operation and real WKWebView mode/selection test. | Full Keyboard Access and spoken VoiceOver acceptance. |

1. **Parity foundation — automated foundation complete; visual acceptance open.** Inject the protected callout resource
   into Read correctly; make Read and CodeMirror consume one runtime
   color/rhythm variable block; remove the deferred synchronization known
   issue; add focused runtime tests. One serialized real-WKWebView fixture now
   compares the shared root variables, colors, document, H2, callout, table,
   footnote, and display-math computed styles and geometry within one device
   pixel at narrow width, 200% text, Dark, High Contrast Dark, and restored
   ordinary presentation. The matrix also requires presentation CSS changes to
   remeasure CodeMirror before semantic scroll restoration. This is a computed
   contract check, not screenshot or human visual approval. Mixed-script
   captures and side-by-side visual comparison of headings, paragraphs,
   blockquotes, code, links, component details, and hostile wrapping remain
   open.
2. **Shared syntax contract — automated Gate complete.** Extend `MarkdownEditingDialect` and
   `MarkdownSemanticDocument` with source-located inline/display mathematics
   and previewable fragments. Port the mature dollar-delimiter rules rather
   than using a new regular-expression dialect. Ten shared Swift/TypeScript
   fixtures now cover aliases, unknown callouts, escapes, currency-like text,
   nesting exclusions, malformed and duplicate footnotes, fragments, CRLF,
   Unicode, comments, raw HTML, code, and YAML. The same fixtures compare
   semantic values and exact UTF-16 source slices for callout headers, links,
   footnote definitions and references, and both whole-expression and content
   mathematics ranges in Swift and TypeScript. The dialect now carries the
   footnote syntax/continuation/identity contract, and the CodeMirror language
   directly locks the mature YAML-frontmatter and Lezer Markdown packages.
   The official Markdown extension now emits dedicated Wiki/Vector-Link,
   named/inline footnote, callout, inline/display-math, highlight, and
   Obsidian-comment nodes. Live link, callout, footnote, and mathematics
   consumers plus the parity projector are constrained by those ranges; a
   normalized-to-exact UTF-16 map preserves BOM and mixed-line-ending fixture
   evidence. Two additional shared fixtures compare H1/Setext headings and the
   supported CommonMark/GFM paragraph, quotation, list/task, table, code,
   thematic-break, HTML, emphasis, code, link, autolink, and image catalog at
   exact LF and BOM/CRLF/Unicode UTF-16 spans in both runtimes.
   Unclosed Obsidian comments now fail closed through EOF in both runtimes;
   Swift also fails closed for unclosed HTML comments, emits an exact
   `malformedComment` diagnostic, and proves hidden links do not enter
   `GraphSnapshot`. The final malformed audit follows mature Markdown failure
   behavior: incomplete inline markers remain ordinary exact source; only
   structurally unclosed block mathematics and comments diagnose fail closed.
3. **Shared render components — automated implementation complete; human acceptance open.** Shared Callout, semantic table, semantic footnote, mathematics,
   preview, color/rhythm, measure, scale, and inset components are reachable.
   Continue extracting mode-neutral presentation roles for
   headings, prose, callouts, links, footnotes, and math. Keep static
   Read DOM and CodeMirror adapters thin. Inactive Live content must consume
   the same roles; active syntax remains source. The table adapter now uses a
   direct CodeMirror state decoration because it changes vertical geometry;
   its exact-source reveal, semantic headers, alignment, rich inline content,
   and narrow overflow are covered by focused tests. The line-oriented
   footnote imitation is replaced by the shared fragment adapter for ordinary
   definitions and nested lists, quotations, fenced code, callouts, tables,
   and mathematics. Selection, undo, copy, navigation, and end-section
   behavior have automated coverage; a real WKWebView journey now also proves
   inactive-to-source reveal and restoration for mathematics, callouts,
   tables, and footnotes while retaining exact bytes. Real IME and
   assistive-technology acceptance remain open. Ordinary typing in documents
   whose current index proves there are no table, callout, or footnote
   constructs reuses the empty block-projection state. Construct-bearing
   documents map cached presentations through bounded ordinary insertions
   outside their indexed ranges; structural, multiline, boundary/interior,
   and deletion edits rebuild conservatively.
4. **Local mathematics — automated implementation complete; human acceptance open.** Admit exactly pinned KaTeX only after its license,
   package contents, matching CSS/fonts, bundle-size effect, class-prefix
   migration, and reproducible offline build are reviewed. Current upstream is
   `0.18.1`; do not retain the superseded `0.18.0` pin. Use accessible
   `htmlAndMathml`, `trust: false`, bounded expansion/size, inert errors, and
   no network. Verify Read/Live parity, source reveal, copy, VoiceOver, zoom,
   overflow, and malformed input.
5. **Bounded previews — automated implementation complete; human acceptance open.** Add one typed preview request/response path for neutral
   links, all Vector-Link roles, and one referenced footnote definition. Read
   uses hover; Live uses Command-hover; focus, context menu, and keyboard paths
   are equivalent. Swift resolves graph authority and committed content;
   ambiguous, stale, oversized, external, or missing targets fail closed.
6. **Mode and host closure — automated implementation complete; measurement and human acceptance open.** Preserve one CodeMirror state between Live and
   Source, keep YAML/line numbers hidden only in Live, keep Source line numbers
   and exact-source typography, and pass one document presentation
   configuration through the host. Window, split, theme, text-scale, or mode
   changes may not lose dirty source, selection, undo, scroll, or composition.
   The bootstrap-created QA workspace route now carries the deterministic
   native window identity instead of asking a later Host view to infer it.
   After first allocation, `DocumentEditorHost` keeps committed Read and the
   CodeMirror surface mounted; Read/Live/Source transitions change only
   visibility, hit testing, accessibility exposure, and first-responder focus.
   The hidden editor receives clean external revisions without replacing a
   dirty buffer, and keeps its last editable mode for re-entry. Focused
   automation verifies retained source/mode identity, typed blur/focus,
   semantic scroll restoration, 200% text through every mode, snapshot commit,
   termination, relaunch restoration, and exact leading-BOM retention. Closed
   frontmatter is parsed by the official YAML wrapper and hidden in Live even
   when invalid; an unclosed opening now disables all Live semantic projection,
   keeps exact source visible, and presents an accessible Source instruction.
   Measure retained-surface memory per
   tab so visual continuity does not create unbounded WebKit growth.
7. **Acceptance and cutover — in progress.** Run semantic fixtures, all editor TypeScript
   tests, focused and complete Swift suites, reproducible-bundle verification,
   real WebKit lifecycle/conflict recovery, disposable UI journeys, and manual
   VoiceOver/Voice Control/Dictation/CJK/RTL gates. Use internal performance
   budgets only as regression evidence until the release owner approves the
   canonical p95 thresholds and an exact packaged Release build is eligible
   for G7. Remove an old renderer branch or patch only after the replacement
   passes its adjacent empty, loading, error, conflict, and recovery states.

Official-source research informing this migration: CodeMirror provides
incremental syntax trees, visible-range decorations/widgets, and hover
tooltips; Lezer Markdown supports typed inline/block extensions; Obsidian uses
single-dollar inline and double-dollar display math plus Command-hover previews
while editing; the micromark math extension publishes a non-regex delimiter
grammar; and KaTeX publishes accessible MathML output and explicit trust,
expansion, and size controls. These are implementation inputs, not product
authority; Section 5.1 remains the target rule.

1. Complete manual Full Keyboard Access, visual 200% text, localization, and real system-setting propagation acceptance for Light/Dark appearance, Increase Contrast, Reduce Transparency, and Reduce Motion. Complete the editor-specific real VoiceOver, Voice Control, Dictation, standard text-service, Simplified and Traditional Chinese, Japanese, Korean, dead-key, emoji, bidirectional-cursor, composition-conflict, and composition-recovery journeys. Existing automated tests prove source preservation and bridge policy but do not substitute for those operating-system interactions.
2. Approve the proposed strict p95 thresholds, freeze and exactly tag a clean reviewed commit, package that exact source, and run the packaged Release-app G7 protocol against frozen RDF-1 on Reference Machine R1. Complete-boundary instrumentation, the external XCUITest driver, strict report validator, thermally bounded fail-closed 5-warm-up/30-sample runner, build provenance, and privacy-safe environment capture are implemented. Warm Search and Read reuse one process; only process-boundary metrics relaunch. Internal SQLite and semantic-projection microbenchmarks remain regression checks only.
3. Continue explainable lexical-ranking evaluation beyond the current 2,056-note disposable collision fixture, including broader ranking-usability review and eventual release-owner approval. The current field-weighted contract ranks Title, Alias, Heading, and Body matches deterministically, verifies equal-rank path ordering, and labels their context explicitly. Beta remains deterministic local SQLite FTS5 plus separately labelled direct graph relations; vector search, embeddings, AI ranking, and chat-style search are explicitly out of scope.
4. Implement and verify the 1.0 **Open in Codex** handoff without adding
   background execution: detect supported local availability, validate the
   exact agent working root, prepare a locator-only composer for a new task,
   preserve explicit researcher submission and the copy fallback, and cover
   unavailable launch, retry, cancellation, Unicode paths, accessibility,
   application reactivation, and unchanged Function recovery with disposable
   fixtures. Do not begin **Run with Codex** as part of this work.

Permanent deletion no longer advertises Checkpoint or Research Record recovery
for deleted content. The coordinated implementation, destructive confirmation,
checkpoint invalidation, durable recovery notice, file-by-file inspection, and
record-only resolution paths are verified on disposable filesystems.

## Verification evidence

This table retains representative evidence, not every run. Temporary `/tmp`
results are not durable; superseded detail remains in Git history. All research
fixtures were disposable. Zotero MCP bounded reads used the local service; one
synthetic import/read-back used a disposed profile, never a live-library write
or retained private value.

| Evidence class | Latest recorded result | Interpretation |
| --- | --- | --- |
| Editor special-topic implementation | On 2026-07-20 the locked editor toolchain passed TypeScript typechecking and all 99 WebEditor tests, including safe offset mapping for construct-bearing documents, parse-tree-only projection refresh, and bounded point-anchored preview protocol validation. The CodeMirror language now exposes the shared CommonMark/GFM base catalog plus formal Wiki/Vector-Link, named/inline/multiline footnote, callout, inline/display/unclosed-mathematics, highlight, and Obsidian-comment nodes; Live consumers accept these semantics only at typed syntax-tree ranges. Ten specialized fixtures and two base-syntax fixtures compare Swift/TypeScript semantic values and exact UTF-16 source slices across BOM, LF/CRLF, decomposed Unicode, emoji, CJK, Arabic/Hebrew, no-final-newline input, Setext headings, and malformed constructs. Swift additionally fails closed for unclosed HTML comments, emits an exact `malformedComment` diagnostic, and a focused GraphSnapshot test proves comment-hidden links publish no edges. Focused Swift tests passed safe Read table semantics, nested component-rich footnote ownership/rendering, shared resources, retained Host state, and typed blur/focus. Bridge v3 additionally returns a bounded, numeric-only Editor performance ring; the serialized real-WKWebView CRLF/Unicode/mode/math/table/footnote/preview/process-recovery journey passed inactive semantic component DOM, exact-source reveal for mathematics, callouts, tables, and footnotes, nested list/quotation/fenced-code/callout/table/math footnote DOM, one-definition structured footnote preview, pointer-to-exact-definition reveal, Source projection removal, 50 typed Source/Live transitions through one retained buffer, exact text retention, Editor semantic scroll reconstruction, Read semantic block restoration, stale-fingerprint fallback, explicit focus resignation/restoration, and diagnostic retrieval. A separate real-WKWebView test loaded 100,000 CJK characters, appended exact bytes through the typed bridge, and preserved them across Source/Live transitions. The computed-style journey compares shared variables, colors, and key document/H2/callout/table/footnote/math styles and geometry within one device pixel across narrow width, 200% text, Dark, High Contrast Dark, and restored ordinary presentation. A prior isolated-QA 100,000-CJK journey passed, but the current macOS 27 XCU rerun could not make the document-height virtualized AX text node an input target; because the bridge test is green and the UI driver produced no edit, this remains automation evidence debt rather than a product-loss result. | Current-checkout automated correctness evidence. The computed-style matrix does not establish screenshot/human visual parity, mixed-script wrapping, real VoiceOver/Voice Control/Dictation/IME behavior, visible-frame p95 performance, or the release gates. |
| Repository verification | The 2026-07-20 `verify.sh` run passed protected Skill references, the process-memory sampler self-test, editor typecheck and all 99 WebEditor tests, reproducible bundle, RDF-1 v2 (800 notes; tree hash `bcef4ae9addf1dd01752cb5d21fb3309f7c487eb53b0b0b9e7df048f785997f9`), all four Swift test products including 196 App tests in 20 suites, the serialized real-WKWebView Editor/Read journey with 50 retained-buffer mode transitions and a shared computed-style/geometry matrix across narrow width, 200% text, Dark, High Contrast Dark, and restored ordinary presentation, executable workflow/Function CLI checks, public symbol isolation, and optimized build. The App target now explicitly disables in-process Swift Testing parallelism at its shared AppKit/WebKit boundary; test-owned windows retain their own close lifetime, and the complete verifier exits successfully while still failing on every recorded test issue. It also verified removal of named dead UI/data branches, visible Settings feedback, repository-local `.build/` isolation, a cold 2,730-record/661-unit index rebuild without File Provider metadata, and explicit Xcode developer-directory resolution. A dirty-checkout arm64 Release packaging smoke passed the updated Editor resources, nested signing, strict delivered-app verification, and actual standalone/bundled CLI catalog loading. | Repository/build and local packaging-smoke evidence only; no screenshot/human visual-parity result, clean tagged package, packaged Editor performance run, Developer ID/notarization, or G7/G9 result. |
| Beta Skill architecture | Focused/full verification passed five Workflow packages, System protection, dependency closure, citations, guarded evolution/recovery, Dialogue/bootstrap, and Zotero. `ScholiumCore/Resources/Skills` is the sole bundled authority. A disposable Settings journey passed comparison, validation, attributed fixture evaluation, atomic apply, relaunch persistence, restore, and undo snapshot; local reads and isolated synthetic import/read-back passed. See the [package architecture](../ScholiumCore/Resources/Skills/README.md) and [twelve field trials](../ScholiumCore/Resources/Skills/evals/REAL_WORKFLOW_ASSESSMENT.md). | Structural/transport evidence only. Synthetic evolution evidence proves no philosophical quality; field-trial and manual accessibility acceptance remain open, so G10 and J-014–J-016 are incomplete. |
| Focused Function contracts and CLI | Focused Contracts/controller/Application/installer/Settings tests passed Dialogue modules, immutable response contracts, stale rejection, reset, routing isolation, CLI installation, and live-activation preservation. The executable lifecycle passed help/version/doctor, strict parsing, function availability, Dialogue/promotion, conditional Revise with fingerprint edit, Awaiting Fidelity child/link/reuse, cancellation, bibliography, transports, and specified malformed/stale/role/duplication/confirmation/premature failures. | Executable transport, persistence, and orchestration; philosophical adequacy remains researcher-owned. |
| Search and derived state | The focused SearchIndex suite passed against a synthetic 2,056-note collision fixture, covering deterministic Title/Alias/Heading/Body precedence, equal-rank path ordering, repeat-query stability, and safe replacement of an incompatible generated contract; an isolated UI run verified the same visible field-context order. Broader ranking-usability evaluation remains open. | Semantic and isolated UI evidence. |
| Current UI journeys | A fresh 2026-07-20 complete-class discovery ran 63 journeys: 26 passed and 37 failed. The result separates migration debt from product defects: stale tests still queried removed role radio buttons or the former Research-menu Checkpoint location; several multiwindow journeys incorrectly assumed a new window inherited the current note; Dialogue's embedded Human Review compressed the agent scroll to about 58 points at compact height; and one dirty retained session lost its save address while selection was temporarily absent. Editor-only follow-up has now passed eight focused journeys: Live/Source chrome and Frontmatter behavior, native/context commands, commit-before-note-switch, WebContent termination recovery with exact resave, 200% presentation persistence across all modes, dirty external-rename rebinding, dirty external-edit conflict recovery, and a visible dirty single-footnote preview immediately before external-conflict recovery. The eighth journey uses a bounded clipboard insertion so this preview/conflict acceptance is independent of the host input method; the selected system source was separately confirmed as ABC. It proves the exact dirty preview content, disk-conflict ownership, preview dismissal, and Keep Editing buffer retention. The QA termination route was repaired to address the focused bridge document ID rather than a mutable relative path. The retained-reference fix also passed 24/24 Window controller tests. The XCU target's legacy synchronous lifecycle was replaced by MainActor-isolated async `setUp`/`tearDown`, removing the Swift 6.4 XCUI actor diagnostics; `build-for-testing` passes with only Xcode's unrelated no-AppIntents metadata warning. The earlier 41/58 result is superseded as the current baseline, not converted into a green complete-class claim. | Disposable automation only. The overall UI gate remains open; the 100,000-CJK XCU input-target limitation and VoiceOver enablement timeout remain separate from human assistive-technology and real-IME acceptance. |
| Upgrade safety | `verify-qa-upgrade-safety.sh` passed distinct baseline `587b93a0a710bac273601c1fa86ad4db1578702c6cf34884f525c3fb8df8000c` and candidate `b7b3e109cb37e83e4dd3d6c76dac26f04abac1fed019bf85ef518a446480e551` builds on one disposable Triptych/home. All 195 vault files retained path, size, SHA-256, permissions, and mtime; only allowlisted `.scholium/identities.json` and `.scholium/manifest.json` changed. | Evidence for these two QA builds only; every release must rerun it. Not installed-app or private-vault evidence. |
| Performance | Complete-boundary launch/Search/Read instrumentation, the external XCUITest driver, strict validator, privacy-safe capture, and fail-closed runner are implemented. Editor bridge v3 exposes bounded startup/load/projection/key/scroll/mode/preview/bridge diagnostics without source content. RDF-1 v2 adds the deterministic 100,000-CJK-character Editor stress Work while preserving the 800-note role counts. A guarded incremental path avoids table/callout/footnote rescans for selection-only transactions and maps existing indexes through bounded ordinary insertions outside their ranges; deletions, structural or multiline inserts, boundary/interior edits, and other unsafe changes still rebuild conservatively. The fail-closed sampler resolves the exact app originator's active WebKit service PIDs through `launchctl print pid/<app-pid>`, verifies every executable through `ps`, and only then sums app plus attributed WebContent/GPU/Networking RSS. On an unlocked M4 QA host, one-sample `scenario_only` latency runs completed for launch, Search, cold Read, and warm Read: 4,479 ms, 440 ms, 7,264 ms, and 1,580 ms respectively, all above the proposed limits. Retained-memory attempts kept a stable five-process attribution but the retained artifacts contain only 3- or 5-sample prefixes, not the required 51 samples, so convergence is unproven. These are actionable diagnostics, not G7 percentiles. The exact ASCII query helper now commits letter runs before numeric characters so an active CJK input source cannot consume digits as candidate selectors; this does not constitute real CJK IME acceptance. UI runners share one fail-fast unlocked-console preflight and route result bundles into repository-local `.build` scratch. The canonical protocol still requires the exact packaged Release app on R1, approved thresholds, and five warm-ups plus 30 retained samples per latency metric. | Scenario-only: latency needs improvement and retained-memory convergence must be rerun; G7 plus the Editor Usable Core performance gate remain open. |
| Distribution | A 2026-07-20 local arm64 Release smoke passed metadata, licenses, complete editor resources, inside-out app/helper signing, strict signature verification, standalone and bundled CLI execution, ZIP generation, and checksum generation. Its provenance recorded `source_clean=false`, it had no exact tag, and it used ad-hoc signing. | Local preflight; not clean-tagged G9 evidence, Developer ID/notarization evidence, or a release asset. |

`BETA_RELEASE.md` fixes the source-first `v0.1.0-beta.1` policy: exact
`GPL-3.0-or-later` source plus optional ad-hoc-signed app ZIP and checksum.
Bundle metadata and packaging align, but no clean tagged artifact, external
install, Developer ID/notarization result, or public release has passed.
