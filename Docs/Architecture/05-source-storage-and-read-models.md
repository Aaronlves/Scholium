# Architecture: Source Storage and Read Models

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Source writes,
recovery, immutable read models, and metadata.

## Vault write and prewrite-recovery boundary

`MarkdownRelativePath` is the typed authorization input for research Markdown.
It preserves display spelling, treats backslash as a literal character, and
rejects absolute paths, empty or dot components, NUL, and non-Markdown targets.
`VaultPathResolver` scopes lookup to one canonical root and uses a
volume-sensitive `VaultPathComparisonKey` only for case/Unicode collision
decisions; neither rewrites Markdown or stored display paths.

`VaultDescriptorAccess` opens one root descriptor for each top-level operation,
walks every parent with `openat` plus `O_NOFOLLOW`, and opens leaves with
`O_NOFOLLOW | O_NONBLOCK`. Immediate `fstat` accepts regular files only.
Enumeration supplies candidates, never final authorization. Vault loads,
fingerprints, precommit checks, postcommit readback, and recovery verification
all use this descriptor-relative boundary. `FilePresence` distinguishes
present, `ENOENT` absence, and inaccessible/error; only confirmed absence may
complete deletion.

`VaultMutationCoordinator` performs short `NSFileCoordinator` accessors around
that descriptor authority. Create and move use exclusive rename. Existing-file
update retains the original descriptor, writes and synchronizes one
same-directory candidate, rechecks the exact expected bytes and parent
identity, and delegates the atomic replacement to
`FileManager.replaceItemAt` inside a `.forReplacing` coordinated accessor. The
default replacement options let the system preserve or adjust standard
filesystem metadata; Scholium neither copies nor compares the complete
mode/owner/ACL/xattr/flags/birth-metadata envelope. It then performs canonical
no-follow exact-byte readback and rechecks the current parent. Only that source
authority determines whether the save committed.

Before canonical replacement can occur, the coordinator records the relative
path and exact expected/candidate fingerprints in a schema-versioned
machine-local transaction; `VaultRepository` durably persists both byte sets
before the final authorization check. A failure before replacement leaves
canonical source unchanged and removes the same-directory candidate on a
best-effort basis. A failure after replacement never initiates a compensating
source write: exact canonical readback may prove the candidate committed, while
any other state retains the transaction for recovery and reports no Saved
outcome. Successful readback makes transaction removal redundant, invisible
housekeeping. There is no cleanup-warning contract or fourth Document outcome.

The retained interrupted-save candidate contributes a workspace health issue
and a vault-qualified entry in the existing Recovery sheet. Core no-follow reads
revalidate its manifest plus expected/candidate bytes; read-only source, Copy,
and Finder reveal grant no write authority. Restore carries the displayed
vault, path, revisions, creation identity, and retained reason back to Core,
flushes all Triptych editors, and uses the ordinary revision-checked repository
save only while canonical source remains at the expected revision. Current
evidence and remaining acceptance belong to
[Implementation Status](../IMPLEMENTATION_STATUS.md).

`PrewriteRecoveryLedger` is Core-only machine state under
`Vaults/<vault-id>/save-transactions-v1/`. Each unresolved replacement owns one
small manifest plus exact expected and candidate bytes. A proven committed or
not-written operation deletes the directory immediately; only commit-uncertain
or startup-interrupted transactions survive. Unsupported pre-use bytes remain
unchanged and nonauthorizing. It exposes no versions or history API. Its one
bounded `InterruptedSaveRecovery` projection includes only exact
startup-retained candidates and remains distinct from Run-bound Agent change
evidence. `DocumentOperations` vault-qualifies listing, read-only content,
Finder location, and restore; `ResearchController` owns that listing beside the
existing durable-recovery list, while `WindowModel` owns the cross-window editor
flush and presentation effects. Startup reads pending canonical source through
the descriptor boundary. A canonical
candidate proves the interrupted save committed and completes its mutation
journal; a still-canonical expected revision retains the distinct candidate
bytes and publishes a health diagnostic instead of deleting the only
structured copy of interrupted editor work. Current mutation manifests require
their exact schema version. Unsupported pre-use machine data remains
byte-unchanged and nonauthorizing; no legacy save schema is migrated or
interpreted.

