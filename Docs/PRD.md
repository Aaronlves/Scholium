# Scholium Product Requirements Document

**Status:** Draft consolidated requirements baseline
**Product:** Scholium for macOS and its agent-facing CLI
**Platform baseline:** macOS 26 or later
**Document date:** 2026-07-14
**Product owner:** Imna
**Release owner:** Imna
**Current release:** 0.1 Experimental
**Release identifier:** 0.1

## 0. Document purpose and authority

This document consolidates the product requirements already distributed across
the Product Guide, Design Handbook, implementation ledger, README, and
repository rules. It adds the release-oriented structure those documents do
not provide on their own: product problem, users, goals, outcomes, numbered
requirements, acceptance criteria, risks, open decisions, and traceability.

This is a requirements synthesis, not permission to change the product model.
The documentation hierarchy is:

1. [Product Guide](PRODUCT_GUIDE.md) owns target product role, Triptych
   workflows, terminology, feature boundaries, non-goals, and target product
   behavior.
2. [Design Handbook](DESIGN_HANDBOOK.md) owns interface structure, visual
   language, accessibility, exact user-visible state meanings, action labels,
   and stable design decisions.
3. This PRD synthesizes the two authorities above into release-oriented
   requirements, gates, risks, and traceability. It does not override them.
4. [Implementation Status](IMPLEMENTATION_STATUS.md) records current
   reachability, migration status, remaining work, and verification evidence.
   It does not redefine the target product.
5. [README](../README.md), live construction call sites, executable tests, and
   scripts establish what the current build actually demonstrates.
6. The repository [HANDBOOK](../HANDBOOK.md) is an entry point and authority
   map, not a competing product specification.

When this PRD conflicts with one of those authorities, the conflict must be
resolved explicitly. It must not be resolved by silently treating a target
requirement as current behavior.

### 0.1 Requirement language

- **MUST** identifies a target requirement for the product baseline.
- **SHOULD** identifies a strong requirement that may be waived only with a
  recorded decision.
- **MAY** identifies an allowed but non-required capability.
- **TBD** identifies a decision or measurement that has not yet been set.
- **Target** means required product behavior, regardless of implementation
  status.
- **Reachable** means current documentation reports the behavior as reachable;
  it is not by itself complete release acceptance.
- **Partial** means some implementation or evidence exists, but the documented
  target or acceptance gate is incomplete.
- **Deferred** means the target is intentionally unresolved or scheduled later.
- **Non-goal** means the capability is outside the product boundary.

### 0.2 How to maintain the document set

Use this PRD to answer:

- Why does the product exist?
- Who is it for?
- What is in the product baseline?
- What must be true for a capability to be accepted?
- How do requirements map to design decisions, code, tests, and open work?

Use the Product Guide to change product semantics. Use the Design Handbook to
change interface semantics. After implementation or verification changes, update
the Implementation Status ledger and the relevant evidence. A requirement is
not complete merely because it is written in this PRD.

## 1. Executive summary

Scholium is a local-first macOS research workbench for sustained humanities
research, especially philosophy. It helps a researcher read, write, comment,
review, search, connect, organize, recover, and trace source-grounded work
across three linked research roles:

- Analyses: reusable source analyses;
- Topics: reusable topic-centred knowledge; and
- Works: researcher-governed writing and related material.

The central product promise is:

> Scholium lets a researcher sustain an argument across sources, topic
> synthesis, governed judgments, and authored prose without losing the origin,
> status, exact source, or recoverability of an idea.

The product is document-first. Research files remain authoritative and local.
Derived indexes, rendered views, comments, reviews, Dialogue records,
Critiques, and checkpoints must remain visibly distinct from source Markdown.
External agents may be instructed to inspect and directly edit relevant files,
but they are optional participants. Scholium does not become a permanent agent
chat, task manager, or hidden authorization layer, and the researcher can
complete the core academic workflow without an external agent.

## 2. Problem and opportunity

### 2.1 Problem statement

Researchers working with long-form Markdown, source analyses, topic synthesis,
drafts, Zotero, and external agents need to move between evidence, concepts,
objections, and authored prose without collapsing their differences. Existing
tools and ad hoc workflows can make it difficult to tell:

- which vault or document role a note has;
- whether a claim came from a source, a researcher, or an agent;
- whether a review applies to the exact current fingerprint;
- whether a link is merely a connection or an explicit support relation;
- whether an external edit has conflicted with local unsaved work;
- what can be recovered after substantial agent or filesystem work; and
- whether a warning is a source-grounded fact, a derived diagnostic, or a
  judgment that remains the researcher's responsibility.

Scholium addresses this problem by combining an exact-source Markdown editor
with role-aware research views, app-owned review and comment records,
copyable agent instructions, source-located relationships, and reversible
recovery mechanisms.

### 2.2 Opportunity

The opportunity is not to automate philosophical judgment. It is to make the
researcher's own distinctions and responsibilities legible while reducing
avoidable source, provenance, synchronization, and recovery failures.

The product should make a careful research workflow easier to execute and
audit, while preserving the researcher's control over claims, qualification,
agent instructions, file operations, and final prose.

### 2.3 Evidence status

The repository documents product decisions and implementation evidence, but
this PRD does not claim that formal user research, market research, or
quantitative usability baselines have been completed. User-outcome targets
below are therefore proposed acceptance measures or TBD items, not observed
facts.

## 3. Users, actors, and operating context

### 3.1 Primary researcher

The primary researcher:

- works primarily with long-form Markdown;
- may migrate from or interoperate with Obsidian, Zotero, PDFs, and external
  agent tools;
- needs to distinguish source material, interpretation, researcher analysis,
  provisional synthesis, and finished prose;
- may work across independently located vaults and multiple bodies of writing;
- may work in English, Chinese, mixed scripts, or another language;
- values source fidelity, explicit uncertainty, and recoverability over visual
  novelty; and
- expects keyboard, pointer, accessibility, resizing, selection, and durable
  state to work predictably.

The researcher governs the Triptych and defines the current instruction and
scope for optional agent work. Scholium supports that responsibility; it does
not replace it with app-owned permission state. The researcher is also
expected to be able to write Analyses, Topics, and Works, complete Human
Review, and manage lifecycle decisions without an agent.

### 3.2 External agent

An external agent MAY inspect and directly create, edit, rename, move,
organize, or delete relevant Triptych files when instructed by the researcher.
The agent is an optional external filesystem participant, not a persistent
Scholium conversation partner and not a prerequisite for the core workflow.

Scholium may provide paths, fingerprints, comments, source ranges, linked-note
context, and checkpoints. These are safety and context mechanisms, not a
standing authorization token or a guarantee of recovery.

### 3.3 Filesystem, sync, and other editors

Finder, Obsidian, synchronization tools, scripts, external editors, and agents
are concurrent participants in the filesystem. Scholium MUST detect or safely
handle changes that occur outside the app. It MUST NOT assume that an open
buffer is the only writer.

### 3.4 Zotero

Zotero is an optional external bibliographic and PDF-reading system. Scholium
may read bounded local metadata through Zotero's localhost API when the
researcher uses it, but Zotero is not required for the core workflow. Scholium
is not a Zotero replacement and does not manage Zotero attachments or the
Zotero database.

## 4. Product goals and non-goals

### 4.1 Goals

| ID | Goal | Desired outcome |
| --- | --- | --- |
| G-001 | Preserve exact research source | Reading, editing, rendering, YAML presentation, and recovery do not silently rewrite authoritative Markdown. |
| G-002 | Make research roles legible | Analyses, Topics, Works, Critiques, comments, reviews, and derived Attention remain distinguishable. |
| G-003 | Support source-grounded research | Researchers can trace notes, explicit relations, Zotero identities, comments, and warnings to source locations where possible. |
| G-004 | Make optional agent work explicit and recoverable | When a researcher chooses an agent, she can prepare instructions, inspect context, checkpoint before agent work, detect conflicts, and restore selected or complete state. |
| G-005 | Keep human judgment in human hands | Scholium does not infer truth, support, settlement, sufficiency, or authorization from links, keywords, age, graph paths, or agent output. |
| G-006 | Remain local-first | Research content and app-generated state remain local by default, with bounded and explicit external access. |
| G-007 | Provide calm native interaction | Reading and writing remain primary, with familiar macOS controls, keyboard routes, focus restoration, and accessible state communication. |
| G-008 | Support research beyond one project | The product supports multiple complete Triptychs and ordinary researcher-controlled Works folders without app-managed project records. |
| G-009 | Standalone academic work | A researcher can complete Scholium's core academic workflow without installing or using Obsidian; Obsidian remains optional interoperability. |

### 4.2 Current release exclusions and permanent boundaries

The following boundaries apply to the target product:

- a permanent LLM chat sidebar;
- app-enforced agent task authorization or proposal approval;
- automatic philosophical support, settlement, sufficiency, truth, or prose
  authorization judgments;
- a fourth vault or an All Notes mode;
- a generic task manager or plugin marketplace;
- a Zotero replacement or embedded PDF reader;
- automatic untraced-premise verdicts;
- Canvas authoring or conversion of Canvas edges into Markdown;
- a proprietary backup-export format;
- complete arbitrary Obsidian-theme compatibility; or
- bundled general instructions that purport to teach researchers how to
  conduct philosophy; researcher-authored skills remain the researcher's
  responsibility.

The following capabilities are intentionally deferred beyond 0.1 rather than
permanently rejected:

- document, project, HTML, PDF, or DOCX export;
- additional bundled discipline-specific skills and skill-driven workflows;
  and
- richer Dialogue compression and reflection modes.

### 4.3 Standalone academic workflow

Scholium MUST support its core academic workflow without requiring Obsidian.
For this PRD, that workflow includes:

