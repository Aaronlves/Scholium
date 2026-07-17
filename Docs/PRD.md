# Scholium Product Requirements Document

**Status:** Draft consolidated requirements baseline
**Product:** Scholium for macOS and its agent-facing CLI
**Platform baseline:** macOS 26 or later
**Document date:** 2026-07-17
**Product owner:** Imna
**Release owner:** Imna
**Current release:** 0.1 Experimental
**Release identifier:** 0.1

## 0. Document purpose and authority

This document consolidates the product requirements distributed across the
Product Guide and Design Handbook. It adds release-oriented requirements,
acceptance criteria, gates, risks, open decisions, and traceability.

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

When this PRD conflicts with an authority, resolve the conflict explicitly; do
not treat a target requirement as current behavior.

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
Zotero database. For Beta, an external agent MAY use a separately bounded,
local Zotero MCP integration under a protected Scholium System Skill. This
does not change the built-in app's read-only boundary. Agent-side imports, when
explicitly requested, remain guarded MCP operations rather than app metadata
editing or direct database access.

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
- a proprietary backup-export format;
- complete arbitrary Obsidian-theme compatibility; or
- bundled general instructions that purport to teach researchers how to
  conduct philosophy. Official Workflow Skills are philosophy-facing,
  truth-pursuing, fidelity-caring, and knowledge-base-constructing methods for
  agents. Their technical operations remain subordinate to scholarly outcomes,
  and they do not replace the researcher's methodological judgment, certify
  truth, or make Scholium an authority over philosophical quality.

The following core agent capabilities are intentionally deferred beyond 0.1
and are required for Beta:

- protected System Skills and complete official Workflow Skill packages;
- bounded catalog and package retrieval with function-aware selective assembly
  and isolated Manuscript phases;
- immutable Dialogue `responseContract` snapshots and agent-facing exposure;
  and
- the protected Zotero MCP adapter with a supported local transport.

The following additional capabilities are intentionally deferred beyond 0.1
rather than permanently rejected:

- document, project, HTML, PDF, or DOCX export;
- additional discipline-specific or researcher-contributed workflows beyond
  the Beta baseline; and
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
7. canonical Connections, Search, and Attention;
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
waivers. Mode-aware System and Workflow packages, selective assembly, the
Dialogue response contract, and the protected Zotero MCP adapter are not 0.1
dependencies, but they are required Beta capabilities because agent-assisted
research is central to the mature product. The bounded file-backed management
requirement below does not make skills necessary for the manual academic
workflow.

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

Each requirement below has target behavior, acceptance criteria, and source
authority. Current reachability and verification are maintained once in
[Implementation Status](IMPLEMENTATION_STATUS.md), not repeated in every
requirement.

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

#### PRD-TRI-002 — Triptych windows

**Requirement:** One window MUST belong to one complete Triptych. Multiple
Triptychs MAY be open simultaneously in separate windows or grouped as native
macOS window tabs. One native tab MUST be one complete window scene and session
with one selected document, document mode, History, inspector, scroll
location, Search state, and presentation router while shared services remain
coherent. Scholium MUST NOT maintain custom document tabs.

**Acceptance criteria:**

- File → New Triptych… opens setup for three new locations.
- File → Open Triptych opens a registered Triptych in its own window.
- File → New Window opens another independent window for the focused Triptych.
- Ordinary note selection replaces the focused session's document.
- Switching the Library among Analyses, Topics, and Works retains the focused
  session's document and changes only the browsed hierarchy and **This Vault**
  Search scope.
- Open in New Tab creates another window scene and groups it explicitly with
  the source window, including across different Triptychs.
- Standard Window-menu tab commands and `Command-W` remain functional.
- Native tab title, tooltip, and edited indicator follow note identity,
  Triptych, path disambiguation, and the active editor session.
- Closing flushes only the focused native tab and is blocked on save failure.
- Commands route to the focused window and document.
- Shared repositories, indexes, watchers, identity registries, and graph state
  do not become divergent per-window copies.

**Authority:** Product Guide section 3.2; Design Handbook sections 4.1–4.5 and
decisions D-020, D-036, and D-041.

#### PRD-TRI-003 — Works organization without project management

**Requirement:** Works MUST remain an ordinary researcher-controlled Markdown
hierarchy. Scholium MAY display folders and folder context, but MUST NOT
register, select, validate, assign, or manage projects.

**Acceptance criteria:**

- A Works folder can represent a paper, chapter, book, or any
  other researcher-chosen grouping.
- No project selector appears below Triptych navigation.
- No project completeness, readiness, or membership warning is generated.
- No folder-specific schema, mandatory template, or one-note-per-concept rule
  is imposed.

**Authority:** Product Guide sections 3.2 and 4; Design Handbook decision D-015.

#### PRD-TRI-004 — Onboarding and management

**Requirement:** First launch MUST use a narrow, multi-step, no-scroll flow to
select Analyses, Topics, and Works locations, then request the bounded
authorization beside Works at the point of use. Each step MUST present one
decision with concise copy. Longer storage and optional-agent explanations MUST
remain available outside the primary setup flow. Later management MUST support
complete registered Triptychs and three-root editing without requiring a
project setup.

**Acceptance criteria:**

- First-run setup reaches usable folders without requiring a feature tour.
- Setup completion performs the sole application-driven expansion to the
  preferred 1180 × 760 configured workspace with a 760 × 520 minimum;
  Reduce Motion makes it immediate.
- Configured windows launch or restore at the normal workspace frame. Note
  open, replace, and close preserve frame and position exactly.
- First-run setup has no scrolling page and never presents all folder choices
  at once.
- Manage Triptychs… lists complete registered Triptychs.
- Standard Open panels are used for vault and import selection.
- Errors identify the affected operation and offer recovery actions.

**Authority:** Product Guide section 16; Design Handbook sections 4.9 and 10.5
and decision D-036.

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

#### PRD-TRI-006 — Stable no-note workspace and session migration

**Requirement:** A configured window MUST use one stable
`NavigationSplitView` root. Its detail MUST display either the selected
document or the fixed decorative Scholium artwork. The native Show/Hide Sidebar
item MUST change only Library visibility and MUST remain paired with the
standard View-menu command. Scholium MUST NOT add a separate Collapse Note
function.

**Acceptance criteria:**

- The no-note detail contains only the authored 16:10 light/dark artwork: no
  Home title, instructions, buttons, document controls, or Research Strip.
- The artwork is decorative and excluded from VoiceOver; Library remains the
  actionable interface.
- Both variants preserve the approved semantic palette, use a centered
  proportional crop, and have recorded generation and asset provenance.
- Opening, replacing, or closing a document changes no window
  frame coordinate.
- Legacy snapshots restore the former active tab or otherwise the last valid
  open-tab entry as the single selected document. Legacy tab/history fields are
  decode-only and disappear on the next save; no legacy snapshot creates
  multiple native tabs.

**Authority:** Product Guide sections 3.2 and 16; Design Handbook sections 4.2,
4.5, and 10.5 and decisions D-036 and D-047.

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

#### PRD-DOC-002 — Document modes

**Requirement:** Read, Live Preview, and Source MUST be modes of one document,
not separate files or ordinary tabs.

**Acceptance criteria:**

- Read provides selectable semantic prose and source navigation.
- Live Preview edits the exact Markdown body through a visual projection,
  matches Read's prose and construct presentation wherever its editable
  projection permits, hides YAML frontmatter, and does not expose a line-
  number gutter.
- Source exposes complete Markdown and YAML and MAY show line numbers.
- Live Preview and Source initially place the first editable line below the
  floating Metadata and Properties surface. That clearance scrolls away so
  later text can travel beneath the surface.
- Mode transitions preserve focus, selection, scroll, and nearest semantic
  location where possible.
