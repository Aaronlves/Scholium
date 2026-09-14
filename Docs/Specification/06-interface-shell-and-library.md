# Specification: Interface Shell and Library

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 18.1–18.3.

## 18. Canonical interface contract

Sections 1–17 own scholarly and workflow meaning. This chapter owns native shell
and Library presentation without restating those workflows.
[Settings §18.2.1](13-settings.md) owns the separate preferences window.

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
3. **Apparatus**: the Inspector's Links and Related Material pages.

Native split behavior governs resizing and collapse. Scholium requests the
initial Inspector reveal but never continuously reasserts divider positions.
The main/auxiliary color and material boundary follows §19.1; native safe areas
protect content through window zoom and resize. Only the selected Sidebar page
participates in pointer, tooltip, keyboard and accessibility interaction; retained
pages cannot intercept another page. A popover remains an auxiliary surface.

New windows show Library, hide Inspector, and begin in Analyses/Links. The toolbar's
leading native icon selector, labelled Library / Chat in Help and accessibility, shows
the chosen sidebar presentation. Choosing the other item switches content at the same
width; choosing the visible item again collapses the sidebar, leaving neither item
selected. Selecting either item while collapsed reveals it. Both presentations retain
their independent scrolling and disclosure while switching. Native split visibility
remains authoritative, including menu and window-resize changes. Inspector controls
use native enabled, selected, pressed, and disabled states, with no hand-tinted
unavailable symbols or custom refusal animation. Chat is available with an open Triptych
even without a Note. [Chat presentation §18.2.2](14-chat-interface.md) owns the conversation list,
composer, transcript and capability controls. §8.7 owns their behavior.
Inspector modes remain document-dependent. Toolbar
validation and View menus derive availability from the same current window state. Native
spacers express logical grouping; the system owns glass shapes, proximity effects, and
transitions. This native state contract applies to every toolbar component, including
history, document mode, Settlement, and Inspector modes. A disabled action cannot
execute through another route. Document-specific popovers close when
their document or required source revision changes; detaching a window ends its toolbar
interactions and prevents stale state from updating it. Back/Forward begin the Document
toolbar region, after the sidebar tracking boundary and before its secondary-text document
name. They remain available with the sidebar collapsed and traverse document visits, not
heading jumps. Visibility and workspace session state are installed before first
presentation, then native state is authoritative. Each workspace retains Library filters
and disclosure. Document tabs and selection belong to the window; browsing another
Library role preserves the active document, its mode, and Inspector context. A document transition
commits only after source safety succeeds; failure preserves the exact origin workspace
and buffer.

The native toolbar remains a bounded, stable set for frequent or high-value
commands: the native **Library / Chat** sidebar selector, Triptych Notifications, Back/Forward,
current-Document identity and mode,
Settlement, Note Actions, confirmed Agent Changes when present, Inspector
projection, and Inspector visibility. Commands retain their menus. One catalog
defines menu shortcuts and conflicts. Window-scoped menus govern execution,
including embedded editors. Native overflow preserves access. Toolbar customization is not required.

One native **Note Actions** menu sits immediately after Review/Edit in both
window types; the separate window reuses its existing More button. It groups
Note-link copying and Add to Chat; Rename, Move, Duplicate and Merge; Find and
current-Note Agent Changes; Finder and window actions; then system Trash.
Settle and Document Mode retain their direct controls. Menu execution remains
bound to its captured Note even when Library selection or the active tab changes.
Separate-window Add to Chat opens the same Triptych's main Chat without moving
the Note. Copied links must resolve unambiguously across the current Triptych.

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

AppKit tabs use equal-width rounded labels and system typography/colors. Below two tabs, it hides.
One collection spans roles; Library browsing preserves it and the shared panes. AppKit owns containment;
Scholium guards selection and close. Library and Chat provide **Open in Separate Window**. Each Note has one location per Triptych; reopening activates it. Ordinary
opening replaces selection; Open in New Tab appends. Switching preserves state without saving; background close saves only its target; selected close chooses right, otherwise left; last close shows No Document
Selected. Failure retains the tab with Retry. Menus provide Close/Next/Previous Tab and Document Tabs for overflow.

Tabs drag with an insertion gap; dropping back reorders, Escape cancels. Dropping
outside, or **Move to Separate Window**, moves the same session into one document window: Review/Edit, Find, and
save/conflict/recovery actions; no Library, Chat, Inspector, tabs, or floating
priority. **More** reuses the shared Note Actions menu, with **Move to Main Window** and
**Close Window** as its window-specific actions. Hover/focus reveals ×; right-click targets its tab. Removal is immediate. Preparation
precedes removal; source, Undo, selection, scroll, mode, and conflicts travel
without forced save. Saving finishes first; composition or failure keeps
its location. **Move to Main Window** appends and selects, reusing the
origin, another same-Triptych main window, or creating one. Closing separately
closes the document through save guards; it never returns automatically. Main closure or navigation preserves separate windows. Scholium owns session
transfer; AppKit owns windows and dragging, without window-tab grouping.

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

Menu group order:

- **File**: create/open; close; import; duplicate/rename/move; attachments; reveal; Trash.
- **Edit**: native editing; Markdown paste; Find.
- **Format**: styles; headings/lists; quotations/code; tables.
- **Insert**: links; footnotes; images; tables/breaks; comments/Callouts.
- **View**: history/search; panes; Document mode; text size/appearance.
- **Research**: related material; selection to Chat; Settle; Agent Changes.
- **Window**: native windows; tabs/transfer; Notifications.
- **App**: native commands and Settings (§18.2.1).

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
  Integrity filters, source properties, and a Sort By submenu;
- one Add menu for immediate New Note and New Folder;
- a single scrollable hierarchy of real folders and Notes, including root Notes
  and empty folders; and
- explicit empty, loading, stale, and recoverable error states.

Library is a muted section label rather than a competing page title. Organize
and Add remain separate native menus and focus targets with familiar symbols;
macOS owns their resting, hover, press, focus, disabled, menu, and accessibility
presentation. Folder-local Expand/Collapse remains in each Folder's contextual
and accessibility actions.

Library and Chat share semantic action and object symbols. Repeated actions use
one glyph; editing, creating, archiving, restoring, dismissing, removing supplied
material, and deleting remain distinguishable. Custom accessory glyphs share an
alignment track; compact action labels use the shared control target independently
of glyph size. Native Source List and header controls retain their own geometry.
Symbol-only actions retain complete accessibility names and pointer help. Domain
state symbols remain paired with meaningful state text where a glyph is ambiguous.

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

Menus and accessibility actions provide creation, Rename, Move, Copy Relative
Path, Reveal, disclosure, and Trash. Notes offer native left-swipe Move to Trash
with confirmation; right swipe has no action. AppKit owns feedback. Drag carries Note identity/revision or Folder vault/path,
never source text. Invalid,
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
external Agent Note mutation and the live Chat events defined in §8.7.6. The first eligible background event requests
system authorization directly; there is no in-app permission pre-prompt or
separate enable switch. Denial is respected without repeated requests.
Foreground events update the bell and local Note state without banners or
focus changes. Consecutive writes to one Note coalesce to the latest exact
change; individual machine-local receipts remain inspectable.

System notification text is generic and excludes Note titles, paths, and source.
Only opaque Triptych, change, Note, operation, fingerprint, conversation identity
and Chat event category support click routing. Opening a change revalidates its
exact receipt; opening Chat reveals its exact conversation and leaves the Note
unchanged. Missing or stale targets
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
