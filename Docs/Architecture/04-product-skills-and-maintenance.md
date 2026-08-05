# Architecture: Research Skills and Agent Collaboration

Part of the canonical document set rooted at [IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md).
This chapter owns Research Skill/Practice registration, Action configuration,
local Agent connection, and their maintenance transactions; sibling chapters
do not restate it.

## Skill, Practice, Profile, and collaboration owners

Research Guidance has one strict configuration owner, one closed Platform
catalog, and the existing Run/Record owners; it has no package layer:

```text
ResearchConfigurationStore
    strict revision-checked Triptych subdocuments
        |
        +-> ResearchSkillRegistrationDocument
              one Action -> one enabled registration
              hidden stable key, display name, primary Markdown locator,
              optional machine-local folder locator, enabled state
        |
        +-> SecureResearchMethodIO + ResearchPracticeResolver
              exact primary Markdown / Practice reads and targeted writes
              exact Wikilinks, first-use order, deterministic ambiguity
              one replaceable pre-edit recovery point per file
        |
        +-> ResearchAcademicProfileDocument
              flat academic input/result fields only
        |
        +-> ResearchCollaborationPolicyDocument
              one missing-is-Ask-Every-Time policy per Triptych
        |
        +-> ResearchCitationMethodDocument
              one optional code-catalog citation style per Triptych

PlatformActionCatalog
    protected supported roles, selectors, source preconditions,
    machine fields, and executable operations

```

The registration document is portable Triptych configuration but contains no
absolute path, bookmark, method bytes, folder inventory, version, digest,
dependency, or capability declaration. A primary entry already under the
portable control root uses a descriptor-relative locator. An entry or optional
folder outside that root uses a stable machine-local locator and read/write
bookmark in the same private Application Support boundary as other local
source access. Only a successful authenticated Session may receive the frozen
resolved path string. Portable Records retain only registration relation key,
display name, and Practice names.

Existing `.scholium/skills/<id>/SKILL.md` bytes need not move during cutover.
Each current active method can become a registration whose primary locator is
that exact file and whose optional folder locator is its existing directory.
After readback, Scholium ceases to interpret sibling files as package resources.
New simple methods may use one Markdown entry without a folder. New folder
methods select one primary Markdown file and may register its containing
folder. The researcher filesystem, not Scholium, owns all other folder bytes.

`ResearchConfigurationStore` through `SecureResearchMethodIO` supports exact read, revision-checked complete
Markdown replacement, explicit app-default restoration, and one recovery
point. It does not snapshot a directory, diff versions, list history, validate
dependencies, enumerate supplements, or execute scripts. Recovery stores the
complete displaced primary/Practice file in machine-local private state and is
replaceable after the next confirmed write. External changes participate in
the ordinary current-revision/conflict boundary.

Practices are ordinary Markdown files in a bounded Triptych-managed location
or explicitly selected machine-local location. `ResearchPracticeResolver`
parses only ordinary Wikilinks from the exact primary method, resolves exact
title or explicit path within the Practice catalog, de-duplicates after first
use, and returns missing/ambiguous diagnostics. It does not resolve headings,
blocks, aliases, transclusion, nested Practice dependencies, or Connections.

`PlatformActionCatalog` is code-owned and closed. `ResearchAcademicActionProfile`
stores only bounded academic text/single/multi-choice fields, order, necessity,
visible name/order, role-valid placement, and enabled state. `ResultContract`
is an immutable Run snapshot of result fields plus Application-provided
machine fields. Neither object contains readable/writable roles, operations,
Property boundaries, source capability, recovery behavior, or permission.

`ResearchConfigurationStore` persists one strict policy document per
Triptych. Missing state is Ask Me Every Time. It has no per-Skill override,
Skill/Profile digest, package revision, fallback subject, or bearer key. Every
actual authorization is recomputed from current Platform Action support,
current policy, concrete Run request, exact identities/revisions, and the
Run/Session capability boundary.

The citation-style document stores only a code-catalog identifier such as
APA 7. It is a Platform integration setting rather than a Skill package,
Practice, permission, or executable method. Citation checking resolves the
current style at preparation and fails closed when the requested check has no
configured style.

