# Implementation Status: Interface Boundary

Part of the canonical document set rooted at [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md).
This chapter owns current interface implementation, bounded evidence, and open acceptance; sibling chapters do not restate it.

## Current interface boundary

### Connect relation system

**Current state**

D-118 is reachable end to end: Markdown dialect 4 and editor protocol 7 expose neutral, support,
opposition, and undirected incompatibility; Graph contract 5 canonicalizes reciprocal
incompatibility without rewriting source; Related Search and Read use the same meaning. The native
Connect projection groups rows by relationship, places one direct SF Symbol in a shared leading track
per cluster, keeps counts only on major role headings, and bounds the current symbol below the pinned
original group header in the existing single scroll owner. The current repository gate covers the
locked WebEditor, graph/rendering, dialect, bridge, and frontend architecture contracts. One
isolated Light QA opened a 70-relation disposable Analysis and visually exercised top position plus
support, incompatibility, and neutral sticky handoff.

**Still open**

Researcher visual approval remains open. Also pending: 278pt, long localization, RTL layout,
Dark, Increase Contrast, inactive window, 200% readability, physical Full Keyboard
Access, and genuine spoken VoiceOver. The isolated screenshot and synthetic AX tree are bounded
evidence, not human or assistive-technology acceptance.

### Ownership and shell

**Current state**

One native Library–Document–Inspector split has scoped controllers and stable sessions. AppKit owns
geometry; `WorkspaceWindowCoordinator` owns the exact lifecycle. `WindowShellState` owns
Library/Inspector presentation, disclosure, restore completion, text scale, appearance, toast, and
shell status. `WindowWorkspaceController` owns assignment, registered Triptychs, access recovery,
and the installed capability session. `WindowEditorFlushCoordinator` owns one window's
current-editor and aggregate flush registrations, Triptych/window rebinding, and
flush-before-capture validation through a narrow app-registry port. Close preparation no longer
unregisters those capabilities: only actual native close or scene teardown does, so a peer window
that cancels application termination leaves successful windows retryable. `WindowModel` remains the
composition/focused-command root and routes transition, persistence, Agent, Search, projection, and
typed cross-feature effects, but now publishes only its own remaining mutable facts and never relays
child `objectWillChange`. The scene retains root owners before a child observation view derives
bounded observers, preventing SwiftUI reconstruction from pairing retained state with children of a
discarded model. Content, Research Record, and toolbar hosts likewise observe bounded owners
directly; `WindowCommandObservation` carries only a window-local invalidation revision for
command-facing facts and owns no product state. Role-owned opaque backgrounds extend beneath the
native titlebar, with content inside its safe area. The one inert-from-first-frame toolbar is
divided by native tracking separators and owns one stable Sidebar control and one stable Inspector
control; native-mirrored visibility changes their Show/Hide labels and actions without moving them
into pane corners or changing toolbar topology. Native Inspector transitions and the Library's 300
pt content minimum add no second geometry owner. Focused two-attempt termination and native-close
tests cover the corrected ownership lifetime.

**Still open**

Fullscreen, automatic-collapse recovery below the expanded Library threshold, the complete
adaptation matrix, and human/assistive-technology acceptance remain open.

### Scenes, tabs, and Document

**Current state**

Codable routes use `windowID` as session identity; failed scene replacement retains the source. A
window admits one tab per stable document target and selects an existing member on repeated open.
Stable and identity-unavailable sessions are both vault-qualified, so equal paths in two Triptych
vaults cannot share a buffer, Read-cache identity, mode, or scroll state. All tab closes flush
first. Every accepted complete Workspace generation reconciles all open tabs by stable identity:
clean externally deleted documents close and select a valid neighbor or the no-document state, while
dirty, conflicted, in-flight, retryable, or recovery-buffer sessions preserve their exact bytes. The
generation gate runs before path or document projection, preventing an older event from mutating
newer window state. Leased/pinned sessions retain safety state; clean detached zero-lease sessions
release editor/WebKit state immediately, with only bounded lightweight presentation retained. Exact
zero-byte Markdown now presents one completed native **Empty Note** Review group and starts no empty
WebKit render; whitespace, unavailable source, loading, and rendering failure remain distinct. With
no selected document, Document shows one centered read-only symbol/title/instruction group without
adding an action, focus target, or state owner; Library and the inert toolbar remain stable. Focused
controller, tab, projection, live two-window, cache, frontend, localization, provider-coordination,
and process-interruption tests plus focused disposable XCU and pointer/AX journeys cover these
boundaries. Debug launch uses a real repository-local bundle through LaunchServices.

