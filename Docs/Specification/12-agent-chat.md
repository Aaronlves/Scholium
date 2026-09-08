# Specification: In-app Agent Chat

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Section 8.7.

## 8.7 In-app Chat

Chat belongs to one Triptych and may reference several Notes across its vaults. Sending
the first message starts a conversation without an academic task or Record. Library
navigation and current Note changes do not change the active conversation or silently
share another document. Conversation history, drafts, attachments and uncertain delivery
survive reopening in machine-local storage. Titles derive from the first message; saving
and reopening need no technical session-management decision. Archiving hides an idle
conversation from the active list while preserving its messages, draft and modification
links. Restoring makes it writable again; archived conversations cannot send or become
active tool runs. Runtime history remains runtime-owned; a retained public projection is
not a second writable Note or researcher endorsement.

The researcher selects Ask for Approval or Full Access per conversation. Ask
requires confirmation of each Scholium Note mutation and displays runtime
approval requests. Full Access permits autonomous operations in the runtime's
full-access environment and permits scoped MCP mutations without an additional
proposal approval. Both preserve exact source, current revisions, live editors,
readback, conflict and recovery. Full Access does not imply that arbitrary
filesystem edits acquire Agent Change evidence. Raw edits remain external edits.
A permission change applies only while the conversation is idle; it persists
across turns. Runtime tools outside Scholium obey the actual runtime policy,
not a simulated UI permission. Unsupported approval requests cannot run silently.

One active execution at a time owns each conversation's tool admission. In-app MCP calls bind
the connected conversation and exact Triptych to the runtime-confirmed current
turn; a model-supplied other Triptych is rejected. A reusable connection route
is not research permission or continuing execution authority. Missing, stale or
mismatched turn identity cannot acquire admission. Decline or Stop revokes pending approvals and new operation
admission; already admitted source transactions finish or recover through their
existing owner. Successful interruption is distinct from rollback. Uncertain
requests are retained and never automatically resent. Continuing after an
uncertain delivery is an explicit action that does not resend its old message.

The client supports sending, streaming public answers, additional input,
interruption, sign-in, disconnection and conversation reopening. Source excerpts
come from one checked editor source/selection snapshot, retaining Note identity,
source fingerprint and locator. Adding an excerpt prepares input without sending.
Review selections may be handed off only when they map uniquely to exact source
in the displayed revision; rendered text never reconstructs source. Unmappable
selections offer Edit or Source. No-selection and unavailable-editor states
request an explicit selection rather than sharing the whole document. Ask Agent
stages that checked passage in the current conversation and focuses its ordinary
composer without sending, replacing a draft, or granting a Note modification.
The selection surface also offers Clarify Concepts, Examine Argument and Check
Evidence. Each prepares an editable question alongside the checked passage in
ordinary Chat; existing draft text is retained. These are inquiry starters, not
academic task types, fixed methods, research scores or completion records.
Clarification distinguishes a passage's usage and ambiguities from an Agent's
interpretation. Argument examination distinguishes stated reasons, supplied
premises and objections without forcing nonargumentative prose into a proof.
Evidence checking distinguishes inspected sources, analysis Notes and inference;
unavailable primary material leaves attribution and support explicitly unverified.
The prepared question requests discussion without Note changes. Nothing is sent
until the researcher reviews and sends the draft; adopting a result is separate.
Opening a retained passage reveals its exact range only while the current source
revision and range match; an older snapshot keeps its original attribution.
For an exact Chat passage, Review restores the native text selection only when
its rendered block maps exactly to that source range. Otherwise an editable Note
opens Source at the verified range; a read-only Note retains the supplied-text
preview and explicitly reports that Review cannot select it. Ordinary line-only
references retain their current-mode arrival behavior. A Note reference opens its
verified identity in the same Triptych; missing identities remain explicit and never fall back to
an arbitrary path. Show in Library is a separate navigation action.
Pending passage navigation belongs to its destination Note and one explicit
activation. Switching documents invalidates it; a replaced page or earlier
activation cannot consume a newer request, even at the same range.
The source revision is checked again when the location is applied. A revision
change while loading leaves the Note open without selecting obsolete coordinates;
editor coordinate conversion preserves exact original newline and Unicode offsets.

