# Specification: Interface Shell and Library

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 18.1–18.3.

## 18. Canonical interface contract

Sections 1–17 own scholarly and product meaning. This section defines its
native presentation and state ownership without restating each workflow.

### 18.1 Interface principles

- Keep Document the largest, most stable region; navigation, Metadata,
  research context, diagnostics, and agent assistance remain subordinate.
- Prefer native macOS windows, split views, inspectors, toolbars, menus, sheets,
  alerts, file panels, controls, selection, and focus. Custom presentation must
  preserve equivalent menu, keyboard, accessibility, cancel, and recovery.
- Give every mutable fact one owner. Route commands to the focused window or
  document; identities, repositories, indexes, watchers, and registries are
  shared workspace services, not view state.
- Derive Review, Edit, Source, Search, and research views reversibly from
  authoritative Markdown. Metadata is a distinct portable authority keyed by
  stable Note identity; neither source nor metadata projections reconstruct
  the other writable owner.
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
   selected-workspace Library source region; and Library-local disclosure,
   Filter, and Add controls. Settings is not a Library destination.
2. **Document:** selected note or the restrained no-document empty state.
3. **Apparatus:** Research Inspector's read-only Overview, Connect, and Actions
   projections. It never owns buffers, autosave, Undo, or conflicts;
   full chronology belongs to Research Records.

The workspace uses the initial content size owned by §19.4, not a minimum. Scene state owns route
identity and restoration; the native window and split controller own divider,
compression, collapse, fullscreen, and frame geometry. Scholium never
persists, restores, observes, or continuously reasserts divider geometry. The only additional
initial condition is the one-time first-Apparatus-reveal request owned by
§19.3, after the native split is attached. That request yields to the remaining Document space
and native bounds; it is not a minimum, maximum, restored divider value, or
later-reveal preference. After that one transition, the native container and
direct user resizing remain authoritative. The Library and Apparatus readable-
thickness metrics are owned by §19.3. The
native split must keep each expanded peripheral plane at or above its boundary;
Apparatus has no application-defined maximum. These are neither preferred
widths, restored divider values, nor parallel geometry owners. Library remains
a semantic Sidebar and Apparatus a semantic Inspector. All three planes are
opaque, and the native tracking separator remains the sole interactive
inter-pane boundary and divider-geometry owner.
At the Sidebar–Document edge alone, the Workspace adds §19.3's secondary
**document-navigation boundary** depth cue. It is visually continuous from the
top of the window through the titlebar/toolbar band to the bottom, falls only
into Sidebar, and remains behind the native toolbar and tracking separator.
It neither obscures nor intercepts system chrome, changes divider geometry, or
creates another boundary. It is absent while Sidebar is collapsed, uses the
logical Sidebar edge, remains structurally mirrorable for the deferred
right-to-left interface scope in §18.7, and never appears between Document and
Apparatus.

New windows show Library and hide Apparatus. Initial or restored peripheral
visibility is installed before the native split's first presentation; the
window never draws an expanded Apparatus and then retracts it during launch.
Restore applies both visibility values once; then native collapsed state is authoritative and the model only
mirrors Library and Apparatus visibility for labels, commands, and the next
session. Menu, toolbar, and content actions send explicit per-window intents to
the native controller; model observation never continuously reasserts split
state. Notes/tabs never reconstruct the shell or change peripheral
visibility. The selected workspace is per-window presentation state, not a
Note, vault, or Markdown fact. Each workspace retains its own filters,
disclosure, source-list scroll, selected tab, live Document mode, and
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
that native toolbar. Sidebar and the window-local Back/Forward pair occupy the
fixed leading zone before the first tracking separator and remain beside the
traffic lights as the Sidebar resizes or collapses. Back/Forward traverse the
nonpersistent sequence of successfully visited Documents and never become a
source, editor, Undo, tab, or per-Note mode history. The Inspector control
occupies the fixed trailing edge after the Inspector tracking separator. Native
collapsed state changes each visibility item's accessible Show/Hide label,
value, and explicit per-window action; collapse and expansion never transfer a
control, change toolbar item topology, or add a pane-local duplicate. Visibility
is expressed by the actual pane rather than a persistent selection underline or
custom active enclosure. Tracking separators remain structural bounds. Add no
split-item accessory row, custom title strip, Inspector replacement, ellipsis,
fixed height, automatic glass-like item, or Liquid Glass.

