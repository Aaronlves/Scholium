# Specification: Foundation and Triptych

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 1–4.

## 1. Canonical terminology

- A **Scholium Triptych** (**Triptych**) is one research context with exactly
  three vault-backed workspaces: **Analyses**, **Topics**, and **Works**.
- **Scholium MCP** is the local application adapter through which an external
  Agent can obtain current Triptych state and perform exact Note operations.
- The **Scholium Core Protocol** is the release-bundled System Skill governing
  source authority, retrieval, permission, mutation scope, and reporting. It
  is not a complete philosophical method.
- A researcher-owned **method Skill** is optional instruction installed in the
  Agent host. Scholium does not register, inspect, execute, or grant authority
  through it.
- An **Agent Change** is one machine-local, exact MCP mutation record used for
  comparison and eligible recovery. It is not a research task, result,
  acceptance, review state, or Research Record.
- **Settle** is the researcher's replaceable judgment that one saved fingerprint
  is sufficiently stable for current research. It stores no source version.
- **Critique** is an attributed Agent assessment of one Work. **Fidelity**
  audits an exact revision. Neither silently edits or settles the Note.
- **Connect** presents authored link occurrences and their annotations.
  **Attention** presents recoverable
  derived warnings without philosophical judgment.
- **Metadata** is the researcher-owned structured state managed by Scholium.
  About combines selected managed values with authored YAML `summary` and
  `keywords` without becoming another status model.
- A **Research Record** is attributed, portable research history for one
  continuing inquiry: a revisable question whose substantive steps must be
  understood together to explain how the current understanding formed,
  changed, or was challenged. It is not a broad topic, one fixed sentence, one
  MCP call, complete chat, operation log, or automatic task result. Record
  prose never establishes truth, researcher adoption, Review, or Settlement.

## 2. Product role and authority

### 2.1 Research document first

Scholium is a local-first macOS environment for sustained humanities research.
Exact researcher-governed Markdown is the primary interface and sole writable
research-content authority. Rendered views, YAML projections, Metadata,
indexes, diagnostics, external Agent output, and Records must not reconstruct
or silently replace it.

The manual core—setup, open, create, read, edit, autosave, Search, Library,
tabs, conflicts, and recovery—must work without Obsidian, Zotero, or Agents.
Scholium supports source-grounded research, writing, annotation, deliberate
Agent collaboration, Settle, Search, Connect, organization, provenance, and
recovery. It is not project management, reference management, permanent AI
chat, or an Obsidian replacement.

### 2.2 Researcher responsibility and optional agent access

The researcher governs the Triptych and instructs an external Agent in the
Agent host. A clear create, modify, or move-to-Trash instruction authorizes only
the named task and targets; Scholium adds no second approval sheet and does not
attempt to reconstruct the conversation. The Core Protocol defaults to
read-only work when no such instruction exists.

Scholium provides:

- stable identities, containment, revision checks, and atomic readback-verified
  writes;
- autosave, external-change detection, conflicts, and interrupted-write
  recovery; and
- current source/index reconciliation plus exact Agent Change evidence, diff,
  and eligible direct Undo.

Raw external filesystem edits remain unattributed external changes.
Fingerprints identify revisions, not permission. Scholium MCP owns tool shape
and application safety; the Core Protocol owns common research boundaries; an
optional researcher-owned Skill owns its declared intellectual method. None
becomes epistemic authority or researcher adoption.

### 2.3 Authorship and provenance

Each Triptych has one researcher authority. Agents are attributed participants,
not additional researchers. Keep distinct: source and modified Notes; vault
role and location; Settlement state; Critique authorship; external conversation;
Research Records; and Agent Changes. Later editing, incorporation, or Settle
never erases provenance.

Use sparse visible labels. Vault placement communicates Note role; About
carries Note detail, and reminders appear only when the current revision
requires a researcher action. Research Records use the separate attributed
history and presentation contract in §§8.6, 13, and 18.5; they never become a
fourth vault, Note status, or Document mode.

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
- Analysis–Zotero bindings and attachment identity/location catalogs; and
- versioned Research Record files under `.scholium/inquiry-records/`.

Application Support contains machine-local access and execution state:
security-scoped bookmarks and paths, window sessions, derived indexes and
caches, local MCP bridge state, exact Agent Change evidence, optional
Record-step/Agent-Change associations, and recovery artifacts. Note
Markdown/YAML remains the sole writable research-content authority; Markdown
strings inside a Record are authority only for that attributed history.
Attachment bytes remain ordinary Finder-owned files.

Portable control state never contains secrets, absolute paths, bookmarks,
indexes, live editor state, or temporary execution state. Scholium never
uploads it automatically. Production must resolve and verify the real per-user
Application Support root before constructing a workspace; only QA may supply an
explicit isolated root.

### 3.4 Triptych Guide and agent instructions

The Guide states vault roles, Works organization, annotated-link syntax,
fidelity/provenance/uncertainty/conflict rules, and safe external-edit
conventions. It remains researcher-owned research context, not the MCP or Core
Protocol.

Scholium ships one protected, project-neutral `scholium-core-protocol` Skill.
It does not create or alter workspace `AGENTS.md`/`CLAUDE.md`, scan arbitrary
Skill locations, or register researcher methods. Settings reveals the bundled
folder and copies host-specific user-scope setup commands; the researcher owns
whether and how optional method Skills are installed.

### 3.5 Import

Import copies one regular UTF-8 Markdown file to the selected vault root,
preserving exact bytes, BOM, newlines, YAML, and final newline. The original is
unchanged. A collision uses the next `Name N.md` path without replacement.
The result is immediately an ordinary Note in that workspace.

## 4. Works folders and organization

Works is an ordinary researcher-defined Markdown hierarchy. Scholium imposes no
project membership, required metadata, completeness model, or template.
`Critiques/` alone has special behavior under §11.
