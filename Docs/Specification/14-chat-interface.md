# Specification: Chat Interface

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Section 18.2.2.

## 18.2.2 Chat presentation

[Agent Chat §8.7](12-agent-chat.md) owns conversations, runtime capabilities,
materials, execution and recovery. This chapter owns their native presentation;
[Workspace shell §18.2](06-interface-shell-and-library.md#182-workspace-shell-and-document-tabs)
owns sidebar placement, and §20 owns accessibility. Design remains the sole
visual authority.

### Conversation list and transcript

Chat inherits the Sidebar background with list-to-detail
navigation. A native sidebar List scrolls; buttons open conversations without persistent selection. Text-aligned separators divide rows in one continuous list. Dates accompany titles; no date sections. Titles wrap and expose Help; previews
strip Markdown while retaining search matches. Draft, Unread, Important
and current activity have text equivalents; completed turns carry no checkmark.
One click opens; native button focus and keyboard activation remain available. Organize switches
current and archived lists, without batch mode.
While the list is open, existing rows retain their order as live previews update.
Re-entering the list refreshes recency order; newly visible conversations remain discoverable.
Within a workspace window, returning to a conversation restores its reading
message and relative position, together with explicit activity and plan disclosure
choices. New content cannot turn a retained history-reading position into follow-to-latest.
Long transcripts initially mount a bounded recent portion; Earlier/Later Messages
expose retained history progressively. Paging preserves the visible passage;
explicit jumps may replace the mounted portion without deleting history.
Left swipe reveals Archive for current conversations, Delete and Restore for
archives. Right swipe toggles read and
important markers. Read/Important/Archive use system blue/orange/purple; Delete uses its destructive
role. Native controls own continuous swipe feedback. Full swipe executes read or archive actions; deletion requires its button and confirmation. Menus and accessibility actions
provide equivalent operations plus Rename and Changes. Search filters include
Unread and Important, with Clear/empty feedback. §8.7 owns durable meanings.
Library and Chat share native header controls and a spacing grid; headings,
dates and row text align. The bottom
composer and compact conversation-files entry float above the transcript using
native Liquid Glass. Transcript content scrolls beneath these controls, with no
extra opaque backing, gradient mask or simulated blur. One bottom area arranges
the queue, input/request surface and candidate anchor. Its measured inset
lets the latest message and every action scroll fully clear of the controls;
growing drafts and material changes update that inset without moving a researcher
reading earlier messages. New replies follow the bottom only while already there;
otherwise a compact latest-reply action preserves the reading position.
Selecting or operating reply content also pauses automatic follow until the
researcher returns to the latest reply. Streaming preserves the active passage selection.
A disconnected-state Connect Codex action starts initial setup or retries a real
unresolved failure; restored connections require no repeated setup. Sign-in appears
only when needed. Connection editing belongs in
Settings, with manual paths editable only in its explicitly advanced connection group. Composer secondary controls
are borderless; current model/reasoning remains visible beside the input. Full Access
retains an explicit visible status when enabled; selected permissions remain named in Chat Settings.
The circular Send button uses native control styling; availability, keyboard sending and
native state feedback remain authoritative. The whole message input rectangle, including
whitespace, is editable; text clicks position the native caret. Return sends when
available; Shift-Return or Option-Return inserts a newline. Marked-text Return belongs
to the input method. Native placeholder visibility includes composition and never overlaps marked text. Unavailable sending preserves the draft and selection, with a
visible connection explanation when disconnected. Native selection and Undo remain
within the current conversation. Sending starts a fresh draft Undo history;
Chat input never shares that history with Document or another input.
Back returns to conversations while work
continues. User messages align trailing in content-sized shared-Accent bubbles with
legible full-opacity text. Repeated visible speaker labels are omitted; alignment
and accessible speaker names retain authorship. Agent replies support natural long-form prose.
One quiet status above each attributed Agent turn replaces its speaker label and
serves as the process disclosure when process items exist. It describes observed
research activity, followed by elapsed time only when runtime timing is known.
A pending asynchronous answer count remains beside the turn status even after
runtime completion; it does not change that recorded outcome.
Completion shows total turn duration, including waits, never private thinking time;
missing timing stays unnumbered. Waiting, interruption, uncertainty and failure
have distinct text. Completed process groups use an **Activity Log** label with
reported duration when available; their accessible name retains the turn outcome.
The header is a quiet text row with a leading disclosure triangle, without a
full-width selection plate or link-colored hover treatment. Its entire row is a
named, keyboard-accessible toggle. The current activity names its
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
raw technical records are deeper. Each activity has one row and one disclosure for its retained command,
parameters, output and errors. Single calls have no extra grouping layer.
Delegation follows the same disclosure hierarchy: its collapsed row names the
action and supplied task path or Agent count. Opaque identities, requests, reports
and per-target navigation stay in its details. Coordination completion never
claims target completion; failures and unavailable reported states remain visible.
Unknown commands may show their literal identifier as secondary text without
inferring purpose. Details expose reported exit code, duration and directory;
missing values stay absent. Long output opens in the shared resizable read-only preview
with selection and copying. Failure and unconfirmed-outcome counts remain
visible when the process is collapsed, regardless of a final answer or later
successful calls. They report evidence, not an inferred need for intervention.
Diagnostics remains an additional overview.
Public progress commentary and individual
tool calls form a leading-aligned Agent process group, separate from the final answer.
Each call retains its own target and outcome rather than being replaced by counts
by tool type. During execution public commentary remains readable while individual tool details stay collapsed unless opened. Accessory symbols share size and semantic
secondary color in a shared leading gutter. Tool symbols yield to a disclosure
triangle on hover or focus; the expanded triangle remains visible. Expanded
content uses indentation and a quiet hierarchy rule rather than nested cards.
Inline tool details lead with their outcome and expose Copy and Open Output
directly, with exact execution facts and output below.
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
separates Open Note from View Changes. Both the entry and All Changes history remain
when the pending list is empty; only the pending badge disappears. Input attachments
remain separate draft materials.
A compact Agent-count capsule sits beside Changes when retained child work exists,
and remains available when no Changes await review. Its native popover lists
the distinct Agents, including ended work, grouped by observed Active, Not Running
and Unavailable states, with first-appearance order within each group. Opening and
Refresh verify ancestry and read metadata; supplied names, observed states and
observation times remain distinct from historical reports. Refresh failures retain
prior information with an explicit failure label. Each row opens the existing verified Agent
detail. The two entries stay together when narrow widths move the latest-reply action
onto a second row. No empty accessory row remains when none of these entries applies.
Opening the list neither starts nor refreshes Agent execution.
Return to latest is a neutral downward-arrow button with an accessible name, shown
only away from the latest content. Exact comparisons remain available
only by explicit action.
Each final reply provides a quiet Copy Markdown action for its exact reply text and a Sources action when it contains
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
Sources and conversation file-operation history have distinct scopes. Eligible
message actions use familiar icon buttons for Copy Markdown, Sources, Materials, Edit in
New Branch, Branch from This Turn, Retry in New Branch and Quote in Reply. The
row appears when the pointer enters that message or its controls receive keyboard
focus. It remains visible with VoiceOver or Switch Control. Visual concealment
never removes native controls from keyboard traversal or accessibility, changes
layout, or moves the reading position. Full Help and accessible names identify
each action; no More menu replaces these direct actions. Inapplicable actions
stay absent; temporarily unavailable branch actions retain disabled state.
The action row shares one compact content-control treatment with composer
accessories, attachment removal and queue actions: equal activation targets and
consistent pointer feedback, while native controls retain focus and disabled
behavior. Revealing the row and highlighting one action are separate states.
Floating Changes/Agents controls use native button chrome; menu items, primary
delivery controls, disclosures and navigation rows retain their own categories.
Native text selection retains Copy and Ask About Selection in its context menu;
message actions retain context menus at their controls without covering the
text's pointer interaction. Pointer hover is not the sole route.
Selected reply text supports ordinary Copy/Paste and copy-only dragging into
Edit or Source. The editor shows a valid insertion point and inserts the selected
rendered text there, with focus ready for typing and one Undo step. An unavailable
drop position, read-only surface or active composition cannot replace an existing
selection or change source. Copy Markdown retains the complete original reply;
selected-text copying does not reconstruct Markdown from its presentation.
Dragging selected Document text into the composer inserts ordinary draft text
at its native drop target without removing Note source or sending the draft.
Both directions use native text dragging, including enabled three-finger trackpad
dragging. The system owns gesture timing, selection-versus-drag disambiguation
and the selection image; the app does not force immediate dragging or draw a
replacement preview.
Changing text focus preserves the other surface's selection while presenting
it as inactive; two retained selections must not both imply current keyboard focus.
Ratings and export actions are not part of this reply-action surface.
Reply prose fills the available width between the shared sidebar grid insets,
using ordinary line wrapping without paragraph-wide line balancing or extra
reading-column margins. User messages, public commentary and final answers
share one Markdown presentation; adding a table or other rich object does not
change existing prose or inline-code styling. Paragraphs, headings, lists and
quotations share a compact, font-relative rhythm without inheriting Document
Appearance spacing. Headings stay subordinate to the conversation; quoted prose
retains full text contrast. Short user paragraphs fit their rendered content;
long requests reflow within the same trailing bubble. Inline code has a semantic
system-gray background.
Tables and code retain bounded horizontal scrolling; Mermaid reuses the local
safe renderer with visible failure fallback. Diagrams omit developer hints,
format labels and a separate source disclosure; Copy returns exact diagram code.
Rich objects offer Copy and Expand without executing content or changing Notes.
Table Copy retains the corresponding source Markdown; code and diagram Copy
retain the corresponding code. Each action addresses the same object as its
inline presentation, including repeated objects and source-only fallbacks.
Their shared native action row appears when the pointer enters the object or its
controls receive focus, and remains visible with assistive navigation. Revealing
it preserves layout and selection. Copy uses the ordinary content-copy symbol
replacement only after confirmed clipboard success, with a static Reduce Motion equivalent.
Expand opens one native temporary preview centered over its originating workspace,
using most of that window's area while staying inside the visible screen. Code,
tables, diagrams and operation output share its presentation and dismissal owner.
There is no visible title bar, traffic-light control, popover arrow or dimming
backdrop. A quiet header retains identity, Close and Copy. Escape, Close or clicking
outside dismisses the preview; the outside click does not also activate a workspace
control. Switching away or closing the originating window dismisses it. Closing
from within returns focus to the origin and preserves conversation reading position.
Opening uses a restrained expansion and fade directed from the initiating control;
explicit dismissal reverses toward that origin without a large reader reflow. The panel remains above its parent until
dismissal completes, so it never appears merely hidden behind the workspace.
Reduce Motion uses a short fade without spatial movement.
Content fills the preview: text and tables scroll locally and diagrams fit the
available canvas. Native resizing remains available without separate window chrome.
Vertical scrolling over any inline reply object scrolls the conversation; horizontal
scrolling stays local to wide tables and code. Loaded message heights remain stable
while scrolling; reaching the latest reply never disables reverse scrolling. User
scrolling suspends automatic following. Copy and Expand retain the same SF
Symbols, size and semantic color across native and embedded content.
### Chat capability presentation

Agents & Chat settings contains a retained Skills and Tools task segment
with native Skills and Connected Tools groups with Refresh, per-Skill enablement, descriptions and discovery
errors. The connected configuration scope is visible before applying a setting;
a shared configuration change requires explicit confirmation. The protected
Core Protocol is identified separately from optional Skills and shown as always
included and protected; its source has a read-only Finder reveal route. Tool inventory
shows the actual observed connection/authentication state and discoverable tool
names; a count alone does not imply tools were invoked or source material read.
Typing `$` offers available Skills in a compact native candidate popover;
chosen Skills retain removable labels in the draft. Sent messages retain those labels as requested Skills, without an
invocation badge unless the runtime supplies an invocation event.

Skills settings identifies This Triptych and offers Open Chat Workspace in
Finder for its `.scholium` directory. Adjacent copy identifies `AGENTS.md` and
`skills/`; no folder chooser, association list or editable discovery path is
shown. Refresh repairs a failed workspace discovery without erasing the draft.

A tool requiring authentication offers Sign In. The runtime-provided page opens
after the explicit action, with Continue Sign-In available while the flow is
pending. Completion and failure are concise native status text. Shared-scope
confirmation binds to the configuration that was shown; switching connections
cannot redirect a pending approval to another configuration.

Connected Tools offers Add Tool and per-connection Edit, enable/disable and
Remove controls. One inline selected-tool editor distinguishes Remote and Local, with name,
address or program, and arguments where applicable. Authentication uses
runtime-managed sign-in or visible named environment-variable fields in the
native tool editor.
Remote connections expose a bearer-token variable name; local programs expose
inherited variable names. Brief supporting text distinguishes names from values.
The form does not become a second credential store. Shared scope and removal require confirmation
of the named connection. Zotero's tool editor lives in the dedicated Zotero
Settings page beside its separate Desktop Local API diagnosis; the generic
tool list links there without duplicating configuration controls. Failed saves preserve the form; Reload is explicit.

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
options provide Find in Conversation and Rename Conversation. The named Conversation
Outline command in the header's options menu opens a searchable native question list with bounded
answer previews. Selecting a question loads its retained portion and jumps to that
exchange without changing the draft or execution. Keyboard and accessibility
activation provide the same navigation as pointer selection. Find opens a
compact native search field with previous/next, a matching-message position and
Done. The focused search field accepts Return/Shift-Return to navigate and
Escape to dismiss. The current matching message is revealed and identified
without relying solely on color. Search and Find state belong to the visible
view; neither changes stored messages, drafts or execution selection implicitly.

The message action row offers Branch from This Turn at an ended exchange;
conversation options do not duplicate turn-selection controls. A branch has a quiet
Open Original Conversation route. Creating it shows a cancellable pending state;
failure stays with the source conversation. The branch is opened only if the
researcher is still viewing its source; otherwise it appears in the list without
pulling them out of another discussion.

Edit in New Branch is available in the eligible researcher message's action row.
Its placement identifies the exact request. The new discussion opens with that request in the ordinary composer
and its original materials and Skills visible, ready for editing and explicit
Send. It reuses branch progress, cancellation and failure presentation; it adds
no second message editor or confirmation sheet. Requests without an independent
ended-turn boundary do not offer this action.

The composer uses `/` for supported conversation controls, `@` for Note/material
selection and `$` for Skills. A small native candidate popover filters
the current query, supports arrows, Return and Escape, and never consumes marked
text or sends the message on selection. Literal punctuation outside an active
candidate query remains ordinary prose. Candidate placement follows its measured
content and input anchor rather than a row-count estimate in the conversation.
Selection replaces only that query and
preserves surrounding text, native Undo and the captured conversation. A single
discoverable actions entry offers the same routes without requiring memorized
syntax: file selection, Note mentions, Skills and commands. Menu labels name
actions without syntax hints. Gray placeholder text inside the empty composer
and its accessible Help explain the three prefixes; the placeholder disappears
during typing or marked input. The `/` catalog uses
single-token names for Context, Account Usage, Find, Outline, available Changes
and Agents, Skills and idle Web Search choices. `@` offers named Notes, file
selection and the current selection; `$` offers enabled optional Skills with
refresh and management. Candidates remain fully reachable within a bounded
viewport; arrows scroll to the selected item, and refresh preserves its identity
or resets to a valid item. Availability is checked again before accepting a
candidate; an unavailable action preserves the query. Expanding a request or
leaving Chat dismisses suggestions without editing the retained draft.
Interaction > Chat chooses whether Return during work adds to the current turn
or queues the next one. The send button follows the same preference and exposes
its effective action. Idle Return sends normally; newline and IME behavior remain
unchanged. The default is immediate input. Queue is not an Add-menu action.
Queued input appears in a native Liquid Glass surface behind the input surface.
A single queued message has a visible summary row and a direct Steer action; idle
input exposes Send Next. Multiple messages start collapsed to one named count
and expand into rows in a bounded scrolling region. Inspection keeps that group
open; explicit editing and delivery retain its expanded state. Failures remain
visible through the owning conversation state. Only empty surface margins overlap; text, focus rings and controls remain
clear of the front input surface. Selecting a summary opens a native popover showing its
full text once, with retained Note snapshots, file representation labels, quotations
and requested Skills available in its material disclosure. Add to Current Turn explicitly sends the selected item as
additional input to its bound running turn; Send Next retains queue order while
idle. Inspection cannot dispatch or reorder input. Edit Message opens a native editor
for the queued text without replacing the composer draft or its materials.
Saving preserves queue identity, position and attached context. If already sent,
the edit is not applied and remains available to copy. The composer places Add to Chat, the current model/reasoning selection and
delivery in one bottom row, with a small Context indicator beside the model.
The composer has one enclosing surface. Its quote, Note and file summaries sit
directly within it; they do not add nested card backgrounds. Secondary controls
have quiet resting states and shared transient feedback. Send and Stop retain
their native primary-action prominence. Exact previews and removal remain
available, and sent materials retain their own transcript grouping.
Its hover Help and accessible value show last-reported occupancy, remaining
percentage and used/total tokens. Unknown capacity has an explicit unavailable
state, never a zero reading. Clicking the indicator opens a content-sized native
popover anchored to that button. Occupancy leads; remaining capacity and token
counts are secondary. One Details disclosure contains cumulative token use and
the complete prepared-context list in a bounded scroll area. Compact Context
remains in the footer with runtime-owned availability. Chat Settings at the model label groups named Model,
Reasoning, Permission and Web Search pickers. Selected values remain visible in
those menus; long model labels truncate with complete Help and accessible values.
Full Access retains a visible status beside the input when enabled. Add Material
groups material and Skill selection. Execution controls do not belong in that menu.
Transcript plans use one disclosure showing the current reported step while active
and the completed-step count; full steps start collapsed and preserve explicit
reading choices. There is no duplicate floating plan entry beside the composer.
These summaries never invent plans, progress or token measurements. Short labels
and direct actions lead, with explanations for unavailable or consequential states.
An explicit web-search mode is distinguishable from Note Search.

Conversation options own Outline, Find, Rename, Account Usage and Diagnostics; a branch also
offers Open Original Conversation. Changes has its existing entry beside Agents
and is not repeated in the detail header. While a request replaces the composer
or a conversation is archived, conversation options provide the Context and Usage
entry at that header. Only one Context presentation may be open. Switching
conversations, leaving the detail, or replacing the input closes it. It
separates last-reported occupancy from cumulative consumption, with bounded native
progress, token details and a state-valid Compact Context action. It never shows a
guessed percentage.
It never estimates subscription charges or invents unreported token breakdowns. Account quota
has a separate labelled presentation. Search in the conversation list retains
its scope and query; in-conversation Find provides match navigation and Close.
Both preserve drafts and running work. A branch names its origin and does not
look like an edit to historical messages.

Composing, questions and approvals share one fitted native Liquid Glass shell
with bounded scrolling.
One request replaces the draft without a duplicate transcript card.
The hidden, inert native editor retains selection, Undo and materials.
Incoming requests never interrupt typing, composition or history reading;
a persistent named entry opens them. Open requests have no return-to-composer
or Escape action. Completion or decline restores the retained draft. Requests
remain reachable until resolved; submission and uncertainty retain identity
and recovery, and only runtime acknowledgement removes a pending decision.
Multiple requests show a count. Conversation changes transfer no answers or grants.
Native resize and crossfade present composing/request changes;
Reduce Motion is immediate. Motion never replaces the editor, delays input,
or leaves outgoing controls actionable.
Request typography and spacing replace nested cards. One bottom row groups
borderless previous-question and skip icons; delivery stays circular. No empty
header action row is added. Scrolling leaves native field focus rings clear.
Composing keeps Stop at the trailing edge throughout active work, including while
a draft can be sent. Available follow-up delivery sits beside it, with a native
send menu offering Send Now and Queue for Next Turn for that message. The primary
send action and Return retain the configured default; choosing the other menu
action neither changes that default nor stops the turn. Idle composing has one
circular Send action. Compaction shows Stop; interruption shows disabled Stopping.
The native Research > Stop Agent command owns Command-Period for the current
window, including when a request replaces the composer. It and the trailing Stop
button share the same interruption action and availability. Command-Return means delivery only.
Symbols retain position and accessible names.

Research questions appear one at a time with a position indicator and Previous
Question action when a request contains several. Clicking an offered answer advances
to the next question; completing the last submits the complete set. Earlier answers
remain editable before submission. Custom answers use a directly visible ordinary
or secure field and a Next/Send icon in the bottom action row, without a separate
option selector.
A labelled skip icon supplies no answers for the entire ordinary request; declining
a tool-input request instead stops its turn and explains this consequence. There is
no duplicate Stop action in the request header.
They do not show Allow Once or an expanded protocol payload. Choices begin
unselected; the selected option remains apparent. Operation approvals retain
their own operation, scope and allow/decline presentation. Secondary actions use native borderless controls; primary delivery and
authorization actions use native emphasized controls. Permissions retain explicit
action labels, while message delivery uses circular symbols. The approval card
leads with the requested action and a readable overview of affected files or
network access, retaining exact targets and restrictions in that overview. It
shows no Access Details or Technical Details controls and does not repeat internal
connection names. Known tool-permission prompts distinguish permission to request
a Note change from approval of the concrete source comparison. Unknown commands
or path patterns are not given an invented
purpose or narrower scope. Unconfirmed submission exposes an explicit end-turn
recovery action; ordinary pending cards expose no separate Stop or return action.

A Note update prompt names its target and offers Review Changes. The comparison
reuses the existing exact-source comparison surface, with saved source and
proposed source labelled explicitly and unchanged ranges folded. It provides
the same request's Allow Once / Decline actions and an ordinary close route;
closing preserves the unanswered request. Approval is unavailable after that
request ends. The compact prompt contains no duplicate full proposed source.

Runtime approval presents the actual command or terminal input, reported file
proposal, or requested permission rules as a native read-only form. Exact paths
and scope remain in the readable overview. Allow Once and Allow for This Turn
remain distinct from an explicit Allow for Session action. Unsupported approval
scope shows its unavailability without offering an unchecked grant. Waiting for
confirmation replaces decision controls and preserves the inspected request.

The latest actual activity is shown in the Agent process group in the transcript; Stop
remains available through the composer's trailing Stop button. Plans and each tool call retain native
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

Agent detail gives public requests, progress and replies the main reading area.
The header retains identity, parent context, observed state, Refresh and Stop;
failures and unconfirmed interruption remain visible. Ordinary tool records use
compact disclosure. Exact identities, role and observation time sit behind one
Details disclosure, without a separate tab. Open Parent and Done remain direct
navigation actions. There is no adjustment composer or Ask Parent control.
Public targeted messages and editable branches retain their compact target
reference and applicable original-conversation and removal routes.

Chat transient content is organized into native grouped cards: one request and
its consequence per approval card, one question and its options per question
card, and distinct source/representation and exact-content groups for materials.
Card headings name the object or action; technical identifiers remain secondary.
Cards use system content surfaces under §19.1 rather than glass over readable
prose. Native menus, segmented tabs and floating controls retain their system
material; a surrounding card never recreates their selection plate or effects.

Context stays in the composer and contains only conversation occupancy, prepared
context and a valid Compact Context action. Prepared context and cumulative token
details start collapsed and retain complete inspectable information. Account Usage
has an independent entry in Chat options, available from the conversation list or
detail, and opens a native account-only sheet with reported quota, reset, Refresh
and Done. Inspecting or closing either surface never reads Notes, resumes a turn,
sends input or clears a draft. Long content scrolls within its own surface.

Motion follows native controls and containers under §19. Card disclosure and tab
selection use system transitions; request-to-confirmation feedback changes in
place with a persistent label and restrained native symbol replacement. Reduce
Motion supplies the same state immediately. No full-form transition replaces an
active answer field, restarts its identity, or delays a decision. Streaming directly
renders received content in the retained reading surface. It has no separate
visible-character counter, concealed text ranges or synthetic typing delay.
The received text remains authoritative; later chunks complete its Markdown
projection without replaying existing text. Reply parsing runs away from the
interface executor, serially coalescing superseded pending snapshots. Completed
prefixes may remain readable while appended source is projected; replacements,
cancellation and final delivery preserve generation identity and exact final text.
There is no artificial character-reveal delay. Completion, Stop, selection, copying,
history reading and accessibility adaptation never leave received text hidden.
Newly sent messages and arriving replies may
fade in once, locally, without moving the transcript. Opening retained history,
reading earlier messages and Reduce Motion show content immediately. Disclosure
motion is confined to its indicator. Content layout changes do not animate the
following transcript or replay its text. Opened activity content retains its
reading state when collapsed, with hidden controls excluded from interaction and
accessibility. Changes preserve stable message identity,
selection and reading position. Completion, interruption and errors retain static
labels; activity indicators stop when activity ends. No fabricated progress,
reasoning trace or animated research-confidence meter is presented.
