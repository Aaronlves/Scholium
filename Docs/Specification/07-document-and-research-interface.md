# Specification: Document and Research Interface

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 18.4–18.7. Shared state
presentation belongs to [Scholium Design](../../Design.md#199-cross-functional-state-language).

## 18.4 Document modes, context, and Metadata

Review, Edit, and Source are modes over one Document, not tabs. Each live
Triptych workspace session owns one current mode, starting in Edit and retained
across its Note/tab changes. Switching workspace restores that workspace's
selection. Mode state never becomes a Note, vault, or Markdown fact.

Review owns read selection; Edit owns formatting. Selection remains available
to document statistics without creating a separate annotation or collaboration
object.

Managed New Note opens Edit at the exact body start after durable commit.
Editor failure retains the Note and offers **Retry Edit** and **Source**. An
exact empty body has a distinct quiet state; malformed YAML, whitespace,
unavailable source, and render failure are not Empty.

Edit's compact formatting surface presents frequent text styles, Bold, Italic,
Strikethrough, Highlight, Link, Wikilink/Vector Link, and More. Less frequent
code, lists, blockquote, Markdown Comment, image, and insertion actions may move
into one bounded menu without losing menu/keyboard access. Menu labels name
actions rather than syntax.

Caret suggestions use one bounded panel attached to the editor caret. They keep
document focus, show only useful identity/path context, fit the viewport, and
never introduce another text owner. Selection, menus, and suggestion panels use
the semantic surfaces, boundaries, and elevation roles in §19.

All modes use one adaptive editorial grid and one Appearance **Line width**
value. Review/Edit use scholarly type; Source uses exact-source type. The
measure remains centered with readable logical insets and adapts at narrow
widths and enlarged text. Source soft-wraps visual rows without changing
logical lines. Layout changes reconfigure the retained editor rather than
replace its buffer, selection, Undo, composition, scroll, or focus.

Beta/1.0 interactive writing supports English, Simplified Chinese, and mixed
content. Every Unicode byte remains preserved and Source-visible. Code,
mathematics, and inert raw HTML are isolated technical regions. Complete RTL
chrome/input behavior remains deferred under §17, but all Scholium-owned layout
uses logical start/end edges.

Document Appearance is machine-local. It manages named configurations for line
width, Body, headings, and semantic Callouts while preserving protected
structure and accessibility. Source typography and app chrome are not
themeable. Advanced CSS is additive and optional.

### 18.4.1 Advanced CSS boundary

Imported CSS is copied into managed Application Support storage and applies
only to document content in Review/Edit. It is scoped to ordinary prose,
headings, lists, quotations, tables, code, links, emphasis, marks, and rules,
using bounded visual declarations.

Sanitization rejects imports, executable content, external URLs, escaping
selectors, `!important`, and declarations that hide, reposition, or cover
protected information. Callouts, footnotes, provenance, diagnostics,
conflicts, recovery, and chrome remain app-owned. Invalid snippets stay disabled
with errors. Rendering failure enters persistent CSS Safe Mode until the
researcher disables or selectively re-enables managed copies.

The Document toolbar keeps Sidebar and Back/Forward leading, identity and
outline in the Document region, then Search, Document Mode, Agent Changes, and
trailing Inspector. Source remains available through the Document Mode menu;
the toolbar button prioritizes Review/Edit and reports its current value.
Document Text Size is per-window and source-neutral.

About directly edits one current-Note field at a time. Plain values activate an
inline control; structured contributors retain their ordered structured editor.
Save and Cancel remain explicit, field-local actions. Managed values commit at
the exact Metadata revision. Authored `summary`/`keywords` commit through the
exact-source writer after the current editor is flushed and never become
managed values. The Metadata sheet remains available for Add Field and
multi-field editing; definitions come from Settings and archived present fields
remain editable/removable. About coordinates these existing owners without
creating another one.

## 18.5 Contextual research and Agent Changes

Apparatus contains Research Inspector only. Until §22's replacement Record
contract is resolved, Scholium exposes no Research Records route, window,
provider, mutation, or presentation. Current implementation bytes cannot
silently define the future format or interface.

**Agent Changes** is a temporary read-only comparison presentation, not a
fourth Document mode, Records collection state, durable review state, or
research history. An Agent Change notification opens one exact
`(change_id, Note ID)` result. An updated Note shows only the exact preimage and
confirmed readback revision. A created Note shows **Created by External Agent**
and current content without a fabricated empty baseline. A system-Trash change
shows the original Note identity and location plus the Finder-owned recovery
boundary; it is not rendered as an editable deletion diff.

Several Agent Changes never become one cumulative diff. They appear one at a
time in confirmation order with exact position and deterministic **Previous**
and **Next** routes. The compact header names Note, operation, time, and
current-revision state; `change_id`, complete path, and exact fingerprints use
progressive detail. Ordinary Review continues to show the current complete
Note. If current saved source differs from the ending fingerprint, comparison
is **Earlier Revision** and is never overlaid on current prose.

Closing returns to the originating context, records no viewed/unread progress,
and never changes Settlement. Direct Undo remains per eligible update and uses
§8.4's revision requirement; creation and system Trash have no fabricated
source preimage or Undo.

There is one native trailing Inspector with **Overview** and **Connect** modes.
Each workspace retains its selected mode; Note/tab/mode changes do not alter it.
Hiding Inspector moves no content elsewhere. Without a Document it presents
**No Document Selected**.

Overview contains, in order:

1. **Needs Attention** count and route for the current Note;
2. **About** with visible semantic groups, configured core fields even when
   empty, every other present managed value, authored values, direct field
   editing, read-only file dates and exact-revision Settlement state, plus Add
   Field; and
3. optional Analysis Zotero link/manage/open/refresh actions.

It has no generic Research Status, Provenance, Derived State, or inline Zotero
metadata section. Freshness appears only when pending, stale, failed, or
unavailable and retains last trustworthy content plus Retry.

Connect starts with one Incoming/Outgoing control, then role-appropriate groups
for related Analyses, Topics, and Works. Each direction preserves authored
relation meaning and exact source anchors. Neutral and Incompatible appear in
both directions. Groups show relationship clusters and counts; row titles wrap
and use full-row native activation. The sole scroll owner preserves group
context without adding a second panel, graph owner, or Combined direction.
Switching direction changes only the projection and returns scroll to its
beginning.

Document owns a trailing-centered overlay **Document Rail**. Settle, Settle
Again, or Mark Unsettled appears as the quiet state-valid researcher judgment;
there are no Agent-launch or fixed research-method buttons. Agent Integration
belongs to Settings, and the external conversation remains in its host.

MCP status, Search, and read calls create no persistent activity UI. A confirmed
mutation adds its Agent Change to Notifications without activating the App,
moving focus, or presenting an approval sheet. Dismissal hides the notification
but does not delete exact recovery evidence or imply reading, acceptance,
adoption, Undo, or Settlement. The Inspector, Document mode, projection
refresh, and pane visibility never replace the retained editor host or state.

## 18.6 Document-owned state and action meanings

Shared presentation vocabulary is owned by
[Scholium Design §19.9](../../Design.md#199-cross-functional-state-language).
These Document states retain their source-specific meanings:

| State | Meaning |
| --- | --- |
| **Edited** | Buffer differs from committed source. |
| **Saving** | Revision-checked commit is running. |
| **Saved** | Canonical Markdown readback exactly matches the validated candidate. |
| **Autosave Failed** | Commit cannot be proven; retain buffer and recovery. |
| **Conflict** | Expected revision differs from disk; retain buffer and compare. |
| **Refreshing** | Derived consumers are catching up to committed source. |
| **Derived State Stale** | A consumer reflects an older committed revision. |
| **Fully Up to Date** | Source and named consumers share one committed revision. |

Conflict offers **Compare Changes**, **Reload from Disk**, and **Keep Editing**.
Comparison shows exact soft-wrapped source lines without altering either
revision and returns to Editing or explicit Reload. Editor Undo affects only
the live editor; Agent direct Undo follows the selected Agent Change's
fingerprint-bound recovery contract.

After Saving, the only terminal outcomes are silent Saved, persistent Autosave
Failed, or persistent Conflict. Failures remain above Document content with
their consequence and repair. There is no Save button, success toast, timeout,
or saved-with-warning state.

Recovery candidates use one native Recovery surface with exact source,
relationship to canonical source, Copy, Reveal, and Restore only when the
recorded revision permits it. System-Trash recovery is visibly distinct and
offers only safe forward cleanup or **Resolve** after an unknown native
outcome. Source Trash has no Research Record effect. Any future Record deletion
route requires its own §22 contract, name, consequence, and confirmation.

## 18.7 Simplified Chinese terminology and translation boundary

Beta/1.0 localizes researcher-facing interface text in English and Simplified
Chinese. Translate contextually; stable identifiers, enum values, command IDs,
paths, source, researcher prose, and Skill names remain verbatim.

| English | Approved Simplified Chinese |
| --- | --- |
| Scholium | Scholium |
| Triptych | 脉络 |
| Vault | 研究库 |
| Library | 研究文档 |
| Analyses / Topics / Works | 分析 / 议题 / 写作 |
| Agent Integration / Agent Changes | Agent 集成 / Agent 修改 |
| Critique / Fidelity | 评析 / 忠实性 |
| Research / Review / Judgment | 研究 / 审查 / 判断 |
| Settle / Settled | 暂定 / 已暂定 |
| Attention / Connect | 关注 / 连接 |
| Incoming Links / Outgoing Links | 传入连接 / 传出连接 |
| Summary / Source Basis / Limitations | 摘要 / 来源依据 / 局限 |
| Review / Edit / Source | 审阅 / 编辑 / 源文本 |
| Research Record | 研究记录 |
| No Document Selected | 未选择文档 |
| Expand / Collapse All Folders | 展开 / 折叠所有文件夹 |
| Move to Trash… | 移至纸篓… |

Chinese uses full-width punctuation. System-owned Finder names, exact paths,
stable identifiers, raw values, and researcher-authored titles are never
translated.
