# Specification: Interface Shell and Library

Part of the canonical document set rooted at [SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md).
This chapter owns Sections 18.1–18.3: global interface principles, workspace shell, Library, and Search; sibling chapters do not restate it.

## 18. Canonical interface contract

Sections 1–17 own scholarly and product meaning. This section defines its
native presentation and state ownership without restating each workflow.

### 18.1 Interface principles

- Keep Document the largest, most stable region; navigation, Properties,
  research context, diagnostics, and agent assistance remain subordinate.
- Prefer native macOS windows, split views, inspectors, toolbars, menus, sheets,
  alerts, file panels, controls, selection, and focus. Custom presentation must
  preserve equivalent menu, keyboard, accessibility, cancel, and recovery.
- Give every mutable fact one owner. Route commands to the focused window or
  document; identities, repositories, indexes, watchers, and registries are
  shared workspace services, not view state.
- Derive Review, Edit, Source, Properties, Search, and research views
  reversibly from authoritative Markdown; projections never reconstruct
  writable source.
- Distinguish source, researcher prose, agent content, Discussion turns,
  Action output, Settle, Critique, Connect, and diagnostics by text and
  structure, not color alone.
- Preserve menu, toolbar, keyboard, pointer, focus, accessibility, cancel,
  compare, retry, conflict, and recovery routes. Hover, drag, color, motion,
  secondary click, and gestures are never the only route to a core task.
- Gate all workspace composition behind the single Application Support
  bootstrap owner. A storage failure is an app-root state, not a workspace
  sheet, alert loop, hidden temporary runtime, or view-local fallback.

### 18.2 Workspace shell and Document tabs

The configured shell exists only after Application Support reaches Ready.
While storage is unavailable, no workspace route, window session, repository,
watcher, index, or restore task may be constructed, and workspace commands are
disabled rather than queued against a hidden runtime.

Each configured window contains exactly one native split view with three
sibling items:

1. **Sidebar:** a Library navigation region containing Scholium and Triptych
   identity; one vertical **Analyses / Topics / Works**
   TriptychWorkspaceNavigator; one stable Triptych Attention entry; one
   title-style LocationPicker for **Library**, **Set Aside**, and **Trash**;
   one selected-workspace-and-location source region; and Library-local Filter
   and Add. Settings is not a Library destination.
2. **Document:** selected note or the restrained no-document empty state.
3. **Apparatus:** Research Inspector's read-only Overview, Connect, and Actions
   projections. It never owns buffers, autosave, Undo, or conflicts;
   full chronology belongs to Research Records.

The workspace starts at **1180 × 760**, not a minimum. Scene state owns route
identity and restoration; the native window and split controller own divider,
compression, collapse, fullscreen, and frame geometry. Scholium never
persists, restores, observes, or continuously reasserts divider geometry. The only additional
initial condition is that a newly created window's first explicit Apparatus
reveal may request a provisional **320pt** readable thickness once, after the
native split is attached. That request yields to the remaining Document space
and native bounds; it is not a minimum, maximum, restored divider value, or
later-reveal preference. After that one transition, the native container and
direct user resizing remain authoritative. Scholium declares no scene/window minimum
unless the complete adaptation matrix proves one necessary. The sole specified
content constraint is the expanded Library's **300pt minimum readable
thickness**: the native split must keep it at or above that boundary or
collapse it. This is neither a preferred width, restored divider value, nor parallel
geometry owner. Library remains a semantic Sidebar and Apparatus a semantic
Inspector. All three planes are opaque, and the native tracking separator
remains the sole interactive inter-pane boundary and divider-geometry owner.
At the Sidebar–Document edge alone, the Workspace adds §19.3's secondary
**document-navigation boundary** depth cue. It is visually continuous from the
top of the window through the titlebar/toolbar band to the bottom, falls only
into Sidebar, and remains behind the native toolbar and tracking separator.
It neither obscures nor intercepts system chrome, changes divider geometry, or
creates another boundary. It is absent while Sidebar is collapsed, mirrors the
logical edge in right-to-left presentation, and never appears between Document
and Apparatus.

