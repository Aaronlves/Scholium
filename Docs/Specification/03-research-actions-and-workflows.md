# Specification: Research Actions and Workflows

Part of the canonical document set rooted at [SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md).
This chapter owns Sections 8–11: Actions and the Analysis, Topic, and Work workflows; sibling chapters do not restate it.

## 8. Research Actions, Method Skills, and direct agent work

### 8.1 Actions and the protected execution contract

The Research Inspector's **Actions** mode exposes only the default Actions
valid for the current note, followed by researcher-enabled custom Actions:

| Target | Default Actions, in order |
| --- | --- |
| Analysis | **Discuss, Analyze, Check Fidelity** |
| Topic | **Discuss, Synthesize, Check Fidelity** |
| Work | **Discuss, Write, Critique, Check Fidelity** |

There is no default mode picker. Analyze Source and Reanalyze are one adaptive
Analyze Action; reading multiple Materials is context assembly, not a
Multi-note mode; Analyze and Synthesize remain separate authority-bound phases.
**Manuscript** ships as an optional ordinary Method Skill whose Action Profile
is disabled and hidden by default. The researcher may enable it as a custom
Work Action.

Internal Develop, Revise, Critique, Fidelity, and Manuscript mechanisms may
remain protected implementation identities. The public Action snapshot records
the scholarly Action, exact Method Skill and Profile revisions, not an internal
name presented as researcher vocabulary.

Every official and custom Action uses one Scholium-rendered modular sheet;
the document's lightweight line-Comment composer is not an Action sheet. An
Action Profile may request only bounded native modules: current Target or
passage; a natural-language instruction; bounded text, single-choice,
multi-choice, or toggle parameters; optional focal note or Material selection;
source access; expected academic outcome; and feedback. It may set a visible
label, role applicability, Triptych placement, order, and **Show in Actions**.
It cannot provide arbitrary Swift, HTML, JavaScript, shell code, native window
layouts, or application statuses.

Opening that sheet captures the exact execution kind, complete Profile
semantic revision, and Profile-document revision that the researcher saw.
Preparation must reject the sheet if any of those values changed, including a
same-kind change to readable roles, candidate write authority, editable
properties, or other capabilities.

Scholium always owns and displays stable identity, revision, source access,
authority, consequential scope, preparation, cancellation, conflict,
comparison, and recovery. A Skill or Profile cannot hide or
replace these modules. Custom Actions appear under **Researcher Skills** and
create no new application-defined event taxonomy.

The optional-agent journey is choose Action, state the request naturally,
inspect focal context and consequences, prepare a durable run, hand it to an
external agent, then inspect the response or confirmed source state. Scholium
contains no embedded agent runtime, does not monitor agent reasoning, and never
claims that opening an agent app means the task was accepted or completed.

Provider-neutral copy and explicit app selection remain available. A Codex
handoff may open a new task at the exact requested root with locator-only
bootstrap data; it must not append to an existing task, auto-submit, select a
model, alter permissions, or put Target or Material content in a launch URL.

Origin, passage, and focal Materials guide attention. Resolved one-hop Connect
relations may suggest Materials with their source location, but are never
evidence, never preselected, and never expand readable or writable scope.
Transitive paths, lexical similarity, Comment text, and inferred philosophical
roles cannot select Materials automatically.

Opening an Action flushes only its current Target editor. Preparation rechecks
the frozen Target, every explicitly selected Material, source access, Method,
Profile, and authority without saving unrelated Notes. Current Actions create
no automatic whole-Triptych checkpoint. Every Scholium-mediated existing-Note
write preserves the exact displaced bytes in per-Note pre-write recovery before
commit; Critique uses the same exact-note recovery and explicit rollback for a
new output. Any relevant save failure, dirty conflict, unknown identity, stale
revision, unsupported Target, invalid Method Skill, or unapproved capability
blocks preparation or commit. Discuss and Check Fidelity are read-only. The
researcher may still create a manual whole-Triptych checkpoint or instruct an
external agent outside Scholium; external edits remain ordinary concurrent
filesystem inputs.

