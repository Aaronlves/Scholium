# Specification: Interface Shell and Library

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 18.1–18.3.

## 18. Canonical interface contract

Sections 1–17 own scholarly and workflow meaning. This chapter owns native shell
and Library presentation without restating those workflows.

### 18.1 Interface principles

[Design](../../Design.md) owns the global native design and visual identity;
§2 owns document and researcher authority, and §20 owns accessible routes.
This chapter owns shell composition, navigation and command placement.
Bootstrap readiness is governed by §16.

### 18.2 Workspace shell and Document tabs

Each configured window contains one native split view:

1. **Sidebar**: one region with **Library** and **Chat** presentations.
   Library contains Search and Analyses–Topics–Works navigation. Chat belongs
   to the Triptych and retains its conversation while the Document changes.
2. **Document**: the selected Note or the restrained no-document state.
3. **Apparatus**: the trailing Research Inspector's About and Links pages.

Native split behavior governs resizing and collapse. Scholium requests the
initial Inspector reveal but never continuously reasserts divider positions.
The main/auxiliary color and material boundary follows §19.1; native safe areas
protect content. A popover opened here is still an auxiliary surface.

New windows show Library, hide Inspector, and begin in Analyses/About. The toolbar's
leading native icon selector, labelled Library / Chat in Help and accessibility, shows
the chosen sidebar presentation. Choosing the other item switches content at the same
width; choosing the visible item again collapses the sidebar, leaving neither item
selected. Selecting either item while collapsed reveals it. Both presentations retain
their independent scrolling and disclosure while switching. Native split visibility
remains authoritative, including menu and window-resize changes. Inspector controls
use native enabled, selected, pressed, and disabled states, with no hand-tinted
unavailable symbols or custom refusal animation. Chat is available with an open Triptych
even without a Note. Chat inherits the Sidebar background with list-to-detail
navigation. Conversation rows share cards with native secondary backgrounds by calendar
day, with internal separators and Today/Yesterday/date headings instead of repeated
dates. Empty unused sessions are omitted. Each conversation's entire row, including
padding, opens its detail. The archive menu appears only at the list's top right: it
opens Archived Chats or enters selection mode. Only in this mode, rows show leading
selection circles; clicking a row toggles selection instead of navigating. A temporary
bottom action bar offers Cancel and archive/restore with the selected count. Empty
selection or active execution disables the batch action; canceling changes no
conversations. Detail options open only this conversation's Agent Changes. Library and
Chat share a native panel-header action group with consistent symbol sizing,
neutral ink and complete button hit areas. Native controls own interaction feedback.
Sidebar container edges align across Search, the workspace navigator, conversation
cards and the composer; headings, dates and row text use one content inset.
Inspector/editorial geometry does not determine these sidebar relationships. Only the bottom
composer uses rounded Liquid Glass. A single disconnected-state Connect Codex action
connects automatically; sign-in appears only when needed. Connection editing belongs in
Settings, with manual paths behind its advanced disclosure. Composer secondary controls
are borderless; permission uses an icon with a checked menu and accessible current
value. The circular Send button uses shared Accent; availability, keyboard sending and
native state feedback remain authoritative. The whole message input rectangle, including
whitespace, is editable; text clicks position the native caret. Return sends when
available; Shift-Return or Option-Return inserts a newline. Marked-text Return belongs
to the input method. Unavailable sending preserves the draft and selection, with a
visible connection explanation when disconnected. Native selection and Undo remain
within the current conversation. Back returns to conversations while work
continues. User messages align trailing in content-sized shared-Accent bubbles with
legible full-opacity text; the speaker label remains above and outside the bubble; Agent
replies support natural long-form prose. Completed operations collapse into compact,
typed summaries. Current activity, approval requests, failure and uncertainty remain
visible. A compact file/change count opens a popover, with exact comparisons available
only by explicit action. File rows distinguish recorded edits, reads, verified no-op
updates and runtime reports. They describe observed operations, not current filesystem
or acceptance state. Chat adds no permanent change-review pane or technical
history-management task. Inspector modes remain document-dependent. Toolbar
validation and View menus derive availability from the same current window state. Native
spacers express logical grouping; the system owns glass shapes, proximity effects, and
transitions. This native state contract applies to every toolbar component, including
history, document mode, Settlement, and Inspector modes. A disabled action cannot
execute through another toolbar or overflow route. Document-specific popovers close when
their document or required source revision changes; detaching a window ends its toolbar
interactions and prevents stale state from updating it. Back/Forward begin the Document
toolbar region, after the sidebar tracking boundary and before its Muted Text document
name. They remain available with the sidebar collapsed and traverse document visits, not
heading jumps. Visibility and workspace session state are installed before first
presentation, then native state is authoritative. Each workspace retains Library filters
and disclosure, selected tab, live Document mode, and Inspector mode. A transition
commits only after source safety succeeds; failure preserves the exact origin workspace
and buffer.

