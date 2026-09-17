# Architecture: Source Storage and Read Models

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Descriptor
authorization, transaction recovery, and source-bound projections.

## Vault write and prewrite-recovery boundary

Typed Markdown-relative paths preserve spelling and reject absolute/dot/empty/NUL
or non-Markdown targets. Root-owned volume comparison keys handle collision
decisions without rewriting source or stored paths.

Repository authorization captures root device/inode and verifies that exact
directory on every operation. Moved/replaced/inaccessible/symlinked roots latch
unavailable. Every parent is walked descriptor-relatively with no-follow opens;
leaves are nonblocking and immediately proved regular by descriptor metadata.
Enumeration admits candidates only. Loads, fingerprints, final authorization,
readback and recovery all use this boundary. Presence distinguishes confirmed
absence from inaccessible/error; only confirmed absence completes deletion.

Core's mutation coordinator wraps short native coordinated accessors around
descriptor authority. Create/move use exclusive no-replace rename. Update retains
the original descriptor, synchronizes a same-directory candidate, rechecks expected
bytes/parent identity and performs Foundation atomic replacement in a replacing
accessor. The system-managed sibling backup is retained until reconciliation.
Foundation owns preservation/adjustment of standard filesystem metadata; Scholium
does not reconstruct or compare the full ACL/xattr/ownership/flags envelope.

Before replacement, durable machine-local recovery binds exact expected/candidate
bytes, fingerprints and path. Pre-replacement failure leaves canonical source
unchanged. Post-replacement failure never triggers an automatic compensating write.
Canonical no-follow readback plus parent identity proves commit or leaves recovery
uncertain; no generic Saved result is allowed without that proof.

Backup bytes are no-follow read before success/transaction removal. Differing
displaced source is durably retained and bound to the same transaction before
backup cleanup. Failure preserves the backup; startup reconciles its exact
transaction-bound location first. Expected, candidate and displaced bytes survive
uncertainty even if canonical bytes equal the attempted candidate. Ordinary proven
saves leave no history.

Recovery read/reveal/copy is nonauthorizing. Explicit restore carries exact vault,
path, revisions and retained creation identity, flushes Triptych editors, and uses
the same revision-checked repository writer only while canonical source remains at
the expected revision. Window/Research owners borrow recovery projections, not
filesystem transaction ownership. Unsupported records remain unchanged and
nonauthorizing.

