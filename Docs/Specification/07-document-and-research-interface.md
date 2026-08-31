# Specification: Document and Research Interface

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 18.4–18.7. Shared state
presentation belongs to [Scholium Design](../../Design.md#199-cross-functional-state-language).

## 18.4 Document modes, context, and Metadata

Review, Edit, and Source are modes over one Document, not tabs. Each live
Triptych workspace session owns one current mode, starting in Edit and retained
across its Note/tab changes. Switching workspace restores that workspace's
selection. Mode state never becomes a Note, vault, or Markdown fact.

Review owns the passage Comment surface; Edit owns formatting; Source owns
neither. Contextual surfaces appear only after selection completes, remain
anchored to the source location while scrolling, and disappear when their
selection, focus, task, or mode ends. Cancelling Comment must not erase the
visible selection.

Current-revision Comments use one quiet source-line treatment and counted
margin marker per Discussion/range. Activation opens the matching Discussion
turn; its locator returns to Review. Revision mismatch removes the current
marker and labels the locator **Earlier revision**. The first Agent response
forms the Record and removes the active markers.

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
protected information. Callouts, footnotes, Comments, provenance, diagnostics,
conflicts, recovery, and chrome remain app-owned. Invalid snippets stay disabled
with errors. Rendering failure enters persistent CSS Safe Mode until the
researcher disables or selectively re-enables managed copies.

The Document toolbar keeps Sidebar and Back/Forward leading, identity and
outline in the Document region, then Search, Document Mode, Records, and
trailing Inspector. Source remains available through the Document Mode menu;
the toolbar button prioritizes Review/Edit and reports its current value.
Document Text Size is per-window and source-neutral.

The Metadata sheet edits the current Note's managed record at its exact
revision. Definitions come from Settings; archived present fields remain
editable/removable. Authored `summary`/`keywords` route to Source. About reuses
the configured cross-authority order and never creates another owner.

## 18.5 Contextual research and Actions

Apparatus contains Research Inspector only. Active Discussion remains an Action
sheet. Research Records is a separate, resizable, nonrestored native auxiliary
window bound to one Triptych; it never follows unrelated window focus or
appears inside Inspector.

Research Records opens collection-first with a native **Records / Reading
Leads** index, one search/scope/filter header, and flat rule-separated ledgers.
Rows show the minimum scanning identity: frozen Record Title, focal Note when
needed, Action, date, and exceptional limitation/blocked state; Reading Leads
show disposition plus bibliographic identity. Method, reason, uncertainty, and
complete result remain in detail. Collections support provider-owned ordering,
bounded pagination, exact filtered total, and retained loaded rows on later-page
failure.

Selecting a Record opens one reading-first detail with a narrower optional
**Evidence** rail. Back restores collection state. The reading plane contains
Action/time, scholarly title, distinct Method/source context, attributed
researcher and Agent prose, Research Result, Follow Up, and optional Method
Feedback. The Evidence rail contains Changes, Effects, Participants, and
Technical Details without becoming writable source or a second result owner.

Record prose supports a limited safe read-only Markdown subset: headings,
emphasis, inline code, lists, quotations, safe web links, internal links, and
Wikilinks. Unsupported extensions remain visible as literal source. Resolved
links use ordinary accessible navigation; missing or ambiguous destinations
remain noninteractive exact text. Generated presentation never rewrites Record
content.

A Reading Lead detail uses one centered flow: reversible
Unprocessed/Handled disposition, full citation, bibliography, discovery
locator, reason, uncertainty, researcher note, source/parent destinations, and
technical identity. Handled means processed only. Grouping and presentation do
not turn the lead into an Analysis, Zotero match, or evidence.

Record participants and evidence remain bounded provenance, not a dossier or
reading history. Change comparison shows only confirmed Agent modifications.
Direct Undo appears per eligible Note and uses §8.4 revision requirements.
Created Notes show provenance but no fabricated preimage/Undo.

**Follow Up…** starts a new Action from the selected Record, preserving parent
lineage. Optional **Feedback on Previous Result** writes Method Feedback to the
parent, not the child. Record deletion is a separately confirmed permanent
operation and never masquerades as Finder-restorable source deletion.

There is one native trailing Inspector with **Overview** and **Connect** modes.
Each workspace retains its selected mode; Note/tab/mode changes do not alter it.
Hiding Inspector moves no content elsewhere. Without a Document it presents
**No Document Selected**.

Overview contains, in order:

1. **Needs Attention** count and route for the current Note;
2. **About** with nonempty managed/authored values and Edit Metadata; and
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

Document owns a trailing-centered overlay rail. **Research Actions** presents
the role-valid Actions from §8.1 in canonical order as neutral icon-only,
fully named accessible buttons; Settle follows as the quiet current-Note
judgment. Conditional **Note Review** appears above without becoming an Action
or notification. The rail never owns lifecycle status.

Action launchers open sheets containing scholarly inputs, target effect,
read-only context, availability, repair, and **Copy Handoff**. They never expose
assembled prompts, secrets, registration keys, or technical modes. Closing
preserves unfinished work. Re-pairing invalidates prior Session authority
without replacing the Run. Discussion shows Comments, locators, handoff, Close,
and End, but no manual Agent reply or duplicate Finish.

After preparation, persistent Run state belongs to Notifications:
**Waiting for Agent**, **Running**, **Needs Attention**, **Result Ready**, and
**Recovery Required**. Updates never activate the app, move focus, or present
approval sheets. Completion offers Review Result, Follow Up, and explicit
Dismiss; Dismiss means none of read, review, acceptance, adoption, Undo, or
cancellation.

One multi-Note Run remains one activity with disclosed affected Notes; each
Note retains independent Review and Undo. The Inspector, Document mode,
projection refresh, and pane visibility never replace the retained editor host
or its state.

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
the live editor; Agent direct Undo follows its Record-bound recovery contract.

After Saving, the only terminal outcomes are silent Saved, persistent Autosave
Failed, or persistent Conflict. Failures remain above Document content with
their consequence and repair. There is no Save button, success toast, timeout,
or saved-with-warning state.

Recovery candidates use one native Recovery surface with exact source,
relationship to canonical source, Copy, Reveal, and Restore only when the
recorded revision permits it. System-Trash recovery is visibly distinct and
offers only safe forward cleanup or **Retain Records and Resolve**. Source
Trash and permanent Record deletion retain separate names and confirmations.

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
| Discuss / Analyze / Synthesize / Write | 讨论 / 分析 / 综合 / 写入 |
| Critique / Check Fidelity | 评析 / 核查 |
| Research / Review / Judgment | 研究 / 审查 / 判断 |
| Settle / Settled | 暂定 / 已暂定 |
| Attention / Connect | 关注 / 连接 |
| Incoming Links / Outgoing Links | 传入连接 / 传出连接 |
| Summary / Source Basis / Limitations | 摘要 / 来源依据 / 局限 |
| Review / Edit / Source | 审阅 / 编辑 / 源文本 |
| Comment / Discussion / Response | 评论 / 讨论 / 回应 |
| Research Record | 研究记录 |
| No Document Selected | 未选择文档 |
| Expand / Collapse All Folders | 展开 / 折叠所有文件夹 |
| Move to Trash… | 移至纸篓… |

Chinese uses full-width punctuation. System-owned Finder names, exact paths,
stable identifiers, raw values, and researcher-authored titles are never
translated.