- Source and editor behavior supports undo, Find, keyboard access, marked-text
  composition, and accessibility.

**Authority:** Product Guide section 5.1; Design Handbook sections 4.4, 5,
8.2, and 10 and decision D-042.

#### PRD-DOC-003 — Common note capabilities

**Requirement:** Analysis, Topic, and ordinary Work notes MUST support reading,
editing, comments, Connections, role-aware Properties, search, Attention, Note
History, and safe file lifecycle operations.

**Acceptance criteria:**

- Create, duplicate, import, rename, move, Set Aside, Trash, Put Back, Reveal
  in Finder, and permanent deletion are available where applicable.
- Autosave does not require an ordinary Save button.
- App writes are atomic and conflict-aware.
- External edits are reconciled without silently replacing dirty buffers.

**Authority:** Product Guide sections 5 and 6.

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

**Authority:** Product Guide section 5.3.

#### PRD-DOC-005 — Properties and Research Status

**Requirement:** Each of Analyses, Topics, and Works MUST support a fixed
starting profile that the researcher can configure by vault. Configuration MUST
control visible fields, order, disclosure, and human-editable allowlist
without allowing protected identity and automatic fields to be edited through
structured Properties. Scholium MUST support a minimal nested `research_unit`
mapping, presented as **Research Status**, for declaring the epistemic scope
within which a note's claims apply.

The default mapping MUST contain only a required non-empty `scope` and an
optional non-empty `limitations` list. It MUST NOT duplicate note role, source
identity, links, backlinks, relation counts, coverage percentages, confidence,
reading-pass state, or timestamps.

Creation and modification time MUST be app-owned History data. Researchers and
agents MUST NOT be required or instructed to create, infer, or maintain
frontmatter timestamps. Existing timestamp YAML remains exact preserved source
for compatibility but is not part of the target default profiles.

**Acceptance criteria:**

- No folder-level or note-level Properties layouts are required.
- Protected fields remain available in Source mode for exact YAML editing.
- Absent, empty, invalid, derived, and not-applicable values are distinct.
- Legacy YAML remains readable and is not bulk-rewritten automatically.
- New Analysis creation offers exact choices **Declare Now** and **Not Yet**.
  Declare Now requires non-empty Scope and may include Limitations. Not Yet
  writes no `research_unit` mapping and no sentinel value.
- An Analysis with no mapping remains editable and available for Comments,
  Dialogue, Develop, and Review drafts. **Complete Review** remains unavailable
  until Research Status is declared and the panel offers **Declare Research
  Status…**.
- Properties presents an absent mapping as **Not Yet**, not inferred or
  malformed scope. Existing notes receive no migration or automatic YAML
  rewrite.
- An agent MAY declare Research Status through an ordinary authorized exact-
  source edit subject to existing fingerprint, conflict, and source-fidelity
  rules; no special mutation path is created.
- Topics and Works may declare Research Units without making YAML mandatory;
  ordinary reading, editing, or saving never injects Topic YAML solely for this
  purpose.
- Research Status remains inside the existing Properties region and creates no
  new document type, panel, workflow state, or project object.
- Dialogue expresses its Research Unit through app-owned selected-note,
  selection, Comment, and scope records rather than Markdown frontmatter.
- Links and Connections provide related targets and reverse navigation; the
  Research Unit does not store derived relation or coverage data.
- Project Relevance, when requested, remains contextual report content rather
  than a universal Analysis property.
- An optional `debate_importance` whole-number rating from 0–10 is valid only
  together with `debate_importance_scope`. It has no pass grade, remains
  explicitly scoped, and is never inferred from project relevance, quality,
  truth, prestige, citation count, or the source's self-positioning.
- Debate Importance sorting is numeric, high to low, and available only when
  the Library is filtered to one exact `debate_importance_scope`. Unrated
  matching Analyses sort after rated ones; Scholium provides no cross-debate
  ranking. A bounded Research Synthesis may recalibrate a same-scope corpus.
- App-owned History supplies creation and modification time even when no
  corresponding YAML timestamp exists.
- For a long source, the default durable workflow updates one source-level
  Analysis and its cumulative Research Unit after each bounded three-pass
  session. It creates a separate segment Analysis only by explicit researcher
  choice or for an independently durable scholarly purpose.

**Authority:** Product Guide section 5.2; Property Profiles; Design Handbook
sections 4.6, 9, and 10 and decisions D-033 and D-039.

#### PRD-DOC-006 — Set Aside, Trash, and deletion

**Requirement:** Set Aside MUST be a direct reversible action without a stored
failure or superseded label. Move to Trash MUST be recoverable until explicit
permanent deletion. Trashed and set-aside notes MUST be excluded from ordinary
research workflows according to the Product Guide.

**Acceptance criteria:**

- The actions are Set Aside, Move to Trash, and Cancel.
- Put Back returns a Set Aside or Trash note to its exact original
  vault-relative path. It MUST NOT expose a destination field, silently rename
  the note, or choose another folder; an occupied original path is a conflict.
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
- For an Analysis, Complete Review is also unavailable while Research Status
  is **Not Yet**; the same panel explains the gate and offers **Declare
  Research Status…**.
- Save as Draft preserves incomplete work without marking the fingerprint
  reviewed.
- Cancel discards unsaved sheet changes.
- Qualification can change only through Review.

**Authority:** Product Guide sections 5.2 and 7; Design Handbook sections 4.8
and 10 and decisions D-037 and D-039.

#### PRD-REV-002 — App-owned comments

**Requirement:** Researcher Comments MUST remain outside Markdown source and
MUST bind to stable identity, exact fingerprint, source range, quotation, and
context. Scholium MUST NOT store, decode, or present an unanchored Comment.
Comments MUST not insert hidden Markdown. Note-level judgment belongs to Human
Review or Critique rather than being duplicated as a Comment.

**Acceptance criteria:**

- Read and editor selections create the same comment record shape.
- Every Comment has a source anchor. A Comment can be edited,
  deleted, resolved, or reattached by the researcher.
- After edits, reattachment occurs only when quotation and context identify one
  reliable location.
- Ambiguous comments are marked Needs Reattachment.
- An agent MAY reply but MUST NOT resolve a researcher comment.
- Analysis/Topic Comments appear with Human Review in one panel; Work Comments
  appear with Critique in one panel. Both show existing Comments and show an
  inline composer only when a source anchor is present, without a Manage
  Comments doorway, whole-note Comment textbox, or second-level sheet.
- Editor Add Comment opens the role-valid panel and focuses the inline composer
  with the current source anchor.
- Shared presentation MUST NOT merge the storage or provenance of Comment,
  Human Review, and Critique records.

**Authority:** Product Guide section 7.2; Design Handbook sections 3.4, 8,
and 10 and decisions D-037 and D-043.

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

### 7.4 Dialogue and external agent work

#### PRD-DIA-001 — Dialogue function and instruction generation

**Requirement:** Dialogue MUST let the researcher select one or several notes
and provide one overall researcher Comment or instruction. It MUST generate
copyable context without communicating with an agent process or imposing
specialized task types. Using an external agent is optional; Dialogue remains
usable as a researcher-facing record even when no agent is involved. The
active template and assembled technical instructions MUST remain hidden from
the Dialogue workflow and MUST NOT permit one-run selection or editing there.
Dialogue MUST be read-only by default. A request to change the Target MUST be
promoted through the function API to Develop for an Analysis or Topic or Revise
for a Work before mutation; the frontend MUST NOT classify philosophical prose.

The generated prompt SHOULD include, as applicable:

- researcher instruction;
- selected note names, vault-relative paths, and advisory fingerprints;
- selected passages, source lines, and included comments;
- Triptych context, linked-note context, and ordinary Work metadata;
- requested destination and read-only boundary; and
- the exact function-API promotion required before the single Target may be
  changed.