- configuring and opening a Triptych;
- reading and writing exact Markdown;
- creating and using Analyses, Topics, and Works;
- source-linked research context through the bounded Zotero integration when
  Zotero is used;
- Human Review, comments, Connections, Search, Attention, checkpoints, and
  recovery;
- optional Dialogue between the researcher and one or more external agents;
- optional Work Critique; and
- optional bounded Zotero context.

Dialogue and Critique are supported product extensions, but no external agent,
Zotero installation, or Critique result is required to complete the manual
academic workflow.

This requirement does not require Scholium to reproduce Obsidian's entire
feature set, theme system, plugin ecosystem, or visual conventions. Obsidian
import and interoperability MAY remain available, but no core academic
journey, setup path, file model, or user-facing instruction may assume that
Obsidian is installed.

## 5. Product baseline and release boundary

### 5.1 Baseline covered by this PRD

This PRD describes the target Scholium baseline rather than a single sprint.
The baseline includes:

1. complete Triptych setup, registration, and multiwindow separation;
2. exact-source Markdown reading and editing;
3. role-aware note lifecycle, identity, Properties, and source preservation;
4. Human Review and comments for Analyses and Topics;
5. researcher-centred Dialogue records with optional transient agent-instruction
   generation and attributed replies;
6. optional Work Critique with source-located findings;
7. canonical Connections, Search, and Attention, with Canvas explicitly
   deferred until the core document workflow is stable;
8. self-contained checkpoints, comparison, selective restore, and full restore;
9. optional bounded, read-only local Zotero integration;
10. direct CLI operations with revision checks; and
11. native, accessible, document-first macOS interaction.

### 5.2 Release boundary

The current release is **0.1 Experimental**, owned by Imna. It validates the
foundational document-first workflow and its boundaries; it is not a claim of
Beta or 1.0 readiness.

| Decision | Status | Owner | Due |
| --- | --- | --- | --- |
| Release name and version | 0.1 Experimental | Imna | Current |
| Minimum release scope | Manual core workflow plus the documented optional Dialogue and integration boundaries | Imna | Current PRD baseline |
| User-outcome targets | Proposed measures; no formal usability baseline yet | Imna | Before Alpha/Beta |
| Accessibility acceptance threshold | Defined in PRD-UX-005 and Design Handbook §8.4; not yet passed by 0.1 | Imna | Beta/1.0 gate |
| Performance targets | R1/RDF-1 benchmark policy defined; numeric thresholds not yet measured | Imna | Before Beta |
| Packaging and distribution | Source-first GitHub beta approved: exact GPL-tagged source plus an optional ad-hoc-signed app-only ZIP and checksum | Imna | Before `v0.1.0-beta.1` |
| Developer ID signing and notarization | Optional and deferred pending institutional sponsorship or sufficient demand | Imna | Future distribution decision |

The product MUST NOT be represented as release-ready solely because the Product
Guide is complete. Release readiness requires the gates in Section 14 and an
explicit disposition for all unresolved items in Section 15.

### 5.3 Product constitution and release definition

The following principles constrain every target requirement in this PRD:

- Researcher-authored Markdown and settled prose remain under the
  researcher's control.
- Scholium independently supports the manual academic workflow; Obsidian,
  Zotero, external agents, and research skills are optional extensions.
- Dialogue records the scholarly exchange between researcher and agent rather
  than the technical mechanics of an LLM.
- Notes represent the researcher's eventual formulation. Dialogue, Critique,
  comments, reviews, indexes, and checkpoints remain distinct records.
- Scholium provides structure, recovery, and reviewability, but does not decide
  truth, philosophical support, sufficiency, or settlement.
- Local source fidelity, explicit uncertainty, and recoverability take priority
  over automation or convenience.

Release stages are capability-based:

| Stage | Definition | Current disposition |
| --- | --- | --- |
| Experimental 0.1 | Foundational product and interaction concepts are being validated. The researcher can use the document-first app and manual research primitives; data and interface contracts may still evolve. | Current release; owner Imna. It does not claim Beta or 1.0 readiness. |
| Alpha | One researcher can complete the manual core academic workflow in a clean environment without Obsidian, Zotero, or an external agent. | Future stage. |
| Beta | The core workflow and file format are stable for real external research use; the applicable release gates have evidence, with only bounded polish or deferred capabilities remaining. | Future stage. |
| 1.0 | A researcher can sustain daily academic work from setup through writing, review, recovery, and delivery without depending on Obsidian or manual filesystem operations. | Future stage. |

The release owner is Imna. A release declaration MUST identify the version,
stage, applicable gates, evidence, deferred capabilities, and any explicit
waivers. Richer bundled skill content and skill-driven workflows are not a 0.1
dependency; the bounded file-backed management requirement below does not make
skills necessary for the manual academic workflow.

## 6. Product model and authoritative data

### 6.1 Scholium Triptych

Each Triptych MUST contain exactly three independently located vaults:

| Vault | Product role |
| --- | --- |
| Analyses | Reusable source analyses for papers and other research materials. |
| Topics | Reusable topic-centred knowledge, including concepts, terminology, distinctions, positions, debates, objections, and synthesis. |
| Works | Researcher-governed writing, planning notes, arguments, drafts, papers, chapters, books, Critiques, and related material. |

Unclassified is temporary staging for imported Triptych-relevant Markdown. It
is not a fourth research vault.

### 6.2 Source and derived state

| Material | Authority/status |
| --- | --- |
| Markdown bytes and explicitly edited YAML | Authoritative research source. |
| Read, Live Preview, and Source presentations | Reversible projections of one exact source buffer. |
| Search, link, graph, render, and Zotero presentation state | Derived state; never authoritative research content. |
| Researcher comments and Human Review | App-owned researcher records associated with an exact fingerprint. |
| Dialogue entries and agent replies | App-owned scholarly interaction records; not technical prompt logs or document versions. |
| Critique document | Ordinary Markdown associated with one Work; attributed agent assessment, not a replacement for the Work. |
| Checkpoint | Self-contained fingerprint-bound snapshot; distinct from editor Undo and subject to the permanent-deletion purge rule. |

### 6.3 Storage boundaries

A portable .scholium directory beside Works MAY contain Triptych configuration,
identity mappings, guide state, per-vault Properties, prompt templates and
their workflow assignments, Triptych-local user skill packages at
`.scholium/skills/<skill-id>/SKILL.md`, and imported Unclassified Markdown.

Machine-specific or replaceable state MUST remain in Application Support,
including bookmarks, window sessions, indexes, caches, app-owned review and
comment records, Dialogue replies, and checkpoints.

Scholium MUST NOT upload .scholium or research content automatically.

## 7. Functional requirements

Each requirement below has a target behavior, acceptance criteria, source
authority, and current status. The current status is a planning signal, not a
substitute for current tests.

### 7.1 Triptych setup, registration, and navigation

#### PRD-TRI-001 — Exactly three vaults

**Requirement:** Scholium MUST represent one Triptych as exactly one Analyses
vault, one Topics vault, and one Works vault. The three locations MAY be
independently located. Scholium MUST reject configurations that would cause two
Triptychs to share one portable control directory beside Works.

**Acceptance criteria:**

- New Triptych setup requests three locations.
- The interface presents Analyses, Topics, and Works as peer roles.
- No fourth vault or All Notes mode is available.
- Existing vault bytes are not moved automatically.
- Invalid shared-control-directory configurations are rejected with a
  recoverable explanation.

**Authority:** Product Guide sections 1 and 3; Design Handbook section 4.1.
**Status:** Target; multiple Triptych behavior is reported reachable, with
remaining interactive acceptance noted in Implementation Status.

#### PRD-TRI-002 — Triptych windows

**Requirement:** One window MUST belong to one complete Triptych. Multiple
Triptychs MAY be open simultaneously in separate windows. Each window MUST own
its selection, tabs, document modes, History, inspector, scroll locations,
search state, and Canvas state while shared services remain coherent.

**Acceptance criteria:**

- File → New Triptych… opens setup for three new locations.
- File → Open Triptych opens a registered Triptych in its own window.
- File → New Window opens another independent window for the focused Triptych.
- Commands route to the focused window and document.
- Shared repositories, indexes, watchers, identity registries, and graph state
  do not become divergent per-window copies.

**Authority:** Product Guide section 3.2; Design Handbook sections 4.1–4.2 and
decision D-020.
**Status:** Reachable; registry, per-window sessions, and shared
`WorkspaceStore` ownership are implemented. Sustained interactive multiwindow
acceptance remains open.

#### PRD-TRI-003 — Works organization without project management

**Requirement:** Works MUST remain an ordinary researcher-controlled Markdown
hierarchy. Scholium MAY display folders and folder context, but MUST NOT
register, select, validate, assign, or manage projects.

**Acceptance criteria:**

- A Works folder can represent a paper, chapter, book, dissertation, or any
  other researcher-chosen grouping.
- No project selector appears below Triptych navigation.
- No project completeness, readiness, or membership warning is generated.
- No folder-specific schema, mandatory template, or one-note-per-concept rule
  is imposed.

**Authority:** Product Guide sections 3.2 and 4; Design Handbook decision D-015.
**Status:** Reachable; project-management UI is removed and Works organization
remains ordinary folder structure.

#### PRD-TRI-004 — Onboarding and management

**Requirement:** First launch MUST ask the researcher to select Analyses,
Topics, and Works locations and explain local-first storage, generated state,
and the agent boundary. Later management MUST support complete registered
Triptychs and three-root editing without requiring a project setup.

**Acceptance criteria:**

- First-run setup reaches usable folders without requiring a feature tour.
- Manage Triptychs… lists complete registered Triptychs.
- Standard Open panels are used for vault and import selection.
- Errors identify the affected operation and offer recovery actions.

