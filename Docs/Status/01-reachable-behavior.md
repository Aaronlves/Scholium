# Implementation Status: Reachable Behavior

Part of the canonical document set rooted at [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md).
This chapter owns reachable behavior, boundaries awaiting acceptance, and retired product surfaces; sibling chapters do not restate it.

## Reachable target behavior

### Triptych and storage

**Current reachable boundary**

Multiple registered Triptychs use independently chosen Analyses, Topics, and Works; each window
belongs to one Triptych. Portable control state stays beside Works in `.scholium`; machine/derived
state stays in Application Support. The atomic v2 registry does not import the retired
single-workspace registry.

### Application storage bootstrap

**Current reachable boundary**

D-104 is reachable: production composition validates the real per-user Application Support root
before constructing `WorkspaceStore` or `WorkspaceRuntime`, has no temporary or implicit read-only
fallback, and disables workspace commands in Storage Unavailable. The nonmodal app-root failure page
provides default Retry, selectable Details, and Quit. Debug/QA isolation requires an explicit root.

### Exact source

**Current reachable boundary**

`VaultDescriptorAccess` now holds a root descriptor per operation, walks parents with no-follow
`openat`, opens leaves nonblocking/no-follow, and accepts only immediately `fstat`-verified regular
files. Loads, fingerprints, precommit checks, readback, and recovery verification use this boundary.
Existing-file commits hold the original FD, copy and verify metadata, preserve advancing content
mtime, synchronize staging and parent, and use inode-guarded swap-back plus retained evidence on
uncertainty. ACL and ordinary xattr/Finder-tag values remain exact; a valid system-managed
quarantine envelope newly attached to an unquarantined staging inode is retained, while an existing
quarantine attribute may normalize only its agent and forward-moving timestamp with flags and event
identity fixed. Focused Core tests reject malformed or ordinary xattr additions, quarantine removal,
and quarantine authority changes. A real `NSFilePresenter`
coordination proxy proves that a provider-side replacement before writer grant
becomes a conflict with exact expected/candidate recovery. `SIGKILL` subprocess fixtures at staged
and post-swap boundaries prove deterministic repository reopen, one canonical revision, exact
prewrite recovery, hidden staging exclusion from Library inventory, pre-swap candidate-journal
retention or post-swap journal completion, and a subsequent save. Startup replay now reads canonical
source through the descriptor boundary and no longer deletes a distinct uncommitted candidate merely
because the old expected revision remains canonical. The existing Recovery sheet now lists each
exact-valid retained candidate with vault/path/revisions and read-only source, Copy, Finder reveal,
and revision-checked Restore. Core revalidates the displayed transaction fields and no-follow
recovery bytes; Window flushes every Triptych editor before Application invokes the ordinary
repository save, and a changed/missing/unverifiable source fails closed without consuming the
candidate. Focused Core and Application fixtures pass; direct human, real File Provider domain,
packaged-process termination, and assistive-technology recovery acceptance remain open.
`FilePresence` treats only `ENOENT` as absence. `FrontmatterPatchPlanner` validates complete Yams
semantics and requires a unique bounded plain key: scalar edits change only the value token, the
role-aware Research Unit uses bounded member/array replacements, and missing keys append only at a
proven block-mapping boundary. Ambiguous YAML returns a typed Source-directed refusal without byte
changes.

### Refresh and disposable projections

**Current reachable boundary**

One `WorkspaceRefreshCoordinator` serializes prepare → Search transaction → snapshot publication;
monotonic request IDs, merged request payloads, and waiter-scoped cancellation prevent overlapping
builders. One actor-isolated `WorkspaceSourceOperationGate` gives source mutations and refresh
cycles mutually exclusive leases, removes a cancelled pre-acquisition waiter without granting later
authority, and buffers watcher invalidations across file/identity migration. It does not revoke an
acquired transaction or add an actor hop. Each pooled vault owns one rebuildable
`VaultSourceCatalog` of exact documents, descriptor-observed metadata, source versions, semantics,
and source-bound Search projections. Ordinary changes reread/reparse affected notes; event loss/root
discontinuity requests full reconcile. Three independent catalog actors may prepare immutable
generations concurrently inside the one cycle; Graph, Search, and publish remain ordered. Snapshot
assembly reuses the same generation's fail-closed resolved identity and fingerprint-bound title
projection. Graph still rebuilds completely, `WorkspaceSnapshot` remains intact, and Search v6
applies a transactionally persisted, generation-checked delta in one database per Triptych; stale
generations remain rejected after reopen. UTF-16 projection cursors are linear, and privacy-safe
counters cover enumeration/read/parse, graph, Search, snapshot/source size, Application publication,
and MainActor delivery.

### Lifecycle and deletion

**Current reachable boundary**

