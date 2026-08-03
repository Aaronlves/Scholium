# Architecture: Research Actions and Execution

Part of the canonical document set rooted at [IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md).
This chapter owns Research Actions, protected execution, records, permissions, and agent coordination; sibling chapters do not restate it.

## Research Action and protected execution boundary

Research Actions follow the same in-process compiler boundary as every other
delivery-neutral capability. The protected Function adapter remains below the
public presentation and use-case boundary:

```text
ResearchActionsInspectorView / ResearchActionPanelView
        ↓ immutable presentation values and closures
ResearchActionController (one window, production UI)
        ↓ ResearchActionClient
ResearchActionUseCases (Contracts)
        ↓ internal Action-to-Function adapter
ResearchFunctionCoordinator
        (Application; preparation, delivery, evidence, completion;
         one shared WorkspaceHandle isolation domain)
        ↓
Core skill, checkpoint, record, and repository authorities
```

The old Function controller, panel, presentation route, and public use cases are
deleted. `ScholiumContracts` owns public Action identity, Target/Material/scope,
Fidelity checks, availability/repair codes, runs, submissions, and fingerprints.
`WorkspaceStore` composes `WindowResearchCapabilities` from independently
declared record, checkpoint, Skill, Action, source-access, and bibliography
ports. `ResearchController` receives a still smaller capability value and
cannot reach permission, source-access, or bibliography operations. Settings-
only and CLI-completion operations remain concrete Application capabilities
rather than requirements of a window-facing Contracts protocol. Protected
Function types remain only behind Application as the mechanism used by the
Action adapter. Contracts contain no application-defined labels, symbols,
package storage, YAML inspection, or layout. Researcher-owned Profile labels
are declarative data, not interface code.

The §8 Research Action public layer begins in `ScholiumContracts` with validated
`ResearchActionID`, public execution kinds and Target roles, role-filtered
default definitions, a unified native parameter model, and a fail-closed
schema-v2 `ResearchActionSnapshot`. Each preparation freezes the exact Target,
ordinary Method package and loaded-resource revisions, resolved Profile and
Profile-document revision, validated parameter values, and concrete readable
and writable note envelope. The snapshot contains no `ResearchFunctionID`. A separate versioned
`ResearchActionRecordIdentity` fixes the complete Action projection allowed in
future portable records to the Action ID alone; execution kind, Target role,
and protected Function identity are not record fields.

`ResearchActionProfile` schema 1 adds a bounded declarative configuration
contract without making it executable. It permits only note picker, passage
anchor, Material selector, source reference, bounded text, Boolean, and
enumeration modules. Profile, module, choice, and capability objects reject
unknown fields; every label, identifier, list, property boundary, selection,
text limit, module count, and choice count has an explicit byte or count
ceiling. Raw package and file-size preflight belongs to the later installation
boundary rather than the Codable value. The capability declaration contains
readable roles and a candidate existing-note write ceiling only. Its two
operations are Markdown modification and property-limited modification; it
contains no grant, policy, destructive lifecycle operation, conflict overwrite,
or executable payload. Property-limited modification rejects every key owned
by Scholium's protected machine-property catalog.
Applicable Targets remain readable, picker roles stay inside that
scope, execution kinds impose their direct-write role maximum, and Analyze
requires one matching required source-reference module. These declarations do
not grant authority. The Application resolver intersects them with the exact
current request and live identities to produce one nonreusable preparation
envelope. Machine-local standing policy is a separate decision factor and
cannot enlarge that envelope.
Property-only mutation is rejected by the current resolver because the retained
coordinator cannot yet prove a property-bounded source delta.
`ResearchActionProfileDocument` stores at most 256
Action-keyed bindings in `.scholium/research-action-profiles-v1.json`. Core
reads and atomically replaces that one bounded file through no-follow directory
descriptors, exact expected-revision checks, readback validation, and a
package/Profile compatibility check. The document may bind researcher-owned
Action identities and the optional bundled Manuscript Action only; it cannot
replace the six default bundled Action identities. Storage and its production
Settings editor remain nonexecuting configuration, while the Action resolver
consumes an exact Profile snapshot only during availability and preparation.
Once
a file exchange commits, any failed directory flush, readback, cleanup, or
canonical-path identity proof returns an unsafe-document error; bytes visible
through the old descriptor never become a reported Settings success.