**Acceptance criteria:**

- The Dialogue panel fixes the open note as Target, selects additional read-only
  Materials inside the panel, shows included Comments and consequential
  context, and provides one researcher instruction field.
- The researcher verifies the selected context rather than inspecting or
  editing the prompt template or assembled technical instructions.
- **Edit Dialogue Template…** opens **Settings → Research Guidance** at the
  active Dialogue template without discarding current Dialogue inputs.
- Pending autosaves complete before a write-capable promotion is prepared.
- A Before Agent Work checkpoint is created for promoted Dialogue, not for a
  read-only Dialogue record.
- Scholium does not transmit research automatically.

**Authority:** Product Guide section 8.1; Design Handbook sections 3.5, 4.8,
  and 10.

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
- Comment-preservation modes and response modules beyond the bounded Beta set
  in PRD-DIA-004 remain deferred until separately approved.

**Authority:** Product Guide sections 1 and 8; Design Handbook sections 3.5,
4.8, 7, and 10.

#### PRD-DIA-004 — Request-scoped scholarly response contract

**Requirement:** For Beta, the Dialogue request UI MUST provide one required
Academic Outcome and a bounded multi-selection of optional scholarly response
modules. The effective request-time choice MUST be stored as an immutable
`responseContract` on the Dialogue entry and exposed to a local responding
agent through the supported CLI. A response choice controls presentation only;
it MUST NOT expand retrieval, select a workflow, authorize a note mutation, or
weaken fidelity and uncertainty requirements.

**Acceptance criteria:**

- The initial optional modules are Critical Reflection, Remaining Questions,
  Philosophical Significance, Debate Context, and Research Directions.
- The agent receives the request-scoped snapshot rather than a later revision
  of the Triptych default profile.
- A selected module may be marked unavailable when the bounded evidence is
  insufficient; the agent does not retrieve outside scope or fabricate content
  to fill it.
- Legacy Dialogue entries without a snapshot use an explicitly labelled
  fallback and never claim request-time exactness.
- The resulting response remains one concise attributed Dialogue reply and
  does not become settled note content automatically.

**Authority:** Product Guide sections 8.1–8.2; [Skills README](../Skills/README.md)
runtime assembly and [catalog](../Skills/catalog.yaml).

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
- Research Guidance has exactly two principal collections, **Prompt Templates**
  and **Skills**. Per-Triptych **Dialogue Defaults** are a subordinate section
  under Prompt Templates and MUST NOT appear as a third peer collection.
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

#### PRD-RGD-002 — File-backed skill management

**Requirement:** **Settings → Research Guidance → Skills** MUST let the
researcher manage bundled Scholium skills and Triptych-local user skills while
keeping skills distinct from prompt templates. Scholium MUST discover a user
skill only from `.scholium/skills/<skill-id>/SKILL.md` and MUST NOT scan research
notes, arbitrary filesystem locations, `~/.codex/skills`, or another agent's
global configuration.

This requirement records the current direct-package management baseline.
PRD-RGD-003 refines bundled ownership for Beta: protected System Skills are not
duplicable or resettable as local replacements, while Workflow Skills may be
duplicated into independent Researcher Skills.

**Acceptance criteria:**

- Bundled Skills are immediately usable through Scholium defaults without
  requiring composition knowledge.
- The ordinary Skill detail shows name, plain-language purpose, relevant
  function, Built-in/Triptych ownership, structural validity, and active
  status.
- Research Guidance identifies **Bundled** and **Triptych** skills in text and
  uses the same native list-and-detail editing architecture as Prompt
  Templates without merging their semantics.
- The researcher can inspect and edit Triptych-local `SKILL.md` source,
  duplicate a permitted official package into a new independently identified
  Triptych package, rename or delete a Triptych-local skill, and use **Reveal
  Skills Folder** to open the supported location. Protected System Skills do
  not expose a duplicate action.
- A bundled Workflow Skill offers Duplicate without a disabled source editor.
  A Triptych-owned Skill offers ordinary edit and duplicate actions.
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
- Research Methods, Supplements, Practices, citation bindings, routing
  metadata, revision comparison, evolution, and Recovery appear under one
  **Advanced** disclosure. Eligible Triptych-owned Skills alone expose
  **Evolve…**.
- Missing or malformed configuration exposes **Repair…**, which opens the
  exact Advanced recovery destination without weakening validation or atomic
  replacement.

**Authority:** Product Guide sections 2.2, 3.3, and 8.3; Design Handbook
sections 4.9 and 10 and decisions D-029 and D-040.

#### PRD-RGD-003 — Function-aware skill package architecture

**Requirement:** Beta MUST ship protected Scholium System Skills, exactly five
official Scholium Workflow Skills—Development, Critique, Revision, Content
Fidelity, and Manuscript—and editable Triptych-local Researcher Skills through
one bounded package catalog. Official packages MAY contain release-pinned one-
level references and templates. Scholium MUST own package discovery, structural
validation, origin and update policy, explicit Triptych bindings, dependency
closure, current task facts and permissions, and exact resource retrieval. The
Application function coordinator MUST resolve package IDs and revisions; the
frontend and CLI MUST NOT select package IDs, parse package YAML, or scan a
global skill directory.

**Acceptance criteria:**

- System Skills are release-managed, protected, non-editable, and cannot be
  shadowed by a Triptych-local package.
- Workflow Skills are release-managed and read-only; duplicating one creates
  an independent Researcher Skill that releases never overwrite.
- Researcher Skills and researcher-owned Philosophical Practices remain
  editable and use the direct runtime shape
  `.scholium/skills/<skill-id>/SKILL.md`; nested ownership folders are not
  required.
- The bundled APA 7 citation-verification starter is classed as a
  copy-on-adoption Researcher Skill, not a protected universal citation
  method; other styles and venue rules remain researcher-selected.
- The bundled Prose Control starter is classed as a copy-on-adoption
  Researcher Skill, not part of the official Revision method or a
  universal prose standard. It activates only when explicitly selected and
  preserves its declared semantic ledger; an adopted copy is editable and
  never overwritten by releases.
- The catalog exposes stable routing metadata without loading full methodology;
  selected-package retrieval exposes only validated, declared resources.
- `supported_functions` declares function compatibility;
  `supported_modes` remains legacy decoding and internal method selection.
  Capabilities and citation styles are explicit metadata, never inferred from
  filenames.
- Selective assembly loads Core Protocol, the resolved Workflow Skill, required
  System adapters, and only explicitly bound Researcher Skills or Practices.
  Each run records the exact package revision and conditional resources loaded.
- A one-click request that still requires agent judgment returns a read-only
  method preflight. The external agent finalizes semantic conditional
  references—including an explicit empty selection for primary-method-only
  work—on the same fixed run before execution. The same run, checkpoint, and
  Dialogue or Critique record survive finalization; no mutation instructions
  or completion are available before it, and the finalized snapshot records
  only the exact selected references and revisions. No UI mode or prose
  classifier selects them.
- **Research Guidance → Skills → Research Methods** activates compatible
  Triptych-local Researcher Skills per function as one primary replacement,
  zero or more supplements, and exact Practices. Application MUST validate the
  function, role, Practice, and expected binding revision and persist the
  change atomically. The Strip MUST receive no package IDs or binding controls.
- Development conditionally covers exploration, concept development, argument
  development, synthesis, and Analysis or Topic expression without exposing
  those submethods in the interface.
- Critique is Work-read-only and writes a separate Critique; Revision is the
  independently permissioned current-Work write method; Content Fidelity is
  read-only; Manuscript resolves every isolated phase independently.
