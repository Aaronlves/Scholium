# Specification: Foundation and Triptych

Part of the canonical document set rooted at [SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md).
This chapter owns Sections 1–4: terminology, product authority, Triptych structure, and Works organization; sibling chapters do not restate it.

## 1. Canonical terminology

- A **Scholium Triptych** (**Triptych**) is one configured workspace containing
  exactly three vaults: **Analyses**, **Topics**, and **Works**. Their ordinary
  documents are an **Analysis**, **Topic**, and **Work**.
- A **Research Action** is a researcher-selected scholarly transition or
  authority boundary exposed by the Research Inspector's **Actions** mode and
  executed through the shared Application API. The stable default Actions are
  Discuss, Analyze, Synthesize, Write, Critique, and Check Fidelity. Internal
  execution mechanisms may retain implementation names such as Develop or
  Revise, but those names are not public operations.
- An Action's **Origin** is the immutable current Analysis, Topic, or Work from
  which work begins. Its **Target** is the note or passage the Action is meant
  to affect. **Focal Materials** guide attention without defining the complete
  read boundary, and no readable or focal note becomes writable merely because
  an agent can inspect it.
- A **Discussion** is one resumable researcher-agent exchange containing
  passage-anchored Comments, optional whole-note turns, optional focal notes,
  attributed replies, and any authorized child Action. Closing its Action
  surface preserves it; **Finish Discussion** creates one Research Record and
  makes no claim of acceptance, truth, or settlement.
- A **Method Skill** is an ordinary, directly editable, versioned Skill package
  that supplies the intellectual method for one or more Actions. It remains
  distinct from the protected Scholium mechanism and from ordinary research
  notes. An **Action Profile** is researcher-owned declarative configuration
  for placement, inputs, applicability, and requested capability; neither
  Skill prose nor a Profile grants authority by itself.
- **Settle** is the researcher's fingerprint-bound, replaceable current
  judgment that one saved revision is sufficiently stable for current
  research. It is neither a verdict nor a qualification. Each distinct
  settled revision pins one deduplicated machine-local exact-byte recovery
  version of that Note.
- **Critique** is an attributed agent assessment of one Work. It does not
  replace or silently edit the Work.
- **Fidelity** audits the exact revision's philosophical content and, when an
  applicable Researcher Skill is bound, citations. It remains distinct from
  Settle and Critique.
- **Connect** is the Inspector surface for source-located neutral, support,
  opposition, or incompatibility relations. **Attention** contains derived, recoverable
  warnings; it makes no philosophical judgment.
- **Properties** is the human-facing projection of frontmatter. A **Research
  Unit** is the minimal YAML declaration of the epistemic scope represented by
  a note; About presents its Scope and material Limitations with other chosen
  properties rather than creating another status model.
- A **Research Action Grant** is one short-lived, task-bound write authority.
  Its plaintext key is carried only in the prepared handoff; Scholium persists
  only a digest and the frozen Action, Skill revision, Origin, scope,
  identities, revisions, and expiry.
- **Research Record** is the portable intellectual record of one finished
  Discussion or validated Action run. A separate nonmodal two-panel utility
  window browses these records; active Discussion remains in Actions, and
  ordinary Markdown annotations remain in the document.
- A **Checkpoint** is a self-contained, fingerprint-bound snapshot of the
  complete Triptych, distinct from editor Undo.

There is no formal Revision artifact, Proposal, Research Task, Research
Session, Failure object, or Alternative relation. “Revision” may still
describe an edit or a Critique section.

## 2. Product role and authority

### 2.1 Research document first

Scholium is a local-first macOS document editor for sustained humanities
research, especially philosophy. The research document—not a dashboard, task,
workflow state, or agent conversation—is primary; exact Markdown underlies
every projection.

Before polish or optional workflows may block release, setup, open, create,
read, edit, autosave, Search, conflicts, recovery, Library, Document tabs, and
contextual inspection must work without data loss, shell reconstruction, or
surprising state changes. Visual metrics are provisional unless required by
readability, accessibility, source integrity, or native-window behavior.

Scholium supports source-grounded reading, writing, authoritative Markdown
annotation, deliberate agent communication, Settle, Search, Connect,
organization, recovery, and provenance. It is not project or reference management,
permanent AI chat, or a full Obsidian replacement. The manual core must work
without Obsidian, Zotero, or agents.

### 2.2 Researcher responsibility and optional agent access

The researcher governs the Triptych and may instruct an external agent to
mutate files through filesystem or CLI tools. Scholium never revives Proposal.
A standing permission policy decides only when a validated short-lived grant
may be issued without another question; every prepared write phase still uses
one Research Action Grant whose key, frozen scope, and completion command
authorize only that phase. Discussion and Critique remain optional.

Scholium supplies safety, not transferred responsibility:

- exact paths, stable identities, and Application-owned fingerprint checks;
- autosave, atomic writes, external-change detection, and conflicts;
- automatic and manual Triptych checkpoints, comparison, and restoration.

Extensive external work without a suitable checkpoint is not guaranteed
recoverable. Fingerprints detect revisions; they are not permission tokens and
do not need to be copied into the agent prompt.

The Application API validates each Research Action's Target, focal context,
source access, revision, Method Skill, Action Profile, permission, checkpoint,
and completion contract. Frontends select semantic Actions, never protected
package identifiers or assembled technical instructions. The protected
mechanism supplies protocol and safety; one installed Method Skill supplies
the intellectual procedure.

Scholium distinguishes:

- protected, release-managed **System Skills** for mechanism only;
- directly editable, Triptych-installed **Working Method Skills**;
- read-only bundled references used only for explicit compare or restore; and
- researcher-installed **Researcher Skills**, disabled until deliberately
  configured and enabled.

