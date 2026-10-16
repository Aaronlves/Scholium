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

Durable machine-local recovery binds exact expected/candidate bytes, fingerprints
and path before replacement. Prewrite failure preserves source; postwrite failure
never compensates automatically. No-follow canonical/backup reads and parent
identity must prove commit before Saved or cleanup. Differing displaced bytes
are durably transaction-bound before backup removal; failure retains backup for
startup reconciliation at its exact location. Expected, candidate and displaced
bytes survive uncertainty even when candidate bytes are canonical. Proven saves
retain no history.

Recovery inspection grants no writes. Explicit restore binds vault/path/revisions
and retained creation identity, flushes Triptych editors, then uses the repository
writer only against expected source. Window/Research owners borrow projections;
unsupported records remain unchanged and nonauthorizing.

Core `DocumentReviewStore` keeps source baselines, captures, batches and
receipt-version coverage outside vaults. Application `DocumentChangeOperations`
prepares bounded baselines against one revision-bound identity inventory;
`DocumentChangeArchiveOperations` accesses Triptych metadata for Settings
without vault activation. MCP receipts and Undo remain with
[Agent Collaboration](02-agent-collaboration.md#note-mutation-authority-and-evidence).

Bounded record stores share Core's contained atomic secure-record primitive and
advisory locking. Stores own schema/transactions; the primitive interprets no
research. Portable settings and machine-local style manifests use exact-byte
coordinated replacement, exclusive recovery copies and checked absence. Application
owns independent appearance/snippet failures; Settings retains target-bound
drafts/recovery. Style requests serialize through snapshot publication; failed
reload retains profile/draft and repair availability. Unsupported settings project
defaults without rewriting. Identity bootstrap is no-replace; updates carry exact
decoded preimages through coordinated swap/readback. Source never grants identity.

`TriptychControlStore` owns essential UUID-keyed citation companions;
`ZoteroCitationSaveCoordinator` uses Application's source lease and
`TriptychMutationRecoveryStore`'s exact paired evidence. Source/companion revisions
and portable ownership declarations govern commit, absence and recovery;
derived projections cannot reconstruct authority.

## System Trash and coordinated source boundary

One Core deletion coordinator freezes source revisions, identities and complete
folder manifests. The Application handle holds the source lease and flushes
Triptych editors before preparation/execution. Durable plans precede filesystem
effects; each source has an independent receipt/binding identity and duplicates
fail before side effects.

Inside a deleting accessor, Core rechecks containment, revisions, inode and exact
source or complete manifest. Its internal Objective-C
`ScholiumNativeFileOperations` adapter passes an inode-bound Foundation reference
to Finder, preserving the original restoration location without staging.
Original-route and returned-object checks reject substitution. Per-source native
uncertainty persists before dispatch; interruption never authorizes replay. Returned
Trash locations remain machine-local recovery evidence.

Portable identity and machine-local Agent Changes have independent writers and
are not deletion cleanup targets. Watchers and Finder/sync observations cannot
execute a deletion plan.

## Shared read models and source properties

Source-free Workspace summaries carry identity, revisions, facts and projections.
Committed summaries and descriptor versions bridge consecutive moves and link
rewrites to complete derived publication. Hydration validates version, path,
fingerprint and identity before returning source. Filename and YAML projections
support display/discovery without write or bibliographic authority. Yams proves
source ranges and refuses ambiguity.

One source-projection cache owns compact catalog and Search records under independent
parser/projection and Search policies. Fresh descriptor reads supply exact fingerprints,
facts and versions; validated catalog hits skip semantic parsing. Restoration validates
path, role/profile, coordinates and payload digest; unusable records recompute. Caches
contain no source or identity authority. Coordinated path deletion clears both kinds;
policy retirement and abandoned staging share that owner.
Search index publication transactionally binds complete paragraph/offset maps and
lexical preparation to exact source revisions. Negation cannot evaluate cropped
body passages. Literal term groups persist raw alternatives with group-level
preimage comparison, not query macros or hidden expansion.

Recommendation retrieval shares Search's transaction/decoder/parser. Core owns
bounded, revision/generation/role-bound Note preparation reused by independent
focused recall. Application validates current sources before scoring; prewarming
reads bounded batches under one protection snapshot covering all candidates and checks
the generation at each batch. It authorizes no results. The window owns cancellation and
foreground priority. Complete comparison sets precede bounded excerpts; exact
source ranges remain separate from readable highlights. Deduplication preserves
provenance; contextual weighting implies no philosophical interpretation.
Ordinary Search coordinates/clauses remain separate.

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