The native toolbar remains a bounded, stable set for frequent or high-value
commands: the native **Library / Chat** sidebar selector, Triptych Notifications, Back/Forward,
current-Document identity and mode,
Settlement, confirmed Agent Changes when present, Inspector
projection, and Inspector visibility. Every command also exists in its owning
menu, and native overflow preserves access at narrow widths. The current scope
does not require toolbar customization.

Search is directly editable at the top of the Sidebar. Triptych Notifications
has one stable toolbar bell, available with either sidebar presentation or with
the sidebar collapsed. Triptych opening and
creation remain in the native File menu; open-window switching remains in the
Window menu. Back/Forward traverse successful document visits only. The toolbar
remains structurally stable during loading and uses live safe areas. Pane
visibility is expressed by the actual pane, not duplicate custom selection
styling.

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

The Sidebar has no separate brand header or persistent Triptych title.
When open Workspace windows belong to more than one distinct Triptych, the
native window subtitle names the Triptych; it remains absent when that
disambiguation is unnecessary. The no-document state contains only a decorative
document symbol, **No Document Selected**, and **Select a note in the Library
to read or edit.** as one read-only accessibility group.

Menus follow task ownership:

- **File**: Triptych/window, New Note, Import, Duplicate, Rename, Move, Reveal,
  and system-Trash actions.
- **Edit**: editing, Find, and formatting.
- **View**: Back/Forward, Library, Chat, Sidebar visibility, Search,
  Advanced Search, Document mode/text size, and Inspector.
- **Research**: Settle, and Agent Changes.
- **Window**: standard windows plus Notifications.
- **Settings**: one native preferences window with icon-and-label toolbar categories,
  Settings search, and explicit Application, This Triptych, or This Mac scope.
  Switching categories adjusts the window from its current top-left corner to
  the pane’s preferred size within screen bounds, using native animation and
  an immediate Reduce Motion result.

Settings search indexes static page/control metadata, not research or Skill
content. Triptychs, Document Appearance, and Hotkeys are Application settings;
Metadata Profiles and Attention are Triptych settings; Agent Integration and
Zotero are Research Guidance. Scope is explicit where a page mixes This
Triptych and This Mac.

Settings uses one content axis for controls and a trailing-aligned label column,
with supporting copy beside its owner. Native collections hold field/shortcut
rows and adjacent actions. Appearance controls and configuration-file editing
belong to §18.4; Settings adds no nested advanced appearance editor.

Hotkeys is machine-local and limited to frequent Scholium-specific menu
commands. It requires Command, rejects conflicts and reserved shortcuts, and
supports clear and restore. Standard macOS commands remain outside remapping.

### 18.3 Library and Search

The Triptych workspace navigator is one native single-choice segmented control
for Analyses, Topics, and Works in stable order. The system owns its selection,
material and geometry; Scholium adds no selection skin or outer frame.
Ordinary widths show complete localized text; when those labels cannot fit,
the entire control uses stable role symbols with complete Help and accessible
names. Resizing preserves selection and focus. Counts do not occupy the control.
Unavailable workspaces remain disabled. AppKit owns control focus, selection,
keyboard traversal, and active/inactive presentation.

The Search field and workspace navigator form a compact fixed header. Library
has one muted operation row; its native file tree occupies the remaining height
and scrolls independently, retaining normal source-list row sizing.

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

- one native Organize menu for global Folder expansion/collapse, content and
  Integrity filters, Metadata, and Order;
- one Add menu for immediate New Note and New Folder;
- a single scrollable hierarchy of real folders and Notes, including root Notes
  and empty folders; and
- explicit empty, loading, stale, and recoverable error states.

Library is a muted section label rather than a competing page title. Organize
and Add remain separate native menus and focus targets with familiar symbols;
macOS owns their resting, hover, press, focus, disabled, menu, and accessibility
presentation. Folder-local Expand/Collapse remains in each Folder's contextual
and accessibility actions.

Content presence, including link annotations, is not an Integrity problem.
A filtered empty result names the absence of matches and retains Clear; it
does not claim the Library contains no Notes or invite creation as the remedy.

The application-owned root `Attachments` directory and everything beneath it
remain on disk but are excluded from the Library hierarchy. Document
attachments are reached only through their owning Note's attachment routes;
this projection rule does not hide a researcher-authored file or nested folder
that merely uses the same word elsewhere in a path.

Folder and Note rows use one native outline hierarchy. The native owner controls
selection, focus, indentation, active/inactive presentation, disclosure, and
drag feedback. Clicking a row selects it; the disclosure control and Left/Right
commands expand or collapse the selected Folder. Titles expose full
accessibility names and pointer help when visually truncated. Folder
disclosure, selection, drop target, disabled, and focus states remain distinct.
Disclosure communicates hierarchy state; Folder and Note symbols communicate
item type, and titles retain a consistent aligned text track. Indentation
adapts with the native Source List rather than becoming a product metric.