**Still open**

Clean-account/restoration/Dock/New Window journeys, final tab visuals/replacement automation, a real
File Provider domain's dataless materialization/eviction behavior, packaged-App termination UI
acceptance, and Editor adaptation acceptance. The inspected Dark QA screenshots and synthetic
accessibility tree do not close Light, Increase Contrast, 200% interface text, localized layout,
physical Full Keyboard Access, genuine spoken VoiceOver, or researcher visual acceptance.

### Library, Search, and research

**Current state**

Filter, scoped Debate Importance ordering, root-level Notes, Set Aside, and Trash are reachable.
Search exposes This Note, This Vault, and Triptych only; current v4 parsing rejects `status:`
explicitly. This Note reads the current in-memory editor revision without saving; all scopes cancel
superseded requests and reject stale request, generation, fingerprint, session, or revision results.
Related remains a separately loaded direct-connection region and has no vector/AI/chat path. The
per-window Inspector restores Overview, Connect, or Actions. Overview omits empty About fields and
Zotero metadata/key presentation while exposing the D-131 exact-item action only for a keyed current
Analysis; Connect preserves counted empty groups without filler; Actions presents Research and
Review default groups, grouped Researcher Skills, and Judgment without chronology, a duplicate
record launcher, or a separate active-Discussion row. Discuss itself opens an existing exchange.
Research Records remains separate and identity-bound to the Triptych that opened its keyed window;
later Workspace or document focus changes do not retarget it. D-114 gives all three Inspector modes one
borderless Apparatus component system, a section-level adaptive FactGrid, a keyboard-reachable
equal-column ModeIndex, and one nonpersisted 320 pt first-reveal offer that leaves later split
geometry to AppKit. D-115 seeds restored Inspector collapse before the split item is installed,
preventing the default expanded frame from appearing at launch. D-116 makes the current-Note
Attention summary one full-row route, moves Edit Properties into the About heading while leaving
values selectable, gives diagnostic names the label face, and converts Connect to relaxed
single-button rows without the trailing diagonal glyph. Each Connect group now uses its original
collapse button as a sticky section header inside the existing scroll owner; no overlay, second
title, divider, or scroll region is added. The distinct source anchor remains a named
context/accessibility action. Action rows call the exact current-window route; arbitrary enabled
Skills remain generic ordered Researcher Skill rows, and pointer activation no longer forces or
later restores a keyboard-only focus ring. Research Guidance mutation completion now publishes one
typed configuration invalidation without replacing the workspace snapshot or clearing derived
freshness; every active window re-resolves its current Action availability and shows Checking rather
than a stale repair while that read is pending. The Inspector Preview Catalog consumes the
production ModeIndex and mirrors the current Attention, About, Connect-cluster,
Research/Review/Researcher Skills, and Judgment grammar. Focused Inspector-geometry, Working Method
invalidation, and Attention-destination checks pass; an isolated Debug QA confirms hidden launch,
current-Note Attention routing, the About heading route, relaxed Connect rows, sticky long-list
headings that remain pointer-collapsible, an enabled Action presentation, and pointer activation
without the prior blue focus box. The 2026-07-31 complete repository gate covers the current
Inspector implementation, Action-availability invalidation path, and converged Preview grammar.

**Still open**

Researcher side-by-side approval at 320/278 pt; keyed/nonkeyed role-switch visual acceptance for
D-131; sticky-header behavior under long localized titles; launch and pointer-focus visual
acceptance; mixed-script/RTL, dark and increased-contrast, Reduce Transparency/Motion,
inactive-window, physical Full Keyboard Access, and genuine spoken VoiceOver acceptance; current
Search timing and broader ranking review.

### Library creation and context actions

**Current state**