### 8.2 Authorship, feedback, and truthful records

Scholium-owned records keep four authorship classes distinct:

| Class | Proper content |
| --- | --- |
| Researcher-authored | Comments, questions, direct Markdown, explicit authorization, and deliberate later judgments |
| Agent-authored | Analysis, synthesis, Critique, writing, replies, feedback, uncertainty, and proposed diagnoses |
| Scholium-established | Identities, revisions, configured methods, authorized scope, checkpoints, conflicts, confirmed changes, and application failures |
| Deliberately unknown | Unexpressed intention, belief, significance, maturity, truth, reasons for silence, and private lessons |

An Action does not reveal the researcher's intention. Scholium records only
the meaning already expressed by a necessary action and never interprets
beyond it. Opened does not mean read; selected does not mean supporting;
modified does not mean improved; Settled does not mean true; silence does not
mean acceptance; structurally valid does not mean philosophically sound.

After Analyze, Synthesize, Write, Critique, or another substantive Action, the
agent returns bounded feedback when material. It may report the academic
outcome, what it tried to do, the Materials it actually relied upon, important
uncertainty, missing evidence, access limits, unresolved pressure, method
conflicts, recommended next Actions, and a proposed failure diagnosis. It must
not fabricate a finding to fill a field or write an interpretation of the
researcher's mind as a Scholium-established fact.

A failure proposal remains attributed feedback. The researcher may reply,
question it, request another Action, ignore it, or preserve a lesson in
ordinary Markdown. Scholium creates no Failure object, score, status, form, or
mandatory post-run disposition. It likewise creates no Alternative relation;
researchers express competing paths in their notes, while Set Aside means only
that a note is not currently active.

One finished Discussion or validated nonconversational Action creates one
portable Research Record. Cancelled preparation with no scholarly response
need not create one. The record may contain researcher turns, attributed agent
replies and feedback, participating note identities, Action and exact Skill
revisions, starting and ending revisions, agent-reported actually used
Materials, confirmed changes, discrepancies, and deliberately expressed
researcher responses. It excludes assembled prompts, raw keys, bookmarks,
absolute paths, token counts, transport logs, routine save events, derived
index freshness, window state, and stored diff hunks.

Portable Research Records use schema version 3. Decoding rejects another
schema version or unknown fields without projecting, authorizing, rewriting,
or deleting the underlying file.

Every current Action completion contains a complete Material-use report.
`actuallyUsedMaterialNoteIDs: []` is the Agent's explicit report that no frozen
Material was actually used; omission is invalid, and Scholium never infers an
empty report from selection or silence. Membership remains Agent testimony,
while Scholium validates each reported identity, role, qualified reference,
title, and exact starting revision.

Every portable Action record also preserves whether exact-revision Fidelity
was `not_required`, `completed`, or `unverified`; a Discussion records only
`not_applicable`. `completed` means the required checks ran against the exact
recorded revision, including checks that found issues. It does not mean passed,
true, important, philosophically adequate, improved, or accepted.

Intellectual records live under `.scholium/research-records/v1/` as one file
per record in `active/` or `records/`. Pending requests, grants,
credentials, temporary transport state, and rebuildable indexes remain in
Application Support. Markdown remains authoritative research content; a record
never reconstructs writable source.

The independent **Research Record** utility window is Triptych-scoped and uses
one list row per finished Discussion or completed Action, with a coherent
detail rather than one row per turn. Opening from a note applies a removable
**This Note** filter. Search and filters cover note, date, Skill, Action, and
participant; Pin is explicit. Record titles derive quietly from Action,
context, and date and are not editable.

The detail uses attributed editorial prose, fine rules, restrained context,
and collapsed **Record Details**, not chat bubbles. Line Comments retain only
their revision-bound inclusive line range; no stored passage copy is required
for a Comment or agent handoff. Multi-note context appears
once. Active Discussion
never moves into this window. The toolbar, Research menu, and keyboard route
open the window without revealing or changing Inspector state.