One-click connection discovers an installed executable and the Scholium CLI, prepares
its MCP configuration, and requests provider sign-in if needed. Advanced paths and
connection management live in Settings. These machine paths, credentials and runtime
data stay outside portable `.scholium`; existing Triptych control settings keep their
current portable owner. A separate configuration directory is the default; choosing an
existing runtime directory explicitly inherits its configuration and tools. Scholium
does not copy credentials, change global host settings, or promise arbitrary
desktop-thread adoption. Cloud inference and account usage remain subject to the
provider; local execution does not imply offline inference. Normal Note work remains
available without a runtime or sign-in.

After an explicit successful connection, Scholium remembers that connection intent
locally and restores the connection when reopening the Triptych. Login remains
with the selected runtime configuration. Ordinary turns, browsing and window
changes reuse the connection without asking the researcher to reconnect.
Explicit Disconnect disables automatic connection until the researcher connects
again; application shutdown does not erase that preference or the provider login.
An unexpected transport loss revokes current execution admission and attempts a
bounded automatic reconnection without modal interruption. Only an unresolved
connection failure or required authentication presents an actionable repair.
Recovered transport and public history never resend user input, resume Agent
work, repeat a mutation, answer an approval or silently settle uncertain delivery.

Chat adds no automatic Settle, durable philosophical verdict, argument graph or
second proposal lifecycle. Research-context handoff is provider-neutral; adding
runtime adapters does not change its Note-snapshot contract.

### 8.7.1 Conversation continuity

Viewing a conversation is independent of running it. Researchers can browse,
search, create and draft in other conversations while execution continues.
Independent conversations may run concurrently; replies, approvals, input,
Stop and Agent Changes always belong to their exact conversation and execution.
Changing the visible conversation never transfers an operation or its permission.
Concurrency does not bypass per-Note revision and source-operation coordination.
Connection setup, sign-in and account observations are shared by the Triptych;
each conversation owns its execution, pending input, approvals, errors and
cancellation. Disconnect closes the shared connection and revokes admission for
all of its conversations. Stop targets only the explicitly addressed conversation.
Additional input targets the execution active when the researcher sends it.
Material preparation or target verification must not silently retarget that input
to a later execution or start a new one after the original finishes. If the target
ends before local admission, the draft and materials remain available for an
explicit new request. After dispatch, only a matching runtime acknowledgement or
correlated public history confirms delivery; an unconfirmed result is retained
without automatic retry.
Late responses from an earlier connection or execution cannot reactivate admission.
Runtime interaction identities must be unambiguous across the shared connection.
A reused pending request identity closes that connection without forwarding a
decision whose recipient cannot be established; public history is preserved.
Waiting for input in one authenticated connection cannot block unrelated
conversation tool requests. Transport concurrency is bounded; source transactions
remain serialized by their existing Note/workspace owner. Shutdown stops new
admission, cancels pending requests, and reports whether admitted work has drained
within its deadline without claiming cancellation rolled back a confirmed write.

Conversation search covers retained public messages and titles within the
current Triptych, including an explicit archived scope. Find in Conversation
locates matching messages without editing or resending them. Both use literal,
case-insensitive matching over retained public text, including disclosed plans,
activities and supplied material text; they do not search private runtime state
or fetch additional source material. A result exposes the matching passage.
Find navigates matching messages in chronological order, reveals a match inside
collapsed activity, and preserves the draft. Renaming changes
the title only. A branch copies runtime history through a selected ended
turn, retains the source conversation, and starts with no pending approvals or
in-flight input. Branching requires the source conversation to be idle and its
delivery reconciled; other conversations remain usable. The runtime confirms
the exact boundary before the new conversation becomes usable. The branch
retains permission, model, reasoning and search choices, plus an explicit link
to its source conversation and turn. It copies neither the unsent draft nor
unsubmitted materials and does not start inference or continue a goal by itself.
Stopping a pending branch request preserves the source; an unconfirmed result
is not silently retried. Historical Agent Changes remain evidence of their original
operation, not new writes by the branch. Editing and retrying a past request
uses a branch; it never silently rewrites the observed execution history.