The Library is a researcher-authored project binder, not a flat taxonomy of app
destinations. It may therefore represent the complete on-disk Folder hierarchy
in this one outline. Search, Expand/Collapse, Reveal, keyboard traversal, and
native split collapse keep deep structures usable; Scholium does not add an
intermediate content-list pane merely to flatten source organization. Standard
controls and rows retain their macOS cursor behavior; link cursors are reserved
to document links and genuinely link-equivalent targets where native controls
do not already own cursor behavior.

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

Triptych Notifications has one stable native bell in the toolbar. It aligns
with the Sidebar's upper trailing edge when expanded; native toolbar layout
reflows it beside the sidebar selector when collapsed. It opens the complete
Agent Change/Settlement/Attention queue without changing the selected workspace
or Document. Zero is quiet; nonzero uses the native badged bell
with a small dot, without a visible number, unread model, animation, or
auto-open. Bell shape, dot shape, accessible state, and the popover's exact
contents preserve meaning without relying on color.

Background notifications use macOS UserNotifications for a newly confirmed
external Agent Note mutation. The first eligible background event requests
system authorization directly; there is no in-app permission pre-prompt or
separate enable switch. Denial is respected without repeated requests.
Foreground events update the bell and local Note state without banners or
focus changes. Consecutive writes to one Note coalesce to the latest exact
change; individual machine-local receipts remain inspectable.

System notification text is generic and excludes Note titles, paths, and source.
Only opaque Triptych, change, Note, operation, and fingerprint identity supports
click routing. Opening revalidates that exact receipt; missing or stale targets
never silently select another change or authorize a source operation. Delivery
failure, denied permission, and Focus never suppress necessary in-app state.

Changed Since Settle and structural Attention stay in the bell and their local
context. Save, Conflict, and Recovery failures remain persistent beside their
owners with valid repair actions. Other failed or partially committed operations
remain in the originating window's Document region; Settings validation and
copy acknowledgement stay beside their controls. Ordinary successful save,
copy, creation, and refresh are silent. There is no global in-app notification
overlay, priority stack, expiry timer, or duplicate delivery of the same event.

The complete Notifications queue is a window-owned native popover. The toolbar
opens Triptych scope; Inspector may open a current-Note subset. Popover closure
does not dismiss an Agent Change or alter Settlement. The queue
presents Agent Changes, then Settlement reminders, then grouped structural
issues with exact reason, Note/path location, and only valid actions.
Rows separate Note identity from the event or issue description; Agent Changes
also show time and the current/earlier/unavailable revision state.
Search/filter changes only this presentation. Notification-type filters live in
the native search-field magnifying-glass menu rather than a separate filter
button.
Stale or failed refresh retains last trustworthy content and Retry; empty and
unavailable remain distinct.

Scholium MCP never activates the App or moves focus on its own. An explicit
system-notification click may activate the exact Triptych and comparison;
ordinary in-app routes retain the same exact-identity validation.

Workspace switching stages the destination from trustworthy source and commits
atomically after source safety. It never replaces the origin with a full-page
loading state during background work. Library loading uses an explicit system
progress indicator rather than skeleton decoration.

System-Trash actions always use §6 confirmation. After a committed move, focus
advances to the next row, previous row, then Library; only absent documents
close. Finder owns restoration.

Shared Search follows §13: an inline quick-search surface and one explicitly
opened advanced window per originating Workspace, with visible scope and bounded
provider-specific results, typed completion, Explain Query, exact freshness,
and distinct invalid, ambiguous, unavailable, partial, stale, and empty states.
Completion edits visible query text only and shares
one keyboard selection with results.

Quick Search keeps its native editable field in place and shows concise results
below it. The field's native magnifying-glass menu holds scope,
Reset Filters, and Advanced Search. Active scope remains visible
in one muted result-summary line. Reset affects these menu filters, not query
text. Clearing quick-search text reveals the retained Library immediately.
Its result list inherits the Sidebar's existing background without painting a
second content surface; the system continues to own row selection feedback.

Advanced Search opens explicitly from that menu or View, carrying query and scope into a
resizable native window. Its own search menu has no Advanced Search entry. It uses one
query field, one quiet summary/action line, and an independently scrolling native result
list. The system owns row selection, focus feedback, and keyboard traversal. Note rows
use a small document symbol, title, available bounded snippet, and one secondary
location/reason line in interface typography. Repeated workspace labels, ranking
decoration, and permanent “Retrieval lead” labels do not occupy each row. Before a
query, the window shows a neutral Search prompt; an initial or cleared projection does
not claim an index failure. Empty and genuinely unavailable states use native
content-state views, preserving the actual reason and any valid retry. Saved Searches
remains directly available. Explain Query opens a compact transient explanation of the
actual conditions; tokenizer, normalization, ranking recipes, and repeated result titles
do not occupy the search workspace. Opening a result returns to the originating Document
while keeping the advanced window and query available for continued search. Ordinary
input never opens an advanced window automatically.

Both presentations use one Search session and one result-validation contract.
Only the active presentation issues queries. Closing Search cancels work and
restores the retained Library hierarchy, disclosure, and scrolling. Closing the
originating Workspace closes its search window. Native composition, focus,
clear, and keyboard behavior remain intact.