`ResearchSourceReference` schema 1 is the only source-access value permitted in
an Action/Function snapshot or future portable record. It contains a closed
route, stable source ID, exact Zotero parent/attachment keys when applicable,
one display-only filename, and a source fingerprint. Its decoder rejects
unknown fields, route/key mismatch, path-shaped labels, and malformed
fingerprints. It has no bookmark, absolute path, or source bytes. The transient
`ResearchSourceBindingRequest` is deliberately non-Codable because its selected
file URL belongs only to the current machine-local operation.

Core's per-Triptych `ResearchSourceAccessStore` owns the corresponding private
binding at `Application Support/Triptychs/<id>/source-access/`. It writes a
single-link mode-0600 atomic file beneath a mode-0700 directory. Owned path
components are traversed through `openat` without following symlinks. Bookmarks
request read-only security scope; binding and every reopen acquire that scope
before filesystem inspection and balance every successful start. Source reads
open the complete path with macOS `O_NOFOLLOW_ANY`, require an
`fstat`-verified regular file, hash
exactly its starting size, then reject growth, truncation, path substitution,
alias, symlink, directory, stale bookmark, unreadable state, or fingerprint
change. A valid reselection repairs private permission drift without losing
peer bindings and atomically replaces corrupt app-owned bytes. Persisted
absolute paths and bookmark data remain only in this machine-local store. A
changed or inaccessible source is never replaced with the Analysis note.

An internal-only `ResearchActionFunctionMapping` in `ScholiumApplication` maps
Analysis and Synthesis to Develop, Write to Revise, and the remaining public
execution kinds to their protected Function mechanisms after role validation.
The same internal adapter derives the exact bundled Action from Function plus
Target role inside the protected coordinator. Core Skill resolution accepts that Action
identity explicitly: Analysis Develop resolves `scholium-analyze`, Topic
Develop resolves `scholium-synthesize`, and a package bound to one fails closed
for the other. `ResearchActionUseCases` now resolves and prepares default and
researcher Actions and embeds the resulting Action snapshot before protected
execution. Binding v1 never enters this path. The Inspector, Research menu,
common modular sheet, CLI, and delivery contracts enter only through Action
identity. Every Action run uses the separated Local Execution v2 boundary
below; unsupported pre-production run files remain byte-unchanged, invisible,
and unable to authorize current work.

The product Skill catalog schema 4 separates protected mechanism from ordinary
method prose. `ResearchSkillClass.method` packages each declare exactly one
public Action plus one internal protected mechanism. Discuss is an ordinary
Method and `scholium-discussion-protocol` is its automatic mechanism-only
adapter. Analyze, Synthesize, Write, Critique, Content Fidelity, and optional
hidden Manuscript are similarly distinct bundled Method references. System
Skills own authority and persistence boundaries; they cannot supply the
intellectual procedure. The old conditional Development, Revision, and
Manuscript resource selectors remain internal to protected stored execution
records and are never offered by current Actions; each Method now loads
its complete adaptive core, with Write feedback guidance included by default.
Before a new Triptych manifest is committed,
`ResearchSkillTransactionCoordinator` installs six independent editable
packages under `.scholium/skills/` and atomically writes
`research-working-method-bindings-v2.json`; Manuscript is represented by an
explicit disabled state. The initializer is idempotent for an exact interrupted
bootstrap and never runs automatically for a Triptych with an existing
manifest. Application exposes the same absence-checked operation as the
explicit repair primitive for the later categorized Settings interface.

The coordinator is the sole actor and cross-store transaction owner, not the
implementation of every storage concern. `ResearchSkillPackageRepository`
owns bounded package discovery, resources, revisions, CRUD and publication;
`ResearchWorkingMethodStore`, `ResearchActionProfileStore`,
`ResearchCitationMethodStore`, and `ResearchBibliographyMethodStore` each own
one persisted document; and the I/O-free `ResearchSkillResolver` owns package
graph validation and dependency ordering. These are synchronous values used
under the coordinator's isolation. Package-plus-binding replacement, recovery,
and use-before-delete checks remain together in the coordinator because they
span those authorities.