Direct New Note creation, duplicate, move/rename, Set Aside, Trash, exact-path Put Back, and
permanent deletion route through Application and `VaultRepository`. Library Add/File/keyboard create
an empty untitled note at the current vault root; an ordinary folder context action creates in that
folder. Creation claims the first unoccupied default path atomically, refreshes and selects it
within one serialized document transition, and opens no sheet. Identity-dependent interface commands
now carry one `NoteLifecycleTarget` containing the vault-qualified document ID, stable Note ID, and
exact revision through the complete call chain; Application re-resolves that identity under the
source mutation lease and rejects a reused path. Put Back is a direct reversible row command with no
sheet and no unrelated editor flush. A committed category move removes the moved Note's document
page and clears its current presentation; selecting it explicitly in Library, Set Aside, or Trash
still opens the exact content. Deletion removes the Note, current Critique, machine-local prewrite
recovery and execution, stable identity, active Discussions, and affected checkpoints; finished
portable records retain a tombstoned participant instead of being silently erased. A durable
higher-level deletion journal restores pre-commit state or completes post-commit privacy cleanup;
concurrent path recreation is preserved for explicit recovery. The focused Application
identity-drift test and QA journeys cover reused-path rejection, current-note Trash to empty
Document, lifecycle browsing, hover-native exact-path Put Back without a sheet, stale-hover
teardown, and current-note Set Aside to empty Document followed by explicit Set Aside browsing.

### Move and import

**Current reachable boundary**

Confirmed moves preflight destination and incoming-link revisions and rewrite only identically
resolved links. Stable identity/records follow confirmed moves or reconciled external renames;
ambiguity requires confirmation. Proven source commits return their committed value with separate
derived-refresh and identity-recovery warnings across Application, GUI, and CLI, so post-commit
repair never invites a repeated mutation; identity-dependent window actions remain unavailable when
identity migration needs recovery. Create, import, and duplicate no longer discard an exact rollback
failure after identity setup fails: a proven retained source becomes a committed identity-recovery
outcome, while unreadable presence is reported as explicitly uncertain. D-132 imports regular UTF-8
Markdown directly into the current Scope's vault root, preserves exact source bytes and the external
original, and resolves collisions without replacement. Multi-file import attempts each selected
source independently, reports exact partial failures, aggregates derived-refresh and
identity-recovery warnings across committed files, identifies already committed imports as
nonretryable, and stops remaining files if the owning window closes or switches Triptych instead of
routing them through replacement capabilities. Root-level Notes are ordinary Library Notes; the
former staging/classification APIs, UI, CLI alias, and transaction roles are absent. Existing legacy
staging bytes are left untouched and invisible. Focused contract, fault-injected refresh,
creation-rollback, CLI-boundary, exact-byte, collision, batch-presentation, and window-lifecycle
tests pass; direct multi-file UI acceptance remains open.

### Settlement, Discussion, and Critique

**Current reachable boundary**

Settle is a researcher-owned, fingerprint-bound, replaceable current judgment stored as one portable
file per Note; it is not an application-authored event history. Before that portable state commits,
the current Note's exact bytes are pinned in machine-local recovery; the same stable Note and
fingerprint reuse one pin. Repeating Settle can update rationale/date and backfill a missing pin
without duplicating identical bytes. Changed Since Settled is derived directly from the current
Markdown revision during snapshot assembly; the unused `PendingResearchState` delivery contract and
projection are absent. Review alone saves a selected-range Comment directly as one researcher turn
containing only the stable Note, current fingerprint, and inclusive line range; Edit and Source have
no Comment route. The composer closes only after write acknowledgement and retains its text on
failure. Comment opens no sheet or agent handoff. The first Discuss on a Comment-only draft resolves
the editable Discuss Method/Profile into the same Discussion and current Run; later handoffs reload
those frozen machine-local instructions. Bound Discussion reopens directly, and no duplicate
active-Discussion row appears in Actions. Finished Discussions remain Research Records and are not
silently injected as Critique evidence. Written annotation remains authoritative Markdown or a
semantic Callout. D-105 cleanly removes Human Review, Qualification, ResearcherComment, app-owned
Annotation, pre-Function Dialogue, and their stores, decoders, migrations, recovery, Search, and UI
paths. A Work retains one attributed current Critique under `Works/Critiques`; Action-backed
Critique execution uses the recoverable authenticated Run handoff and idempotently reconciles actionable
findings, while Accept/Reject/Rebut and researcher Complete Round remain separate scholarly
decisions.

### Research Action contract foundation

**Current reachable boundary**

Contracts expose bounded Action IDs, public execution kinds, Action-specific Target roles, the
closed `PlatformActionCatalog`, a unified native parameter model, fail-closed schema-3 Action
snapshots, and a separate record identity that permits only schema version plus Action ID. The
academic Profile document stores only bounded flat text/single/multi-choice input and Result fields,
visible name/order/enabled state, and role-valid placement. Platform selectors, readable scope,
operations, Properties, recovery, and permission no longer occur in Profiles. Registration schema 2
binds each Action to one opaque key, display name, current primary Markdown, optional Skill-folder
marker, and enabled state. Portable registration contains only a `.scholium`-relative location or a
`machine_local` marker; absolute paths and security-scoped bookmarks live only in the Triptych's
private Application Support locator store. Application resolves and rechecks these owners, then
freezes the exact target, Method text/revision, ordered Practice text/revisions, Profile revision,
Result Contract, read scope, and initial Bounded Write Set entry. One Triptych collaboration policy
is evaluated separately. Neither Method prose nor Profile state can grant machine authority.

