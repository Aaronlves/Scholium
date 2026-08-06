# Specification: Research Actions and Workflows

Part of the canonical document set rooted at [SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md).
This chapter owns Sections 8–11: Actions and the Analysis, Topic, and Work workflows; sibling chapters do not restate it.

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

There is no default mode picker. Analyze Source and Reanalyze are one adaptive
Analyze Action; reading several Materials is context assembly rather than a
Multi-note mode; Analyze and Synthesize remain separate scholarly Actions.
**Manuscript** may remain an optional hidden Work Action, but it grants no
extra authority and sequences only ordinary Runs.

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
required. A Profile cannot declare Search, reading, Properties, Zotero,
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
transport fallback; the Agent may continue from the delivered primary method
and Practices or report the limitation.

**Philosophical Practices** are researcher-owned Markdown method references.
A primary Skill entry names zero or more Practices through exact ordinary
Wikilinks. Scholium resolves exact title or explicit path, preserves first-use
order, delivers duplicate references once, and reports missing or ambiguous
references without substitution. Practice references never enter research
Connections, grant capability, create evidence, or override the researcher
request or platform safety. A Practice may combine a lens, procedure, and
criterion; Scholium creates no Practice type or dependency graph.

Run creation freezes the registration relation, exact primary entry text,
resolved Practice identities and text, optional Skill-folder path string, and
Result Contract. Later registration, Skill, Practice, or Profile edits affect
new Runs only; Scholium does not freeze or track folder contents. A new
Triptych begins with editable current default methods. Updates never overwrite
researcher edits. **Restore Default…** means the current app-bundled default
and states the replacement consequence before writing.

Each Scholium-mediated Skill or Practice edit retains exactly one replaceable
machine-local recovery point containing the displaced exact bytes. A later
safe method edit may replace it. There is no revision list, version browser,
comparison history, package lineage, or past-method reproduction promise.
Research Records retain only the hidden registration relation, then-visible
method name, and referenced Practice names, never complete method text or
folder contents.

The method/context stack has fixed roles:

1. protected Scholium execution and safety facts;
2. the researcher's current request;
3. the primary Skill entry;
4. supplementary files the Agent actually reads from the registered folder;
5. resolved Practices; and
6. Notes, sources, Records, Search results, Properties, research state, and all
   provider content as **Research Evidence Context**.

Evidence content never enters Method Context, changes platform capability, or
authorizes a tool, network destination, write, or next Action. Instructional
text in a PDF, Note, Record, summary, webpage, metadata field, or provider
response remains untrusted research material. A material conflict between the
researcher request and method is made visible; it is not silently averaged or
resolved by the material itself.

### 8.2 Local pairing, layered delivery, and Research Context

Direct Agent connection is local, provider-neutral, and bound to the current
Scholium application process. The researcher deliberately copies one complete
handoff into the selected Agent conversation. It contains the opaque Run
locator, short-lived one-time **Pairing Code**, and direct instructions for the
Agent to run the installed `scholium` CLI itself, enter that code through the
pairing command's standard input, and load the authenticated Run context. The
handoff contains no research text, complete method, local path, internal
fingerprint, permission payload, result schema, Session secret, or reusable
bearer authority.

Pairing exchanges the one-time code for a hidden **Connection Session**. The
Pairing Code and Session secret are independently generated from an Apple
Security cryptographic random source whose success is checked. A code is
single-use and invalid attempts are bounded. The server stores only the digest
and binding needed to validate a Session. Raw codes and credentials are not
general Codable or printable domain values; the typed handoff presentation
explicitly unwraps the one-use code for researcher-directed copy, while the
protected bridge and CLI credential store use private wire/storage adapters.
The Pairing Code
may enter only the researcher-selected Agent conversation and pairing standard
input. It never enters the research vault, command argument, URL, file,
ordinary output, log, later prompt, Result, or Record. The reusable Session
secret never enters any copied handoff, prompt, vault, command argument, URL,
ordinary output, or log.

