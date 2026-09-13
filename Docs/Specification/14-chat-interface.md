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
extra opaque backing, gradient mask or simulated blur. A measured bottom inset
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
are borderless; permissions expose their current value in the actions menu.
The circular Send button uses native control styling; availability, keyboard sending and
native state feedback remain authoritative. The whole message input rectangle, including
whitespace, is editable; text clicks position the native caret. Return sends when
available; Shift-Return or Option-Return inserts a newline. Marked-text Return belongs
to the input method. Native placeholder visibility includes composition and never overlaps marked text. Unavailable sending preserves the draft and selection, with a
visible connection explanation when disconnected. Native selection and Undo remain
within the current conversation. Back returns to conversations while work
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
separates Open Note from View Changes and retains All Changes history when the
pending list is empty. Input attachments remain separate draft materials.
Return to latest is a neutral downward-arrow button with an accessible name, shown
only away from the latest content. Exact comparisons remain available
only by explicit action.
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
Sources and conversation file-operation history have distinct scopes. A quiet row beneath each eligible message exposes Edit in New Branch,
Branch from This Turn, Retry in New Branch and Quote in Reply through named SF
Symbol buttons alongside reply Copy, Sources and Materials. Inapplicable actions
stay absent; temporarily unavailable branch actions retain disabled state.
Context menus remain equivalent routes. Clear action symbols replace repeated
footer labels, retaining full Help and accessible names; counts and meaningful
state text remain visible when an icon alone would be ambiguous. No swipe gesture
is required.
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
Expand opens one native temporary preview centered over its originating workspace,
using most of that window's area while staying inside the visible screen. Code,
tables, diagrams and operation output share its presentation and dismissal owner.
There is no visible title bar, traffic-light control, popover arrow or dimming
backdrop. A quiet header retains identity, Close and Copy. Escape, Close or clicking
outside dismisses the preview; the outside click does not also activate a workspace
control. Switching away or closing the originating window dismisses it. Closing
from within returns focus to the origin and preserves conversation reading position.
Opening expands from the initiating control into the preview; explicit dismissal
shrinks and fades toward that same origin. The panel remains above its parent until
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

Agents & Chat settings contains native Skills and Connected Tools
groups with Refresh, per-Skill enablement, descriptions and discovery
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
Remove controls. The native form distinguishes Remote and Local, with name,
address or program, and arguments where applicable. Authentication uses
runtime-managed sign-in or visible named environment-variable fields in the
native tool editor.
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
options provide Find in Conversation and Rename Conversation. A named Conversation
Outline icon near the composer opens a searchable native question list with bounded
answer previews. Selecting a question loads its retained portion and jumps to that
exchange without changing the draft or execution. Keyboard and accessibility
activation provide the same navigation as pointer selection. Find opens a
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
and its original materials and Skills visible, ready for editing and explicit
Send. It reuses branch progress, cancellation and failure presentation; it adds
no second message editor or confirmation sheet. Requests without an independent
ended-turn boundary do not offer this action.

The composer uses `/` for supported conversation controls, `@` for Note/material
selection and `$` for Skills. A small native candidate popover filters
the current query, supports arrows, Return and Escape, and never consumes marked
text or sends the message on selection. Literal punctuation outside an active
candidate query remains ordinary prose. Selection replaces only that query and
preserves surrounding text, native Undo and the captured conversation. A single
discoverable actions entry offers the same routes without requiring memorized
syntax. Interaction > Chat chooses whether Return during work adds to the current turn
or queues the next one. The send button follows the same preference and exposes
its effective action. Idle Return sends normally; newline and IME behavior remain
unchanged. The default is immediate input. Queue is not an Add-menu action.
Queued input appears in a native Liquid Glass surface behind the input surface.
Each queued message has one visible summary row and a direct Steer action; idle
input exposes Send Next. Multiple messages expand into rows in a bounded scrolling
region. Only empty surface margins overlap; text, focus rings and controls remain
clear of the front input surface. Selecting a summary opens a native popover showing its
full text once, with retained Note snapshots, file representation labels, quotations
and requested Skills available in its material disclosure. Add to Current Turn explicitly sends the selected item as
additional input to its bound running turn; Send Next retains queue order while
idle. Inspection cannot dispatch or reorder input. Edit Message opens a native editor
for the queued text without replacing the composer draft or its materials.
Saving preserves queue identity, position and attached context. If already sent,
the edit is not applied and remains available to copy. The composer shows only
its text and necessary delivery controls. Chat Actions groups materials, Skills,
web search, model/reasoning and permissions; these do not occupy permanent
rows or separate icons. Context and Usage additionally has one compact named
icon near the composer, showing only last-reported occupancy when available.
A running turn with a reported plan shows its current step and completed-step
count in one compact disclosure near the input; full steps open on demand.
This summary never invents a plan, progress or token measurement. Native menus and named pickers expose selected values;
short labels and direct
actions lead, with explanations only for unavailable or consequential states.
An explicit web-search mode is distinguishable from Note Search.

Conversation options expose Rename, Find, Branch, Context and Diagnostics.
Context and Usage also remains reachable through Chat Actions, including when
runtime usage is unavailable. It never shows a guessed percentage. Context
separates last-reported occupancy from cumulative consumption,
with bounded native progress, token details and a state-valid Compact Context action.
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
Composing shows Chat Actions and one circular primary action: during work,
Stop when delivery is unavailable, otherwise Send Now or Queue for Next Turn.
Compaction shows Stop; interruption shows disabled Stopping. Chat Actions retains
Stop with Command-Period. Command-Return means delivery only. Symbols retain position and accessible names.

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
remains available through the composer's primary action or Chat Actions menu. Plans and each tool call retain native
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