**Authority:** Product Guide section 16; Design Handbook section 4.9.
**Status:** Target; implementation evidence exists, but full onboarding and
settings acceptance remain part of the completion work.

#### PRD-TRI-005 — Unclassified import

**Requirement:** Import MUST copy selected Markdown into .scholium/unclassified/
without changing the original. The imported copy MUST remain readable and
editable but MUST not receive role-specific Review, qualification, Critique, or
Properties behavior until classification.

**Acceptance criteria:**

- Original files remain unchanged.
- Imported copies can be classified into Analyses, Topics, or Works.
- Classification is reversible through ordinary file and lifecycle operations
  where the target rules permit.
- Failed classification does not leave an unverified partial migration.

**Authority:** Product Guide section 3.5.
**Status:** Reachable according to Implementation Status; rollback and recovery
behavior must remain covered by tests.

### 7.2 Documents, source fidelity, and identity

#### PRD-DOC-001 — Exact Markdown source

**Requirement:** Scholium MUST treat exact UTF-8 Markdown and targeted YAML
changes as authoritative. Outside an explicitly changed range it MUST preserve
BOM, newline style, comments, unknown YAML, ordering, quoting, multiline
values, and final newlines.

**Acceptance criteria:**

- Read, Live Preview, Source, search, links, and diagnostics derive from the
  same committed source revision.
- Targeted property edits do not whole-file or whole-frontmatter reserialize
  unrelated content.
- Malformed or unknown source remains readable and is not silently repaired.
- Write failure preserves the current buffer, selection, and typed values.
- Readback verifies the committed bytes after an atomic write.

**Authority:** Product Guide sections 5.1 and 5.2; Design Handbook sections
3.3, 4.4, 9, and 10.
**Status:** Reachable in current implementation evidence; continued fidelity
regression testing is a release gate.

#### PRD-DOC-002 — Document modes

**Requirement:** Read, Live Preview, and Source MUST be modes of one document,
not separate files or ordinary tabs.

**Acceptance criteria:**

- Read provides selectable semantic prose and source navigation.
- Live Preview edits the exact Markdown body through a visual projection,
  hides YAML frontmatter, and does not expose a line-number gutter.
- Source exposes complete Markdown and YAML and MAY show line numbers.
- Mode transitions preserve focus, selection, scroll, and nearest semantic
  location where possible.
- Source and editor behavior supports undo, Find, keyboard access, marked-text
  composition, and accessibility.

**Authority:** Product Guide section 5.1; Design Handbook sections 4.4, 5,
8.2, and 10.
**Status:** Reachable with fallback and editor bundle evidence; full
accessibility and large-document acceptance remains required.

#### PRD-DOC-003 — Common note capabilities

**Requirement:** Analysis, Topic, and ordinary Work notes MUST support reading,
editing, comments, Connections, role-aware Properties, search, Attention, Note
History, and safe file lifecycle operations.

**Acceptance criteria:**

- Create, duplicate, import, rename, move, Set Aside, Trash, restore, Reveal
  in Finder, and permanent deletion are available where applicable.
- Autosave does not require an ordinary Save button.
- App writes are atomic and conflict-aware.
- External edits are reconciled without silently replacing dirty buffers.

**Authority:** Product Guide sections 5 and 6.
**Status:** Reachable in implementation evidence. The current coordinator
purges the selected source note and a Work's separate current Critique Markdown,
repository versions, Human Review/comments, every Dialogue containing either
stable identity, Critique associations, portable identity state, and every
checkpoint containing either identity. Durable pre-commit rollback and
post-commit cleanup recovery are covered with fresh-runtime tests; broader
lifecycle UI acceptance remains open.

#### PRD-DOC-004 — Stable identity and path changes

**Requirement:** Every note MUST have a stable app-owned identity. Paths are
locations, not identity. Duplicates receive new identities; confirmed app
moves and renames preserve associated app-owned records.

**Acceptance criteria:**

- Duplicate resets Human Review and qualification and records its source note.
- Confirmed app moves preserve comments, History, and applicable Critique
  association.
- Resolved incoming links are updated after app-performed move or rename.
- Ambiguous external identity changes keep the note readable but block
  identity-dependent mutations until confirmation.

**Authority:** Product Guide section 5.3; Implementation Status sections 1 and
2.
**Status:** Reachable; confirmed app moves and externally reconciled renames
migrate stable identity, Note History references, Human Review/comments, Dialogue
references, Critique associations, window snapshots, and Canvas references.
Ambiguous external identity changes require confirmation.

#### PRD-DOC-005 — Properties

**Requirement:** Each of Analyses, Topics, and Works MUST support a fixed
starting profile that the researcher can configure by vault. Configuration MUST
control visible fields, order, disclosure, and human-editable allowlist
without allowing protected identity and automatic fields to be edited through
structured Properties.

**Acceptance criteria:**

- No folder-level or note-level Properties layouts are required.
- Protected fields remain available in Source mode for exact YAML editing.
- Absent, empty, invalid, derived, and not-applicable values are distinct.
- Legacy YAML remains readable and is not bulk-rewritten automatically.

**Authority:** Product Guide section 5.2; Design Handbook sections 4.6 and 9.
**Status:** Reachable. Legacy role, property-alias, sparse window/Search,
Triptych-identity, and Canvas compatibility paths are covered by immutable
fixtures. Reads preserve fixture bytes; malformed present fields and unknown
roles fail closed.

#### PRD-DOC-006 — Set Aside, Trash, and deletion

**Requirement:** Set Aside MUST be a direct reversible action without a stored
failure or superseded label. Move to Trash MUST be recoverable until explicit
permanent deletion. Trashed and set-aside notes MUST be excluded from ordinary
research workflows according to the Product Guide.

**Acceptance criteria:**

- The actions are Set Aside, Move to Trash, and Cancel.
- Set-aside notes remain readable and recoverable but are excluded from
  ordinary search, synthesis, Critique, and agent context unless included.
- Trashed notes are excluded from ordinary search, Connections, agent context,
  and research workflows.
- Permanent deletion is explicit. It MUST purge the deleted note's associated
  comments, Dialogue records, Critique associations, review records, and other
  note-specific app state.
- Permanent deletion MUST also remove the note and those associated records
  from every checkpoint copy. A checkpoint that cannot be safely scrubbed MUST
  be invalidated and removed rather than retaining a recoverable copy.
- If a multi-note Dialogue or other shared record cannot be partitioned without
  retaining content belonging to the deleted note, the shared record MUST be
  deleted in full.

**Authority:** Product Guide section 6; Design Handbook sections 4.8 and 10.
**Status:** Reachable in implementation evidence and covered by disposable
filesystem tests. Work/current-Critique deletion is one recoverable transaction:
pre-commit failures and interruption restore exact files and records, while an
interruption after the commit decision resumes privacy cleanup. A concurrent
replacement at a deleted path is preserved rather than overwritten. Broader
lifecycle and recovery UI acceptance remains open.

#### PRD-DOC-007 — External changes and conflicts

**Requirement:** Scholium MUST treat external edits as concurrent filesystem
changes. A clean open note MAY refresh quietly. A dirty local buffer MUST be
preserved and presented as a conflict when the disk revision diverges.

**Acceptance criteria:**

- The conflict identifies that disk changed and preserves both revisions.
- Available actions are Compare Changes, Reload from Disk, and Keep Editing.
- Reload from Disk is never the harmless or implicit default.
- Comparison returns to the same conflict decision.
- A failed derived refresh does not relabel an authoritative source commit as
  unsaved.

**Authority:** Product Guide sections 2.2, 8.4, and 14; Design Handbook
sections 3.3, 9, and 10.
**Status:** Reachable in current implementation evidence; sustained
multiwindow and conflict-recovery UI acceptance remains open.

### 7.3 Human Review, comments, and qualification

#### PRD-REV-001 — Human Review

**Requirement:** Human Review MUST apply to Analyses and Topics. A completed
review MUST record a Qualified or Unqualified verdict and a non-empty Review
Note of at most 500 characters. Works MUST use Critique rather than
qualification.

**Acceptance criteria:**

- The available action is Review, Continue Review, Qualified, or Unqualified,
  according to state.
- Complete Review is unavailable until verdict and review note are present.
- Save as Draft preserves incomplete work without marking the fingerprint
  reviewed.
- Cancel discards unsaved sheet changes.
- Qualification can change only through Review.

**Authority:** Product Guide section 7; Design Handbook sections 4.8 and 10.
**Status:** Reachable in current implementation evidence; full clean-account
  and accessibility acceptance remains open.

#### PRD-REV-002 — App-owned comments

**Requirement:** Researcher comments MUST remain outside Markdown source and
bind to stable identity, exact fingerprint, source range, quotation, and
context where applicable. Comments MUST not insert hidden Markdown.

**Acceptance criteria:**

- Read and editor selections create the same comment record shape.
- A comment can be edited, deleted, resolved, or reattached by the researcher.
- After edits, reattachment occurs only when quotation and context identify one
  reliable location.
- Ambiguous comments are marked Needs Reattachment.
- An agent MAY reply but MUST NOT resolve a researcher comment.

**Authority:** Product Guide section 7.2; Design Handbook sections 3.4, 8,
  and 10.
**Status:** Partial; Trash retention remains separate and permanent deletion
removes the selected Work and associated Critique Human Review/comment records.
Cross-store failure and fresh-runtime rollback coverage is implemented; full
comments UI acceptance remains open.

#### PRD-REV-003 — Unqualified Analysis Attention

**Requirement:** An Unqualified Analysis MUST remain readable, linkable,
searchable, usable in Topic integration, Work Critique, and further agent
work. Explicit scholarly reliance MAY produce a source-anchored Attention;
a neutral link alone MUST NOT be treated as reliance.

