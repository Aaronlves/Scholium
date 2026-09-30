# Architecture: Agent Collaboration

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Authenticated
MCP delivery, conversation admission, and runtime-owned capabilities.

## Delivery path

The App-bundled helper is a stdio delivery adapter. It owns JSON-RPC framing,
initialization, fixed discovery, closed schemas and error envelopes, then calls
the authenticated current-user App endpoint. It cannot launch the App, construct
a workspace runtime or independently read/write Triptych files. The App router
uses only currently open workspace capabilities; multiple open Triptychs require
an exact stable workspace identity.

External clients and in-app Chat use the same Application research-operation
owners. Chat adds a connection-bound conversation route and exact runtime
thread/turn metadata. Transport authentication is not mutation permission.
The registry resolves the route and rechecks turn admission before each effect
after suspension. Stop/completion revoke turn admission;
connection replacement invalidates routes. Pending server-request identities must
be unique across the connection: ambiguity revokes all admission before teardown.
Queued replies recheck connection generation and exact turn before I/O.

Bridge admission and handler work are independently bounded. Blocking peer I/O
does not block the main actor. Shutdown stops admission, interrupts peer I/O and
tracks draining handlers without indefinitely waiting on an already-admitted
source transaction that must finish or recover. Peer workers own descriptor close.

## Fixed tool surface

Contracts owns closed tool names, schemas and structured output. External research
tools and token-scoped runtime capability controls are separate surfaces. The
latter use the addressed connection's existing capability owner, not an expanded
external research API. Exact tool inventory belongs to executable schemas.

Browse consumes current Library inventory/visibility, not another index.
Pagination binds the sorted listing and exact workspace/role/directory scope;
changed listing revisions reject old pages. Note slices preserve complete-source
UTF-8 offsets. Optional context is source-derived and rechecks Note fingerprint;
it does not join a bibliography or trigger Zotero reads.

Attachment operations bind current authored relationships and Note revision to
bounded descriptor-relative reads or an exact external bookmark lease. The
shared immutable-snapshot reader supplies selected PDF text/page or image
coverage; no source archive is created. Empty extraction is not blank-page proof.

Display validates complete-source ranges before a UI request. External calls
name a current exact window; Chat captures window/registration identities at
admission. Navigation uses that window's existing transition queue and editor/tab
owners. Source, scope and supersession are rechecked after suspension; hidden,
reopened or switched windows cannot inherit requests. Cancellation settles the
waiting call even if its queue entry is skipped. Dispatch is not focus/selection
acceptance.

## Note mutation authority and evidence

Mutations flush matching editors and enter the workspace source gate. Create
proves vacancy and commits exact source/identity. One saved-revision
transformation owner handles complete-source, body-preserving-envelope and
multi-range updates, validating UTF-8 ranges, old bytes, scalar boundaries,
overlap, YAML and capacity. Preview shares transformation; execution repeats
revision/transaction checks. Read-only Ask preview neither flushes nor prepares
a receipt.

Ask-mode source operations await native permission for the exact request;
unrelated runtime approvals remain separate. Presentation cannot write.
Preview/move plans confer neither execution authority nor stored state; execution
recomputes the fingerprint within the source lease.

Move uses the ordinary coordinator and one Agent Change containing exact
identity/path/source/link effects and linked-source preimages after readback.
Inverse checks identities, revisions, vacant destinations and future link
resolution before feeding preimages to that coordinator; it never normalizes
reverse links. Receipt state changes only after inverse proof; partial failure
retains per-file recovery.