Library Add is now one native menu offering **New Note** and **New Folder** at the current vault
root; File and Shift-Command-N retain the direct focused-window note path. A secondary click in
unoccupied Library source-list space offers the same two root actions, while Add remains the
non-secondary-click accessibility route. Direct New Note returns after the exact source and stable
identity commit, records that durable identity in the Application source-ahead bridge, installs one
explicitly `sourceAhead` window row, and queues the sole complete derived rebuild before releasing
the mutation lease; matching watcher work no longer starts a duplicate generation. The complete
event replaces the transient row and reopens Research Actions only after derived state is current.
After activation Library clears excluding filters, preserves ordinary sort and unrelated disclosure,
expands only the destination ancestors, and emits one scope-bound reveal to the selected row without
taking keyboard focus; clearing a scoped Debate Importance filter restores Recently Modified order.
The selected row exposes its state accessibly. Library now projects empty real directories. Ordinary
folder menus provide direct New Note/New Folder, Rename Folder, Move Folder, conditional
Expand/Collapse All, Copy Relative Path, Reveal in Finder, and confirmed Move Folder and Notes to
Trash, with equivalent accessibility actions. Folder creation atomically advances default names,
installs the durable directory immediately in the exact window, and queues folder inventory plus
disposable derived assembly behind the source lease instead of blocking the action. A typed
failed-refresh fixture proves that the directory remains committed while derived state becomes
explicitly stale; unchanged Markdown is not reread or reparsed. Folder moves containing notes
preflight every descendant Markdown revision, rename the directory once, preserve non-Markdown
bytes, rewrite exact resolved incoming links, batch-rebind stable note IDs, and reuse durable
rollback/recovery. An ordinary Note menu now exposes name-only **Rename…**. The populated native
outline owns the process-private, revision-bound drag source, Folder-row validation, AppKit
autoscroll, and full-row drop feedback; the stable LocationHeader owns the sole native vault-root
destination, and the SwiftUI shell registers no competing destination. Core derives the mounted
vault's case and Unicode-normalization filename comparison behavior once, Workspace snapshots carry
that immutable policy, and the native drop inventory uses its typed comparison keys for Note/Folder
occupancy, no-op, current-parent, self, and descendant rejection; missing policy rejects the target,
while Core still repeats current filesystem collision, containment, identity, and revision checks at
commit. A valid Note move conditionally flushes only that active Note, plans incoming-link edits
from a coherent exact Workspace snapshot by reparsing candidate sources only, falls back to complete
re-derivation when the snapshot cannot authorize it, and publishes the committed destination row
before the background refresh. Pending, stale, comparison-equivalent occupied, no-op, cross-vault,
protected, self, descendant, and ambiguous moves fail before dispatch or on exact acceptance
revalidation. Ordinary mutable Folders reuse that same Application-owned folder Move transaction for
Folder or vault-root destinations. A coherent Folder move now validates the accepted source-manifest
cohort, reparses only graph-identified incoming-link candidates, and retains the complete
filesystem/graph fallback for any pending or stale cohort. The repository still rechecks every
descendant immediately before the no-replace directory rename. After link and identity commit, the
exact window installs every committed Note source and moved Folder path as one `sourceAhead`
hierarchy, expands only the destination ancestors needed to reveal it, and lets the sole complete
derived generation converge behind the source lease. Application overlays those durable identities
by stable Note ID when planning another Folder move, so a just-created Note and two consecutive
Folder classifications use current paths while Core retains its complete inventory check.
File/accessibility **Move Note** and context/accessibility **Move Folder** remain the non-drag
routes. An adjacent icon-only disclosure button shows Collapse All whenever any current Folder is
expanded and otherwise shows Expand All; it mutates the current disclosure scope directly. Every
successful active-Note activation automatically uses the independent stale-target-checked reveal
path; filters remain when the destination already passes them and clear only when they exclude it.
The other open/lifecycle/Finder actions plus Copy Relative Path remain. Focused path-policy, tree,
incoming-link, projection, Application lifecycle, and frontend-structure checks pass. A focused
native XCU journey verifies Note-to-LocationHeader root movement, source-row removal, exact
filesystem placement, and immediate root-row publication. One isolated native-drag XCU journey
confirms that the target row appears about one second after release, the source row disappears,
exact filesystem placement commits, and the moved Note remains selected; this timing is Debug QA
evidence rather than a release performance gate. Isolated QA also confirms the adaptive disclosure
button's outward Expand and inward Collapse symbols, state switch, complete-tree action,
accessibility name, and empty-Folder edge. The 300-note Debug QA fixture reveals a nested Folder
about two to three seconds
after release while exact placement, descendant source, identity, and background convergence checks
pass. This is bounded Debug evidence rather than a packaged performance gate or researcher
acceptance. Focused Contracts/Core/Application/App tests cover the source-ahead state and creation
publication; localization validation and the direct Add-menu XCU journey pass. On the current
300-note disposable QA fixture, a second New Folder action returned from the Computer Use click in
about 0.42 s while its complete derived generation continued independently; this is interaction
evidence, not a release performance gate. On a 550-note disposable Debug fixture, the New Note
pointer path reached visible selection in about 0.98 s (source commit
about 0.47 s), Empty Note appeared at about 0.94 s, and logs showed one 2.03 s background generation
without a competing complete refresh. An empty-vault pointer journey also confirmed both
blank-space menu items and approximately 0.56 s selection.

