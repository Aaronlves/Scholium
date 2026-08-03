# Architecture: Product Skills and Maintenance

Part of the canonical document set rooted at [IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md).
This chapter owns release-shipped Skill resources, package ownership, and maintenance transactions; sibling chapters do not restate it.

## Product Skill resources and maintenance

`ScholiumCore/Resources/Skills/` is the sole canonical product-skill tree and
the exact resource directory copied into the `ScholiumCore` SwiftPM bundle.
There is no repository-level source mirror or synchronization step. Catalog
schema 4 separates protected System mechanism from ordinary bundled Methods.
Discuss, Analyze, Synthesize, Write, Critique, Content Fidelity, and optional
Manuscript each declare exactly one public Action and one retained protected
Function. Discuss method prose is separate from its automatic Discussion
protocol. Catalog metadata also exposes capabilities—including
`bibliography-recommendation`—and citation styles while retaining modes only
for internal package assembly.

Function-keyed Method activation and its Settings contracts are retired. No
current decoder or mutation API models the preserved v1 primary, supplemental,
or Practice selections; only the bounded Citation/Bibliography migration reader
described above may inspect its own fields. Current Application operations edit,
disable, replace, and explicitly restore an Action's v2 Working Method through
exact package and binding revisions. Direct edit and restore exchange
the complete package through descriptor-relative operations, recheck the v2
binding before and after package mutation, and publish the displaced package
through the existing machine-local Research Guidance snapshot lifecycle.
Same-volume archival moves the displaced inode; cross-volume archival uses a
verified complete copy and retains the hidden portable inode so a late write
cannot be discarded. Snapshot listing reports the retained package's observed
revision separately, and a corrupt retained stage cannot hide the valid
machine-local snapshot. A binding exchange that commits but cannot complete
verification is reported as recovery-required without rolling the package back
into a state that could contradict the active binding. Every prepared run
captures the resulting exact package and loaded-resource revisions.

The production Research Guidance pane now owns one persistent category list
for Methods, Researcher Skills, Permissions, Sources and Integrations, and
Recovery and Technical. Methods exposes direct edit, disposable bundled
comparison, disable, compatible replacement, explicit restore, hidden
Manuscript activation and direct edit, and explicit default installation for
an established Triptych with no v2 document. Researcher Skills exposes local
package editing,
structural validation, staged directory installation, package deletion guarded
by every current or retained binding, and Action Profile creation, confirmed
deletion, global ordering, seven bounded modules, declared role/source/write
requirements, and a nonexecuting native sheet preview. An Action ID already
owned by any Profile cannot be silently claimed by another Skill. Root-owned
Skill drafts are keyed by Triptych and package; Action Profile drafts are keyed
by Triptych, package, and Action. They survive Skill, category, and Settings-tab
navigation until the researcher saves or discards them without crossing a
Triptych boundary. Methods, Researcher Skills, and Recovery publish asynchronous
reload results only after cancellation and active-Triptych identity checks; the
New Local Skill sheet is dismissed when that identity changes. Deleting an
unused Skill rechecks binding, Profile, root, package identity, and complete
package revision before an atomic
isolation move; production then archives the exact package through the
machine-local recovery store rather than recursively deleting possibly late
external writes. Applying one Profile to other Triptychs
preflights a compatible independently installed package and writes independent
copies; it never synchronizes Skill bytes. Permissions stores one Triptych
default plus deliberate per-Skill overrides in machine-local Application
Support. Bootstrap states the quiet Ask Me Every Time default and points to
this later Settings route without requiring a policy choice.

`ResearchPermissionPolicyStore` owns one strict schema-v1 file per Triptych at
`Triptychs/<id>/research-guidance/standing-permissions-v1/` under Application
Support. A missing file means Ask Me Every Time without creating state. The
store uses descriptor-relative no-follow traversal, private directory/file
modes, an advisory cross-process lock, exact expected revisions, atomic
replacement, directory synchronization, identity proof, and decode/readback
validation. Corrupt, cross-Triptych, linked, over-permissive, or stale state
fails closed; no permission policy is portable research data or a bearer grant.