`ResearchSkillInstallationStore` owns the app-wide, short-lived staging
boundary for researcher-selected local directories. It walks the selected
directory through no-follow descriptors, accepts only bounded regular UTF-8
`SKILL.md` and one-level `references`, `templates`, or `evals` resources, and
rejects linked, multiply linked, executable, scripted, nested, oversized, or
structurally malformed input. Directory enumeration stops as soon as the
bounded entry ceiling is exceeded rather than first collecting an unbounded
directory listing. Its public preparation contains only a display
name, bounded file inventory and fingerprints, method metadata, proposed
Action placement, and the explicit fact that an Action Profile is still
required; source paths and bytes remain Core-private and expire from memory.
`WorkspaceRuntime` resolves the explicitly selected Triptychs and supplies
their existing `ResearchSkillTransactionCoordinator` actors. Core preflights every destination,
publishes each independently copied package with descriptor-relative
`RENAME_EXCL`, then repeats the bounded file/link/mode/readback validation.
Preflight and post-publication validation both reject a package identifier
still named by an active Action binding or by a retained capability binding;
malformed binding state fails closed. If a later destination fails, every
proved task-owned directory is moved out of the executable package namespace
to a hidden same-volume recovery quarantine. The quarantined inode is not
recursively deleted, so a late write through an already-open descriptor is
preserved. A missing or moved package, replaced Skills root, identity mismatch,
or otherwise unprovable rollback produces a typed recovery-required error.
Installation creates no binding, Profile, permission approval, or execution
state, so an unbound package starts disabled and later edits cannot synchronize
across Triptychs silently. Production Research Guidance Settings now presents
the staged inventory in a native sheet and requires explicit destination
Triptych selection. Cleanup and presentation of installation recovery
quarantines remain later Research Guidance work.

Action execution resolves only that Action-keyed v2 document. Its
`installed_default`, `researcher_skill`, and `disabled` states are explicit;
absence, malformed data, missing packages, invalid packages, and role/Action
incompatibility fail closed without a bundled fallback. The bundled package is
read only during initial installation or explicit restore. Research Citation
Method writes only `research-citation-method-v1.json`, and Recommended
Bibliography Method writes only `research-bibliography-method-v1.json`. If
either owned document is absent, a minimal compatibility reader may project
only that capability's fields from a retained Function-era
`research-skill-bindings.json`. Complete or empty valid state migrates lazily to
the owned document; an incomplete Citation package selection remains visible
for explicit style repair, and malformed bytes expose their exact revision for
revision-checked repair. The retained file is never rewritten or deleted, and
its Function-keyed primary, supplemental and Practice fields are not decoded,
validated, executed, or treated as package-use constraints. After an owned
document exists, later retained-file edits cannot change that capability.

One independently constructed `ResearchFunctionCoordinator` now exists per
workspace. It owns availability, Action/Skill resolution, immutable authority
and instruction packets, preparation and rollback across checkpoints,
Critique, Local-v2 and grants, delivery-only process keys, Local-v2 run lookup
and duplicate-Critique reconciliation, the complete completion/Fidelity
transaction, portable-record repair, protected cancellation, and protected
Discussion Finish. Its purpose-specific dependency bundle contains only the
repositories, vault roles and roots, control and Skill stores, source and Agent
request stores, checkpoints, portable records, Local-v2, Critique, and Zotero
authorities proved necessary by those responsibilities; the Workspace-wide
service aggregate cannot enter the coordinator.

A narrow `ResearchFunctionCoordinatorHost` lets the component borrow the
existing `WorkspaceHandle` actor for active-lifetime checks, the current
immutable Workspace projection, process-local key custody, default Action
context, Critique's general source-mutation adapter, Discussion Finish, and
disposable post-commit publication. The coordinator directs the protected
Critique preparation transaction and recovery, while the host adapter retains
the one general Critique Markdown mutation owner. The coordinator is not
another actor, adds no actor hop, and owns no Markdown buffer,
source-operation gate, mutable Workspace snapshot, or refresh implementation.
`ResearchOperations`, public Action preparation/completion/cancellation, and
Agent-request preparation/cancellation call it directly. The old
WorkspaceHandle preparation, completion, cancel, finish, record,
grant-completion, portable-record, Fidelity-linkage, continuation-validation,
source-validation, and refresh-warning helpers are deleted.

