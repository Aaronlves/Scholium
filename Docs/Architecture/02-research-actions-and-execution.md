# Architecture: Research Actions and Execution

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Action preparation,
execution, Research Context, Records, continuation, and recovery.

## Public Action and Run boundary

Research Actions use the in-process compiler boundary shared by every
delivery-neutral capability:

```text
ResearchActionsInspectorView / ResearchActionPanelView / CLI
        | immutable values and intents
ResearchActionController (one Workspace window)
        | ResearchActionUseCases
ResearchActionRunCoordinator (Application; one WorkspaceHandle isolation domain)
        +-- PlatformActionCatalog
        +-- Research Guidance owners
        +-- ResearchConnectionCoordinator
        +-- ResearchContextUseCases
        +-- LocalResearchExecutionStore
        +-- AgentAnalysisCreationReservationStore
        +-- PortableResearchRecordStore
        +-- repository / recovery / source / Zotero authorities
```

`ScholiumContracts` owns public Action identity, initial object/material/source
references, flat academic Profile/Result Contract types, Run/Session-safe
request and response values, Run Activity Ledger entries, Source Reference
Envelope, result/evaluation schemas, structured errors, and
fingerprints. Contracts contain no SwiftUI layout, absolute path, bookmark,
socket location, provider implementation, repository, or hidden secret.

Every Run boundary carries the six-value `ResearchActionID` directly and a
required `ResearchActionSnapshot`. There is no compressed internal Function
identity, Action-to-Function mapper, optional snapshot fallback, or decoder for
the retired shape; unknown Action identities and fields fail closed.

`ResearchActionRunCoordinator` is the sole Action availability, preparation,
delivery, extension, submission, finalization, cancellation, manual-end,
continuation, and recovery coordinator. It is one Application component under
the owning `WorkspaceHandle`, not another runtime or mutable Workspace
snapshot. Its purpose-specific dependencies contain only the registration,
Profile, source, Search/read/Graph/Metadata/Record,
repository, recovery, and local connection authorities required by those
transactions.

Per-window `ResearchActionController` owns only selected Action/Profile,
researcher Action-input drafts, presentation identity, progress/cancellation,
errors, and the current Run projection. It owns no source, method, Session,
result, Record, researcher Response, Settlement, provider, or mutation
authority.

## Availability and preparation

The closed `PlatformActionCatalog` first filters role-valid public Actions and
provides their hard source/selectors/operations. Application then resolves
exactly one enabled Action Skill-folder registration and its availability,
loads the academic-only Profile, and evaluates source/integration availability.
Missing, changed, ambiguous, or invalid owners fail closed with one repair
route; no bundled fallback or package resolver participates.

Opening the Action sheet flushes only its current initial object. Preparation
rechecks the presented Action, object identity/revision, focal Materials,
source access, registration relation, folder availability, Profile, and
repository/recovery readiness. It creates one Run and inserts the displayed
initial object into its Run Activity Ledger.
For every existing writable Note, `AgentChangeEvidenceStore` captures one exact
Run- and Note-bound starting revision before Agent access. Confirmed writes
advance its ending revision. Body-only and complete-source intents map to the
corresponding `NoteChangeSet` and repository transaction. Targeted Metadata is
a distinct typed operation with its own portable-record revision, transaction lease,
compare-and-swap transaction, and readback; it never creates source change
evidence. This
machine-local evidence serves only Record diff and direct Undo; ordinary
repository transactions continue to own interrupted-save recovery.

`ResearchActionController` distinguishes one active sheet's preparation from
a global cancellation barrier. Presentation invalidation cancels its task; a
noncooperative result or late initial handoff is rejected by generation and
receives one best-effort typed cancellation without creating a visible retry
entry or blocking another Action. Only an explicit cancellation already in
flight, or its retained retryable recovery, contributes to the window's
barrier. The Application remains the owner of Session revocation, write
convergence, and durable recovery truth.

The Run snapshot freezes:

- public Action, initial object, research request, focal Materials/source, and
  starting revisions;
- registration relation/display identity, registration-document revision, and
  resolved local folder path string;
- academic Result Contract plus Application-owned machine fields;
- operation availability and exact Run read scope;
- initial Run Activity Ledger entry and its origin; and
- continuation origin when present.

It does not freeze folder contents, Search/Record query responses, rank,
provider cache, Session secret, or a reusable write key. A failed multi-store
preparation rolls back only proved task-owned new machine state; source bytes
and existing recovery remain authoritative.

## Pairing and delivery