- Dialogue remains System transport and record infrastructure. Human Review
  has no Workflow Skill. Source Analysis and self-evolution are neither
  Workflow packages nor Strip functions. Source Analyzer is a complete
  copy-on-adoption Researcher Skill for direct external-agent source work; it
  declares no supported function, requires no Scholium-owned PDF or Zotero
  control, and grants no note-write permission.
- Every official Workflow Skill remains complete without Philosophical
  Practices and declares compatible Practices only as routing hints. Only
  explicitly selected researcher-owned Practices are loaded, with stable IDs,
  revisions, and composition rules preserved; they cannot grant permission or
  silently replace official workflow requirements.
- Selected Practices divide a literal 100% methodological-attention budget.
  The complete active method may declare role-sensitive base weights, which
  are normalized across the selected Practices; otherwise the split is equal.
  Dialogue's selected optional response modules divide their own 100% budget
  equally, so five modules receive 20% each. Attention allocation is distinct
  from output length and never licenses filler or fabricated findings.
- Revision owns planning, drafting, substantive revision, write-mode permission,
  and durability. A selected researcher-owned Prose Control package may compose
  with it for meaning-preserving revision, but
  remains a separate method and cannot silently change thesis, claims,
  concepts, inferential or dialectical relations, source roles, scope,
  modality, qualification, or status.
- One project-neutral Manuscript Workflow coordinates ordinary workflows
  through isolated phases, duplicates none of their full methods, keeps
  evidence state separate from gate judgment, and can conclude only **ready
  for researcher submission decision**.
- A clipboard-only fallback remains bounded and does not claim execution of
  packages the agent could not retrieve.
- On an explicit workspace-setup request, Scholium may supply a protected
  one-shot bootstrap, but only the external agent constructs the optional
  researcher-owned `AGENTS.md` at an exact verified target. It never overwrites
  applicable instructions and deletes only a task-created temporary bootstrap
  after successful read-back validation.
- `Package.swift` resource inclusion, complete-package duplication, the package
  loader, typed catalog, dependency and collision rules, selective assembly,
  local and bundled CLI package retrieval, and package-revision behavior
  receive focused implementation and migration tests before Beta.

**Authority:** Product Guide sections 2.2, 3.4, and 8.3; [Skills README](../Skills/README.md),
`catalog.yaml`, the package evals, and Design Handbook decisions D-029 and
D-040.

#### PRD-RGD-004 — Guarded Researcher Skill evolution

**Requirement:** Self-evolution MUST be an explicit Research Guidance
maintenance transaction, not a Research Function. Only an opted-in
Triptych-local Researcher Skill MAY evolve. Bundled System and Workflow Skills
MUST remain immutable.

**Acceptance criteria:**

- The request carries the expected package revision, proposed whole-package
  patch, evaluation result, and confirmation token.
- The Settings UI shows the diff, evaluation status, **Apply**, and **Restore**.
- Core validates the complete package and bounded `references/`, `templates/`,
  and `evals/`, snapshots it, atomically replaces it, reads it back, and rolls
  back on failure.
- Settings loads one global Recovery inventory independently of the selected
  or valid current package. A missing or malformed current package MUST NOT
  hide its valid snapshots, and one corrupt snapshot MUST NOT hide other valid
  entries.
- Restore MUST confirm complete-package replacement, recheck an expected
  present-or-missing state, remove files absent from the snapshot, and create
  an undo snapshot before displacing an existing package. Reinstalling a
  missing package has no displaced package to snapshot. Snapshot discovery and
  restore MUST use descriptor-relative no-follow reads and report unsafe
  entries without following them.
- No research run, model judgment, filename, or global plugin scan triggers
  evolution automatically.

**Authority:** Product Guide section 8.3; Design Handbook sections 4.9 and 10
and decisions D-029 and D-040.

#### PRD-FUN-001 — Shared Research Function boundary

**Requirement:** Scholium MUST expose delivery-neutral role availability for
Dialogue, Develop, Review, Fidelity, Critique, Revise, and Manuscript. Review
MUST route to Human Review and Comments without creating an agent instruction
packet. Scholium MUST expose material-candidate, preparation,
conditional-method selection, completion, and cancellation use cases for the
agent-facing functions. The App and CLI MUST depend only on Contracts and
Application and MUST NOT import Core, perform vault I/O, inspect skill YAML, or
choose package IDs.

**Acceptance criteria:**

- Contracts contain semantic IDs, Target and Material values, Whole/Passage
  scope, Fidelity checks, availability and repair reason codes, fingerprints,
  prepared runs, completions, and validation without interface labels or
  symbols.
- Material candidates project aliases, direct source location when available,
  and typed suggestion reasons for linked-from-selected-passage,
  linked-from-Target, or links-to-Target. Only explicit resolved one-hop
  Connections qualify; transitive paths, lexical similarity, AI ranking,
  Comment text, and inferred evidential roles MUST NOT qualify.
- Agent-facing panels expose one `ResearchFunctionMaterialsState` and typed actions
  for query, disclosure, Suggested Only, selection, removal, retry, and reset;
  the per-window function controller remains the sole draft owner.
- Analysis/Topic availability is Dialogue, Develop, Review, Fidelity; Work
  availability is Critique, Revise, Dialogue, Fidelity, Manuscript.
- `ResearchUseCases` remains a compatibility composite over narrow record,
  checkpoint, skill, and function protocols.
- CLI function commands decode and encode Contracts values and invoke the same
  Application coordinator as the App.

**Authority:** Product Guide sections 8.1 and 12; Design Handbook sections 4.8
and 10 and decision D-037.

#### PRD-FUN-002 — Preparation and completion transaction

**Requirement:** For agent-facing preparation, Application MUST fix one Target, validate every read-only
Material independently, reject Target duplication, resolve the exact workflow
resources, create the required checkpoint and record, recheck revisions before
returning instructions, and roll back a partial preparation. Completion MUST
validate the prepared run, function, and final fingerprints.

**Acceptance criteria:**

- Develop, Revise, Manuscript, promoted Dialogue, and Critique use the required
  checkpoint; Fidelity does not. Review bypasses agent preparation and uses the
  Human Review contract.
- An unresolved conditional-method request persists a read-only preflight on
  the normal run, checkpoint, and evidential record. Explicit method selection,
  including an empty base-only selection, atomically finalizes that same run;
  preparation completion is rejected while selection remains unresolved.
- Cancellation is explicit and idempotent for a prepared run.
- Legacy Dialogue and Critique APIs delegate through the coordinator during
  migration.
- Dialogue, Critique, Human Review, Comments, and Fidelity remain separate
  records even when related by one run identifier.
- Every Material starts unselected. The browser supports title, alias,
  filename, and path search while retaining matching Analyses/Topics/Works
  ancestors, an optional Suggested Only filter, and a Selected Materials tray
  with individual Remove actions. There is no bulk selection.
- Material failure blocks preparation and offers Retry Materials; honest empty
  permits Target-only preparation. Preparation freezes Materials so the
  packet cannot diverge from copied instructions.

**Authority:** Product Guide sections 8.1 and 8.4; Design Handbook sections 4.8
and 10 and decisions D-026 and D-037.

#### PRD-FUN-003 — Revision-specific Fidelity handoff

**Requirement:** Fidelity MUST record manual or automatic invocation provenance
through one exact-revision evidence contract. Manual Fidelity MUST remain the
direct Strip function against the current exact revision. After Develop or
Revise changes the Target, automatic orchestration MUST create or reuse an
independent read-only Fidelity child against the exact final fingerprint and
link it without requiring the researcher to operate that relationship. Because
Scholium has no embedded agent runtime, automatic orchestration MUST NOT claim
that an audit occurred before an agent submits actual outcomes.

**Acceptance criteria:**

