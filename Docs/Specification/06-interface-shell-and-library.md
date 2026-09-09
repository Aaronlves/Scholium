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
3. **Apparatus**: the trailing Research Inspector's About and Links pages.

Native split behavior governs resizing and collapse. Scholium requests the
initial Inspector reveal but never continuously reasserts divider positions.
The main/auxiliary color and material boundary follows §19.1; native safe areas
protect content through window zoom and resize. Only the selected Sidebar page
participates in pointer, tooltip, keyboard and accessibility interaction; retained
pages cannot intercept another page. A popover remains an auxiliary surface.

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
selection or execution in a selected conversation disables the batch action; canceling changes no
conversations. Detail options open only this conversation's Agent Changes. Library and
Chat share a native panel-header action group with consistent symbol sizing,
neutral ink and complete button hit areas. Native controls own interaction feedback.
Sidebar container edges align across Search, the workspace navigator, conversation
cards and the composer; headings, dates and row text use one content inset.
Inspector/editorial geometry does not determine these sidebar relationships. The bottom
composer and compact conversation-files entry float above the transcript using
native Liquid Glass. Transcript content scrolls beneath these controls, with no
extra opaque backing, gradient mask or simulated blur. A measured bottom inset
lets the latest message and every action scroll fully clear of the controls;
growing drafts and material changes update that inset without moving a researcher
reading earlier messages. New replies follow the bottom only while already there;
otherwise a compact latest-reply action preserves the reading position.
A disconnected-state Connect Codex action starts initial setup or retries a real
unresolved failure; restored connections require no repeated setup. Sign-in appears
only when needed. Connection editing belongs in
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
legible full-opacity text. Repeated visible speaker labels are omitted; alignment
and accessible speaker names retain authorship. Agent replies support natural long-form prose.
One quiet status above each attributed Agent turn replaces its speaker label and
serves as the process disclosure when process items exist. It describes observed
research activity, followed by elapsed time only when runtime timing is known.
Completion shows total turn duration, including waits, never private thinking time;
missing timing stays unnumbered. Waiting, interruption, uncertainty and failure
have distinct text. The top status has no decorative symbol or pulse; only its
disclosure affordance appears after its label on hover or keyboard focus. It
retains a named, keyboard-accessible toggle. The current activity names its
observed action and target, with intermittent text shimmer. Completed activities
use quiet past-tense descriptions without repeated success badges. Other running
items remain identifiable; no parallel work is silently marked complete. Short
operations avoid flashing, and stopped, waiting or inactive presentations stop
shimmer immediately. Reduce Motion and Increase Contrast retain static readable
text. Glyph positions, input, scrolling and window geometry never animate with
shimmer. Runtime command-action metadata may describe reads/searches; unknown
commands use neutral wording rather than inferred research claims.
Body text uses native primary text; history and supporting labels use secondary
text. The collapsed process shows only its single status/timing row, without an
operation inventory. Disclosure follows distance from research: answers, source
navigation and necessary decisions are direct; operation history is secondary;
raw technical records are deeper. Consecutive tools between public commentary
form one collapsed, single-line activity row whose current action updates in
place. Expanding reveals individual operations; each discloses
its retained command, parameters, output and errors in a native grouped card,
with text selection. Copy appears beside the section title on pointer hover or
keyboard focus, with an additional context-menu route. The card omits redundant
success labels. Long details scroll within that bounded card. Missing output is
explicit, never reconstructed. Diagnostics provides an additional overview,
never the sole detail route. Failure remains identifiable on the collapsed row.
Public progress commentary and individual
tool calls form a leading-aligned Agent process group, separate from the final answer.
Each call retains its own target and outcome rather than being replaced by counts
by tool type. During execution public commentary remains readable while tool
groups stay collapsed unless opened. Accessory symbols share size and semantic
secondary color; disclosure controls trail their labels and reveal on demand.
After completion it collapses while the final answer remains visible, unless the
user is reading earlier content or has explicitly expanded the process or an
operation's details. Manual disclosure choices survive new items and outcomes.
Streaming and collapse do not animate the entire transcript or steal its position. Unresolved approval,
failed-turn and uncertain outcomes remain visible; Find reveals a matching process
entry without dropping the draft or stored trace. Reply Note links open Notes;
Chat adds no duplicate file cards above or below those links. Reading and no-op
records belong to activity details, where exact returned Note identities provide
Open Note. The floating Changes entry counts confirmed, not-yet-viewed mutations
in this conversation, never reads or runtime-only claims. Its native popover
separates Open Note from View Changes and retains All Changes history when the
pending list is empty. Input attachments remain separate draft materials.
Return to latest is a neutral downward-arrow button with an accessible name, shown
only away from the latest content. Exact comparisons remain available
only by explicit action. Input attachments remain separate draft materials.
Each final reply provides a quiet Copy action and a Sources action when it contains
locatable references or has supplied materials in its confirmed turn. Sources opens a native popover for that reply, including cited
webpages, Notes and other supplied locators; it is not restricted to workspace Notes.
It retains source titles and destinations without inventing previews or attributing
uncited search results to the answer. Supported destinations open through their
existing owner; other locators remain selectable without executing arbitrary URLs.
Source rows disclose observed read ranges, revision and bounded excerpts without
promoting a different version or an uncovered cited line to verified reading.
Runtime web access remains separately named. A compact Materials for This Turn
disclosure reuses the existing Note/file/image previews and identifies the supplied
representation; it never presents all materials as citations or adds another reader.
Sources and conversation file-operation history have distinct scopes. Ratings and
export actions are not part of this initial reply-action surface.
Reply prose wraps normally. Inline code has a semantic system-gray background.
Tables and code retain bounded horizontal scrolling; Mermaid reuses the local
safe renderer with visible failure fallback. Diagrams omit developer hints,
format labels and a separate source disclosure; Copy returns exact diagram code.
Rich objects offer Copy and Expand without executing content or changing Notes.
Expand presents a native transient card near its source, fitted to measured content
and bounded by the screen. It has no title bar, traffic-light controls, backdrop
dimming or blocked workspace. Click outside or Escape dismisses it; large content
scrolls within the card. Returning preserves the conversation and reading position.
Vertical scrolling over any inline reply object scrolls the conversation; horizontal
scrolling stays local to wide tables and code. Loaded message heights remain stable
while scrolling; reaching the latest reply never disables reverse scrolling. User
scrolling suspends automatic following. Copy and Expand retain the same SF
Symbols, size and semantic color across native and embedded content.
Inspector modes remain document-dependent. Toolbar
validation and View menus derive availability from the same current window state. Native
spacers express logical grouping; the system owns glass shapes, proximity effects, and
transitions. This native state contract applies to every toolbar component, including
history, document mode, Settlement, and Inspector modes. A disabled action cannot
execute through another toolbar or overflow route. Document-specific popovers close when
their document or required source revision changes; detaching a window ends its toolbar
interactions and prevents stale state from updating it. Back/Forward begin the Document
toolbar region, after the sidebar tracking boundary and before its secondary-text document
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
- **App**: Settings opens the single native preferences window under §18.2.1.

