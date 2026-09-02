# Specification: Interface Shell and Library

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 18.1–18.3.

## 18. Canonical interface contract

Sections 1–17 own scholarly and workflow meaning. This chapter owns native shell
and Library presentation without restating those workflows.

### 18.1 Interface principles

- Keep Document the largest and most stable region. Navigation, Metadata,
  research context, diagnostics, and Agent assistance remain subordinate.
- Prefer native macOS windows, split views, inspectors, toolbars, menus, sheets,
  alerts, file panels, controls, selection, and focus.
- Give every mutable fact one owner. Commands route to the focused
  window/document; identities, repositories, indexes, watchers, and registries
  are shared workspace services, not view state.
- Derive reading and research projections reversibly from authoritative
  Markdown. Managed Metadata remains a separate portable authority.
- Distinguish source, researcher prose, external Agent content, Agent Changes,
  Settle, Critique, Connect, and diagnostics through text and
  structure, not color alone.
- Apply §20's route applicability. Menus remain comprehensive; the toolbar stays
  bounded to frequent or high-value commands, and no toolbar command exists only
  there. Hover, drag, color, motion, secondary click, and gesture are
  supplementary.
- Construct no workspace until Application Support bootstrap is Ready.

### 18.2 Workspace shell and Document tabs

Each configured window contains one native split view:

1. **Sidebar**: Scholium/Triptych identity, Analyses–Topics–Works navigation,
   Triptych Notifications, and the selected workspace's Library.
2. **Document**: the selected Note or the restrained no-document state.
3. **Apparatus**: the trailing Research Inspector's read-only Overview and
   Connect projections.

The native window and split controller own frame, dividers, collapse,
compression, fullscreen, and toolbar geometry. Scholium owns semantic order,
readable peripheral thresholds, and the one initial Inspector reveal request.
It never continuously reasserts divider positions. All planes are opaque and
the system separator is the sole interactive boundary. Design §19 owns the
single decorative Sidebar-edge depth cue.

New windows show Library, hide Inspector, and begin in Analyses/Overview.
Visibility and workspace session state are installed before first presentation,
then native state is authoritative. Each workspace retains Library filters and
disclosure, selected tab, live Document mode, and Inspector mode. A transition
commits only after source safety succeeds; failure preserves the exact origin
workspace and buffer.

The native toolbar has stable leading Sidebar and Back/Forward controls,
Document identity/actions in the center, and trailing Inspector control.
Back/Forward traverse successful document visits only. The toolbar is stable
during loading and uses live safe areas. Pane visibility is expressed by the
actual pane, not duplicate controls or persistent custom selection styling.

The Inspector remains hideable whenever visible and showable only with a
Target. If an already-visible Inspector loses its Document, it presents **No
Document Selected** without stale content or automatic collapse.

With two or more open documents in the selected workspace, a Document-owned tab
strip appears only in the middle plane. One window-local controller partitions
tabs by vault role and presents only the selected workspace's group. A stable
Note appears at most once per window. Closing flushes safely and selects a
neighbor only within the current group; closing the last tab returns to the
no-document state.

Closing a window, switching route, or terminating must preserve any failing
save/conflict buffer and provide Retry. Window-session persistence is
best-effort only after source safety. Cold launch begins with no document
selected unless the researcher explicitly opens one.

The Sidebar header shows the Scholium wordmark, Triptych identity, and
Triptych Notifications. The no-document state contains only a decorative
document symbol, **No Document Selected**, and **Select a note in the Library
to read or edit.** as one read-only accessibility group.

Menus follow task ownership:

- **File**: Triptych/window, New Note, Import, Duplicate, Rename, Move, Reveal,
  and system-Trash actions.
- **Edit**: editing, Find, formatting, and Edit Metadata.
- **View**: Back/Forward, Heading Outline, Search, Document mode/text size,
  Sidebar, and Inspector.
- **Research**: Research Records, Settle, and Agent Changes when present.
- **Window**: standard windows plus Notifications.
- **Settings**: one searchable native list/detail window with **Application**,
  **This Triptych**, and **Research Guidance** groups.

Settings search indexes static page/control metadata, not research or Skill
content. Triptychs, Document Appearance, and Hotkeys are Application settings;
Metadata Profiles and Attention are Triptych settings; Agent Integration and
Zotero are Research Guidance. Scope is explicit where a page mixes This
Triptych and This Mac.

Hotkeys is machine-local and limited to frequent Scholium-specific menu
commands. It requires Command, rejects conflicts and reserved shortcuts, and
supports clear and restore. Standard macOS commands remain outside remapping.

### 18.3 Library and Search

The vertical Triptych workspace navigator presents Analyses, Topics, and Works
in stable order as peer destinations. The selected row uses one restrained
native navigation selection; rows show localized exact Note counts without
role descriptions, progress, pipeline state, or Attention badges. Unknown
initial count is unavailable, not zero.