Edit in New Branch applies to the opening researcher request of an ended turn.
The runtime forks immediately before that turn, including an empty history when
editing the first request. The selected request's exact text, material snapshots
and requested methods populate the new draft; its answer and later turns are
excluded. The source's current unsent draft remains untouched. Earlier turns
remain history, and the origin records that its boundary excludes the edited
turn. Additional input within a running turn has no independent runtime branch
boundary and cannot use this action. Nothing is sent until the researcher sends
the new draft; unavailable methods or retained materials use ordinary repair
and send checks. Failure, cancellation and uncertain fork results preserve the
source and never fall back to copying the rejected answer into a new thread.

Runtime identity and public history remain distinct. Missing, unreadable or
unavailable runtime history preserves the visible conversation and draft.
Paginated history is loaded through the runtime's supported continuation; a
partial result is never presented as complete. Delivery uncertainty requires
reconciliation and explicit continuation, never automatic resend.

### 8.7.2 Models, context and account use

Each conversation retains its selected model, reasoning effort and web-search
mode. Runtime Default remains an explicit choice. Choices come from runtime
capabilities rather than a hardcoded model list. Unavailable saved choices are
visible and block dependent sending until resolved; they never silently select
another model. Settings cannot change an already executing turn.

A saved choice and its application to a loaded runtime are distinct. If a
thread-static setting requires runtime renewal, retain the choice as pending
until all work owned by that runtime is confirmed idle, including delegated
work and background commands. Pending renewal prevents new turn admission;
existing turns retain Stop, additional input and their current settings.
Renewal preserves conversation identities, history, drafts, materials and the
existing sign-in. It neither changes shared host configuration nor starts a new
conversation. Show application progress without treating planned renewal as a
connection failure. Cancellation or failure preserves input and never resends
it; explicit disconnect cancels pending renewal. A setting is not presented as
effective merely because a resume request accepted its configuration fields.
Connection renewal reapplies associated method folders before reopening new-turn
admission. Initialization is distinct from changing configuration during work;
the renewal guard cannot prevent restoration of the new connection's own roots.
Failed root application retains its scoped error and explicit recovery route.

Context usage and account quota are separate runtime observations. Context
shows the latest reported usage and capacity; account limits show their actual
window and reset when available. Missing values are unavailable, never zero.
These values do not estimate research completeness or philosophical quality.

Automatic compaction remains runtime-owned. Chat shows its actual start,
completion or failure and offers an explicit Compact Context action when the
runtime supports it and the conversation is idle. Compression does not alter
public chat history, Notes or permission. A pending compaction blocks new turn
admission in that conversation and participates in Stop and disconnect handling.
Researchers can reintroduce exact source material after compaction; a compacted
summary never gains source authority or becomes a second research memory.

### 8.7.3 Skills and connected tools

Settings provides runtime-backed discovery, inspection, local association or
installation, enable/disable and removal of researcher-owned method Skills.
Chat provides explicit Skill selection for a message. A selected Skill is shown
separately from a runtime-confirmed invocation. Discovery errors, unavailable
dependencies and disabled Skills are visible. The protected Core Protocol
retains §8.1 precedence and is not a removable method choice.

Method choices belong to the unsent message and remain visible in the retained
message after sending. Sending resolves each exact selected method against the
current runtime inventory; missing or disabled choices preserve the draft and
block sending rather than silently dropping a requested method. Enable/disable
changes apply to the connected runtime configuration, require all of that
connection's conversations to be idle, and show the effective runtime result.
An inventory or connection failure is distinct from an empty method/tool list.

The runtime is the single owner of installed Skills and tool configuration;
Scholium neither mirrors an editable inventory nor implements a second package
manager. Removing an association preserves researcher-authored Skill files.
Installation into, or mutation of, a selected shared runtime configuration
states that scope before confirmation. No action silently changes another host.

Local folder association is a Scholium launch preference scoped to the selected
runtime configuration folder. It supplies additional discovery roots to that
app-server process and is reapplied when connecting. The preference records
only the researcher's chosen folders, not a second installed-method inventory.
Adding or removing a folder requires the connection's conversations to be idle;
removal never deletes Skill files. Missing folders and unconfirmed application
remain visible with Refresh and removal routes. A failed application is retried
only by an explicit refresh or connection, never by a background inventory event.