Settings uses one restrained list/detail Research Guidance surface for
Methods, Profiles and Practices, Collaboration, Sources and Integrations, and
Recovery and Technical. It edits one owner at a time. The Profile editor
mutates only the one strict academic Profile document under expected revision:
visible name/order/enabled state, allowed-role subset, and bounded ordered flat
input/Result fields with free-text or closed choice kinds and excluded/optional/
required status. Platform selectors, machine fields, permissions, write scope,
and recovery cannot be represented there. There is no staged
package installer, resource preview, package validation, version comparison,
Skill snapshot history, marketplace, or package deletion quarantine. Removing
a registration rechecks Action binding and active Runs; it never recursively
deletes the selected method folder. Removing a Scholium-managed simple primary
file uses a recoverable isolation transaction and states that exact file
consequence.

## Pairing and Connection Session

`ResearchConnectionCoordinator` is one app-process owner of Pairing Codes and
Connection Sessions. Durable Run state remains in the execution store; the
coordinator owns only current-process authentication:

```text
Action sheet -> issue one-time Pairing Code
                 |
local CLI -> App Group AF_UNIX socket -> exchange code
                 |
ResearchConnectionCoordinator -> Session secret + bound Run set
                 |
authenticated CLI request -> Application Run/Context/Write capability
```

`ResearchSecureRandom` wraps `SecRandomCopyBytes` and returns failure rather
than fallback. Pairing Code and Session secret use independent random bytes.
Only salted/delimited cryptographic digests and bindings are retained server
side. Pairing records bind Run, local effective UID, process generation,
expiry, bounded failed-attempt count, consumed state, and revocation. Sessions
bind secret digest, UID, generation, expiry, revoked state, allowed Runs, and
which Run currently has write capability. Raw codes/secrets are non-Codable and
redacted from descriptions and logs. Only private bridge and protected CLI
storage adapters explicitly unwrap them for their one required boundary.

The coordinator is initialized with a fresh unpersisted process-generation
nonce. No Session decoder, Keychain item, Application Support file, Run file,
socket path, rendezvous file, or old handoff can restore authority in another
process. Run persistence intentionally survives coordinator teardown. One
Run's successful re-pairing atomically revokes its old write-capable Session
binding before publishing the new one. Ending a Run revokes every Session
binding for it.

`LocalAgentBridgeLocation` resolves the packaged App/CLI socket and minimal
rendezvous data only through the configured App Group container. Debug/QA may
use one explicit repository-local isolated root. Production has no discovery
of the App private container. The existing listener retains exclusive owner
lock, peer credential equality, 0700 parent/0600 socket, no-follow/type/owner
checks, bounded frames and deadlines, version/schema validation, cancellation
convergence, and body-free logging. App Group contents never include research
or recovery authority.

Bridge operations are authenticated envelopes. The authenticated context
schema exposes only a safe view of the current Bounded Write Set: stable
identity, role, operation, expected revision/proven absence, expiry, and
authorization origin; it never serializes a write capability or secret.
Pairing is the only operation
that accepts a Pairing Code; all Run, Research Context, read, write-set,
mutation, result, continuation, Method-improvement context/submission, reload,
and end operations require a Session secret delivered on stdin or another
hidden local channel, never a command argument. Authenticated end revokes the Run binding, blocks new operations,
retains confirmed/conflict/recovery truth, and removes the acknowledged CLI
credential when its protected store is safe. Delivery adapters pass the
authenticated Application request without re-parsing capability semantics.

## Run context and Bounded Write Set

`LocalResearchExecutionStore` is the only durable Run owner. The current
schema stores public Action/initial object, frozen registration reference and
primary method text, Practice identities/text, optional folder path string,
frozen Result Contract, capability availability, temporary canonical result
payload, current top-level state/reason, continuation origin, and machine
recovery correlations. It stores no raw Pairing Code, Session secret, absolute
path not already authorized for local delivery, query response, rank, or
provider cache.

The same schema also retains at most one current Method-improvement Run on its
parent completed execution. That value owns only frozen feedback/target
revisions, retry identity, in-flight reconciliation, and one terminal receipt;
it is not a second portable Record, feedback queue, or method history.

`ResearchBoundedWriteSet` is an embedded Run-owned machine value, not a store
or user object. Each entry binds stable document identity or reserved create
identity, role, operation, expected fingerprint/proven absence, expiry, and
whether authority came from explicit researcher selection or Full Access.
Contracts impose limits for one extension request, one Run, and encoded bytes.
The initial object is inserted during preparation. Extension validates and
adds one exact set or selected subset atomically; it never stores document
content or a research relation.