The component is physically divided by responsibility without creating new
owners: `ResearchFunctionPreparation.swift` contains availability and the
cross-store preparation/rollback transaction;
`ResearchFunctionDelivery.swift` contains Action/Skill resolution, packet
rendering, live-key attachment, and next actions;
`ResearchFunctionEvidence.swift` contains current source, Material, Target,
and repair evidence; and `ResearchFunctionCompletion.swift` contains the
terminal completion/Fidelity transaction. Machine-local source-binding
mutations and citation-method settings are the separate
`WorkspaceResearchGuidanceOperations.swift` adapter. Current preparations load
one complete Method plus the exact required System references and never enter
conditional-resource finalization. The legacy selection payload remains
Codable for machine-local state, but no public Use Case, CLI command, next
action, or rendered packet exposes its retired finalizer. Dialogue and Critique
have no alternate preparation path.

### Portable Research Record storage v1, record schema 3, and Local Execution v2

`PortableResearchRecordStore` owns one JSON file per intellectual record under
`.scholium/research-records/v1/records/`; `active/` owns one file per unfinished
portable Discussion. The retained empty `trash/` directory is legacy reserved
storage, not a current lifecycle or projection. Confirmed record deletion
isolates the exact reread JSON with a descriptor-relative rename inside
`records/`, verifies the isolated bytes, unlinks only that file, and restores an
interrupted pre-unlink rename on startup. A
separate `settlements/` directory stores exactly one replaceable current-state
file per Note. Settle therefore no longer appends an application-authored
history event, and Changed Since Settled is derived against the current
Markdown revision during snapshot assembly without a parallel pending-state
contract or event. Before the portable state commits, `VaultRepository` pins the exact
current bytes in the existing immutable-object prewrite ledger under the stable
Note identity. Identical fingerprints reuse one pin. The Triptych-scoped
machine-local `ResearchRecoveryPolicyStore` revision-checks the 10/30/50/no-
automatic-deletion policy; lowering a limit applies only the exact pin IDs in a
fresh preview. After confirmation it durably retains that approved ID set until
idempotent cross-vault removal completes, so interruption can resume without
silently including a later pin. Ordinary prewrite retention cannot collect
pinned entries, and removing a pin later permits unreferenced temporary evidence
to be collected. Each pin has a descriptor-relative, file-and-parent-synced
manifest with exact-byte fingerprint and a persistent per-Note monotonic order;
wall-clock time is display metadata only. SQLite is a derived projection:
startup validates each manifest against immutable bytes and replaces any row
whose note, entry, time, or order differs through one immediate transaction and
UPSERT. One advisory lock plus a partial unique SQLite index coordinate order
allocation across ledger instances. Every exact-valid manifest protects its
entry independently of projection; ambiguous order or projection failure sets
a write blocker and suspends automatic cleanup. Portable replacement errors
distinguish proved pre-rename refusal from post-rename uncertainty, and only
the former permits task-owned pin rollback. The retention journal accepts the
same bounded 100,000-ID set that its 8 MiB secure-file ceiling can encode.
Precommit deletion removes only the exact journaled Settle state and
aborts on a concurrent replacement; rollback never overwrites a newer state,
while postcommit privacy cleanup always removes late state for every deleted
Note identity. Portable record contracts whitelist Action identity, exact
Method/Profile revisions, the path-free Source Reference when present,
participating Note revisions, attributed statements, agent-reported
actually-used Materials, Application-confirmed changes, and discrepancies.
Every new Action record also identifies its primary Target Note. Completion
accepts actually-used Material IDs only as a unique subset of the frozen,
exact-revision Material selection; merely selecting a Material never creates
use evidence. The portable record stores the Material's frozen revision and
role, not a later projection. Strict record validation cross-checks the use's
Note identity, qualified reference, role, title, and revision against its
participant fact while still retaining a later deletion tombstone as history.
For current Action runs, the protected optional representation distinguishes
retained Function-era absence from an explicit report; the Action decoder
requires the field, and record construction rejects absence instead of
coalescing it to `[]`. Schema 3 adds the closed `fidelity_completion` value:
Action permits `not_required`, `completed`, or `unverified`, while Discussion
requires `not_applicable`. Application derives that process fact from terminal
state plus exact-revision Fidelity evidence; it does not copy an Agent verdict.
Schema 1/2 record files are isolated as unsupported and remain unchanged. The
`v1` directory name continues to version this storage layout rather than the
individual JSON schema.
They have no generic metadata escape hatch and cannot encode a
protected Function ID, assembled instructions, raw key, bookmark, absolute
path, diff, token count, transport log, or window state. Strict decoding is
recursive through Note identities, fingerprints, passage anchors, line-only
Comment references, Method resources, and Source references; unknown nested fields and path-shaped
resource names fail closed rather than surviving as ignored JSON.