### Agent connection and Bounded Write Set coordination

**Current reachable boundary**

`ResearchConnectionCoordinator` owns one-time Pairing Codes and process-generation-bound Connection
Sessions. Codes and secrets use independent Security-framework randomness; only digests and typed
bindings are retained. The supported bridge location is the App Group container and contains only
the protected AF_UNIX socket plus minimal rendezvous state. Pairing is the sole unauthenticated
operation; Context, read, write-set extension, write capability, result, continuation, reload, end,
status, and cancellation require the Session secret through stdin or another hidden channel. The
copied Agent handoff contains the Run locator/route, one-time Pairing Code, and Agent-owned CLI
steps, but no method text or local path. The code is available only inside that complete copied
handoff rather than as a separate visible or accessible field. Copy New Handoff invalidates the
prior pairing and copies its replacement while preserving the Run and recovery state; the Agent
enters the code only through pairing stdin.
The code and credential are non-Codable and redacted from descriptions; only the typed copied
handoff exposes the one-use code, while private bridge/storage adapters handle exchange and Session
bytes. Session schema 3 returns the frozen exact
Method/Practices, Result Contract, and a capability-free view of the current Bounded Write Set only
after authentication. Re-pairing one Run revokes its prior write-capable binding, application restart
invalidates every Session, and the durable Run remains. `scholium agent end`
authenticates before cancellation, revokes the Run, retains recovery truth, and
removes the acknowledged protected CLI credential.

Bridge request schema 9/response schema 11 also carries the separately paired
Method-improvement boundary. An explicit Record action installs one current
improvement Run on the parent Local Execution record and freezes the unchanged
comment, finalized Result fingerprint, registration, primary Method, linked
Practices, and exact revisions. Authenticated `method-context` exposes only
those targets; `improve-method` may replace one target or save one no-change/
unavailable diagnosis. Replacement uses a non-Codable, nonreusable capability
bound to Run, Session, request, target, expiry, and expected revision before
the existing exact configuration transaction and previous-edit recovery point.
Interruption after commit reconciles without another write. Completion clears
only unchanged feedback and retains one local terminal receipt, not a queue,
history, portable opinion, or second knowledge owner.

Each Local Execution schema-8 Run embeds one Bounded Write Set. Its initial object is inserted at
preparation. An extension request binds one bounded proposed set to exact Triptych/Run, stable or
reserved identities, roles, operations, expected fingerprints/proven absence, expiry, and attributed
reason. The existing exact-window native sheet permits a subset, continues without changes, or
cancels; Ask Me Every Time, Ask Me Only for Works, and Full Triptych Access are evaluated from the
same current Triptych policy. Even Full Access only admits machine-validated Run members. Every
actual write still receives a separate nonreusable short-lived capability bound to the Session,
complete allowed-set digest, one member, one expected revision, and one idempotent operation ID.
The former coordination key, allowed correlation plan, per-document child Run, activity grant, and
parent/child execution lineage have no current decoder or route. Synthetic UI evidence does not
certify genuine VoiceOver, Full Keyboard Access, installed IME, localization quality, or researcher
visual acceptance.

### Analyze source access

**Current reachable boundary**

`ResearchSourceReference` schema 1 retains only route, stable source identity, exact Zotero
item/attachment keys where applicable, display filename, and fingerprint. A per-Triptych single-link
mode-0600 Application Support file alone retains read-only bookmark and canonical path;
descriptor-relative traversal rejects owned-path symlink, hard-link, nonregular, permission, and
substitution attacks. Source hashing is bounded to the opened starting size and rejects concurrent
change. The exact Zotero route refuses redirects, requires its original loopback response URL and
absolute query-free file URL, and rechecks parent, attachment, selected path, source revision, and
current nonempty Analysis key. Prepared and legacy Analyze runs fail closed on delivery and
completion when exact source authority is absent. Permanent deletion preflights store health and
removes its machine-local locator through the deletion recovery boundary. The production Analyze
sheet now keeps a source-repair Action reachable while execution is disabled, accepts one
researcher-selected local regular file through the native Open panel, re-resolves availability after
binding, and shows only the safe filename. Packaged-sandbox reopen of a researcher-selected external
source and an in-sheet Zotero attachment chooser remain unverified.

### Research Actions and protected execution

**Current reachable boundary**

One per-window Inspector exposes Overview, Connect, and Actions; Document has no Research Strip. The
Inspector, Research menu, focused keyboard route, common modular sheet, CLI, and authenticated bridge
use public Action identity only. Availability is target-bound, and late results cannot become
actionable. Opening saves only the current initial-object editor and presents the academic Profile
while declared Note/Source dependencies load. Preparation rechecks Action, target, focal Materials,
source, registration, exact Method/Practices, Profile, collaboration policy, repository, and recovery
readiness without flushing unrelated Notes. It creates one Local Execution schema-8 Run, freezes the
Result Contract and method context, and inserts the initial object into its Bounded Write Set. There
is no automatic whole-Triptych checkpoint; each confirmed mediated write preserves Before Agent Work
exact bytes for that Note.