GUI Action preparation requests a one-time Pairing Code from
`ResearchConnectionCoordinator` only for an existing unfinished Run. The
copyable Agent handoff contains the locator, one-time code, and direct steps for
the Agent to operate the CLI itself. The code is unwrapped only while composing
that complete copied handoff; it is not separately rendered or exposed to the
accessibility tree. **Copy New Handoff** invalidates the prior pairing, obtains
a replacement, and copies it while retaining the same Run and recovery state.
The Agent enters the code through CLI standard input. An Agent-originated
`agent start` request uses the same Application preparation path, carries the
complete typed academic-input map for validation against the just-resolved
current Profile, and returns a protected Session directly; it does not create
or consume a Pairing Code. The CLI exposes no parallel public `action`
preparation, inspection, or cancellation family for external Agents.
`agent preflight-analysis` calls
`WorkspaceRuntime.preflightResearchAgentAnalysisCreation` without issuing a
Session. `WorkspaceHandle` resolves the assigned Analyses vault, uses the
managed-default root filename, reads current Settings only for optional field
preferences, filters canonical Metadata contracts through the selected
`AnalysisSourceTypeProfile`, and reports the fixed authored-YAML keys without
inventing values. It inspects the exact repository path,
portable identity owner, and pending system-Trash recovery evidence before
returning one status and one retry contract. The CLI never supplies the
Analyses vault ID for creation.
It also cannot assert a subfolder: researcher-selected placement enters this
workflow only as a researcher-created existing Analysis target.

For consequential `new_analysis`, deterministic digests of Triptych ID plus
the stable `request_id` own the reserved Note and Run identities. A separate
fingerprint of the logical preflight request detects changed input after the
first portable creation phase. The wire-level
`ResearchAgentNewAnalysisRequest` uses schema 4. Independently, machine-local
creation-reservation schema 1 persists replay state for both external-Zotero
and researcher-provided routes; optional binding state exists only for the
Zotero route. Reservation schema 1 is owned by
`AgentAnalysisCreationReservationStore` in `agent-analysis-creations-v1`, with
its own lock and validation boundary. It is not a
`LocalResearchExecutionStore` entry; the latter owns only Run execution and
deletion authority. The reservation schema belongs only to exact replay of the
deterministic request identity. Its
sibling directory is never scanned as Local Execution authority and cannot
block system-Trash preparation; an unreadable record fails that request identity
closed rather than being auto-deleted or treated as a Run. A reservation with
no portable identity, source, or Run is explicitly pre-commit:
preflight reports the real absent state. The record freezes the first
consequential destination, route or binding, authored YAML values, source type,
supplied managed values, and academic purpose. A refreshed preflight cannot
replace any of them; optional Settings preferences grant no authority. One atomic CAS then
advances the logical-request, returned-creation, and complete-start fingerprint
tuple together. The record freezes
the committed source fingerprint before projection or relationship work. Once
matching source and identity exist, the owner resumes
only those exact inputs without reconsidering later Settings. Concurrent starts
for the same deterministic Run are coalesced by complete start fingerprint;
changed payload conflicts before another creator can run. For a
requested Zotero relationship, it marks the mutation boundary before calling
the portable owner and reconciles only an exact readback. Replay never reapplies
a committed request over a changed source/relationship, missing source,
system-Trash responsibility, or terminal Run. The managed creator's
source/identity readback queues the sole derived refresh; direct start awaits
that owner rather than racing a second Workspace generation. A committed-source
projection failure is therefore exact-retryable without duplicate creation
even if later Settings or App-process state changed.

`LocalAgentBridgeErrorPayload` and CLI error schema 2 carry one
`AgentOperationRecovery`: retry safety, whether the original request identity
must be retained, one next-step token, and only for missing/trashed source the
two researcher-controlled branches. Each branch separately states identity
reuse and its next step: request-owned Restore resumes exact identity, Restore
of another existing Analysis starts that target, and distinct creation uses a
new identity. Bridge mapping owns the closed
`path_occupied`, `identity_occupied`,
`identity_source_missing_or_trashed`, `source_unreadable`,
`stale_projection`, `replay_conflict`, `session_expired`, and
`outcome_unknown` results. These owner errors do not fall through to
`operation_failed`.
Unknown outcomes carry an operation-specific executable step: creation reruns
its same-ID preflight, idempotent reads/writes retry exactly, pairing obtains a
new handoff, and non-idempotent existing-target start stops and reports. End is
also non-retryable: it may already have revoked the Session, so response loss
requires stop-and-report rather than another credential use.
Both routes use the mutually authenticated loopback framed bridge and the same authenticated
Context, Discuss-turn, Discussion-Finish, write, Result, End, conflict, and
recovery owners. This is a deployment tradeoff rather than the default native
IPC choice. An embedded XPC service is private to its containing app; exposing
a Mach service to the independently installed CLI would require a separately
installed helper or LaunchAgent. The current no-helper topology instead uses
the established local-tool pattern: loopback-only binding, an App-created
current-user secret, mutual authentication, bounded frames, and authentication
before request decoding. The signed sandbox probe proves the listener needs
`com.apple.security.network.server`; packaging rejects entitlements outside the
declared privilege set while accepting only Apple-injected signing identity
metadata.

A Discuss-turn request uses the same authenticated Session and
appends only to the active `PortableResearchDiscussion`; it does not use the
Run Activity Ledger. After durable Agent response evidence exists, authenticated
Discussion-Finish calls the same Application finish owner as the researcher,
forms the portable Record, and revokes the Session. Its unknown outcome is
non-retryable for the same reason as End. The UI's End Action route calls the
same Application cancellation owner as authenticated CLI end;
sheet dismissal alone does not end the Run. Cancelling Discuss converts its
current portable exchange into a finished Research Record before removing the
active projection, so researcher-authored statements are not discarded. A
write Result finalizes after its own exact transaction and Result validation;
the Application does not prepare, attach, or expose a post-write Fidelity
child. A separate Fidelity Run is created only through the researcher-visible
Check Fidelity Action.
This chapter owns pairing, Session, and Run lifecycle. [Research Guidance](04-research-guidance.md)
owns the Skill, Profile, and citation configuration consumed during
preparation.

