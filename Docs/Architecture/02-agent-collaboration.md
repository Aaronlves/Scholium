# Architecture: Agent Collaboration

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Local MCP,
mutation evidence, and Settings ownership.

## Delivery path

`scholium mcp serve` is a stdio adapter. `ScholiumMCPServer` owns JSON-RPC
framing, initialization, fixed tool discovery, closed input/output schemas,
annotations, and MCP error envelopes. `MCPCommandHandler` owns stdin/stdout
only.

The CLI calls `ScholiumAppBridge`, which discovers one current-user App
endpoint and authenticates the live process. It does not construct a workspace
runtime, start the App, or access Triptych files. `ScholiumAppBridgeRequestRouter`
validates the bridge request and delegates one tool call to
`MCPAppBridgeRequestRouter`.

The App router operates only on currently open `WindowSession` capabilities.
Workspace selection is automatic only for exactly one open Triptych. Multiple
open Triptychs require the caller's exact stable Triptych identity.

## Fixed tool surface

`ScholiumMCPToolName` defines eighteen external research tools and four
token-scoped in-app capability controls, all with closed schemas. The external
surface includes:

- workspace status;
- current Library inventory browsing, Note Search and exact Note reads;
- related attachment listing and bounded text/page/image reads;
- exact-source Note/passage display in an explicitly scoped live window;
- authored link occurrence listing; and
- exact Note create, update, move, and system-Trash mutations; and
- Agent Change listing, comparison reads and fingerprint-guarded Undo; and
- read-only, revision-bound move impact previews; and
- revision-checked managed Metadata patches and document-attachment relationships.

The external MCP server exposes no Resources, Prompts, Tasks, model operation,
Handoff, Research Action, acceptance, Review, Settle, or research-result
endpoint. Tool availability is not write permission.
The in-app Chat server appends the four capability controls only when it carries
the addressed conversation token; those controls remain runtime-owned and do
not expand the external research surface.

Browse projects the current `WorkspaceVaultSnapshot` folders and Note identities
without a second index. `WorkspaceLibraryVisibility` owns the shared Library/MCP
attachment-storage exclusion. A sorted exact listing plus Triptych/role/directory
scope produces the continuation fingerprint; changed listings reject old pages.
Read slices retain their complete-source UTF-8 offsets for exact update ranges.
Optional Note context uses `AgentNoteContextOperations` to read existing validated
portable Metadata, the selected Analysis binding and `AgentAttachmentOperations`
relationships. It rechecks source identity/revision and record snapshots before
returning. The App router projects fields as plain typed JSON, separate from
source, and shares the attachment listing serializer and continuation fingerprint.
There is no context store, secondary catalog or Zotero network read.
`AgentNoteMoveOperations` projects the existing workspace move plan and shares
`TriptychMoveCoordinator.prepareMove` validation with the actual writer. Its
fingerprint binds all effect identities, paths, source revisions and blocked
link locators, excluding disposable graph counters. `IncomingLinkRewriteBlock`
carries its owning source fingerprint; presentation does not guess that version.
The preview retains no execution authority or durable plan store. Execution
recomputes its fingerprint inside `coordinatedMoveDocument`'s source lease.
`AgentMoveEvidence` extends the existing Agent Change with primary move effects
and exact linked-source preimages; coordinator readback confirms the full set.
`AgentNoteMoveRecovery` verifies identity, revisions, vacant original path and
current/future link resolution before feeding exact preimages to that same
coordinator. It never substitutes canonical reverse-link spelling for Undo.
The original receipt transitions only after complete inverse readback. Existing
per-file transaction Recovery is bounded into the MCP failure envelope.

`AgentAttachmentOperations` joins current Note identity/revision to document
relationships or registered Markdown image locations. `VaultAttachmentStore`
reads bounded descriptor-relative bytes; external references first acquire the
existing `IndexedAttachmentAccessStore` exact-path bookmark lease. Relationship
and Note revision are rechecked before returning. Core's shared
`AgentAttachmentContentReader` uses PDFKit/ImageIO on that immutable snapshot: one page/text slice or bounded
PNG derivative, with no material archive. MCP emits native image content beside
structured coverage. Chat records attachment reads separately from Note source
observations, displaying selected-page and empty-extraction evidence.

`CodexZoteroReadReport` projects only identified completed runtime MCP results
whose arguments, locator, representation, counts and fingerprints agree.
`ZoteroReadReport` remains a nonauthorizing public report in the existing
conversation activity, decoded identically for live and restored history.
Sources matches its exact library/attachment/page/annotation before the reply
in the same turn, shows server/tool and separate bounded text/comment excerpts,
and never merges reports into verified whole-source coverage. It owns no new
configuration trust flag, source archive or observation store.