Connected tools expose identity, connection, authentication, availability and
enabled state with runtime-supported setup, sign-in, refresh and removal routes.
Credentials stay with the provider/runtime. Tool availability does not authorize
its use on private data or change the current research scope. Missing protocol
support remains an explicit unavailable capability, not an inert control.

Tool configuration supports remote endpoints and local server programs, with
native add/edit, enable/disable and remove actions. Changes target the runtime's
selected writable user configuration, preserve fields not edited in the form,
and use its current version to reject intervening changes. A stale form retains
its draft and requires an explicit reload; it never overwrites newer settings.
Connections controlled by another configuration layer remain inspectable, with
their ownership visible. Scholium's own bridge is managed by the application.
Configuration changes wait for active conversation executions to finish and do
not interrupt admitted research operations. Saving configuration and connecting
successfully remain distinct results. Removing a connection does not revoke
provider credentials or delete its local program.
Changing a remote origin or local program requires an explicit choice before
reusing configured authentication headers or process environment values with
the new destination. Credential values are not displayed as configuration prose.
Advanced access settings may name a bearer-token environment variable for a
remote server or selected inherited environment variables for a local program.
The form edits names only; it neither reads their values nor creates credentials.
Empty fields remove those explicit references without changing other access
settings. The runtime reports missing variables or failed authentication; a
saved name is not evidence of availability. Existing unsupported access fields
remain unchanged and cannot be silently replaced by a simpler form.

Tool sign-in is an explicit researcher action for an observed tool connection.
The runtime supplies and owns the authorization flow and credentials. Opening
the authorization page is not a successful login; only a matching runtime
completion confirms authentication, independently of connection readiness.
Sign-in remains available while a conversation waits for a tool; it does not
transfer execution ownership, resend a request or change research authorization.
Authorization URLs remain ephemeral, accept secure web destinations only, and
are never recorded in conversations or portable research data. A late response
from a disconnected runtime cannot open a page or update the new connection.

Web search is a first-class chat capability with explicit Off, Cached and Live
choices where supported. Its availability is separate from general filesystem
or network permission. Public events expose queries, opened URLs and outcomes
when supplied. Search hits and counts remain discovery leads; claiming that an
article was read requires an actual reading result. Missing access, excerpts,
paywalls and failed retrieval remain explicit evidential limits.

### 8.7.4 Research materials and references

Completed public replies support quoting a selected passage into the ordinary
composer as a compact, removable quote card. It retains its conversation and reply locator;
rendered reply text is Agent content, never an exact research-source capture.
The researcher can inspect or remove the quote and edit the draft before sending. A named action and
keyboard route accompany native selection; stale or departed replies cannot
redirect a quote into another conversation. Existing draft text is preserved.
Selection can cross paragraphs, lists and table cells within one completed reply.
Native Copy and quote handoff use the same rendered text and reading order;
formatting remains a projection, with no reconstruction of writable source.

The composer accepts explicitly selected Notes and checked editor passages,
local documents and supported images. File selection, paste and drop are
equivalent routes where applicable; a named picker remains available. Navigation
alone never attaches or transmits a Note. Materials can be inspected and removed
before sending without replacing the draft.
Dragging a Library Note into the composer copies context through the same
identity-checked capture as Choose Note; it never moves the file. Invalid or
foreign Note identities are rejected without falling back to a local file.
When Library is visible, its Notes can also be dropped on the toolbar's Chat
segment. Only an accepted drop opens Chat and prepares the copied context;
hover and cancellation read nothing. The drop binds to that window's Triptych
and destination conversation. Library Notes also expose Add to Chat through their
context menu and named accessibility action; the existing picker remains available.
All routes prepare inspectable context in the destination draft, without sending
a message or navigating away from the current document.
Chat source opening reuses an existing document tab or opens a new tab, preserving
the previous document and Chat reading position. Triptych roles and workspace
ownership remain unchanged. Material snapshots retain their preview; local files
use Quick Look rather than creating persistent document tabs.