An external Agent workspace registers every exact Protocol and current Action Skill
source returned by `WorkspaceSkillDiscovery` through its host's project-level
Skill mechanism before connecting a Run. `ScholiumCore` owns the release-managed
Protocol folders; `ResearchConfigurationStore` owns current Action-folder
resolution without content access. Core Protocol always routes one protected runtime kernel. Its entry
uses the current request or official handoff for project entry and an explicit
researcher request for workspace bootstrap. After authentication, only
Application-owned state, typed `next_actions`, and operation responses route
active-Run, mutation/recovery, and completion references; no Core mode or
second state field exists. Completion
routes exactly one per-Action Result reference. Core and those references own
Result-field composition; Action Skills own intellectual procedure and never
restate the submission form. Discussion Protocol separately owns
attributed-turn response composition because Discuss has no generic Result
body. Application-selected `required_skills` and Core Protocol route the
registered Action Skill; user Skill prose cannot select Protocols, commands, operations,
authority, lifecycle, or recovery. Each allowed Run receives one Run Brief, minimum
`ResearchRequiredSkill` set, frozen registration revision, and Result Contract,
with no Skill prose or source path. Run Brief contains current task/object/state,
safe operation availability and next action, not a dump or summary of research
materials. Scholium does not fingerprint or attest the host-loaded Skill bytes. Result Contract
marks Agent academic fields versus Application machine fields. `reload`
reconstructs this packet from the frozen Run, revalidates exact Target,
Materials, and formal source owners, and returns typed `stale_run` rather than
a usable packet after true drift. It never reads Skill contents, later Profile
values, or old Research Context responses.

`agent start` stores its issued credential and then returns the start receipt
with the initial authenticated Action context. `agent pair` stores the exchanged
credential and asks the Application-owned Run owner for one
`ResearchAuthenticatedRunContext`. A failed initial delivery retains
the protected credential and directs the Agent to `reload` for the same Run;
start or pair is not repeated. The retired public `agent context` command has no
compatibility route.

Application derives ordered authenticated `next_actions` from the frozen
Action, Result Contract, and Run Activity Ledger. Discuss gets an exact read,
bounded Search, reply, and Finish; other Actions get eligible reads, writes,
and a strict Result template. Requirements remain typed, and Check Fidelity
requires its frozen inspections. Templates contain required academic fields;
the contract retains optional fields. No query creates reading or source-use
testimony, and CLI help is only an adapter. The frozen Target stays the
first-write baseline; after a confirmed self-write, the ledger revision drives
reload, Recommended Reading, and exact inspection. Source or identity drift
still returns `stale_run`.

Authenticated Run Context schema 18 gives Work Write/Critique Analysis/Topic
`recommended_reading` and Topic Synthesize Analysis-only reading.
`RecommendedReadingCoordinator` owns eligibility and delivery shaping. It
combines the revalidated target and frozen request with Graph-owned direct
Connections and Search-owned title/alias, role, and lexical ranking. Fixed
quotas merge identical fingerprints while retaining typed reasons, then form
ordinary exact-read requests. It creates no parser, index, Saved Search, source
cache, score, or persistent recommendation state. Channel failure is Partial
or Unavailable; start, pairing, and `reload` use the same path. A
`related_notes` clause resolves one to four catalog names and reuses this owner;
`agent related` is its CLI adapter.

Agent-facing material is serialized under an explicit evidence channel.
`taskDirective` contains public Action, researcher request, safe operation
facts, current Result Contract, and the minimum required Skill identities plus
the frozen registration revision; `researchEvidence` contains Markdown, YAML declarations, citations,
Zotero metadata, Records, and provider responses as typed data. Evidence text
cannot alter the other two layers, Session, activity ledger, tools, or next Action.

Result and Method Feedback prose remains an opaque exact string throughout
Agent submission, strict schema-18 decoding, Record validation, hashing,
persistence, CLI reading, Search projection, and replacement. No Core or
Application operation parses scholarly markup, resolves a Record-authored
link, or reconstructs source from a rendered value. Presentation may derive a
read-only projection only after the complete portable Record has been accepted.

## Research Context

`ResearchContextUseCases` authenticates Session/Run, authorizes Triptych scope,
and snapshots generation before provider calls. The provider composes existing
Search, exact Note reads, Graph, Metadata, Records, research-state owners, and
the frozen source/Zotero references. Material inspection cannot search or
enumerate: an authorized closure asks `ResearchSourceAccessStore` for one page
of the selected binding. Core balances bookmark access, rejects symbolic or
nonregular targets, and fingerprints and reads from one no-follow descriptor.
Application returns a path-free base64 page with whole-source and page
fingerprints. It imports no Core types and reads no private stores directly.
Researcher State is separately rebuilt on demand for the Action target Note
from current Settlement, Critique disposition, and
attributed active-Discussion owners. It is neither stored by the provider nor
expanded into source history: Settle has no machine-local source version or
recovery pin.