**Still open**

Full Keyboard Access, spoken VoiceOver, broader localization/adaptation review, File-menu/shortcut
automation, drag-out and Folder-to-root automation, real case-sensitive or normalization-sensitive
mounted-volume UI acceptance, injected identity/refresh failures during the source-ahead interval,
and final researcher interaction/visual acceptance remain open.

### Sidebar and Attention clean cutover

**Current state**

D-119 through D-134 are reachable without a compatibility branch. Sidebar now composes fixed
BrandHeader, a quiet equal-column ScopeIndex with no Attention statistics, a zero-absent
current-Scope Attention alert, stable LocationHeader, and one active source region with no fixed
literature-recommendation footer or reserved gap. `AttentionScopeCounts` derives exact
internal values from the existing catalog and dismissal ledger without owning queue state; Scope
labels never render or announce them. A nonzero current Scope receives the persistent raised alert,
while first-load failure presents Attention Unavailable with Retry. D-128 removes the alert's
leading Accent rule without replacing it: warning symbol, exact count, raised surface, and
complete-row activation carry its hierarchy without resembling Source List selection. D-134 makes
Sidebar collapse remove the contextual alert without transferring any Attention symbol, count,
aggregate, reserved width, observer, or popover anchor into the Document toolbar. Triptych and
Location menus each rely on one native indicator; LocationPicker is a reusable borderless
native-menu component with no enclosing fill or custom chevron. Library alone shows Filter/adaptive
Folder disclosure/Add; Set Aside and Trash reuse the same 28pt Note rows. One AppKit-owned Put Back
control appears as a trailing overlay above a hit-test-transparent semantic Sidebar material veil on
pointer hover or while its Outline row owns native keyboard focus; titles retain full width without
reflow, while SwiftUI retains context/accessibility actions. Committed lifecycle moves clear a
presented moved Note into the no-document state while destination Notes remain explicitly browsable;
hover teardown resolves only current stable row IDs. The source hierarchy has one flat visible-row
order in a native `NSOutlineView`; Folder and Note rows remain ordinary scrolling rows, and no
Folder is reclassified as a floating group header. The fixed LocationHeader and its
Library/Filter/disclosure/Add controls remain outside the source scroll owner. One outline-owned
native tracking area derives restrained full-row hover feedback for unselected enabled Folder and
Note rows without letting reusable row views own hover state or changing selection. Titles are
single-line middle-truncated with full pointer help and accessibility names. `DiscoveryLibraryState`
owns one Scope/Location pair, filters apply only in Library, and request identity rejects late
results after either dimension changes. D-129 replaces the detached D-120 Scene with one 420 × 480pt
transient native popover per Workspace. Sidebar and Inspector share the exact per-Workspace queue,
filters, selection, Scope, optional Note subset, three groups, stale/error retention, and
deterministic post-removal focus. Outside activation and Escape dismiss natively; Inspect and
Resynthesize dismiss before continuing in the same Workspace. Switching to another Workspace resets
query, kind filter, selection, and Note subset without changing the dismissal ledger. `Window →
Attention` is enabled only when the focused Workspace has a visible Sidebar or Inspector Attention
anchor. The complete Sidebar has one Navigation surface, while Inspector's Apparatus tone remains
close to Document with the native split boundary and semantic roles intact. D-123 makes Inspector sticky occlusion
consume that exact Apparatus role and shares one semantic underline component between ScopeIndex and
ModeIndex without merging their metrics. Sidebar and Inspector share one 28pt peripheral page edge
without merging their internal rhythms. Their shared `ScholiumLibrarySourceState` aligns Library, Set Aside,
and Trash empty/loading/error content to that page edge while populated OutlineRows retain the
denser row-surface inset. D-125 stages ordinary Scope/Location replacements from the latest accepted
window snapshot, so navigation retains the committed tree until one coherent target commit and never
flashes full-page Loading; late results remain rejected and staged failure retains the prior
projection. Focused hierarchy and frontend contracts plus exact Put Back and long-title native XCU
journeys pass; isolated QA confirmed the ordinary nonsticky hierarchy, row hover, retained
accessibility actions, and smooth synthetic scrolling on the disposable 300-Note fixture. The native
coordinator now skips complete expansion reconciliation when both outline structure and the desired
disclosure set are unchanged. In one 5,000-Folder/100-expanded Debug diagnostic, 20 unchanged
coordinator applications measured 48.8–56.2 ms across three observations; this is a synthetic
main-thread diagnostic, not visible-scroll or release evidence. A production-like cached-title
10,000-Note diagnostic measured five repeated filter/sort projections at 84.7 ms. The matching
no-title-cache modified-time stress case measured 64.3–68.0 ms across three observations. Five
Folder projections remained 21.9 ms and twenty equal cache-input checks 193.9 ms; because AppKit
scrolling did not demonstrate those latter costs, no speculative second cache owner was added. A
focused current-build disclosure XCU journey now passes: clicking `Cluster-01` exposes its exact
child Note row, and clicking it again removes that row; one selected test completed with zero
failures. Selected Sidebar/Inspector UI journeys and the 2026-08-03 complete repository gate cover
the current native hierarchy, disclosure optimization, and D-134 no-toolbar cutover. Complete
adaptation and researcher visual acceptance remain open.