New windows show Library and hide Apparatus. Initial or restored peripheral
visibility is installed before the native split's first presentation; the
window never draws an expanded Apparatus and then retracts it during launch.
Restore applies both visibility values once; then native collapsed state is authoritative and the model only
mirrors Library and Apparatus visibility for labels, commands, and the next
session. Menu, toolbar, and content actions send explicit per-window intents to
the native controller; model observation never continuously reasserts split
state. Notes/tabs never reconstruct the shell or change peripheral
visibility. The selected workspace is per-window presentation state, not a
Note, vault, or Markdown fact. Each workspace retains its own Location,
filters, disclosure, source-list scroll, selected tab, live Document mode, and
Inspector mode. A workspace transition saves or fails safely before it commits
the destination session; it never replaces a dirty buffer or presents the
destination identity over retained origin content. A new window's first
workspace and first Inspector reveal begin in Analyses and Overview.

The native titlebar owns traffic-light, drag, and height geometry. Its one
window toolbar exists inert from the first configured frame;
loading may replace items but not move traffic lights or change band height.
Opaque regions extend beneath it, and controls use the live safe area rather
than a measured toolbar height.

Sidebar and Inspector each keep one visibility control at a stable position in
that native toolbar. The Sidebar control sits immediately before the first
tracking separator at the logical trailing side of Sidebar; it mirrors in
right-to-left presentation and remains visible when Sidebar collapses. The
Inspector control remains before the Inspector tracking separator. Native
collapsed state changes each item's accessible Show/Hide label, value, and
explicit per-window action; collapse and expansion never transfer a control,
change toolbar item topology, or add a pane-local duplicate. Visibility is
expressed by the actual pane rather than a persistent selection underline or
custom active enclosure. Tracking separators remain structural bounds. Add no
split-item accessory row, custom title strip, Inspector replacement, ellipsis,
fixed height, automatic glass-like item, or Liquid Glass.

Attention never enters the Document toolbar. While Sidebar is visible, the
stable Triptych-owned control beside its identity is the workspace-chrome
entry and popover anchor; collapsing Sidebar removes that control without
transferring a count, symbol, or anchor. Inspector retains its distinct
current-Note summary. **Window → Attention** is enabled only when the focused
window has a visible Triptych entry or Inspector summary capable of anchoring
the transient popover; otherwise showing Sidebar restores the Triptych route.

The Inspector toolbar control and View command send one explicit intent through
the exact window coordinator to the native split.
The Inspector routes share selected-document availability and preserve native
transition and geometry. Inspector Show remains visible but disabled without a
Target; a visible Inspector can always be hidden. Research Records remains a
separate Triptych-bound auxiliary window; opening it from the document toolbar
explicitly reapplies **This Note** Scope without changing Inspector state.

With two or more documents in the selected workspace, a Document-owned strip
appears only in the middle item. One window-local tab owner partitions tabs by
vault role; each tab references one retained editor session, and the single
native tab controller presents only the active group. Inactive groups remain
layout-neutral, inert, and accessibility-hidden while their sessions remain
available for return. Scholium supplies equal-width selection and
save-before-transition. One stable document has at most one tab in a window;
repeated open or **Open in New Tab** selects its owning workspace and existing
tab. Close flushes and selects a retained neighbor only inside the current
group; last close returns that workspace to no-note. Tabs create no window
group, parallel controller, split, or toolbar owner. Prototype styling has no
authority; selector styling is provisional.

Window close, route handoff, and application termination are bounded. A
content flush, save, or conflict failure keeps the affected window and exact
buffer available with a retry path. Machine-local window-session or layout
persistence is best-effort after content is safe; its failure is diagnosed but
does not veto close or misreport a source-save failure. Late lifecycle work may
not act on a newer route, window, document, or close attempt.