Every actual write receives a non-Codable, cryptographically random
`ResearchWriteCapability` bound to Session, Run, complete allowed document-set
digest, exact entry identity/operation/revision, operation ID, and short expiry.
Only its digest/binding is compared inside Application. The operation ID owns
idempotent retry and outcome query. One write still enters the sole repository
transaction: authorize/contain, read and compare, establish Before Agent Work
exact-byte recovery, final identity/revision recheck, atomic replace, and exact
readback. Confirmed success advances only that entry. Unknown outcome remains
Run recovery state and blocks safe finalization/end.

The former additional-Note request, allowed correlation plan, per-document
child Runs, child grants, group lineage, and write-capable parent/child phase
split have no current decoder or execution route after cutover. A next
scholarly Action uses Continue Research and creates a genuinely separate Run;
another document mutation inside the same Action extends the existing write
set.

Method improvement does not extend this set. Its separately paired Run can
address exactly one frozen primary Method or linked Practice. A replacement
receives a distinct non-Codable `ResearchMethodWriteCapability` bound to
Session, Run, request, target, expected revision, and short expiry. It is
consumed immediately before the ordinary configuration transaction, which
retains one previous-edit recovery point and reads back exact bytes. The
machine-local writing state makes a retry reconcile an already committed edit
instead of issuing a second mutation.

## Research Context, result, and evaluation

`ResearchContextUseCases` is one Application-owned capability whose providers
conform to the closed contracts in `ScholiumContracts/ResearchContext.swift`.
The production provider composes existing Application Search, exact read,
Graph/direct Relations, Property projection, strict Record store/query, and
owned research-state reads. A pure test provider implements the same protocol.
Both receive an already authenticated/authorized Run scope. No provider may
read raw Record JSON directly, parse Search, rank, widen scope, or persist a
response. Response schema 2 transports the already returned Foundation Note
match reasons without reinterpretation, preserving direct-relation direction
and exact occurrences and Property source ranges across App/CLI delivery.

The Run owns one partitioned `ResearchResultPayload`. Validation checks Agent
academic fields against its frozen Result Contract and Context Use Report
references against the Run-readable Source Reference registry. Application
adds machine fields from actual transactions. Finalization is idempotent and
writes one strict portable Record only after every initiated transaction is
known and recovery responsibility is satisfied.

`PortableResearchRecordStore` remains the only long-term result owner. Its
current strict schema includes one immutable finalized-result partition and an
optional current Researcher Evaluation partition. The exact canonical digest
of the serialized finalized partition is its immutable result fingerprint.
Evaluation replacement runs under the existing portable-record lock, rereads
the exact file, compares record ID, expected evaluation revision, and result
fingerprint, replaces only evaluation content/actor/revision/time, atomically
commits, and reads back. Pre-commit failure leaves the old Record authoritative;
post-commit uncertainty returns an uncertain outcome and never invites blind
retry. Deleting the Record is the only cascade deletion owner.

Action return and Record detail use the same `ResearcherEvaluationView`
contract keyed by exact Record identity, expected evaluation revision, and
finalized-result fingerprint. Draft state is
window-local before finalization and never persisted or published. A stale or
deleted target keeps local text for copy/reload/discard and cannot fall back to
the current Note/Record. Cross-Record summaries are rebuildable projections
over strict Records and cannot write evaluation source.

## Clean-cutover transaction

The migration is one idempotent, fail-closed transaction on a disposable or
explicitly selected Triptych:

1. create and validate new registration, Practice, Profile, policy, Run,
   Record, and Session contracts beneath no production caller;
2. map each current active method's exact `SKILL.md` to one registration and
   optional ordinary folder without rewriting method/folder bytes;
3. derive exact Practice Wikilinks only where the old association is
   unambiguous; otherwise stop and expose the conflicting researcher content;
4. map every academic Profile label, option, order, and requirement to flat
   fields while platform selectors/capabilities move to Platform Action
   definitions; an unrepresentable researcher string stops migration;
5. map the single effective Triptych policy only when unambiguous; per-Skill
   digest overrides do not become hidden permissions;
6. read back and compare method, Practice, Profile, and policy content;
7. redirect every producer, consumer, UI route, CLI route, failure/recovery
   path, test, fixture, and documentation owner;
8. make package/binding/profile-v1/permission-v1/Agent-change-request and child
   execution owners unreachable, non-writable, and nonauthorizing; then delete
   their current decoders, encoders, adapters, aliases, fallbacks, and
   compatibility tests.

Unsupported pre-production files remain byte-unchanged and cannot authorize
behavior. At no point may old and new stores both write or grant authority.
Migration can be retried without duplicate registrations; inability to prove
content preservation or readback leaves the old owner current and the new
state quarantined outside every execution path.