The window controller now separates active preparation from cancellation
recovery. If presentation invalidation rejects a noncooperative preparation or
late initial handoff before delivery, it attempts one background cancellation;
failure creates neither a researcher recovery row nor a global Action barrier.
An interrupted explicit End Action cancellation still blocks replacement
Actions and remains independently retryable, preserving Session, transaction,
and recovery truth until Application cancellation succeeds.

The authenticated Agent may query the one Application Research Context across Search v6, exact Note
read, direct Graph relations, Properties, Records, and explicit researcher state. Source Reference
envelopes keep owner, identity, revision, locator/range, scope, currentness, evidential layer,
retrieval reason, and limitation separate. Response schema 2 also retains each Note's typed Search
match reasons, including direct-relation direction and exact occurrences and Property source ranges;
research text is data, not an instruction source. Result submission
must satisfy the frozen academic fields and Context Use references. The current
Application retains no delivered-reference registry: it authenticates the Run,
checks each reference's authorized scope, and revalidates the current owner,
revision, locator, and owner-specific provenance fields. Application adds machine fields
from actual transactions and finalizes idempotently only after every initiated write has a known
outcome and recovery responsibility is satisfied. Portable Record schema 5 retains the immutable
finalized-result partition, minimal Method provenance, exact participating revisions, Context Use,
confirmed changes/discrepancies, Fidelity completion, and Analyze-only Literature Recommendations.
Other Actions reject recommendations. Unsupported Record schemas/fields have no compatibility
decoder. Fidelity completion records that declared checks ran, not truth, quality, or acceptance.
Analyze resolves one exact source; its path remains machine-local and transient.

The return window and Record detail share one Researcher Evaluation editor. Evaluation and bounded
Method-feedback updates compare the exact Record, expected subrevision, and immutable finalized-result
fingerprint under the portable-record lock. They cannot overwrite Agent results or create a second
evaluation store. Explicit Settle and explicit adopted/kept/rejected dispositions remain attributable
researcher state; opening, selection, dwell, silence, and rank never become commitment.

### Action write scope and Fidelity

**Current reachable boundary**

The initial object is one exact member, not a Triptych-wide write grant. The common Action sheet
presents its current fingerprint and the revalidation/checkpoint/conflict/recovery boundary. During
the same Run, an authenticated Agent may request a bounded set of additional existing or reserved-new
documents. Admission is atomic for the approved subset; each later mutation names one member and one
idempotent operation. Application reauthorizes current identity, role, operation, expected revision
or proven absence, containment, Session, expiry, and complete-set digest before the sole repository
transaction performs exact read/compare, Before Agent Work recovery, final recheck, atomic replace,
and readback. A conflict or unknown outcome affects that member and recovery duty without widening
any other authority. **Continue Research** creates a separate Run for a new Action/method purpose;
it is not an authorization layer or a child write phase.

### Recovery and chronology

**Current reachable boundary**

Researcher-created self-contained checkpoints support comparison, selective/full restore, and Finder
access; retained legacy automatic checkpoints remain recoverable but are not created by current
Actions. Core keeps a non-delivery SQLite/immutable-object prewrite ledger with v1 preservation,
corruption quarantine/rebuild, remap, temporary retention, deletion tombstones, and settled-version
pins. Durable pin manifests own exact-byte identity and per-Note monotonic order; a common advisory
lock and unique index coordinate allocation, while one-transaction UPSERT replaces a derived SQLite
row when any manifest field differs. Exact-valid manifests protect bytes even when projection is
ambiguous; that condition blocks new recovery writes and all automatic cleanup. Portable replacement
distinguishes proved pre-rename failure from commit uncertainty, so only the former can roll back a
new pin. Machine-local per-Triptych policy retains 10, 30, 50, or no automatic limit per stable
Note, defaults to 30, and requires an exact-ID preview before a lower limit removes older pins. The
approved set remains in a bounded 8 MiB journal until cleanup completes. Terminal validated
nonconversational Action runs create one whitelisted portable record under
`.scholium/research-records/v1/records/`; it records the Action rather than its protected Function
and recursively rejects undeclared fields and path-shaped nested values while excluding prompts, raw
keys, bookmarks, absolute paths, diffs, token counts, transport logs, and window state. Portable
active Discussion now uses one file under `active/`, and Finish creates exactly one neutral finished
record with interruption reconciliation. Corrupt peer files are isolated. The independent
list/detail window now provides confirmed direct record deletion and disposable exact-byte
comparison; settled-version restore UI remains later work.

### Application and CLI

**Current reachable boundary**

GUI and CLI share Application capabilities and trust rules. Each CLI invocation uses one snapshot
runtime; existing-note mutations require current SHA-256. App/CLI import only Contracts and
Application, Core remains internal, one live app runtime has one accepted event subscription, and
per-window controllers own independent presentation state.

### Connections, Search, and Attention

**Current reachable boundary**