The Library BrandHeader sits below window controls. A static Scholium wordmark
occupies its own identity line. The next line pairs the Triptych identity menu
with one logical-trailing Triptych Attention control on the 28pt peripheral
page edge; neither turns the wordmark into a second toolbar. The control uses a
direct `exclamationmark.triangle` SF Symbol and places an exact nonzero Triptych
total beside, never over, that symbol. Its resting background is transparent;
one complete interaction surface appears only for hover, keyboard focus, press,
or the open popover. Traffic-light alignment is visual reference only, never
derived geometry. No-note is
one centered `doc.text` symbol, **No Document Selected**, and the secondary
sentence **Select a note in the Library to read or edit.** It has no card,
button, motion, focus target, source state, or duplicate creation route. The
symbol is decorative; the two visible strings form one VoiceOver-readable
group. No Collapse Note, custom `<<`,
Back/Forward, Recents, or Quick Open exists.

Menus follow researcher tasks:

- **File:** Triptych/window create/open; direct **New Note** at the focused
  vault root; Import; Duplicate; Rename; Move; Reveal; Checkpoint create/restore.
- **Edit:** editing and **Edit Properties…**.
- **View:** Search, document mode/text size, Sidebar, Research Inspector.
- **Window:** standard window navigation plus **Attention**. The command is
  enabled only when the focused window has a visible Triptych or Inspector
  Attention anchor, and opens that anchor's transient popover.
- **Research:** role-valid Actions and **Triptych Records**, never Attention
  or Checkpoints.
- **Settings:** Triptychs, Property profiles, Appearance, Attention, and one
  Research Guidance surface for Methods, Profiles & Practices, Collaboration,
  Sources & Integrations, and Recovery & Technical.

### 18.3 Library and Search

- TriptychWorkspaceNavigator is Library's top-level vertical navigation. Its
  three full-width rows appear in stable Analyses, Topics, Works order and
  expose no role description, icon, Attention count, progress, or pipeline
  mark. The selected row uses Semibold primary ink plus one persistent native-
  style Navigation selection surface. An unselected row uses Regular secondary
  ink; hover or focus adds the same purpose-owned continuous shape with a
  quieter surface and primary ink, without changing weight or geometry. Rows
  have no underline, Accent mark, capsule band, enclosing border, shadow, or
  full-width rule. The group exposes one selected workspace, uses Up/Down Arrow
  within the group, and lets Tab continue into the selected workspace without
  pointer activation creating a keyboard-only focus ring.
- Each workspace row places the last trustworthy exact count of ordinary
  active Notes in that role vault at its logical trailing edge. Set Aside and
  Trash do not contribute. The count is noninteractive neutral inventory
  metadata: system Sans, monospaced digits, and `mutedText` in selected,
  unselected, hover, focus, and inactive-window states. Zero remains visible;
  an unavailable first result uses an em dash rather than claiming zero; a
  refresh retains the last trustworthy count. The row's accessible name or
  value states the workspace and localized Note count.
- One native **Filter** menu groups Integrity, Metadata, Properties, Order, and
  Actions with at most one submenu level. Its icon-only entry hides the
  redundant outer menu indicator; native submenu chevrons remain. Current
  Library rows and filters have no Review, Unreviewed, Qualified, or
  Unqualified state.
- One icon-only disclosure button sits beside Filter. When any Folder in the
  current tree is visibly expanded, it presents **Collapse All Folders** with
  one direct collapse symbol and collapses the complete tree; otherwise it
  presents **Expand All Folders** with one direct expand symbol and expands the
  complete tree. It never constructs either mark by stacking glyphs.
  It is unavailable when the tree contains no expandable Folder. The action
  mutates only the current vault-and-Location disclosure set and never source, order,
  selection, or another window. Every successful in-app active-Note navigation
  independently switches Library to that Note's exact Triptych Scope and
  Library Location, clears filters only when they exclude that Note, expands
  only its ancestors, and scrolls only as much as needed without transferring
  keyboard focus. Manually browsing a different Scope remains possible until
  the next document navigation.