The Inspector's already-visible Action availability initializes the common
sheet synchronously; declared Note and Source modules load their bounded data
inside the visible sheet rather than blocking its presentation. Same-Target
availability refresh retains its rows but disables them until revalidation
finishes. The sheet submits the execution kind, semantic Profile revision, and
researcher Profile-document revision it presented. Application resolution
compares all three before parameters or authority are constructed, so an old
same-kind sheet cannot acquire broader readable roles, write operations, or
property authority after Settings changes.

Portable reads and writes combine per-process actor isolation, one
machine-local advisory lock, `NSFileCoordinator`, and descriptor-relative
no-follow access. Writes additionally use a same-directory temporary file,
file and directory synchronization, atomic rename, and exact readback.
Enumeration isolates malformed record files instead of hiding valid peers.
Store reopen removes incomplete app-owned staging files while holding the same
lock and portable coordination boundary. The lock lives below the verified
Application Support Triptych directory; it is not portable authority.

`PortableResearchDiscussion` is the single current exchange model. A
lightweight Comment statement carries only the exact Note fingerprint and a
one-based inclusive line range; it stores no selected prose or source offsets.
The Web surface keeps its textarea until an identity-bound native acknowledgement;
failures preserve the entered text, and committed-refresh failures acknowledge
the durable write without inviting a duplicate. Review resolves rendered text to
its real Markdown source line only as transient input.
Older passage statements retain their exact anchors for compatibility, and the
participant list may also contain whole-note or focal Note context. Appending a turn rewrites only that active
file; closing the sheet performs no storage action. Finish validates current
participant revisions, creates exactly one `kind: discussion` record, and
removes the active file under the shared coordination lock. A matching
active/finished pair left by process interruption is reconciled on reopen;
conflicting pairs fail closed. Anchor refresh reattaches only at one reliable
source location and otherwise records `needsReattachment`. Permanent deletion
purges active Discussions containing the deleted identity and retains finished
records with a participant tombstone. Passage continuation resolves the
current path from the stable primary Note identity instead of retaining a
historical path. A machine-local deletion marker shares the portable advisory
lock so another Scholium process or helper cannot create or advance an active
Discussion after deletion has entered its committing transaction.
If synchronization introduces more than one active Discussion for a primary
identity, the store reports every conflicting file, all ID-addressed reads and
mutations fail closed, and the workspace publishes no active Discussion row
until the conflict is repaired.

`LocalResearchExecutionStore` owns one schema-v2 file per Action run at
`Application Support/Triptychs/<id>/research-execution-v2/`. It may retain the
protected Function snapshot, assembled instructions, grant digest, static
Discuss transport contract, and completion evidence. Scholarly Discussion
turns never enter this private execution file. Raw grant keys remain non-Codable and are
delivered only in memory. Completion authorization for a new Action consults
only this store, so a matching legacy grant cannot authorize it. A write
report, consumed grant, completion, and submission digest advance in one
atomic replacement of their single run file; there is no durable
completed-grant/missing-completion intermediate state. Permanent
Note deletion preflights this store and, after the commit decision, removes
every execution containing the deleted Note or its associated Critique;
finished portable records remain under their separate tombstone lifecycle.