**Acceptance criteria:**

- Unqualified status does not block editing or agent work.
- Attention identifies the explicit reliance and source anchor where one exists.
- Attention does not make a philosophical judgment and does not block work.
- The warning clears when qualification or usage changes.

**Authority:** Product Guide section 7.3; Design Handbook sections 4.7 and 9.
**Status:** Reachable according to Implementation Status.

### 7.4 Dialogue and external agent work

#### PRD-DIA-001 — General Dialogue instruction generation

**Requirement:** Dialogue MUST let the researcher select one or several notes
and provide one overall researcher Comment or instruction. It MUST generate
copyable context without communicating with an agent process or imposing
specialized task types. Using an external agent is optional; Dialogue remains
usable as a researcher-facing record even when no agent is involved. The
active template and assembled technical instructions MUST remain hidden from
the Dialogue workflow and MUST NOT permit one-run selection or editing there.

The generated prompt SHOULD include, as applicable:

- researcher instruction;
- selected note names, vault-relative paths, and advisory fingerprints;
- selected passages, source lines, and included comments;
- Triptych context, linked-note context, and ordinary Work metadata;
- requested destination and editing rules; and
- permission to inspect and directly modify relevant Triptych files.

**Acceptance criteria:**

- The sheet displays the selected-note list, included Comments, consequential
  context, and one researcher instruction field.
- The researcher verifies the selected context rather than inspecting or
  editing the prompt template or assembled technical instructions.
- **Edit Dialogue Template…** opens **Settings → Research Guidance** at the
  active Dialogue template without discarding current Dialogue inputs.
- Pending autosaves complete before copying.
- A Before Agent Work checkpoint is created before copying.
- Scholium does not transmit research automatically.

**Authority:** Product Guide section 8.1; Design Handbook sections 3.5, 4.8,
  and 10.
**Status:** Reachable according to Implementation Status; full Dialogue
presentation and clean-account acceptance remain open.

#### PRD-DIA-002 — Dialogue History and CLI replies

**Requirement:** Each selected note MUST receive the Dialogue entry in its own
Note History. Dialogue entries MUST remain distinct from document versions.
A local agent MAY reply through the scholium dialogue CLI, which MUST validate
request and comment identities before writing attributed records.

**Acceptance criteria:**

- Multi-note Dialogue entries appear in every selected note's History.
- Entries show researcher Comments, selected notes, checkpoint, and replies
  where available. Transport context may be inspected while instructions are
  copied, but technical prompt text is not required as part of the scholarly
  record.
- Entries provide no document restore action.
- Replies are immutable and attributed.
- Manual return of a reply remains possible for agents without local CLI
  access.

**Authority:** Product Guide section 8.2; Design Handbook section 10.
**Status:** Reachable according to Implementation Status.

#### PRD-DIA-003 — Concise scholarly interaction and academic change summary

**Requirement:** Dialogue MUST preserve the researcher's Comments, agent
Responses, and chronological follow-up Comments and Responses. The record MUST
remain concise at the level of scholarly interaction rather than LLM mechanics.
It MUST NOT require hidden prompts, model parameters, token counts,
paragraph-level AI provenance, or a separate AI audit dashboard. When an agent
has changed research notes, its default closing response MUST give a concise
summary of the academic change and identify any unresolved issue or required
researcher review when relevant. Routine file-operation details are secondary.

The eventual note remains the researcher's decision. Scholium does not require
an accept/reject state for each agent Response, and an agent Response does not
silently become authoritative note content.

**Acceptance criteria:**

- Researcher Comments and agent Responses are clearly distinguishable.
- Follow-up exchanges retain their order and remain attached to the selected
  Dialogue.
- Multiple agents MAY participate when the researcher uses them; participant
  attribution remains simple and human-readable.
- The Dialogue record remains usable without exposing technical prompt or model
  metadata.
- The agent's closing response foregrounds academic change, unresolved
  questions, or review needs rather than a detailed operation log.
- Richer comment-preservation and reflection modes remain deferred until their
  interaction design is approved.

**Authority:** Product Guide sections 1 and 8; Design Handbook sections 3.5,
4.8, 7, and 10.
**Status:** Implemented in the reachable app. Dialogue stores and presents the
initial researcher Comment, chronological follow-up Comments, and attributed
agent Responses; legacy records decode without synthetic turns and path
migration retains existing exchanges. The default bundled response contract
requires a concise academic-change summary and unresolved question or required
researcher review when applicable. Focused isolated UI acceptance covers
append, chronology, close/reopen persistence, and the canonical journey.

#### PRD-RGD-001 — Settings-only prompt-template configuration

**Requirement:** **Settings → Research Guidance** MUST be the only Scholium
surface that displays or edits prompt templates. Each supported workflow MUST
have one active Triptych-local template. Workflow surfaces MUST expose
scholarly inputs and scope without exposing template names, bodies,
placeholders, previews, pickers, assembled technical instructions, or one-run
prompt editors.

**Acceptance criteria:**

- Research Guidance provides a **Prompt Templates** collection and one native
  multiline editor, with structural validation and preview.
- Researchers can create, duplicate, rename, delete, and assign templates.
- Editing a Scholium default creates a researcher-owned customization, and
  **Reset to Scholium Default** restores the bundled baseline without silently
  overwriting another researcher-created template.
- A restrained workflow text action opens Research Guidance at the exact
  applicable template; **Edit Critique Template…** opens **Prompt Templates →
  Critique**.
- A structurally invalid active template preserves current workflow inputs,
  provides the applicable Settings action, and blocks instruction copying or
  Critique request generation until the blocking problem is resolved.
- Structural validation does not judge philosophical quality, truth, support,
  settlement, or methodological sufficiency.
- Technical template text and assembled instructions do not become part of the
  scholarly Dialogue record.

**Authority:** Product Guide section 8.3; Design Handbook sections 4.8, 4.9,
and 10.
**Status:** Implemented in the reachable app. The Settings-only Prompt
Templates collection, active Triptych-local Dialogue and Critique templates,
structural validation, preview, workflow deep links, and technical-source
exclusion from new scholarly Dialogue records have focused automated evidence.

#### PRD-RGD-002 — File-backed skill management

**Requirement:** **Settings → Research Guidance → Skills** MUST let the
researcher manage bundled Scholium skills and Triptych-local user skills while
keeping skills distinct from prompt templates. Scholium MUST discover a user
skill only from `.scholium/skills/<skill-id>/SKILL.md` and MUST NOT scan research
notes, arbitrary filesystem locations, `~/.codex/skills`, or another agent's
global configuration.

**Acceptance criteria:**

- Research Guidance identifies **Bundled** and **Triptych** skills in text and
  uses the same native list-and-detail editing architecture as Prompt
  Templates without merging their semantics.
- The researcher can inspect and edit Triptych-local `SKILL.md` source,
  duplicate a bundled skill into the Triptych, rename or delete a
  Triptych-local skill, reset a customized bundled skill, and use **Reveal
  Skills Folder** to open the supported location.
- A user package is manageable only when it is located under the supported
  skills root and contains `SKILL.md`. Structural validation identifies missing
  or malformed required metadata without judging philosophical accuracy,
  methodological quality, truth, or suitability.
- An invalid skill remains visible with a recoverable inline error but is not
  available for instruction assembly until corrected.
- Skill management does not create a marketplace, automatic download or
  installation, embedded agent runtime, workflow-local picker, one-run skill
  override, or claim that Scholium endorses a skill's output.
- Skill source does not become part of the permanent scholarly Dialogue record.

**Authority:** Product Guide sections 2.2, 3.3, and 8.3; Design Handbook
sections 4.9 and decision D-029.
**Status:** Implemented in the reachable app. Discovery is bounded to direct
packages under the portable Skills root; bundled and Triptych-local management,
inline structural recovery, revision checks, safe instruction assembly, and a
focused isolated Settings journey have automated evidence.

### 7.5 Works and Critique

#### PRD-CRI-001 — Critique association and storage

**Requirement:** A Work MAY have at most one current Critique document. A
Critique normally targets one Work, lives in the designated Critiques area,
remains distinct from Work prose, and is read-only inside Scholium while
remaining ordinary Markdown for external editors.
Critique is an optional agent-assisted extension and is not required for the
manual academic workflow.

**Acceptance criteria:**

- Request Critique is available for a Work where applicable.
- Later Critique rounds update the current Critique while earlier states remain
  available through checkpoint-backed history.
- Critiques cannot cross the Critiques boundary through ordinary lifecycle
  actions.
- Critique association records the target Work and target fingerprint.
- External edits to the ordinary Critique file are detected safely.

**Authority:** Product Guide section 11; Implementation Status section 1.
**Status:** Reachable; association migration follows confirmed moves and
externally reconciled renames. A disposable accessibility-driven journey now
verifies agent attribution, deterministic Specific Findings disclosure, and
exact Source navigation. The equivalent focused XCUITest is implemented but
its current execution is blocked before app launch by the local macOS
automation-mode timeout, so full Critique UI acceptance remains open.

#### PRD-CRI-002 — Critique request and form

**Requirement:** Request Critique MUST offer Overall Critique, Specific
Comments, or Both, with optional scholarly scope such as a selection, line
range, section, focus, or disciplinary lens. It MUST NOT display or permit
one-run selection or editing of the active template or assembled technical
instructions.
Request Critique remains optional; a Work can be written and revised without
requesting a Critique.

The default Critique MUST distinguish source reports, support, disputes, and
uncertainty from agent reconstruction or evaluation. It MUST identify
materials consulted and limitations.

**Acceptance criteria:**

- The Critique contains the default sections: Overall Assessment, Strengths,
  Major Concerns, Source Support, Objections and Alternatives, Revision
  Priorities, Specific Findings, and Materials Consulted and Limitations.