- Notes outside folders appear at vault root as ordinary Library rows.
- Folder/note rows form one hierarchy at one semantic callout size and a
  provisional **28pt minimum** rhythm that grows rather than clips when text
  requires it. Folder and unselected Note titles use Regular; only the selected
  Note uses Semibold. Use color, indentation, symbols, and this restrained
  selection weight—not size or permanent Folder emphasis. One leading semantic
  slot contains either a folder disclosure or a Note symbol; a folder never
  repeats both disclosure and folder icon. Notes are one line without sublines,
  use middle truncation for the Beta, and expose full titles through pointer
  help and accessibility names. The Beta adds no custom marquee, fade-mask
  reveal, or scroll-linked title motion. At most one redundant
  state mark precedes title; selected, focused, disclosed, drop-target, and
  inactive-selected remain distinct, and selection stays visible off-focus.
- Folder and Note rows scroll as one native hierarchy; no Folder becomes a
  sticky section or floating group row. The LocationHeader and its
  Filter/disclosure/Add controls remain outside the Source List scroll owner
  and stay available while the hierarchy scrolls.
- Every enabled, unselected Note and Folder row provides one restrained
  full-row hover response. Selection remains the stronger persistent state and
  does not change on hover; pointer feedback never becomes the only route to
  activation or any row action.
- A draggable ordinary Note uses one process-private identity-and-revision
  payload, never source text. A draggable ordinary Folder uses one
  process-private vault-and-path payload. An eligible Folder row and the
  Library LocationHeader advertise Move and provide a restrained temporary
  target surface; every other row and Location rejects the drop. Note
  completion uses the ordinary revision-checked Move transaction; Folder
  completion uses the ordinary complete-descendant flush-and-recheck Move
  transaction. Both resume through the established derived refresh path.
- When Library is selected, the LocationHeader Add menu offers direct **New
  Note** and **New Folder** at the current vault root. A secondary click in
  unoccupied Source List space offers the same two actions without becoming
  their only route.
  Every ordinary folder row offers direct **New Note** and **New Folder**, then
  **Rename Folder…**, **Move Folder…**, conditional subtree expansion/collapse,
  Copy Relative Path, Reveal in Finder, and destructive **Move Folder and Notes
  to Trash…**. Equivalent accessibility actions provide non-secondary-click
  routes. Neither creation action opens a sheet. Library enumerates empty real
  directories. Protected machine-managed folders and ambiguous
  projections retain only safe nonmutating navigation.
- After a successful New Note source-and-identity commit, Library immediately
  installs and opens an exact source-bound row explicitly marked ahead of
  disposable derived state. It does not wait for Triptych-wide identity
  reconciliation, graph, Search, or research projection rebuilds, and it never
  presents placeholder graph values as current. The Workspace queues one
  complete background refresh before releasing its source-mutation lease;
  matching watcher work cannot start a competing rebuild, and the resulting
  complete generation replaces the temporary row. Library clears filters that
  could exclude the created row, expands that row's folder ancestors, retains
  unrelated disclosure and ordinary sorting, and scrolls the selected row into
  view once. This reveal does not transfer keyboard focus.
- The Library Location shows no total. Triptych Attention treats zero as the
  steady state, **1–3** unresolved items as its primary design condition, and
  larger queues as exceptional accumulation rather than a separate mode or
  hard cap. Its stable BrandHeader control always remains a direct entry. At
  zero it uses secondary ink without a visible number. At nonzero the warning
  symbol and exact aggregate Triptych total use Attention ink; the number
  remains beside the symbol and never becomes a notification badge. Its resting
  background remains transparent in both states. Hover, keyboard focus, press,
  and the open popover apply the shared shallow interaction surface behind the
  complete symbol-and-count target; the symbol never owns a separate circle.
  It neither auto-opens, steals focus, pulses, nor repeats attention-seeking
  motion. Opening it presents the complete Triptych queue without changing the
  selected workspace, Location, source content, Document, or Sidebar selection.
  Inspector may open the same queue with a current-Note subset. Attention is
  not a Location.