#### Chat capability presentation

Agent Integration settings contains native Methods and Connected Tools
disclosures with Refresh, per-method enablement, descriptions and discovery
errors. The connected configuration scope is visible before applying a setting;
a shared configuration change requires explicit confirmation. The protected
Core Protocol is identified separately from researcher methods. Tool inventory
shows the actual observed connection/authentication state and discoverable tool
names; a count alone does not imply tools were invoked or source material read.
Typing `$` offers available methods in a compact native candidate popover;
chosen methods retain removable labels in the draft. Sent messages retain those labels as requested methods, without an
invocation badge unless the runtime supplies an invocation event.

Methods settings offers Add Methods Folder and a compact Associated Folders
disclosure. A named folder chooser adds an association; each folder has an
accessible Remove Association action and an inspectable full path. These
associations affect Scholium's connected process, including when it reads a
shared configuration; they do not change the other host's discovery settings.

A tool requiring authentication offers Sign In. The runtime-provided page opens
after the explicit action, with Continue Sign-In available while the flow is
pending. Completion and failure are concise native status text. Shared-scope
confirmation binds to the configuration that was shown; switching connections
cannot redirect a pending approval to another configuration.

Connected Tools offers Add Tool and per-connection Edit, enable/disable and
Remove controls. The native form distinguishes Remote and Local, with name,
address or program, and arguments where applicable. Advanced authentication uses
runtime-managed sign-in or named environment variables in an Advanced disclosure.
Remote connections expose a bearer-token variable name; local programs expose
inherited variable names. Brief supporting text distinguishes names from values.
The form does not become a second credential store. Shared scope and removal require confirmation
of the named connection. Failed saves preserve the form; Reload is explicit.