- Source-related findings MAY be labelled Traced, Untraced, Disputed, or
  Beyond Sources.
- Findings record target Work, fingerprint, heading or section where available,
  original line, and a short quotation.
- A finding with a fingerprint mismatch is visibly an earlier-version finding.
- Ambiguous target passages are never guessed.
- Critique attribution is visible before the body.
- The workflow states that Critiques use the template configured for the
  Triptych and provides **Edit Critique Template…**, which opens **Settings →
  Research Guidance → Prompt Templates → Critique**.
- No template body, placeholder list, template picker, preview, additional
  technical-instruction field, or one-run prompt editor appears in the Critique
  workflow.

**Authority:** Product Guide section 11.3–11.4 and Appendix A; Design Handbook
sections 4.8, 9, and 10.
**Status:** Reachable in current implementation evidence; overlaying findings
directly on Work prose remains deferred.

### 7.6 Connections, Canvas, Search, and Attention

#### PRD-CON-001 — Canonical Connections

**Requirement:** Scholium MUST support the four canonical source forms:

| Markdown | Meaning |
| --- | --- |
| [[B]] | Neutral, undirected A—B connection. |
| +[[B]] | A supports B. |
| -[[B]] | B supports A. |
| ?[[B]] | Symmetric incompatibility A—B. |

Aliases, headings, and fragments remain supported. Legacy source bytes remain
untouched and receive diagnostics only.

**Acceptance criteria:**

- Incoming and Outgoing views show direction and exact source location.
- Resolution is deterministic within the Triptych and reports ambiguity.
- Legacy syntax is not automatically converted.
- Source punctuation and unrelated bytes remain unchanged.

**Authority:** Product Guide section 12; Design Handbook decision D-018.
**Status:** Reachable according to Implementation Status.

#### PRD-CON-002 — No inferred philosophical evidence

**Requirement:** Scholium MUST NOT infer philosophical support, truth,
settlement, sufficiency, or integration from keywords, proximity, folder
membership, Canvas placement, graph paths, neutral links, or transitivity.

**Acceptance criteria:**

- Neutral and transitive paths are presented as Connections, not evidence.
- Derived warnings identify themselves as derived.
- Source-related Critique judgments remain attributed agent judgments.
- Search results remain retrieval leads, not evidence.

**Authority:** Product Guide sections 2, 10, 12, 13, and 18; Design Handbook
sections 3.4 and 7.
**Status:** Target; current implementation evidence reports the canonical
graph and Attention contract.

#### PRD-CAN-001 — View-only Canvas

**Requirement:** Canvas MAY provide an optional spatial view of notes and
Connections. It MUST remain view-only and MUST provide an accessible,
source-anchored list equivalent.

**Acceptance criteria:**

- Canvas cannot author a relation.
- Canvas edges cannot be converted into Markdown.
- Every spatial relation has a keyboard-accessible list or table equivalent.
- Source location can be opened from the list.

**Authority:** Product Guide section 12; Design Handbook sections 4.7, 8.2,
and 9.
**Status:** Deferred from the stable UI while the core document workflow is
stabilized. Legacy Canvas records remain read/migration compatibility only;
view-only and accessible-list acceptance must be re-established before return.

#### PRD-SEA-001 — Search scopes

**Requirement:** Sidebar filtering, Quick Open, in-note Find, full ranked
Triptych search, and Research inspector retrieval MUST remain distinct tasks
while sharing a clear query and filter contract.

**Acceptance criteria:**

- Search results show title, snippet, field/context, and destination.
- Quick Open supports Triptych-wide title, path, and alias navigation with
  vault-qualified destinations.
- Recent Notes returns to a bounded, per-window, vault-qualified MRU list
  without depending on derived Search or graph readiness.
- In-note Find operates within the current note.
- Loading, zero-result, malformed, conflict, and inaccessible states remain
  scoped and recoverable.
- Search does not rewrite source or claim evidential support.

**Authority:** Product Guide section 13; Design Handbook sections 4.3 and 9.
**Status:** Reachable according to Implementation Status. In-note Find,
heading outline, saved-search management, and per-window Recent Notes are
implemented.

#### PRD-ATT-001 — Derived Attention

**Requirement:** Attention MUST report only defined, derived warnings and
recoverable research issues. Every item MUST be dismissible, identify its
derived status, and open its source line when one exists.

Attention MAY report:

- possible orphan structure;
- Changed Since Review;
- broken or ambiguous Connections;
- explicit reliance on an Unqualified Analysis;
- malformed metadata; and
- unresolved identity.

**Acceptance criteria:**

- No Attention item is nondismissible.
- Dismissal duration is Triptych-local and defaults to seven days.
- Attention does not infer Superseded status from file age.
- Attention does not implement automatic untraced-premise verdicts.
- Retired governance queues and philosophical settlement judgments do not
  appear in the Research inspector.

**Authority:** Product Guide section 13; Design Handbook sections 4.7 and 9.
**Status:** Reachable according to Implementation Status.

### 7.7 Checkpoints, versions, and recovery

#### PRD-CHK-001 — Before Agent Work checkpoint

**Requirement:** Immediately before Scholium generates and copies researcher
instructions for an agent, it MUST complete pending autosaves and create a
named, fingerprint-bound checkpoint of the entire Triptych.

**Acceptance criteria:**

- The checkpoint is named Before Agent Work.
- It contains the complete Triptych and portable configuration needed to
  interpret it.
- It is stored outside the vaults.
- It is not confused with a Dialogue entry or editor Undo.
- Manual checkpoints remain available.

**Authority:** Product Guide sections 8.1 and 14; Design Handbook section 10.
**Status:** Reachable according to Implementation Status.

#### PRD-CHK-002 — Self-contained restore

**Requirement:** Checkpoints MUST be self-contained and remain usable if
another checkpoint is moved or deleted. Scholium MUST support comparison,
selective note restore, complete Triptych restore, and Finder reveal.

**Acceptance criteria:**

- Comparison identifies created, changed, moved, deleted, and unchanged files
  in text.
- Selective restore does not require full rollback.
- Full rollback moves files created after the checkpoint to Trash rather than
  permanently deleting them.
- Restore uses the same conflict-aware repository path as normal writes.
- A restore conflict does not silently replace current changes.
- Permanent deletion scrubs the deleted note and its associated app-owned
  records from every checkpoint copy, or invalidates and removes a checkpoint
  that cannot be scrubbed safely.

**Authority:** Product Guide section 14; Design Handbook sections 9 and 10.
**Status:** Partial target; restore behavior is reported reachable, and
permanent deletion invalidates every checkpoint containing the selected Work or
associated Critique stable identity as part of the recoverable deletion
transaction. Complete recovery and accessibility UI journeys remain release
gates.

#### PRD-CHK-003 — Undo versus durable recovery

**Requirement:** Editor Undo MUST reverse current-session editing operations.
Restore from Checkpoint… MUST create a new current version through the
conflict-aware repository and MUST NOT silently rewrite history.

**Acceptance criteria:**

- The interface uses distinct labels and actions.
- Ordinary autosaves do not create visible versions.
- A restored version remains attributable to the restore operation.

**Authority:** Product Guide section 14; Design Handbook section 10.
**Status:** Target; current implementation evidence reports separate Note
History and checkpoint behavior.

### 7.8 Zotero integration

#### PRD-ZOT-001 — Local, read-only Zotero boundary

**Requirement:** Scholium MAY read Zotero through the localhost API only when
the researcher chooses to use Zotero. Zotero MUST NOT be required for the core
workflow. When enabled, Scholium MUST NOT require a server, password, online
Web API, attachment enumeration, attachment download, SQLite access, or
Zotero metadata writes.

**Acceptance criteria:**

- Settings exposes connection status, Open Zotero, Test Connection, Refresh
  Library Information, Forget Cached Zotero Data, and last successful
  connection time.
- Privacy explanation is concise and local.
- Unavailable Zotero states explain the exact condition.
- Cached metadata is labelled with retrieval time.
- The only source action is Open in Zotero.

**Authority:** Product Guide section 15; Implementation Status sections 2 and
  3.
**Status:** Reachable according to current evidence.

#### PRD-ZOT-002 — Stable matching

**Requirement:** Matching MUST prefer zotero_item_key, then DOI or ISBN, then
citation key, then exact title plus author and year. Ambiguous matches MUST
remain visible and require researcher selection.

**Acceptance criteria:**

- No ambiguous candidate is silently selected.
- Confirmed matches can persist the item key through the permitted property
  path.
- Technical keys remain out of ordinary UI labels.

**Authority:** Product Guide section 15.2.
**Status:** Reachable according to Implementation Status.

#### PRD-ZOT-003 — Bounded source presentation

**Requirement:** For an Analysis, Research shows only that Analysis's Zotero
item. For a Topic or Work, Zotero Sources from Linked Analyses includes only
outgoing linked Analyses with keyed Zotero items. Incoming backlinks,
transitive paths, bibliography text, Unclassified notes, children, and the
wider library MUST be excluded.

**Acceptance criteria:**

- Duplicate keyed papers appear once.
- Compact metadata includes title, authors, year, publication, available
  volume/issue/pages, primary identifier, and citation key.
- Expanded metadata is disclosed separately.
- The Research inspector does not present unrelated library items.

**Authority:** Product Guide section 15.2; Implementation Status section 1.
**Status:** Reachable according to current evidence.

### 7.9 Agent-facing CLI

#### PRD-CLI-001 — Direct operations and revision checks

**Requirement:** The agent-facing CLI MUST support explicit, script-friendly
operations within the target boundary, including note create, replace,
move, Set Aside, Trash, and delete where implemented. Existing-note
mutations MUST require the current SHA-256 fingerprint and canonical
vault-relative paths.