The Note picker searches the current Triptych's known Note identities by title
and path. Selection alone reads or transmits nothing; Add captures the whole
Note's exact source. If a retained editor has unsaved changes, capture that
editor's checked source and label it as an editor snapshot. Otherwise capture
the current saved source through the document owner. Failure or composition
never substitutes older saved text for the requested editor content. The
material retains its vault role and distinguishes a passage from a whole Note.
Picking and asynchronous capture bind to the original conversation and Triptych;
switching either cannot redirect the result. Adding prepares input only.

Each material identifies its origin, kind, revision and exact supplied extent.
Unsaved editor selections remain labelled snapshots. Local files are staged in
machine-local chat storage with source identity and fingerprint; external file
change or disappearance cannot silently substitute bytes at send time. Runtime
input capabilities determine which kinds can be sent. Unsupported or failed
extraction preserves the material and draft with a repair route.

An explicit paste or image drop in the message editor can attach image material. File
references take precedence over their clipboard icon representations. Image
representations become material rather than embedded editor objects; ordinary
text and rich-text pastes retain the native text editor path. Marked text remains
owned by the input method. The clipboard is not polled or read in the background.
Capture binds to the conversation receiving the paste or drop, and replacement clipboard
contents cannot change an already captured image.

Captured images distinguish clipboard and drag-and-drop origin without inventing
a file path or claiming the originating application is known. Drag entry checks
offered types only; bytes are captured when the drop is accepted. Material drops
require copy semantics and preserve the source, text draft, selection and text
Undo history. Ordinary text drops retain the native editor route;
disabled input or marked-text composition cannot admit a material drop.
File references outrank image representations of the same dragged item.
Supported encoded images retain their supplied bytes; native bitmap formats
that require conversion use a labelled PNG representation and retain fingerprints
for the captured encoding and prepared image. Unsupported or failed conversion
remains a visible unsent material. Pasting or dropping never sends automatically or changes
the text draft, selection or text Undo history when it attaches image material.

Local text and Markdown files supply exact decoded UTF-8 text. A PDF supplies
page-indexed extracted text, labelled as that representation rather than the
original page images. Pages without extractable text remain identified in both
the preview and the delivered material; a PDF with no usable text cannot send
through that route. Locked, unreadable, oversized and unsupported files remain
inspectable failures with removal and explicit replacement routes. Supported
single-image files are supplied through the runtime's image input only when the
selected model reports image support; unknown support is not assumed.

For a retained PDF, the researcher can explicitly choose physical page numbers
and use those pages as images. This works for scanned pages without introducing
OCR claims. The replacement material retains the original PDF fingerprint,
selected page numbers and a fingerprint for each rendered page. The original
PDF copy remains available for system preview. Page images are a separately
labelled representation; they never masquerade as extracted text or complete
coverage of unselected pages. Rendering uses the retained PDF, never a fresh read
of the external path. Invalid ranges, locked files, cancellation before attachment
and rendering failure preserve the existing draft material. Once a prepared
replacement is attached, cancellation does not undo that completed attachment.
Rendering limits are stated before
confirmation; no range is silently shortened. Choosing page images prepares a
replacement material only and does not send the conversation.

Preparation retains the chosen conversation, supports cancellation and never
sends automatically. Before delivery, local snapshots are checked against their
retained fingerprints; missing or changed staged bytes preserve the draft and
require repair, rather than creating uncertain delivery for an unsent request.
Preview opens the retained local snapshot through the system's file preview;
it never substitutes the current external file. Removing an unsent material
does not delete the original file or invalidate material retained by a message
or another conversation branch.

For papers, retain bibliographic identity when supplied, page or source locator,
and whether the Agent received full source, selected pages, extracted text or an
image. Page images and extracted text are different representations. OCR and
extraction failure cannot be hidden by a fabricated reading claim. Zotero
remains authoritative for its library and PDFs; Chat does not embed a second
PDF reader or import bibliographic claims without their source.

Answer references distinguish external primary material, Analyses, Topics,
Works and the Agent's own reconstruction. Source links open the exact known
identity and location; a changed revision is disclosed instead of presenting an
old line as a verified current passage. Open Source and Add to Chat remain
different actions. A source list records provenance, not support scores.

