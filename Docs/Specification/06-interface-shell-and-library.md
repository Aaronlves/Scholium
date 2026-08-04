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
   identity; one quiet equal-column **Analyses / Topics / Works** ScopeIndex
   with no Attention statistics; one conditional current-Scope Attention alert;
   one title-style LocationPicker for **Library**, **Set
   Aside**, and **Trash**; one active location-owned source region; and
   Library-local Filter and Add. Settings is not a Library destination.
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
Inspector. All three planes are opaque, and the native tracking separator is
the sole inter-pane boundary; Scholium draws no parallel main divider or
shadow.

New windows show Library and hide Apparatus. Initial or restored peripheral
visibility is installed before the native split's first presentation; the
window never draws an expanded Apparatus and then retracts it during launch.
Restore applies both visibility values once; then native collapsed state is authoritative and the model only
mirrors Library and Apparatus visibility for labels, commands, and the next
session. Menu, toolbar, and content actions send explicit per-window intents to
the native controller; model observation never continuously reasserts split
state. Notes/tabs never reconstruct the shell or change peripheral
visibility/mode. Library Scope and Location are per-window presentation state,
not Note, vault, or Markdown facts. Switching Scope preserves the selected
Location and reloads that Location under the new Scope without replacing the
open Document. A new window's first Inspector reveal selects Overview. Each
window restores its own last Inspector mode; changing notes, Document tabs, or
document presentation mode never changes it.

The native titlebar owns traffic-light, drag, and height geometry. Its one
toolbar belongs to Document and exists inert from the first configured frame;
loading may replace items but not move traffic lights or change band height.
Opaque regions extend beneath it, and controls use the live safe area rather
than a measured toolbar height.

Sidebar and Inspector each keep one visibility control at a stable position in
the one native Document toolbar. Native collapsed state changes that item's
accessible Show/Hide label, value, and explicit per-window action; collapse and
expansion never transfer the control, change toolbar item topology, or add a
pane-local duplicate. Tracking separators remain structural bounds. Add no
split-item accessory row, custom title strip, Inspector replacement, ellipsis,
fixed height, automatic glass-like item, or Liquid Glass.

Attention never enters the Document toolbar. While Sidebar is visible, its
conditional current-Scope alert is the only workspace-chrome signal;
collapsing Sidebar removes that signal without transferring a count, symbol,
reserved gap, or popover anchor. Inspector retains its distinct current-Note
summary. **Window → Attention** is enabled only when the focused Workspace has
a visible Sidebar alert or Inspector summary capable of anchoring the transient
popover; otherwise showing Sidebar restores the contextual route.

The Inspector toolbar control and View command send one explicit intent through
the exact window coordinator to the native split.
The Inspector routes share selected-document availability and preserve native
transition and geometry. Inspector Show remains visible but disabled without a
Target; a visible Inspector can always be hidden. Research Records remains a
separate Triptych-bound auxiliary window; opening it from the document toolbar
explicitly reapplies **This Note** Scope without changing Inspector state.

With two or more documents, a Document-owned strip appears only in the middle
item. Each tab references one retained editor session. The native tab
controller owns containment; Scholium supplies equal-width selection
and save-before-transition. One stable document has at most one tab in a
window; repeated open or **Open in New Tab** selects that tab in place. Close
flushes and selects a retained neighbor; last close returns no-note. Tabs
create no window group, parallel state, or toolbar owner. Prototype styling
has no authority; selector styling is provisional.

Window close, route handoff, and application termination are bounded. A
content flush, save, or conflict failure keeps the affected window and exact
buffer available with a retry path. Machine-local window-session or layout
persistence is best-effort after content is safe; its failure is diagnosed but
does not veto close or misreport a source-save failure. Late lifecycle work may
not act on a newer route, window, document, or close attempt.

The Library BrandHeader sits below window controls. A static Scholium wordmark
and a separate Triptych identity menu share the 28pt peripheral page edge;
Triptych management never turns the wordmark into a second toolbar. Traffic-
light alignment is visual reference only, never derived geometry. No-note is
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
  enabled only when the focused Workspace has a visible Sidebar or Inspector
  Attention anchor, and opens that anchor's transient popover.
- **Research:** role-valid Actions and **Triptych · Records**, never Attention
  or Checkpoints.
- **Settings:** Triptychs, Property profiles, Research Guidance, Attention,
  Zotero, and Appearance.

### 18.3 Library and Search

- The ScopeIndex is Library's only horizontal index. Analyses, Topics, and
  Works occupy three equal columns, with each label centered and the selected
  item marked by a provisional **18pt × 1pt** Accent underline. It has no
  capsule, shared backing plate, enclosing border, or full-width rule. The
  group exposes selection, follows reading direction for Left/Right Arrow, and
  lets Tab continue into Library content without pointer activation creating a
  keyboard-only focus ring. Scope labels expose no Attention count visually or
  accessibly; Attention state belongs to the conditional current-Scope alert or
  the current-Note Inspector summary.