**Acceptance criteria:**

- Traversal, nonexistent targets, symlink escape, stale fingerprints,
  malformed proposed frontmatter, and cross-vault identity mismatch are
  rejected.
- Writes use snapshots, validation, atomic replacement, readback, and accurate
  attribution.
- CLI replies validate request and comment identities.
- CLI behavior does not reintroduce Proposal as an authorization layer.

**Authority:** Product Guide sections 2.2, 8.2, and 17; Scholium development
guidance; Implementation Status sections 1 and 3.
**Status:** Reachable according to current evidence.

### 7.10 Standalone academic workflow

#### PRD-INT-001 — No Obsidian dependency

**Requirement:** A researcher MUST be able to complete the core academic
workflow in Scholium without installing or using Obsidian. Obsidian MAY be
supported as an import or interoperability path, but it MUST NOT be a hidden
runtime, storage, appearance, plugin, or workflow dependency.

**Acceptance criteria:**

- A clean environment without Obsidian can complete setup, reading, writing,
  source analysis, Topic synthesis, Works drafting, Human Review, comments,
  Connections, Search, Attention, checkpoint, and recovery journeys.
- The manual workflow remains complete when Zotero and external agents are
  absent. Dialogue and Critique remain available as optional extensions when
  the researcher chooses to use them.
- Scholium does not require an Obsidian vault, plugin, theme, URI handler, or
  configuration directory for its core behavior.
- Help, onboarding, prompts, and error recovery do not instruct the researcher
  to install or open Obsidian for a core Scholium task.
- Existing Obsidian Markdown can be imported or opened where supported, but
  failure or absence of Obsidian does not block the Scholium workflow.
- Zotero and external agents remain explicit, bounded integrations rather than
  evidence that Obsidian is required.

**Authority:** Product Guide section 2.1 and this PRD section 4.3; Design
Handbook section 2.
**Status:** Target; standalone clean-environment acceptance is not yet
separately recorded.

## 8. User experience and interface requirements

The Design Handbook remains the detailed interface authority. The requirements
below define the PRD-level contract that every feature must satisfy.

### PRD-UX-001 — Document-first window

The research document MUST remain the largest stable region of the main
window. Navigation, Properties, Connections, diagnostics, Zotero context,
Dialogue, Critique, and recovery controls MUST remain subordinate to reading
and writing.

At constrained widths, the inspector or secondary navigation MUST yield before
the document becomes unusable.

### PRD-UX-002 — Stable information architecture

The main hierarchy MUST distinguish:

1. navigation sidebar for scope, vault, search, Attention, hierarchy, and
   filters;
2. a content list when needed;
3. document detail for header, Properties, reader/editor, and local commands;
4. a trailing research inspector for contextual Connections, Zotero identity,
   Attention, and source-located diagnostics.

The product MUST use native windows, split views, inspectors, toolbars, menus,
sheets, alerts, controls, focus, and file panels where they provide the
required behavior.

### PRD-UX-003 — Exact lifecycle language

The following meanings and labels MUST remain stable:

- Edited, Saving, Saved, Save Failed, Conflict, Refreshing, Derived State
  Stale, Refresh Failed, and Fully Up to Date;
- Keep Editing, Retry Save, Compare Changes, Reload from Disk, Return to
  Editing, and Retry Refresh;
- Create Dialogue…, Copy Instructions for Agent, Edit Dialogue Template…, and
  Cancel;
- Review, Continue Review, Qualified, Unqualified, Complete Review, Save as
  Draft, and Cancel;
- Request Critique, Overall Critique, Specific Comments, Both, and Edit Critique
  Template…;
- Research Guidance, Prompt Templates, Skills, Reveal Skills Folder, and Reset
  to Scholium Default;
- Create Checkpoint…, Restore from Checkpoint…, and Reveal Checkpoints in
  Finder.

A capability MUST be omitted when unavailable rather than renamed to imply a
different action.

### PRD-UX-004 — Command parity and recovery

Core toolbar actions MUST have menu routes. Hover, drag, color, motion,
secondary click, and custom gestures MUST NOT be the only route to a core
task. Every consequential action MUST communicate target, consequence,
provenance, and recovery where applicable.

### PRD-UX-005 — Accessibility and adaptation

The product MUST support and test:

- Light, Dark, System, Increase Contrast, Reduce Transparency, and Reduce
  Motion;
- at least 200% document scaling without clipping ordinary prose;
- VoiceOver landmarks, headings, labels, values, source anchors, validation,
  and named actions;
- Full Keyboard Access for setup, navigation, search, reading, editing,
  Review, Dialogue, Critique, checkpoint restore, conflicts, and settings;
- Voice Control with speakable control names;
- mixed Chinese/Latin text, marked-text composition, punctuation, selection,
  and source ranges; and
- accessible list equivalents for graph and Canvas surfaces.

Important state MUST be communicated through at least two suitable channels.
Color or spatial position alone is insufficient.

The Beta and 1.0 accessibility pass threshold is explicit: 100% of the core
academic workflow MUST be operable through Full Keyboard Access and VoiceOver,
with no mouse-only or color-only required action. This includes setup, opening
and editing notes, Human Review, comments, Dialogue presentation, Search,
Connections, checkpoint restore, conflict recovery, and Trash/restore. Light
and Dark appearance, Increase Contrast, Reduce Transparency, Reduce Motion,
and 100%, 150%, and 200% document scaling MUST preserve usable layout. Mixed
English, Simplified Chinese, Traditional Chinese, Greek, Latin, and Unicode
content MUST remain editable, searchable, renderable, and accessible. There
MUST be zero unresolved critical or high-severity accessibility defects at
these stages; a proposed medium-severity ceiling is five and remains subject
to release-owner confirmation. Experimental 0.1 records this threshold as a
target and does not claim to have passed it.

### PRD-UX-006 — Empty, loading, unavailable, malformed, and error states

Every user-facing capability MUST specify empty, loading, unavailable,
malformed, conflict, error, cancellation, and successful states where
applicable. A malformed note remains readable and exposes a repair path.
Unaffected content remains usable during scoped derived failures.

### 8.1 UX requirement status

| Requirement | Detailed authority | Current status |
| --- | --- | --- |
| PRD-UX-001 | Design Handbook sections 3.1 and 4.2 | Partial; the document-first structure and automated wide/medium/compact behavior pass, while manual visual and adaptation acceptance remains open. |
| PRD-UX-002 | Design Handbook sections 4.1–4.2 and 4.7 | Reachable; shared multiwindow state is implemented, while sustained interactive acceptance remains open. |
| PRD-UX-003 | Design Handbook section 10 | Target; exact state/action alignment requires continued UI audit. |
| PRD-UX-004 | Design Handbook sections 6 and 10 | Target; command, focus, cancellation, and recovery coverage remains part of acceptance. |
| PRD-UX-005 | Design Handbook section 8 and decision record | Partial; manual accessibility and adaptation verification remains incomplete. |
| PRD-UX-006 | Design Handbook section 9 | Target; each material surface must document and verify its adjacent states. |

## 9. Cross-cutting quality requirements

### 9.1 Trust and safety

Scholium-authored writes and restore operations MUST go through the
conflict-aware repository path. The implementation MUST preserve exact source,
validate paths and revisions, create pre-write snapshots, perform atomic
writes, verify readback, and retain recovery paths on failure.

Fingerprints identify revisions and support conflict detection, Review binding,
checkpoint comparison, and restore integrity. They MUST NOT be represented as
permission tokens.

### 9.2 Provenance and semantic separation

The product MUST keep these distinctions visible:

- source material versus researcher writing;
- authoritative source versus derived diagnostic;
- researcher comment versus agent reply;
- Human Review versus Critique;
- Dialogue record versus transient agent-transport instructions and document
  version;
- editor Undo versus checkpoint restore;
- explicit relation versus neutral or inferred connection; and
- agent origin or last modifier versus qualification or current fingerprint.

Dialogue records the scholarly exchange: researcher Comments, agent Responses,
follow-up Comments, follow-up Responses, simple participant attribution, and
the eventual researcher decision in the note. Technical prompts, hidden
instructions, model parameters, token counts, and paragraph-level AI lineage
are not required research records.

No derived view may silently write a philosophical judgment into a research
note.

### 9.3 Local privacy

Core reading, editing, review, search, Connections, Canvas, checkpoints, and
recovery workflows MUST work without transmitting research content. Any
external access MUST be contextual, bounded, visible, and explained.

### 9.4 Concurrency and recovery

The product MUST remain safe when vault files change through Scholium, agents,
Finder, sync tools, Obsidian, or other editors. It MUST not silently overwrite
dirty local work or claim recovery for external work that was never
checkpointed.

Trash retains recoverable note-specific records. Permanent deletion is a
stronger operation: it purges the note, associated Dialogue, comments,
Critique/review records, and every checkpoint copy or invalidates a checkpoint
that cannot be scrubbed safely.

### 9.5 Performance and scale

The product MUST maintain usable reading and editing for long Markdown notes,
large vaults, mixed-script text, and search workloads represented by the
fixture and benchmark suites. Performance acceptance MUST identify the build,
fixture root, state, sample set, measurement method, and retained artifact.

The initial named reference machine is Reference Machine R1: the researcher's
MacBook, recorded by exact model, Apple chip, memory, storage/free-space
condition, macOS version, and release-build state at benchmark freeze. R1 is
run without a debugger or heavy competing workload. The primary fixture is the
frozen Reference Dissertation Fixture RDF-1, containing approximately 500
Analyses, 250 Topics, 100 Works, 3,000 Dialogue entries, 10,000 Comments,
50,000 semantic links, 100 checkpoints, and mixed English, Simplified Chinese,
and Traditional Chinese text. Exact latency and resource thresholds remain
TBD until measured and approved against R1/RDF-1.