Notifications never enters the Document toolbar. While Sidebar is visible, the
stable Triptych-owned control beside its identity is the workspace-chrome
entry and preferred popover anchor; collapsing Sidebar removes that control
without transferring its count or symbol. Inspector retains its distinct
current-Note summary. A focus-neutral Document activity stack is a third
temporary anchor only while one or more Action activities require researcher
attention under §18.5; it is presentation over the same queue, not another
count or state owner. **Window → Notifications** prefers the visible Triptych
entry, then that activity stack, then a nonempty Inspector summary. Without a
visible anchor, showing Sidebar restores the Triptych route.

The Inspector toolbar control and View command send one explicit intent through
the exact window coordinator to the native split.
The Inspector routes share selected-document availability and preserve native
transition and geometry. Inspector Show remains visible but disabled without a
Target; a visible Inspector can always be hidden. If a workspace transition
leaves an already-visible Inspector without a selected Document, Apparatus
retains its structure and presents one restrained **No Document Selected**
content state rather than an empty plane, stale origin projection, or automatic
collapse. Research Records remains a separate Triptych-bound auxiliary window;
opening it from the document toolbar reapplies **This Note** Scope when a
resolved Note is selected and **Triptych** Scope when no Document is selected,
without changing Inspector state.

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
group, parallel controller, split, or toolbar owner.

Window close, route handoff, and application termination are bounded. A
content flush, save, or conflict failure keeps the affected window and exact
buffer available with a retry path. Machine-local window-session or layout
persistence is best-effort after content is safe; its failure is diagnosed but
does not veto close or misreport a source-save failure. Late asynchronous work may
not act on a newer route, window, document, or close attempt.

An ordinary application-cold launch opens the selected Triptych with no
document selected; it does not restore or implicitly open a previous document.
Only an explicit researcher route, such as an intentional document open, may
bypass that no-note starting state.

The Library BrandHeader sits below window controls. A static Scholium wordmark
occupies its own identity line. The next line pairs the Triptych identity menu
with one logical-trailing Triptych Notifications control on §19.3's peripheral
page edge; neither turns the wordmark into a second toolbar. The control uses a
direct `bell` SF Symbol and places an exact nonzero Triptych
total beside, never over, that symbol. Its resting background is transparent;
one complete interaction surface appears only for hover, keyboard focus, press,
or the open popover. Traffic-light alignment is visual reference only, never
derived geometry. No-note is
one centered `doc.text` symbol, **No Document Selected**, and the secondary
sentence **Select a note in the Library to read or edit.** It has no card,
button, motion, focus target, source state, or duplicate creation route. The
symbol is decorative; the two visible strings form one VoiceOver-readable
group. No Collapse Note, custom `<<`, Recents, or Quick Open exists.

Menus follow researcher tasks:

- **File:** Triptych/window create/open; direct **New Note** at the focused
  vault root; Import; Duplicate; Rename; Move; Reveal.
- **Edit:** editing and **Edit Metadata…**.
- **View:** Back/Forward, Search, document mode/text size, Sidebar, Research
  Inspector.
- **Window:** standard window navigation plus **Notifications**. The command is
  enabled only when the focused window has a visible Triptych or Inspector
  Notifications anchor, and opens that anchor's transient popover.
- **Research:** role-valid Actions and **Triptych Records**, never Notifications.
- **Settings:** one searchable native list/detail window restores its last
  destination. The titlebar retains native traffic-light and drag geometry but
  hides the redundant window-title label; the navigation plane starts with
  search rather than a repeated Settings heading. Triptych registration and selection remain inside the
  Triptychs detail; navigation exposes no global Triptych selector.
  Static page, section, control, and command metadata supplies Settings search;
  authored Skill, reference, YAML, profile, and document content is never
  indexed into it. Navigation has three explicit groups: **Application** owns
  Triptychs, Document Appearance, and Hotkeys; **This Triptych** owns Metadata
  Profiles and Attention; **Research Guidance** owns Skills,
  Action Profiles, Agent Access, and External Tools & Citations. Scoped detail
  sections say **This Triptych** or **This Mac** where one page presents both.
  No General or Advanced destination becomes an unrelated catch-all.