One workspace `GraphSnapshot` owns Vector-Link v3 resolution: bare links remain neutral, `+` and `-`
mean the containing Note supports or opposes the target, and `?` records undirected incompatibility.
Graph contract 5 preserves exact markers and anchors, derives only support/opposition inverse views,
and invalidates the retired directed-Questions projection. Connect groups each Triptych-role section
by relationship, shows one direct SF Symbol per cluster rather than per Note, and keeps both the
major heading and bounded current-cluster symbol sticky in its single scroll owner. Major headings alone
carry counts; rows retain pointer help, keyboard activation, VoiceOver relationship names, and the
named source-anchor alternative. Neutral/transitive paths never become evidence and retired syntax
remains exact with diagnostics. Search contract v6/schema 9 uses one normal-content SQLite FTS5 Note corpus
per Triptych and one Application-owned projection over exact-byte-fingerprinted portable Research
Records. GUI, Research Records, and CLI share one provider router and typed query semantics. This
Note occurrence Search still reads the unsaved editor snapshot. Top-level Property presence/exact-
string clauses retain source ranges and empty/type identity; direct relation clauses consume only
same-manifest explicit Graph edges and replace the retired parallel Related Search path. The
canonical YAML `summary` is an optional document declaration with its own source range and match
reason; mediated writer attribution stays in the owning operation/Record rather than a second YAML
field. A summary match only discovers the Note and rolls back into exact full
source rather than becoming a summary-only Research Context result. No index, Record, or machine
state can backfill or overwrite it. The removed `status` and `review` fields have no semantic projection, filters, or ordering; `status:` and
`review:` fail explicitly without affecting ordinary lexical search. Search field/canonical-value
completion and deterministic Explain Query use the same capability table; scope-specific Property-
key and Note-identity candidate delivery remains deferred. Attention is limited to specified
structural, currency, connection, reliance, metadata, and
identity conditions. Material Changed Since Use is rebuilt only from the latest completed Synthesize
record for each Topic/Material pair whose fully cross-validated actually-used Analysis revision
differs from the current active resolved revision; unused, deleted-record, tombstoned, deleted,
contradictory, and unresolved inputs do not qualify. D-129 presents the existing derived queue in
one transient native popover owned by the exact Workspace, grouped by Identity & Metadata, Structure
& Connections, and Revision & Reliance. Sidebar and Inspector route to the same session without
showing statistics in ScopeIndex or the Document toolbar; Inspect dismisses before opening the Note
in the owning Workspace without global search or notification. Timed Dismiss,
latest-record-revalidated Resynthesize, and revision-pair-bound Leave Unchanged express no verdict
and never mutate the Topic or record. Revision-bound keys include Triptych identity, and Settings
can restore timed or revision-bound machine-local presentation decisions.

### Editor

**Current reachable boundary**