Add Material offers Choose Note and Add Selection as distinct actions. Choose
Note opens a native searchable list with title, vault role and path, followed by
explicit Add or Cancel. Empty, unavailable and failed capture states retain the
query and selected identity. Material previews identify whole Note versus
passage and saved source versus editor snapshot; previewing exact supplied text
does not open or replace the working Document. Open Source remains separate.

Choose File accepts supported papers, text files and images. File chips show
the filename and supplied representation; a preview exposes the source location,
page coverage or preparation problem, with system Quick Look for the retained
file. Image previews use a system-generated thumbnail of the retained snapshot,
with Quick Look for full inspection. Preparation has a cancellable native
progress state. Failed material and
unsupported model input remain visible beside the composer with a repair action;
they do not erase the question or disappear on Send. Paste and drop use the same
preparation path as the named picker.

Paste in the message editor accepts clipboard images as material chips. Their
details show Clipboard as the source and identify a PNG conversion when one was
needed. Standard text paste continues to edit the message; pasting in Find or
conversation search does not attach a material. No additional clipboard window
or background clipboard control is introduced.

PDF material details offer Use Page Images. A native sheet identifies the PDF,
its physical page count, a named page-range field and the rendering limit, with
Use Pages or Cancel. No pages are preselected silently. The completed material
shows its exact selected page ranges and image representation; the original
PDF remains available through Quick Look. Failure or cancellation before the
replacement is attached keeps the previous material and question.

The conversation list has a native search field; the archived list retains its
explicit scope. Matching rows show a passage containing the query. Changing the
list query clears temporary archive/restore selection. Detail
options provide Find in Conversation and Rename Conversation. Find opens a
compact native search field with previous/next, a matching-message position and
Done. The focused search field accepts Return/Shift-Return to navigate and
Escape to dismiss. The current matching message is revealed and identified
without relying solely on color. Search and Find state belong to the visible
view; neither changes stored messages, drafts or execution selection implicitly.

Detail options expose Branch Conversation with a choice of ended exchanges;
the message menu offers the same action at its exact turn. A branch has a quiet
Open Original Conversation route. Creating it shows a cancellable pending state;
failure stays with the source conversation. The branch is opened only if the
researcher is still viewing its source; otherwise it appears in the list without
pulling them out of another discussion.

Edit in New Branch is available on an eligible researcher message and through
Edit Earlier Request in conversation options. The choice identifies the request
by its text. The new discussion opens with that request in the ordinary composer
and its original materials and methods visible, ready for editing and explicit
Send. It reuses branch progress, cancellation and failure presentation; it adds
no second message editor or confirmation sheet. Requests without an independent
ended-turn boundary do not offer this action.

The composer uses `/` for supported conversation controls, `@` for Note/material
selection and `$` for method Skills. A small native candidate popover filters
the current query, supports arrows, Return and Escape, and never consumes marked
text or sends the message on selection. Literal punctuation outside an active
candidate query remains ordinary prose. Selection replaces only that query and
preserves surrounding text, native Undo and the captured conversation. A single
discoverable actions entry offers the same routes without requiring memorized
syntax. Send/Stop, current model and permission remain immediately inspectable;
separate permanent method and web-search buttons are removed. Model choice never
lives inside Add Material. Native menus and named pickers expose selected values;
short labels and direct
actions lead, with explanations only for unavailable or consequential states.
An explicit web-search mode is distinguishable from Note Search.

Conversation options expose Rename, Find, Branch, Context and Diagnostics.
A compact composer percentage opens the same native Context popover by click or
keyboard when runtime usage and capacity are known; unknown usage remains unnamed
numerically. Context separates last-reported occupancy from cumulative consumption,
with bounded native progress, token details and a state-valid Compact Context action.
It never estimates subscription charges or invents unreported token breakdowns. Account quota
has a separate labelled presentation. Search in the conversation list retains
its scope and query; in-conversation Find provides match navigation and Close.
Both preserve drafts and running work. A branch names its origin and does not
look like an edit to historical messages.