`AgentChangeEvidenceStore` is a separate Core actor under Triptych-keyed
Application Support. Each JSON record is keyed by `(Run ID, Note ID)` and binds
that pair to the Triptych, exact starting bytes/fingerprint, and optional final Agent
bytes/fingerprint. It enforces the Bounded Write Set source-size limit,
descriptor-safe storage, atomic replacement, and cross-process locking. It is
not queried as history, cannot reconstruct source authority, and is consumed
only by exact Record comparison, direct Undo, and post-Record system-Trash
cleanup.

`SecureRecordDirectory` is the Core-only descriptor-relative primitive for
bounded machine-local JSON state. It owns no-follow containment, byte limits,
atomic replacement, readback, staging/deletion recovery, and the companion
`AdvisoryFileLock` for cooperating-process serialization. Portable Records,
compacted local execution receipts, Agent change evidence, and the prewrite
ledger each retain their
own schema, path, transaction, recovery, and error semantics, and translate
primitive failures at that owner boundary. The primitive neither interprets a
Record nor becomes a writable research-source authority.

## System Trash and Record cleanup boundary

`NoteSystemTrashDeletionCoordinator` is the Core owner for one confirmed
source-and-Record cutover. `prepareNote` and `prepareFolder` bind exact source,
stable identities, revisions, complete directory manifests, managed Critiques,
active Discussions, and finished Record byte fingerprints into one immutable
preview. `WorkspaceHandle` holds the source-mutation lease and flushes every
Triptych editor before both preparation and execution. Relevant nonterminal
`LocalResearchExecutionStore` entries fail preflight.

`TriptychMutationRecoveryStore` persists the `SystemTrashDeletionPlan` before
the first filesystem call. Each source owns an independent receipt.
`VaultRepository` repeats descriptor-relative containment and revision or
manifest checks; `VaultMutationCoordinator` then calls Foundation's native
system-Trash API inside an `NSFileCoordinator` deleting accessor. The returned
URL is machine-local recovery evidence only. Original-path absence after an
interruption cannot prove Foundation success, so that receipt becomes
`outcomeUnknown` and blocks all portable cleanup.

After every source receipt is `movedToSystemTrash`,
`PortableResearchRecordStore` discards affected active Discussions and deletes
each previewed finished Record with exact-fingerprint compare-and-swap. A
durable deletion marker makes retry idempotent. Note Review activities are
pruned, then local executions and Agent change evidence are removed. Settlement,
stable identity, source-access records, Zotero bindings, and Critique
associations are not cleanup targets. Portable Record schema 12 has no deleted-
participant representation; the bounded schema-11 cutover converts ordinary
participants and turns any old deleted-participant Record into one whole-Record
deletion marker.

Watcher reconciliation, Finder actions, and sync tools cannot construct this
plan or call its Record cleanup. They publish source inventory changes through
the ordinary refresh and stable-identity diagnostics only. Finder restoration
therefore re-enters as source and may reconcile retained identity, but it never
reverses a finished Record deletion.

## Shared read models and metadata

`WorkspaceNoteSnapshot` is the shared immutable read model for a workspace
note. It carries vault-qualified identity, exact `NoteDocument`,
descriptor-observed file metadata, a fingerprint-bound title projection, and
graph counts. The app does not maintain a second mutable `Note` or YAML value
model; the app wrapper carries only the Application-owned workspace snapshot
without copying its exact source.

Contracts' `PropertyContract` catalog is the sole canonical vocabulary and
shape authority. It defines clean-sheet role keys, value kinds, allowed values,
CreatorList structure, and shape/source-safety validation. It contains no
creation-requiredness or machine ownership. `AnalysisSourceTypeProfileCatalog`
separately owns applicable, recommended, and deterministic serialization order.
`ResearchNoteTitleResolver` supplies one role-aware identity fallback to
Workspace, Search, Link Graph, and Research Actions. App's independent
`AboutProfileCatalog` owns researcher-configured display choices and order;
`PropertyPresentation` adds label, help, one group, and control style only.
The app's Properties feature composes those owners without creating another
schema: Settings edits exact role seeds, per-source-type Agent requirements,
and About order as one revision-bound candidate. One shared Analysis/Topic/Work
Note sheet lists every present safe top-level value and offers only applicable
canonical missing keys. Editability is derived from the current exact source
and targeted planner, never Settings. Unsupported shapes remain read-only with
a Source route. Creator controls produce the canonical ordered mapping sequence.
Quoted strings remain structured-editable. Any YAML scalar resolved as a
timestamp, whether implicit or explicitly tagged and regardless of its field,
is shown as its exact authored token and remains Source-only, so no text value
is parsed and then silently normalized by the Properties surface.
Custom top-level keys, including Unicode and dotted spellings, use an exact
top-level accessor in Properties and About; dots are never reinterpreted as a
nested path at that boundary.
Property edits are validated through Contracts and applied by Application as targeted
`NoteDocument` changes. `FrontmatterPatchPlanner` first validates complete YAML
with Yams, then proves a unique bounded plain key. Ordinary scalar edits replace
only the value token; list and creator edits use bounded sequence/member
replacements; and a missing key is appended only at a proven top-level or child
block-mapping boundary. Flow roots, quoted/duplicate or complex keys,
merge/anchor/alias involvement, block scalars, structured scalar continuations,
and ambiguous indentation return a typed refusal that directs the researcher
to Source. Refusal leaves every Markdown byte unchanged; successful patches
preserve BOM, newline/final-newline style, comments, unknown YAML, formatting,
and all bytes outside the proven range.
String edits use YAML-safe scalar encoding for literal quotes, leading
indicators, controls, Unicode, and surrounding whitespace. The planner reparses
the complete candidate and compares every requested edit with its semantic
readback; any mismatch refuses the whole replacement.