A Session binds the current macOS user, current application-process
generation, allowed Runs, expiry, and revocation. One Run has at most one
write-capable Session; re-pairing it revokes the old Session's access to that
Run. Window closure, sleep, a short socket interruption, or ordinary CLI
reconnection does not require pairing again while that process and Session
remain valid. Full app exit, crash, update restart, or Mac restart always
invalidates every old Session. Re-pairing an unfinished Run changes connection
authority only; it does not rebuild the Run or discard confirmed writes,
Records, conflicts, or recovery duties. Keychain does not restore Sessions.

The supported packaged App and signed CLI communicate through the existing
per-user Unix domain socket located with minimal rendezvous state in one App
Group container. The App Group owns no Triptych, Run, Session semantics,
research content, Record, checkpoint, or recovery bytes. Existing same-user,
owner/mode, bounded-frame, timeout, contract-version, and schema checks remain
mandatory. Beta adds no XPC service, LaunchAgent, helper application,
Network.framework listener, relay, or public network endpoint. Direct pairing
is promised only for an Agent environment that can reach the local CLI/bridge;
manual copy collaboration with a cloud Agent is not described as a Session.

Delivery is progressive:

- a newly paired Agent session receives Core Protocol, capability catalog, and
  Session boundary once;
- each Run receives a short Run Brief, exact Method Context, and Result
  Contract;
- Research Context arrives only after an explicit query;
- a specialized capability explains only its additional contract on first
  use; and
- ordinary calls return data, result, error, next step, current Run/Action,
  and `reload`/`help` anchors without repeating Core Protocol.

`reload` returns the Run-frozen method, Practices, folder-path string, and
Result Contract. It never substitutes later current method text and never
replays an old Research Context response, ranking, availability, or cache.
Local absolute paths are delivered only after authentication.

The versioned, read-only **Research Context Query/Response** contract belongs
to Application. A query carries an explicit research question and narrowing
conditions; Application binds current Run, Session, Triptych, authorized
scope, and generation before provider execution. Initial Beta composes the one
Search capability, exact Note/section read, explicit direct Relations,
canonical Properties, Research Records, and only researcher-state facts whose
existing owner proves actor, object, action meaning, revision/scope, and text.
It creates no Agent-only parser, ranker, JSON scan, hidden index, persistent
response, Research State store, researcher profile, vector store, or automatic
synthesis.

Every returned item uses one closed **Source Reference Envelope** carrying:
source kind, authoritative owner reference, stable object identity, actor
class or unknown, object/vault role, exact revision or fingerprint, locator or
source range, authorized scope, currentness, evidential layer, retrieval
reason, and material limitation. The envelope expresses provenance and
discovery, not confidence, relevance truth, philosophical support, importance,
or acceptance. Response schema 2 additionally preserves the exact typed
Foundation Search match reasons beside every Note item. Property key/value
source ranges and direct-relation predicate, direction, anchor, target, and
Markdown occurrences therefore survive delivery without becoming prose or a
second relation interpretation. Unknown owner kinds, malformed identities, and
a coarse Property/direct-relation reason without its typed match fail closed.

Response availability distinguishes **Current**, **Partial**, **Stale**,
**Unavailable**, and **Invalid Query**. Partial names the unavailable provider
or scope. Stale references cannot navigate or be recorded as current use.
Provider failure cannot return an older response, broaden scope, silently omit
a clause, or present unavailable as no matches. App and CLI consume the same
Application response; delivery adapters do not parse, rank, or fill provenance.
The Source Reference Envelope's response-local ID is correlation only, not
authority. Scholium retains no process registry of previously delivered
references. Context Use and Continue Research submissions remain bound to an
authenticated Run, must carry that Run's authorized scope, and recheck the
current authoritative owner, revision, and locator before any reference is
recorded or handed forward. These checks establish a current referent, not
that delivery itself caused use; actual use remains explicit Agent testimony.

