# Specification: Document and Research Interface

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 18.4–18.7. Shared state
presentation belongs to [Scholium Design](../../Design.md#199-cross-functional-state-language).

## 18.4 Document modes, context, and Metadata

Review, Edit, and Source are modes over one Document, not tabs. Each live
Triptych workspace session owns one current mode, starting in Edit and retained
across its Note/tab changes. Switching workspace restores that workspace's
selection. Mode state never becomes a Note, vault, or Markdown fact.

Review owns read selection; Edit owns formatting. Selection remains available
to Document Information statistics without creating a separate annotation or
collaboration object.

Managed New Note opens Edit at the exact body start after durable commit.
Editor failure retains the Note and offers **Retry Edit** and **Source**. An
exact empty body has a distinct quiet state; malformed YAML, whitespace,
unavailable source, and render failure are not Empty.

Edit's compact formatting surface presents frequent text styles, Bold, Italic,
Strikethrough, Highlight, Link, Wikilink, Annotated Wikilink, and More. Less frequent
code, lists, blockquote, Markdown Comment, image, and insertion actions may move
into one bounded menu without losing menu/keyboard access. Menu labels name
actions rather than syntax.

Caret suggestions use one bounded panel attached to the editor caret. They keep
document focus, show only useful identity/path context, fit the viewport, and
never introduce another text owner. Selection, menus, and suggestion panels use
the semantic surfaces, boundaries, and elevation roles in §19.

Insert presents Footnote and Inline Footnote as neighboring commands. Their
default shortcuts are Option-Command-N and Option-Shift-Command-N respectively;
the existing Hotkeys owner may replace or clear either binding.

Internal-link preview preserves each mode's interaction meaning. Review reveals
the cached destination on ordinary pointer hover or link focus. Edit follows the
macOS editing convention: holding Command while pointing at an inactive
projected link reveals the same cached destination, and Command-click opens it;
pressing Command after the pointer is already over the link works without
requiring pointer re-entry. The armed link gives visible pointer feedback.
Unmodified Edit interaction continues to place the caret and reveal exact
source. Preview never mutates source, moves selection, or takes editor focus.

Review and inactive Edit present an annotated Wikilink through one small
trailing superscript disclosure marker. Pointer hover or keyboard focus reveals
its source-owned Markdown in the same bounded anchored surface as a footnote
preview; primary activation keeps that surface open for reading. Escape,
outside activation, scrolling, resizing, source activation, or a document
change dismisses it. Annotation prose never enters document flow or changes
neighboring line geometry.

Review and inactive Edit present every named or inline footnote occurrence as
the same superscript ordinal. Pointer hover or keyboard focus reveals one
bounded rendered definition without adding prose to document flow. Review
activation navigates to the generated end note and its return route; Edit
activation reveals the exact source-owned definition or inline range in the
same Editor state.

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
width, Body, headings, semantic Callouts, and Exact-source face and size while
preserving protected structure and accessibility. The researcher may choose any
installed Exact-source font; Scholium does not audit the choice. The shipped
default is monospaced. Changing presentation never changes source bytes or
logical lines. Native app chrome is not themeable. Advanced CSS is additive and
optional.

The app-owned filename title is the primary document title. Review and Edit
place it at the top of the shared document plane, inside the document's
scrolling reading and writing context but outside authoritative Markdown.
Review presents it as a read-only identity projection. Edit presents the same
title as a borderless inline filename control: Return or leaving the field
requests the existing revision-aware Rename file operation, while Escape
cancels. Its visible trailing space belongs to the control and focuses it when
clicked; it is never an unresponsive surface. A rejected rename preserves the
draft and explains the failure beside the title. Native window title continues
to identify the window without becoming the visual title. Authored Markdown
headings belong to the body: H1 is
presented as a first-level section beneath the Note title, while H2–H6 use the
quieter lower-heading tier. Review and Edit preserve those relative visual and
accessible levels; Source exposes only the exact authored hierarchy and no
projected title.

Review and Edit place the Note's document attachments in one compact,
single-line strip immediately below that title. Existing attachments remain
visible as paperclip-and-filename controls; each caps its width, uses middle
truncation, exposes its complete filename as Help and accessibility text, and
opens native Quick Look without moving the document selection. The small
expected set grows horizontally and scrolls locally when it overflows rather
than wrapping or narrowing the manuscript.

The trailing **Add Document** control retains its layout slot, appears briefly
when a Note opens or changes, and otherwise becomes visible when pointer or
keyboard focus enters the title/attachment region. Its menu distinguishes
**Attach a Copy…** from **Reference Original…**; both remain available in the
File menu without hover. When hidden it is neither visible nor interactive, and
surrounding document layout does not move. Source has no attachment strip
because it presents exact authored source only.

When a Note enters Edit for the first time without retained window
presentation, focus enters the inline Note title with one collapsed insertion
point at its end. Returning to a Note that remains open restores its last title
or body focus and exact valid editor selection; quitting and reopening Scholium
does the same only for Notes retained in that window's open tabs. Selection
restoration requires the same exact source fingerprint. An explicit source
locator and Managed New Note's body-start insertion override this default.
Closing the Note's tab ends this focus and selection retention; Scholium keeps
no permanent vault-wide cursor history.

Quick Look owns a temporary native presentation and any required read-access
lease. Closing it returns Edit to the title or body target and exact selection
that owned focus before preview; changing the attachment projection while it is
open never recreates the retained editor or Review document.

Edit treats all visible document rhythm as addressable. Clicking an authored
heading's visual padding places the caret in that heading; clicking a visible
Markdown blank line places it on that exact source line; and source-less
spacing between projected objects resolves to the nearest explicit source
boundary. Typography cannot create a region that merely ignores editing input.
Review and inactive Edit retain the same recognizable manuscript hierarchy,
measure, wrapping intent, and visible semantic-block order. Editing may create
bounded geometric differences needed for caret placement, marked text, exact
spaces, blank source rows, and active syntax. Every authored blank line remains
addressable and cannot collapse, overlap adjacent content, or jump when its
first visible character is entered.

An inactive heading or quotation may de-emphasize its structural prefix.
Entering it reveals the exact prefix at the same source location without moving
the researcher to another block or losing selection, composition, or scroll
context. The product contract does not prescribe a particular prefix track,
line-box recipe, or pixel-identical Review/Edit geometry. Preserved spaces keep
their exact width without acquiring visible whitespace markers in ordinary
Edit prose. Ordinary prose follows language-aware line-breaking rules, and
closing punctuation is not left alone at a visual-line start merely because it
follows an interactive inline projection.

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

The Workspace toolbar follows §18.2's bounded-set, menu-parity, and overflow
contract. Document Information is one native transient popover: its
scrollable Heading Outline remains the primary region and its
current statistics remain fixed below. Body scope is implicit; `Selection`
appears only while a nonempty selection owns the count. Statistics show one
researcher-selected number at a time; the native selector remembers the last
machine-local choice among language-aware Words, Characters with Spaces,
Characters without Spaces, and Han Characters. Its closed label uses the short
measure name, while the open menu shows every exact measure beside its value
and marks the current choice with the native checkmark. The popover sizes to
localized content within a bounded maximum. Choosing a heading closes the
popover and returns focus to that document location; Escape or an outside click
dismisses it without losing the editor selection. Search belongs beside
Notifications in the Sidebar header. Agent Changes may appear in the default
toolbar only while at least one confirmed local change exists. Source remains
available through the Document Mode menu; a retained toolbar item may prioritize
Review/Edit while reporting its current value. Document Text Size is per-window
and source-neutral. Native toolbar and Sidebar-header controls preserve the
semantic content-plane boundary in §19 without adding feature-owned material or
geometry.

About directly edits one current-Note field at a time. Plain values activate an
inline control; structured contributors retain their ordered structured editor.
Save and Cancel remain explicit, field-local actions. Managed values commit at
the exact Metadata revision. Authored `summary`/`keywords` commit through the
exact-source writer after the current editor is flushed and never become
managed values. The Metadata sheet remains available for Add Field and
multi-field editing; definitions come from Settings and archived present fields
remain editable/removable. About coordinates these existing owners without
creating another one.

## 18.5 Research Records, contextual research, and Agent Changes

Apparatus contains Research Inspector only. **Research Records** opens one
separate, resizable native auxiliary window bound to the initiating Triptych;
it is not an Inspector mode, Document mode, chat, or application task surface,
and it never follows unrelated window focus. Research menu/toolbar activation
opens the collection, while a Search result opens the same window at the exact
Record and matched step.

The window opens as a quiet scanning list of current questions and last
substantive-step times. One system Search field reuses §13's Record provider
rather than creating a second parser or index. Selecting a Record transitions
the same window to a centered Record reading view; Back returns to the list, and
a Search result may open the exact Record and matched step directly. List and
detail are sequential states, not simultaneous fixed regions, and the
transition preserves selection and reading position.

The reading view pins the current question as its sole content title above an
independently scrolling chronological step sequence. Each step shows time and
Agent attribution followed by its rendered §8.6 Markdown; revision relationships
are stated without turning them into acceptance or completion. Immediately
beneath that step, one compact, single-line Note-reference strip exposes its own
`basis` and `modified` references plus current, earlier, or unavailable revision
state. Each control has a capped width and complete accessible name; the small
expected set scrolls locally if it overflows. Record identifiers and
fingerprints remain progressively disclosed after the sequence. A Note reference
navigates to the current Note when available but never substitutes current prose
for the historical revision.

The attachment control shows only the Note name and `Basis` or `Modified` in
the ordinary current-revision case. `Earlier` or `Unavailable` appears only
when exceptional state changes what navigation means. The native titlebar shows
the narrow task title **Research Records**, without repeating the owning
Triptych, and retains standard window controls and dragging. The window has a
compact task-sized width and height rather than a desktop-scale split layout;
exact defaults remain implementation choices, and resizing still preserves
legibility. Search remains collection-local, visible Records refresh
automatically, and no unavailable write or redundant refresh action is
advertised. The window closes through Escape or its close control and dismisses
after an attachment transfers focus to its Note in the exact originating
Workspace window. It never creates a second Workspace window or falls back to
another open Workspace. Merely losing focus does not close it or discard the
current reading position.

The window is read-only. It has no rich, Markdown, or plain-text editor and no
Action, Run, Method, Result, Reading Lead, participant ledger, chat, response,
Review, or Settle workflow. An Agent-created or appended step refreshes the
collection without activating the App, moving focus, or implying that the
researcher saw or accepted it; reporting remains in the external host under
§8.6. Empty, loading, stale, invalid-file, and unavailable-provider states stay
distinct, and one isolated invalid file does not replace valid Records.

The first Record interface provides no delete, merge, split, or write-suspension
control. Those operations remain unavailable under §22 rather than inheriting
their superseded implementations.

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

There is one native trailing Inspector with **Overview**, **Outgoing**, and
**Incoming** projections. An icon-only single-choice group sits at the logical
leading edge of the Inspector's native toolbar section; every icon has a full
Help/accessibility name and the selected projection remains visible. Pane
content contains no duplicate projection selector. Each workspace retains its
selected projection; Note/tab/projection changes do not alter it. Hiding
Inspector moves no content elsewhere. Without a Document it presents **No
Document Selected**.

Overview contains, in order:

1. a conditional **Needs Attention** count and route for the current Note;
2. **About** with visible semantic groups, configured core fields even when
   empty, every other present managed value, authored values, direct field
   editing, read-only file dates and exact-revision Settlement state, plus Add
   Field; and
3. optional Analysis Zotero link/manage/open/refresh actions.

It has no generic Research Status, Provenance, Derived State, or inline Zotero
metadata section. Freshness appears only when pending, stale, failed, or
unavailable and retains last trustworthy content plus Retry.

Outgoing and Incoming each show one flat row per authored occurrence, without
role folders, predicate clusters, inferred grouping, or a Combined direction.
Each row retains its exact source anchor, complete local context, and optional
annotation; repeated links remain repeated occurrences. Outgoing annotation
editing changes only the current source Note. Incoming annotations are
read-only and expose a separately named **Edit at Source** route that navigates
to the source occurrence. Row titles, annotation text, and context wrap and use
full-row native destination activation. Switching projection changes only the
derived occurrence list and returns its sole scroll owner to the beginning.

Document owns one **Settlement** command with a default native toolbar item and
complete Research-menu route. It is presented as a research milestone, not task
completion. Unsettled, Settled, and Changed Since Settle have distinct wording,
symbol shape, Help, and state-bearing accessibility value. Settled may receive
restrained Confirmed reinforcement; Changed Since Settle combines the milestone
identity with Attention without implying failure.

Activating Settle or Settle Again opens one compact popover with optional
rationale rather than changing the judgment directly. Successful exact-revision
Settlement updates the control and Inspector facts. One brief,
non-celebratory transition may acknowledge an explicit successful Settle, but
existing state, document switching, refresh, failure, and Mark Unsettled do not
replay it; Reduce Motion presents the final state immediately. Exact color,
symbol, material, and motion choreography remain implementation choices. There
is no parallel Document overlay, Agent launcher, or fixed research-method
button. Agent Integration belongs to Settings, and the external conversation
remains in its host.

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
| Annotated Wikilink / Link Annotation | 带注释双链 / 链接注释 |
| Summary / Source Basis / Limitations | 摘要 / 来源依据 / 局限 |
| Review / Edit / Source | 审阅 / 编辑 / 源文本 |
| Research Record | 研究记录 |
| Research Step / Basis / Modified | 研究步骤 / 依据 / 已修改 |
| All / Notes / Records | 全部 / 笔记 / 研究记录 |
| No Document Selected | 未选择文档 |
| Expand / Collapse All Folders | 展开 / 折叠所有文件夹 |
| Move to Trash… | 移至纸篓… |

Chinese uses full-width punctuation. System-owned Finder names, exact paths,
stable identifiers, raw values, and researcher-authored titles are never
translated.