Reply Sources distinguishes explicit citations from material supplied in that
reply's confirmed turn. Reading evidence comes only from successful scoped App
read responses or identified public runtime events before that reply. Note reads
retain exact revision, returned line range, continuation state and a bounded exact
excerpt. Disjoint ranges and different revisions never become one complete read;
coverage of a cited location must be established separately. Missing observations
stay unknown and are never reconstructed from prose or file-operation counts.
Runtime webpage open/find events describe reported access, not verified full-text
reading or philosophical support. Unsupported result formats remain unknown.
Supplied PDF text, page images and ordinary images retain their existing snapshot,
page coverage and preview owner; supplying a material is not proof it was used.
Sources neither fetches content nor creates citations on opening, and never executes
an arbitrary locator. Public observations remain nonauthorizing conversation data.


Note passage links retain the supplied exact-source fingerprint and, when known,
vault identity alongside the Note and line. Opening an attachment or an answer
link uses the same revision check in the window's document transition. A matching
current editor snapshot can establish the location without saving it; composition,
unavailable editor state and unversioned links cannot. Opening a reference to the
current Note never saves or reconstructs its editor. A changed or unverifiable
location opens the exact Note without selecting a passage and states that limit.
Missing or ambiguous Note identities never substitute another Note. Invalid link
fields are rejected; a valid fingerprint does not establish that the linked
passage supports the Agent's claim.

### 8.7.5 Public execution, questions and approvals

Runtime MCP tool-call approval requests expose the issuing server, supplied
request and exact conversation/turn with Allow Once and Decline. Only a correlated
tool-approval request can use this route; arbitrary forms, web destinations and
persistent permission choices cannot acquire a grant through it. Allowing the
runtime call does not replace Scholium's current-source Note modification
approval. Unsupported requests state their unsupported status instead of being
presented as a researcher-made decision.

Chat presents public plans, plan changes, tool activities and outcomes supplied
by the runtime. It does not reveal private reasoning or manufacture steps,
progress percentages, remaining time or philosophical acceptance. A completed
software step means only the named operation ended successfully. Runtime-labelled
public progress commentary is distinct from the final answer and is retained with
its exact turn and item identity. The process view groups the commentary, plans
and individually inspectable tool calls for that turn; completion collapses the
process, not the final answer. Missing phase metadata never justifies hiding an
Agent message as presumed reasoning. The client does not expose raw reasoning
items or reinterpret ordinary answer text as a private reasoning trace.
Default progress names the action and outcome in ordinary research language.
Each tool's commands, identifiers, paths, parameters and raw failure output remain
in collapsed details, including after failure. A visible status still identifies
failure or an uncertain outcome; required questions, permission scope and recovery
actions cannot be hidden as technical detail. Native activity indicators reflect
actual running state and use a static alternative under Reduce Motion.
Live delivery, restored history and inspected Agent history interpret the same
public item consistently: exact text, phase, turn identity and tool outcome must
agree. Missing or unknown phase remains unclassified. Invalid attributed history
cannot partially replace retained messages or confirm delivery; keep it unchanged
and report the unavailable history. Private reasoning never enters public history.
Turn acknowledgements may confirm lifecycle identity without containing message
history. Such metadata never claims that missing items were read or restored.

A reply or turn ending does not end a background tool operation. Each operation
retains its own runtime item identity and reported outcome, including updates
after the final reply or during a later turn. History restoration follows the
same rule. Losing the connection makes an unconfirmed running runtime operation
uncertain, not confirmed interrupted. Pending interactions still expire with
their owning turn; no historical activity can regain approval authority.
An expired approval cannot leave its tool displayed as waiting for a decision;
without a confirmed tool outcome, retain uncertainty.

Research questions and operation approvals are distinct interactions. Questions
show the actual prompt, offered choices and free text, retaining answers until
the runtime acknowledges them. An unanswered question remains inspectable when
viewing another conversation. Unsupported form or URL interactions fail visibly;
an external authorization route opens only the exact validated provider request.
Question options retain their labels and descriptions, without a preselected
answer. A custom response is available when the request permits it, or when
there are no options. Secret input uses a secure field and never enters retained
conversation prose or technical details. Invalid or partially understood question
sets are rejected as a whole; they never turn into an operation-approval prompt.
Reply submits only the requested answers; Skip supplies no answers and grants no
operation permission. Pending question text is separate from the chat draft.
An input request correlated with a runtime tool call retains that tool's identity
and inspectable arguments. It is presented as tool input, since an offered answer
may authorize the referenced action; it is not labelled as a philosophical
research question. Its alternative to replying is Stop Turn rather than an
assumed empty or default answer. Tool arguments remain transient request details;
retained input records contain the identity, questions and nonsecret responses.

