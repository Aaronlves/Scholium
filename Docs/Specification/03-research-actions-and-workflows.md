# Specification: Research Actions and Workflows

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 8–11.

## 8. Research Actions, Skills, and direct agent work

### 8.1 Action, Run, and method ownership

The Research Inspector's **Actions** mode exposes only the code-owned Platform
Actions valid for the current note. Profiles may change their academic fields,
visible names, order, and enabled state but cannot create another executable
Action identity:

| Target | Default Actions, in order |
| --- | --- |
| Analysis | **Discuss, Analyze, Check Fidelity** |
| Topic | **Discuss, Synthesize, Check Fidelity** |
| Work | **Discuss, Write, Critique, Check Fidelity** |

Analyze adapts to creating or updating an Analysis. Reading several Materials
assembles context without creating another Action mode; Analyze and Synthesize
remain separate scholarly Actions.

A **Run** is the only working object for one Action. It owns the task, initial
research object, frozen Method Context, Result Contract, current capability
availability, short-lived Bounded Write Set, per-document transaction results,
status, and one temporary result payload. It limits Research Context queries
but never owns the Triptych, a provider, an index, or a query response. The
researcher sees only **In Progress**, **Needs Attention**, or **Ended**, with
an accurate reason such as waiting for Agent, conflict, write result unknown,
completed, failed, cancelled, or manually ended.

One protected **Platform Action Definition** owns each Action's supported
initial roles, required Note/Material/source selectors, machine fields, and
operations Scholium can actually execute. It is not editable configuration and
does not grant permission. An **Action Profile** owns only researcher-configured
academic interaction: visible name/order/enabled state, role-valid placement,
academic inputs, and academic result fields. Profile fields are flat bounded
text, single-choice, or multi-choice values and may be excluded, optional, or
required. A Profile cannot declare Search, reading, Metadata, Zotero,
mutation, recovery, roles, operations, or permission.

Each available Action resolves exactly one enabled **Research Skill
Registration**. The registration stores one hidden stable relation key, the
researcher-visible name, Action binding, one primary Markdown entry path, an
optional ordinary local Skill-folder path, and enabled state. The key is not a
user-visible Skill ID or version. The primary Markdown entry is the method
authority. Scholium stores and delivers its exact current text, but does not
define a package schema, version, dependency graph, resource manifest, digest,
history, marketplace, or executable plug-in contract.

The optional Skill folder is ordinary researcher-owned filesystem content.
Portable registration contains only a Triptych-relative location or a
machine-local marker; Application Support alone retains any absolute primary
Method/folder path and security-scoped bookmark under the opaque registration
key. An absolute path never enters a portable Record or copied handoff.
After authenticated local pairing, Scholium may deliver only the frozen path
string. It never enumerates, copies, snapshots, hashes, validates, proxies,
uploads, explains, or executes that folder. The Agent reads any supplementary
files through its own local file capability. Missing entry or folder paths are
reported explicitly. An inaccessible folder never causes Scholium to invent a
transport fallback; the Agent may continue from the delivered Skill entry or
report the limitation.

**Philosophical lenses** are methodologically substantive ordinary reference
files inside a Skill folder. `SKILL.md` explicitly routes the smallest
task-relevant lens set and states when a selected lens's evidential
distinctions and safeguards become part of the Skill's method. A lens may
combine a perspective, procedure, and criterion, but it is not a second
product object: Scholium creates no lens catalog, registration, resolver,
snapshot field, Settings destination, Record field, or dependency graph.
Reference files never enter research Connections, grant capability, create
evidence, or override the researcher request or platform safety. Scholium does
not infer lens selection from Wikilinks or filenames.
Pre-cutover `.scholium/practices` bytes remain untouched and nonauthorizing;
Scholium neither reads nor migrates them.

If the machine-local Skill locator document is invalid, Skills exposes a
confirmed archive-and-reset action. Scholium preserves the exact invalid file
under a unique sibling recovery name, installs an empty current locator
document, and requires affected external Skills to be selected again on that
Mac. Portable registrations, Skill and reference files, Research Records,
and vault files remain unchanged; I/O or unsafe storage is not silently reset.

Run creation freezes the registration relation, exact Skill entry text,
optional Skill-folder path string, and Result Contract. Later registration,
Skill-entry, or Profile edits affect new Runs only; Scholium does not freeze or
track folder contents. References are read through the Agent's local file
capability only when the frozen Skill routes them. A new Triptych begins with
editable current default Skills and bundled lens references. Updates never overwrite
researcher edits. **Restore Default…** means the current app-bundled default
and states the replacement consequence before writing.

Bundled defaults may state research burdens, not one universal method or
researcher grade. Scoped Agent judgments never certify novelty,
publishability, doctoral level, field completeness, or acceptance.