Researcher state is only an ephemeral typed read view over existing owners.
The maximum meanings are narrow: exact-fingerprint Settle means that revision
was then judged sufficiently stable; researcher-authored text and turns mean
the researcher wrote them in that context; an explicit researcher Action or
continuation choice records that choice; a Researcher Evaluation records the
submitted evaluation of that exact Record. Opened, selected, searched, dwell,
pin, autosave, authorization, Agent output, and silence never imply reading,
importance, support, commitment, acceptance, or belief. Missing proof returns
absent or unknown rather than an inferred psychological state.

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

Adding one or more extra documents to the same Run is a distinct consequential
operation. Ask Me Every Time presents one bounded set and permits a subset;
Ask Me Only for Works asks only when the set creates or changes a Work; Full
Access binds a valid set without a sheet. The same policy governs creation of a
next Run. Skill or Practice edits require their own researcher-initiated
method-improvement action. No policy authorizes third-party disclosure.

The **Bounded Write Set** is hidden, short-lived, expandable, and owned only by
its Run. Each member binds Triptych, stable existing-document identity or one
explicitly authorized new identity, vault role, permitted operation, exact
expected revision or proven absence, expiry, and authorization provenance.
It contains no document bytes, research plan, write order, academic relation,
or persistent group. Single-request member count, Run-total member count, and
encoded payload have explicit testable limits; exceeding one returns a bounded
continuation result rather than widening authority.

One authorization may bind several exact documents, but every actual mutation
uses a nonreusable short-lived capability bound to the current unique writable
Session, Run, complete allowed document set, and each member's expected
revision. Each call names one member and has one hidden idempotent operation
identity. Before writing, Scholium revalidates Session, Run, membership,
identity, role, operation, containment, current revision, and policy facts that
can revoke unused Full Access authority. It then establishes **Before Agent
Work** exact-byte recovery, builds and validates complete candidate bytes,
atomically replaces, and reads back. A confirmed Scholium write advances only
that member's expected revision.

The set is not a batch transaction. One member's conflict, external change,
failure, or abandonment does not roll back confirmed siblings, revoke
unchanged references, or create a child Run. An external change makes only the
affected member stale. Already-submitted file transactions must reach a known
written/not-written/recovery-needed result; policy tightening or manual End
cannot pretend to cancel them. Manual End may block new operations and revoke
Session access, but cannot safely finalize the Result or clear the write set
while a started write is unknown or required recovery remains. Run cleanup
removes the write set only after every transaction converges; transaction recovery may outlive it only as
the existing machine-owned recovery duty.

Direct Agent editing remains the product model. Scholium creates no Proposal,
candidate Markdown copy, approval-to-apply step, section/full-document
permission mode, target plan, or automatic semantic approval. It guarantees
scope, identity, revision, transaction truth, exact displaced bytes, conflict,
readback, and recovery. It does not certify fidelity to a source, preservation
of the researcher's thesis, philosophical quality, or researcher acceptance.
Those remain method, attributed reasons, visible changes, recovery, optional
Check Fidelity, and researcher judgment.

### 8.4 Result Contract, one Research Record, and evaluation

Each Run freezes one **Result Contract** from its Action Profile. Academic
fields are flat text, single-choice, or multi-choice, each excluded, optional,
or required. Scholium pre-fills Action, initial object, time, machine state,
actual changed documents, per-document outcomes, conflicts, and recovery.
Agent fields contain only irreducible academic judgments or bounded testimony.
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

One Run has one canonical result payload partitioned into Agent academic fields
and Scholium machine fields. The Run owns it until every initiated write and
recovery duty is determined. Safe finalization creates exactly one portable
**Research Record** and the Action sheet then presents that Record; there is no
independent Result object or second durable store. A crash between commit,
readback, and finalization may retain overlapping private recovery evidence,
but startup reconciles it to the same one result and one Record.

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