Note update approval displays the target and exact proposed changes against the
expected revision; create shows the proposed Note, and Trash names the item and
system-Trash consequence. Currentness is rechecked at execution. A stale proposal
requires a new read and decision, not reuse of approval for different content.
Update comparison is a read-only preparation through the existing Application
source-transformation owner. It validates the expected saved revision and uses
the same body/source replacement semantics as execution; it does not save an
editor, create an Agent Change, or reserve a write. Missing, stale or unrenderable
source prevents approval rather than offering an unchecked replacement. The
comparison labels its ending content as proposed. Opening or dismissing it grants
nothing; its decision remains bound to the exact originating request even if
another conversation becomes visible. A stopped or resolved request cannot be
approved from an old comparison.
Runtime command, file and permission approvals show the operation, scope and
consequence, with technical detail available on demand. Grant and decline are
scoped to the supplied operation; dismissal grants nothing.
Command text and terminal input are labelled distinctly. Working directory,
execution environment, network destination and requested filesystem rules stay
visible when supplied; best-effort command classifications never replace the
actual command. File proposals retain their reported paths, effects and diffs,
and remain runtime reports rather than confirmed Scholium Note changes.
Managed-network approval is presented as access to the supplied destination and
protocol; its opaque command metadata stays in technical details. It may resolve
grouped requests to that destination and is not labelled as one shell command.
One-time, current-turn and session decisions have distinct labels. Session access
requires its own explicit action and is never substituted for Allow Once.
Permission rules are shown in full, including patterns, special roots and deny
entries, without claiming an inferred effective permission. Unknown scope or
unsupported decisions cannot silently acquire a broader grant. Persistent policy
amendments are not implied by these actions. Decisions remain pending until the
runtime resolves the exact request; a response write alone is not confirmation,
and an uncertain response is never automatically repeated.

Confirmed Note changes reuse Agent Changes comparison and eligible Undo under
§8.4. Full Access preserves its existing no-additional-approval policy. Runtime
filesystem reports never masquerade as confirmed Scholium change receipts.

### 8.7.6 Concurrent, delegated and background work

The runtime owns Agent execution, child Agents and scheduled execution. Chat
observes their public state and exposes supported open, message, stop and
continuation actions tied to exact identities. Delegated work retains its
parent relation and evidence provenance. No child can enlarge the parent's
Triptych or write scope merely by receiving a delegated request.

Public delegation reports retain the issuing runtime identity, exact target
identities, requested work and each supplied result/state. A completed spawn,
message or wait operation does not by itself mean the target Agent completed
its research. Missing states remain unavailable. These are labelled observations
at that point in the conversation; reopening cannot turn them into live status.
Only an explicit spawn relation or verified runtime parent metadata establishes
parentage; messages between Agents do not. A reported result remains attributed
Agent content, never a source document or confirmed Note modification.
Inspecting a report neither starts nor resumes its targets and grants no tool
admission. Unverified or unsupported child control remains unavailable; arbitrary
runtime identities cannot be adopted into the Triptych through a report.

Opening a reported Agent verifies its exact runtime identity and follows its
runtime-reported parent chain to the originating Scholium conversation. Missing,
cyclic or unrelated ancestry is unavailable, without substituting another Agent.
Forked reports retain their original parent scope. The detail shows the supplied
name/role, current observed status and public history; it excludes private
reasoning and makes paginated or unavailable history explicit. Reading and
refreshing do not resume or subscribe a dormant execution. Closing the detail
cancels its inspection tasks without stopping the Agent.

Reports inside an Agent's public history offer the same exact-target opening
route. Each destination verifies ancestry against the original local
conversation, not against whichever Agent is currently visible. A reported
interaction does not establish a new parent relation. Returning preserves the
previous inspection and its separate adjustment draft; revisiting an Agent
already in the navigation path returns to that inspection and refreshes its
observation. Opening the originating parent returns to its existing conversation.
Unavailable destinations retain Back and the original conversation route.
Popping or closing an inspection cancels its reads without cancelling admitted
parent input or stopping any Agent. Connection replacement cannot make an old
report a live control surface.