Scholium-mediated Skill improvement replaces only the exact expected
`SKILL.md` and reads it back. Ordinary references are edited through ordinary
filesystem tools. There is no recovery copy, revision list,
version browser, comparison history, package lineage, or past-method
reproduction promise.
Research Records retain only the hidden registration relation, then-visible
Skill name, and Profile revision, never Skill text, reference names, or folder
contents.

The method/context stack has fixed roles:

1. protected Scholium execution and safety facts;
2. the researcher's current request;
3. the Skill entry;
4. ordinary references, including philosophical lenses, that the Skill
   explicitly routes and the Agent actually reads from the registered folder;
5. any conditionally attached release-managed Integration Adapter, scoped only
   to interpreting and operating its integration; and
6. Notes, sources, Records, Search results, Metadata, research state, and all
   provider content as **Research Evidence Context**.

Evidence content never enters Method Context, changes platform capability, or
authorizes a tool, network destination, write, or next Action. Instructional
text in a PDF, Note, Record, summary, webpage, metadata field, or provider
response remains untrusted research material. A material conflict between the
researcher request and method is made visible; it is not silently averaged or
resolved by the material itself.

### 8.2 Agent entry, local pairing, layered delivery, and Research Context

GUI preparation and Agent-originated `agent start` share one Run contract. GUI
offers the one-time Pairing Code below;
direct start supplies Triptych, Action, target, and all typed Profile inputs,
then receives a Session directly. Both routes use only `scholium agent` and share
Context, writes, Result, continuation, End, conflict, and recovery. A write Result becomes final after its own transaction
and Result validation converge without preparing or attaching a Check Fidelity
child. Analyze performs
its bounded source/content fidelity self-check through its registered Method
before submission. **Check Fidelity** remains a separate read-only Action
prepared only when the researcher explicitly initiates that Action for an exact
revision. Raw UUIDs authorize nothing, and no Result completion invents a
second Run or child lineage.

For Discuss, Session exposes frozen `DialogueResponseContract` and
`agent discuss-reply`, appending one attributed Agent turn keyed by
`statement_id`. Exact repeat returns `already_recorded`; changed content
fails closed. After at least one durable Agent turn, `agent finish-discussion`
finishes that same Run, forms its portable Discussion Record, and revokes the
Session. Finish accepts no Result body and grants no Note/Metadata mutation,
evaluation, Undo, recovery, new Run, or filesystem access. It does not imply
researcher acceptance.

Analyze-only `new_analysis` preflight returns the Analyses vault, applicable
managed fields, optional Settings preferences, fixed authored-YAML fields,
root destination, and target
recovery state. Agent folders, placeholders, retries, and fallback names are
invalid; researcher placement requires an existing Analysis. Only `ready`
returns a start payload. Application re-resolves both. Request ID reserves identity;
the first consequential start freezes destination, route/binding, authored
YAML values, source type, managed metadata values, and academic purpose.
Settings changes do not alter that request or creation authority. Other input
changes conflict; identical starts coalesce.
`researcher_provided` grants no source/Zotero claim.

Results encode retry safety, identity reuse, and one next step for occupation,
stale projection, replay, Session expiry,
and operation-specific unknown outcome. Unknown End or Discussion Finish is
not retryable because Session may be revoked. Retained identity with missing/trashed
source permits Restore or distinct creation—never recreation, overwrite,
deletion, or retry rename.

Direct Agent connection is local, provider-neutral, and bound to the current
Scholium application process. The researcher deliberately copies one complete
handoff into the selected Agent conversation. It contains the opaque Run
locator, short-lived one-time **Pairing Code**, and direct instructions for the
Agent to run the installed `scholium` CLI itself, enter that code through the
pairing command's standard input, and load the authenticated Run context. The
handoff contains no research text, complete method, local path, internal
fingerprint, permission payload, result schema, Session secret, or reusable
bearer authority.

Pairing exchanges the one-time code for a hidden **Connection Session**. Both
values are independently generated, bounded, nonpredictable, and never stored
in recoverable plain text. The code enters only the researcher-selected Agent
conversation and pairing standard input; the reusable secret enters neither.
Neither value enters a vault, command argument, URL, ordinary output, log,
later prompt, Result, or Record.

A Session binds the current macOS user, current application-process
generation, allowed Runs, expiry, and revocation. One Run has at most one
write-capable Session. Re-pair or direct-Session replacement revokes that Run
and all child locators derived from its authority root, while preserving
independently attached Runs. Ordinary reconnection needs no new pairing while
process and Session remain valid; full app exit, crash, update, or Mac restart
invalidates all Sessions. Re-pairing changes connection authority only, never
the Run, confirmed writes, Records, conflicts, or recovery. Keychain does not
restore Sessions.

