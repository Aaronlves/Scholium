# Architecture: Research Actions and Execution

Part of the canonical document set rooted at [IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md).
This chapter owns Action preparation, Run execution, Research Context,
records, continuation, and recovery; sibling chapters do not restate it.

## Public Action and Run boundary

Research Actions use the in-process compiler boundary shared by every
delivery-neutral capability:

```text
ResearchActionsInspectorView / ResearchActionPanelView / CLI
        | immutable values and intents
ResearchActionController (one Workspace window)
        | ResearchActionUseCases
ResearchRunCoordinator (Application; one WorkspaceHandle isolation domain)
        +-- PlatformActionCatalog
        +-- Research Guidance owners
        +-- ResearchConnectionCoordinator
        +-- ResearchContextUseCases
        +-- LocalResearchExecutionStore
        +-- PortableResearchRecordStore
        +-- repository / recovery / source / Zotero authorities
```

`ScholiumContracts` owns public Action identity, initial object/material/source
references, flat academic Profile/Result Contract types, Run/Session-safe
request and response values, Bounded Write Set entries, Source Reference
Envelope, Context Use Report, result/evaluation schemas, structured errors, and
fingerprints. Contracts contain no SwiftUI layout, absolute path, bookmark,
socket location, provider implementation, repository, or hidden secret.

`ResearchRunCoordinator` is the sole Action availability, preparation,
delivery, extension, submission, finalization, cancellation, manual-end,
continuation, and recovery coordinator. It is one Application component under
the owning `WorkspaceHandle`, not another runtime or mutable Workspace
snapshot. Its purpose-specific dependencies contain only the registration,
Practice, Profile, collaboration, source, Search/read/Graph/Property/Record,
repository, recovery, and local connection authorities required by those
transactions.

Per-window `ResearchActionController` owns only selected Action/Profile,
researcher draft values, presentation identity, progress/cancellation/errors,
unsaved evaluation draft, and stale-response tokens. It owns no source,
method, Session, Run, result, Record, provider, or permission authority.

## Availability and preparation

The closed `PlatformActionCatalog` first filters role-valid public Actions and
provides their hard source/selectors/operations. Application then resolves
exactly one enabled Skill registration for the Action, loads one coherent
current primary Markdown entry, resolves exact-Wikilink Practices in order,
loads the academic-only Profile, and evaluates source/integration availability.
Missing, changed, ambiguous, or invalid owners fail closed with one repair
route; no bundled fallback or package resolver participates.

Opening the Action sheet flushes only its current initial object. Preparation
rechecks the presented Action, object identity/revision, focal Materials,
source access, registration, primary method, Practices, Profile, current
Triptych collaboration policy, and repository/recovery readiness. It creates
one Run and inserts the displayed initial object into its Bounded Write Set.
No whole-Triptych checkpoint is automatic. Every later mediated existing-Note
write creates per-Note Before Agent Work exact-byte recovery through the sole
repository transaction.

The Run snapshot freezes:

- public Action, initial object, research request, focal Materials/source, and
  starting revisions;
- registration relation/display identity, exact primary method text, resolved
  Practice identities/text, and optional local folder path string;
- academic Result Contract plus Application-owned machine fields;
- capability availability and exact authorized read scope;
- initial Bounded Write Set entry and its authorization provenance; and
- continuation origin when present.

It does not freeze folder contents, Search/Record query responses, rank,
provider cache, Session secret, or a reusable write key. A failed multi-store
preparation rolls back only proved task-owned new machine state; source bytes
and existing recovery remain authoritative.

## Pairing and delivery

The Action sheet requests a one-time Pairing Code from
`ResearchConnectionCoordinator` only for an existing unfinished Run. The
copyable Agent instructions contain the locator/route only; the code remains a
separate privacy-sensitive Action-sheet value entered only through CLI standard
input. Pair exchange over the protected App Group Unix socket returns a hidden
Connection Session and the first layered delivery packet. Pairing/session
mechanics and lifecycle are owned by
[Research Skills and Agent Collaboration](04-product-skills-and-maintenance.md).

The first authenticated Agent session receives one Core Protocol and
capability catalog. Each allowed Run receives one Run Brief, Method Context,
and Result Contract. Run Brief contains current task/object/state, safe
capability availability and next action, not a dump or summary of research
materials. Method Context preserves exact primary Skill and Practice text plus
the post-authentication folder path. Result Contract marks Agent academic
fields versus Application machine fields. `reload` reconstructs this packet
from the frozen Run and never reads later method/Profile values or old Research
Context responses.

Agent-facing material is serialized under an explicit evidence channel.
`taskDirective` contains public Action, researcher request, safe capability
facts, and current Result Contract; `methodContext` contains primary Skill and
Practices; `researchEvidence` contains Markdown, YAML declarations, citations,
Zotero metadata, Records, and provider responses as typed data. Evidence text
cannot alter the other two layers, Session, write set, tools, or next Action.