Search remains the only parser/ranker and keeps Note and Record identities
discriminated. Direct Relations remain same-manifest explicit Markdown
occurrences. Metadata retains its typed portable owner; authored `summary` and
`keywords` remain document declarations. Record queries retain
strict source fingerprint, actor, Action, and deletion semantics. A provider
adapter can only convert an already returned owner value into the closed Source
Reference Envelope; it cannot fill unknown actor/locator/revision, add a
confidence score, or broaden scope.

Research Context request and clause schema 7 use closed snake-case Agent input.
Evidence eligibility is Application-derived from content kind and owner state,
never Agent-selected. Clause versions change with their legal shapes, so older
clauses cannot acquire Material inspection. Application validates shape and
capability, then dispatches through the current owner. Response schema 7 keeps
one ordered, limited Current, Partial, Stale, Unavailable, or Invalid Query
outcome per clause; one owner failure cannot erase the others.

Response schema 7 also copies the Note result's closed `NoteSearchMatchReason`
values from that same Search response. The Application adapter does not
reconstruct them: authored YAML provenance retains exact source ranges,
managed Metadata explicitly has none, and
direct-relation provenance retains relation, direction, anchor, target, and
explicit Markdown occurrences. A coarse direct-relation or Metadata retrieval
reason without the corresponding typed match is rejected.
Search contract 11's structured `callout:` and `has:` match reasons are not
admitted into Research Context schema 7: those queries return Invalid Query at
this boundary instead of being flattened into a lexical Source Reference.

Exact Note/section reads use a lossless UTF-8 page with a source-range locator.
The provider calculates UTF-16 offsets and line/column positions from the raw
source, including EOF after a final newline. A stateless page cursor binds the
Application-computed query/Run/Triptych/clause digest to the selected Note,
fingerprint, complete slice, next UTF-8 offset, and prior-page digest. On a
continuation, the provider rechecks every binding and returns Stale rather than
reading a replacement Note or revision. Contracts cap an encoded context
response below the bridge frame, and `LocalAgentBridgeResponse` preflights the
complete outer envelope before it writes a frame.

`inspect_materials` is a single-clause request. Its current item contains one
bounded byte-exact page and no locator outside the closed Material envelope. A
stateless Material cursor binds Run, Triptych, query, clause, Material identity,
whole-source fingerprint, prior offset, and prior-page digest. Continuation
rereads and verifies the prior page before advancing; each page revalidates the
whole source. The response budget therefore remains below the bridge frame
without creating a cached source, tokenized extraction, or general file-read
port.

Continue Result schema 4 and authenticated Run Context schema 18 carry the
closed Material reference states `current`, `changed`, `missing`, and
`unavailable` plus the typed Researcher State requery requirement. A created
Continue Result embeds that child Context. The stable
Local Execution envelope persists Run and Triptych identity, complete Note
participation, authority state, payload revision, and payload fingerprint. Its
current private payload persists the frozen Analyze source route, active child
handoff, and independent Zotero-binding write state. Agent change evidence is keyed directly by
`(Run ID, Note ID)` rather than copied foreign identifiers. Authenticated Run
Context schema 18 also carries a closed minimum required-Skill set and optional
typed Fidelity contract. The Skill set always identifies Core Protocol and the
Action Method with its frozen primary revision; it conditionally identifies
Discussion or Zotero System Skills and contains no prose or path. The Fidelity
contract contains vault-qualified exact-read selectors
and expected revisions but no mutation operation; the Research Context provider
loads those exact owners directly rather than resolving an ambiguous Search
path. Application requires the Zotero System Skill only for an Analysis target
with frozen Zotero context and a Zotero-capable Platform Action; the requirement
contains no authority or transport.
All prior Result, authenticated Context, and Local Execution payload revisions
fail closed instead of interpreting expanded continuation or Skill semantics
under an old revision. A structurally valid Local Execution envelope remains
readable for deletion scoping without authorizing that unsupported payload. If
the envelope remains live but any current or nested payload contract is
unreadable, Local Execution exposes only its stable Note scope and exact file
fingerprint to the system-Trash recovery owner; it does not partially decode or
reconstruct the Run.

Opaque reference resolution rechecks Session, Run, scope, current owner, and
revision. Ending/re-pairing/revocation, Triptych change, deletion, or source
change therefore invalidates old references without claiming that already
delivered text can be retracted. Response bytes remain in memory only and are
neither Run state nor Record content. Session authority retains no Source
Reference registry or delivery history. A response-local reference ID is only a
correlation value. Continue Research authenticates the submitting Run, requires
its authorized scope, and re-reads the current owner to validate identity,
revision, locator, and owner-specific provenance fields before handoff.

