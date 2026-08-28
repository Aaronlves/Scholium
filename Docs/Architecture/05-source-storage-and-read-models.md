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

`VaultDescriptorAccess` captures the authorized root's device and inode when a
repository opens, then verifies that exact directory identity whenever it opens
the registered root path. A moved, replaced, inaccessible, or symlinked root is
latched unavailable and cannot be reused merely because a directory later
appears at the same path. Each authorized operation walks every parent with
`openat` plus `O_NOFOLLOW`, and opens leaves with `O_NOFOLLOW | O_NONBLOCK`.
Immediate `fstat` accepts regular files only.
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
enveloped local execution payloads, Agent change evidence, and the prewrite
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
Triptych editor before both preparation and execution. System Trash reads the
stable Local Execution envelope rather than its private payload: relevant live
or recovery-required entries fail preflight, terminal entries remain eligible
for cleanup, and an unsupported payload cannot block unrelated Notes. A file
without a valid envelope yields a store-wide fingerprint-bound recovery
preview. A valid live envelope with an unreadable payload yields a preview only
when the selected Note set intersects its stable participation set.

`LocalResearchExecutionStore.archiveUnsupportedExecutions` is the sole recovery
mutation for either preview. Under the store lock it recomputes the complete
store-wide or Note-scoped set and rechecks each exact fingerprint, creates or
verifies a byte-identical file in the
descriptor-contained `unsupported-executions` directory, then removes only the
matching original. It performs no legacy decode or migration. Application owns
the standard cancel/destructive alert and retries the original preparation only
after archival succeeds.

`TriptychMutationRecoveryStore` persists the `SystemTrashDeletionPlan` before
the first filesystem call. Each source owns an independent receipt and a stable
binding identity; duplicate source, Note, Record, Discussion, or receipt
identities fail before the deletion gate or another side effect.
`VaultRepository` repeats descriptor-relative containment and revision or
manifest checks. `VaultMutationCoordinator` atomically renames the checked
directory entry into the plan-owned hidden sibling, verifies the bound inode
and exact bytes or complete manifest, and only then calls Foundation's native
system-Trash API inside an `NSFileCoordinator` deleting accessor. A late path
replacement is restored or retained without entering Trash. A pending plan
resumes an interrupted binding, while absence of both the original entry and a
valid binding cannot prove Foundation success and becomes `outcomeUnknown`.
The returned URL remains machine-local recovery evidence only.

After every source receipt is `movedToSystemTrash`,
`PortableResearchRecordStore` discards affected active Discussions and deletes
each previewed finished Record with exact-fingerprint compare-and-swap. A
durable deletion marker makes retry idempotent. Note Review activities are
pruned, then local executions and Agent change evidence are removed. Settlement,
stable identity, source-access records, Zotero bindings, and Critique
associations are not cleanup targets. The Note-deletion marker shares the
portable-store lock with active Discussion, Settlement, and finished Record
creation, so no participating state can appear after confirmation. Portable
Record schema 15 has no deleted-participant representation; every unsupported
schema remains byte-unchanged, unread, and nonauthorizing.

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

Contracts split structured values by authority. `PropertyContractCatalog`
contains only authored YAML `summary` and `keywords` for all three roles.
`BuiltInNoteMetadataCatalog` owns the product vocabulary and complex shapes;
portable schema-8 Settings owns stable simple definitions and lifecycle by role.
`NoteMetadataCatalog` resolves both once per workspace generation and is the
sole catalog consumed by Core record validation, Application plans, Search,
Library filters, Settings, About, and the Metadata editor. It defines
role-valid fields, value kinds, allowed values, and CreatorList structure
without owning researcher values.
`AnalysisSourceTypeProfileCatalog` separately owns Analysis applicability,
recommendation, and deterministic presentation order.