**Still open**

Researcher approved the transient anchored-popover route, no cross-Workspace filter retention, and
removal of Triptych Scope Attention statistics. Still open: direct popover visual acceptance,
rendered zero/one/three approval, Dark/Increase Contrast/inactive-window acceptance, genuine
VoiceOver, physical Full Keyboard Access, installed IME, Reduce Transparency, Reduce Motion, exact
200% readability, broader RTL/localization review, a real File Provider domain and packaged-App
interruption journey, and release readiness.

### Research Records auxiliary window

**Current state**

The former focus-following fixed presentation is replaced by one data-driven ordinary WindowGroup
per Triptych ID. It reads the exact Triptych snapshot and Records capability directly, defaults to
760 × 680pt, resizes to a 700 × 520pt minimum, and does not restore across launches. The document
toolbar explicitly opens This Note Scope; the Research menu explicitly opens Triptych Scope. Scope
and Records/Recommendations View remain independent and do not follow unrelated window focus.
The ordinary titlebar now carries only the window title. The leading Navigation plane owns a
restrained Records/Recommendations index and a borderless Scope menu in its list-context row, so
no full-width control strip crosses the reading plane. Both Lists expose the semantic Navigation
surface, controls inherit the resolved Accent, long revision identities use selectable wrapping
blocks, and reading-plane actions share one borderless ink treatment. The auxiliary window
consumes the same persisted System/Light/Dark choice as Workspace instead of falling back to
system Light. Recommendations still reuses the same list/detail split, search, empty/error states,
checkbox, sheet, typography, surfaces, and focus behavior. The Sidebar,
Attention, and Inspector have no count, entry, or reserved gap for this view.

**Still open**

The focused coordinator/model and frontend-architecture suites pass. Five bounded native-window
XCUITest journeys pass on the current Xcode 27 build after correcting one count-label AX merge and
keeping primary provenance navigation above long identities; they cover keyed-window reuse,
Recommendations disposition/note/parent routing, comparison/deletion, cross-Triptych isolation,
View-index keyboard traversal, deterministic RTL mirroring, and the 700 × 520pt minimum content
size. A populated Records and Recommendations pass also confirmed the shared semantic surfaces,
controls, typography, and hierarchy in representative Light and Dark appearances. Genuine
VoiceOver, exact 200% readability, Increase Contrast review, and researcher visual acceptance
remain to be recorded for this cutover.

### Beta static Sidebar hierarchy polish

**Current state**