- Refresh preserves the last trustworthy Triptych total. A first load with no
  trustworthy result never claims zero; checking uses the control's bounded
  native progress state. Failure without a trustworthy result presents a
  visible non-counting unavailable state from the same control and exposes
  Retry in the popover. Resolving or dismissing the final item removes only the
  visible number and Attention emphasis; the focused control remains stable.
- Attention is one native transient popover owned by the exact
  Workspace window, never an application-wide Scene, sheet, inline destination,
  custom panel, or always-on-top surface. Its preferred bounded content size is
  **420 × 480pt**. Triptych entry and Inspector summary each anchor the same
  Triptych-owned queue to their complete trigger.
  Native transient behavior dismisses it after outside activation or Escape;
  opening a Note or Resynthesize also dismisses it. It has no custom or manual
  close control. Dismissing and reopening within the same Workspace may retain
  its session filter and selection. Activating a different Workspace window
  resets query, kind filter, selected task, and current-Note subset; the
  machine-local dismissal ledger is unaffected. The Triptych entry opens the
  complete queue; Inspector entry adds the current Note. Switching workspace
  neither filters nor retargets an already open Triptych queue.
- The Attention popover groups **Identity & Metadata** (Change Attribution
  Needed, Malformed Metadata, Unresolved Identity), **Structure & Connections**
  (Possible Orphan, Broken Connection, Ambiguous Connection), and **Revision &
  Reliance** (Changed Since Settled, Material Changed Since Use). Each row shows
  the issue, resolved Note title, locator, and only real available actions.
  Ordinary rows provide Inspect and timed Dismiss. Material Changed Since Use
  retains Inspect, Resynthesize, and Leave Unchanged. Inspect opens the Note in
  the exact owning Workspace without global window search or notification and
  dismisses the popover; its session selection remains available if the same
  Workspace reopens Attention before the task changes.
- Loading retains the popover structure; refreshing, stale, or failed refresh
  retains the last trustworthy list when one exists and exposes status plus
  Retry; failure without a prior result shows a complete error; an empty queue
  shows a quiet completion state. The heading and search/filter controls remain
  top-aligned in ready, loading, empty, stale, and complete-error states; only
  the list or state region below them consumes the remaining height. When
  resolution, refresh, or dismissal removes
  the selected item, focus moves next, previous, then the popover filter/search
  control. Count updates use the same Scope and dismissal ledger as the popover.
- The stable LocationHeader contains one title-style LocationPicker and only
  the actions applicable to the selected Location. Its current title always
  identifies **Library**, **Set Aside**, or **Trash**. Every Location uses the
  same adaptive Folder disclosure button when its current category projection
  contains a hierarchy; the button remains unavailable when there is no
  expandable Folder. Library additionally shows Filter and Add. Set Aside and
  Trash omit only those Library-specific controls. The header keeps the same
  position and height while the source region changes. Its matching icon-only
  controls use one exact **28 × 28pt** target, secondary ink at rest, primary
  ink plus the shared shallow semantic interaction surface on hover, native
  keyboard focus, and the same purpose-owned continuous corner recipe. Filter,
  disclosure, and Add reuse this complete presentation regardless of whether a
  native Menu or Button owns activation. They add no persistent Accent tint,
  independent radius, hover animation, scale, or shadow.
- The LocationPicker is one native menu of three mutually exclusive items.
  Its title presentation is quiet and borderless: it has no enclosing fill,
  bezel, capsule, custom disclosure glyph, or persistent Accent tint. Its title
  uses Regular secondary ink at rest, matching the ordinary command icons in
  the same header without becoming a section heading. Hover or keyboard focus
  promotes the title to primary ink and places the shared shallow interaction
  surface behind its complete native title-and-indicator target at the
  preferred **28pt** height. Hover, focus, and press use the same continuous
  editorial-control corner recipe and never stack a native hover enclosure
  beneath the Scholium surface.
  Its selected item uses a checkmark; Set Aside and Trash may show a last-
  complete count as neutral location metadata. Missing, refreshing, or failed
  counts never disable selection or change the selected Location. Opening the
  menu enters its native keyboard order; Arrow keys, Home, End, and Return
  navigate and choose, while Escape closes the menu and restores focus to the
  LocationPicker. Leaving Set Aside or Trash requires choosing Library or
  another Location; there is no parallel Back control, footer toggle, or
  lifecycle tab row.
