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
update holds the original descriptor, writes and synchronizes a same-directory
candidate, copies metadata with descriptor APIs, preserves the candidate
content mtime, rechecks the exact preimage, uses displaced-byte-preserving swap,
and verifies bytes, mode, owner/group, ACL/xattrs, flags, birth metadata, and
the parent-directory synchronization boundary. Ordinary xattrs and Finder tags
remain byte-exact. For the LaunchServices-managed `com.apple.quarantine`
attribute only, verification accepts either one valid sandbox-added envelope
on a previously unquarantined staging inode or a valid system normalization
when its security flags and event identifier are unchanged and its timestamp
does not move backward. Scholium retains an added quarantine envelope; a
missing attribute, malformed value, other added attribute, or quarantine
authority change still fails closed.
Unsupported swap fails closed.
Any post-swap identity, readback, metadata, permission, or synchronization
uncertainty attempts a guarded swap-back, keeps observed staging evidence, and
returns `commitUncertain`; Application persists a `.noteSave` Transaction
Recovery record and never reports Saved.

Before canonical replacement can occur, the coordinator records the relative
path, staging name, candidate and preimage device/inode, and both exact
fingerprints; `VaultRepository` durably persists that task before the final
authorization check and swap. If authorization or swap aborts before canonical
replacement, that task is also the sole authority for removing only the
unchanged staged candidate; failed cleanup retains the task for reopening
instead of abandoning an unauthorized hidden file. Once swap, readback,
metadata, and parent synchronization prove the candidate canonical, the
displaced preimage becomes cleanup-only state. The already-persisted task therefore survives process
termination or later repository readback and history failure without creating
a second cleanup authority. The recovery ledger then atomically isolates the exact
staging inode inside a mode-0700 same-parent cleanup directory, revalidates its
bytes, and rechecks the isolated path identity immediately before removal. A
cleanup failure therefore keeps the source commit successful and returns a
`SaveResult.cleanupWarning`; it does not become `Save Failed` or
authorize a repeated source mutation.
Composite Note and Folder moves retain every cleanup warning produced by their
incoming-link rewrites in the move commit and application outcome.
Startup retries only after the candidate remains canonical and the recorded
task still matches the transaction. A missing staging and isolated path
completes the task; an inode, byte, type, containment, access, or task-binding
mismatch retains it and publishes a health diagnostic without deleting a
replacement observed at either checked path, including a staging name that
reappears during cleanup. The public macOS APIs still do
not provide descriptor-bound unlink; the final checked-name removal is bounded
by the random restricted directory rather than claimed as protection against
an adversarial same-UID process racing the last system call.

The retained pre-swap candidate contributes a workspace health issue and a
vault-qualified entry in the existing Recovery sheet. Core no-follow reads
revalidate its manifest plus expected/candidate bytes; read-only source, Copy,
and Finder reveal grant no write authority. Restore carries the displayed
vault, path, revisions, creation identity, and retained reason back to Core,
flushes all Triptych editors, and uses the ordinary revision-checked repository
save only while canonical source remains at the expected revision. Current
evidence and remaining acceptance belong to
[Implementation Status](../IMPLEMENTATION_STATUS.md).

`PrewriteRecoveryLedger` is Core-only machine state under
`Vaults/<vault-id>/recovery-v2/`. Immutable fingerprinted objects are indexed by
SQLite WAL with full synchronization, bounded to ten entries per path, and
protected by remap journals and permanent-delete tombstones. A damaged database
is quarantined and rebuilt from verified objects. Unsupported version bytes
remain unchanged and nonauthorizing. It exposes no general delivery-facing
versions or history API. Its one bounded `InterruptedSaveRecovery` projection includes only exact
startup-retained candidates and remains distinct from Checkpoints and settled
versions. `DocumentOperations` vault-qualifies listing, read-only content,
Finder location, and restore; `ResearchController` owns that listing beside the
existing durable-recovery list, while `WindowModel` owns the cross-window editor
flush and presentation effects. Startup reads pending canonical source through
the descriptor boundary. A canonical
candidate proves the interrupted save committed and completes its mutation
journal; a still-canonical expected revision retains the distinct candidate
bytes and publishes a health diagnostic instead of deleting the only
structured copy of interrupted editor work.

`SecureRecordDirectory` is the Core-only descriptor-relative primitive for
bounded machine-local JSON state. It owns no-follow containment, byte limits,
atomic replacement, readback, staging/deletion recovery, and the companion
`AdvisoryFileLock` for cooperating-process serialization. Portable Records,
local executions, recovery policy, and the prewrite ledger each retain their
own schema, path, transaction, recovery, and error semantics, and translate
primitive failures at that owner boundary. The primitive neither interprets a
Record nor becomes a writable research-source authority.

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
About order, and structured-edit allowlists as one revision-bound candidate;
the Note sheet lists every present safe top-level value and offers only
applicable canonical missing keys. Unsupported shapes remain read-only with a
Source route. Creator controls produce the canonical ordered mapping sequence.
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