Research questions use native option controls with their short descriptions,
an ordinary or secure answer field as appropriate, and Reply / Skip actions.
They do not show Allow Once or an expanded protocol payload. Choices begin
unselected; the selected option remains apparent. Operation approvals retain
their own operation, scope and allow/decline presentation.

A Note update prompt names its target and offers Review Changes. The comparison
reuses the existing exact-source comparison surface, with saved source and
proposed source labelled explicitly and unchanged ranges folded. It provides
the same request's Allow Once / Decline actions and an ordinary close route;
closing preserves the unanswered request. Approval is unavailable after that
request ends. The compact prompt contains no duplicate full proposed source.

Runtime approval presents the actual command or terminal input, reported file
proposal, or requested permission rules as a native read-only form. Exact paths
and scope precede optional technical details. Allow Once and Allow for This Turn
remain distinct from an explicit Allow for Session action. Unsupported approval
scope shows its unavailability without offering an unchecked grant. Waiting for
confirmation replaces decision controls and preserves the inspected request.

The latest actual activity is shown in the Agent process group in the transcript; Stop
remains immediately available at the composer. Plans and each tool call retain native
disclosure for detail; live queries, sources, exact targets and outcomes remain inspectable. Cards distinguish source material, questions, approval and
operation evidence without enclosing every prose paragraph. Source links and
material previews retain provenance under §8.7. Technical payloads remain behind
Details; human questions and changes have first-class native controls.

Waiting for input, failed, completed and running conversations are identifiable
in the list without changing selection. The Chat selector indicates when any
conversation in that Triptych needs input, including one that is not visible.
Child work appears under its parent,
with supported actions scoped to that exact child. Delegation reports use native
disclosure for supplied requests and results, with each target's reported state
visible; completion of the coordinating call does not hide its report among
routine completed tools. The coordinating operation's outcome remains distinct from target
completion; technical identities remain inspectable without becoming the main
label when a runtime path is available.

Each reported Agent has an explicit Open Agent action. Its native detail keeps
parent context, observed state, public history, Refresh and an applicable Stop
Agent action together. Pending reads and interruption remain distinguishable;
missing ancestry, disconnected state and unavailable history have a readable
recovery route. Closing this inspection grants nothing and leaves execution
alone.
Nested reports navigate within this same detail using native Back navigation,
without stacking sheets. Back restores the previous Agent context; Done closes
the entire inspection. The original conversation remains the visible parent
context at every depth, including unavailable destinations.

Runtime-managed schedules live with the relevant conversation and expose timing
and pause/remove actions;
the interface never implies an unavailable background execution capability.

Agent detail keeps an adjustment composer separate from its transcript, with
Ask Parent naming the actual receiving role and a route to that parent
conversation. Sent, unavailable and unconfirmed delivery remain distinct.
Public messages and editable branches show the retained Agent target as a
compact reference with inspection/removal where applicable; unavailable branch
targets expose their original conversation without obscuring the text draft.

Chat transient content is organized into native grouped cards: one request and
its consequence per approval card, one question and its options per question
card, and distinct source/representation and exact-content groups for materials.
Card headings name the object or action; technical identifiers remain secondary.
Cards use system content surfaces under §19.1 rather than glass over readable
prose. Native menus, segmented tabs and floating controls retain their system
material; a surrounding card never recreates their selection plate or effects.

Agent detail uses Activity and Details tabs inside one native grouped content
region. State, failure, Refresh and Stop remain outside the tabs and visible;
the parent adjustment composer keeps its identity while tabs change. Details
holds exact Agent and parent identities. Context and Account Usage use the same
native grouped-tab navigation, retaining their distinct scope and valid actions.
Tab selection and disclosure are local presentation only: switching cannot read,
resume, cancel, send or clear a draft. Long tab content scrolls within its card.

Motion follows native controls and containers under §19. Card disclosure and tab
selection use system transitions; request-to-confirmation feedback changes in
place with a persistent label and restrained native symbol replacement. Reduce
Motion supplies the same state immediately. No full-form transition replaces an
active answer field, restarts its identity, or delays a decision. Streaming displays
arriving text without artificial typing delays, repeated entrance effects or
reanimation of existing paragraphs. Changes preserve stable message identity,
selection and reading position. Completion, interruption and errors retain static
labels; activity indicators stop when activity ends. No fabricated progress,
reasoning trace or animated research-confidence meter is presented.

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