## Research Context

`ResearchContextUseCases` authenticates Session/Run, resolves authorized
Triptych scope, and snapshots current generation before any provider call. Its
production provider composes the existing Application Search use case, exact
Note/section reader, same-snapshot explicit Graph relations, Property
projection, Application Record provider, Settle/Discussion/Evaluation owner
reads, and existing Zotero metadata or Record-owned literature-recommendation
capabilities when explicitly requested. It never imports `ScholiumCore` types
across the Application boundary or reaches private JSON/index files directly.

Search remains the only parser/ranker and keeps Note and Record identities
discriminated. Direct Relations remain same-manifest explicit Markdown
occurrences. Properties remain document declarations. Record queries retain
strict source fingerprint, actor, Action, and deletion semantics. A provider
adapter can only convert an already returned owner value into the closed Source
Reference Envelope; it cannot fill unknown actor/locator/revision, add a
confidence score, or broaden scope.

Research Context response schema 2 also copies the Note result's closed
`NoteSearchMatchReason` values from that same Search response. The Application
adapter does not reconstruct them: Property provenance retains exact source
ranges and direct-relation provenance retains relation, direction, anchor,
target, and explicit Markdown occurrences. A coarse direct-relation or
Property retrieval reason without the corresponding typed match is rejected.

The response carries one query/contract identity and Current/Partial/Stale/
Unavailable/Invalid Query availability. Opaque reference resolution rechecks
Session, Run, scope, current owner, and revision. Ending/re-pairing/revocation,
Triptych change, deletion, or source change therefore invalidates old
references without claiming that already delivered text can be retracted.
Response bytes remain in memory only and are neither Run state nor Record
content. The process-bound Session authority keeps at most 512 exact returned
Source Reference Envelopes per Run, without their response content, so Context
Use and Continue Research can require an actually issued envelope rather than
accepting an Agent-fabricated current owner reference. Re-pair/restart/end
clears this registry; it is neither a response cache nor durable research
state.

The test target supplies a pure replacement provider over fixed nonprivate
values. Production and test providers must produce the same envelope,
availability, failure, and replacement behavior without changing Run,
permission, Record, or continuation contracts.

## Bounded multi-document mutation

One Run embeds one `ResearchBoundedWriteSet` whose limits are enforced before
decoding or resolution can allocate unbounded work. Extension requests contain
only exact stable identities/reserved create identities, requested operations,
expected revisions/proven absence, and an Agent-authored reason. Application
resolves current roles/lifecycle/containment and the Triptych policy before
presenting one optional subset sheet or binding a Full Access set. Researcher
approval remains an exact Run-local fact until expiry/revocation/end.

Tightening the Triptych policy revokes an unused member added only by Full
Access and affects later extension/continuation. An explicit researcher-approved
member remains until its recorded expiry/revocation. Loosening policy affects
only later decisions. No policy change interrupts a repository transaction
already submitted.

Every mutation names one set member and one idempotent operation ID. The live
Session obtains one non-Codable short-lived write capability bound to that
operation and the complete allowed-set digest. Application repeats containment,
regular-file/absence, stable identity, role, operation, revision, and
capability checks at the last safe point. The sole repository then retains
displaced bytes, validates complete candidate Markdown/YAML, atomically
replaces, and reads back. Result truth is written into the same Run operation
entry before the response. An I/O timeout after delivery returns outcome
unknown and subsequent calls query the same operation ID.

Member transactions are independent. Confirmed changes stay committed when a
sibling conflicts or fails. Only Scholium-confirmed success advances that
member's expected revision. External changes invalidate one member. The Run
cannot finalize or safely clear the write set until every started operation is
written, not written, explicitly abandoned before mutation, or reconciled to a
recovery duty. Manual End blocks new calls and revokes Session access but
retains unresolved recovery state.

## Result submission and finalization

Agent submission contains only the frozen contract's academic fields, explicit
blocked state where applicable, and optional reference IDs for Context Use.
Application validates field presence/type/cardinality/exclusive choices and
that each claimed reference is current, in Run-readable scope, and has one
Source Reference Envelope. Agent use remains testimony; Application validation
is a separate machine fact. An invalid field returns field-level repair without
mutating the Record or write set.

The Run stores one `ResearchResultPayload` partitioned into Agent and machine
fields. For write Actions, submission may precede final transaction
reconciliation, but Record finalization cannot. Application derives actual
changed/unchanged/conflicted/unknown documents from operation entries,
completes Fidelity status from exact evidence, and creates one strict portable
Record in one idempotent finalization. A completion retry with the same
operation/submission digest returns the same Record; a different payload fails
closed. An interrupted committed source/finalization gap is repaired from the
Run and transaction evidence unless a Record deletion tombstone forbids
recreation.

`PortableResearchRecordStore` owns strict current Records and exact source-byte
fingerprints. It never decodes a retired record schema. Record mutation is
limited to Pin, Analyze recommendation disposition/note, and the Record-owned
Researcher Evaluation partition. Those paths all use one revision-safe
replacement primitive under portable coordination and lock, distinguish
pre-commit refusal from post-commit uncertainty, and read back before success.