- Hotkeys is machine-local and exposes only the closed catalog of frequent
  Scholium-specific menu commands. Recording requires Command, rejects a
  duplicate active binding and standard macOS reservation inline, and supports
  explicit clear, per-command default restoration, and complete default
  restoration. Accepted changes update the corresponding menu shortcut
  immediately. Standard macOS commands, including Settings, window, document,
  Edit, Find, formatting, and text-size conventions, retain their system or
  application-defined shortcuts and never enter this remapping surface.

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
  Notes in that role vault at its logical trailing edge. The count is
  noninteractive neutral inventory
  metadata: system Sans, monospaced digits, and `mutedText` in selected,
  unselected, hover, focus, and inactive-window states. Zero remains visible;
  an unavailable first result uses an em dash rather than claiming zero; a
  refresh retains the last trustworthy count. The row's accessible name or
  value states the workspace and localized Note count.
- Live application opening may publish the selected workspace's first
  trustworthy Vault projection before the complete Triptych projection. Once
  that Vault's Library is usable, the shell removes its full-page Loading state
  and keeps those rows interactive while one persistent derived-state progress
  status names the remaining background work. Workspace rows without a first
  trustworthy projection retain the em dash and remain unavailable; they never
  claim zero or stage an empty destination. Graph, shared Search, Attention
  totals, Research Records, and Research Actions remain unavailable rather than
  presenting a selected-Vault subset as complete. One later complete generation
  atomically supplies all three Vaults and those cross-Vault projections without
  replacing, clearing, or moving focus from the usable Library. Snapshot and CLI
  delivery continue to wait for a complete Triptych projection.
- One native **Filter** menu groups Integrity, Metadata, Order, and
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
  mutates only the current vault's Library disclosure set and never source,
  order, selection, or another window. Every successful in-app Note navigation
  independently switches Library to that Note's exact Triptych Scope and
  Library, clears filters only when they exclude that Note, expands
  only its ancestors, and scrolls only as much as needed without transferring
  keyboard focus. Manually browsing a different Scope remains possible until
  the next document navigation.
- Notes outside folders appear at vault root as ordinary Library rows.
- Folder/note rows form one hierarchy at one semantic callout size and use the
  Library row metric owned by §19.3, growing rather than clipping when text
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
  sticky section or floating group row. The Library header and its
  Filter/disclosure/Add controls remain outside the Source List scroll owner
  and stay available while the hierarchy scrolls.
- Every enabled, unselected Note and Folder row provides one restrained
  full-row hover response. Selection remains the stronger persistent state and
  does not change on hover; pointer feedback never becomes the only route to
  activation or any row action.
- A draggable ordinary Note uses one process-private identity-and-revision
  payload, never source text. A draggable ordinary Folder uses one
  process-private vault-and-path payload. An eligible Folder row and the
  Library header advertise Move and provide a restrained temporary target
  surface; every other row rejects the drop. Note
  completion uses the ordinary revision-checked Move transaction; Folder
  completion uses the ordinary complete-descendant flush-and-recheck Move
  transaction. Both resume through the established derived refresh path.
- The Library header Add menu offers direct **New
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
  The Document transition itself opens Edit and transfers focus to the exact
  body insertion point only after editor mode acknowledgement. This explicit
  writing focus is separate from Library reveal and remains recoverable when
  the editor fails after the durable source commit.
- Library shows no total. Triptych Notifications treats zero as the
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
  selected workspace, source content, Document, or Sidebar selection.
  Inspector may open the same queue with a current-Note subset. Notifications is
  not Library navigation.
- One or more **Needs Attention**, **Result Ready**, or **Recovery Required**
  Action activities also present one centered **Activity Notification Stack**
  at the top of Document. Its front control always states the exact activity
  total, latest state, and latest target; at most two additional decorative
  surfaces remain visibly offset behind it, so plurality is evident without
  pointer input. Hover or keyboard focus only increases those two offsets
  enough to preview the stack and never reveals item content or expands the
  complete queue. Activation opens the ordinary complete Triptych
  Notifications popover from that exact control. The stack has no independent
  Dismiss, selection, filter, unread state, or timeout. Waiting and Running
  remain in the persistent queue and Triptych total without occupying
  Document. When no attention-requiring Action remains, the stack disappears;
  Reduce Motion retains the collapsed layers and exact text without the preview
  transition. A presented current-Note Review task owns the Document top while
  the stack waits without dismissing any activity; the stack returns after that
  task closes or completes when attention-requiring Actions remain. A pending
  one-time system-notification permission prompt waits while either surface is
  present and may appear only after both disappear.
- Refresh preserves the last trustworthy Triptych total. A first load with no
  trustworthy result never claims zero; checking uses the control's bounded
  native progress state. Failure without a trustworthy result presents a
  visible non-counting unavailable state from the same control and exposes
  Retry in the popover. Resolving or dismissing the final item removes only the
  visible number and Attention emphasis; the focused control remains stable.