Application derives every per-Skill approval digest from the current
Triptych-local package revision and the complete set of current Action/Profile
role revisions. Settings carries the exact digest it displayed only as an
expected value; Application re-derives and rejects a stale envelope before
saving. Missing overrides inherit the Triptych default; an explicit override
whose Skill or any Profile changed becomes Ask Me Every Time and cannot fall
through to a broader default. The same derivation is repeated for evaluation,
so a caller-supplied stale digest cannot authorize work. Ask Me Only for Works
requires a researcher decision for every request containing a Work write role,
while Triptych-wide can only permit a later validated bounded grant after all
independent System, Skill, Profile, request, identity, and revision
intersections pass. The initial Target selected
by deliberately clicking an Action is already authorized and is not prompted
again. These policies govern only Scholium-mediated continuations; they neither
monitor a model's reasoning or network activity nor police direct external file
edits, which remain ordinary filesystem concurrency.

`AgentNoteChangeRequest` schema 1 is the non-authorizing coordination contract
for one additional-note or child-Action request. It binds a caller-provided
request UUID to the exact Triptych and parent Local Execution v2 run; the
parent and requested Action, Method Skill, Profile, and Profile-document
revisions; a bounded canonical set of stable Note identities and
expected fingerprints; existing-note operations; and one bounded attributed
agent reason. The request carries no display title or lifecycle assertion;
the Application derives both from current state before presentation. The
Application authenticates the parent against the local run,
rejects requests that do not expand its frozen scope, and re-resolves the
requested Action, package, Profile, role, operation, identity, lifecycle, and
source revision. A cancelled, stale, awaiting-Fidelity, or otherwise
incomplete parent completion closes an unresolved request; a normal complete
parent may remain provenance for a separately authorized continuation. A live
mismatch records only a terminal stale disposition; it never widens the parent
snapshot or grant.

`AgentNoteChangeRequestStore` keeps one strict file per request under
`Application Support/Triptychs/<id>/agent-change-requests-v1/`. The store uses
private modes, descriptor-relative no-follow access, an advisory cross-process
lock plus in-process serialization, atomic replacement, and exact readback.
Request submission and current-state queries borrow the Workspace source-
mutation gate across authentication, source revalidation, and the store
operation, so permanent deletion cannot interleave a new orphaned request
between parent-run discovery and privacy cleanup. Dates retain subsecond
precision so a valid decision immediately before expiry survives canonical
readback.
Exact replay of one request UUID returns the first record. Reusing that UUID
with different payload fails closed, and one parent run has at most one
unresolved request. Pending records expire after a bounded machine-owned
lifetime; decisions are pending, allowed subset, continue without changes,
cancelled, stale, or expired. A decision remains coordination state rather than
a completion key or child grant. Journaled permanent-deletion finalization
purges requests targeting the deleted Note and requests whose authenticated
parent execution contains it.

`AgentNoteChangeClaimCoordinator` is the one MainActor, App-wide owner of
request-to-window claims. Each exact window has its own
`AgentNoteChangeWindowController`, which registers the live Triptych identity,
key-window state, presentation availability, and bounded presentation/focus
endpoint. The claim coordinator never owns a sheet, identity lookup, expiry or
decision task, and never searches the global AppKit window list. One request ID
can be claimed by only one matching window. The key matching window wins, a
closing window releases its claim for another live matching window, and a busy
window retains the request without replacing its existing sheet. Exact bridge
replay updates the claimed controller, while `show_note_change_request` only
focuses that existing claim and never creates a second presentation.

The per-window controller owns the transient request record, display identity,
identity retry, local expiry, snapshot refresh, decision task, and exact
`WindowSheetRoute`. It cancels all four task families on dismissal or window
closure and checks request identity before applying an asynchronous result, so
a cancellation-insensitive late failure cannot revive closed-window state.
`WorkspaceWindowCoordinator` retains only AppKit-native prior-responder capture
and restoration; `ContentView` consumes the window controller rather than
duplicating presentation state.