CodeMirror-backed Edit/Source and sanitized Review share one checked semantic projection and the
same callout, table, footnote, math, preview, font, and presentation contracts. Generated callout
roles are accessibility-only; supplied titles inherit role styling. One retained Host keeps Review
and one CodeMirror state mounted; stable internal identifiers remain `read`, `livePreview`, and
`source`. One atomic Document state now separates active mode from restoration intent and
retained-surface lifetime; the Web bridge accepts only the editor-specific Edit/Source type.
`MarkdownEditorSession` publishes one readiness/document-phase snapshot, serializes mode
convergence, and stages initial input without publishing during WebView construction. Its adapter
retains only a one-way input diff cache and no longer initializes or recovers mode from a parallel
field. Bridge v9 preserves exact source, identity, recovery, focus, scroll, and nonmutating UTF-16
Search-result reveal while coalescing selection reports. An established editor remains visible
during Edit/Source reconfiguration, and CodeMirror applies the complete mode compartment atomically.
Source retains exact-source typography without semantic rich styling; explicit selection no longer
highlights matching text elsewhere, and adjacent Markdown brackets no longer acquire a
selection-like match background. Its active-line treatment now applies only to a collapsed caret,
so a triple-click selection ending after a line break does not paint the following logical line;
losing window focus no longer rebuilds Live Preview from a hidden viewport. Edit's compact selection toolbar exposes the approved common Markdown hierarchy through a
neutral separator boundary, shallow shared floating-control elevation, and direct, quiet monochrome
SF Symbols; its custom menus use the deeper bounded-panel role. Both it and Review's separate direct
line-only Comment bar remain hidden until pointer selection finishes. Review remeasures the retained
Comment selection into a document-coordinate anchor so its bar or open field remains attached to the
passage while scrolling, and remeasures that anchor on viewport resize. Leaving Review now
deactivates that surface explicitly: an empty composer clears, while an authored or pending draft is
suspended in the retained page without focus and can resume on return. Saving remains read-only and
live-announced rather than disabling the focused field. Edit separates toolbar content equality from
geometry equality, so scroll and viewport changes remeasure an unchanged selection; one pure geometry
owner centers, clamps, and flips the bar, and is also reused by the separately dismissed Edit preview.
Shared Read/Edit previews now use one opaque bounded-panel surface and close on scroll, resize, or blur.
Edit now also mounts one CodeMirror-owned bounded-panel suggestion surface:
`[[` queries the generation-owned Workspace catalog as characters are typed,
shows title plus bounded path context, excludes ambiguous noninsertable targets,
and consumes existing closing brackets without duplication. A bare block-safe
`/` shows only Callout, Date, Inline Math, and Mermaid; further input fuzzy-filters
the complete nine-command insertion catalog, while prose limits the initial list
to Date, Inline Math, and Footnote. Source, marked-text composition, and protected
syntax own no suggestion overlay. The same Arrow/Return/Escape and pointer paths
retain the CodeMirror caret; each accepted result is one Undo transaction.
Edit and Source hide WebKit's native caret and use one CodeMirror cursor layer,
while source-character marks remain the only range paint; deleting a
structurally inserted line cannot leave a second caret at its obsolete Live
Preview baseline.
Inactive Edit lists retain their semantic marker while the caret edits prose
and reveal exact source only inside the indexed physical-line prefix. Review
and Edit share the same marker track, nesting step, and task-control geometry;
checked, unchecked, projected, and exact-prefix states keep one prose column.
Review renders disabled task controls. Edit's pointer checkbox and the
caret-line Toggle Task command share one exact-marker transition and one Undo
event across supported list markers. Left Arrow from the prose start enters
the prefix at its trailing edge without jumping to the physical line start.
Return saves, Shift-Return inserts a line, Escape cancels, and Edit/Source have no Review Comment
surface. The editor's one DOM-to-AppKit secondary-click path preserves a clicked selection, moves an
outside click through CodeMirror, and presents Cut, Copy, Paste, and Select All before any available
collapsed-construct action; the retired local right-mouse monitor, private-view menu query, Autofill,
Services, common formatting, and Preview routes are absent. Review alone owns footnote hover preview,
navigation, and
return. Edit projects inactive references as locators; one composite definition remains at its
authoritative source, keeps its marker exact, and applies ordinary construct-scoped projection only
to its body. Paragraph separator lines remain real measured source lines rather than collapsed
geometry; an authored separator now owns any larger adjacent semantic block spacing and its complete
visible area maps to that exact empty line, while source-less gap widgets remain only where no
authored separator exists. Inline clicks place one caret before delimiter exposure; a projected
Callout click commits that exact source caret and removes its widget during pointer-down, so no
intermediate boundary caret is painted below the block. Activation derives from the shared
Live-selection snapshot and keeps one quiet block surface over the complete Callout. Only the
caret-owning or selected physical lines expose exact structural markers; the other lines and nested
constructs remain projected. Return continues the exact quote prefix, while Return on an empty
quoted line removes that prefix and exits. Title-only Callouts stay visible, and a title-only Orient
projects its author-supplied title as Body without rewriting source. Source remains exact text and
owns none of these Edit-only continuation or projection behaviors.
Automated TypeScript, Swift, and real-WKWebView checks cover implemented semantics; human visual,
assistive-technology, IME, retained-memory, sustained-performance, and the current post-migration
mode-handoff experience remain open.

### Properties and Zotero

**Current reachable boundary**

Contracts now separate canonical vocabulary/ownership, default About profiles, and empty creation
requirements. Analysis uses Completion/Limitations and retains hidden title plus protected
`zotero_item_key`; Topic/Work use Scope/Limitations and H1→filename identity, with Work labelled
Research Scope. `status`, Work `deadline`, required markers, About Customize, and default disclosure
state are removed. Inspector exposes only one exact-item **Open in Zotero** action for a current
Analysis with a normalized key; it exposes no key, fetched metadata, matching, or confirmation. An
eligible Analyze Action reads the exact item once, attaches the protected Zotero integration Skill,
and stores labelled bibliographic metadata or a nonblocking warning in its immutable run snapshot;
resume reuses it and a new run rereads without cross-task cache. Bibliographic metadata remains
nonblocking, but a Zotero attachment selected as Analyze's required source is independently exact
and blocking. D-133 presents one Settings **Check Connection** action in place of the duplicate
Test/Refresh controls; **Clear Connection History** still resets only the in-memory last-successful
timestamp.

### Product Skills

**Current reachable boundary**

The code-owned Platform catalog defines seven public Actions and their machine capabilities. A new
Triptych bootstraps one current editable primary Markdown Method per Action, with Manuscript disabled,
and nine exact Practice Markdown references. Registration schema 2 is the only Action-to-Method
relation. Exact Wikilinks in the primary Method resolve Practices once in first-use order and expose
missing/ambiguous references without substitution. Each Method and Practice keeps one replaceable
pre-edit recovery point. Restore Default writes the current app-bundled primary Markdown under exact
revision checking; the bundle is never a runtime fallback. An optional ordinary local Skill folder
is represented portably only by a machine-local marker; its absolute path and security-scoped
bookmark remain in private Application Support, and authenticated delivery exposes only the frozen
path string. Scholium neither inventories nor reads sibling folder content. No catalog YAML,
package/version/digest/dependency/resource schema, package history, installer, resolver fallback, or
protected Skill-ID collision path remains.

### Research Skill registration

**Current reachable boundary**