Records are never summarized or deleted automatically. **Delete Record…**
opens a second confirmation, then permanently removes the one underlying record
and its projections from every participant without editing Markdown,
checkpoints, exact-note recovery, or unrelated records. Scholium provides no Record Trash
or Restore workflow for portable records. A diff is computed
only on request from exact retained revisions or checkpoints. If those bytes
cannot be verified, the interface states **Comparison Unavailable**; diff text
or rendered hunks are never permanent record content.

### 8.3 Research Guidance and Skill architecture

**Settings → Research Guidance** uses stable responsibility categories rather
than one flat package list:

1. **Methods** shows the active Working Method for Discuss, Analyze,
   Synthesize, Write, Critique, and Check Fidelity, plus the optional
   Manuscript method. It supports direct editing, disable, replacement,
   comparison, and explicit restore from the bundled reference.
2. **Researcher Skills** shows installed, disabled, invalid, and
   researcher-created packages and their Action Profiles. It owns staged
   installation, creation, editing, validation, Triptych placement, role
   applicability, **Show in Actions**, and ordering. Before first activation,
   its detail view presents a nonexecuting preview of the modular Action sheet
   at regular and narrow widths, including every app-owned Target, revision,
   permission, conflict, and recovery region that the Profile
   cannot hide.
3. **Permissions** owns the Triptych default and deliberate per-Skill
   overrides. Requested capabilities remain visible here but do not become
   authority.
4. **Sources & Integrations** owns source bindings, Zotero, citation methods,
   agent handoff, and the Scholium CLI.
5. **Recovery & Technical** owns settled-version retention, Skill snapshots,
   restore, validation detail, and **Reveal Skills Folder**.

These categories use a restrained native list/detail hierarchy with persistent
selection, succinct rows, semantic grouping, and one detail destination. They
do not become card grids, nested sidebars, dashboards, or a package marketplace.
Task-specific parameters, focal Materials, and write scope stay in the Action
sheet; Settings contains only longer-lived configuration.

Every assisted workflow separates three owners:

```text
Protected Scholium mechanism
        + directly editable Method Skill
        + researcher-owned Action Profile
```

System Skills own protocol, identity, revision, authorization, checkpoint,
conflict, agent change requests, validated completion, record routing, and
recovery. They contain no claim to be the best philosophical method and cannot
be edited, replaced, or shadowed.

Each Triptych installs directly editable Working Method Skills for Discuss,
Analyze, Synthesize, Write, Critique, and Content Fidelity. A bundled read-only
reference remains available only for explicit comparison or restoration. It
is not an active fallback and release updates never overwrite the researcher's
current method. A workflow with a disabled, missing, incompatible, or invalid
active Skill is unavailable with one executable repair route.

Researcher Skills are ordinary bounded packages at
`.scholium/skills/<skill-id>/SKILL.md`. They may contain UTF-8 `SKILL.md` plus
one-level `references/`, `templates/`, and `evals/` regular files. The first
installation contract accepts local directories only and rejects archives,
network installation, executables, scripts, symlinks, path escape, nested
ownership, collisions, malformed metadata, and unsupported resources.

Installation is staged and inspectable. Before an imported package becomes
active, Scholium shows its origin, bounded contents, purpose, applicable roles,
requested capabilities, and proposed Action placement. It installs atomically
and disabled. Enabling remains unavailable until its Profile is structurally
valid and the same detail surface has shown the generated Action-interface
preview; preview never executes the Skill or grants authority. The researcher
then chooses Triptychs, roles, Action Profile, and permission policy. Installing
the same Skill into several Triptychs creates independent snapshots; later
edits do not synchronize silently.

Every save of an active Skill creates an identifiable revision, and each run
records the exact revision and loaded resources. Editing an ordinary research
note never activates it as instruction. A methodology note may inspire a Skill,
but Notes remain research objects and Skills remain methods applied to them.

Action Profiles declare readable roles, focal-input modules, candidate writable
roles and operations, property boundaries, source requirements, feedback, and
review expectations. A declaration can narrow what Scholium may grant but can
never enlarge application hard limits. Enlarging a previously approved Profile
or Skill envelope invalidates its machine-local approval until the researcher
confirms the new digest.