- The first valid write completion persists as Awaiting Fidelity. Direct
  Fidelity outcomes on the write run are rejected.
- The Fidelity child preserves the parent's Target identity at its exact final
  fingerprint plus the same Materials, scope kind, selected Comments, and
  required checks. Only a completed matching child run ID advances the parent.
- The deterministic audit planner rejects duplicate work by reusing rather
  than persisting a second result for one function, scope, evidence, checks,
  and final revision. Later Target or evidence changes mark the outcome stale.
- Content is always available. Citations is available only when the backend
  validates an active Triptych binding to a compatible citation capability and
  style; malformed or missing bindings return a typed repair reason.
- Manuscript reuses automatic Fidelity evidence attached to its final selected
  Revise child. Critique and Dialogue do not trigger Target Fidelity because
  they do not edit the Target.
- Manual and automatic paths share evidence validation and deterministic
  revision-specific reuse while preserving invocation kind for provenance.

**Authority:** Product Guide section 8.4; Design Handbook sections 4.8 and 10
and decision D-038.

### 7.5 Works and Critique

#### PRD-CRI-001 — Critique association and storage

**Requirement:** A Work MAY have at most one current Critique document. A
Critique normally targets one Work, lives in the designated Critiques area,
remains distinct from Work prose, and is read-only inside Scholium while
remaining ordinary Markdown for external editors.
Critique is an optional agent-assisted extension and is not required for the
manual academic workflow.

**Acceptance criteria:**

- Critique is available for a Work where applicable.
- Later Critique rounds update the current Critique while earlier states remain
  available through checkpoint-backed history.
- Critiques cannot cross the Critiques boundary through ordinary lifecycle
  actions.
- Critique association records the target Work and target fingerprint.
- External edits to the ordinary Critique file are detected safely.

**Authority:** Product Guide section 11.

#### PRD-CRI-002 — Critique request and form

**Requirement:** Critique MUST be one Work function offering **Whole |
Passage**, included Work Comments, and an optional focus or disciplinary lens.
An existing editor selection MUST default to Passage. It MUST NOT display or permit
one-run selection or editing of the active template or assembled technical
instructions.
Critique remains optional; a Work can be written and revised without it.

The default Critique MUST distinguish source reports, support, disputes, and
uncertainty from agent reconstruction or evaluation. It MUST identify
materials consulted and limitations.

**Acceptance criteria:**

- Existing Work Comments and the anchored inline composer appear directly in
  Critique; no Manage Comments doorway or second-level Comments sheet exists.
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
sections 4.8, 9, and 10 and decision D-037.

### 7.6 Connections, Search, and Attention

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

#### PRD-CON-002 — No inferred philosophical evidence

**Requirement:** Scholium MUST NOT infer philosophical support, truth,
settlement, sufficiency, or integration from keywords, proximity, folder
membership, graph paths, neutral links, or transitivity.

**Acceptance criteria:**

- Neutral and transitive paths are presented as Connections, not evidence.
- Derived warnings identify themselves as derived.
- Source-related Critique judgments remain attributed agent judgments.
- Search results remain retrieval leads, not evidence.

**Authority:** Product Guide sections 2, 10, 12, 13, and 18; Design Handbook
sections 3.4 and 7.

#### PRD-SEA-001 — Search scopes

**Requirement:** Sidebar filtering, unified ranked Search, and Research
inspector retrieval MUST remain distinct tasks while sharing a clear query and
filter contract. Search MUST also provide known-note navigation by ranking
exact title, alias, filename, and path matches above body matches without a
separate mode. Scholium MUST NOT provide Back/Forward, Recent Notes, Quick
Open, or their commands, state, persistence, or tests. Command-F MUST activate
temporary **This Note** in the shared Search surface only when a note is open;
Scholium MUST NOT present a separate in-note Find interface.

Beta Search MUST use deterministic local SQLite FTS5 retrieval. It MAY resolve
one exact Topic title or alias and show only its direct resolved graph
connections in a separate **Related** section. Related items MUST NOT alter
lexical ranking, include transitive inference, or imply evidential support.
Vector search, embeddings, AI query interpretation, AI ranking, and chat-style
search are excluded from Beta.

**Acceptance criteria:**

- Empty Search is a centered, compact Liquid Glass command surface over a
  softly obscured window with ordinary interface-sized text and **This Note /
  This Vault / Triptych** visible immediately; it does not expose a blank
  result panel or occupy most of the document region.
- Entering a non-empty query expands the same surface vertically to reveal a
  bounded result list while keeping a compact responsive width. Exact title,
  alias, filename, and path matches rank above body matches.
- Search results show title, snippet, field/context, and destination.
- **This Note** operates within the exact vault-qualified current note.
- Each window retains the last explicitly selected general scope. Dismissing
  temporary Find restores that scope unless the researcher changed scope,
  which makes the chosen scope ordinary and ends the override.
- Dismissal cancels pending work, rejects stale results, clears transient query
  and results, and retains only the ordinary scope and saved searches.
- Every lexical result identifies its match context and source destination.
- Related items identify the direct graph relation and remain visually and
  semantically separate from lexical results.
- Loading, zero-result, malformed, conflict, and inaccessible states remain
  scoped and recoverable.
- Search does not rewrite source or claim evidential support.

**Authority:** Product Guide section 13; Design Handbook sections 4.3, 4.5, 9,
and 10 and decisions D-031, D-036, and D-044.

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

### 7.7 Checkpoints, versions, and recovery

#### PRD-CHK-001 — Before Agent Work checkpoint

**Requirement:** Immediately before Scholium prepares Develop, Revise,
Manuscript, promoted Dialogue, or Critique work for an agent, it MUST complete
pending autosaves and create the required named, fingerprint-bound checkpoint
of the entire Triptych. Read-only Dialogue, Review, and Fidelity MUST NOT
create that checkpoint.

**Acceptance criteria:**

- The checkpoint uses the function's required Before Agent Work reason.
- It contains the complete Triptych and portable configuration needed to
  interpret it.
- It is stored outside the vaults.
- It is not confused with a Dialogue entry or editor Undo.
- Manual checkpoints remain available.

**Authority:** Product Guide sections 8.1 and 14; Design Handbook section 10.

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

#### PRD-CHK-003 — Undo versus durable recovery

**Requirement:** Editor Undo MUST reverse current-session editing operations.
Restore from Checkpoint… MUST create a new current version through the
conflict-aware repository and MUST NOT silently rewrite history.

**Acceptance criteria:**

- The interface uses distinct labels and actions.
- Ordinary autosaves do not create visible versions.
- A restored version remains attributable to the restore operation.

**Authority:** Product Guide section 14; Design Handbook section 10.

### 7.8 Zotero integration

#### PRD-ZOT-001 — Built-in local, read-only Zotero boundary

**Requirement:** Scholium's built-in Zotero integration MAY read through the
localhost API only when the researcher chooses to use Zotero. Zotero MUST NOT
be required for the core workflow. The built-in integration MUST NOT require a
server, password, online Web API, attachment enumeration, attachment download,
SQLite access, or Zotero metadata writes. The separately bounded external-agent
MCP target is governed by PRD-ZOT-004 and does not broaden the built-in UI.

**Acceptance criteria:**

- Settings exposes connection status, Open Zotero, Test Connection, Refresh
  Library Information, Forget Cached Zotero Data, and last successful
  connection time.
- Privacy explanation is concise and local.
- Unavailable Zotero states explain the exact condition.
- Cached metadata is labelled with retrieval time.
- The only source action is Open in Zotero.

**Authority:** Product Guide section 15.

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

**Authority:** Product Guide section 15.2.

#### PRD-ZOT-004 — Protected external-agent Zotero MCP adapter

