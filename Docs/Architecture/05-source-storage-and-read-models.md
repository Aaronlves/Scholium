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
ownership authority. It defines role-specific keys, value kinds, empty
creation requirements, allowed values, cross-field constraints, and validation.
`ResearchUnitDeclaration` separately parses Analysis Completion versus
Topic/Work Scope, and `ResearchNoteTitleResolver` supplies one role-aware
identity fallback to Workspace, Search, Link Graph, and Research Actions.
App's independent `AboutProfileCatalog` owns default display choices and order;
`PropertyPresentation` adds labels, help, grouping, and control style only.
Property edits are validated through Contracts and applied by Application as targeted
`NoteDocument` changes. `FrontmatterPatchPlanner` first validates complete YAML
with Yams, then proves a unique bounded plain key. Ordinary scalar edits replace
only the value token; the role-aware Research Unit uses bounded member and array
replacements; and a missing key is appended only at a proven top-level or child
block-mapping boundary. Flow roots, quoted/duplicate or complex keys,
merge/anchor/alias involvement, block scalars, structured scalar continuations,
and ambiguous indentation return a typed refusal that directs the researcher
to Source. Refusal leaves every Markdown byte unchanged; successful patches
preserve BOM, newline/final-newline style, comments, unknown YAML, formatting,
and all bytes outside the proven range.

`summary` is one optional string contract in the Analysis, Topic, and Work
profiles. The same `FrontmatterPatchPlanner` and repository transaction own
researcher and authorized Agent changes; there is no summary writer, sidecar,
approval copy, backfill task, or freshness database. Attribution remains an
operation/Record fact rather than a second YAML value. Missing or source-shape-
unsupported summary stays absent/readable and never triggers normalization.

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
