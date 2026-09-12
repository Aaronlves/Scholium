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
unchanged and nonauthorizing. The ledger exposes no versions or history API.
`DocumentOperations` vault-qualifies listing, read-only content, Finder
location, and restore; `ResearchController` owns that listing beside durable
recovery state, while `WindowModel` owns cross-window editor flush and
presentation effects.

`AgentChangeStore` is a separate Core actor under
`Triptychs/<triptych-id>/agent-changes-v1/`. One descriptor-contained JSON file
records one MCP create, update, or trash transaction and binds stable Note
identity, role, paths, exact before/after fingerprints, optional bounded source
bytes, and recovery state. It is machine-local evidence, not a task, result,
permission, research history, or source authority. Prepared entries are
confirmed only after the ordinary source owner proves readback. Outcome-uncertain
entries require exact reconciliation. Direct Undo exists only for a confirmed
update whose current authoritative fingerprint still equals the recorded after
fingerprint.

`SecureRecordDirectory` is the Core-only descriptor-relative primitive for
bounded JSON state. It owns no-follow containment, byte limits,
atomic replacement, readback, staging/deletion recovery, and the companion
`AdvisoryFileLock` for cooperating-process serialization. Agent Changes, the
prewrite ledger and other bounded stores retain their own schema,
path, transaction, recovery, and error semantics. The primitive interprets no
research object and never becomes a writable source authority.

## System Trash and coordinated source boundary

`NoteSystemTrashDeletionCoordinator` is the Core owner for one
researcher-confirmed source cutover. `prepareNote` and `prepareFolder` bind
exact source revisions, stable identities, and complete directory manifests
into one immutable preview.
`WorkspaceHandle` holds the source-mutation lease and flushes every Triptych
editor before preparation and execution.

`TriptychMutationRecoveryStore` persists the `SystemTrashDeletionPlan` before
the first filesystem call. Each source owns an independent receipt and stable
binding identity; duplicates fail before the deletion gate or another side
effect. `VaultRepository` repeats descriptor-relative containment and revision
or manifest checks. `VaultMutationCoordinator` atomically renames the checked
directory entry into the plan-owned hidden sibling, verifies the bound inode
and exact bytes or complete manifest, and only then calls Foundation's native
system-Trash API inside a coordinated deleting accessor. A late path
replacement is restored or retained without entering Trash. A pending plan
resumes an interrupted binding; absence of both original entry and a valid
binding becomes `outcomeUnknown`. Returned URLs remain machine-local recovery
evidence only.

`SettlementStore` owns portable judgments at `.scholium/settlements/v3/`,
independently of research prose. It uses strict schema decoding, coordinated
writes, and the shared Triptych lock; unsupported directories are not imported.

Settlement, stable identity records, and Agent Changes are not
portable cleanup targets of source deletion. Watcher reconciliation, Finder
actions, and sync tools cannot construct or execute the plan; they publish
ordinary source inventory changes and stable-identity diagnostics only.
## Shared read models and source properties

`WorkspaceNoteSnapshot` carries exact `NoteDocument`, stable vault-qualified
identity, observed file facts and derived graph/search state. Filename owns
Note title. There is no second mutable property record or catalog.
`SearchPropertyProjection` reads arbitrary top-level YAML keys using Yams and
proves source ranges, refusing ambiguous keys or unbounded scalar tokens.
`SearchDocumentProjection` supplies lexical summary, keywords, authored title,
aliases, author text and publication date. These are discovery projections,
not bibliographic validation or writable source.

Search contract 18 and disposable schema 14 use the existing `property:`
grammar with quoted literal keys and normalized scalar/direct-list equality.
All property rows come from source; no source-kind discriminator or managed
record refresh path remains. Rebuild and incremental publication consume the
same exact-source manifests. User YAML cannot assign stable identity or Settle.

Managed creation takes complete authored Markdown and preserves its bytes.
GUI creation starts empty. `FrontmatterPatchPlanner` remains the existing
bounded source-edit utility, not a property store or a catalog validator.

`SourceResourceReferences` walks Markdown links/images. Zotero occurrences
retain exact library-qualified references; Links presents them on its outgoing
page. No Zotero API call, inferred binding or bibliography write occurs during
projection. The existing independent Zotero read tools remain unchanged.

Attachments use one file registry at `.scholium/attachments/v2/`: attachment
UUID, vault UUID and a contained path or neutral external filename descriptor.
It provides file identity only. There is no Note-to-file catalog. Current
Markdown alone supplies relationships; unregistered contained file links get
deterministic projection IDs. Missing external access yields unavailable.
`IndexedAttachmentAccessStore` owns exact absolute path/bookmark matching in
machine-local Application Support; filenames never substitute for identity.

`VaultAttachmentStore` owns no-follow file validation, bounded reads, exclusive
copies and exact-fingerprint rollback. `PreparedSourceAttachment` joins that
file preparation to the existing editor insertion transaction. Failed insertion
rolls back only newly created preparation state; uncertain commits preserve
files. Native Quick Look holds an explicit preview-lifetime lease. Agent reads
recheck source/listing fingerprints and containment and never acquire access
from a caller-supplied arbitrary path. Link deletion never deletes file bytes.

Retired Metadata, Zotero-binding and Note-attachment control files remain
untouched and nonauthorizing. There are no readers, writers or migration paths
for those preproduction records.