Every new preparation path writes Local Execution v2 and creates one portable
record only after a terminal validated nonconversational completion. It never
writes `research-activity.json` or `dialogue.json`. Legacy activity, Dialogue,
binding, and grant files are not migrated, rewritten, or imported as current
authority. Legacy Comment and Dialogue content is no longer projected into the
current exchange model. No decoder, projection, recovery workflow, or product
entry exposes those pre-production files; their bytes remain untouched.
Critique preparation
writes a machine-local handoff intent under
`research-execution-v2/critique-handoffs/<run>.json` before its portable
association becomes staging. The intent contains only Triptych, run, an
optional legacy checkpoint identity, and the canonical digest of the frozen
snapshot plus prepared instructions.
Portable prose can create the exact Local v2 run after interruption only when
the complete Critique invariants and that machine-local digest match. Missing,
remote, changed, malformed, or
conflicting evidence remains portable testimony with a health issue and cannot
grant execution authority. Exact duplicate staging is reconciled
deterministically, and completion retry idempotently repairs missing actionable
findings.
Discussion agent replies are appended only to the portable active exchange;
completion validates that attributed evidence, while Finish remains a separate
researcher action with no legacy activity projection. The production Action
surface uses the public role matrix and declarative Profile modules. The
independent record browser consumes only finished portable records. Application
comparison resolves each recorded
start and end fingerprint independently from an exact current snapshot,
machine-local prewrite recovery object, or checkpoint file. If either digest
cannot be matched to retained bytes, comparison is unavailable. The line
projection is non-Codable, created only after an explicit request, and discarded
on close, selection change, or cancellation; no diff hunk enters portable or
machine-local record storage.
While any active Discussion exists, the current document surface rereads the
portable projection at a bounded interval. A cooperating CLI reply can
therefore update current state while the Discussion sheet is closed. Selecting
Discuss opens a Method-bound exchange directly. A Comment-only draft instead
passes once through the ordinary Action resolver, reuses its stable Discussion
ID as the Local-v2 run ID, and atomically adds the exact Action/Method identity
and request statement without losing earlier Comments. Subsequent handoffs
reload that run's machine-local instructions. Actions has no duplicate
active-Discussion row. A finished
or removed record dismisses the stale route.

Current Action opening flushes only the current editor registration. The Action
request carries the execution kind shown in the sheet, and Application
resolution rejects a changed kind before preparation. No current Action creates
an automatic whole-Triptych checkpoint; each mediated repository write instead
prepares, verifies, and retains only the exact bytes it actually displaces.
`WorkspaceStore.flushEditors(in:)` remains for explicit Triptych-wide lifecycle
operations and invokes at most one aggregate registration per window.

Rendered function input keeps three typed layers distinct: `taskDirective`
contains the explicit public Action, its validated native parameter values,
retained Function transport, read/write
sets, the safe source reference when Analyze applies, a separately typed
Critique-output binding when applicable, and exact loaded Skill
package/resource revisions; a validated
`methodContract` supplies bounded method guidance; and provenance-labelled
`researchData` carries Markdown, YAML-derived values, citations, bibliographic
metadata, and records only as serialized data. The machine-local Function
snapshot embeds the complete schema-v2 Action snapshot. The agent-facing
directive receives the resolved Action and parameter values but not the full
Profile document or its storage revision; neither Skill prose nor transport
text may reconstruct or enlarge that frozen Application authority.
Researcher Skills may change
method, never fingerprints, checkpoints, conflict handling, containment,
recovery, or typed permissions. Agent completion is revalidated against those
Application-owned constraints regardless of text found in any data field.

For an Analysis Target carrying canonical `zotero_item_key`, preparation reads
that exact item once through Application's local read-only `ZoteroOperations`,
adds `scholium-zotero-integration` to the resolved phase, and embeds a labelled
`ZoteroBibliographicContext` in the durable `ResearchFunctionSnapshot`.
Warnings are data in that snapshot and never fail preparation. Resume reuses
the stored context; a new run rereads Zotero. No fetched field enters Markdown,
Inspector, Search, or a cross-task metadata cache.

Analysis Develop now maps to Analyze before preparation and requires one
freshly resolved source binding before and after checkpoint/Method resolution,
again on delivery, and before completion. A legacy Analyze snapshot without a
safe source reference remains decodable evidence but cannot resume or complete.
Topic Develop remains Synthesize and has no source requirement.
The assembled machine-local delivery packet may include the validated absolute
file path as a transient locator; the durable `ResearchFunctionSnapshot`
retains only `ResearchSourceReference`. Application exposes bind, inspect, and
remove operations; the production Action sheet connects the native local-file
picker and its repair route through those operations. A bounded in-sheet Zotero
attachment chooser is not yet connected. For the Zotero route,
`ZoteroOperations` permits only exact bodyless
loopback GETs, refuses redirects, verifies the exact response URL, parent and
attachment keys, absolute query-free local file URL, and exact selected path,
and repeats that identity check through completion. Permanent note deletion
preflights this private store before mutation and removes the note's locator in
the committing recovery phase. Zotero unavailability blocks this source route
even though ordinary bibliographic metadata warnings remain nonblocking.