`AgentNoteDisplayTarget` validates exact complete-source ranges before any UI
request. `WorkspaceStore` registers weak live-window presentation closures;
`WorkspaceWindowCoordinator` owns the native key-window/sheet gate. Chat captures
window and registration identities in its existing execution state at admission,
then preserves transport context only for the checked display delivery. Hidden,
switched or reopened windows cannot inherit that request. External calls require
a current explicit window identity from workspace status. `WindowModel` uses its
existing currency-aware transition queue, editor preparation, tabs and source
location request; every suspension rechecks scope/source and supersession.
Cancellation settles the waiting bridge call even when its queue entry is skipped.
This activates navigation; it is not rendered-selection or focus evidence.

`AgentRecordOperations` prepares Metadata patches and attachment relationship
changes, then acquires the existing source-operation lease and rechecks their
inputs without recursively entering refresh. `commitNoteMetadata` and its shared
field validator remain the ordinary Metadata writer. The attachment planner
reads only registered, scoped originals, retaining bounded immutable bytes;
`VaultAttachmentStore.copyDocumentSnapshot` shares the existing no-replacement
copy path. `TriptychControlStore.replaceDocumentAttachment` uses its coordinated
exact-file swap. Removing a relationship never deletes its file.

`AgentRecordChange` binds serialized record preimages/endings into the existing
Agent Change store with distinct operation kinds. Preview, current-ending review
and Undo use those records rather than Note source. `AgentRecordRecovery` restores
through the existing portable owners; no secondary journal or receipt is created.
Receipt confirmation and uncertain outcomes preserve the normal evidence boundary.
Committed record mutations publish through workspace refresh; retained Document
sessions invalidate their attachment-list task on accepted workspace generations.

## Note mutation authority and evidence

Every Note mutation first flushes matching live editors and enters the existing
workspace source-operation gate. Create proves an exact vacant `.md` path and
commits the common managed scaffold plus stable Note identity. Update preserves
either the complete YAML envelope or replaces the explicitly authorized full
source, depending on its mode. Exact multi-range edits use `AgentSourceEdit`
against the complete fingerprint-bound UTF-8 source. The same pure transformation
feeds Chat preview and the existing save/Agent Change transaction, validating
old bytes, scalar boundaries, overlap, complete YAML and size before writing.
`prepareAgentChangeUndo` supplies the same current-source/retained-preimage check
for reverse preview and direct Undo. Undo changes the original evidence state;
post-write evidence failure reports an uncertain outcome rather than retrying.
Change queries read the existing store and page comparisons and move effects;
linked Note queries find their containing move receipt. Chat reuses current-turn
mutation admission and Ask comparisons for moves and Undo, showing each affected
source. Successful activities project the verified moved/edited effects.
Update and Trash compare the caller's exact
fingerprint with current source before commit.

Application repositories retain containment, atomic replacement, native Trash,
readback, identity recovery, and complete derived refresh ownership. The bridge
never bypasses those owners.