**Requirement:** Beta MUST provide the protected
`scholium-zotero-integration` System Skill and pair it with a supported local
Zotero MCP service or supported installation path. The Skill MUST define safe
use of readiness, search, item inspection, bounded attachment pointers,
selected-target inspection, and guarded BibTeX or RIS import capabilities. The
MCP integration MUST remain optional and MUST NOT change Scholium's built-in
read-only Zotero UI boundary.

**Acceptance criteria:**

- The skill and MCP transport are identified as separate components; a skill
  file alone is never presented as a working Zotero connection.
- Retrieval is the default, starts with readiness checking, preserves ambiguous
  matches, and distinguishes Zotero item keys from citation keys.
- Zotero metadata establishes record identity only and is never treated as
  evidence for a quotation, locator, claim, concept, argument, or
  interpretation.
- Attachments or full text are requested only when needed by the current read
  set, with version, extraction, and locator reliability recorded.
- A real import requires an explicit current-task request for the exact record,
  a verified destination, a successful dry run, the MCP tool's explicit
  confirmation gate, and read-back verification.
- The integration never scans an external agent's global configuration, never
  reads or writes the live Zotero SQLite database directly, and never bypasses
  an unavailable MCP route through raw database access.
- Citation style and bibliographic-format authority remain researcher-selected
  specialist concerns rather than responsibilities of this System Skill.

**Authority:** Product Guide section 15.3; [Skills README](../Skills/README.md)
Zotero contract; [Zotero MCP](ZOTERO_MCP.md); and
`Skills/Scholium System Skills/scholium-zotero-integration`.

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
guidance.

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

1. navigation sidebar for scope, vault, Attention, hierarchy, and filters;
2. a content list when needed;
3. document detail for header, Properties, reader/editor, and local commands;
4. a trailing research inspector for contextual Connections, Zotero identity,
   Attention, and source-located diagnostics.

The product MUST NOT provide a Triptych Home or dashboard. A configured window
MUST keep one stable workspace frame and `NavigationSplitView` root. With no
selected note, Library remains the actionable leading interface and detail
contains only the decorative featured artwork. Selecting, replacing,
or closing a note MUST NOT change frame or position. The native Show/Hide
Sidebar control MUST change only Library visibility, and Scholium MUST NOT add a
separate Collapse Note function. First-run setup MUST remain the only narrow
window state, complete without scrolling, expand once to the normal workspace,
and honor Reduce Motion.

Changing the Library's Analyses, Topics, or Works browser scope MUST retain the
open document. Only explicit note selection replaces it; showing or hiding
Library MUST NOT clear it.

Parallel document work MUST use native macOS window tabs as complete window
sessions. The product MUST retain standard Window-menu tab commands and
`Command-W` and MUST NOT add a custom document-tab strip, custom cycling or
closing, or custom Merge/Move commands.

The product MUST use native windows, split views, inspectors, toolbars, menus,
sheets, alerts, controls, focus, and file panels where they provide the
required behavior.

When a note is open, one Research Strip MUST be mounted at the bottom of the
editor with matching reserved space. It MUST be absent when no note is
selected, MUST open one typed function panel directly, and MUST NOT add a
folder- or multi-selection Strip, Open Scholia doorway, or second-level mode
chooser. The Research menu and keyboard commands MUST provide equivalent
focused-window access.

### PRD-UX-003 — Exact lifecycle language

The following meanings and labels MUST remain stable:

- Edited, Saving, Saved, Save Failed, Conflict, Refreshing, Derived State
  Stale, Refresh Failed, and Fully Up to Date;
- Keep Editing, Retry Save, Compare Changes, Reload from Disk, Return to
  Editing, and Retry Refresh;
- Dialogue, Develop, Review, Fidelity, Critique, Revise, Manuscript, Whole,
  Passage, Content, Citations, Copy Instructions for Agent, Awaiting Fidelity,
  Unverified, Verified, Stale, Open Research Guidance…, and Cancel;
- Review, Continue Review, Qualified, Unqualified, Complete Review, Save as
  Draft, Declare Now, Not Yet, Declare Research Status…, and Cancel;
- Suggested Only, Selected Materials (n), Remove, Suggested — Linked from
  Selected Passage, Suggested — Linked from Target, Suggested — Links to
  Target, and Retry Materials;
- Edit Dialogue Template… and Edit Critique Template…;
- Research Guidance, Prompt Templates, Skills, Reveal Skills Folder, and Reset
  to Scholium Default;
- Research Methods, Function, Method, Built-in, Supplements, Practices,
  Advanced, Repair…, Evolve…, Recovery, Recovery Issues, Restore…, Restore
  Complete Package, and Cancel;
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
- accessible list equivalents for graph surfaces.

Important state MUST be communicated through at least two suitable channels.
Color or spatial position alone is insufficient.

The Beta and 1.0 accessibility pass threshold is explicit: 100% of the core
academic workflow MUST be operable through Full Keyboard Access and VoiceOver,
with no mouse-only or color-only required action. This includes setup, opening
and editing notes, Human Review, comments, Dialogue presentation, Search,
Connections, checkpoint restore, conflict recovery, and Trash/Put Back. Light
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

### 8.1 UX acceptance pointer

The Design Handbook sections cited by PRD-UX-001 through PRD-UX-006 define
their interface acceptance contract. Current reachability and remaining
manual acceptance work are maintained only in
[Implementation Status](IMPLEMENTATION_STATUS.md).

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

Core reading, editing, review, search, Connections, checkpoints, and
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
frozen Reference Data Fixture RDF-1, containing approximately 500
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
| J-001 | Create or open a Triptych | Researcher selects three roots in narrow setup, expands once into the stable workspace, sees peer vaults and the artwork-only no-note detail, and can group complete sessions through native tabs. |
| J-002 | Read and edit a note | Researcher reads, switches modes, edits exact source, and receives authoritative Saved or recoverable failure state. |
| J-003 | Configure Properties and inspect Research Status | Researcher configures vault-wide visible fields, chooses Declare Now or Not Yet for a new Analysis, sees declared Scope/Limitations or honest Not Yet without raw-YAML clutter, receives app-owned creation/modification History, and does not corrupt unrelated YAML or protected identity. |
| J-004 | Review an Analysis or Topic | Researcher sees and adds anchored Comments in the Review panel, completes or drafts Human Review, receives the Research Status completion gate when applicable, and sees fingerprint-bound state. |
| J-005 | Use an Unqualified Analysis | Researcher can continue work while explicit reliance produces a non-blocking source-anchored Attention. |
| J-006 | Prepare optional agent work | When the researcher chooses an agent, she searches the real folder hierarchy, evaluates direct explainable Material suggestions, makes an explicit frozen selection, and verifies scholarly and consequential context without seeing prompt mechanics. Checkpoint-eligible write or Critique preparation completes Before Agent Work before mutation instructions; read-only functions create none. |
| J-007 | Reconcile an external edit | Clean notes refresh; dirty notes preserve the local buffer and present Compare Changes, Reload from Disk, and Keep Editing. |
| J-008 | Critique and inspect a Work | Researcher opens Critique from the Work Strip, sees and adds anchored Work Comments in the same panel, chooses Whole or Passage with Materials, and can navigate findings to the fixed Target. |
| J-009 | Restore a checkpoint | Researcher compares and selectively or completely restores a self-contained checkpoint without confusing restore with Undo. |
| J-010 | Search and trace Connections | Researcher always sees the three scopes, uses Search for known-note navigation, temporarily enters This Note with Command-F and restores the general scope, sees snippets and source locations, and does not receive inferred philosophical evidence. |
| J-011 | Use optional Zotero context | When Zotero is available and selected, the researcher sees only bounded relevant metadata and can open the identified item in Zotero; its absence does not block the workflow. |
| J-012 | Complete the workflow accessibly | Researcher completes primary journeys with keyboard and assistive technology paths under supported adaptations. |
| J-013 | Complete the manual workflow without optional integrations | Researcher completes the core academic workflow in a clean environment where Obsidian, Zotero, and external agents are absent; Dialogue and Critique remain optional extensions. |
| J-014 | Manage research guidance | Researcher uses bundled defaults from the plain-language Skills summary, edits or duplicates according to ownership, opens Advanced only for composition or maintenance, and follows Repair directly to recovery without exposing technical sources in the scholarly workflow. |
| J-015 | Run a function-aware agent workflow | A local agent prepares one typed function, explicitly finalizes any conditional methods on the same run, receives only the resolved dependency closure and selected resources, respects phase-local permission, submits actual outcomes to an automatically linked/reused final-fingerprint Fidelity child when required, and answers using the request-scoped Dialogue contract. |
| J-016 | Use optional agent Zotero MCP | A local agent retrieves an exact Zotero record without treating metadata as source evidence and performs an import only through explicit request, dry run, confirmation, and read-back verification. |