Write preparation records only a pending Fidelity handoff. Post-edit completion
stores the final Target fingerprint as `awaitingFidelity`; Application creates
or reuses an independent read-only child with the same inputs. An agent must
submit its evidence. Parent advancement validates and links that child (or
identical completed evidence); direct write-run Fidelity outcomes are rejected.
Exact evidence keys prevent duplicate storage or scheduling.

Core separates Skill discovery/bindings (`ResearchSkillTransactionCoordinator`), machine-local
source access (`ResearchSourceAccessStore`), dependency and
instruction assembly (`ResearchWorkflowAssembler`), checkpoints
(`TriptychCheckpointStore`), portable Discussion, Critique, and Research Record
storage. The clean cutover retains no Research Activity decoder/store, Human
Review, Qualification, pre-Function Dialogue, ResearcherComment, or app-owned
Annotation store; unsupported pre-production files remain unread and
repositories alone mutate revision-checked source.
`RecommendedBibliographyStore` alone owns its atomic portable JSON and never
mutates notes or Zotero. No omnibus function store exists.

CLI decodes Contracts, invokes the same Application use cases, and encodes the
canonical Action and bibliography command families. No pre-1.0 aliases remain.
`AgentCommandAction` uses argument vectors; CLI rendering never owns
eligibility, Skill routing, checkpoints, write sets, or shell command strings.

`CommandLineToolInstaller` is an app-wide Application capability. It verifies
and atomically copies the packaged `Contents/Helpers/scholium` executable into
the user-local command directory and refuses symbolic-link destinations. The
Settings feature receives status/install closures only; SwiftUI does not copy
executables or inspect the filesystem. Packaging and QA scripts build and sign
the app and its helper together.

Application-icon identity is product-owned by
[Specification §19.5](../Specification/08-design-system.md#195-application-icon), not by
SwiftUI state, document Appearance, or a runtime resolver.
`Tools/Packaging/ScholiumIcon.icns` is the sole derived bundle icon named by
`Tools/Packaging/Info.plist`. Debug, QA, and release assembly copy that same
repository resource; no build lane synthesizes or selects an alternate icon.

All SwiftPM scratch and Xcode DerivedData live in isolated lanes beneath the
ignored repository-local `.build/`; none may use `/tmp`. This requires the
checkout to remain outside File Provider-managed locations.

Per-window `ResearchController` owns a `ResearchActionController` containing
only the selected public Action/Profile, draft inputs,
progress/cancellation/errors, presentation identity, and stale-response tokens.
A narrow client composes document flush/selection capture with async use cases;
the controller owns no repository, filesystem, document controller, protected
Function identity, or authoritative research data. Its published presentation
is observed directly and is not forwarded through `ResearchController`.

Recommended Bibliography follows a separate Triptych-library capability
boundary:

```text
SidebarRecommendedBibliographySection (fixed Sidebar utility outside Source List scroll)
        ↓ compact presentation values and closures
RecommendedBibliographyController (one window)
        ↓ RecommendedBibliographyClient
RecommendedBibliographyUseCases (Contracts)
        ↓
RecommendedBibliographyCoordinator (Application)
        ↓
ResearchSkillTransactionCoordinator + RecommendedBibliographyStore + Zotero read adapter (Core)
```

The controller is a sibling of `ResearchActionController` under the
per-window `ResearchController`. One `RecommendedBibliographyScope` freezes the
Triptych identity and the exact revisions of researcher-selected active Notes;
those Notes are focal source context, not a second durable owner. The portable
store exposes one Triptych overview and permits one active request regardless
of current Scope, Location, selected Note, or window. Application snapshots the
complete Source Analyzer method, validates completion tokens and
evidence, and performs conservative duplicate discrimination without note or
Zotero mutation. Bibliography views observe this controller directly; its
changes are not forwarded through the research-record owner. Core owns portable storage,
package resolution, path safety, and matching inputs. The App owns goals,
purpose, focus, stale-response rejection, refresh presentation, and compact
rows. Candidate rows route only to a matched Analysis or Dismiss; they no
longer open Zotero directly. Prior results remain visible through refresh and
failure.