`TriptychControlStore` owns one portable metadata file per stable Note UUID at
`.scholium/note-metadata/v1/<uuid>.json`. `NoteMetadataRecord` schema 1 stores
only that UUID and a field mapping in canonical sorted JSON. Reads validate the
record schema, UUID/path identity agreement, and role catalog before publishing
any value; one invalid file fails the complete Metadata projection closed and
preserves its exact bytes. Preflight reports that direct filename, exact
fingerprint, optional embedded identity, and failure class. Confirmed recovery
uses the shared exact-state preserver to archive only that unchanged regular
file under a non-JSON sibling name; replacement or drift refuses the action,
and valid neighbor records and the rest of `.scholium` remain untouched.
Creates and edits use a metadata-revision
compare-and-swap, atomic replacement, canonical readback, and an explicit
uncertain-commit outcome. The researcher owns every field value; Scholium owns
the schema, location, validation, and transaction. No metadata file is a
writable projection of Markdown or YAML.

`WorkspaceSnapshot` carries the resolved catalog next to its generation;
`WorkspaceNoteSnapshot` carries the optional validated metadata snapshot next
to exact source. `ResearchNoteTitleResolver` uses managed Analysis `title`,
then first H1, then filename; Topic and Work use first H1, then filename. YAML
`title` has no identity semantics. App's independent `AboutProfileCatalog`
owns researcher-configured display choices and order; presentation adds label,
help, group, and control style only. The shared Metadata sheet reads and edits
only managed fields, offers only role-valid missing keys, and never creates or
patches frontmatter. Authored `summary` and `keywords` are read from exact
source for About and edited only in Source. Unknown YAML remains byte-preserved
custom source and is never surfaced as a managed-field alias.

`FrontmatterPatchPlanner` remains a source-fidelity utility for bounded typed
serialization and explicit source operations. It is not a Metadata writer.
Managed creation always emits fixed `summary` then `keywords`; omitted values
serialize as `null` and `[]`, while a typed request may supply either value.
No runtime path inserts YAML merely because a managed field is added. The body has
no Scholium schema, required section, or generated research prose.

Search constructs one read-only structured projection from both authorities.
For authored `summary` and `keywords`, it proves exact top-level key and
string/member source ranges and rejects malformed, duplicate, complex, or
ambiguous source rather than guessing. For managed Metadata, it projects the
validated record value and revision with no Markdown range. Unknown YAML is
not indexed. The v9 disposable index stores nullable structured-field ranges;
incremental publication and clean rebuild consume the same authorized Note and
Metadata manifest.

A Metadata-only commit carries its exact single-record delta through the
existing refresh coordinator. The builder overlays that delta on the last
complete Metadata map, reprojects Search/Graph/snapshot state, and records zero
Metadata catalog reads and zero source enumerate/read/parse/project work. Any
coalesced non-Metadata request drops the optimization and uses the ordinary
complete authority read; there is no second refresh or index owner.

`SearchDocumentProjection` additionally emits a `.summary` lexical segment
only from the canonical top-level string and the exact scalar range already
proved by the source projection. The segment is independently searchable and
explainable but belongs to the same Note/index generation and cannot write the
authored field. Quoted source ranges may include their delimiters; a block or
otherwise unbounded scalar retains canonical field presence but is excluded from
summary lexical projection until an exact range is provable.

The lexical projection uses managed string `publication_date`; there is no
numeric `year` field or derived year guess. The FTS schema version changes with
that column and query grammar, so an old disposable database is rebuilt rather
than adapted. `property:year` cannot match unknown authored YAML and does not
restore retired field semantics, filters, ranking, or aliases.

`TriptychControlStore` owns `analysis-zotero-bindings.json`, a strict portable
envelope of one typed user/group-library + item-key relationship per stable
Analysis Note UUID. Reads return an exact-byte revision; set and clear require
that revision, atomically replace, and readback. `WorkspaceSnapshotBuilder`
joins bindings only through resolved portable identities. The catalog and
Overview never derive a binding from frontmatter or bibliographic similarity.

`ZoteroMetadataPlanner` is the sole pure mapping from one exact local item
read into catalogued Analysis Metadata. It selects the effective source-type
profile, preserves structured creator components, filters inapplicable fields,
and partitions absent, differing, and conflicting keys according to explicit
Link-and-Fill or Refresh mode without adding abstract, tags, citation key,
Collections, `summary`, or `keywords`. Its immutable plan
binds the exact source, binding, Metadata, server, library, key, and item state;
`ZoteroBindingOperations` revalidates those inputs and owns the ordered
binding-then-Metadata commit. Neither the read model nor the UI reconstructs a
writable source or a second bibliographic snapshot.

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