## 11. Success measures and product outcomes

The following measures convert product principles into release evidence. They
are proposed measures, not current telemetry or user-study findings.

| ID | Measure | Proposed acceptance target | Evidence |
| --- | --- | --- | --- |
| M-001 | Unexpected source mutation | Zero unexpected bytes changed outside the explicitly edited range in fidelity fixtures. | Source-fidelity test matrix and readback comparison. |
| M-002 | Dirty-buffer overwrite | Zero accepted writes that overwrite a dirty local buffer after an external revision change. | Conflict and repository tests plus QA journey J-007. |
| M-003 | Checkpoint boundary | 100% of Develop, Revise, Manuscript, promoted-Dialogue, and Critique preparation journeys create the required Before Agent Work checkpoint before mutation instructions; read-only Dialogue, Review, and Fidelity create none. | Function tests and QA evidence for J-006 and J-008. |
| M-004 | Derived-status honesty | 100% of user-visible diagnostics identify their derived scope and source anchor or explicitly state that no anchor exists. | Attention, Connections, Critique, and UI review. |
| M-005 | Accessibility path coverage | Every primary journey has a tested keyboard path; all required assistive-technology gaps are explicitly dispositioned before release. | UI automation, manual accessibility audit, and retained artifacts. |
| M-006 | Recovery correctness | Selective and complete restore preserve source integrity and expose conflicts rather than silently replacing newer work. | Checkpoint fixtures and QA journey J-009. |
| M-007 | Zotero boundary | The built-in app makes zero attachment-enumeration, download, database-access, or Zotero-write requests. The optional agent MCP makes zero direct database accesses and zero imports without exact current-task authorization, dry run, explicit confirmation, and read-back verification. | Built-in and MCP boundary tests, tool-call audit, and J-011/J-016 evidence. |
| M-008 | Researcher task success | Target and baseline for setup, review, agent preparation, conflict recovery, and restore. | TBD usability protocol and researcher tasks. |
| M-009 | Performance | Measure warm launch, indexed Search, warm Read activation, and application-cold 5,000-word Read activation on Reference Machine R1 and frozen RDF-1. Proposed strict p95 limits are respectively `< 1,000 ms`, `< 100 ms`, `< 300 ms`, and `< 1,000 ms`; release-owner approval remains required. Complete-boundary instrumentation and the thermally bounded fail-closed runner are implemented, but no packaged Release 30-sample gate run exists. | `PERFORMANCE_BENCHMARK.md`, Release-app timing harness, raw 30-sample artifacts, and RDF-1 correctness results. |
| M-010 | Obsidian independence | 100% of core academic journey acceptance in a clean environment without Obsidian installed. | Isolated Scholium app run and J-013 workflow checklist. |
| M-011 | Skill routing integrity | 100% of routing fixtures load only the required function dependency closure; zero protected-ID shadows, undeclared resources, global-directory scans, package-ID selection by delivery adapters, stale binding writes, unresolved-method completion, or Manuscript-phase permission leaks. | Catalog, loader, binding, CLI, selective-assembly, collision, and forward-routing tests plus J-014–J-015. |
| M-012 | Dialogue response fidelity | 100% of new agent requests expose the immutable request-time `responseContract`; legacy fallbacks are labelled and no response module expands task scope. | Dialogue migration, snapshot, CLI, and response-module tests plus J-015. |

M-008 still requires an explicit usability target before a release decision.
M-009 now records proposed numeric targets and the deterministic RDF-1 fixture,
but the release owner has not yet approved the limits and the packaged-app
timing harness has not yet produced gate evidence.

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
- use disposable nonprivate UI fixtures or generated temporary vaults, never
  real research vaults; performance measurements follow the canonical
  [RDF-1 protocol](PERFORMANCE_BENCHMARK.md);
- exercise primary journeys J-001 through J-016 as applicable to the declared
  release stage;
- cover empty, loading, malformed, unavailable, conflict, and recovery states;
- test light/dark appearance, Increase Contrast, Reduce Transparency, Reduce
  Motion, large text, keyboard access, VoiceOver, mixed-script input, and
  minimum usable window sizes;
- retain command, build configuration, platform/SDK, fixture root, outcome,
  and result bundle or screenshot for material UI work; and
- record all unresolved behavior rather than converting it into a passing
  assumption.

### 12.3 Current evidence pointer

Current reachability and verification evidence are maintained in
[Implementation Status](IMPLEMENTATION_STATUS.md). The PRD keeps release
requirements, gates, risks, and top-level traceability here; it does not
repeat run-by-run evidence.

## 13. Migration and delivery plan

The delivery sequence below preserves the Product Guide's migration boundary
while adding an exit gate to each phase.

| Phase | Scope | Exit gate |
| --- | --- | --- |
| P0 | Approve this PRD, set release boundary, assign owners, and resolve authority conflicts. | Approved product baseline, requirement dispositions, and named owners. |
| P1 | Remove obsolete Proposal/Revision/Research Session assumptions from product and UI documents without deleting legacy data. | No reachable retired authorization or governance UI; legacy files remain untouched. |
| P2 | Complete stable identity, exact-source autosave, external-edit conflicts, repository safety, and shared multiwindow ownership. | Fidelity, conflict, identity, and multiwindow tests pass with no dirty-buffer overwrite. |
| P3 | Complete lifecycle, import, Unclassified classification, Properties, Research Status, app-owned creation/modification History, Human Review, comments, and Note History. | Create/move/rename/delete/recovery, Research Unit compatibility, and Review journeys pass in isolated fixtures. |
| P4 | Complete researcher-centred Dialogue, Settings-only prompt-template and file-backed skill management, optional pre-agent checkpoints, CLI replies, Critique association, prompt transport, and source-located findings. | Dialogue, Research Guidance, optional agent reply, Critique, provenance, skill-discovery, and fingerprint journeys pass. |
| P5 | Complete self-contained checkpoints, comparison, selective/full restore, Finder access, and permanent-deletion scrubbing of app-owned records and checkpoint copies. | Recovery and purge journeys pass with newer external changes and conflict paths. |
| P6 | Complete Search, Attention, canonical Connections, and bounded Zotero integration. | Search, relationship, Attention, and Zotero boundary gates pass. |
| P7 | Add Research Function Contracts, the Application coordinator, thin CLI commands, legacy API wrappers, the per-window frontend controller, editor-only Strip, typed panel route, direct menu commands, and mandatory completion/Fidelity handoff. | Function-role, transaction, race, cancellation, parity, target-locking, stale-response, architecture, and UI journeys pass. |
| P8 | Migrate to the five function-aware Workflow packages, capability and citation bindings, exact resource snapshots, product-skill mirror tooling, and guarded Researcher Skill evolution; retain the protected Zotero MCP adapter and transport. | J-014–J-016, M-007, M-011, and M-012 plus function/skill/evolution rollback cases pass. |
| P9 | Complete visual, accessibility, CJK, performance, multiwindow, conflict, recovery, and release acceptance. | All release gates pass or have explicit documented waivers. |