- One native **Filter** menu groups Integrity, Metadata, Properties, Order, and
  Actions with at most one submenu level. Its icon-only entry hides the
  redundant outer menu indicator; native submenu chevrons remain. Current
  Library rows and filters have no Review, Unreviewed, Qualified, or
  Unqualified state.
- One icon-only disclosure button sits beside Filter. When any Folder in the
  current tree is visibly expanded, it presents **Collapse All Folders** with
  the collapse symbol and collapses the complete tree; otherwise it presents
  **Expand All Folders** with the expand symbol and expands the complete tree.
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
- The Library Location shows no total. Attention treats zero as the steady
  state, **1–3** unresolved items as its primary design condition, and larger
  queues as exceptional accumulation rather than a separate mode or hard cap.
  When the selected Scope's last trustworthy count is zero, Sidebar contains
  no Attention row, reserved gap, visible zero, or accessibility target. When
  the count is nonzero, one full-width **ATTENTION** alert appears after
  ScopeIndex and before LocationHeader on the **28pt** peripheral page edge.
  Its warning symbol, exact count, and persistent raised Navigation surface
  make the condition prominent without relying on color alone. It has no
  leading selection rule or other decorative Accent boundary.
  It neither auto-opens, steals focus, pulses, nor repeats attention-seeking
  motion. The complete alert opens a native transient Attention popover from
  itself and never becomes selected Library content. Inspector may open the
  same Workspace-owned queue from its current-Note summary. Attention is not a Location:
  opening it leaves the selected Location, source content, Document, and
  Sidebar selection unchanged.
- Refresh preserves the last trustworthy per-Scope counts and the corresponding
  current-Scope alert while Sidebar is visible. A first load with no trustworthy result never
  claims zero. If it fails, the alert position shows a distinct non-counting
  **Attention Unavailable** state with Retry rather than hiding a potentially
  urgent condition. Resolving or dismissing the final item removes the alert;
  if that disappearing control owns keyboard focus, focus moves to
  LocationPicker. No reassurance row replaces it.
- Attention is one native transient popover owned by the exact
  Workspace window, never an application-wide Scene, sheet, inline destination,
  custom panel, or always-on-top surface. Its preferred bounded content size is
  **420 × 480pt**. Sidebar alert and Inspector summary each anchor the same
  Workspace-owned queue to their complete trigger.
  Native transient behavior dismisses it after outside activation or Escape;
  opening a Note or Resynthesize also dismisses it. It has no custom or manual
  close control. Dismissing and reopening within the same Workspace may retain
  its session filter and selection. Activating a different Workspace window
  resets query, kind filter, selected task, and current-Note subset; the
  machine-local dismissal ledger is unaffected. The conditional Sidebar alert
  uses the selected Scope; Inspector entry adds the current Note. Changing Sidebar
  Scope clears that Note subset and switches the queue to the newly selected
  Scope.
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
  position and height while the source region changes.
- The LocationPicker is one native menu of three mutually exclusive items.
  Its title presentation is quiet and borderless: it has no enclosing fill,
  bezel, capsule, or custom disclosure glyph, and relies on the menu's one
  native indicator.
  Its selected item uses a checkmark; Set Aside and Trash may show a last-
  complete count as neutral location metadata. Missing, refreshing, or failed
  counts never disable selection or change the selected Location. Opening the
  menu enters its native keyboard order; Arrow keys, Home, End, and Return
  navigate and choose, while Escape closes the menu and restores focus to the
  LocationPicker. Leaving Set Aside or Trash requires choosing Library or
  another Location; there is no parallel Back control, footer toggle, or
  lifecycle tab row.
- Ordinary ScopeIndex and LocationPicker navigation stages the target Source
  List from the latest accepted Workspace snapshot while the last committed
  Scope/Location pair remains intact, then commits the target pair and list
  atomically. It never replaces a trustworthy Source List with a full-page
  Loading state merely because an in-memory projection crosses an asynchronous
  boundary. Loading remains available only when no trustworthy committed
  projection exists or an explicit recovery/refresh owns that state. A staged
  target failure retains the prior pair and content and reports the failure;
  it never presents that target's error under the prior Location title.
- **Set Aside** and **Trash** are same-plane Library Locations, never overlays,
  cards, sheets, or separate Sidebar modes. Selecting one replaces only the
  source-region content; BrandHeader, ScopeIndex, conditional Attention state,
  LocationHeader retain their ownership.
  All three Locations project the same native Folder-and-Note outline and row
  interaction grammar; lifecycle filtering and category-valid actions are the
  only intentional differences.
  Switching Scope retains the Location and loads its content for the new Scope.
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
- Shared Search follows Section 13: compact centered surface, always-visible
  scopes, no empty sheet, bounded results that identify match context and
  destination, and deterministic lexical Beta.