Continue never calls the Researcher State provider as a handoff owner and never
copies a parent-Run Researcher State envelope into the child. Application
validates the old reference's closed nonauthorizing shape, removes it from the
child handoff and reference checks, and persists only
`requires_researcher_state_requery`. A subsequent child query receives the
child Run scope and reads the then-current underlying owners. The original
full request audit, including old Researcher State references, remains in the
parent Run's local continuation request record. The child carries only the
approved academic purpose and stripped Agent-authored handoff; these retain
Agent attribution and become neither old state evidence nor researcher
commitment.

The test target supplies a nonempty pure replacement provider over one fixed
nonprivate summary candidate. Its mechanism bypasses production Search, checks
the candidate against the authorized Workspace snapshot, and returns current,
stale, unavailable, or invalid-query outcomes through the same response
contract. Focused tests compare its provenance and currentness to production
summary discovery, reject guessed writer attribution, keep query delivery out
of the Record, and re-resolve an explicit handoff through Continue Research. This fixture is test-only:
it owns no runtime fallback, parser, ranker, index, or persistent state.
Production and test providers cannot change Run, Activity Ledger, Record,
Application-derived evidence eligibility, or continuation contracts.

## Tracked multi-document mutation

One Run embeds one `ResearchBoundedWriteSet` as the current implementation type
for its Run Activity Ledger. Its limits are enforced before decoding or
resolution can allocate unbounded work. Activity requests contain exact target
selectors, requested operations, and an Agent-authored reason. Application
resolves stable or reserved identities, expected revisions/proven absence,
current roles, lifecycle, and containment, then automatically appends every
valid target. No App permission coordinator, subset sheet, collaboration
policy, or per-document researcher decision participates.

Schema 7 members have no wall-clock expiry: they survive Session rotation or
re-pairing until the Run or member ends. Every operation still revalidates its
Session, identity, operation, and revision.
Members may independently track `modify_metadata` for an existing
Note and freeze its portable Metadata revision, including proven absence for a
first record. `set_zotero_binding` and `clear_zotero_binding` apply only to an
existing Analysis and freeze the global portable binding revision in addition
to the Analysis source revision.
The separate `ResearchZoteroBindingWriteIntent`, Local Execution binding-write
ledger, bridge payload, and `agent write-zotero-binding` command contain no
Markdown or Metadata payload and never call a Zotero write. Core set/clear is
the sole portable mutation owner; stable Analysis identity, operation, one-use
transaction lease, and current binding revision are rechecked before commit.

Every mutation names one ledger member and one idempotent operation ID. The live
Session obtains one non-Codable short-lived transaction lease bound to that
operation and the complete activity-ledger digest. This lease prevents replay
and cross-operation confusion; it is not a consent or trust decision. Application repeats containment,
regular-file/absence, stable identity, role, operation, revision, and
lease checks inside the final source operation. Completion likewise
uses a coordinated identity/source observation with identity readback after
the source read. The sole repository then retains
displaced bytes, validates complete-source candidates, and for body-only writes
requires a provable body boundary while preserving any closed frontmatter bytes
unchanged. Closed YAML diagnostics do not erase a known body boundary; an
unclosed delimiter fails before mutation. The repository then atomically
replaces and reads back. A `modify_metadata` call instead validates the exact
granted keys and role catalog, replaces the canonical identity-keyed JSON at
its expected Metadata revision, and reads it back without entering the source
repository. Result truth is written into the same Run operation entry before
the response. An I/O timeout after delivery returns outcome unknown and
subsequent calls query the same operation ID.

Member transactions are independent. Confirmed source or binding changes stay committed when a
sibling conflicts or fails. Only Scholium-confirmed success advances that
member's applicable revision. External changes invalidate one member. The Run
cannot finalize or safely compact the ledger until every started operation is
written, not written, explicitly abandoned before mutation, or reconciled to a
recovery duty. Manual End cancels a no-write Run; confirmed changes require
Result finalization, while unknown writes and recovery duties block End.

## Result submission and finalization

Agent submission contains the required one-line Record Title, the frozen
contract's academic fields, explicit blocked state where applicable, formal
Fidelity outcomes, and Analyze-only literature recommendations.
Core Protocol's state-gated completion reference loads exactly one
current-Action Result reference before submission; the frozen Profile remains
field authority and the Method remains scholarly-method authority.
Application validates field presence/type/cardinality/exclusive choices and
that every explicit source reference carried by an Action-specific payload is
current, in Run-readable scope, and has one authoritative owner, revision, and
locator. Query and delivery history is neither submitted nor interpreted as
reliance. An invalid field returns field-level repair without mutating the
Record or Activity Ledger.

The Run stores one `ResearchResultPayload` partitioned into Record Title, Agent
academic fields, and machine fields. For write Actions, submission may precede final transaction
reconciliation, but Record finalization cannot. Application derives actual
changed/unchanged/conflicted/unknown documents from operation entries and
creates one strict portable Record in one idempotent finalization. Fidelity
status is attached only to an explicitly initiated Fidelity Run; an ordinary
Analyze, Synthesize, or Write Record may therefore carry `not_required` while
the registered Method still reports its own checks and limitations. A
completion retry with the same operation/submission digest returns the same
Record; a different payload fails closed. An interrupted committed
source/finalization gap is repaired from the Run and transaction evidence
unless a Record deletion tombstone forbids recreation.