Bundled philosophical Method Skills must preserve evidential layers; separate
source-explicit claims, reconstruction, charitable repair, and agent criticism;
distinguish concepts, definitions, premises, conclusions, objections, replies,
concessions, and background; preserve material uncertainty and competing
possibilities; and avoid forced findings. Analyze reconstructs before critical
pressure. Synthesize updates a conceptual home only when material genuinely
adds, corrects, qualifies, or reopens it. Critique distinguishes exposition,
argument, objection, reply, and researcher commitment. These are method-quality
requirements for Scholium's defaults, not certification that any method is
philosophically best or that an agent followed it.

Structural validation establishes only bounded identity, compatibility,
resources, and declared capability. It never certifies truth, source support,
philosophical quality, or researcher endorsement. Sharing, inheritance,
automated evolution, executable plugins, nested Practices, and a marketplace
remain outside this contract.

### 8.4 Permission, preparation, completion, and Fidelity

Read capability, focal context, and write authority remain separate. Read
capability defines what an agent may inspect through a mediated handoff; focal
context identifies the note, passage, Comment, or Materials that deserve
attention; write authority is the exact validated note set for one phase.
A researcher may allow Triptych-wide reading within an approved Skill envelope
without selecting every note as focal context. That does not grant write
authority or prove that every readable note was consulted.

Bootstrap adopts **Ask Me Every Time** without requiring an abstract setup
choice and states that the researcher can change the policy later for each
Triptych or Skill in Research Guidance. Permissions offers:

1. **Ask Me Every Time**;
2. **Ask Me Only for Works**; and
3. **Triptych-wide**.

A deliberate per-Skill override replaces the Triptych default only for runs of
that exact approved Skill/Profile digest. When no stored override exists because
none was configured or the researcher deliberately removed it, the Triptych
default applies. A stored override whose digest no longer matches does not fall
through to a potentially broader Triptych default: **Ask Me Every Time**
applies until the researcher reviews the change and explicitly renews or removes
the override. These are machine-local policies that decide whether Scholium
may issue one bounded grant without another sheet; they are not reusable bearer
tokens:

- **Ask Me Every Time** requires a decision for every agent-requested
  additional note change or write-capable child phase.
- **Ask Me Only for Works** may grant a qualifying Analysis or Topic request
  without a sheet when it remains inside the exact approved envelope, but any
  request to change a Work or begin a Work-writing child phase requires a
  decision.
- **Triptych-wide** may grant a qualifying request inside the current Triptych
  without a sheet only when every requested note, role, operation, identity,
  revision, Skill/Profile digest, and source requirement remains inside the
  approved envelope.

Clicking a current Action already authorizes the clearly displayed initial
Target and does not trigger a redundant second prompt. Standing policy governs
agent-requested additional notes, expanded write scope, or a new child phase.
Silence, an expired decision, and an unmatched policy grant nothing. No policy
overrides the hard limits below.

Effective authority is the intersection of application hard limits,
machine-local policy, Skill declaration, approved Action Profile envelope, the
concrete request, and current validated identities and revisions. Destructive
lifecycle operations, out-of-Triptych writes, record edits, unsupported create,
delete, rename, or conflict overwrite never become silently authorized.

One application-level coordinator owns Action availability, preparation,
completion, cancellation, and Fidelity. Preparation resolves Origin and exact revision,
validates source access and focal Materials, resolves the exact Method Skill
and Profile, creates recovery evidence, freezes the write set, rechecks every
revision, and rolls back partial preparation. Discuss and Settle use separate
typed authorities and no write packet.

After preparation succeeds, each write-capable phase receives a
cryptographically random short-lived completion key bound to the Triptych, run,
Action, Skill/Profile revisions, frozen note identities, roles, operations,
and expiry. Only its digest persists. Completion, cancellation, revocation, or
expiry invalidates it. An identical repeated completion is idempotent; a
different payload fails closed.