YAML-free Notes have a distinct explicit `insertFrontmatter` change set. It
requires at least one concrete Property edit, preserves a leading BOM and the
existing body/final-newline bytes, uses the observed newline style for the new
envelope, and remains expected-revision bound through the ordinary repository
transaction. Ordinary `frontmatter` edits still refuse a YAML-free Note, so a
Properties caller cannot create empty delimiters or silently opt into YAML.

`summary` is one optional string contract in the Analysis, Topic, and Work
profiles. The same `FrontmatterPatchPlanner` and repository transaction own
researcher and authorized Agent changes; there is no summary writer, sidecar,
approval copy, backfill task, or freshness database. Attribution remains an
operation/Record fact rather than a second YAML value. Missing or source-shape-
unsupported summary stays absent/readable and never triggers normalization.
Research Context receives only the current Note revision, so its Note and
`summary` envelopes use actor `unknown`. A prior authorized mutation or Record
retains its own actor without becoming a per-field or current-revision writer
registry. Authorization, most recent Run, path, vault, and local user are not
writer evidence; no hidden history store fills that absence.

Search constructs a separate read-only top-level YAML projection from each
exact `NoteDocument`. It records literal key presence and the exact source
range of the key, plus exact scalar or sequence-member ranges only when the
value is an eligible YAML string. It never recursively flattens mappings,
coerces scalar types, patches source, or reconstructs Markdown. Malformed,
duplicate, complex, or range-ambiguous keys are ineligible rather than guessed.
The projection may address an unknown literal key for retrieval, but
`PropertyContract` remains the sole owner of canonical meaning, role validity,
editing, and scholarly presentation. Its derived entries publish and rebuild
with the same authorized Note manifest as lexical Search.

`SearchDocumentProjection` additionally emits a `.summary` lexical segment
only from the canonical top-level string and the exact scalar range already
proved by the source projection. The segment is independently searchable and
explainable but belongs to the same Note/index generation and cannot write the
Property. Quoted source ranges may include their delimiters; a block or
otherwise unbounded scalar retains Property presence but is excluded from
summary lexical projection until an exact range is provable.

The lexical projection uses string `publication_date`; there is no numeric
`year` field or derived year guess. The FTS schema version changes with that
column and query grammar, so an old disposable database is rebuilt rather than
adapted. Literal `property:year` may still find authored custom source, but it
does not restore field semantics, filters, ranking, or aliases.

`TriptychControlStore` owns `analysis-zotero-bindings.json`, a strict portable
envelope of one typed user/group-library + item-key relationship per stable
Analysis Note UUID. Reads return an exact-byte revision; set and clear require
that revision, atomically replace, and readback. `WorkspaceSnapshotBuilder`
joins bindings only through resolved portable identities. The catalog and
Overview never derive a binding from frontmatter or bibliographic similarity.

`TriptychControlStore` also owns one strict JSON record per attachment under
`.scholium/attachments/v1/`. Each record contains a stable attachment UUID,
vault UUID, and typed location: Import uses a vault-relative path; Index uses a
standardized absolute path. The record contains neither bytes nor access
credentials. `VaultAttachmentStore` alone performs no-follow image validation,
descriptor-relative exact Import creation, and fingerprint-bound rollback.
`IndexedAttachmentAccessStore` retains read-only security-scoped bookmarks in
Triptych-keyed Application Support. It requires the bookmark to resolve to the
authored absolute path and reports unavailable rather than following a moved
file or rewriting source.