The shared `WindowSheetRoute` presents one native Agent Note Change sheet. It
derives current titles, roles, and revision state from the live Workspace
snapshot, exposes the requested Action, write operations, Method/Profile
revisions, subset selection, Allow These Notes Once, Continue Without Changes,
and Cancel the Run, and keeps stale or expired state readable. Before a researcher
decision, `WorkspaceStore` flushes registered editors for that Triptych and
Application reauthenticates the parent, Action, Method Skill, Profile, standing
policy subject, Note identities, roles, lifecycle, operations, and exact
fingerprints under the source-mutation gate. Bridge submission authenticates
and binds the request before any editor flush; only then may the App flush and
evaluate standing policy. Both manual and automatic decisions repeat frozen
request validation after policy evaluation, while automatic resolution also
requires a stable repeated policy evaluation whose subject package and
Action/Profile role revisions equal the frozen request. A qualifying standing
policy may resolve the exact validated request without a sheet. The sheet
resolves the current Profile button name and exact Skill display name for
researcher-owned Actions; Allow remains disabled while those names are loading
or unavailable, and raw package identity remains separately labeled technical
evidence. Identity lookup uses a bounded retry, and a later exact replay or
refresh retries a still-pending unavailable identity. At `expiresAt` it removes
the decision controls immediately and uses a
bounded durable-refresh retry before retaining the contract-derived expired
state. Either route records only coordination state. An allowed schema-v2
record freezes an exact child-phase plan; Application revalidates current
Action, Method, Profile, Note identities, roles, operations, and fingerprints
before atomically preparing one independent single-Target child snapshot,
checkpoint, and grant for each approved Note. Partial siblings remain
independent, while interrupted group preparation is reconciled before retry.
All in-App mutations of active Working Methods, Action Profiles, Skill package
content, Skill maintenance state, and standing policy borrow the same gate as
the final request validation and decision write. Actor reentrancy therefore
cannot place a configuration commit between those two operations.

Every new Local Execution v2 Action also receives one short-lived
`AgentCoordinationGrant`. The local execution persists only its SHA-256 digest,
bound Triptych, parent run, exact Action revision, and expiry; a non-Codable
authorization carries the plaintext key only in the live delivery packet.
`WorkspaceStore` owns one process-wide AF_UNIX listener
under its validated Application Support root. Its private parent is mode 0700
and the socket is mode 0600. The server holds an exclusive owner lock,
validates the peer with `getpeereid`, accepts one versioned length-prefixed JSON
request per connection, bounds frames and I/O time, and never logs request
bodies. The client validates socket type, owner, private modes, and server UID
before transmitting the key. App absence is a typed unavailable result; the
bridge neither launches the App nor queues work.

The serial listener owns at most one asynchronous request handler. At its
deadline it cancels the task and reports `outcome_unknown`: cancellation can
race a durable state transition, so the caller must converge by querying the
same request ID instead of inventing a new one. If the handler exits within a
bounded cancellation grace it is reaped before another request. If it ignores
cancellation, the listener closes and retains its exclusive owner lock until
the task finally exits; no later request can accumulate behind it. A
client-side I/O deadline after connection is classified the same way because
delivery cannot be disproved. `stopAndWait` reports failure after a bounded
wait; `WorkspaceStore` then leaves its still-borrowed Application runtime alive
rather than racing shutdown against that task. It also retains and logs a typed
bridge-startup diagnostic without disabling an otherwise valid runtime. Its
nonblocking deinitialization cleanup likewise retains both bridge and runtime
until owner release, then shuts the runtime down; it never destroys the runtime
under a cancellation-insensitive handler.