The agent reports candidate modified identities. Scholium normalizes paths,
rejects traversal, symlink escape, role mismatch, identity substitution,
out-of-scope files, unsupported lifecycle state, and unauthorized creation,
deletion, or rename. The Application derives confirmed modified, unmodified,
and unreported sets from frozen and current fingerprints, performs readback,
and records only validated source changes. A discrepancy is a narrow
Scholium-established fact, never evidence of intellectual improvement or
failure.

An agent that identifies additional necessary Targets may submit one typed
change request for the current parent run. The request contains stable
Triptych/run/Skill/Profile identities, proposed note identities and expected
revisions, requested Action or operation, and an agent-authored reason. The
protected local bridge carries the request into the running app; the external
agent neither draws nor automates the interface.

When policy requires a decision, Scholium presents one native sheet in the
exact Triptych window with **Allow These Notes Once**, subset selection,
**Continue Without Changes**, and **Cancel the Run**. There is no redundant
Deny action. Before resolving, Scholium flushes and revalidates policy, Skill,
Profile, roles, lifecycle, identities, and revisions. Silence is never
permission. If Scholium is closed or live state cannot be validated, the tool
returns unavailable rather than inventing authority.

A frozen parent snapshot or grant is never widened. Allowance creates an
independent child phase with its own snapshot, exact-note recovery, grant,
completion, Fidelity, and lineage. Analyze may therefore request a separately bounded
Synthesize phase; Critique may lead to Write; optional Manuscript coordinates
only explicitly permitted children. The external conversation may continue,
but Scholium preserves each scholarly and authority boundary.

The Core Skill and Triptych guidance explain this cooperative request protocol
and instruct compatible agents not to transmit Works content to an additional
external service, upload destination, or web query without explicit researcher
instruction. Scholium does not host, stream, monitor, or police an external
agent. A direct external Markdown edit is an ordinary concurrent filesystem
event, not a permission-system failure.

Manual and automatic Check Fidelity share exact-revision evidence validation.
A multi-target check retains a distinct result for every note revision and
never collapses mixed outcomes into one verdict. Missing evidence leaves the
phase Awaiting or Unverified; later source changes make the result Stale.
Discuss and Critique do not inherit a write Fidelity result, and Fidelity never
certifies truth, researcher acceptance, or that an agent followed a method.

### 8.5 External edits and conflicts

A clean open note refreshes quietly after an external change. If the local
buffer is dirty, Scholium retains it and presents conflict instead of
overwriting either version.

Before replacing an existing research file, Scholium must durably retain the
expected and candidate bytes and use a volume-supported commit mechanism that
can preserve and verify the displaced file. If that boundary is unavailable or
the observed displaced bytes differ, the mutation fails closed, retains every
available version for recovery, and never reports **Saved**.

## 9. Analyses workflow

1. Create or import one source-facing Analysis and bind one exact readable
   source: a specific Zotero attachment resolved through explicit source
   access, or a researcher-selected local regular file. A Zotero item identity
   may supplement this with bibliographic metadata but is not itself source
   access.
2. Use **Analyze** when agent assistance is useful. The same Action populates
   an initial Analysis or reopens the current source and Analysis revisions to
   extend, correct, clarify, reorganize, or leave warranted content unchanged.
3. Analyze reconstructs the source before critical pressure. It distinguishes
   source-explicit claims, reconstruction, charitable repair, and agent
   criticism; it may clarify rival definitions, formulate an objection,
   consider the strongest reply, and report residual pressure without forcing
   a weakness.
4. If the source cannot be reopened, Analyze reports a bounded access failure
   and cannot simulate source analysis from the Analysis note alone.
5. Add direct Markdown or passage Comments through Discussion, use Check
   Fidelity for the exact revision, and let the researcher decide whether any
   Topic or Work should change.

Analyze's required source access is satisfied only by a specific readable
source: an exact Zotero attachment identity resolved through the explicit
source-access route, or a researcher-selected local regular file with a
security-scoped bookmark and fingerprint. A Zotero item identity alone provides
only the non-evidential bibliographic context in §15.2 and never satisfies this
requirement. Missing item metadata remains a nonblocking integration warning;
a missing, changed, unreadable, nonregular, symlinked, or unauthorized required
source blocks Analyze with one repair route. Bookmarks, absolute paths, and
source bytes remain machine-local. Portable configuration and records retain
only stable source identity, fingerprint, route kind, and a display label.