The mutation adapter consumes the machine-local `AgentChangeStore` and its
prepared/confirmed/uncertain evidence; persistence and eligible recovery are owned by
[Source Storage and Read
Models](05-source-storage-and-read-models.md#vault-write-and-prewrite-recovery-boundary).

## App presentation and setup

[Source Layout and Presentation](03-source-layout-and-presentation.md#presentation)
owns Agent Changes composition;
[Settings integrations](04-research-guidance.md#agents-chat) owns external-host
setup. Both consume this chapter's bridge and mutation-evidence owners.

## Native Chat client

`CodexAppServer` in Application owns one official stdio process, bounded JSONL
framing, correlation, timeouts, server-request replies and process teardown. It
implements no model/tool loop. Runtime authentication remains in the selected
Codex configuration directory. No credentials or raw stderr are copied to logs.

`WorkspaceStore.chatRegistry` owns one `AgentChatController` per Triptych across
windows. The controller owns the conversation inventory, visible selection, public
messages, drafts and permission. Each conversation has one `AgentChatExecutionState`
value for its turn admission, connection route, input delivery, approvals, errors and task handles.
`AgentChatStorage` atomically
persists versioned machine-local history under `Chat/<triptych-id>`; a corrupt
archive blocks overwriting it. The default Codex home is `Chat/Codex`.

The Chat controller retains successful connection intent per Triptych in its
machine-local preferences; the existing configured paths and runtime login keep
their owners. Loading a previously connected Triptych restores only transport
and public history. Unexpected transport failure invalidates execution admission
before a bounded controller-owned reconnection task; explicit Disconnect and
shutdown cancel that task. Only explicit Disconnect clears saved connection
intent. Recovery never replays input or source operations.

The runtime config registers the existing CLI MCP server with a connection-local
conversation route, retained across ordinary turns. MCP request metadata supplies
the issuing runtime thread and turn; the CLI forwards that context and route in
bridge schema 3. The App registry resolves the conversation route and its current
execution owner requires the exact active runtime thread/turn before admission
and again after an approval wait. Stop and completion revoke turn admission,
not the reusable transport route; connection replacement invalidates every route.
The App binds the Triptych, applies conversation policy,
then calls the same `MCPAppBridgeRequestRouter`. External clients retain their
ordinary route and published public tools. Ask-mode Note writes wait for
one native client approval; runtime approval requests are answered separately
only when they concern a different runtime operation.

`AgentChatSelectionInquiry` carries native action instructions. `WindowChatActions`
captures a checked passage, then revalidates the originating selection before
Chat admission. Ask Agent retains the existing draft-only handoff; other actions
create an ordinary Chat conversation without replacing the visible draft.
`AgentSelectionResult` holds a reference to that conversation, and its native
popover projects the Chat-owned state and final reply. Continue opens the same
conversation; closing presentation neither cancels nor replays an admitted turn.
Polish adoption returns to the same window/document session and uses a typed,
full-source-checked editor range replacement, with ordinary editor Undo.
`WindowChatActions` captures checked editor or exactly mapped Review selection,
or whole-Note source, and
resolves stable Note references through the current catalog. Whole-Note capture
uses the document reader or the retained editor's checked snapshot; unavailable
dirty editors never fall back to disk. `AgentChatNotePicker` owns only query,
selection and its cancellable capture task. The presentation request and capture
retain the target conversation, so a selection change cannot redirect material.
Attachments retain exact text, fingerprint, extent, source kind and known vault
role; previews display the supplied text rather than reconstructing it from
rendered prose.

`AgentChatMaterialStore` owns file copies beneath each Triptych's machine-local
Chat directory. Coordinated bounded reads capture original bytes; strict UTF-8
decoding preserves BOM, PDFKit supplies page-indexed text, and ImageIO validates
supported single images. The immutable `AgentChatLocalMaterial` records the
source location, fingerprint, representation, page coverage and preparation issue.
The Chat controller owns conversation-scoped preparation/cancellation and only
attaches confirmed results to that conversation. File picker, file-URL paste and
drop call the same operation. The native message editor captures pasteboard
materials only on explicit Paste or accepted copy-drop; drag entry inspects
types without loading bytes. Ordinary text drag/paste retains NSTextView ownership.
`AgentChatLocalMaterial.Source` records a file URL or a typed image-capture origin;
clipboard and dropped snapshots have no invented filesystem origin. The shared
material preparation owner stages both capture routes. Supported image encodings retain
their bytes; TIFF conversion retains both captured encoding and normalized PNG
with independent fingerprints. All representations share the existing material
preparation, validation and disposal owner. Explicit replacement/removal releases an unused
copy only after history saving succeeds and no draft/message retains its identity.
Cancelled unpublished copies are discarded without changing original files.

Send validates retained copies before adding a delivery-pending message. Failure
keeps the draft and material; Stop during this preparation cancels without a
runtime turn. Prepared text and page coverage enter text input; supported images
use `localImage` input. The original file is never reread at delivery. Native
material detail views own disclosure and system Quick Look/thumbnail tasks,
without a second document reader, bibliography store or inference loop.
PDF page-image preparation uses the same task and attachment owner. The store
validates the retained PDF, parses an explicit bounded physical-page selection,
and creates a new PDF copy plus fingerprinted PNG derivatives. Failed or cancelled
unpublished derivatives are removed together. Replacements keep their draft
position; retained message/branch references keep their original material files.
Send validates every selected derivative and pairs each image input with its
physical page identity. `AgentChatPDFPagesView` owns sheet state and delegates
rendering; its form and shared material-label projection own presentation only.
`AgentChatView` consumes the shared controller;
it owns list/detail navigation, file popover and configuration input. The native
composer retains text selection, marked text and Undo; actual native first-responder
transitions report focus to its presentation binding. Its scroll host alone applies
editor geometry; proposed-size measurement uses a read-only attributed-text copy
and cannot resize the live editor or its accessibility frame. Its completion owner tracks
only the current query range and candidate selection. Candidate actions capture the
conversation and never rewrite the whole draft. Reply links open Notes; activity
details retain read targets. Changes uses ResearchController receipts and a shared
machine-local AgentChangeViewedLedger, independent of evidence and Settlement.
Public assistant phase metadata is retained on the message by streaming and history
reconciliation. Timeline grouping uses explicit turn and phase metadata; a process
disclosure owns only expansion, keeping each tool item distinct from the final answer.
Reply actions copy original text and project explicit links into Sources.
`AgentChatInputDock` owns only the view-local request disclosure. It keeps the
native composer mounted and inert while a request occupies the same bottom
surface; request identities, answers and submission remain controller-owned.
Queue-to-steer reuses the current-turn send path with the captured turn identity
and exact retained message, leaving the unsent draft untouched.
`AgentChatReadReply` owns every user, commentary and answer body through the same
safe reader, including plain prose. DOM selection crosses prose, tables and code;
reader height events reserve each message’s wrapped space in the transcript. Native
attributed text remains limited to expanded object previews. `AgentChatReplyQuotation`
validates bounded reader excerpts against the current reply identity and exact source. Whole-reply Copy retains original Markdown. The controller
stages compact `AgentChatReplyQuote` values in the existing conversation draft,
then retains them on the sent message. They are Agent prose, not Note snapshots;
source navigation retains its conversation/reply identity and no independent archive.
`ScholiumSidebarModeControl` accepts local Note copies only on the Chat segment.
Library menu and accessibility actions reuse that same Note-copy admission.
The native outline exposes the selected Note action; its coordinator binds the
Note and rejects a changed selection or detached list before forwarding.
`WindowChatActions` validates catalog identity, binds the destination at invocation,
and delegates capture/cancellation to the existing material-preparation owner;
hover performs no source read or navigation. Successful scoped App reads retain a bounded exact excerpt, source
fingerprint and returned line range as `AgentChatSourceObservation` on their
existing activity. Public completed web open/find events retain access observations
only. `AgentChatReplySourceContext` projects observations preceding the reply in
the same confirmed turn, merging Note coverage only within one source revision.
Supplied materials remain separate from explicit citations and reuse existing
material previews. This projection performs no network fetching or source-authority
inference; Note navigation and external URL opening retain their existing owners.
A native bottom safe-area inset owns floating-control clearance; transcript geometry
follows the latest reply only while the researcher is not reading earlier content.
Navigating back
does not stop work. Other conversations can be viewed, drafted and run concurrently.
Every asynchronous operation captures its conversation identity and connection
generation; incoming thread IDs and bridge tokens resolve their owner independently
of visible selection. Input preparation captures the original active turn before
awaiting material or target validation. That same identity selects and validates
the steering request; completion cannot turn it into a new start. A pending send
retains its message identity so cancellation cleanup cannot release a newer send.
Direct receipt sheets load only their requested change; a conversation
scope filters by its complete retained receipt IDs without collapsing successive changes
to a Note. Storage retains complete evidence. The controller owns archive/delete/restore and read/important markers;
conversation metadata persists through AgentChatStorage. The native List owns scrolling and swipes; row Buttons own activation; its Chat host uses automatic Button/Menu
styles. Archived conversations cannot send;
permanent deletion removes the conversation and execution entry. Machine path discovery and one-click
connection have one controller entry point; Settings receives the selected Triptych
controller from its composition root through environment injection, without giving
Settings a workspace runtime. The connection form and native file picker live only in
the Settings surface. The left selector is Library/Chat; Inspector exposes About/Links. Window close flushes drafts; runtime shutdown persists input and closes
its connection without global logout.

Conversation-token bridge requests allow 590 seconds for researcher input and
execution, with a 600-second client deadline. Cancellation removes ungranted
approvals before returning. Ordinary external requests keep the existing
25/30-second budgets. The bridge listener admits at most 32 peer connections;
blocking authenticated I/O runs on a concurrent dispatch queue. Active handler
tasks have the same independent bound, including operations still finishing after
transport timeout. A lock owns descriptors, admission and handler registration;
source transactions keep their existing workspace owner.

Stop revokes only the addressed turn admission and pending approvals. Disconnect
revokes all conversation admissions before closing the shared runtime. Toolbar
input-needed presentation derives from all pending approvals through one publisher.
Bridge shutdown stops admission, interrupts peer I/O and cancels registered handlers.
A dispatch group tracks the listener, peers and admitted operations; a one-shot continuation
reports drain completion or its deadline without waiting indefinitely for a source
transaction that must finish despite cancellation. Peer workers close their own sockets.

`AgentChatMarkdown` routes rich replies to `AgentChatReadReply` and plain text to
the native text view. The safe reader owns rendering and continuous selection;
the Chat list owns vertical scrolling. `AgentChatScrollBoundary` routes transcript
gestures before dispatch and retains one native recipient through momentum;
it owns neither offsets nor layout. Obscured native scroller hits return to AppKit
tracking without custom drag math. Its monitor detaches with the transcript. Wide
objects have one horizontal viewport. The loaded transcript uses measured stack
layout rather than lazy height estimates; scrolling cannot change its extent. User
interaction suspends automatic following. Mermaid uses the local runtime and semantic
colors. A reply-owned `AgentChatRichPreviewController` presents a transient native
card anchored to its source, bounded by measured content and screen size. Closing
or recycling the source removes the card; geometry messages grant no source authority.
`AgentChatCommandOutput` bounds retained public output to 256 KiB and reconciles
stream deltas with aggregate or tail-only completion without replacing prior output.
Agent Changes projects its collection/comparison size through a sheet-only native
attachment, leaving workspace geometry and receipt selection with their owners. `AgentChatTimelineItem` groups
contiguous operation messages for disclosure without shortening public replies.
`CodexChatTranscript` owns public item, turn and transcript-event decoding for
live delivery, history restoration and child inspection. Contracts carry typed
public content, phase, turn status and item identity; no raw child-history items
cross that boundary. Its activity decoder retains `CodexChatActivity` as the
single tool projection. Controllers apply decoded values to their existing state
without reinterpreting wire fields. Opaque Application-owned operation contexts
remain ephemeral within execution state for approval codecs and tool questions;
they are neither public messages nor persisted history. Invalid history is fully
rejected before reconciliation. Turn values distinguish full items, identity-only
summaries and unloaded items; lifecycle acknowledgements need no invented history.
`AgentChatActivityProjection` owns localization
and connection-loss presentation. The controller publishes App bridge activity before
waiting or executing, updates the same message at completion, and suppresses
the duplicate runtime envelope for its registered Scholium tools. Reopened
unfinished activity is interrupted or uncertain until authoritative runtime
history supplies a terminal result. File effects remain on their exact activities;
viewed preferences never alter receipt recovery state or authorize Undo.

`CodexChatDelegation` projects public coordination and child-lifecycle items into
an immutable `AgentChatDelegation` on the existing activity message. Sender,
targets, exact prompt/results and independently reported target states remain
distinct from the coordinating call's status. Runtime IDs and paths are data,
not adopted conversations or tool admission. Native disclosure owns presentation
only; search reads these retained values. Branch/reconnect preserves original
report provenance, including lifecycle records without their own sender field.
No child execution registry, inferred live state or competing scheduler is added.

`CodexChatChildReader` verifies runtime parent chains to the original local
conversation and reads legacy or paginated public turn history without resuming.
It rejects cyclic/unrelated ancestry, incomplete item projections and ambiguous
pages; private reasoning is excluded. `AgentChatChildController` owns one native
inspection's cancellable requests, snapshot, page cursor and pending interruption.
Its transport closure is bound to the originating connection and parent scope;
opening from a branch retains the original parent. An exact child turn is reread
before interruption and briefly checked afterward; acknowledgment alone leaves
an unconfirmed state. Disconnect and closing revoke inspection actions without
changing parent/sibling execution or bridge tokens. The inspector reuses native
Markdown and the activity projection, displaying managed tool invocations as
runtime reports without creating Agent Change receipts. It persists no second
child conversation, inferred live state or source material.

`AgentChatChildInspector` owns the sheet's native navigation path and inspection
lifetimes. Each child controller validates a target against its decoded public
report before using a connection-bound factory from the conversation owner.
That factory retains the original local conversation scope at every depth.
Navigation holds transient inspection identities only; popping cancels removed
inspections and dismissing cancels the whole path. The detail view does not
cancel itself merely because another destination covers it. Existing draft,
runtime and source owners remain unchanged.

Child adjustment drafts are keyed by runtime child identity in the original
`AgentChatConversation`. The inspector observes that owner through a narrow
`AgentChatParentCoordination` port; it keeps no writable draft copy or send task.
Ask Parent supplies an immutable message to the same admission and delivery
worker as the ordinary composer, with ancestry checked before local admission.
It consumes only the matching child draft. An `AgentChatCoordinationTarget`
retains public routing context separately from exact user text, including in
search, branch history and editable branch drafts. Receiving parent identity
must match; target removal is explicit. Parent acknowledgment never becomes
child-delivery evidence. Closing the inspector cancels reads, not admitted sends.

Live turn completion and pending interaction admission produce generic Chat
notification events through the registry's injected sink. Their validity stays
with the execution: superseded turns, answered input, Stop and disconnect cannot
deliver an old alert. No notification event is replayed from persistence or
hydration. Initial history loading has its own task so a cold notification can
await it without connecting; load failure leaves the requested conversation
unavailable. Opening consumes only the exact local conversation identity and
requests ordinary detail presentation. System delivery and window routing remain
owned by [Source Layout and Presentation](03-source-layout-and-presentation.md#presentation).

Chat presentation boundary values live in Contracts: `AgentChatQuestion`,
`AgentChatRuntimeApproval`, `AgentChatChildHistory` and structured material
failures. Application owns question decoding, public activity parsing, child
history validation and approval-response encoding. An approval codec retains
the exact requested permission payload privately; its immutable presentation
lists the supported decisions. Only the originating reply closure retains the
codec and may encode a selected decision for that exact request.

`AgentChatReference` carries a validated Note/vault identity, optional line and
exact-source SHA-256 in client-local URLs. `WindowChatActions` routes attachments
and answer references through the window's existing document transition queue.
Only that window owner publishes a verified source location after reading current
document source or the editor's checked text snapshot. A missing, changed or
unverifiable revision clears the requested passage location and retains an
informational notice; it creates no source write or second navigation queue.

`AgentChatController`, `AgentChatCapabilitiesController` and
`AgentChatChildController` are bounded App composition owners for conversation
execution, configuration/authentication and one child inspection, respectively.
They may import Application; their views and presentation helpers may import
only Contracts. A tool edit retains a revision and a read-only access-warning
projection; saving returns to the capabilities owner, which requires the same
configuration revision and still uses the runtime's versioned write. There is
no second editable configuration snapshot or alternate writer in the form.

`CodexChatCapabilities` in Application translates the official runtime catalog,
configuration defaults, plans, context usage and quota responses into Contracts
values. Model discovery follows the runtime cursor; provider picker IDs remain
distinct from execution model names. `ScholiumAgentIntegrationResources` owns
executable discovery and checks, leaving the frontend without filesystem I/O.

Conversations own `AgentChatPreferences` and the latest reported context usage;
public plan messages retain the runtime turn identity and observed run outcome.
The controller applies model, effort and web-search configuration at turn
admission. Compaction is an execution state whose acknowledgement is not its
completion; runtime events and Stop own its terminal state. Account quotas are
connection observations, fetched through the transport and cleared on disconnect.
`AgentChatRuntimeControls` renders these values with native controls and has no
transport, persistence or source authority. The current machine-local archive
version is 11; unsupported archives remain byte-unchanged and block overwrite.
Runtime turn status/timing is retained by exact turn ID through the shared transcript
decoder and controller. The view projects elapsed wall time without owning execution.

The same connection owner coordinates pending thread-static setting renewal.
Conversation preferences retain desired values; connection-scoped observations
track application. Renewal closes admission before checking runtime idleness,
including loaded descendants and background commands. Connection identity and
cancellation guard replacement, preserving the existing archive and sign-in;
presentation owns no parallel reconnect or replay loop.
Connection construction awaits capability initialization before publishing
readiness. The capability owner applies saved Skill roots through its private
connection-initialization route; ordinary configuration edits retain the existing
idle admission check. Renewal cannot block its own initialization.

Turn completion expires blocking interactions independently of runtime tool
observations. Item events and restored item statuses own tool outcomes; an ended
turn cannot manufacture an interruption. Connection invalidation marks running
runtime observations uncertain while revoking all execution admission.

`AgentChatInputBehavior` stores the machine-local Return preference. Native
Return and the composer button share `submitDraft`; explicit queued-item steering
keeps its exact-turn checks. Queue edits change only retained text in place.
`AgentChatActivityIssues` keeps failure/unknown counts visible above individual
activity rows. `CommandExecution` retains runtime facts; expanded output uses a
read-only native window owned and closed by its originating details view.

`AgentChatActivityProjection` supplies action/target wording from existing receipts
and optional public command-action metadata; it never parses shell text for intent.
`AgentChatActivityText` owns only a visibility/adaptation-bound text shimmer.
Context occupancy uses the last reported turn against reported capacity, separately
from cumulative tokens and account quota. In-place details and Diagnostics share
one retained-evidence view. Conversation-local disclosure choices survive item
updates; inspecting an operation preserves its process on completion.
Consecutive calls are projected into compact activity groups without replacing
the underlying records. Native disclosure styling owns trailing accessory
visibility; it owns no execution state.

The capability owner decides whether a Zotero connection is explicitly configured.
Only a successfully read configuration without that connection permits the default
read-only server in thread overrides; disabled/custom connections remain untouched.
Chat's research instruction adapter provides Triptych routing and source-link
context. The bundled Core Protocol owns research boundaries. Runtime launch and
thread overrides disable automatic project-document discovery; selected Skills
and runtime account/configuration remain with their existing owners.

`AgentChatSearch` derives literal matches and passages directly from retained
public conversation values. It owns no index, provider access or source reads.
`AgentChatFindState` retains only the view's query and matching-message selection;
streaming updates preserve that selection while it still matches. The view maps
message identity to grouped timeline identity and reveals matching activities.
`ContextSearchField` keeps AppKit field-editor, marked-text and focus ownership;
optional Find callbacks leave other search surfaces' Return/Escape behavior intact.
Rename captures its conversation identity before the alert, independently of selection.

Messages retain runtime turn identity from correlated turn-start responses and
public events/history, including the turn captured before an admitted bridge
operation awaits input or a source transaction. `CodexChatBranch` validates the
runtime prefix and projects exactly attributed public messages; it refuses an
unknown boundary instead of dropping unattributed history. Branch creation owns
the idle source conversation's operation task and cancellable `branching` state.
`thread/fork` receives `lastTurnId` for inclusive branches or `beforeTurnId` for
editing an opening request, plus `deferGoalContinuation` and a fresh
connection route without active turn admission. The latter prepares the selected request's exact text, materials
and Skill choices in the ordinary draft, including an empty retained prefix
before the first turn. Origin records whether its boundary is included. Only a
confirmed exact runtime prefix creates a local branch;
the next explicit send admits its confirmed turn on that retained route. Branches retain original
receipt identities and an immediate source-conversation/turn link. Late or
cancelled creation does not select or admit a new conversation. Other selected
discussions remain selected when the original source is no longer being viewed.

Blocking runtime questions use `CodexChatQuestions` decoding into `AgentChatQuestion` and the
same conversation-owned pending-interaction queue as approvals. Their native
form owns presentation only; answer drafts and submission state live in
`AgentChatExecutionState`. Reply writes the exact requested answer mapping once,
then awaits the matching thread/request `serverRequest/resolved` event. Skip
sends an empty mapping for ordinary input. Correlated MCP input retains its tool
identity and transient arguments; its alternative action stops the owning turn.
Stop, disconnect and turn completion revoke unresolved
input instead of inferring confirmation or replaying it. Public activity retains
question text, nonsecret option descriptions and labelled nonsecret draft/submitted
responses; secret values remain ephemeral and are discarded at resolution or
termination. Active forms replace their duplicate activity row except during
Find. Reopening displays interrupted public records without restoring request
authority or secret input.

Explicit async delivery uses `CodexChatAsyncQuestions` and the same native form.
`AgentChatMessage.asyncQuestion` owns persisted nonsecret questions, drafts and
receipts outside execution state. Identity-bound reply envelopes use the existing
send/steer path without consuming the composer draft. Confirmed user input or a
send receipt resolves matching questions; uncertain sends retain their message
identity and never replay during recovery. Turn completion does not expire them.

`CodexChatRuntimeApproval` strictly projects supported command, terminal input,
network, file and permission requests without inferring effective access. Native
presentation shares its typed decisions and complete scope; raw details remain
transient. Initialize requests experimental metadata so per-command additional
permissions are not omitted; this requests protocol information, not execution
permission. `AgentChatInteractionReply` keeps Note, question and runtime responses
distinct. Runtime replies freeze the exact pending request until its correlated
resolution; item completion separately owns the operation outcome. Persistent
policy amendments have no granting action. Public approval records retain the
request and chosen scope without creating Agent Change receipts.

Pending server-request IDs are unique across the shared connection. Ambiguity
immediately invalidates every execution admission before asynchronous transport
teardown. Queued replies recheck connection generation and exact turn before I/O;
stale callbacks cannot answer a replacement execution. One execution invalidation
owner handles both normal disconnect and ambiguous-request teardown.

Ask-mode Note updates obtain an `AgentNoteUpdatePreview` through the same App
router and Application collaboration owner that later execute the request.
`prepareAgentNoteUpdate` is the single saved-revision validation and body/source
transformation path shared by preview and execution. Preview builds the existing
exact-source comparison without flushing App editors or preparing an Agent Change;
execution repeats preparation and retains its ordinary editor, revision and
transaction checks. The App preview route checks an open Triptych and is not an
additional external MCP tool. The controller captures the preview with its
request, checks execution admission after awaiting it, and refuses unconfirmed
comparisons. The native comparison sheet reuses `ExactSourceComparisonView` and
answers the same pending request identity; presentation holds no write authority.

`AgentChatCapabilitiesController` owns connection-scoped Skill/tool observations,
refresh and configuration-write tasks, with generation checks and disconnect
invalidation. It does not persist an installed inventory or edit configuration
files. `CodexChatMethods` translates Skills discovery/configuration and paginated
MCP status; the official runtime owns the effective configuration. Native
Settings changes retain their idle guard, while the token-scoped in-app Chat
capability tools use the same owner for explicit Agent-requested writes during
an active turn. Those writes are serialized and version-checked; they do not
change the admitted source or permission result. Selected Skills are draft
values; sent messages retain immutable request labels and explicit runtime
Skill inputs, independently of observed invocation events. Unknown or disabled
choices remain visible and non-sending. The connection Settings owner refreshes
inventory for its selected thread; its native capability subview owns visible
grouping and shared-setting confirmation presentation.

Associated Skill folders are launch preferences in UserDefaults, keyed by the
normalized selected Codex configuration path. The capability owner reads the
latest preference before editing or refreshing, so separate connections merge
folder choices instead of overwriting a stale projection. Each process tracks
whether it has applied that preference through `skills/extraRoots/set`; a
background inventory refresh cannot apply new roots or retry a failed request.
Explicit Refresh validates folders and reapplies them when idle. The Application
boundary validates local directories without reading or changing Skill contents.
Settings uses the existing window-owned folder picker and captures configuration
scope across its asynchronous result. Removal changes only the launch preference
and process discovery roots; source directories and Skill bytes remain untouched.

Tool authentication has a separate connection-generation-bound task in the
capability owner, so ordinary inventory refresh cannot cancel or falsely confirm
it. `mcpServer/oauth/login` returns an ephemeral validated HTTPS URL; only the
explicit Sign In action opens it. A matching tool/thread
`mcpServer/oauthLogin/completed` event clears the pending URL and refreshes current
inventory. Authentication completion does not manufacture connection readiness.
The URL, pending request and result notice never enter conversation persistence.
Shared-setting confirmations capture the configuration path before presentation;
the native view rejects applying them after that scope changes.

`CodexChatToolConfiguration` projects editable connection fields from effective
runtime settings and retains the exact writable user-layer version. Known
overrides make a connection inspectable but noneditable; runtime-added defaults
do not become user configuration. Version-checked `config/batchWrite` changes
only edited fields and requests the runtime's live reload. Unknown fields and
credential values are not rewritten. The view owns its unsaved form; the
capability owner scopes saves and explicit reloads to the captured connection.
Failed or stale writes retain the form without an automatic retry. The
application-managed Scholium bridge has no user edit/removal route.

Advanced access projection contains environment variable names only. Unsupported
structured environment references remain runtime-owned and cannot be flattened
into a text editor. Neither the form nor Chat persistence reads credential
values. The App Server launch retains its existing inherited-environment filter;
the runtime can load its own configuration-folder environment. Changing a server
destination checks whether existing access settings would be reused and requires
an explicit choice. Settings saving remains distinct from connection readiness.

The Zotero preset reuses this configuration editor with the bundled connection helper
and descriptor-owned `--read-only` arguments. `ScholiumAgentHelper` has only
token-scoped Scholium MCP and read-only Zotero entry points. `AgentMCPService`
owns framing for the helper and independent CLI; the App discovers its helper in
`Contents/Helpers`, never through user-local CLI installation. Its enabled state remains in the
selected runtime settings file, including after reconnect. No per-turn override
or secondary preference rewrites it. Existing same-name connections remain
inspectable/editable through their actual effective configuration. Explicit local
API checks use the runtime-owned `ZoteroUseCases` and connection-generation-bound
observations; they neither imply MCP readiness nor add conversation material.