Researcher adjustments can be addressed through the originating parent Agent.
The child detail offers a separately labelled Ask Parent message, retaining that
child's exact identity and the researcher's text. This is a request for the
parent to coordinate the named child, not proof that the child received or acted
on it. Direct child input is a separate capability and is offered only when the
runtime explicitly permits it; no action forces another Agent mode to bypass
runtime ownership.

Each child's adjustment draft is retained with the originating local conversation.
It does not replace the parent's ordinary draft or include its unsubmitted
materials or method choices. Sending revalidates the child's parent chain and
uses the parent's ordinary current-turn input or new-turn admission, permission,
delivery confirmation and uncertainty handling. Archived or unavailable parents
cannot receive it; closed inspections do not erase the draft or cancel an already
admitted parent request. A confirmed parent receipt is labelled as such, without
claiming delivery to the child. Unknown delivery is never automatically resent.

Public adjustment messages retain a distinct target reference alongside their
exact user text. Search and branching retain that reference as provenance. Editing
such a request in a new branch retains its target in the draft; an Agent belonging
to the original conversation cannot be silently retargeted to the branch. Sending
requires a target verified for the receiving parent. The researcher can remove
the target to send ordinary text, or return to its original conversation. Neither
branching nor removing a target starts Agent work by itself.

Stop Agent requests interruption of that exact, currently observed child turn.
It requires a verified parent relationship on the current connection and uses
the runtime's exact-turn precondition; it does not stop the parent or siblings.
Acknowledging the request is not proof of interruption: the inspector briefly
rechecks the exact turn and retains an unconfirmed state with Refresh when its
end is not established. A disconnected snapshot is explicitly a prior
observation. Interruption does not grant tool permission,
undo source transactions or claim the parent admission was revoked. Parent Stop
and disconnect retain their existing admission boundary for delegated Note work.

Navigating away does not stop work. Finishing, failure or required input can
notify the researcher without stealing document focus. Background notification
text contains no research titles, excerpts or paths; denial of system
notifications leaves all status and recovery available in the conversation.

System Chat notifications are eligible only while Scholium is inactive and a
live execution newly completes, fails or requests researcher input. Ordinary
streaming, history hydration and restored records never notify. Researcher Stop
and disconnect do not masquerade as a failed task. Requests answered or cleared
before delivery, and superseded runs, no longer qualify. Bursts within one
conversation coalesce to its latest qualifying event; independent conversations
retain independent destinations. Notification delivery failure cannot change
execution or research results.

Clicking a Chat notification opens the exact retained conversation in its
Triptych, including archived history, without changing the current Note or
restoring execution authority. It neither connects, sends, resumes, answers nor
grants permission. A missing conversation is reported without selecting another
as a substitute. Notification payloads retain only opaque Triptych/conversation
identities and event category; source text, runtime prompts and credentials never
enter the system notification store. The shared macOS notification policy in
§18.2 owns authorization and foreground suppression.

Scheduled work requires an explicit researcher instruction naming scope,
timing and permission. Its runtime-owned schedule can be inspected, paused and
removed through supported APIs; Chat creates no competing scheduler. Off-app
execution must disclose its actual host and availability. If the runtime cannot
deliver that lifecycle, Chat presents the capability as unavailable. Closing or
disconnecting cannot imply that terminated local work will keep running.

### 8.7.7 Presentation and acceptance boundary

§18.2 owns placement and interaction presentation; §19 owns global visual
identity and native motion; §20 owns accessibility. Inputs, source provenance,
execution, research prose and operation evidence remain distinct in every mode.
Core Note work remains usable without a connected or authenticated Agent.

Acceptance includes one real signed-in runtime journey through discovery,
source reading, discussion, scoped modification, comparison, eligible Undo,
interruption and reconnect in a disposable Triptych. Deterministic protocol
fixtures cover failure, concurrency, scope isolation and uncertain outcomes.
Neither fixture success nor a static preview establishes real inference,
keyboard/focus behavior, installed-IME or human accessibility acceptance.