`PortableResearchRecordStore` owns schema-18 Records, including the
frozen Record Title, explicit Analyze source route, exact source-byte
fingerprints, Agent activity outcomes, and researcher-owned
Method Feedback. Activity outcomes retain the exact portable target, operation,
terminal result, and source, managed-Metadata, or Zotero-binding revision domain;
they exclude capability handles, request fingerprints, warning text, recovery
locators, credentials, and Agent reasoning. The same store owns one schema-2
Settlement per Note. Settle derives and records the current confirmed `(Record
ID, Note ID)` Agent-change activities under the Record listing lock. Analyze recommendation
mutation and Method Feedback replacement use one revision-safe replacement
primitive under portable coordination and lock, distinguish pre-commit refusal
from post-commit uncertainty, and read back before success. Record schemas 1
through 17 have no decoder or mutation route; their bytes remain untouched and
nonauthorizing when encountered.

Schema 18 contains no source-use report or actually-used Materials list.
Action participants are the Target, every explicit frozen Material, and every
existing Note with a recorded Agent activity or confirmed Agent change;
dynamically queried Notes never become participants. A failed absent-target
creation remains identifiable inside its activity outcome without fabricating a
Note revision. In-text citations remain optional authored academic content and
are not reconstructed from query or delivery history. The Action identity
retains the Application-established frozen Material Note IDs so projections
never confuse a confirmed-change-only participant with a selected Material.

The researcher CLI's `record list` and `record read` adapters consume one
complete immutable `WorkspaceResearchSnapshot`; they never scan portable JSON
or construct another Record index. List validates the stable Note UUID against
the current catalog or the snapshot's historical participants, filters the
Record-owned `participatingNotes`, and emits the snapshot's complete source
manifest plus exact Record fingerprints. Read selects one exact Record UUID and
returns the decoded schema-18 value with its same-snapshot fingerprint. Either
adapter refuses an incomplete projection or missing fingerprint and exposes no
Record mutation use case.

`saveMethodFeedback` uses exact Record ID, expected Method Feedback revision,
and finalized-result fingerprint. It validates both tokens under the same lock
and replaces the parent Record's feedback in one Record write; a stale token
rejects the candidate. Settlement, Method Feedback, and recommendation
disposition remain excluded from finalized-result identity. Record deletion
removes those partitions and writes the existing minimal machine-local
tombstone; the Application permanent-deletion use case then removes that Run's
Agent-change evidence and completed Local Execution. No Note or filesystem
operation calls this cleanup, and no other operation can recreate or reparent
the Record.

Action completion derives each modified change's starting revision from the
expected revision of its first `committed` Agent write record, not the Run-start
participant revision or an earlier conflict/abandonment. A created change has
no starting revision and cannot enter exact comparison or direct Undo. Its
participant baseline is the first jointly committed source-and-identity
revision; its ending revision is the last confirmed readback after any later
authorized writes.
`ExactSourceComparisonBuilder` is the single exact
byte-diff owner for both Record confirmed-change pairs and Document conflict
inputs; the projections remain disposable and non-Codable.

Application owns `settle` and `undoResearchRecordChanges`. Settle first verifies
the controlled Note's exact saved revision, then asks the portable store to
derive every current `(Record ID, Note ID)` Agent-change activity under the
Record listing lock. Fingerprint, covered activities, rationale, researcher,
and time are the only durable Settlement facts.

Direct undo preflights every selected confirmed change against the portable
Record, exact `(Run ID, Note ID)` `AgentChangeEvidenceStore` binding and
starting bytes, current controlled stable identity/path, and Agent ending
revision. Application restores the complete
starting source only while current source still equals the ending revision,
using the ordinary revision-checked repository save. A stable rename is
resolved before that save. Application returns observed
per-document recovery facts; multi-document requests are not a durable
transaction. Undo does not read or write Settlement, and every attempted
source replacement triggers refresh even when readback is uncertain.

`WorkspaceSnapshotBuilder` derives Action activities, Settlement requirements,
and Result arrivals from current Local Execution, exact schema-18 Records, and
schema-2 Settlements.
The bounded projections omit authority and research content. Needs Attention
follows current entry/recovery state. A formed Record evolves its Action item to
Result Ready; confirmed changes create per-Note Settlement requirements, but one Action creates
at most one Run/Record Result arrival with one affected-Notes list. Local
Execution, Record, and Settlement remain durable owners.

