# Specification: Research Actions and Workflows

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 8–11.

## 8. Research Actions, Skills, and direct agent work

### 8.1 Action, Run, and method ownership

The Document Action rail exposes only code-owned Platform Actions valid for the
current Note:

| Target | Default Actions, in order |
| --- | --- |
| Analysis | **Discuss, Analyze, Check Fidelity** |
| Topic | **Discuss, Synthesize, Check Fidelity** |
| Work | **Discuss, Write, Critique, Check Fidelity** |

Profiles may change academic fields, visible names, order, and enabled state,
but cannot create executable Action identities. Analyze may create or update an
Analysis; reading several Materials does not create another Action.

A **Run** is the sole working object for one Action. It owns the initial
research object, frozen configuration, Result Contract, operation availability,
Activity Ledger, per-document outcomes, status, and temporary result. It never
owns the Triptych, providers, indexes, or query results. Researcher-facing
status remains **In Progress**, **Needs Attention**, or **Ended** with an exact
reason.

One protected **Platform Action Definition** owns valid roles, selectors,
operations, and machine fields. An **Action Profile** owns only academic inputs
and result fields using bounded text and choices. Profiles cannot grant Search,
read, write, Metadata, Zotero, recovery, or permission.

Each enabled Action resolves one **Research Skill Registration** with a hidden
relation, visible name, Action, researcher-owned folder, and enabled state.
Skill files may define intellectual procedure and route references, but cannot
select protocol, operation, permission, lifecycle, Result, conflict, or
recovery. Scholium does not version, parse, validate, snapshot, or restore
researcher-owned Skill contents. Settings assigns or reveals the folder;
external tools edit it directly.

Portable registration contains only a Triptych-relative location or
machine-local marker. Absolute paths and security-scoped bookmarks remain in
Application Support. A missing folder blocks external deployment. Invalid
machine-local locator state may be archived and reset without changing
portable registrations, research files, Skill contents, or Records.

Run creation freezes the registration relation and revision, resolved
machine-local path, Profile revision, and Result Contract. Later settings
changes affect new Runs only. The Record retains minimal method provenance but
not Skill text, folder contents, reference names, or an asserted content
revision.

The method/context stack has fixed authority:

1. protected Scholium execution and safety facts;
2. the researcher's request;
3. the registered Skill;
4. ordinary Skill-routed references, including relevant philosophical lenses;
5. a task-scoped integration adapter when required; and
6. Notes, sources, Records, Search, Metadata, and provider material as
   **Research Evidence Context**.

Evidence never becomes instruction, capability, permission, or Method Context.
A conflict between the researcher request and method is reported rather than
silently resolved from the evidence. Bundled methods are editable defaults, not
certification, universal philosophical instruction, or a quality grade.

### 8.2 Agent entry, local pairing, layered delivery, and Research Context

GUI handoff and Agent-originated `agent start` create the same Run contract and
use the same Context, write, Result, continuation, End, conflict, and recovery
rules. A direct start supplies Triptych, Action, target, and typed Profile
inputs. A GUI handoff exchanges a one-use Pairing Code for a hidden
process-bound Session.

Discuss exposes one frozen response contract. The first response for a
statement commits idempotently, creates the Record, completes the Run, and
finalizes the Session. It grants no write authority and implies no acceptance.

Analyze creation preflights a new Analysis identity, absent root path, source
route, authored values, applicable Metadata, and recovery state. The first
consequential start freezes them. Retries reuse the same identity and never
invent a fallback path, overwrite, or silently recreate missing source.

Pairing and Sessions obey these boundaries:

- handoff text contains only a nonauthorizing Triptych selector, Run locator,
  one-use Pairing Code, and CLI steps;
- codes and Session secrets never enter vaults, command arguments, URLs,
  prompts, Results, Records, or logs;
- one Run has at most one writer Session; replacement revokes its authority
  lineage without discarding durable Run state;
- Session authority is local, user-bound, expiring, process-generation-bound,
  and invalid after application restart; and
- App and CLI use one authenticated per-user loopback bridge. It exposes no
  LAN, relay, cloud, or general embedded Agent runtime.