- Ordinary workspace and Location navigation stages the target session and
  Source List from the latest accepted Workspace snapshot while the last
  committed workspace session remains intact, then commits the destination
  atomically after document safety succeeds. It never replaces trustworthy
  content with a full-page Loading state merely because an in-memory
  projection crosses an asynchronous boundary. Loading remains available only
  when no trustworthy committed projection exists or an explicit
  recovery/refresh owns that state. A staged target failure retains the prior
  workspace, tabs, Document, Inspector, Location, and content and reports the
  failure; it never presents destination identity over origin content.
- **Set Aside** and **Trash** are same-plane Library Locations, never overlays,
  cards, sheets, or separate Sidebar modes. Selecting one replaces only the
  source-region content; BrandHeader, TriptychWorkspaceNavigator,
  Triptych Attention state,
  LocationHeader retain their ownership.
  All three Locations project the same native Folder-and-Note outline and row
  interaction grammar; lifecycle filtering and category-valid actions are the
  only intentional differences.
  Switching workspace restores that workspace's retained Location and content.
  An empty Location remains selected and shows its own short empty state rather
  than silently returning to Library. At most one Location content subtree
  accepts input or appears in the accessibility tree; an implementation may
  retain inactive presentation solely to preserve disclosure or scroll context
  only while it remains layout-neutral, inert, and accessibility-hidden.
- Library, Set Aside, and Trash empty, loading, and error states are
  page-level Location content: they align to the shared **28pt** peripheral
  edge and begin one **16pt** section step below LocationHeader. They never
  borrow the tighter **12pt** OutlineRow surface inset. Populated Note and
  Folder rows retain that row inset and their existing hierarchy rhythm. An
  initial Library load with no trustworthy projection uses one system
  indeterminate progress indicator and the explicit **Loading Library…** name;
  it does not use a shimmer, skeleton, or moving highlight. Staged replacement
  never places that loading treatment over retained trustworthy content.
- Lifecycle rows reuse the same provisional 28pt minimum OutlineRow rhythm and
  Note semantic slot. A single-line truncated title opens the note in place and
  retains the complete row width. Its quiet secondary-ink **Put Back** control
  appears as a trailing native overlay above a semantic Sidebar material veil
  on full-row pointer hover or keyboard focus; it neither reserves title width
  nor reflows the row. Put Back is a direct nonmodal action and opens no
  confirmation or destination sheet. The row's context menu and named
  accessibility action remain available without hover. Ordinary lifecycle rows
  draw no separator. After Put Back, Move to Trash, or permanent deletion
  removes a row, focus moves next, previous, then LocationPicker; cancellation
  or failure restores the originating row. A successful category move of the
  currently presented Note also removes that document page and shows the
  no-document empty state; explicit selection in the destination Location
  remains the route for browsing its content.
- Debate Importance ordering first requires one exact Debate Scope.
- Shared Search follows Section 13: one compact centered surface, always-visible
  provider-specific scope, no empty sheet, and bounded Note or Record results
  that identify match context, source freshness, and destination. Typing a
  valid field prefix may open one bounded capability-driven completion list;
  accepting an item edits only the visible query text. Completion and results
  never expose two simultaneous keyboard selections or turn Search into an
  advanced workspace. **Explain Query** presents the typed explanation carried
  by the Application Search response and shared with CLI—provider, scope,
  clauses, direction, normalization, ordering, and limitations. The Search
  surface may present a compact summary with an explicit route to the complete
  explanation or expose the complete explanation on demand; it need not reserve
  a permanent explanation row for every query. Whatever presentation is used
  remains discoverable and never reparses query text or constructs a second
  interpretation. Provider mismatch,
  ambiguous identity, not-applicable clauses, invalid syntax, unavailable
  Graph, stale source, and no matches retain distinct inline states.