Researcher Evaluation compare-and-save uses exact Record ID, expected
evaluation revision, and finalized-result fingerprint. It re-encodes the same
decoded finalized result without modification and proves its canonical
fingerprint before/after the evaluation-only change. Record deletion removes
the evaluation and writes the existing minimal machine-local tombstone; no
other operation can recreate or reparent it.

`PortableResearchDiscussion` remains the single active exchange owner.
Comments retain stable Note/fingerprint and inclusive line range without a
passage copy. Each attributed researcher/Agent turn updates only the active
exchange. Finish validates current participants and forms one Record; closing
the sheet performs no storage action. Discussion does not use Bounded Write
Set unless it explicitly continues into a separate write Action.

Research Records presentation remains Triptych-keyed:

```text
Document / Research menu / Search Record result
        -> ResearchRecordsWindowCoordinator (routing only)
        -> ScholiumResearchRecordsRoot (exact Triptych capabilities)
        -> ResearchRecordBrowserModel
             +-- Application Record Search
             +-- Portable Record mutation/evaluation use cases
             +-- rebuildable Recommendations/evaluation summaries
```

The coordinator owns no Record data, current Workspace focus, or authorization.
Window-local Scope/View/search/selection state disappears on close. Portable
Records remain the only durable owner.

## Continue Research and method improvement

Continue Research validates a determined current result, next Action/initial
object/purpose, bounded epistemically labelled handoff, current Triptych policy,
and platform support. It reserves one new Run and `continuedFrom` identity
idempotently. The new Run performs ordinary fresh preparation and Research
Context query. It inherits no prior method, Profile, Session-only write
authority, Bounded Write Set, response, rank, cache, or provider availability.

Only after the next Record safely forms does that Record persist
`continuedFrom`; reverse `continuedAs` is a rebuildable Record-index relation.
Denied/abandoned continuation leaves the old Record unchanged. Initiator actor
is explicit and never inferred as researcher adoption.

Method improvement is a separate explicitly researcher-started Run attached as
the one current `methodImprovementRun` in its parent Local Execution schema-8
record. Starting **Improve Current Method...** from a Record with one current
feedback comment freezes that exact comment revision/text, finalized Result
fingerprint, registration, current primary Method, linked Practices, and every
editable target revision. It issues a fresh short Pairing Code/Session through
the same bridge; ordinary Action context, Bounded Write Set, and Result
submission are not inherited.

The authenticated `method-context` response exposes only those frozen exact
targets. `improve-method` accepts one primary Method or linked Practice plus a
replacement, `diagnosed_no_change`, or `unavailable` diagnosis; CLI fills the
comment, Result, and target revisions from the current authenticated context.
A replacement obtains one non-Codable, nonreusable, short-lived capability
bound to Run, Session, request, target, and expected revision immediately
before the ordinary method-file transaction. That transaction retains one
previous-edit recovery point and reads back the exact source. The writing
state preserves enough evidence to reconcile interruption after the file
commit without writing twice.

Completion retains one machine-local terminal receipt rather than a feedback
queue or method history. It clears only a comment whose revision/text and
Result fingerprint remain exact; a concurrently modified comment remains.
Identical submission retry is idempotent, different terminal input fails
closed, and Session finalization removes remaining capability authority.
Folder supplements outside the primary/Practice owner are reported for the
Agent/researcher to edit with their selected filesystem tools; Scholium does
not proxy them.

## Source, Zotero, Fidelity, and lifecycle integration

`ResearchSourceReference` remains the only path-free durable source-access
value. `ResearchSourceAccessStore` retains local bookmarks/paths privately and
reopens exact regular files through the established security-scoped,
descriptor-relative, fingerprinted boundary. Analyze cannot complete without
its required current source. Zotero bibliographic metadata is read once per
Run, labelled as metadata, and never substitutes for source content; a resumed
Run uses its frozen snapshot and a new Run reads again.

Check Fidelity remains a read-only exact-revision Action. Multi-document writes
may request separate checks for each final revision, but no check collapses
mixed outcomes, certifies truth/acceptance, or owns write authority. A source
change makes only the affected check stale.

Permanent Note deletion preflights and cleans Run/write-set/source/active-
Discussion state that could authorize the Note, while finished Records retain
their tombstoned historical participant. Unsupported pre-production package,
binding, Profile, policy, request, child-run, grant, and record files remain
byte-unchanged, unread, and nonauthorizing after their clean cutover; no current
decoder or compatibility path can revive them.

CLI decodes Contracts, invokes the same Application capabilities, and encodes
canonical Run/Context/write/result families. Secrets arrive only through
hidden local input and never shell arguments. CLI owns no eligibility, method
routing, parser/ranker, write set, repository transaction, Record schema, or
shell command string.