R1 and RDF-1 are versioned and immutable after freeze. A replacement machine
or materially larger workload receives a new identifier such as R2 or RDF-2;
historical baselines are not rewritten.

The existence of a test name or a historical benchmark result is not by itself
release evidence.

### 9.6 Platform and implementation boundaries

The target platform is macOS 26 or later with Swift 6. The current editor
implementation may use CodeMirror 6 and sanitized WKWebView with a native
fallback, but implementation choices MUST satisfy source fidelity, focus,
selection, keyboard, accessibility, composition, and large-document
requirements.

## 10. Primary user journeys

Each journey is a product acceptance slice. A journey passes only when the
happy path and relevant empty, loading, error, conflict, accessibility, and
recovery states are covered.

| ID | Journey | Required outcome |
| --- | --- | --- |
| J-001 | Create or open a Triptych | Researcher selects three roots, sees peer vaults, and opens a usable document-first window. |
| J-002 | Read and edit a note | Researcher reads, switches modes, edits exact source, and receives authoritative Saved or recoverable failure state. |
| J-003 | Configure Properties | Researcher configures vault-wide visible fields without corrupting unrelated YAML or protected identity. |
| J-004 | Review an Analysis or Topic | Researcher adds comments, completes or drafts Human Review, and sees fingerprint-bound state. |
| J-005 | Use an Unqualified Analysis | Researcher can continue work while explicit reliance produces a non-blocking source-anchored Attention. |
| J-006 | Prepare optional agent work | When the researcher chooses an agent, she selects notes, verifies scholarly and consequential context without seeing prompt mechanics, and receives a Before Agent Work checkpoint before copying. |
| J-007 | Reconcile an external edit | Clean notes refresh; dirty notes preserve the local buffer and present Compare Changes, Reload from Disk, and Keep Editing. |
| J-008 | Request and inspect Critique | Researcher requests Overall Critique, Specific Comments, or Both and can navigate findings to the target Work. |
| J-009 | Restore a checkpoint | Researcher compares and selectively or completely restores a self-contained checkpoint without confusing restore with Undo. |
| J-010 | Search and trace Connections | Researcher searches the correct scope, sees snippets and source locations, and does not receive inferred philosophical evidence. |
| J-011 | Use optional Zotero context | When Zotero is available and selected, the researcher sees only bounded relevant metadata and can open the identified item in Zotero; its absence does not block the workflow. |
| J-012 | Complete the workflow accessibly | Researcher completes primary journeys with keyboard and assistive technology paths under supported adaptations. |
| J-013 | Complete the manual workflow without optional integrations | Researcher completes the core academic workflow in a clean environment where Obsidian, Zotero, and external agents are absent; Dialogue and Critique remain optional extensions. |
| J-014 | Manage research guidance | Researcher edits prompt templates and correctly placed Triptych-local skills in one Settings pane without exposing either source in the scholarly workflow. |

## 11. Success measures and product outcomes

The following measures convert product principles into release evidence. They
are proposed measures, not current telemetry or user-study findings.

| ID | Measure | Proposed acceptance target | Evidence |
| --- | --- | --- | --- |
| M-001 | Unexpected source mutation | Zero unexpected bytes changed outside the explicitly edited range in fidelity fixtures. | Source-fidelity test matrix and readback comparison. |
| M-002 | Dirty-buffer overwrite | Zero accepted writes that overwrite a dirty local buffer after an external revision change. | Conflict and repository tests plus QA journey J-007. |
| M-003 | Checkpoint boundary | 100% of accepted Dialogue-copy journeys create Before Agent Work before copying. | Dialogue tests and QA evidence for J-006. |
| M-004 | Derived-status honesty | 100% of user-visible diagnostics identify their derived scope and source anchor or explicitly state that no anchor exists. | Attention, Connections, Critique, and UI review. |
| M-005 | Accessibility path coverage | Every primary journey has a tested keyboard path; all required assistive-technology gaps are explicitly dispositioned before release. | UI automation, manual accessibility audit, and retained artifacts. |
| M-006 | Recovery correctness | Selective and complete restore preserve source integrity and expose conflicts rather than silently replacing newer work. | Checkpoint fixtures and QA journey J-009. |
| M-007 | Zotero boundary | Zero attachment enumeration, download, online API, database access, or Zotero write requests from supported Zotero workflows. | Boundary tests and network/access audit. |
| M-008 | Researcher task success | Target and baseline for setup, review, agent preparation, conflict recovery, and restore. | TBD usability protocol and researcher tasks. |
| M-009 | Performance | Measured launch, note switching, reading, search, indexing, and restore thresholds on Reference Machine R1 and RDF-1. | Benchmark protocol and retained R1/RDF-1 artifacts; exact thresholds TBD until baseline approval. |
| M-010 | Obsidian independence | 100% of core academic journey acceptance in a clean environment without Obsidian installed. | Isolated Scholium app run and J-013 workflow checklist. |

M-008 and M-009 require explicit targets before a release decision. The PRD
does not invent a usability or performance threshold that the repository has
not yet approved.

## 12. Acceptance and verification model

### 12.1 Evidence hierarchy

Use evidence in this order:

1. current source and construction call sites for reachable behavior;
2. executable unit, integration, and UI tests;
3. isolated QA runs on disposable fixtures;
4. current Implementation Status entries and retained artifacts;
5. Product Guide and Design Handbook target rules;
6. historical screenshots, test names, or remembered behavior only as context.

Target documentation is not implementation evidence.

### 12.2 Required verification

Before release acceptance, the team MUST:

- run the repository verification script from the Scholium package root;
- run focused tests for every changed behavior;
- use disposable copies of the canonical TestVaults or generated temporary
  vaults, never real research vaults;
- exercise primary journeys J-001 through J-013 as applicable;
- cover empty, loading, malformed, unavailable, conflict, and recovery states;
- test light/dark appearance, Increase Contrast, Reduce Transparency, Reduce
  Motion, large text, keyboard access, VoiceOver, mixed-script input, and
  minimum usable window sizes;
- retain command, build configuration, platform/SDK, fixture root, outcome,
  and result bundle or screenshot for material UI work; and
- record all unresolved behavior rather than converting it into a passing
  assumption.

### 12.3 Current evidence snapshot

The current Implementation Status reports:

- full repository verification passing on 2026-07-14, including 277 Swift
  tests across 30 suites, deterministic editor-bundle verification, the
  indexed-search and cold-render performance gates, and Debug and Release
  builds;
- the canonical isolated one-process XCUITest journey passing against
  disposable TestVaults;
- the focused wide/medium/compact responsive journey passing at 1380, 1080,
  and 900 points, while lifecycle, accessibility, and interruption-recovery
  acceptance remains incomplete; and
- the source-first GitHub beta policy approved, while no package, checksum,
  external-install smoke test, Developer ID signature, or notarization result
  has yet been recorded.

These are current evidence entries, not a claim that every PRD journey or
release gate is complete.

## 13. Migration and delivery plan

The delivery sequence below preserves the Product Guide's migration boundary
while adding an exit gate to each phase.

| Phase | Scope | Exit gate |
| --- | --- | --- |
| P0 | Approve this PRD, set release boundary, assign owners, and resolve authority conflicts. | Approved product baseline, requirement dispositions, and named owners. |
| P1 | Remove obsolete Proposal/Revision/Research Session assumptions from product and UI documents without deleting legacy data. | No reachable retired authorization or governance UI; legacy files remain untouched. |
| P2 | Complete stable identity, exact-source autosave, external-edit conflicts, repository safety, and shared multiwindow ownership. | Fidelity, conflict, identity, and multiwindow tests pass with no dirty-buffer overwrite. |
| P3 | Complete lifecycle, import, Unclassified classification, Properties, Human Review, comments, and Note History. | Create/move/rename/delete/recovery and Review journeys pass in isolated fixtures. |
| P4 | Complete researcher-centred Dialogue, Settings-only prompt-template and file-backed skill management, optional pre-agent checkpoints, CLI replies, Critique association, prompt transport, and source-located findings. | Dialogue, Research Guidance, optional agent reply, Critique, provenance, skill-discovery, and fingerprint journeys pass. |
| P5 | Complete self-contained checkpoints, comparison, selective/full restore, Finder access, and permanent-deletion scrubbing of app-owned records and checkpoint copies. | Recovery and purge journeys pass with newer external changes and conflict paths. |
| P6 | Complete Search, Attention, canonical Connections, and bounded Zotero integration. Keep Canvas deferred until the core document workflow is stable. | Search, relationship, Attention, and Zotero boundary gates pass; no Canvas surface is required. |
| P7 | Complete visual, accessibility, CJK, performance, multiwindow, conflict, recovery, and release acceptance. | All release gates pass or have explicit documented waivers. |

The current status identifies the following concrete remaining work:

1. complete deterministic isolated UI execution for lifecycle, conflicts,
   multiwindow sharing, settings, Critique navigation, and recovery; the
   Critique journey is implemented and has supplementary disposable-workspace
   evidence, but its XCUITest runner has not initialized successfully;
2. complete manual accessibility and adaptation acceptance.

## 14. Release quality gates

The release owner is Imna. A gate applies according to the release stage; a
future capability may be deferred without becoming a hidden dependency.

