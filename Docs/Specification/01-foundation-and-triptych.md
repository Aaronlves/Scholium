# Specification: Foundation and Triptych

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 1–4.

## 1. Canonical terminology

- A **Scholium Triptych** (**Triptych**) is one research context with exactly
  three vault-backed workspaces: **Analyses**, **Topics**, and **Works**.
- A **Research Action** is a researcher-selected scholarly operation executed
  through the Application API. The defaults are Discuss, Analyze, Synthesize,
  Write, Critique, and Check Fidelity.
- An Action's immutable starting Note is its **Origin**; its intended Note or
  passage is its **Target**. **Focal Materials** guide attention but grant no
  write authority.
- A **Discussion** is a bounded researcher–Agent exchange. Its first successful
  Agent response, or explicit End without a response, creates one attributed
  **Research Record**. Completion implies no acceptance, truth, or settlement.
- A **Research Skill Registration** relates one Action to one
  researcher-owned Skill folder. Scholium owns the relation and availability;
  the folder owns method content. **Philosophical lenses** are ordinary
  Skill-routed references, not registrations or authority.
- An **Action Profile** configures bounded academic inputs and result fields; it
  cannot grant platform capability or permission.
- **Settle** is the researcher's replaceable judgment that one saved fingerprint
  is sufficiently stable for current research. It stores no source version.
- **Critique** is an attributed Agent assessment of one Work. **Fidelity**
  audits an exact revision. Neither silently edits or settles the Note.
- **Connect** presents authored relations. **Attention** presents recoverable
  derived warnings without philosophical judgment.
- **Metadata** is the researcher-owned structured state managed by Scholium.
  About combines selected managed values with authored YAML `summary` and
  `keywords` without becoming another status model.
- A **Run** is one Action's working object. A process-bound **Connection
  Session** attributes local Agent operations; a short-lived **Run Activity
  Ledger** records exact targets, revisions, operations, and outcomes.
- A **Research Record** is the portable intellectual record of one finished
  Discussion or validated Action Run. Records, active Discussions, and Markdown
  annotations remain distinct.

## 2. Product role and authority

### 2.1 Research document first

Scholium is a local-first macOS environment for sustained humanities research.
Exact researcher-governed Markdown is the primary interface and sole writable
research-content authority. Rendered views, YAML projections, Metadata,
indexes, diagnostics, Agent conversations, and Records must not reconstruct or
silently replace it.

The manual core—setup, open, create, read, edit, autosave, Search, Library,
tabs, conflicts, and recovery—must work without Obsidian, Zotero, or Agents.
Scholium supports source-grounded research, writing, annotation, deliberate
Agent collaboration, Settle, Search, Connect, organization, provenance, and
recovery. It is not project management, reference management, permanent AI
chat, or an Obsidian replacement.

### 2.2 Researcher responsibility and optional agent access

The researcher governs the Triptych and may authorize an external Agent through
a Run to create or mutate relevant documents. Scholium does not add a
per-document approval layer inside that task. Every CLI-mediated operation is
bound to the current Session, Run, exact identity, revision, and operation.

Scholium provides:

- stable identities, containment, revision checks, and atomic readback-verified
  writes;
- autosave, external-change detection, conflicts, and interrupted-write
  recovery; and
- Run-bound attribution, exact change evidence, diff, and direct Undo.

Raw external filesystem edits remain unattributed external changes.
Fingerprints identify revisions, not permission. The protected Application
protocol owns capability, safety, operations, Result validation, and recovery;
the registered Skill owns intellectual method. Current bundled Skills are
editable starting points and are never silently restored after researcher
changes.

### 2.3 Authorship and provenance

Each Triptych has one researcher authority. Agents are attributed participants,
not additional researchers. Keep distinct: Origin and modified Notes; vault role
and location; Settlement and changed-since-settled state; Critique authorship;
Discussion turns; and Agent changes. Later completion, editing, incorporation,
or Settle never erases provenance.

Use sparse visible labels. Vault placement communicates Note role; About and
Research Records carry detail, and warnings appear only when actionable.

## 3. The Scholium Triptych

### 3.1 Exactly three vaults

| Vault | Research role |
| --- | --- |
| **Analyses** | Reusable analyses of papers and other sources. |
| **Topics** | Reusable concepts, distinctions, positions, debates, objections, and syntheses. |
| **Works** | Researcher-governed plans, arguments, drafts, Critiques, and finished writing. |

A substantially different domain uses another complete Triptych. There is no
fourth vault or All Notes mode. Researchers choose all locations; Scholium may
recommend a common parent but never relocates them. Two Triptychs may not share
a Works parent because `.scholium/` sits beside Works.

### 3.2 Triptych navigation and windows

A configured window belongs to one Triptych and presents Analyses, Topics, and
Works as peer workspaces, not workflow stages. Each window retains workspace-
specific Library state, Document tabs, selected document, live Document mode,
and Inspector mode. A workspace switch first completes the source-safe
transition, then restores the destination; failure retains the exact origin
buffer and context.

Each stable Note appears at most once per window. Opening it again selects its
existing workspace and tab. Cross-workspace navigation switches atomically.
Other windows retain independent presentation sessions over shared workspace
services. Closing the last tab leaves that workspace with no selected document.

**New Triptych…** creates a new configuration, **Open Triptych** opens a
registered one, and **New Window** opens the focused Triptych. Missing
registration uses Bootstrap; expired access uses a bounded Restore Access route.
Works folders are researcher organization, not registered projects.

### 3.3 `.scholium` and machine-local state

Portable `.scholium/` contains only synchronized control state needed to
interpret the same Triptych:

- manifest and stable identity mappings;
- the Triptych Guide and Triptych-local settings;
- Metadata profiles and identity-keyed Note Metadata;
- Analysis–Zotero bindings and attachment identity/location catalogs;
- Skill registrations, Action Profiles, and Action bindings; and
- portable Research Records.

Application Support contains machine-local access and execution state:
security-scoped bookmarks and paths, window sessions, derived indexes and
caches, pairing/session/Run data, transport state, exact Agent-change evidence,
and recovery artifacts. Markdown/YAML contains only portable research content.
Attachment bytes remain ordinary Finder-owned files.

Portable control state never contains secrets, absolute paths, bookmarks,
indexes, live editor state, or temporary execution state. Scholium never
uploads it automatically. Production must resolve and verify the real per-user
Application Support root before constructing a workspace; only QA may supply an
explicit isolated root.

### 3.4 Triptych Guide and AI instructions

The Guide states vault roles, Works organization, relation syntax,
fidelity/provenance/uncertainty/conflict rules, and safe CLI/file conventions.

Scholium does not create or alter workspace `AGENTS.md` except through an
explicit protected one-shot bootstrap. That operation resolves the exact root,
honors ancestor instructions, refuses any applicable existing file, validates
and reads back the new file, and leaves the result researcher-owned. Settings
owns Triptych-local Research Guidance; discovery reads the filesystem and CLI
rather than a generated index.

### 3.5 Import

Import copies one regular UTF-8 Markdown file to the selected vault root,
preserving exact bytes, BOM, newlines, YAML, and final newline. The original is
unchanged. A collision uses the next `Name N.md` path without replacement.
The result is immediately an ordinary Note in that workspace.

## 4. Works folders and organization

Works is an ordinary researcher-defined Markdown hierarchy. Scholium imposes no
project membership, required metadata, completeness model, or template.
`Critiques/` alone has special behavior under §11.