`scholium agent mcp serve` is handled before CLI snapshot-runtime creation and
uses MCP stdio framing only. It exposes `request_note_changes`,
`show_note_change_request`, and `cancel_note_change_request`; coordination keys
are tool arguments arriving on stdin, never command-line options. Submit,
status, and cancel authenticate the parent grant digest, while exact request
replay and cancellation remain idempotent. The first accepted request ID is
atomically bound into the parent Local Execution before request publication;
that ID may be retried, but no later ID can consume the key even after a
terminal decision. Tool failures retain a typed bridge
error code in structured MCP output. Status and cancel first read the stored
parent without applying expiry, authenticate the grant, and only then execute
the ordinary state-changing query. A bridge decision is still not a write
grant. An allowed schema-v2 decision stores only a versioned correlation plan:
one shared group ID plus reserved independent child run IDs for the exact
approved Note subset. Application then re-resolves current Action, Profile,
Method, Note identities, and fingerprints before preparing each child as its
own Local Execution v2 run. Every child has one frozen Target, its own
exact-Note continuation recovery checkpoint outside rolling automatic
retention, its own activity grant and completion validation, optional
final-revision Fidelity child, and durable parent/request/group lineage. The AF_UNIX response
delivers those live child packets only after their complete persisted evidence
matches the plan; plaintext keys remain delivery-only. Neither the plan nor
lineage is consulted as authority without the exact allowed request, current
parent, Action snapshot, checkpoint, and grant.

Revision-bound Resynthesize reuses the same independent Local Execution v2
child mechanics without impersonating an Agent change request. Application
rereads the completed Synthesize record, exact Topic Target, actually-used
Analysis revision, and current changed revision before reserving a new run.
That child owns a new activity grant, an exact-Topic **Before Resynthesis**
checkpoint, frozen Synthesize Action snapshot, cancellation/conflict/recovery
path, optional final-revision Fidelity, and `resynthesis` lineage back to the
source record. Its revision context is validation evidence, never a grant; the
child may write only the current Topic authorized by its own envelope.

Action assembly seeds protected Core, Research Integration, and Discussion
mechanism independently of any editable Method dependency list. A Triptych
Method may be self-contained or name its own bounded resources; it is never
required to mirror bundled `references/` filenames. Package identity and all
resource bytes are captured as one coherent revision, so an interposed
external Skill edit fails closed instead of producing a mixed snapshot.
Practice resources remain exact selections, and Fidelity resources remain
bounded to the checks selected for that run.

The split Methods load a complete adaptive core and expose no secondary
researcher or agent mode choice. Legacy
`ResearchFunctionConditionalResource` and selection payloads remain decodable
for existing machine-local records, but every current Function advertises an
empty resource vocabulary, validation rejects nonempty selections, and the
old selection command is absent from public CLI/help. Current
Analyze, Synthesize, and Write requests also require the exact current Target
as their sole write Target; additional Note writes require later independent
child phases rather than a widened parent grant.

Researcher Skill evolution is an independent Research Guidance maintenance
slice. Contracts carry the expected revision, complete
`ResearchSkillProposedPackage`, evaluation, and confirmation token; Application
enforces explicit request and confirmation. Core validates the proposal against the same bounded package and
dependency graph as installed local Skills, snapshots the entire opted-in
Triptych-local package, replaces it through descriptor-relative operations,
reads it back, and rolls back on failure. Bundled packages remain immutable.
This path is never selected by Action execution.

Snapshot inventory is global to Research Guidance rather than derived from the
selected Skill. Core enumerates snapshots through stable directory descriptors
and no-follow reads, returns valid snapshots together with typed per-entry
issues, and never lets one corrupt entry hide other recovery sources. Restore
accepts an explicitly expected present-or-missing current state, validates the
snapshot as a Researcher Skill, and uses atomic replace or guarded missing-
package installation. An existing displaced package becomes a new undo
snapshot before replacement; a missing package has no displaced state. The UI
confirms complete-package replacement before invoking this authority.
Direct Working Method edit and bundled restore publish their displaced package
in this same UUID/manifest/package format, so existing listing and restore
operations remain the sole machine-local recovery owner rather than creating a
second portable history inside `.scholium`. Cross-volume fallback is the narrow
exception: the verified snapshot records that its displaced hidden package is
still retained under `.scholium/skills`; automatic cleanup is intentionally
not claimed while an external participant may hold its inode open.