Every safely finalized Research Record may contain one optional current
**Researcher Evaluation** partition owned by that Record. It is editable from
two routes: immediately below the returned result in the Action sheet and
later in Record detail. Both routes edit the same Record identity, field
contract, and current evaluation revision; they are not quick/full schemas or
separate objects.

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

Every evaluation save, replacement, or clear carries the expected evaluation
revision and immutable finalized-result fingerprint. The Record store atomically
changes only evaluation content, researcher actor, evaluation revision, and
time, reads back, and otherwise fails closed. A stale editor retains local
input and must reload rather than overwrite. A deleted/unavailable Record
cannot receive the draft or redirect it to another Record. Before finalization,
the return-window form is explicitly an unsaved local draft, never searchable
or visible elsewhere, and closing it with input requires confirmation. Beta
does not persist that pre-finalization draft across windows or app restart.

Portable Records remain one strict closed schema under
`.scholium/research-records/v1/`; unknown schema/fields fail closed. A Record
retains attributed researcher and Agent statements, participating exact Note
revisions, Action, minimal method provenance, Context Use Report, confirmed
changes, discrepancies, Fidelity completion, Analyze-only Literature
Recommendations, and current Researcher Evaluation. It excludes raw secrets,
bookmarks, absolute paths, method/folder snapshots, prompts, token counts,
transport logs, window state, and diff hunks. Markdown remains authoritative
research content; Records never reconstruct writable source.

**Research Records** remains one ordinary nonmodal, resizable auxiliary window
per Triptych. It defaults to **760 x 680pt**, has a **700 x 520pt** minimum,
uses one native list/detail split, and does not restore. The document toolbar
opens **This Note - Records**; Research menu opens **Triptych - Records**.
Scope and **Records / Recommendations** View never follow unrelated focus.
Global Search may open a This Vault Record by selecting it under Triptych scope
and locating the matched statement. Record query semantics remain the shared
Application Search capability, never a window-owned parser or flattened store.

One Record row represents one finished Discussion or Action. Records preserve
attributed prose and collapse machine detail. Comparison is generated on
request only from verified exact revisions; otherwise it states unavailable.
Confirmed permanent deletion removes that Record and its Evaluation and
projections without editing Markdown or unrelated recovery. A durable minimal
deletion tombstone prevents retry from recreating it. There is no Record Trash
or Restore.

Literature Recommendations remain Analyze output owned only by the parent
Record. One occurrence has Unprocessed/Handled plus optional researcher note;
Handled means only processed as a reading lead. Exact nonconflicting DOI or
Zotero identity may group presentation but creates no shared disposition or
second store. Writes reread and replace only the chosen occurrence under the
Record lock, commit atomically, and read back. Record deletion removes its
occurrences.

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
Scholium-mediated writer remains attributable; only another explicit owner can
establish a researcher act. Agent discoveries remain attributed candidates
until retained through the one Result/Record or an authorized exact-document
write. Scholium creates no Discovery store.

**Continue Research** begins another Action and therefore another Run. It is
available only after the current Run has a determined completion or legitimate
blocked result. The initiator supplies the next Action, initial object, short
academic purpose, and only the needed finding/question/hypothesis together
with its epistemic status and why the next Action needs it. Scholium supplies
the `continued from` Record relationship.

Full Access may create the next Run directly; the other policies use the same
single decision rule and ask only when required. The new Run independently
resolves current Skill, Practices, Profile, policy, Result Contract, and
write set. It inherits no old document handles, transaction state, method,
permission decision, Research Context response, candidates, rank, cache,
availability, or future Assembly. Handoff references are re-resolved against
current owner, revision, scope, and generation. Changed, missing, revoked, or
unavailable evidence is reported; a requery reduces stale-context inertia but
does not guarantee completeness or truth.