For a long source, maintain one source-level Analysis by default. Each session
declares a bounded unit and applies required orientation, analysis, and synthesis
passes. Expand Research Unit only to material actually represented and record
unread, excluded, unreliable, or incompletely analyzed material as
Limitations. Chapter sections need not become separate Analyses. Create a
separate Analysis only by researcher request or when a segment needs an
independently citable identity. `complete` means complete for the declared
unit; **Entire source** requires source-wide analysis.

## 10. Topics workflow

1. Create or update a Topic from Analyses, accessible sources, and other
   reliable information actually used, preserving disagreement, limitations,
   and uncertainty.
2. Use **Discuss** to clarify concepts, objections, replies, and unresolved
   alternatives without source mutation.
3. Use **Synthesize** to integrate warranted material into the current Topic.
   Reading multiple Materials is ordinary context assembly; there is no
   Multi-note mode. The current Topic is the initial write Target.
4. Additional Topic Targets require applicable standing authority or a
   validated agent change request and become independent child Synthesize
   phases.
5. Use Check Fidelity for the exact resulting revision and let the researcher
   decide whether other notes need attention.

Topic development remains within Discussion rather than a separate Develop
Action. When the researcher asks to incorporate a result, or the agent requests
and receives authority, a child Synthesize phase retains the Discussion context
while keeping its own snapshot, grant, exact-note recovery, completion, and
Fidelity.

Scholium never auto-merges an Analysis into Topics. It may report relevant
material, but selected context, neutral links, and transitive Connect paths
establish neither use nor support. Read-only critical exchange belongs to
Discuss; formal Critique remains Work-only.

## 11. Works and Critique

### 11.1 Researcher-governed Works

Researchers may scaffold, write, revise, and organize Works directly. Agents
may do so through **Write** when instructed, but Critique remains visibly
separate and optional. Critique assesses without modifying the target Work;
any resulting source change requires a separately authorized Write child.
Manuscript is an optional hidden Method Skill that coordinates only isolated,
independently authorized phases and grants no submission authority.

### 11.2 Critique target and storage

- A Critique targets one Work; broader reflection uses Discussion with optional
  focal notes.
- Each Work has at most one current Critique document. Later rounds update it;
  prior rounds and deliberately expressed researcher responses remain in
  Research Record without restore semantics or a formal approval disposition.
- Critiques are recognized only in the designated `Critiques/` area.
- Bodies are read-only in Scholium, but files remain externally editable and
  may be renamed or moved within Critiques, Set Aside, restored, trashed, or
  revealed.

### 11.3 Critique Action

Critique uses the current whole Work or selected passage context, includes
applicable Discussion anchors, and accepts an optional focus or disciplinary
lens. A current selection defaults
to Passage. Whole evaluates important claims, premises, arguments, sources,
objections, and alternatives against selected Analyses and Topics; this is an
attributed assessment, not an automatic diagnostic. Passage stays bounded
unless the researcher broadens it.

The Action uses the Triptych's active Critique Method Skill without one-run
technical-instruction editing. **Edit Critique Method…** opens **Settings →
Research Guidance → Methods → Critique**, where the directly editable method,
validation, comparison, and bundled restore belong.

### 11.4 Critique form

Default sections are Overall Assessment; Strengths; Major Concerns; Source
Support; Objections and Alternatives; Revision Priorities; Specific Findings;
and Materials Consulted and Limitations. Findings may be **Traced**,
**Untraced**, **Disputed**, or **Beyond Sources**—agent judgments, never
Scholium statuses or Work qualification.

Each specific finding records Work identity and fingerprint, heading when
available, original line, and a short quotation. Selecting it opens the target
passage; a fingerprint mismatch marks an earlier version. Work overlays remain
deferred until Comment anchoring is reliable.