The researcher can create one simple primary Markdown under the Triptych control root, select one
external Markdown file, or select a primary Markdown inside an ordinary local folder. Registration
checks only the exact entry, unique Action relation, optional folder containment, and current
revision. It does not inspect method structure or enumerate the folder. Triptych-controlled locations
stay relative in portable state. External locations create one opaque registration marker and a
private mode-0700/mode-0600 locator document containing the exact absolute paths and security-scoped
bookmarks; reopening and wrong-Triptych replay tests pass. A missing, stale, changed-identity, linked,
or inaccessible primary path fails closed. A missing optional folder is reported without replacing
the primary Method or inventing a transport fallback. Schema 1 absolute-path registration is rejected
and has no compatibility decoder.

### Research Guidance

**Current reachable boundary**

Production Settings presents one restrained categorized list-detail surface for **Methods**,
**Profiles & Practices**, **Collaboration**, **Sources & Integrations**, and **Recovery & Technical**.
Methods exposes one primary Markdown per Action, enabled state, exact linked Practices, optional
ordinary folder availability, direct edit, one previous-edit restore, current Scholium-default
restore, simple creation, and external Markdown/folder registration. Profiles exposes visible
name/order/enabled state and role-valid placement; its bounded editor adds, names, reorders, removes,
and configures only flat free-text/single-choice/multiple-choice academic input and Result fields,
including excluded/optional/required status and closed options, through the one Profile-document CAS
writer. Practices exposes exact Markdown create/edit and one previous-edit restore. Collaboration
edits one Triptych rule—Ask Me Every Time, Ask Me Only for
Works, or Full Triptych Access—and explicitly states that no setting grants blanket writes or binds
an Agent/Skill. Sources owns Zotero/CLI controls and a strict Triptych citation-style selection from
the code catalog (currently APA 7); citation style is not a Method package. Recovery owns settled
Note retention only because Method/Practice recovery stays beside their editors. Typed invalidation
rechecks Actions across windows without replacing the Workspace snapshot. There is no package
installer, staged disabled copy, per-Skill permission, capability module editor, version browser,
snapshot history, **Reveal Skills Folder**, or retained binding repair path.

### Retained research workflow proofs

**Current reachable boundary**

One synthetic Debug-only PreviewCatalog remains for the modular Skill-run sheet, the current five
Research Guidance categories, and Bounded Write Set extension. It is suppressed by default
and its single QA command is available only to the Debug `com.scholium.qa` bundle with an explicit
launch argument. It owns no Workspace, Triptych, document, Skill, permission, execution, record, or
source authority and is not a production surface. Completed Sidebar, Attention, Inspector,
Action-list, generic-state, complete-window, Editorial Parchment, and paired-window proofs have no
active route or compatibility alias.

### Discuss and MCP

**Current reachable boundary**

Line Comment, whole-note Discuss, and optional focal Notes now use one `PortableResearchDiscussion`;
older exact-passage turns remain readable. A new Comment stores only its Note fingerprint and
inclusive line range, never starts an agent run, and is collected when Discuss opens the active
exchange. New Runs keep the frozen authenticated method/result transport contract in Local Execution;
attributed turns live in the portable active exchange. Close has no storage effect. Agent reply
evidence is required before a Discuss run can complete, while researcher Finish is a separate
neutral transition into one portable Research Record and creates no legacy Discussed event. External
Zotero MCP remains separate from the built-in reader; only explicit `--probe` performs its read-only
initialization lifecycle.


## Implemented boundaries awaiting acceptance

### Localization

**Implemented evidence**

English default; complete zh-Hans string catalogs, compiler-synchronized formats,
coverage/placeholder/state/compilation validation, and outer-bundle language declaration. Current
lifecycle and Sidebar UI use 搁置、纸篓、移至纸篓…、放回 plus localized Scope, Location, Attention, and note
counts, while `Trash/`, researcher titles, paths, exact Markdown, and Skill names remain verbatim.
The catalog validator and six focused localization tests pass; packaged QA also covered Bootstrap,
vault/Library/Attention labels, and native accessibility localization.

**Still open**

Researcher terminology review, long labels, and broader manual accessibility.

### Beta Agent handoff

**Implemented evidence**

The Action sheet and active Discussion each expose one Copy Handoff route. It copies the immutable
complete Run handoff for the researcher to paste into the selected Agent conversation; Scholium
does not select, remember, or open an Agent application. The prepared Action sheet exposes End
Action, and an active Discussion exposes End Discussion in addition to nonterminal Close; ending
preserves the current exchange as a finished Research Record. Focused tests cover the copy-only
presentation boundary, pairing replacement, and durable Discussion cancellation.

**Still open**

Full Keyboard Access, VoiceOver, localization, and visual acceptance.

### Properties and Research Unit

**Implemented evidence**

The role-aware targeted editor preserves absent/declared/invalid states and unrelated bytes.
Analysis accepts binary or represented-ratio Completion and/or Limitations; Topic/Work accept Scope
and/or Limitations. All fields are optional at creation, deleting one member retains the others, and
focused contract/source-fidelity tests pass. The native comparison catalog includes mixed/all-serif,
320pt/narrow, light/dark, contrast, mixed-script, long-text, empty-Connect, direct-action, and
unavailable-Fidelity cases.