Live opening may make the selected vault's trustworthy Library usable before
cross-vault projections are complete. Unavailable workspace rows remain
disabled; one persistent progress status names remaining work. Search follows
§13's explicit opening grades: current-buffer This Note Search is exact, and
source-fingerprint-validated This Vault lexical results may remain usable under
a nonblocking **Limited** notice. Triptych Search, Graph, Attention totals,
relations, and cross-Triptych Search remain unavailable until their complete
authoritative generation exists. Completion must not replace usable Library
content or move focus.

Library provides:

- one native Filter menu for Integrity, Metadata, and Order;
- one adaptive Expand/Collapse All control;
- one Add menu for immediate New Note and New Folder;
- a single scrollable hierarchy of real folders and Notes, including root Notes
  and empty folders; and
- explicit empty, loading, stale, and recoverable error states.

Folder and Note rows use one quiet hierarchy. Selection stays visible when
inactive; hover is weaker than selection. Titles expose full accessibility
names and pointer help when visually truncated. Folder disclosure, selection,
drop target, disabled, and focus states remain distinct.

New Note/Folder, Rename, Move, Copy Relative Path, Reveal, Expand/Collapse, and
system-Trash actions are available through menu and named accessibility routes;
secondary click and drag are redundant. Note drag payloads contain identity and
revision, Folder payloads contain vault and path, never source text. Invalid,
cross-vault, stale, self/descendant, protected, or ambiguous drops fail without
source change.

A successful New Note commit installs and opens its exact Library row
immediately, then performs one derived refresh. Filters that would hide it are
cleared, only its ancestors expand, unrelated disclosure and sort remain, and
Library reveal does not steal editor focus. If editor activation fails after
source commit, the UI offers Retry Edit/Source without duplicate creation.

Triptych Notifications has one stable Sidebar entry and exact nonzero total.
It opens the complete Agent Change/Settlement/Attention queue without changing
the selected workspace or Document. Zero is quiet; nonzero uses Attention
semantics but not a badge, unread model, animation, or auto-open.

An Agent Change requiring inspection and the current Note's Settlement reminder
may appear in the top-centered **Activity Notification Stack** over the window
without reflow. One item shows its exact state, Note, and valid actions. With
multiple items, the foremost real notification remains visible; hover or one
explicit disclosure reveals the remaining real notifications downward. The
disclosure names the exact count but never inserts a synthetic summary row. Each
notification keeps at most one primary action beside one bounded More menu;
copy is limited to its key state and Note and truncates before displacing
operations. A Changed Since Settle reminder with Agent Changes may show
**Review Changes**, which opens the exact temporary comparison directly. A
non-Agent save never invents an Agent Change. Dismiss hides
only the reminder; Settle Again and Mark Unsettled remain explicit researcher
choices in the Document Rail. The stack excludes structural Attention and
never becomes the complete queue.
Reduce Motion preserves all content and controls without geometry animation.

Window operation feedback follows consequence:

- redundant Confirmation/Information may use one concise transient toast with
  a bounded dwell and no redundant dismissal control;
- Warning, Error, partial commit, and recovery use one persistent notice with
  complete consequence and repair; and
- field validation stays adjacent to its field.

The operation owner retains Retry, Compare, or recovery. Presentation owns
order, announcement, and dismissal only. Persistent feedback never times out.

The complete Notifications queue is a window-owned native popover. Sidebar
opens Triptych scope; Inspector may open a current-Note subset. Popover closure
does not dismiss an Agent Change or alter Settlement. The queue
presents Agent Changes, then Settlement reminders, then grouped structural
issues with exact reason, Note/path location, and only valid actions.
Search/filter changes only this presentation.
Stale or failed refresh retains last trustworthy content and Retry; empty and
unavailable remain distinct.

Scholium MCP produces no system notification and never activates the App or
moves focus. In-app Agent Change routes carry exact Triptych, `change_id`, Note,
operation, and fingerprint identity. Reopening waits for authoritative
validation rather than guessing or dropping the route.

Workspace switching stages the destination from trustworthy source and commits
atomically after source safety. It never replaces the origin with a full-page
loading state during background work. Library loading uses an explicit system
progress indicator rather than skeleton decoration.

System-Trash actions always use §6 confirmation. After a committed move, focus
advances to the next row, previous row, then Library; only absent documents
close. Finder owns restoration.

Shared Search follows §13: one compact centered surface, visible scope, bounded
provider-specific results, typed completion, Explain Query, exact freshness,
and distinct invalid, ambiguous, unavailable, partial, stale, and empty states.
All is the default provider selection and shows separate Notes and Research
Records groups without interleaving rank; Notes and Records remain directly
selectable dedicated paths. Completion edits visible query text only and shares
one keyboard selection with results.