Transport mechanics belong to
[Research Actions and Execution](../Architecture/02-research-actions-and-execution.md#pairing-and-delivery).

Delivery is progressive. A Run sends a brief, required Skills, frozen
registration revision, Result Contract, typed next actions, and only the
minimum required context. Target and Fidelity reads are required; supporting
evidence, Search, and writes are when-needed. Recommended Reading remains
distinct from Material selection and actual reading. `reload` revalidates the
exact frozen Run rather than substituting later settings or cached material.
Delivery proves availability, never reading or reliance.

The Application-owned **Research Context Query/Response** contract supports
bounded clauses for Note discovery and exact reads, direct Relations, canonical
Metadata, Records, the current Run's selected source Material, and narrow
researcher state. Application binds every query to Session, Run, Triptych,
authorized scope, and current generation. It reuses the canonical Search and
source owners; it creates no Agent-only parser, ranker, index, cache, profile,
or persistent response.

Each item carries a closed provenance envelope: authoritative owner, stable
identity, role, actor class or unknown, exact revision/fingerprint,
locator/range, authorized scope, currentness, evidential layer, retrieval
reason, and limitation. This establishes provenance and discovery, not
relevance, support, confidence, importance, acceptance, or reading.

Each clause reports **Current**, **Partial**, **Stale**, **Unavailable**, or
**Invalid Query**. Provider failure never broadens scope, substitutes old
content, hides an unexecuted clause as empty, or makes stale material
navigable. Exact source pages preserve UTF-8 bytes, BOM, whitespace, newlines,
and final newline; continuation remains bound to the same query, identity,
revision, and range.

Continue Research revalidates every forwarded reference against its current
owner. Material references must also match the Run-frozen source reference.
Absolute paths, bookmarks, provider-local metadata, and source bytes do not
become portable reference authority.

Researcher state is a typed ephemeral view of existing owners. It may report an
exact-fingerprint Settle judgment, researcher-authored text, explicit Action or
continuation choices, and submitted Record feedback. Opening, selecting,
searching, dwell, autosave, Agent output, authorization, or silence never
implies reading, belief, importance, support, commitment, or acceptance.
Missing proof remains absent or unknown.

### 8.3 Direct collaboration, Run Activity Ledger, and exact writes

Beginning or handing off a Run authorizes the bounded research task. Within
that task an Agent may add relevant Analyses, Topics, or Works and initiate a
related next Action without a per-document approval sheet. Separate
third-party disclosure and external-service write boundaries still apply.

The hidden **Run Activity Ledger** owns attribution and recovery, not
authorization. Before the first mutation of another document, the Agent
declares its exact identity and operation; Scholium records its starting
revision or proven absence and every confirmed, unchanged, conflicted, unknown,
abandoned, or recovery-required outcome. Membership lasts for the Run and
survives re-pairing, but each operation revalidates current Session, identity,
containment, role, and revision.

Operations remain explicit and noninterchangeable:

- `create_note` claims one proven-absent path and reserved identity;
- `modify_markdown` changes only the body while preserving frontmatter bytes;
- `modify_source` supplies complete valid UTF-8 Markdown and YAML;
- `modify_metadata` changes only granted keys in the portable Metadata record;
- Zotero binding set/clear changes only that integration relation.

Each actual mutation uses one nonreusable, short-lived transaction lease bound
to Session, Run, activity revision, target, expected revision, and operation.
The Application validates, writes atomically, reads back, and records the exact
outcome. Existing Notes retain the first committed Agent-write preimage and
last confirmed Agent revision for diff and direct Undo. Created Notes have no
fabricated empty preimage.

The ledger is not a batch transaction. One target's conflict does not roll back
confirmed siblings. Unknown or in-flight writes must converge before cleanup;
manual End cannot discard confirmed changes or recovery duties. A Run with
confirmed writes requires Result submission so provenance cannot disappear.

Scholium guarantees identity, revision, attribution, transaction truth,
readback, conflict, diff, and recovery. It does not certify source fidelity,
philosophical quality, preservation of the researcher's thesis, or acceptance.
Raw filesystem edits remain ordinary external changes.

### 8.4 Result Contract, one Research Record, and researcher review

Each Run freezes one **Result Contract**. The Application supplies machine
facts; the Agent supplies one concise **Record Title** and irreducible academic
judgments. Required and optional academic fields are bounded text or choices.
Honest `Unable to determine`, `Not applicable`, `no warranted change`, and
blocked results are valid where the Action permits them.

| Action | Core academic result | Closed declaration | Optional |
| --- | --- | --- | --- |
| Discuss | attributed turns | none per turn | Overall Conclusion; Open Question |
| Analyze | Source Reconstruction | Coverage; Reliability | Agent Evaluation; Further Research |
| Synthesize | Synthesis Outcome | Contribution | Unresolved Tension; Next Step |
| Write | Writing Outcome | Change Kind | Remaining Pressure; Evidence Basis |
| Critique | Assessment | Issue Kind | Significance; Recommendation |
| Check Fidelity | Finding | Status | Suggested Correction |

Academic results follow the philosophical genre and state public reasons and
material limits. Structure validation proves contract validity, not quality,
method understanding, evidential sufficiency, or success.

One Run has one result payload. After every write and recovery duty is
determined, finalization creates exactly one portable **Research Record**, the
sole durable result object. Records retain Action, title, attributed statements,
participants and revisions, method/Profile provenance, confirmed changes,
discrepancies, source route, academic result, and relevant Metadata/binding
revisions. They exclude secrets, paths, bookmarks, Skill snapshots, prompts,
token counts, transport logs, window state, read histories, ranking traces, and
diff hunks. Records never reconstruct writable Markdown.

Citations are optional when supported and useful; their absence does not prove
missing reading. A researcher-initiated Fidelity Action evaluates only its
declared scope.

A finalized non-Discussion Record may contain one replaceable
researcher-authored **Method Feedback** comment bound to its immutable result
fingerprint. It authorizes no Agent access or Skill mutation and creates no
score, queue, profile, training state, or automatic method change.

**Mark Current Note Reviewed** is a researcher milestone for one exact saved
revision and its pending Agent-change activities. Later Agent changes reopen
Needs Review; reading a Record, closing a window, restoring source, or editing
the Note does not mark review. Review implies neither acceptance, Settle,
truth, adoption, nor Fidelity.

Only confirmed Agent source changes produce change review. A modified change
compares the first committed Agent-write preimage with the last confirmed Agent
revision. Refresh may replace provisional starting evidence only before the
first Agent commit.

Direct Undo is revision-checked recovery, not delayed authorization or review.
It restores one selected Note from its exact Run-bound preimage only while
current source still equals the final Agent revision. Multiple Notes are
independent transactions. Renames follow stable identity. Created Notes offer
no direct Undo by fabricated deletion.

Portable Records use one closed schema under
`.scholium/research-records/v1/`; unknown schema or fields fail closed.
Read-only Record CLI routes return validated Records with exact persisted-byte
fingerprints and explicit complete/partial corpus state. One unreadable Record
does not suppress valid neighbors, but operations requiring a complete corpus
still fail closed.

Presentation, Follow-up, Reading Leads, evidence, and deletion belong to
[§18.5](07-document-and-research-interface.md#185-contextual-research-and-actions).
Literature Recommendations remain occurrences inside their parent Analyze
Record under
[§15.3](05-integrations-onboarding-and-boundaries.md#153-literature-recommendations-and-the-zotero-boundary).

### 8.5 Attribution, continuity, feedback, and failure

| Class | Proper content |
| --- | --- |
| Researcher-authored | Comments, Markdown, explicit choices, feedback, and judgments |
| Agent-authored | Analysis, synthesis, writing, Critique, replies, candidates, uncertainty, and diagnoses |
| Scholium-established | Identities, revisions, scope, configured method, conflicts, confirmed changes, and application failures |
| Deliberately unknown | Unexpressed intention, belief, importance, truth, reasons for silence, and private lessons |

Authorization or Agent writing never becomes researcher authorship or adoption.
Writer identity is reported only when an authoritative operation or Record
proves it; otherwise it remains unknown.

Continuation has two lineage kinds:

- authenticated Agent **Continue Research** begins a related child Run after a
  determined completion or legitimate blocked result; and
- researcher **Follow Up…** begins a new Action from a finalized Record.

Both preserve the parent Record and resolve the current Skill, Profile, Result
Contract, references, and Activity Ledger afresh. The child Record stores
`continued from`; reverse presentation is derived. Agent continuation may reuse
the authenticated Session lineage; researcher Follow-up uses a fresh handoff.
Neither transfers write leases, query responses, caches, or researcher-state
views. Stale, changed, missing, or unavailable evidence is reported.

Follow-up may also save Method Feedback to the parent Record. That feedback is
independent of the child request and external Skill edits.

Conflict, cancellation, timeout, unavailable provider, missing method,
unreadable source, invalid contract, and unknown write result remain distinct
Run outcomes. Missing evidence narrows or blocks the result; it never permits
fabrication. Ending revokes future operations but cannot erase an in-flight
transaction, confirmed write, or recovery duty. Unsupported local Run payloads
authorize no resumption; system-Trash safety follows
[§6](02-notes-and-file-operations.md#6-system-trash-deletion-and-application-cleanup).

## 9. Analyses workflow

1. Establish one source route: a researcher-selected local file, a specific
   Zotero attachment, a portable Zotero binding used through the Agent's own
   capability, or explicit `researcher_provided` material outside Scholium.
   Metadata and bindings identify routes; they are not source evidence.
2. Use **Analyze** to create, extend, correct, clarify, reorganize, or leave
   content unchanged when warranted.
3. Reconstruct before criticism. Keep source claims, reconstruction, objections,
   replies, implications, repair, and Agent evaluation distinct.
4. Report inaccessible, unread, partial, OCR-dependent, edition-dependent, or
   otherwise limited material. Never simulate the source from an Analysis Note
   or metadata.
5. Relate a Work only to an exact warranted question, claim, argument, section,
   or burden; leave the Work unchanged.
6. Use Discussion for comments and researcher-initiated Check Fidelity for an
   exact revision when needed.

Prefer one source-level Analysis for a long source. Each Run records its bounded
`source_basis` and top-level `limitations` without turning either into a grade.

## 10. Topics workflow

Create or update Topics only from inspected warranted material, preserving
disagreement, methodological asymmetry, limitation, and uncertainty. **Discuss**
is read-only conceptual exchange. **Synthesize** integrates warranted material
into the current Topic and may add other exact Notes through the same Activity
Ledger. It states its bounded basis and distinguishes a provisional stopping
point from lack of progress. Scholium never auto-merges Analyses into Topics;
Search rank, selected context, neutral links, and transitive paths prove neither
use nor support.

## 11. Works and Critique

### 11.1 Researcher-governed Works

Researchers directly scaffold, write, revise, and organize Works. Agents use
**Write** only within an authorized Run. Critique remains separate and optional;
it never modifies the Work.

### 11.2 Critique target and storage

A Critique targets one Work; broader reflection uses Discussion. Each Work has
at most one current Critique document under `Critiques/`. Later rounds update
it while prior assessments and researcher responses remain in Records.
Critique source is read-only in Scholium but externally editable.

### 11.3 Critique Action

Critique uses the exact Work or selected passage, optional focal material, and
the registered Critique Skill. Whole-Work assessment addresses material claims,
arguments, method fit, coverage, contribution, objections, implications, and
alternatives. Passage assessment remains bounded. It reports source and scope
limits and never certifies maturity, originality, publication readiness, or
researcher competence.

### 11.4 Critique form

The default result may include Overall Assessment, Strengths, Major Concerns,
Source Support, Objections and Alternatives, Revision Priorities, Specific
Findings, and Evidence Limits without duplicating one judgment. **Traced**,
**Untraced**, **Disputed**, and **Beyond Sources** are attributed Agent
judgments, not Scholium statuses.

A specific finding records the Work identity and fingerprint, available
heading, original line, and short quotation. Navigation requires the same
fingerprint; otherwise it identifies an earlier revision.