| Gate | Required condition |
| --- | --- |
| G1 — Functional completeness | All P0 requirements for the declared stage have an owner, status, source authority, and acceptance evidence or documented waiver. |
| G2 — Manual workflow independence | The researcher can complete the declared core academic workflow without Obsidian, Zotero, an external agent, or manual filesystem manipulation. |
| G3 — Source and data integrity | Exact-source tests pass, including malformed YAML, unknown fields, newline/BOM behavior, targeted edits, readback, atomic failure paths, and app-owned record separation. |
| G4 — Recovery and deletion | Conflicts, checkpoints, selective/full restore, Trash recovery, permanent-deletion purge, external rename, and derived-state failures are verified on disposable fixtures. |
| G5 — Scholarly transparency | Dialogue preserves concise Comments and Responses and the researcher's eventual decision without requiring technical prompt logs or automatic philosophical judgments. |
| G6 — Accessibility and internationalization | The Beta/1.0 pass threshold in PRD-UX-005 is satisfied: 100% keyboard and VoiceOver core workflow coverage, visual adaptations, mixed-script support, and zero unresolved critical/high defects. |
| G7 — Performance | Approved measurements on Reference Machine R1 and frozen RDF-1 meet the thresholds declared for the stage, with retained artifacts. |
| G8 — Documentation consistency | PRD, Product Guide, Design Handbook, README, and Implementation Status do not silently contradict one another; target requirements are not presented as current evidence. |
| G9 — Distribution integrity | Every external binary is built from a clean tagged commit, is paired with exact corresponding GPL source and applicable third-party licenses, contains no private state or research content, states its signing/notarization and architecture accurately, and has a published SHA-256 checksum plus an exact-artifact clean-account smoke test. |

For 0.1 Experimental, G1, G2, G3, G4, G5, G8, and—whenever an external
artifact is distributed—G9 are applicable release
conditions. G6 and G7 require a documented baseline and known gaps, but 0.1
MUST NOT be presented as having passed the Beta/1.0 accessibility or
performance thresholds. Beta requires all applicable gates, and 1.0 requires
all gates plus the complete daily-workflow definition in Section 5.3.

## 15. Risks, open decisions, and assumptions

### 15.1 Product and release decisions

| ID | Item | Type | Current disposition |
| --- | --- | --- | --- |
| R-001 | No formal user research or quantitative usability baseline is recorded in the source set. | Risk | Create a bounded researcher-task protocol before setting M-008. |
| R-002 | The release boundary and ownership needed explicit confirmation. | Decision | Resolved for the current baseline: 0.1 Experimental; release owner Imna; scope and gates are defined in Sections 5.3 and 14. |
| R-003 | Exact launch and performance thresholds are not yet measured. | Measurement | Use Reference Machine R1 and frozen RDF-1; set numeric thresholds only after the baseline protocol is run. |
| R-004 | The external distribution model needed a feasible no-fee path. | Decision | Use the source-first `v0.1.0-beta.1` policy in `BETA_RELEASE.md`: exact GPL-tagged source plus an optional ad-hoc-signed app-only ZIP and checksum. State the Gatekeeper limitation explicitly. Developer ID signing and notarization remain optional future improvements. |

### 15.2 Implementation and acceptance risks

| ID | Item | Type | Current disposition |
| --- | --- | --- | --- |
| R-005 | Shared multiwindow ownership is implemented, but sustained interactive multiwindow acceptance is incomplete. | Acceptance risk | Exercise independent sessions, shared commits, dirty conflicts, restoration, and focused-window routing in the canonical QA environment. |
| R-006 | External rename migration is implemented, including ambiguity confirmation, but its complete interactive matrix is not yet accepted. | Acceptance risk | Cover clean, dirty, moved, ambiguous, and multiwindow rename journeys in disposable fixtures. |
| R-007 | Permanent deletion must remove app-owned history, associated Critique content, and every recoverable checkpoint copy of the deleted note. | Acceptance risk | Coordinated Work/current-Critique deletion, cross-store rollback, restart recovery, and checkpoint invalidation are implemented on disposable fixtures. Complete the lifecycle and recovery UI acceptance journey before release acceptance. |
| R-008 | Manual accessibility, clean-account, and several interaction journeys remain incomplete; automated compact-width behavior now passes. | Acceptance risk | Extend the remaining isolated journeys, complete manual adaptation and assistive-technology acceptance, and record retained artifacts. |
| R-009 | Legacy role and schema decoders remain for compatibility. | Resolved migration evidence | Immutable fixtures cover every retained role spelling, property alias, sparse window/Search state, v0 Triptych identity, and Canvas migration record. Keep these bounded read paths while compatible persisted data remains supported. |

### 15.3 Unresolved interface questions

The Design Handbook identifies these as future or unresolved and they MUST NOT
be presented as completed behavior:

- sustained interactive acceptance of restored multiwindow sessions and
  native window grouping;
- sustained VoiceOver, Full Keyboard Access, Voice Control, contrast, scaling,
  and localization verification across CodeMirror/WKWebView;
- whether and how to reintroduce an accessible Canvas after the core document
  workflow is stable;
- final Quick Open presentation; and
- compact multi-note Dialogue presentation in Note History.

## 16. Requirement traceability

The following matrix provides the top-level mapping. Requirement-specific
authority and status appear in Section 7.

| Requirement area | Product Guide | Design Handbook | Implementation Status | Primary journeys |
| --- | --- | --- | --- | --- |
| Triptych and vaults | §§1, 3–4 | §§1, 4.1–4.2 | Reachable multi-Triptych and shared-store evidence; sustained UI acceptance open | J-001 |
| Exact Markdown and YAML | §5.1–5.2 | §§3.3, 4.4, 9–10 | Reachable fidelity and repository evidence | J-002, J-003 |
| Identity and lifecycle | §§5.3, 6 | §§3.3, 4.6, 9–10 | Reachable lifecycle and rename migration; UI acceptance open | J-003, J-007, J-009 |
| Human Review and comments | §7 | §§4.8, 8, 10 | Reachable; full accessibility/clean-account coverage open | J-004, J-005 |
| Dialogue and CLI | §8 | §§3.5, 4.8, 10 | Reachable concise chronological record with focused persistence UI evidence; broader accessibility acceptance open | J-006, J-007 |
| Research Guidance, prompt templates, and skills | §8.3 | §§4.8–4.9, 10; D-029 | Reachable; Settings-only templates, bounded file-backed Skills, workflow concealment, and focused UI evidence implemented | J-006, J-008, J-014 |
| Critique | §11 | §§4.8, 9–10 | Reachable with source-located findings; deterministic XCUITest execution pending | J-008 |
| Connections | §12 | §§4.7, 8–9 | Canonical graph reachable; Canvas is explicitly deferred and absent from the stable UI | J-010, J-012 |
| Search and Attention | §13 | §§4.3, 4.5, 4.7, 9; D-030 | Unified contract, Find, outline, saved-search management, and per-window Recent Notes reachable | J-005, J-010 |
| Checkpoints and recovery | §14 | §§3.3, 4.8, 9–10 | Reachable; full journey acceptance open | J-006, J-007, J-009 |
| Zotero | §15 | §§4.7, 4.9 | Bounded localhost integration reachable | J-011 |
| Standalone academic workflow | §2.1 | §2 | Not separately accepted; add clean-environment coverage | J-013 |
| Accessibility and visual language | — | §§3, 5–10, 13 | Manual acceptance incomplete; Beta/1.0 pass threshold defined in PRD-UX-005 | J-002, J-004, J-006–J-014 |

## 17. Change-control protocol

A proposed product change MUST identify:

1. the affected requirement IDs and user journeys;
2. whether it changes product behavior, interface behavior, implementation
   status, or only documentation;
3. the source authority that must change;
4. affected trust, provenance, exact-source, accessibility, and recovery
   invariants;
5. migration and compatibility impact on existing vault bytes and app-owned
   records;
6. acceptance tests and retained evidence; and
7. any newly introduced non-goal, risk, or open decision.

Changes to target product semantics belong in Product Guide and this PRD.
Changes to exact action labels, interface states, accessibility, or visual
decisions belong in Design Handbook and this PRD. Changes to current evidence
belong in Implementation Status. Existing legacy files and vault bytes MUST
not be migrated merely because a document changed.

## Appendix A. Glossary

| Term | Definition |
| --- | --- |
| Analysis | A reusable source analysis stored in Analyses. |
| Attention | A derived, dismissible warning or recoverable research issue. |
| Canvas | An optional view-only spatial presentation of notes and Connections. |
| Checkpoint | A self-contained, fingerprint-bound snapshot of the complete Triptych. |
| Critique | An attributed agent assessment of one Work, kept separate from the Work. |
| Dialogue | A concise scholarly record of researcher Comments and agent Responses, with optional transient copyable instructions for an external agent. |
| Human Review | Fingerprint-bound researcher review of an Analysis or Topic, including qualification. |
| Prompt template | Triptych-local technical configuration for an existing workflow, visible and editable only in Research Guidance and absent from the permanent scholarly Dialogue record. |
| Properties | The human-facing presentation of role-aware frontmatter. |
| Research Guidance | The Settings pane containing distinct Prompt Templates and Skills collections for inspecting, editing, validating, and managing supported research guidance. |
| Skill | Reusable editable agent guidance. A Triptych-local user skill is manageable only as `.scholium/skills/<skill-id>/SKILL.md`; Scholium does not thereby certify or execute it. |
| Topic | Reusable topic-centred knowledge stored in Topics. |
| Triptych | One configured research workspace containing Analyses, Topics, and Works. |
| Unclassified | Temporary staging for imported Markdown before role assignment. |
| Work | Researcher-governed writing or related material stored in Works. |

## Appendix B. Current source set

- Product Guide, canonicalized 2026-07-14.
- Design Handbook, last reviewed 2026-07-14.
- Implementation Status, audited 2026-07-12 with verification entries dated
  2026-07-13.
- Scholium README and repository AGENTS.md.
- Swift package manifest, which sets macOS 26 as the package platform baseline.

This appendix identifies the source set used to create this PRD. It does not
replace current source, tests, or the explicit authority hierarchy in Section
0.