Agent Changes use a separate machine-local evidence store, binding operation,
stable identity, exact before/after fingerprints and retained source/recovery.
Prepared entries confirm only after source readback; uncertain evidence requires
exact reconciliation. Update Undo requires a confirmed current ending fingerprint;
move recovery retains all linked-source preimages and checks the whole inverse
through [Agent Collaboration](02-agent-collaboration.md#note-mutation-authority-and-evidence).
Create/trash evidence does not fabricate text preimages or comparisons.

Bounded JSON stores share the Core-only secure-record primitive for descriptor
containment, byte limits, atomic replacement/readback and staging/deletion recovery.
An advisory lock serializes cooperating processes. Each store owns its own schema,
path, transaction and error semantics; the primitive interprets no research object.
Portable settings and machine-local style manifests share exact-byte coordinated
replacement, exclusive recovery copies and checked absence creation. Application
owns independent appearance/snippet load failures; Settings retains target-bound
drafts and recovery confirmation. The style adapter serializes requests through
returned-snapshot publication; failed reload publishes repair availability while
retaining the loaded profile and draft. Unsupported settings project safe defaults
without rewriting their saved envelope.
Portable identity bootstrap uses no-replace creation. Identity mutation carries
its exact decoded preimage through coordinated swap and readback, preventing a
stale writer from erasing newer identity. Source bytes alone never grant identity.

## System Trash and coordinated source boundary

One Core deletion coordinator freezes source revisions, identities and complete
folder manifests. The Application handle holds the source lease and flushes
Triptych editors before preparation/execution. Durable plans precede filesystem
effects; each source has an independent receipt/binding identity and duplicates
fail before side effects.

Core repeats containment/revision checks, renames the entry into a plan-bound
hidden sibling, proves its inode and exact source or complete manifest, then invokes
native Trash inside a deleting accessor. Late path replacement is restored or
retained without entering Trash. Interrupted bindings resume only under their
exact plan; absent original and absent valid binding report unknown outcome.
Returned Trash locations are machine-local recovery evidence.

Portable Settlement and identity, and machine-local Agent Changes, have independent
writers and are not deletion cleanup targets. Watchers, Finder/sync observations
cannot execute a deletion plan. Settlement writes retain strict schema validation
and shared control-store coordination, independently of source prose.

## Shared read models and source properties

An immutable Note snapshot carries exact document, vault-qualified stable identity,
descriptor-observed file facts and disposable graph/search state. Filename is
display identity; no second writable metadata record exists. Yams-backed property
projection proves source ranges and refuses ambiguity. Semantic field projection
supports discovery, not bibliographic validation.

Disposable source-projection caches bind exact path/fingerprint, role/profile,
parser/search policy and checked coordinates/payload digest. Fresh descriptor reads
and semantic parsing precede restoration; invalid/missing/unwritable caches cause
recomputation. Caches contain no authoritative source, file facts or identity.
Search index publication transactionally binds complete paragraph/offset maps and
lexical preparation to exact source revisions. Negation cannot evaluate cropped
body passages. Literal term groups persist raw alternatives with group-level
preimage comparison, not query macros or hidden expansion.

Recommendation retrieval shares that index and semantic parser. It checks all
eligible current source candidates, ranks complete comparison-set scores before
selected excerpts, and retains exact passage ranges separately from readable
highlight projections. Revision-bound memoization cannot skip source validation
or candidate scoring. Within/cross-Note deduplication preserves original source
provenance; role diversity and local weighting are ranking mechanisms, not
philosophical interpretation. Ordinary Search coordinates/clauses remain separate.

Source resource projection walks current links/images and validated Zotero
locators without API calls or inferred bindings. One portable attachment registry
provides file identity, never Note relationships. Markdown alone supplies those.
External access requires exact machine-local path/bookmark binding; filename
cannot substitute. Contained unregistered links receive derived IDs.

The attachment owner performs no-follow bounded reads, exclusive copies and
exact-fingerprint rollback. Preparation joins the existing editor insertion
transaction. Failed insertion rolls back newly prepared state only; uncertainty
preserves files. Quick Look holds a scoped preview-lifetime lease. Agent reads
recheck relationships/revisions and cannot gain arbitrary-path access. Link
deletion never deletes file bytes.

Creation preserves complete authored Markdown; GUI creation starts empty.
Targeted YAML edits remain bounded source transformations, not a catalog writer.
Unsupported preproduction control records have no readers/writers/migration route.

## Note reorganization

Contracts planners derive paragraph anchors, exact block edits, source dependency
closures and identity consequences from shared semantic parsers. Parser-owned
footnote slices map back to exact bytes. Append/restructure reparses source scopes,
preserves existing link meaning and handles captured literal openers without
reconstructing source. Frontmatter planning distinguishes proved entries from
independent comments/blank lines and retains explicit per-key conflict choices.

Application prepares/commits through the source gate. Core rechecks all revisions,
retains exact recovery bytes before writes, and uses existing repository/Trash
owners. Preview presentation never owns source. Reorganization recovery is
machine-local transaction evidence, not a citation snapshot.

## Source entry points

- `ScholiumCore/VaultRepository.swift` and `VaultMutationCoordinator.swift`:
  descriptor-backed source transactions.
- `ScholiumCore/SecureRecordDirectory.swift`: bounded state persistence.
- `ScholiumCore/NoteRestructureCoordinator.swift`: multi-source reorganization.
- `ScholiumContracts/MarkdownSemanticDocument.swift`: shared source projection.