Bundled methods are usable defaults, not best methods, philosophy lessons, or
certification. The researcher may edit, replace, or disable a Working Method.
Scholium never silently falls back to a bundled reference after that choice.

### 2.3 Authorship and provenance

Scholium assumes exactly one researcher for each Triptych. It has no
collaborator, coauthor, or multi-researcher approval model. Agents are
attributed participants, never additional researcher authorities.

Keep independent: Origin and confirmed modified identities; vault role and
location; settlement fingerprint and changed-since-settled state; Critique
authorship; and Discussion turns. Agent origin
does not disappear after Finish, Settle, incorporation, or later editing.

Visible labels stay sparse. Location communicates Analysis, Topic, Work, and
Critique roles; do not compose badges such as **Agent — Analysis**. Put useful
provenance and modification detail in Properties or Research Record and show
warnings only when relevant.

## 3. The Scholium Triptych

### 3.1 Exactly three vaults

| Vault | Research role |
| --- | --- |
| **Analyses** | Reusable analyses of papers and other sources. |
| **Topics** | Reusable concepts, distinctions, positions, debates, objections, and syntheses. |
| **Works** | Researcher-governed plans, arguments, drafts, Critiques, papers, chapters, books, and related writing. |

Analyses and Topics remain reusable across Works in the same philosophical
domain. A substantially different domain uses another complete Triptych.
There is no fourth vault or **All Notes** mode.

Researchers choose all locations. Scholium may recommend a common parent but
never requires or relocates it. Because `.scholium/` sits beside Works, two
Triptychs may not share a Works parent.

### 3.2 Triptych navigation and windows

One configured window belongs to one Triptych and presents three peer Library
scopes: **Analyses | Topics | Works**. Switching scope changes only the browsed
hierarchy and **This Vault** Search; it does not replace the open document.

**File → New Triptych…** opens setup for three new locations; **File → Open
Triptych** opens a registered Triptych separately; **File → New Window** creates
another workspace for the focused Triptych. **Open in New Tab** adds a page
only to the current window's central Document region. One stable document may
appear at most once in that window; opening it again selects its existing page
rather than creating another editor surface. Other windows retain independent
document sessions. Switching tabs changes the active document and its
Apparatus projection, while Library disclosure and selection, Sidebar
visibility, Apparatus visibility, and Apparatus mode remain stable.

**New Triptych…** and missing registration use Bootstrap. Expired access stays
in the configured workspace under one **Restore Access** sheet. The workspace
retains one frame and three-item split across loading/no-note/note states;
notes never resize it. No-note Document presents one restrained, read-only,
VoiceOver-readable empty state while Library remains available through the
Sidebar route; it adds no duplicate action or focus target.

Works folders are researcher-controlled organization, not registered projects.
Scholium supplies no project selector, assignment, completeness check, or
Triptych switcher inside Document.

### 3.3 `.scholium` and machine-local state

The portable directory beside Works contains only:

- manifest and stable identity mappings;
- Triptych Guide and Triptych-local settings or folder preferences;
- per-vault Properties profiles;
- Working Method Skills, Action Profiles, explicit bindings, and portable
  intellectual Research Records under `.scholium/research-records/v1/`;
- user packages at `.scholium/skills/<skill-id>/SKILL.md`.

It may be synchronized through ordinary cloud storage or Git; Scholium never
uploads it automatically.

Application Support owns:

- security-scoped bookmarks and absolute paths, including a separate bookmark
  for the folder containing Works that authorizes sibling `.scholium/` without
  creating a fourth vault, plus the agent application selected for Beta handoff;
- window sessions and vault-qualified Document tabs;
- derived indexes, temporary files, and caches;
- temporary grants, pending permission requests, source bookmarks, transport
  state, derived record indexes, and other machine-local execution data; and
- self-contained Triptych checkpoints.

Production requires the real per-user Application Support root before it may
construct a workspace runtime or any machine-owned store. Failure to resolve,
contain, create, or verify that root never falls back to a temporary directory
and never creates an implicit read-only runtime. QA may substitute only an
explicit isolated root supplied by its launch contract.

### 3.4 Triptych Guide and AI instructions

The agent-facing Guide states vault roles, researcher-owned Works organization,
relation syntax, fidelity/provenance/uncertainty/conflict rules, and safe CLI/
file conventions.

Scholium never creates, overwrites, or silently updates workspace `AGENTS.md`
except an explicitly requested protected one-shot bootstrap. The agent must
resolve Triptych/root, inspect ancestor instructions, validate a minimal
candidate, promote it, and read it back. Any applicable existing file stops the
operation; no overwrite, merge, or shadow is allowed. Only a successful
task-created temporary file may be removed; the result is researcher-owned.

Triptych-local technical instructions are managed only in **Settings →
Research Guidance**. Inventory is discovered from the filesystem and CLI, not
a standing generated index.

### 3.5 Import

Import copies a regular UTF-8 Markdown file directly into the root of the
currently selected Analyses, Topics, or Works vault. The external original
remains unchanged; the imported Note preserves its exact bytes, including BOM,
newline style, malformed or unknown YAML, and final newline. A collision uses
`Name 2.md`, then the next available ordinal, without replacing either file.
The imported file is immediately an ordinary Note of the selected Scope; root-
level Notes require no classification workflow.

## 4. Works folders and organization

Works is an ordinary researcher-defined Markdown hierarchy. Scholium creates
no project membership, required metadata, selector, schema, completeness
warning, or internal template. `Critiques/` alone has special behavior.