Current remaining work is maintained only in
[Implementation Status](IMPLEMENTATION_STATUS.md). The release gates below
define the required outcomes without duplicating the dated work ledger.

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
| G10 — Agent skill architecture | For Beta, protected and researcher-owned package boundaries, function-aware dependency-closed assembly, isolated Manuscript phases, citation bindings, guarded evolution, request-scoped Dialogue responses, one-shot bootstrap safety, and guarded Zotero MCP behavior pass J-014–J-016 and M-007/M-011/M-012 without global skill scanning or hidden authorization. |

For 0.1 Experimental, G1, G2, G3, G4, G5, G8, and—whenever an external
artifact is distributed—G9 are applicable release
conditions. G6 and G7 require a documented baseline and known gaps, but 0.1
MUST NOT be presented as having passed the Beta/1.0 accessibility or
performance thresholds. G10 is not an Experimental 0.1 gate. Beta requires all
applicable gates, including G10, and 1.0 requires all gates plus the complete
daily-workflow definition in Section 5.3.

## 15. Risks, open decisions, and assumptions

### 15.1 Product and release decisions

| ID | Item | Type | Current disposition |
| --- | --- | --- | --- |
| R-001 | No formal user research or quantitative usability baseline is recorded in the source set. | Risk | Create a bounded researcher-task protocol before setting M-008. |
| R-002 | The release boundary and ownership needed explicit confirmation. | Decision | Resolved for the current baseline: 0.1 Experimental; release owner Imna; scope and gates are defined in Sections 5.3 and 14. |
| R-003 | Proposed launch, Search, and Read thresholds and the complete-boundary runner are implemented, but packaged Release R1 measurements and release-owner approval remain absent. | Measurement | Freeze and package an exact clean tag, retain the thermally bounded 30-sample RDF-1 artifacts, and approve or revise the proposed strict p95 limits before Beta. |
| R-004 | The external distribution model needed a feasible no-fee path. | Decision | Use the source-first `v0.1.0-beta.1` policy in `BETA_RELEASE.md`: exact GPL-tagged source plus an optional ad-hoc-signed app-only ZIP and checksum. State the Gatekeeper limitation explicitly. Developer ID signing and notarization remain optional future improvements. |

### 15.2 Implementation and acceptance risks

| ID | Item | Type | Current disposition |
| --- | --- | --- | --- |
| R-005 | Shared multiwindow ownership is implemented, but sustained same-process interaction, simultaneous restored sessions, the dirty-peer UI path, and explicit native AppKit grouping and separation still require complete interactive acceptance. | Acceptance risk | Complete and retain the independent-session, shared-commit, dirty-conflict, focused-routing, rename-convergence, restored-multiwindow, and native-grouping matrix before closing the risk. |
| R-006 | External rename migration and its clean, dirty, ambiguous, and multiwindow interactive matrix are accepted on disposable fixtures. | Resolved acceptance evidence | Keep the combined rename matrix in the release regression set and preserve researcher confirmation for ambiguous identity. |
| R-007 | Permanent deletion must remove app-owned history, associated Critique content, and every recoverable checkpoint copy of the deleted note. | Resolved implementation evidence | Coordinated Work/current-Critique deletion, cross-store rollback, restart recovery, checkpoint invalidation, destructive confirmation, and durable recovery inspection pass disposable core and isolated UI journeys. Keep them in the release regression set. |
| R-008 | Manual accessibility and standalone clean-environment acceptance remain incomplete; automated clean-account setup, Critique navigation, and cold compact-width behavior now pass. | Acceptance risk | Complete manual adaptation and assistive-technology acceptance, accept the standalone workflow without optional integrations, and record retained artifacts. |
| R-009 | Legacy role and schema decoders remain for compatibility. | Resolved migration evidence | Immutable fixtures cover every retained role spelling, property alias, sparse window/Search state, and v0 Triptych identity. Keep these bounded read paths while compatible persisted data remains supported. |
| R-010 | The function architecture, five-package migration, explicit citation-style bindings, and guarded whole-package Researcher Skill evolution are structurally implemented, but philosophical field trials and manual accessibility acceptance remain incomplete. | Beta acceptance risk | Preserve the verified function, package, citation, and evolution boundaries while completing the retained philosophical and manual acceptance evidence before claiming G10 or J-014–J-016. |

### 15.3 Unresolved interface questions

The Design Handbook identifies these as future or unresolved and they MUST NOT
be presented as completed behavior:

- sustained VoiceOver, Full Keyboard Access, Voice Control, contrast, scaling,
  and localization verification across CodeMirror/WKWebView;
- compact multi-note Dialogue presentation in Note History.

## 16. Requirement traceability

The following matrix provides the top-level authority and journey mapping.
Requirement-specific authority remains beside each requirement; current
status is centralized in [Implementation Status](IMPLEMENTATION_STATUS.md).

| Requirement area | Product Guide | Design Handbook | Primary journeys |
| --- | --- | --- | --- |
| Triptych, windows, native tabs, and no-note artwork | §§1, 3–4, 16 | §§1, 4.1–4.5, 10.5; D-036, D-041 | J-001 |
| Exact Markdown, YAML, and Research Unit | §5.1–5.2 | §§3.3, 4.4, 4.6, 9–10; D-033, D-042 | J-002, J-003 |
| Identity and lifecycle | §§5.3, 6 | §§3.3, 4.6, 9–10 | J-003, J-007, J-009 |
| Human Review, comments, and Research Status gate | §§5.2, 7 | §§4.6, 4.8, 8, 10; D-037, D-039, D-043 | J-003–J-005 |
| Dialogue and CLI | §8 | §§3.5, 4.8, 10 | J-006, J-007, J-015 |
| Research Functions, Materials, and Fidelity | §§8.1, 8.4 | §§4.8, 10; D-026, D-037, D-038 | J-004, J-006, J-008, J-015 |
| Research Guidance, prompt templates, and skills | §8.3 | §§4.8–4.9, 10; D-029, D-040 | J-006, J-008, J-014, J-015 |
| Critique | §11 | §§4.8, 9–10 | J-008 |
| Connections | §12 | §§4.7, 8–9 | J-010, J-012 |
| Search and Attention | §13 | §§4.3, 4.5, 4.7, 9–10; D-031, D-036, D-044 | J-005, J-010 |
| Checkpoints and recovery | §14 | §§3.3, 4.8, 9–10 | J-006, J-007, J-009 |
| Zotero | §15 | §§4.7, 4.9 | J-011, J-016 |
| Standalone academic workflow | §2.1 | §2 | J-013 |
| Accessibility and visual language | — | §§3, 5–10, 13 | J-002, J-004, J-006–J-016 |

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

## Appendix A. Terminology routing

Product terms are owned by the [Product Guide](PRODUCT_GUIDE.md), exact
interface terms by the [Design Handbook](DESIGN_HANDBOOK.md) Section 10, and
current-status terms by [Implementation Status](IMPLEMENTATION_STATUS.md).
Requirement language is defined in Section 0.1. This PRD keeps no second
product glossary.

## Appendix B. Maintained source set

- Product Guide.
- Design Handbook.
- Implementation Status with a compact representative evidence ledger.
- Scholium README and repository AGENTS.md.
- Swift package manifest, which sets macOS 26 as the package platform baseline.

This appendix identifies the maintained source set for this PRD. It does not
replace current source, tests, or the explicit authority hierarchy in Section
0.