The packaged App and matching CLI use one per-user, loopback-only bridge with
bounded messages, timeouts, and version checks. It relies on the Pairing Code
and process-bound Session, owns no research or recovery state, and exposes no
relay, LAN, or public endpoint. Pairing requires Agent access to that local
CLI/bridge; cloud copy is not a Session. Transport mechanics belong to
[Research Actions and Execution](../Architecture/02-research-actions-and-execution.md#pairing-and-delivery).

Delivery is progressive:

- a newly paired Agent session receives Core Protocol, capability catalog, and
  Session boundary once;
- each Run receives a short Run Brief, exact Method Context, Result Contract,
  and fillable `next_actions` for Discuss reply/finish, each ready write, or the
  strict non-Discuss Result; Fidelity adds its exact boundary and inspections;
- Research Context arrives only after an explicit query;
- a specialized capability explains only its additional contract on first
  use; and
- ordinary calls return data, result, error, next step, current Run/Action,
  and `reload`/`help` anchors without repeating Core Protocol.

`reload` revalidates exact Target, Materials, and formal source, then returns
the frozen Skill entry, folder path, Result Contract, and current state.
Genuine drift returns `stale_run`; an authenticated write uses the Run-owned
revision and completes without scheduling a Fidelity Action. Reload substitutes
no later method and replays no cached Context response, ranking, availability, or
cache.
Local absolute paths are delivered only after authentication.

The versioned, read-only **Research Context Query/Response** contract belongs
to Application. A query contains one or more closed clauses: Note discovery,
exact Note or section read, explicit direct-Relation inspection, canonical
Metadata inspection, Record inspection, current-Run source-Material inspection,
or researcher-state inspection. Material inspection has no free query: it can
return only the path-free source binding explicitly selected and frozen for the
authenticated Run, together with that Run's existing Zotero bibliographic
snapshot when present. It is not Material discovery or generalized Zotero
search. Each clause fixes Triptych scope, its legal query or section selector,
an item limit, and whether the returned material may be proposed for Context
Use. A query cannot choose a provider, source-kind/purpose cross-product, Run,
Triptych, or authorization scope. Application binds current Run, Session,
Triptych, authorized scope, and generation before provider execution. Research
Context composes the one Search capability, exact Note/section read, explicit
direct Relations, canonical Metadata, Research Records, the current Run's
selected source binding, and only researcher-state facts whose existing owner
proves actor, object, action meaning, revision/scope, and text. It creates no
Agent-only parser, ranker, JSON scan, hidden index, source cache, persistent
response, Research State store, researcher profile, vector store, or automatic
synthesis.

Every returned item uses one closed **Source Reference Envelope** carrying:
source kind, authoritative owner reference, stable object identity, actor
class or unknown, object/vault role, exact revision or fingerprint, locator or
source range, authorized scope, currentness, evidential layer, retrieval
reason, and material limitation. The envelope expresses provenance and
discovery, not confidence, relevance truth, philosophical support, importance,
or acceptance. Typed Search reasons preserve authored YAML ranges, range
absence for managed Metadata, and direct-relation provenance without becoming
prose or a second interpretation. Unknown owner kinds, malformed identities, and
a coarse Metadata/direct-relation reason without its typed match fail closed.

Response availability distinguishes **Current**, **Partial**, **Stale**,
**Unavailable**, and **Invalid Query**. Every requested clause has its own
availability, items, and limitations, so an unexecuted channel cannot appear as
Current with an empty list. Partial names an incomplete page or unavailable
provider/scope. Stale references cannot navigate or be recorded as current use.
Provider failure cannot return an older response, broaden scope, silently omit
a clause, or present unavailable as no matches. App and CLI consume the same
Application response; delivery adapters do not parse, rank, or fill provenance.

Exact Note and section material is delivered only as lossless source-range
pages. A page preserves its UTF-8 text, including a byte-order mark, newline
form, leading or trailing whitespace, and final newline; semantic snippets are
a separate response form. A stateless continuation cursor binds the
authenticated query, clause, selected Note, revision, complete source range,
and prior-page digest. Changed query, scope, owner, revision, range, or page
identity becomes Stale rather than selecting new material. Page and complete
response budgets remain below the local bridge frame; they are delivery limits,
not permission or storage state.

The Source Reference Envelope's response-local ID is correlation only, not
authority. Scholium retains no process registry of previously delivered
references. Context Use and Continue Research submissions remain bound to an
authenticated Run, must carry that Run's authorized scope, and recheck the
current authoritative owner, revision, and locator before any reference is
recorded or handed forward. A Material reference is valid only when it matches
the Run-frozen `ResearchSourceReference` and the existing source-access owner
can reopen the same identity and fingerprint; bookmarks, absolute paths,
source bytes, and provider-local metadata never enter the envelope. These checks
establish a current referent, not that delivery itself caused use; actual use
remains explicit Agent testimony.

Researcher state is only an ephemeral typed read view over existing owners.
The maximum meanings are narrow: exact-fingerprint Settle means that revision
was then judged sufficiently stable; researcher-authored text and turns mean
the researcher wrote them in that context; an explicit researcher Action or
continuation choice records that choice; a Researcher Evaluation records the
submitted evaluation of that exact Record. Opened, selected, searched, dwell,
pin, autosave, authorization, Agent output, and silence never imply reading,
importance, support, commitment, acceptance, or belief. Missing proof returns
absent or unknown rather than an inferred psychological state.
Research Context reads only the portable Settlement judgment and its exact
fingerprint. Settle creates no machine-local source version, recovery pin,
importance, stance, adoption, or separately retrievable state item.

### 8.3 Collaboration policy, Bounded Write Set, and exact writes

Each Triptych has exactly one collaboration policy:

1. **Ask Me Every Time**;
2. **Ask Me Only for Works**; or
3. **Full Access**.

There is no per-Action or per-Skill standing override and no method-digest
permission subject. The policy controls when Scholium interrupts the
researcher; it is not a trust score, bearer credential, or capability source.
The researcher selecting an Action already authorizes reading task-relevant
Triptych material and the displayed operation on its initial object. That
object enters the Run's Bounded Write Set without a redundant second prompt.
Reading a Work does not trigger the Works policy.

Adding extra documents is a distinct consequential operation. Ask Me Every
Time presents one bounded set and permits a subset; Ask Me Only for Works asks
only when it changes a Work; Full Access binds a valid set without a sheet. A
sheet's sole denial is **Continue Without Additional Notes**; **End Action**
separately ends the whole Run. The same policy governs a next Run. Skill-entry
edits require a researcher-initiated method-improvement action. No
policy authorizes third-party disclosure.

The **Bounded Write Set** is hidden, short-lived, expandable, and owned only by
its Run. Each member binds Triptych, stable existing-document identity or one
explicitly authorized new identity, vault role, permitted operation, exact
expected revision or proven absence, expiry, and authorization provenance.
It contains no document bytes, research plan, write order, academic relation,
or persistent group. Single-request member count, Run-total member count, and
encoded payload have explicit testable limits; exceeding one returns a bounded
continuation result rather than widening authority.

The operation is always explicit: `create_note`, `modify_markdown`,
`modify_source`, `modify_metadata`, `set_zotero_binding`, or
`clear_zotero_binding`. `modify_markdown` changes the body only. The distinct
`modify_source` operation accepts the complete authored Markdown source,
including YAML, and never reconstructs it from a projection. `modify_metadata`
changes only granted keys in the portable Metadata record and never changes
Markdown.
`create_note` binds a proven-absent path, one authorized new identity, the
fixed authored-YAML scaffold, and for Analysis an allowed source type plus
optional typed initial fields. It is idempotent only for the same hidden creation operation;
after creation the identity is no longer new. Body authority cannot rewrite
frontmatter, Metadata authority is limited to exact granted managed keys, and
either source authority is insufficient for integration binding. Binding authority
is insufficient for Markdown. A `modify_source` member is still limited to
its one existing Note identity, expected revision, Run, and operation
capability; its complete candidate must be valid UTF-8 and have valid or absent
frontmatter before the repository transaction begins. Agent Analysis creation
must satisfy source-type applicability for every value it does provide.
Settings-preferred fields are guidance only; omission never blocks creation or
produces placeholders. Typed authored values replace only the fixed `summary`
or `keywords` placeholder in the same creation request.

One authorization may bind several exact documents, but every actual mutation
uses a nonreusable short-lived capability bound to the current unique writable
Session, Run, complete allowed document set, and each member's expected
revision. Each call names one member and has one hidden idempotent operation
identity. Before writing, Scholium revalidates Session, Run, membership,
identity, role, operation, containment, current revision, and policy facts that
can revoke unused Full Access authority. Before Agent access, each existing
writable Note receives one exact Run-bound starting revision used only for
Agent diff and direct Undo. Existing-note source writes build and validate the
bounded body, complete source, or property candidate, atomically replace, read
back, and advance that evidence's exact ending revision. Creation
instead re-proves absence, claims the exact
path without fallback naming, and must jointly read back both source and its
reserved stable identity. It has no fabricated empty-source revision or
change preimage. A confirmed Scholium write advances only that member's expected
revision; a confirmed creation consumes that one-use new-identity authority.

The set is not a batch transaction. One member's conflict, external change,
failure, or abandonment does not roll back confirmed siblings, revoke
unchanged references, or create a child Run. An external change makes only the
affected member stale. Already-submitted file transactions must reach a known
written/not-written/recovery-needed result; policy tightening or manual End
cannot pretend to cancel them. Manual End cancels only a Run without confirmed
writes. A confirmed change requires Result submission so Record and Review
provenance cannot be discarded; unknown writes and recovery duties block End.
Run cleanup
removes the write set only after every transaction converges; transaction recovery may outlive it only as
the existing machine-owned recovery duty.

Direct Agent editing is the product model. Each mutation proceeds through the
current Run's exact Bounded Write Set and one-document transaction. Scholium
guarantees scope, identity, revision, transaction truth, exact displaced bytes,
conflict, readback, and recovery. It does not certify fidelity to a source,
preservation of the researcher's thesis, philosophical quality, or researcher
acceptance. Those remain method, attributed reasons, visible changes,
recovery, optional researcher-initiated Check Fidelity, and researcher
judgment.

### 8.4 Result Contract, one Research Record, and researcher review

Each Run freezes one **Result Contract** from its Action Profile. Academic
fields are flat text, single-choice, or multi-choice, each excluded, optional,
or required. Scholium pre-fills Action, initial object, time, machine state,
actual changed documents, per-document outcomes, conflicts, and recovery.
Every submitted result also requires one concise, one-line **Record Title**.
It is the frozen interface identity of the completed Record, separate from the
Action Profile's academic fields, focal Note title, source title, and process
summary. Discussion derives the same identity from its first researcher-authored
opening statement. Agent fields otherwise contain only irreducible academic
judgments or bounded testimony.
Machine facts are never recopied by the Agent; one academic judgment is not
requested under several labels. `Unable to determine`, `Not applicable`, no
warranted change, no academic publication used, and an honest blocked result
are valid when the Action permits them.

The common first contract is one `Academic Outcome` text field plus machine
facts. Action-specific defaults refine the same model:

| Action | Core academic result | Closed declaration | Optional |
| --- | --- | --- | --- |
| Discuss | attributed turns; optional Overall Conclusion on Finish | none per turn | Open Question |
| Analyze | Source Reconstruction | Coverage: all declared scope / specified part / partial / unable; Reliability: no material limit / incomplete access / OCR-extraction issue / edition-locator issue / unverified | Agent Evaluation; Further Research |
| Synthesize | Synthesis Outcome | Contribution: add / correct / qualify / connect / reopen / no warranted change; the last is exclusive | Unresolved Tension; Next Step |
| Write | Writing Outcome | Change Kind: draft / revise / restructure / clarify / no warranted change; the last is exclusive | Remaining Pressure; Evidence Basis |
| Critique | Assessment | Issue Kind: interpretation / argument / source use / objection-reply / alternative / other / no material issue; the last is exclusive | Significance; Recommendation |
| Check Fidelity | Finding | Status: no inconsistency found in checked scope / inconsistency found / unable to verify | Suggested Correction |

Substantive durable interpretation, evaluation, synthesis, or integration must
include enough public reasons and material limitations for later research
judgment. This is not hidden chain-of-thought or a universal basis field.
Write Records do not duplicate long target prose; Discussion turns themselves
may supply the public reasons. Structure validation proves only contract
validity, never method understanding, evidential sufficiency, quality, or task
success.

One Run owns one result payload—Record Title, Agent academic fields, and
Scholium machine fields—until every initiated write and recovery duty is
determined. Safe finalization creates exactly one portable **Research Record**,
the sole durable result object. The Action row derives its state from the Run
and Record and opens that Record only after an explicit researcher action.
Private interruption evidence reconciles to the same result and Record.

An applicable result may include one bounded **Context Use Report**. The Agent
identifies only references that actually affected its result; Scholium verifies
that each reference belongs to the Run's readable scope and retains the Source
Reference Envelope plus separate Agent-use testimony and machine-validation
facts for the current owner, revision, and locator. Search hits, selection,
expansion, or delivery do not imply use, and Scholium does not infer them from
process history. The Record never retains unused candidates, query, ranking,
provider-internal ID,
complete response, context assembly, prompt, read count, click, dwell, or tool
trace.

Section 6 owns system-Trash deletion: whole finished Records and
Discussions are removed after every source moves; external disappearance
never cascades. Settlement, source access, stable identity, and Critique
association remain for Finder reconciliation.

Every safely finalized Action Research Record may contain one optional current
**Researcher Response** owned by that Record. One editor presents **Researcher
Evaluation** first and **Method Feedback** second, then saves or clears the two
semantic partitions in one atomic **Save Response** replacement. Discussion
Records have no source-change review or Researcher Response workflow. Method
Feedback remains a researcher-authored comment about the exact Method used by
the Record; saving it alone authorizes no Agent access.

The evaluation contains:

- multi-select **Observed Issues**: source/attribution, concept/interpretation,
  argument/objection-reply, epistemic identity/researcher state,
  evidence scope/restraint, research help/next step, or other;
- **No issue marked in this evaluation scope**, mutually exclusive with issue
  selections and never meaning truth, completeness, adoption, or finality; and
- optional **Valuable Discovery** plus a short note for a useful new relation,
  objection, evidence gap, or research direction.

Absence means unevaluated. There is no score, rating, mandatory severity,
root-cause diagnosis, queue, history, profile, training channel, automatic
method change, retrieval demotion, or adoption inference. Evaluation is
researcher-authored evidence about one exact response; it does not change the
finalized Agent/Scholium result, Record completion, Settle, or philosophical
truth.

Every Response save carries the expected Evaluation revision, expected Method
Feedback revision, and immutable finalized-result fingerprint. The Record
store validates all three under one lock, atomically replaces both partitions,
reads back, and otherwise rejects the entire save while retaining the local
draft. Clearing either saved partition is an explicit confirmed edit inside the
same Response editor. A deleted or unavailable Record cannot receive or
redirect the draft.

Review is a researcher-owned milestone for one Note's current saved state, not
a Record, change, or hunk disposition. Reading Records or Changes, restoring
source, and closing windows never reviews. **Mark Current Note Reviewed** stores
stable Note ID, exact observed saved revision, time, and the system-derived set
of pending `(Record ID, Note ID)` Agent-change activities. A later Record is
uncovered; a later confirmed Agent change reopens **Needs Review**. Researcher
edits do not resurrect covered activities, and the retained revision prevents
calling newer source reviewed. Review means neither acceptance, truth,
adoption, Settle, nor fidelity.

Only confirmed Agent changes create Review work. The origin always participates
in its one Record; other Notes require Action target, confirmed change, verified
Context Use or actual Material use, or Discussion participation. Each Note
projects the same one-Run/one-Record identity. Origin-only or used-only links do
not need Review. A no-change Action finalizes, ends, and emits one deduplicated
Result-arrived notice without another decision.

Agent edits are already authoritative source when the Result arrives. A
modified change begins at the expected revision of that document's first
successfully committed Agent write and ends at the last confirmed readback;
conflicted, abandoned, or uncommitted attempts never move that baseline. Thus
an external edit made after Run preparation but before the first Agent commit
is preserved by direct undo. A created change instead has no starting revision;
its participant baseline is its first committed created revision. Comparison
accepts only confirmed modified revision pairs and never labels Discussion,
researcher, or external changes as Agent work.

Refresh Authority may replace the provisional starting evidence only before
the first committed Agent write to that Note. After a committed write, refresh
is stale: incorporating a later external revision would misattribute external
or researcher work to the Agent diff and make direct undo unsafe.

Direct Undo is a recovery action, not Review or delayed authorization.
Application alone resolves the first committed write's Run-bound starting
bytes, current stable Note identity and path, and exact final Agent revision. It
is available only while current source still equals that final revision. Undo
restores one complete selected document through the ordinary revision-checked,
atomic, readback-verified repository save; a multi-document request is a
sequence of independent transactions, not an atomic batch. A rename follows
stable identity. A later edit, missing Note, failed readback, or uncertain
commit remains explicit and never triggers an approximate or hunk-level
restore. Undo facts stay with the recovery boundary and never become Review
judgments.

An Agent-created Note still creates Note Review work and visible Record
provenance, but the first version offers no direct Undo or exact starting
comparison because no source preimage existed. Scholium never fabricates
an empty revision or silently deletes or trashes the created Note as recovery.

Portable Records remain one strict closed schema under
`.scholium/research-records/v1/`; unknown schema/fields fail closed. The same
portable owner stores one current cumulative Note Review fact per Note,
separate from Record bytes and excluded from finalized-result identity. A Record
retains its frozen Record Title, attributed researcher and Agent statements, participating exact Note
revisions, Action, minimal method provenance, Context Use Report, confirmed
changes, discrepancies, Fidelity completion, the explicit Analyze source route,
Analyze-only Literature
Recommendations, and current Researcher Response. Researcher Response is
excluded from the finalized-result fingerprint. It excludes raw secrets,
bookmarks, absolute paths, method/folder snapshots, prompts, token counts,
transport logs, window state, and diff hunks. Markdown remains authoritative
research content; Records never reconstruct writable source.

Research Records presentation, collection behavior, Reading Leads, evidence,
evaluation, and deletion are owned by [§18.5](07-document-and-research-interface.md#185-contextual-research-and-actions).
Those routes never change the portable ownership above. Analyze-only Literature
Recommendations remain occurrences inside their parent Record under
[§15.3](05-integrations-onboarding-and-boundaries.md#153-literature-recommendations-and-the-zotero-boundary);
**Reading Leads** is only their collection projection, not another durable kind.

### 8.5 Attribution, continuity, method improvement, and failure

Scholium-owned records keep four authorship classes distinct:

| Class | Proper content |
| --- | --- |
| Researcher-authored | Comments, direct Markdown, explicit choices, evaluation, and deliberate judgments |
| Agent-authored | Analysis, synthesis, writing, Critique, replies, candidates, uncertainty, and diagnoses |
| Scholium-established | Identities, revisions, configured methods, scope, conflicts, confirmed changes, and application failures |
| Deliberately unknown | Unexpressed intention, belief, importance, truth, reasons for silence, and private lessons |

Authorization or confirmed Agent writing does not become researcher authorship
or adoption. A canonical `summary` is a document declaration whose actual
writer is reported only when an existing authoritative operation or Record
owner proves that act. Research Context otherwise marks the current Note
revision's actor unknown; it never infers writer from authorization, the last
Run, file location, user identity, or vault ownership. Agent discoveries remain
attributed candidates until retained through the one Result/Record or an
authorized exact-document write. Scholium creates no Discovery or writer-history
store.

**Continue Research** begins another Action and therefore another Run. It is
available only after the current Run has a determined completion or legitimate
blocked result. The initiator supplies the next Action, initial object, short
academic purpose, and only the needed finding/question/hypothesis together
with its epistemic status and why the next Action needs it. Scholium supplies
the `continued from` Record relationship.

Full Access may create the next Run directly; the other policies use the same
single decision rule and ask only when required. The new Run independently
resolves current Skill, Profile, policy, Result Contract, and
write set. It does not inherit document handles, transaction state, method,
permission decision, Research Context response, candidates, rank, cache,
availability, or future Assembly. Handoff references are re-resolved against
current owner, revision, scope, and generation. A selected source-Material
reference reports current, changed, missing, or unavailable from the existing
source-access owner. Changed, missing, revoked, or unavailable evidence is
reported; a requery reduces stale-context inertia but does not guarantee
completeness or truth.

Researcher State has a different continuation boundary because it is a
Run-scoped view rather than a transferable owner object. If a parent handoff
mentions one of its references, Scholium excludes every parent Researcher State
envelope from the child handoff and reference checks, marks that the child must
issue `inspect_researcher_state`, and rebuilds the view only when that new Run
queries current Application-owned objects. The parent request remains
attributed Agent input in the parent Local Execution record; the parent state
response, content, fingerprint, availability, and provider state do not cross
the Run boundary. Requery proves neither completeness nor correctness.

The next Record alone stores `continued from` after it safely forms; `continued
as` is derived in reverse and never rewrites the prior Record. Rejection or
abandonment changes no prior completion. Agent-initiated continuation under
Full Access remains an Agent act rather than researcher intent.

Continue Research is initiated only through the authenticated CLI/Agent Run
protocol. Research Records exposes no Continue Research button or
researcher-side preparation port. The parent Action presentation shows the
continuation and, after the child Record safely forms, derives its relationship
from `continued from`. That child remains one portable Record and remains
searchable, but the Records collection folds it beneath its parent rather than
creating a second peer top-level row.

The Record's Researcher Response accepts one short Method Feedback comment and
the Record exposes an explicit **Improve Current Method...** action. Saving or
editing the comment alone authorizes no Agent access. Starting that action, not
Full Access, Evaluation, or source disposition, creates one
separately paired improvement Run bound to the parent Record, exact comment
revision/text, finalized Result fingerprint, original registration relation,
current Skill entry and its exact revision. It
inherits no ordinary Action context, Result operation, Bounded Write Set, or
blanket folder authority.

The Agent may replace exactly one current `SKILL.md`,
or return one `diagnosed_no_change`/`unavailable` diagnosis after judging
whether the issue concerns method, execution, material, provider, request, or
preference. CLI obtains machine revisions from authenticated context rather
than researcher copying. Every replacement uses one nonreusable short-lived
capability, expected-revision transaction, and exact read-back. A committed
file edit can reconcile after interruption
without a second write. A successful read-back edit or safely saved diagnosis
deletes only the still-exact comment; modified comments remain. Identical
terminal retry is idempotent and different input fails closed. A deleted Record
deletes its comment; a missing registration leaves it readable and manually
removable but cannot redirect it to another Skill. Local Execution retains
only the one current improvement Run and one terminal outcome: there is no
feedback queue, processed state, history, or automatic evolution.

Conflict, cancellation, timeout, unavailable provider, missing method,
unreadable source, invalid contract, and unknown write result remain accurate
Run outcomes. Missing material narrows or blocks the scholarly result; it never
authorizes fabrication. Manually ending a Run revokes new operations and its
Session access but cannot destroy an in-flight transaction or recovery duty.
Abandoned pre-handoff preparation grants no Agent Session or mutation
authority; background cancellation failure does not block another Action. A Run that
has been handed off or paired, has begun a write, or retains an unresolved
recovery duty instead keeps its cancellation and recovery state explicit and
retryable until authority and transaction outcomes are known.

Machine-local Run persistence separates deletion authority from its evolving
payload. Unsupported payloads authorize no resumption or projection;
system-Trash recovery is owned by
[§6](02-notes-and-file-operations.md#6-system-trash-deletion-and-application-cleanup).

## 9. Analyses workflow

1. Create or import one source-facing Analysis and establish one paper-data
   route. A researcher-selected local regular file, or a specific Zotero
   attachment resolved through Scholium source access, supplies a Scholium
   `sourceReference`. Alternatively, a stable Analysis-to-Zotero binding
   supplies an external Zotero data route: the Agent may retrieve the paper
   through its independently configured Zotero/MCP capability, and Analyze
   does not require Scholium source access or a `sourceReference` for that
   route. When both relationships exist, a currently resolvable local source
   selection remains the selected Scholium source route; a Zotero attachment
   relationship or absent source selection uses the external route. The
   binding remains a data-acquisition relationship, not paper content or
   evidence by itself. A direct Agent Run may declare
   `source_route: researcher_provided`: the source stays outside Scholium,
   which receives no path, bytes, or `sourceReference`. Missing or ambiguous
   material remains a limitation. Without a formal revision-bound envelope,
   Citation Fidelity is **Unable to verify**; Note YAML is not verified source
   evidence.
2. Use **Analyze** to create, extend, correct, clarify, reorganize, or leave
   warranted content unchanged.
3. Analyze reconstructs before critical pressure, identifies the operative
   method when material, and applies relevant success conditions rather than a
   universal argument template. Source-explicit claims, reconstruction,
   charitable repair, Agent criticism, rival definitions, objections, replies,
   implications, and residual pressure retain their actual status.
4. If a Scholium-owned local source cannot be reopened, Analyze returns a
   bounded access failure and cannot simulate source analysis from the
   Analysis note alone. On the external Zotero route, unavailable MCP,
   missing attachments, extraction failure, or incomplete pagination narrows
   the result and remains an explicit limitation; metadata alone never
   substitutes for the paper.
5. Use Discussion for comments. Analyze performs its own bounded fidelity
   self-check; use Check Fidelity for an exact revision only when the
   researcher explicitly initiates it, and let the researcher decide whether a
   Topic or Work should change.

For a long source, maintain one source-level Analysis by default. Each Run
declares its bounded source scope in the Research Record. Unread, excluded,
unreliable, or incomplete material becomes a top-level `limitations` entry;
consulted versions, ranges, or locator conditions belong in `source_basis`.
Neither field is a completion grade.

## 10. Topics workflow

1. Create or update a Topic from material actually used, preserving
   disagreement, limitations, and uncertainty.
2. Use **Discuss** for read-only conceptual and dialectical work.
3. Use **Synthesize** to integrate warranted material into the current Topic;
   the Topic is the initial write member. It states its bounded material basis,
   preserves methodological asymmetry, and distinguishes any local provisional
   stopping point from practical cutoff or lack of progress.
4. Additional exact documents may join the same Run's Bounded Write Set under
   Section 8.3; they do not become child Runs or a persistent target group.
5. Use Check Fidelity for an affected exact revision only when the researcher
   explicitly initiates that Action, then let the researcher decide whether
   further Notes need attention.

Scholium never auto-merges an Analysis into Topics. Selected context, Search
ranking, neutral links, and transitive paths establish neither use nor support.
Read-only critical exchange belongs to Discuss; formal Critique remains
Work-only.

## 11. Works and Critique

### 11.1 Researcher-governed Works

Researchers may scaffold, write, revise, and organize Works directly. Agents
may do so through **Write** when instructed, but Critique remains visibly
separate and optional. Critique assesses without modifying the target Work;
any resulting source change requires Write authority in a current Run.

### 11.2 Critique target and storage

- A Critique targets one Work; broader reflection uses Discussion with focal
  Notes.
- Each Work has at most one current Critique document. Later rounds update it;
  prior rounds and deliberate researcher responses remain in Research Records
  without restore or approval semantics.
- Critiques are recognized only in `Critiques/`.
- Bodies are read-only in Scholium but remain externally editable and may use
  ordinary file operations.

### 11.3 Critique Action

Critique uses the current Work or selected passage, applicable Discussion
anchors, and optional focus or disciplinary lens. Whole evaluates important
claims, arguments, method fit, coverage, sustained contribution, objections,
implications, and alternatives against selected Analyses and Topics. It reports
scoped research burdens without certifying maturity, originality, or readiness;
this is an attributed assessment, never an automatic diagnostic. Passage
remains bounded unless the researcher broadens it.

The Action uses the current registered Critique Skill. **Edit Critique
Skill...** opens **Settings → Research Guidance → Skills → Critique**, where
the Skill entry, optional folder path, and explicit default restoration belong.

### 11.4 Critique form

The default Assessment follows Section 8.4 and may present Overall Assessment,
Strengths, Major Concerns, Source Support, Objections and Alternatives,
Revision Priorities, Specific Findings, and Materials/Limitations without
duplicating one judgment across fields. Findings may be **Traced**,
**Untraced**, **Disputed**, or **Beyond Sources**--Agent judgments, never
Scholium statuses or Work qualification.

Each specific finding records Work identity and fingerprint, heading when
available, original line, and a short quotation. Selecting it opens the target
passage; a fingerprint mismatch marks a different revision. Work overlays remain
deferred until Comment anchoring is reliable.