Receipt queries page the evidence store. Update Undo requires current ending
fingerprint and exact preimage, then updates the original receipt. Create/trash
invent no text preimage; post-write evidence failure stays uncertain and never
licenses retry. Repositories retain [Source Storage](05-source-storage-and-read-models.md#vault-write-and-prewrite-recovery-boundary)
containment, atomicity, readback and recovery.

## App presentation and setup

Window routing, notification delivery and Settings composition belong to
[Runtime and Ownership](01-runtime-and-ownership.md#presentation). External-host
setup displays helper commands without changing host configuration. Agent Change
inspection reads exact receipts; Changes review does not alter
receipt recovery eligibility.

## Native Chat client

Application owns bounded framing, correlation, timeouts and replies, without an
Agent loop. Swift Subprocess manages its single stdio process, I/O and teardown.
Runtime authentication/configuration retains selected-directory ownership;
credentials and raw stderr never enter logs.

One Triptych Chat controller is shared across windows. It owns conversation
inventory, public messages, drafts and permission; each conversation owns one
execution state for admission, input delivery, approvals, errors and tasks.
Versioned machine-local history is atomically persisted; corrupt/unsupported
archives block overwrite and remain unchanged. Portable Chat cwd and Skills are
separate from machine-local runtime account/configuration.

Saved connection intent restores transport/history only, never input or source
replay. Unexpected failure revokes admission before bounded owner-controlled
reconnection; explicit Disconnect clears intent and cancels reconnect. Shutdown
saves drafts and tears down transport without global logout. Browsing selection
does not own execution: asynchronous work captures conversation and connection
generation independently of the visible page.

### Materials and source observations

The conversation-scoped material owner prepares bounded immutable copies and
cancellation. Whole-Note/selection capture uses exact saved source or a checked
editor snapshot; an unavailable dirty editor cannot fall back to disk. Note/file
pickers, accepted Paste/drop and PDF-page derivatives share preparation, validation
and disposal. Drag entry inspects types without reading bytes. Clipboard/drop
origin is typed rather than an invented file path. Encoding conversion retains
original and converted representations with independent fingerprints.

Retained files are validated before sending and never reread from originals at
delivery. Failed preparation remains explicit. Removed unpublished copies are
discarded; referenced copies survive branch/history retention. Replacement/removal
releases unused copies only after successful history save and reference checks.
Physical PDF page identity stays paired with each selected image input.

Public source observations retain exact returned ranges, fingerprint, extent and
representation on existing activities. Sources matches preceding observations in
the same confirmed turn, merges Note coverage only within one revision and keeps
supplied materials distinct from explicit citations. Runtime web/Zotero reports
remain reports, not independently verified whole-source access. Reference
navigation revalidates current source through the existing window transition;
changed/unverifiable revisions discard old coordinates with a notice.

### Input, interactions and recovery

Sending captures draft/materials and persists a write-ahead delivery projection
while the current draft remains editable. Confirmed dispatch consumes only captured
input. Known pre-dispatch failure removes provisional history; newer draft text
survives. Attempted-but-uncertain delivery retains identity for explicit recovery,
never automatic replay. Stop during preparation cancels without a runtime turn.

Steering binds the captured active turn; completion during preparation cannot
silently convert it into a new start. Queue advancement occurs once after matching
normal completion and settled delivery. Stop/failure/reconnection pauses it;
unrelated turn completion cannot resume a paused queue.

Blocking questions, Note permissions and runtime approvals retain distinct typed
reply codecs, identities and resolution states. Requested runtime permission
payloads remain private to their originating reply closure. Replies freeze the
exact request until correlated resolution; item outcome is independent of approval
acknowledgment. Stop/disconnect/turn completion expire unresolved blocking input.
Persisted nonsecret records convey history only; secret input and raw details stay
ephemeral. Explicit asynchronous questions instead retain identity-bound public
drafts/receipts on messages and resolve through ordinary send/steer recovery;
normal turn completion does not expire them.

Turn completion cannot manufacture tool interruption. Shared decoding of live
events, restored history and child inspection owns public item/phase/turn meaning.
Malformed or incomplete history is rejected before reconciliation. Connection
loss leaves unfinished runtime observations uncertain while revoking admission.
Bridge activity uses one message through approval/execution and suppresses its
duplicate runtime envelope. Runtime effects never manufacture Agent Change receipts.

### Branches and delegated execution

Branches require an idle source and a confirmed exact runtime prefix. Included
ended-turn boundaries and excluded opening-request boundaries are distinct.
Branch creation is cancellable and establishes a new route without active turn
admission. Exact text/materials/Skills enter its draft without sending; original
draft and receipt identities remain intact. Unknown attribution refuses branching;
late/cancelled creation cannot change selection or admit execution.

Delegation stores public sender/target/prompt/result and separately reported target
states on existing activities, not a competing child scheduler or execution
registry. Child inspection validates ancestry to the original local conversation,
excluding unrelated/cyclic chains, ambiguous pages and private reasoning. Each
inspection owns scoped cancellable reads and exact-turn interruption; acknowledgment
alone is not confirmed Stop. Branches retain original parent provenance. Nested
navigation retains that scope; popping/dismissal cancels inspection lifetimes
without affecting parent/sibling execution. Roster refresh observes transient
metadata, keeping historical reports and refresh failures distinct. Stored child
draft text is inert; coordination routing is separate from editable user text.

### Runtime configuration and capabilities

One connection-scoped capability owner initializes catalogs/Skills before readiness,
serializes refresh/version-checked writes and invalidates on disconnect. Runtime
owns effective model, effort, web search, tools and Skills. Discovery cursors and
provider picker IDs are not execution model names. Conversation desired settings,
connection observations, context occupancy and account quotas remain separate.
Static-setting renewal closes admission and requires runtime/descendant idleness;
it does not replay turns or replace archive/account state.

Native settings drafts are view-local, not a second configuration writer. Known
overrides are inspectable but noneditable; effective defaults do not become user
configuration. Writes touch edited fields only, preserving unknown/credential
values. Stale failure retains the form without retry. Access projection exposes
environment variable names, never secret values or flattened structured references.
Destination changes explicitly resolve reuse of existing access settings.

Portable Skills preparation creates missing files only, never overwrites researcher
instructions. Runtime project discovery is bounded to cwd; one process-local extra
Skill root is applied before readiness and is not a persisted folder preference.
Failed application blocks sending. Ordinary native writes require idle admission;
token-scoped explicit Agent configuration uses the same versioned owner without
changing the admitted research permission.

OAuth has an independent generation-bound task; inventory refresh cannot confirm
or cancel it. Only explicit Sign In opens a validated ephemeral HTTPS URL. Matching
tool/thread completion refreshes observations but does not invent readiness; URLs
and pending auth state never enter history.

### Zotero boundary

Chat uses Scholium's bundled `scholium-zotero` MCP connection for Zotero
library access. The connection uses only Zotero Desktop's localhost API and
Connector, never a community server, Python runtime, private SQLite database,
or a second Scholium-side library authority. Its read surface includes search,
metadata, collections, tags, groups, children, indexed full text, attachment
URLs, annotations, originals, exports and citations. Writes use Zotero-authorized,
version-checked item updates; Connector imports lack prewrite target binding.

The native Zotero service remains the Application owner for settings and links;
the same Application boundary composes the independent MCP server for Chat and
external hosts. A Zotero result is not promoted to Scholium source evidence;
metadata, indexed text, annotations and original-file bytes remain distinct.
Item updates require an exact library and version; failed readback reports
an uncertain outcome.

### Native presentation boundary

Continuation, Explain and Polish share `CodexWritingAssistance`:
ephemeral, tool-free App Server requests with model preferences independent of
Chat. Model/effort checks, disabled capabilities and event rejection constrain
execution. Operation-specific prompts, JSON validation and deadlines distinguish
sentence continuation from explanation/replacement Markdown. Cancellation,
timeout and disconnect interrupt the exact turn. Window-owned selection results
retain variants; popovers own presentation. Explicit Chat handoff creates drafts;
Document owns validation and replacement.

The composer owns selection, marked text, Undo and focus; conversations
own durable drafts. The Chat controller uses window-scoped visibility tokens to
avoid cycling unread markers during visible streaming. Sanitized reply snapshots
own rich-object identities; Copy/Expand cannot reparse objects. The safe reader
preserves continuous selection; one native viewport owns scrolling, and reading
sessions own window-local anchors/disclosures. In-page updates preserve unchanged
blocks and selection without a second reveal/scroll timeline. Preview geometry
grants no trust.

Live notification validity remains execution-owned and is never replayed from
history. System delivery/routes belong to Runtime and Ownership.

## Source entry points

- `Scholium/Services/MCPAppBridgeRequestRouter.swift`: live research routing.
- `Scholium/Services/AgentChatController.swift`: conversation/execution composition.
- `ScholiumApplication/CodexAppServer.swift` and `CodexChatTranscript.swift`:
  transport and shared public decoding.
- `ScholiumContracts/ScholiumMCPContracts.swift`: executable tool surface.