The Action sheet stops at ordinary or researcher Follow-up preparation and
handoff. Persistent Run status, End, Result routing, and recovery belong to the
Action-level Notifications item rather than the Inspector launcher. It contains
no finalized Result or Settlement subtree. The Records detail is the sole
current result-reading surface: its reading plane owns **Follow Up…** and
parent-owned Method Feedback, while its Evidence rail owns Changes, Effects,
Participants, and Technical Details. Its shared exact-comparison
sheet supports whole-document direct Undo only when the feature model holds the
validated window-lifetime grant. The Document conflict route supplies different
inputs and operations to the same pure folding-diff presentation without
sharing source or conflict state ownership.
Notification **Review Result** produces the exact fingerprint-bound
`.reviewResult` grant; browsing cannot. The Inspector row remains a launcher.
`ResearchResultNotificationCoordinator` folds activity and arrival into one
Run item, publishes it to every window, and evolves its five specified states.
Popover/window disappearance never deletes it; completed **Dismiss** and
unfinished **End Action…** remain distinct operations.
Confirmed reload rereads the exact Record ID through the existing Record use
case and accepts no differently identified response; it adds no presentation
cache or Method Feedback owner.
Application maps portable replacement commit uncertainty into the public
mutation-outcome taxonomy rather than exposing a Core error to the interface.
An already-committed refresh failure or commit-uncertain replacement is
nonretryable until that exact-ID reload reconciles the Record; only a
proven-not-committed failure appears as **Save Failed**.
Likewise, a workspace refresh that removes a Record makes an authoritative
reload fail closed and refuses any later write to that missing identity. An
already-open Method Feedback draft retains its local text and exposes
reconciliation rather than substituting a different Record.

`PortableResearchDiscussion` remains the single active exchange owner.
Comments retain stable Note/fingerprint, inclusive line range, and only the
bounded rendered selection; they retain no unselected surrounding context.
Researcher Comments update only the active exchange. The authenticated Agent
`discuss-reply` route validates the frozen Discuss Run and response contract,
uses a stable statement ID for outcome-unknown retry, then commits the Agent
response and finished Record under the portable store's one exclusive lock.
Only after that commit does the Run coordinator idempotently persist `.complete`
and finalize Session authority. A retry between those transitions returns the
same Record and repairs missing Run completion; changed content fails closed.
The route writes no Note or Metadata and accepts no Result body or separate
Finish. Closing the sheet performs no storage action. Discussion does not use
the Activity Ledger unless it explicitly continues into a separate write Action.

Research Records presentation remains Triptych-keyed:

```text
Document / Research menu / Search Record result
        -> ResearchRecordsWindowCoordinator (routing only)
        -> ScholiumResearchRecordsRoot (exact Triptych capabilities)
        -> ScholiumResearchRecordsFeature.ResearchRecordBrowserModel
             +-- Application Record Search
                  +-- exact total, provider-owned sort, 100-row slices
             +-- Portable Record response/review/undo use cases
             +-- browse / exact review-result / Reading Lead route
             +-- window-lifetime direct-Undo eligibility
             +-- rebuildable paged Reading Leads and continuation relations
        -> ResearchRecordBrowserView (App-owned native presentation)
```

The coordinator owns no Record data, current Workspace focus, or mutation.
The package-internal feature imports Contracts only and owns no SwiftUI,
Workspace, window, Agent Bridge, or Application capability. Window-local
Scope/View/search/route state disappears on close. Portable Records remain the
only durable owner.

## Agent Continue Research, researcher Follow-up, and Method Feedback

Continue Research validates a determined current result, next Action/initial
object/purpose, bounded epistemically labelled handoff, and platform support.
It reserves one new Run and `continuedFrom` identity
idempotently. The new Run performs ordinary fresh preparation and Research
Context query. It inherits no prior method, Profile, Session-only write
state, Activity Ledger, response, rank, cache, or provider availability.
Note and Record handoff references re-read their current owners. A selected
source-Material reference rechecks the parent Run's frozen source identity and
fingerprint through `ResearchSourceAccessStore` and reports current, changed,
missing, or unavailable; it transfers no bookmark, path, bytes, or source
authority.

The CLI and authenticated Agent Session remain the owners of Agent autonomous
Continue Research. A created Continue response attaches the child locator to
the existing Session and returns the child's complete authenticated Context,
including its fresh minimum `required_skills`; it requires neither another
pairing nor an initial reload. The CLI stores the same Session credential under
the returned child locator before reporting success, so later `agent reload`
addresses that child directly. Session bindings retain the immediate parent Run;
re-pairing or revoking any ancestor recursively removes every derived descendant
without affecting independent Runs. Only after the next Record safely forms does that child
persist `ResearchContinuationLineage(.continueResearch)` with its parent Run;
the parent relation is rebuildable. The child remains one portable Record and
one Search result for audit, while the Records collection folds it beneath the
parent instead of presenting a second peer row. The parent Action sheet derives
the same direct children as a read-only **Continue Research** section. A denied
or abandoned continuation leaves the old Record unchanged, and initiator actor
is explicit rather than inferred as researcher adoption.

`followUpContext` resolves the live parent fingerprint and target. Record and
Result Ready routes share one `ResearchActionController` sheet for current
Action, finding/question/hypothesis, and Research Request. On confirmation,
`prepareFollowUp` re-resolves Skill, Profile, operation availability, materials,
and the initial activity target, reserves a fresh Run, and persists `.followUp`
with researcher initiator. Parent Session, Activity Ledger, Context, and Agent
judgment never cross. Optional feedback CAS-replaces only the parent comment.

Method Feedback remains a fingerprint-bound researcher comment in its parent
portable Record. It starts no separate Run, Session, capability, bridge
operation, or file transaction. Settings can reveal or replace the Action's
folder relation, and Finder can open an available folder, but any content edit
is performed independently by the researcher or external Agent. Scholium
therefore neither clears feedback after an edit nor claims a verified link
between the comment and a changed Skill file.