The next Record alone stores `continued from` after it safely forms; `continued
as` is derived in reverse and never rewrites the prior Record. Rejection or
abandonment changes no prior completion. Agent-initiated continuation under
Full Access remains an Agent act rather than researcher intent.

Record detail accepts one short researcher Method comment and an explicit
**Improve Current Method...** action. Saving or editing the comment alone
authorizes no Agent access. Starting that action, not Full Access or
Evaluation, creates one separately paired improvement Run bound to the parent
Record, exact comment revision/text, finalized Result fingerprint, original
registration relation, current primary Method, linked Practices, and their
exact revisions. It inherits no ordinary Action context, Result operation,
Bounded Write Set, or blanket folder authority.

The Agent may replace exactly one current primary Method or linked Practice,
or return one `diagnosed_no_change`/`unavailable` diagnosis after judging
whether the issue concerns method, execution, material, provider, request, or
preference. CLI obtains machine revisions from authenticated context rather
than researcher copying. Every replacement uses one nonreusable short-lived
capability, expected-revision transaction, previous-edit recovery point, and
exact read-back. A committed file edit can reconcile after interruption
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

## 9. Analyses workflow

1. Create or import one source-facing Analysis and bind one exact readable
   source: a specific Zotero attachment resolved through explicit source
   access, or a researcher-selected local regular file. Zotero bibliographic
   identity alone is not source access.
2. Use **Analyze** to create, extend, correct, clarify, reorganize, or leave
   warranted content unchanged.
3. Analyze reconstructs the source before critical pressure and distinguishes
   source-explicit claims, reconstruction, charitable repair, and Agent
   criticism; rival definitions, objections, replies, and residual pressure
   retain their actual status.
4. If the source cannot be reopened, Analyze returns a bounded access failure
   and cannot simulate source analysis from the Analysis note alone.
5. Use Discussion for comments, Check Fidelity for an exact revision, and let
   the researcher decide whether a Topic or Work should change.

For a long source, maintain one source-level Analysis by default. Each Run
declares a bounded unit and expands Research Unit only to represented material.
Unread, excluded, unreliable, or incomplete material becomes a Limitation.
**Entire source** requires source-wide analysis; `complete` means complete only
for the declared unit.

## 10. Topics workflow

1. Create or update a Topic from material actually used, preserving
   disagreement, limitations, and uncertainty.
2. Use **Discuss** for read-only conceptual and dialectical work.
3. Use **Synthesize** to integrate warranted material into the current Topic;
   the Topic is the initial write member.
4. Additional exact documents may join the same Run's Bounded Write Set under
   Section 8.3; they do not become child Runs or a persistent target group.
5. Use Check Fidelity for each affected exact revision and let the researcher
   decide whether further Notes need attention.

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
  ordinary lifecycle operations.

### 11.3 Critique Action

Critique uses the current Work or selected passage, applicable Discussion
anchors, and optional focus or disciplinary lens. Whole evaluates important
claims, premises, arguments, sources, objections, and alternatives against
selected Analyses and Topics; this is an attributed assessment, never an
automatic diagnostic. Passage remains bounded unless the researcher broadens
it.

The Action uses the current registered Critique Skill. **Edit Critique
Method...** opens **Settings -> Research Guidance -> Skills -> Critique**, where
the primary Markdown method, Practices, optional folder path, last-edit
recovery, and explicit default restoration belong.

### 11.4 Critique form

The default Assessment follows Section 8.4 and may present Overall Assessment,
Strengths, Major Concerns, Source Support, Objections and Alternatives,
Revision Priorities, Specific Findings, and Materials/Limitations without
duplicating one judgment across fields. Findings may be **Traced**,
**Untraced**, **Disputed**, or **Beyond Sources**--Agent judgments, never
Scholium statuses or Work qualification.

Each specific finding records Work identity and fingerprint, heading when
available, original line, and a short quotation. Selecting it opens the target
passage; a fingerprint mismatch marks an earlier version. Work overlays remain
deferred until Comment anchoring is reliable.