- Notifications is one native transient popover owned by the exact
  Workspace window, never an application-wide Scene, sheet, inline destination,
  custom panel, or always-on-top surface. Its preferred bounded content size is
  **420 × 480pt**. Triptych entry, Inspector summary, and the temporary Activity
  Notification Stack each anchor the same Triptych-owned queue to their complete
  trigger.
  Native transient behavior closes it after outside activation or Escape;
  opening a Note or Resynthesize also dismisses it. It has no custom or manual
  close control. Closing the popover never removes an Action activity; only the
  completed activity's explicit **Dismiss** action does. Reopening within the same Workspace may retain
  its session filter and selection. Activating a different Workspace window
  resets query, kind filter, selected task, and current-Note subset; the
  machine-local structural-dismissal ledger and persistent Action activities
  are unaffected. The Triptych entry and Activity Notification Stack open the
  complete queue; Inspector entry adds the current Note. Switching workspace
  neither filters nor retargets an already open Triptych queue.
- The Notifications popover presents **Action Activities** once per Run, then
  groups structural Attention as **Identity & Metadata** (Malformed Metadata,
  Unresolved Identity), **Structure & Connections** (Possible Orphan, Broken
  Connection, Ambiguous Connection), and **Revision & Research** (Changed Since
  Settled, Synthesis Material Changed). Each group shows its visible count.
  Each row follows one issue-first order: a quiet semantic issue capsule, `/`,
  one short observable reason, resolved Note title, exact relative path and
  optional line, then only real available actions aligned to the logical
  trailing edge. It does not repeat the issue name inside the reason or use a
  middot as structural punctuation.
  Ordinary rows provide Inspect and timed Dismiss. Synthesis Material Changed
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
- The stable Library header contains the adaptive Folder disclosure control,
  Filter, and Add. The disclosure control is unavailable when there is no
  expandable Folder. Matching icon-only controls use the header target metric
  owned by §19.3, secondary ink at rest, primary ink plus the shared shallow
  semantic interaction surface on hover, native keyboard focus, and the same
  purpose-owned continuous corner recipe. They add no persistent Accent tint,
  independent radius, hover animation, scale, or shadow.
- Ordinary workspace navigation stages the target session and Library source
  list from the latest accepted Workspace snapshot while the last committed
  workspace session remains intact, then commits the destination atomically
  after document safety succeeds. It never replaces trustworthy content with a
  full-page Loading state merely because an in-memory projection crosses an
  asynchronous boundary. A staged target failure retains the prior workspace,
  tabs, Document, Inspector, and content and reports the failure.
- Library empty, loading, and error states align to the peripheral page edge
  and begin one section step below the Library header. They never borrow the
  tighter OutlineRow surface inset. An initial load with no trustworthy
  projection uses one system indeterminate progress indicator and the explicit
  **Loading Library…** name; it does not use a shimmer or skeleton.
- A Note or Folder row exposes destructive **Move to Trash…** through its
  context menu and named accessibility action. The focused window also exposes
  the equivalent File-menu command with the standard Command-Delete shortcut.
  It always presents the bounded confirmation owned by section 6 before any
  native move. Confirmation cancellation or preflight failure restores the
  originating row and focus. After a committed move, focus moves to the next
  row, previous row, then Library; an open page for absent source closes while
  unrelated tabs and document focus remain intact. Finder, not Library, owns
  browsing or restoring system-Trash content.
- Shared Search follows Section 13: one compact centered surface, always-visible
  provider-specific scope, no empty sheet, and bounded Note or Record results
  that identify match context, source freshness, and destination. Typing a
  valid field prefix may open one bounded capability-driven completion list;
  scope-authorized property keys participate, optional Note identities may
  participate, and a controlled property value completes after `=`. Accepting an item edits only
  the visible query text. Completion and results
  never expose two simultaneous keyboard selections or turn Search into an
  advanced workspace. **Explain Query** presents the typed explanation carried
  by the Application Search response and shared with CLI under §13. The Search
  surface may present a compact summary with an explicit route to the complete
  explanation or expose the complete explanation on demand; it need not reserve
  a permanent explanation row for every query. Whatever presentation is used
  remains discoverable and never reparses query text or constructs a second
  interpretation. Provider mismatch,
  ambiguous identity, not-applicable clauses, invalid syntax, unavailable
  Graph, stale source, and no matches retain distinct inline states.