D-126 keeps the accepted full-width selection/press surface while retaining the 12pt content axis;
Folder and unselected Note titles use one Regular semantic role and only the selected Note becomes
Semibold. Filter hides only its redundant outer indicator. The compact toolbar identity uses
secondary ink. Middle truncation, pointer help, and accessible full titles remain; custom
fade/marquee reveal and H1-toolbar identity handoff are explicitly deferred beyond Beta.
`ScholiumQuietRowButtonStyle` is now the shared summary/action feedback component instead of an
Inspector-only recipe. Folder expansion no longer animates the complete flat Source List mutation,
eliminating the path that let departing Note labels interpolate past their owner. Folder and Connect
now share one 0.12-second ease-out, non-spring `ScholiumMotion.disclosure` chevron rotation with an
immediate Reduce Motion path; sticky-boundary and Attention count/presentation changes use separate
purpose-named restrained recipes.

**Still open**

Focused source contracts, tree projection tests, and build evidence pass. Direct slow-motion runtime
inspection of deep Folder collapse, long-title motion, identity handoff, full adaptation review, and
human acceptance remain open rather than current Beta claims.

### Visual system

**Current state**

D-087 leaves shell geometry to AppKit and gives semantic rhythm to `ScholiumGrid`; Review/Edit/Source
use explicit Web units. D-093 replaces Document Styles with machine-local named Appearance
configurations for Body, headings, and each Callout. D-100 adds the one shared **Line width**
control: **72ch** by default, normalized to **48–96ch**, applied to Review/Edit/Source with 20/32/40
CSS px minimum divider separation and without changing Source typography. Exactly one configuration
is selected; save, rename, duplicate, delete, strict canonical manifest decoding, and additive
Advanced CSS paths are implemented without a generated CSS preview. Runtime presentation CSS updates
the retained Read WebView and CodeMirror editor, requests remeasurement, and preserves document
bytes, selection, undo, focus, and the semantic scroll anchor. Under D-123, Accent `#A94C22` and
icon-aligned Paper `#FEF8ED` remain the only color inputs; Light Document uses Paper directly and
one resolver supplies every remaining native/WebKit role across Light, Dark, and Increase Contrast.
The complete Sidebar uses Navigation while Inspector retains a distinct but Document-adjacent
Apparatus tone. Feature views consume semantic roles; the accepted QA board retains no local
palette. The preexisting native Elevation family is now closed over three purpose roles and exported
through the same WebKit design-token owner: selection bars use floating control, custom menus and
link previews use bounded panel, and Search uses search overlay. Increase Contrast removes custom
soft shadows while strengthening boundaries; native presentations keep system elevation without a
second Scholium shadow. Mapping, renderer parity, and contrast are covered by focused contracts.
Disposable journeys cover the default window, 1380/1180/1080/900/720 widths, Inspector visibility,
all three modes, 72→73 keyboard adjustment, save persistence, mixed English/Chinese, local
long-token overflow, and 100%/200% text. D-097 adopts one researcher-approved parchment-and-ink
pointing-hand application icon, and every assembly path references the same repository-owned
`.icns`. Bounded researcher visual evidence and the withdrawn RTL surrogate claim are recorded once
in Verification Baseline.

**Still open**

The accepted comparison is bounded visual evidence, not release acceptance. Corrected Arabic/Hebrew
direction, genuine spoken VoiceOver, physical Full Keyboard Access, installed IME, inactive-window
researcher acceptance, Reduce Transparency/Motion real-system-setting acceptance, and
production-runtime acceptance remain open. The icon passed file-level representation inspection, but
Finder, Dock, small-size, appearance, and packaged-Release visual acceptance remain open.

### Derived state and conflicts

**Current state**

Graph publication does not block activation/Search; the last good snapshot reports
current/stale/failed state. Contained normalized paths preserve equivalent macOS paths. Conflict
comparison binds exact editor/disk revisions, defaults to Compare, restores focus, and permits
Reload only for the displayed disk revision.

**Still open**

Adjacent recovery-state and multiwindow acceptance within the complete UI gate.

### Upgrade safety

**Current state**

The fail-closed distinct-build gate uses an isolated disposable byte-hostile Triptych and retains
manifests/results. One run preserved path, size, SHA-256, permissions, and mtime for all 195
authoritative files.

**Still open**

Rerun for every release; this is not private-vault or installed-app evidence.