**Still open**

Researcher catalog review must approve or revise the provisional typography and spacing before those
values are treated as visually settled. Complete pointer/keyboard/focus/VoiceOver, installed-IME,
and human visual acceptance remain open.

### Time and Analysis metadata

**Implemented evidence**

Creation/modification times stay in app History; existing timestamp keys remain custom YAML. Debate
Importance is an optional 0–10 whole number paired with exact Debate Scope and replaces Project
Relevance only in typed defaults.

**Still open**

No migration or normalization of existing custom keys.

### Long-source analysis

**Implemented evidence**

One source-level Analysis may record represented Completion such as `6/11`; this is a quiet reminder
rather than a chapter ledger or adequacy claim. Analyze uses the Triptych's one current registered
primary Markdown Method; source access and any mutation remain separately mediated Platform
capabilities rather than authority conferred by that Method.

**Still open**

Final Completion control and reminder presentation require human review.

### Literature Recommendations and Research Records

**Implemented evidence**

Analyze completion now requires an explicit bounded recommendation array and writes one schema-5
Research Record. Application derives stable occurrence IDs and initial Unprocessed dispositions;
other Actions reject the field. Occurrence disposition and optional researcher-note updates share
the locked atomic replacement/readback path with Pin. The Triptych Recommendations index is rebuilt
only from parent Records and groups only exact nonconflicting normalized DOI or Zotero identities.
Recommendation submissions and researcher notes now reject normalized,
percent-encoded, POSIX, Windows-drive, UNC, and file-URL machine paths before
portable persistence while retaining ordinary HTTPS bibliographic links.
Permanent Record deletion now commits a machine-local tombstone under the same
cross-process lock as portable creation/deletion, so a retained Local Execution
completion cannot resurrect the deleted Record; source access, checkpoints,
and recovery evidence remain outside that deletion.

One nonmodal resizable Research Records window is keyed by Triptych ID, reads that Triptych's
capabilities directly, and does not follow Workspace focus. Document and Research-menu requests
reapply This Note or Triptych Scope respectively; Scope and Records/Recommendations View remain
independent. Its Record filters compile to the same Application Record provider used by global
Search and CLI; the window retains no second Record matcher or flattened search corpus. Search
result locators require the exact Record fingerprint and optional statement UUID before selection.
Recommendations exposes search, Unprocessed/Handled/All, occurrence-local checkboxes,
source and Record provenance, Open Analysis, Open Parent Record, and researcher notes. Sidebar,
Attention, Settings, Method bindings, CLI, and Zotero acquire no parallel recommendation lifecycle
or authority.

**Still open**

Complete Dark/Increase Contrast/RTL/200%/VoiceOver and physical Full Keyboard Access acceptance,
plus genuine research-use evaluation of recommendation quality, remain researcher-owned acceptance.

### Method-locator isolation

**Implemented evidence**

Portable registration stores no absolute path or bookmark. A private machine-local locator is keyed
only by the opaque registration relation, Triptych-bound, strict-schema, descriptor-read, and
mode-0700/mode-0600. Reopen, exact-byte readback, stale registration CAS, wrong-Triptych replay, and
schema-1 rejection fixtures pass. Unused locator rows do not authorize a Method and are removed after
a successful replacement when their old relation is still known.

**Still open**

Packaged sandbox reopen after an external Method or folder moves, loses its security scope, or is
restored by a cloud provider remains a direct acceptance boundary; the product reports repair rather
than adopting another path.

### Architecture stability cutover

**Implemented evidence**

Focused automated suites pass descriptor and special-file rejection, inode/path races, metadata
preservation, three-state deletion, fail-closed YAML, single-flight refresh, stale Search
generation, shared-vault/per-Triptych-index isolation, incremental/full-rebuild equivalence,
multiwindow identity migration, noncooperative lifecycle completion, storage failure/retry,
research-data/Researcher-Skill injection boundaries, and the clean record-model cutover. Complete
repository verification and the current disposable Complete UI baseline are recorded below.

**Still open**

G7 approval/packaged sampling, G9 release provenance, G10 field trials, and genuine
accessibility/IME/visual acceptance remain separate gates.


## Retired product surfaces

- Proposal/Revision review sheets, Research Task/Session, Agent Assessment, and
  the former Agent Review surface.
- Human Review, Qualification, ResearcherComment, app-owned Annotation, and
  pre-Function Dialogue archives and compatibility paths.
- Active-note HTML/PDF export and Canvas.
- Zotero data-folder/SQLite access, additional-vault/All Notes presentation,
  and generated `_index.md`, `_agent-index.json`, or `_agent-context.json`.
- The inline Attention queue, Library lifecycle footer and Back route, Sidebar
  Settings destination, duplicate Folder leading symbols, and hover-only Put
  Back presentation.
- Obsolete Proposal, Research Session, workflow-bridge/readiness/lint,
  pre-release Review-store, and Add Dated Reference implementations.

Unsupported pre-release state is not read into the current interface. The
clean cutover never authorizes deleting or rewriting researcher Markdown,
unknown YAML, or unrecognized Triptych files.