Completion compacts the active Local Execution payload to one machine-local
terminal receipt and recomputes its stable terminal envelope, deleting prepared
instructions, the Run Activity Ledger, write ledgers,
extensions, and conflict rows after the portable Record exists. The receipt
retains only state still needed for idempotency or continuation rather than a
feedback queue or method history. Method Feedback remains owned by the portable
Record and is not cleared by execution compaction.
Identical submission retry is idempotent, different terminal input fails
closed, and Session finalization removes remaining transaction leases.
All Action Skill files remain available for the Agent/researcher to edit with
their selected filesystem tools; Scholium does not proxy or inspect them.

## Source, Zotero, Fidelity, and lifecycle integration

`ResearchSourceReference` remains the only path-free durable value for a
Scholium-owned source-access route. `ResearchSourceAccessStore` retains local
bookmarks/paths privately and reopens exact regular files through the
established security-scoped, descriptor-relative, fingerprinted boundary. An
Analyze Run may instead use a frozen Zotero relationship and external Agent
retrieval: that route has no `ResearchSourceReference`, does not resolve
source bookmarks or read paper bytes through the source-access store, and keeps
paper bytes outside Scholium. When both relationships exist, a currently
resolvable local source selection remains the Scholium-owned route; a Zotero
attachment relationship or absent source selection uses the external route.
Zotero
bibliographic metadata is read once per Run, labelled as metadata, and never
substitutes for source content; a resumed Run uses its frozen snapshot and a
new Run reads again. The required `ResearchActionSnapshot` freezes exactly one Analyze
route: current Scholium source, external Zotero, or `researcher_provided`.
Completion revalidates the first, requires the frozen context for the second,
and accepts the third only while both source reference and Zotero context remain
absent. Selecting the third suppresses any existing Zotero snapshot and adapter
for that Run without changing the portable relationship. Schema-15 Records
retain that route without fabricating a source claim;
the external Agent narrows the scholarly result to the paper data available to
it and states only access limitations that materially constrain support. When a researcher explicitly
starts Check Fidelity without a formal revision-bound source envelope—
including `researcher_provided` and external Zotero retrieval—the Fidelity
skill reports Citation `unavailable`; Analyze's own self-check applies the
same evidential limit in its method result. Completion never promotes Note
YAML, URL, or bibliographic metadata into source evidence.
For the default Check Fidelity Profile, Application derives the aggregate
Finding fields from the attributed per-check outcomes; a researcher-customized
Profile remains explicit.

Check Fidelity remains a researcher-initiated, read-only exact-revision Action.
It never schedules itself, is not required by Analyze or another write Action,
does not collapse mixed outcomes, certify truth/acceptance, or own write
authority. A source change makes only the affected check stale.

System-Trash preparation rejects any relevant active or write-recovering local
execution. After all native source receipts commit, its recovery plan discards
affected active Discussions. It never deletes a finished Record or any
Record-bound Local Execution or Agent-change evidence. Explicit permanent
Record deletion remains the sole owner of that cleanup. An external source
absence without a plan performs none of the temporary cleanup. Unsupported
pre-production files remain byte-unchanged, unread, and nonauthorizing; current
decoders do not interpret them as configuration, execution, or Record authority.

CLI decodes Contracts, invokes the same Application capabilities, and encodes
canonical Run/Context/write/result families. Secrets arrive only through
hidden local input and never shell arguments. CLI owns no eligibility, method
routing, parser/ranker, Activity Ledger, repository transaction, Record schema, or
shell command string. One command specification registry owns both accepted
paths/options and rendered help; unknown help topics fail nonzero. Text-mode
`read` emits exact authoritative source without adding a newline. Agent-start
target JSON has one versioned snake-case wire
shape. A healthy CLI registry projection resolves UUID or unique-name selectors,
including UUID-shaped names; when that projection is absent or lacks a UUID,
the UUID passes directly to Application for selection. The protected
credential store creates and validates its current-user-only parent and session
directories before Session creation or Pairing consumption. In production,
`AgentSessionCredentialStore` persists beneath
`Scholium/State-v1/Agent Sessions` in the shared per-user Application Support
root; an explicit `SCHOLIUM_HOME` launch uses only its isolated
`ApplicationSupport/Agent Sessions` child. The retired home-level
`~/.scholium/sessions` path is not a compatibility route. If the directory
becomes unavailable after Application returns a credential, the CLI presents
the complete bearer value once to the bridge's authenticated Session-revocation
operation. Confirmed revocation leaves the Run active and directs the Agent to
copy a new handoff and pair that same Run; unknown revocation stops and reports.
The bridge cannot revoke a Session from its UUID alone.

Each current-schema credential stores the exact Application-issued expiry.
Every credential-store preparation prunes only expired regular files whose
validated Run identity exactly matches their filename; unknown schemas,
malformed files, symlinks, and unsafe modes remain untouched and nonauthorizing.
Result finalization revokes write capabilities but preserves the binding until
that original expiry for idempotent confirmation and Continue Research, so the
Agent performs no cleanup command after a normal Result.
