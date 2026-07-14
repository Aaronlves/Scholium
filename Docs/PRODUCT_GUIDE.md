# Scholium Product Guide

**Status:** Authoritative target-product guide

**Applies to:** Scholium for macOS and its agent-facing CLI

**Canonicalized:** 2026-07-14

**Purpose:** Define Scholium's product role, Triptych model, research workflows, collaboration boundaries, and stable feature decisions.

This guide is authoritative for Scholium's intended role and feature behavior. It does not claim that every rule is implemented. The repository `README.md`, live source, and executable tests establish current reachability; `DESIGN_HANDBOOK.md` remains authoritative for stable interface design and exact target action language. When current code differs from this guide, treat the difference as migration work rather than an alternative product rule.

This guide's direct-agent-edit decision supersedes older product language requiring every agent change to remain a Proposal or unapplied Revision. Legacy app-owned records created by those retired workflows remain ordinary files for the researcher to archive manually; Scholium does not delete or silently rewrite them.

## 1. Canonical terminology

- **Scholium Triptych** is the full name of one configured research workspace; **Triptych** is its short name.
- Every Triptych contains exactly three vaults: **Analyses**, **Topics**, and **Works**. Their ordinary documents are an **Analysis**, **Topic**, and **Work**.
- **Unclassified** is temporary staging for imported Triptych-relevant Markdown that has not yet been assigned to one of the three vaults.
- **Dialogue** is a concise scholarly record of researcher Comments, agent Responses, and follow-up exchanges. It may generate transient copyable instructions for an external agent, but it is not a chat client, task manager, or permission system.
- **Critique** is an attributed agent assessment of one Work. It does not replace its target.
- **Human Review** is the researcher's fingerprint-bound review of an Analysis or Topic.
- **Qualification** is the researcher's Qualified or Unqualified verdict, recorded only through Human Review.
- **Attention** contains derived warnings and recoverable research issues. Attention does not make philosophical judgments.
- **Connections** are source-located neutral, support, or incompatibility relations.
- **Canvas** is an optional spatial view of notes and Connections.
- **Properties** is the human-facing frontmatter presentation.
- **Note History** contains the note's Human Review, Dialogue, Critique association where applicable, and available checkpoint versions. These record types remain visibly distinct.
- **Checkpoint** is a self-contained, fingerprint-bound snapshot of the complete Triptych. It is distinct from editor Undo. Permanent deletion must purge the deleted note and its associated records from checkpoint copies or invalidate copies that cannot be scrubbed safely.

There is no formal **Revision** artifact, Proposal workflow, Research Task, or Research Session in the target product. When used, an agent edits researcher-authorized files directly. The ordinary word “revision” may still describe an edit or a Critique section such as Revision Priorities.

## 2. Product role and authority

### 2.1 Research document first

Scholium is a local-first macOS document editor with research intelligence for sustained humanities research, especially philosophy. Its primary object is the research document—not a dashboard, task, workflow state, or agent conversation.

Scholium helps a researcher read, write, comment, review, search, connect, organize, recover, and trace source-grounded work. It is not a general project manager, reference manager, permanent AI chat interface, or a general-purpose Obsidian replacement in feature breadth. This does not make Obsidian a dependency: a researcher must be able to complete Scholium's core academic workflow in Scholium itself. Obsidian is optional interoperability for researchers who already use it, not a prerequisite for setup, source analysis, Topic synthesis, Works drafting, Review, comments, Dialogue, Critique, Connections, Search, Attention, checkpoints, or recovery.

### 2.2 Researcher responsibility and optional agent access

The researcher governs the Triptych and is expected to manage the academic
workflow herself when she chooses. She may optionally instruct an external
agent to create, edit, rename, move, organize, or delete notes directly through
filesystem or CLI tools. Scholium does not maintain a separate authorization
scope, require an app-issued permission token, require a proposal, or make an
agent necessary for setup, source analysis, Topic synthesis, Works writing,
Human Review, comments, search, Connections, checkpoints, or recovery.

The current researcher instruction defines the permitted task and scope for
optional agent work. The agent is responsible for following it. No permission
persists beyond that task. Dialogue and Critique are optional extensions, not
conditions for a note to be reviewed, written, or settled.

Scholium supplies safety tools without taking responsibility away from the researcher:

- exact target paths and stable identities;
- fingerprints for revision checks, not authorization;
- autosave and external-change detection;
- conflicts when a dirty local buffer and external edit diverge;
- automatic and manual Triptych checkpoints;
- comparison and restoration.

If a researcher authorizes extensive agent work without an appropriate checkpoint, Scholium does not promise recovery.

Research skills may use these primitives through Dialogue or other bounded
integrations, but they are not required for the core app and Scholium does not
certify their philosophical conclusions. Scholium may bundle default skills
that explain how an agent should work with Scholium. Researchers own and may
edit the skills they choose to use and remain responsible for their content and
methodological consequences.

### 2.3 Authorship and provenance

Agent origin does not disappear merely because material is reviewed, qualified, incorporated, or edited later. Keep these concepts independent:

- origin or last modifier;
- vault role and location;
- Human Review and qualification;
- current fingerprint and changed-since-review state;
- Critique authorship;
- app-owned comments and Dialogue replies.

Keep visible UI labels sparse. Location communicates Analysis, Topic, Work, and Critique roles. Do not add composed badges such as **Agent · Analysis** or **Agent · Revision**. Show provenance and modification information in Properties or History when useful; show temporary warnings only when relevant.

## 3. The Scholium Triptych

### 3.1 Exactly three vaults

| Vault | Research role |
|---|---|
| **Analyses** | Reusable source analyses for papers and other research materials. |
| **Topics** | Reusable topic-centred knowledge: concepts, terminology, distinctions, positions, debates, objections, and synthesis. |
| **Works** | Researcher-governed writing, planning notes, arguments, Critiques, drafts, papers, chapters, books, and related material. |

Analyses and Topics remain reusable across every folder and body of writing in Works when they concern the same philosophical domain. A substantially different domain uses another complete Triptych. Scholium provides no fourth vault and no alternative **All Notes** mode.

Researchers choose the three vault locations. Scholium recommends—but does not require—placing them under one parent. It never relocates a vault automatically.

Because each Triptych has one portable `.scholium/` directory beside Works, the Works roots of two different Triptychs must not share the same parent directory. Scholium rejects that configuration instead of allowing two Triptychs to overwrite one portable control directory.

### 3.2 Triptych navigation and windows

Scholium presents **Analyses | Topics | Works** as three peer tabs without replacing the established document-first, three-column window. Different Triptychs may be open simultaneously in separate windows. Each window owns its tabs, selection, document modes, history, inspector, scroll locations, search state, and current Canvas while shared vault services remain coherent.

One window belongs to one complete Triptych. **File → New Triptych…** opens setup for three new locations, **File → Open Triptych** opens a registered Triptych in its own window, and **File → New Window** opens another independent window for the focused Triptych. Scholium does not put a Triptych switcher inside the document area or confuse a Triptych with a Works folder.

Works folders are ordinary researcher-controlled folders. A researcher may use one folder for each paper, chapter, book, dissertation, or other project, but Scholium does not register, select, assign, validate, or otherwise manage projects. No project selector appears below the Triptych navigation.

### 3.3 `.scholium` and machine-local state

A single hidden `.scholium/` control directory sits beside Works. It contains small, portable Triptych information:

- Triptych manifest and stable identity mappings;
- Triptych Guide or related instruction state;
- Triptych-local folder and organization preferences that do not assign project membership;
- Triptych-local settings;
- per-vault Properties configurations;
- editable prompt templates and their Triptych-local workflow assignments;
- Triptych-local user skill packages under
  `.scholium/skills/<skill-id>/SKILL.md`;
- imported Unclassified Markdown under `.scholium/unclassified/`.

The researcher may synchronize `.scholium` through ordinary cloud storage or Git. Scholium never uploads it automatically.

Machine-specific and replaceable state remains in Application Support:

- security-scoped bookmarks and absolute paths, including the separate bookmark
  for the folder containing Works that authorizes the sibling `.scholium/`
  directory without creating a fourth vault;
- window sessions and open tabs;
- search, link, graph, and render indexes;
- temporary files and caches;
- app-owned Human Review, comments, and Dialogue replies;
- self-contained Triptych checkpoints.

### 3.4 Triptych Guide and AI instructions

Scholium provides one concise agent-facing guide explaining:

- the three selected vaults and their roles;
- the Works folder organization and any ordinary `kind` metadata the researcher chose to record;
- canonical relation syntax;
- source-fidelity, provenance, uncertainty, and conflict rules;
- CLI discovery and safe file-operation conventions.

If a suitable `AGENTS.md` does not exist, Scholium may create one only after preview and researcher approval. If an `AGENTS.md` already exists, Scholium does not rewrite it. Triptych-local technical instructions are managed only in **Settings → Research Guidance**. Dynamic inventory comes from the filesystem and CLI rather than a standing generated index.

### 3.5 Import and Unclassified

Scholium imports one or more Markdown files by copying them into `.scholium/unclassified/`; the originals remain unchanged. An imported note remains readable and editable but does not participate in role-specific Review, qualification, Critique, or Properties behavior until the researcher classifies it as Analysis, Topic, or Work. Classification moves the imported copy into the selected vault.

Irrelevant Markdown should not be imported into the Triptych.

## 4. Works folders and organization

Scholium treats the Works vault as an ordinary researcher-organized Markdown hierarchy. A folder may represent a paper, article, chapter, book, dissertation, or any other grouping, but that meaning belongs to the researcher and is not an app-managed project record. Scholium does not maintain project membership, require project metadata, offer a project selector, or warn about project completeness.

The researcher may create an organization such as:

```text
<Project>/
├── Concepts/
├── Terminology/
├── Cases/
├── Questions/
├── Views and Camps/
├── For/
├── Against/
├── Arguments/
├── Objections/
├── Replies/
├── Critiques/
└── Drafts/
```

This is an example, not a structure Scholium creates or manages. The folders are not formal note kinds or evidential classifications. The researcher may rename, remove, add, and reorganize them at will. Scholium imposes no folder-specific schema, mandatory template, one-note-per-concept rule, or required internal section structure. `Critiques/` is the only folder with special Scholium behavior.

## 5. Common note capabilities

Analysis, Topic, and ordinary Work notes support:

- Read, Live Preview, and Source over one exact Markdown buffer;
- autosaved editing without an ordinary Save button;
- create, duplicate, import, rename, move, reveal in Finder, Set Aside, Trash, restore, and permanent deletion;
- folder organization through the app or external tools;
- exact-source preservation, conflict detection, and atomic app writes;
- incoming and outgoing Connections with source locations and ambiguity;
- line-level and whole-note researcher comments;
- one-note or multi-note Dialogue records with optional transient copyable
  instructions for an external agent;
- role-aware Properties;
- one Search field with **Triptych** and **This Note** modes, plus Quick Open,
  Recent Notes, filters, and Attention;
- Note History and available checkpoint comparison.

Critique bodies are read-only inside Scholium but remain ordinary Markdown files that external editors may modify. Scholium does not enforce filesystem-level read-only permissions.

### 5.1 Document modes and YAML

- **Read** renders the committed note for reading, selection, navigation, and commenting.
- **Live Preview** edits the exact Markdown body through a visual projection. It does not display YAML frontmatter or a line-number gutter.
- **Source** exposes and edits the complete Markdown and YAML and may display line numbers.

Only Read and Live Preview receive a direct keyboard toggle. Source is entered through the document-mode pull-down menu so accidental entry is less likely. Source mode may edit protected or machine-facing YAML directly; the researcher assumes responsibility for those exact-source edits. Scholium still validates and preserves bytes without whole-frontmatter reserialization.

### 5.2 Properties

Scholium provides fixed starting defaults for Analyses, Topics, and Works. The researcher may configure each vault independently:

- visible fields;
- display order;
- disclosure state;
- human-editable allowlist.

The configuration applies vault-wide. There are no folder-level or note-level Properties layouts. Identity, fingerprints, provenance, and automatically maintained fields remain protected in the structured Properties interface, although Source mode can expose and edit the exact YAML.

### 5.3 Duplicate, rename, and identity

Every note has a stable app-owned identity. Paths are locations, not identity.

- A duplicate receives a new identity.
- Human Review and qualification reset on the duplicate.
- The duplicate records its source note.
- Confirmed moves and renames preserve comments, History, Critique association, and other app-owned records.
- Scholium automatically updates resolved incoming links after an app-performed rename or move.
- When an external rename or sync conflict cannot be rebound confidently, Scholium keeps the note readable but blocks identity-dependent mutations, Review, History restore, and comment attachment until the researcher confirms the identity.

## 6. Note location, Set Aside, and Trash

Scholium has no generic note lifecycle property or status-advance control. A note's location determines whether it is in the active Triptych, Set Aside, or Trash.

- **Set Aside** is a direct, reversible action. Scholium asks for no reason and stores no failure or superseded status. Set-aside notes remain readable and recoverable but are excluded from ordinary search, synthesis, Critique, and agent context unless explicitly included.
- **Move to Trash** moves the note into the relevant Trash area without immediately erasing it. Trashed notes are excluded from ordinary search, Connections, agent context, and research workflows.
- **Cancel** leaves the note unchanged.
- Permanent deletion is explicit. It purges the note's associated comments,
  Dialogue records, associated Critique document or association, Human Review
  records, and other note-specific app state. It also purges the note and
  those records from every checkpoint copy. A checkpoint that cannot be
  scrubbed safely is invalidated and removed rather than retained as a
  recoverable copy. If a shared multi-note Dialogue cannot be partitioned
  safely, the shared record is deleted in full.

Reviews, comments, Dialogue entries, Critique links, and other note-specific
records follow the stable identity into Set Aside or Trash. They remain while
the note remains recoverable. Permanent deletion removes them and all
recoverable checkpoint copies according to the rule above.

## 7. Human Review and comments

### 7.1 Scope and completion

Human Review applies to Analyses and Topics. Works use Critique instead of qualification.

A completed Human Review requires:

- a Qualified or Unqualified verdict;
- a non-empty Review Note of at most 500 characters.

The sheet shows a character counter and never truncates the note automatically. **Complete Review** remains unavailable until both conditions are satisfied. **Save as Draft** preserves an incomplete review without marking the fingerprint reviewed. **Cancel** discards unsaved changes to the sheet.

The Review control displays only the applicable state: **Review**, **Continue Review**, **Qualified**, or **Unqualified**. Qualification can be changed only through Review.

### 7.2 App-owned comments

Researcher comments remain app-owned and outside the Markdown source. A selection comment binds to:

- stable note identity;
- exact reviewed fingerprint;
- UTF-8 and UTF-16 source range and original line;
- selected quotation;
- surrounding context.

Read and editor selections create the same record. Scholium renders a restrained annotation without inserting hidden Markdown. After edits, it reattaches only when quotation and context identify one reliable location; otherwise it marks the comment **Needs Reattachment**.

A whole-note comment has no source span. The researcher may edit, delete, resolve, or reattach a comment. The agent may reply but cannot resolve a researcher comment.

### 7.3 Unqualified Analyses

An Unqualified Analysis remains available for reading, editing, linking, search, Topic integration, Work Critique, and further agent work. Scholium does not move it automatically or forbid its use.

Scholium detects explicit scholarly reliance on an Unqualified Analysis and presents a source-anchored Attention warning. A neutral `[[Analysis]]` Connection alone is not reliance. A citation, explicit support relation, or recognized source-bearing use may trigger the warning. The warning identifies the use and never blocks editing or agent work. It clears when qualification or usage changes.

## 8. Dialogue and direct agent work

### 8.1 One general Dialogue mechanism

Dialogue is a concise scholarly interaction record with optional transient
instruction generation. It does not communicate with an agent process,
maintain a global chat, classify tasks, or constrain what a researcher may ask
an agent to do. An external agent is optional.

The researcher selects one or several notes and provides one overall Comment or
instruction. The selected notes are focal context, not an authorization
boundary. Scholium may generate transient copyable instructions containing, as
applicable:

- researcher instruction;
- selected note names, vault-relative paths, and advisory fingerprints;
- selected passages, source lines, and included researcher comments;
- Triptych context, selected note paths, and relevant ordinary Work metadata such as `kind` when present;
- relevant linked-note information;
- requested destination and applicable editing rules;
- permission to inspect and directly modify relevant Triptych files.

The agent may perform any requested work it is capable of performing. Scholium
does not provide specialized request types for re-analysis, integration,
harmonization, or other activities. The generated instructions are transport
material, not the permanent scholarly record. Scholium does not require the
researcher to preserve technical prompts, hidden instructions, model
parameters, token counts, or paragraph-level AI provenance.

Dialogue shows the selected notes, included Comments, researcher instruction,
and consequential context that the researcher needs to verify. It does not
show, preview, select, or permit one-run editing of the active prompt template
or the assembled technical instructions. **Copy Instructions for Agent** uses
the active Dialogue template configured in Settings.

When an agent changes notes, its default researcher-facing response is a
concise academic change summary. It should identify an unresolved question or
required researcher review when relevant; routine file-operation details are
secondary. The note remains the researcher's eventual decision.

Before copying agent instructions, Scholium completes pending autosaves and creates an automatic checkpoint named **Before Agent Work**. The researcher remains free to instruct an agent outside Scholium or without making a manual checkpoint.

### 8.2 Note History and replies

Scholium provides no separate global Dialogue History. Every selected note
receives the Dialogue entry in its own Note History. For a multi-note Dialogue,
each selected note shows the same:

- researcher Comments and follow-up exchanges;
- selected-note list;
- applicable checkpoint;
- agent replies.

Dialogue entries are chronological scholarly records, not document versions,
technical prompt logs, or per-response approval queues. They cannot be
restored as document versions. The note itself expresses the researcher's
eventual decision.

A local agent may reply through the `scholium dialogue` CLI. The CLI validates request and comment identities and writes immutable, attributed reply records under Application Support; the agent never edits the review database directly. Replies may address the instruction overall, one selected note, or one researcher comment. Only the researcher resolves comments.

An agent without local CLI access can still use the copied prompt. Its reply must be returned manually if the researcher wants it recorded in Note History.

The researcher may use Dialogue without an external agent as a concise record
of her own Comments and decisions. Richer comment-preservation choices and
reflection modules remain future design work.

### 8.3 Research Guidance, prompt templates, and skills

**Settings → Research Guidance** is the only Scholium surface that displays or
edits prompt templates. Each supported workflow has one active Triptych-local
template. Researchers may create, duplicate, rename, delete, and assign
templates there. Editing a Scholium default creates a researcher-owned
customization; **Reset to Scholium Default** restores the bundled baseline
without silently overwriting another researcher-created template.

Research Guidance also contains a distinct **Skills** collection. It shows
bundled Scholium skills and Triptych-local user skills discovered only from
`.scholium/skills/<skill-id>/SKILL.md`. A user skill is manageable when its
folder contains a structurally valid editable `SKILL.md`; Scholium does not
search research notes, arbitrary filesystem locations, `~/.codex/skills`, or
another agent's global configuration. **Reveal Skills Folder** opens the
supported Triptych-local location so the researcher can place a skill there.

Researchers may inspect and edit user-owned `SKILL.md` source, duplicate a
bundled skill into the Triptych, rename or delete a Triptych-local skill, and
reset a customized bundled skill. A malformed skill remains visible with a
structural error but is unavailable for instruction assembly until corrected.
Validation concerns package structure only; Scholium does not judge a skill's
philosophical quality, accuracy, or suitability.

Dialogue, Critique, and any future approved research workflow expose scholarly
inputs and scope, not prompt mechanics. They do not display template names,
bodies, placeholders, previews, pickers, or editors. A restrained text action
opens **Research Guidance** directly at the applicable template. If the active
template is structurally invalid, Scholium preserves the current workflow
inputs, explains that the template needs attention, opens the same Settings
destination, and does not generate or copy instructions until the problem is
resolved.

Prompt templates configure existing workflows; skills provide reusable agent
guidance. Managing either one does not create specialized Dialogue request
types, a workflow-local skill picker, an agent runtime, hidden authorization,
or a plugin marketplace. Technical template text, skill source, and assembled
transport instructions do not become part of the scholarly Dialogue record.

### 8.4 External edits and conflicts

When an external agent or editor changes a clean open note, Scholium quietly refreshes it from disk. When Scholium has an unsaved local buffer, it preserves that buffer and presents a conflict rather than overwriting either version. Fingerprints are used for conflict detection, Review binding, checkpoint comparison, and restoration integrity; they are not permission tokens.

## 9. Analyses workflow

1. The researcher creates or imports an Analysis and writes or revises it in Scholium, using a paper or other source when available.
2. The researcher reads the Analysis, follows linked Topics and Works, and adds line or whole-note comments.
3. The researcher completes Human Review or saves a review draft.
4. If desired, the researcher uses Dialogue to ask an external agent for analysis or revision. Zotero may provide bounded metadata when the researcher uses it, but neither Zotero nor an agent is required.
5. The researcher decides whether to incorporate any returned work and may update materially affected Topics or Works herself or through an optional agent.

An Analysis remains reusable for future Works in the same philosophical domain. Qualification records the researcher's judgment of one exact fingerprint; it does not change authorship.

## 10. Topics workflow

1. The researcher creates or updates a Topic from relevant Analyses and identifies the Analyses actually used.
2. The Topic preserves disagreements, limitations, and uncertainty rather than flattening sources into consensus.
3. The researcher reads the Topic to gain knowledge and follows Connections to Analyses and Works.
4. The researcher adds comments and completes Human Review or saves a review draft.
5. If desired, Dialogue hands selected-note context and Comments to an external agent for optional synthesis or revision.
6. The researcher decides whether to update the Topic or other materially affected Triptych notes.

Scholium does not automatically merge a newly qualified Analysis into Topics. It may report that relevant reviewed material exists. Neutral or transitive Connections never establish integration or support.

Topics do not receive a separate persistent Critique feature. A Dialogue instruction may ask an agent to assess a Topic's accuracy, coverage, or organization, but the normal result is direct improvement of the Topic.

## 11. Works and Critique

### 11.1 Researcher-governed Works

Works are researcher-governed. The researcher may create a scaffold, write,
revise, and organize a Work herself. An agent may create a scaffold or
directly edit a Work when instructed, but Critique remains visibly separate
from researcher prose. Works do not use Human Review qualification, and a
Critique is optional.

### 11.2 Critique target and storage

- A Critique normally targets one Work note.
- Multi-note or folder-spanning assessment uses the general multi-note Dialogue mechanism.
- Each Work has at most one current Critique document.
- Later Critique rounds update that document; earlier states remain available through checkpoint-backed Version History.
- Critiques live in the designated `Critiques/` area of Works. Arbitrary Markdown elsewhere is not classified as Critique from metadata alone.
- Scholium presents the body read-only but permits rename, movement within Critiques, Set Aside, restoration, Trash, and Reveal in Finder.
- External editors and agents may edit the Critique file directly.

### 11.3 Request Critique

**Request Critique** lets the researcher choose:

- **Overall Critique**;
- **Specific Comments**;
- **Both**;
- an optional selection, line range, section, focus, or disciplinary lens as
  scholarly scope.

The default overall prompt asks the agent to assess important claims, premises, and arguments against relevant Analyses and Topics. This source-trace assessment is part of Critique, not an automatic Scholium diagnostic. A specific Critique remains bounded to the selected passage and comments unless the researcher requests broader assessment.

The Critique workflow uses the active Triptych-wide Critique template without
showing or permitting one-run adjustment of that template or the assembled
technical instructions. It states that Critiques use the template configured
for the Triptych and provides **Edit Critique Template…**, which opens
**Settings → Research Guidance → Prompt Templates → Critique**. Settings
provides documented placeholders, structural validation, preview, template
management, and **Reset to Scholium Default**.

### 11.4 Critique form

A Critique uses attributed structured prose with these default sections:

1. Overall Assessment
2. Strengths
3. Major Concerns
4. Source Support
5. Objections and Alternatives
6. Revision Priorities
7. Specific Findings
8. Materials Consulted and Limitations

Specific source-related findings may use **Traced**, **Untraced**, **Disputed**, or **Beyond Sources**. These remain attributed agent judgments, not Scholium diagnostics. Scholium does not calculate trace-coverage scores or apply Qualified/Unqualified verdicts to Works.

Specific findings initially remain in the Critique document. Each records the target Work, target fingerprint, heading or section when available, original line, and a short quotation. Selecting the target opens the relevant Work passage. A fingerprint mismatch marks the finding as referring to an earlier version. Overlaying Critique findings on the Work is deferred until human-comment anchoring is proven reliable.

## 12. Connections and Canvas

For source text in note A:

| Markdown | Normalized meaning |
|---|---|
| `[[B]]` | neutral, undirected A—B |
| `+[[B]]` | A supports B |
| `-[[B]]` | B supports A |
| `?[[B]]` | symmetric incompatibility A—B |

These four forms completely replace legacy typed-link syntax. Aliases, headings, and fragments remain supported. Legacy bytes remain untouched and receive diagnostics only; Scholium does not offer automatic conversion.

Scholium never infers philosophical support from keywords, proximity, folder membership, Canvas placement, or multi-hop paths. Neutral and transitive paths remain connections rather than evidence. Incoming and Outgoing views expose direction and exact source location without filling the interface with permanent relation badges.

Canvas remains an optional view-only spatial aid with an accessible list equivalent. It does not author relations or convert Canvas edges into Markdown.

## 13. Search and Attention

Scholium uses one Search field with exactly two modes:

- **Triptych** searches notes in the active **Analyses**, **Topics**, or
  **Works** segment. The researcher searches another vault by selecting its
  peer segment; the current query remains in the field.
- **This Note** searches occurrences within the open note.

Do not add Current Vault, All Workspace, Selected Roles, or other visible
search-scope modes. Do not present a separate in-note Find field or a separate
advanced-search workspace. The standard Find command activates **This Note**
in the shared Search field.

Quick Open remains a separate title, path, and alias navigation command.
Recent Notes is a per-window, most-recent-first navigation command under
**Navigate**. It remains distinct from chronological Back/Forward history,
open tabs, Search, and Quick Open, and it does not add permanent sidebar or
toolbar chrome.
The document-local Research inspector and Attention remain contextual and
derived surfaces rather than Search modes. Search results are retrieval leads,
not evidence.

Attention may report:

- no links, no explicit relation, or no integration as possible-orphan conditions;
- Changed Since Review;
- Broken Connections;
- explicit reliance on an Unqualified Analysis;
- malformed metadata or unresolved identity where applicable.

Scholium does not infer **Superseded** status and does not use file age alone as Attention. There are no nondismissible warnings. Dismissal duration is configurable in Settings and defaults to seven days. The researcher retains responsibility for every judgment.

Scholium does not implement an automatic untraced-premise diagnostic. Source-trace judgment belongs to an attributed Work Critique.

## 14. Checkpoints, versions, and recovery

Ordinary autosaves do not create visible versions.

Immediately before Scholium generates and copies researcher instructions for an agent, it creates a named, fingerprint-bound checkpoint of the entire Triptych. The researcher may also choose **Create Checkpoint…** at any time, especially before substantial external work.

Each checkpoint:

- is self-contained;
- contains Analyses, Topics, Works, and the portable Triptych configuration needed to interpret them;
- is stored outside the vaults;
- may use filesystem cloning internally, but never depends on another checkpoint;
- remains usable if another checkpoint is moved or deleted in Finder.

Automatic checkpoints retain the latest ten. Manual checkpoints remain until the researcher deletes them.

Scholium provides:

- **Create Checkpoint…**;
- **Restore from Checkpoint…**;
- **Reveal Checkpoints in Finder**.

The restore interface shows files created, changed, moved, or deleted since the selected checkpoint. The researcher may restore selected notes or the entire Triptych. Files created after the checkpoint move to Trash during a full rollback rather than being permanently deleted.

Scholium provides no checkpoint-management screen and no proprietary backup
format. Researchers manage checkpoint folders through Finder. Export to
document, HTML, PDF, or DOCX is deferred beyond the experimental release and
is not a permanent product prohibition.

Editor **Undo** reverses editing operations in the current session. **Restore This Version** creates a new current version through the same conflict-aware repository path; it does not rewrite history silently.

## 15. Zotero integration

### 15.1 Local read-only API

Zotero integration is optional. When the researcher enables it, Scholium reads
Zotero through Zotero's localhost API. The researcher does not deploy a server,
provide a password, or configure the online Web API. The absence of Zotero
does not block source analysis, Topic synthesis, Works writing, Review, or
recovery.

**Settings → Integrations → Zotero** provides:

- connection status;
- **Open Zotero**;
- **Test Connection**;
- **Refresh Library Information**;
- **Forget Cached Zotero Data**;
- last successful connection time;
- a concise local, read-only privacy explanation.

If access is disabled, Scholium instructs the researcher to enable **Allow other applications on this computer to communicate with Zotero** in Zotero's Advanced settings.

### 15.2 Matching and presentation

Prefer a stable `zotero_item_key`. If absent, match in this order:

1. DOI or ISBN;
2. citation key;
3. exact title plus author and year;
4. researcher selection among ambiguous candidates.

Never silently choose an ambiguous match. Once confirmed, Scholium may write the Zotero item key through the permitted property path.

For an Analysis, the Research inspector's compact **Zotero Source** section shows only the Zotero item identified by that Analysis. For a Topic or Work, **Zotero Sources from Linked Analyses** includes only Analysis notes named by links written in the currently opened Topic or Work and carrying a Zotero item key. Incoming backlinks do not qualify. Scholium does not crawl bibliography citations, transitive Connections, Zotero children, Unclassified notes, or the wider library. If several linked Analyses identify the same Zotero item, the paper appears once.

For each included paper, the section shows:

- title, authors, and year;
- journal, book, or collection;
- volume, issue, and pages when available;
- DOI, ISBN, or another primary identifier;
- citation key;

An expanded section may show abstract, publisher, edition, URL, collections, and Zotero modification date. Technical keys remain out of ordinary UI labels.

The only source action is **Open in Zotero**. Scholium does not enumerate, download, reveal, or open Zotero attachments. PDF reading and attachment management remain in Zotero.

If Zotero is unavailable, Scholium names the exact condition and may show cached metadata labelled with its retrieval time. Scholium never modifies Zotero metadata, tags, annotations, files, or the live SQLite database.

## 16. Onboarding and protected researcher additions

On first launch, Scholium asks the researcher to select Analyses, Topics, and Works locations. Scholium does not ask the researcher to register a project or choose an app-managed Works structure. This onboarding is setup, not a permanent dashboard. Later, **Manage Triptychs…** in Settings lists complete registered Triptychs, edits the three locations of the selected Triptych, creates another Triptych, and opens the selected Triptych in a separate window.

The following researcher-authored additions are preserved verbatim. Their canonical resolutions appear immediately below each passage.

**My addition:** so maybe we can use [a pull-down button](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons) under the Works tab (when selected) for users to choose between projects? And we should use Tab style for the Triptych. And [the pull-down button](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons) should be hidden when there is only 1 project.

**Resolution:** Analyses, Topics, and Works are peer tabs. The later canonical decision supersedes the proposed project pull-down: Works folders are researcher-controlled organization, and Scholium does not display or manage a project selector.

**My addition:**  Scholium should tell users that discarded notes could be stored up for agents to learn from failure. So when the user is to delete one note, give the user options to choose whether she is going to delete it or keep it as failure (the `delete` option should be colored as red, `keep it as failure` colored as blue; there should also be a cancel option in the default color.). You should rename them so that the options are intuitive.

**Resolution:** The final actions are **Set Aside**, **Move to Trash**, and **Cancel**. Set Aside preserves a note without labelling it a failure. Destructive meaning must be conveyed by label and role rather than color alone; system color is only a redundant cue.

**My Addition:** Users mark notes as qualified or unqualified via the `review` button. Users are able to link unqualified analysis, but there should be warnings or attentions provided by Scholium.

**Resolution:** Qualification occurs only through Human Review. Unqualified Analyses remain usable, while explicit reliance produces source-anchored Attention.

**My Addition:** Users mark notes as qualified or unqualified only via the Review process.

**Resolution:** This is binding for Analyses and Topics. Works do not use qualification.

**My Addition:** When the user opens this app for the first time, Scholium should provide a bootstrap page for the user to deploy her workspace, in which Scholium should ask the user to choose between using the recommended organization or using her own, or set it later. Maybe the bootstrap page comes out after the user selected her workspace.

**Resolution:** First-run setup selects only the three Triptych locations. The researcher organizes Works with ordinary folders; Scholium does not configure or manage projects.

## 17. Consolidation requirements

Remove or consolidate obsolete parallel implementations:

- Remove the unreachable legacy `AgentSkillService`/`AgentSkill`; any new skill
  management follows the file-backed Research Guidance contract in section
  8.3 rather than reviving the obsolete implementation.
- Remove unused `IndexGenerator` and generated `_index.md`, `_agent-index.json`, and `_agent-context.json`; a researcher-authored `index.md` remains an ordinary note.
- Remove unused `NoteViewModel`, obsolete render cache, and handwritten legacy renderer after fallback acceptance.
- Remove only the unused `selectedKB` state; retain vault assignments, bookmarks, and independently selected locations.
- Never hydrate writable notes from partial caches.
- Use one semantic Markdown/Connection graph authority.
- Use one atomic Human Review store.
- Use one shared search/filter/Attention contract.
- Use one Vaults settings pane for the three required roots.
- Use shared vault repositories, watchers, indexes, graph, review, CSS, and Zotero services; keep window presentation state independent.
- Remove Proposal, Revision, Research Task, Research Session, Agent Assessment, and legacy Agent Review UI after migrating reachable data into direct editing, Dialogue, Critique, Note History, or checkpoints as appropriate.

## 18. Permanent boundaries and deferred capabilities

Do not add:

- a permanent LLM chat sidebar;
- app-enforced agent task authorization or proposal approval;
- automatic philosophical support, settlement, sufficiency, truth, or prose-authorization judgments;
- a fourth vault or All Notes mode;
- a generic task manager or plugin marketplace;
- a Zotero replacement or embedded PDF reader;
- automatic untraced-premise verdicts;
- Canvas authoring or Canvas-edge-to-Markdown conversion;
- a proprietary backup-export format;
- complete arbitrary Obsidian-theme compatibility;
- bundled general instructions that purport to teach researchers how to
  conduct philosophy; researcher-authored skills remain the researcher's
  responsibility.

Deferred beyond the experimental release, but not permanently rejected:

- document, project, HTML, PDF, or DOCX export;
- additional bundled discipline-specific skills and skill-driven workflows;
  and
- richer Dialogue comment-preservation and reflection modes.

Editable prompt templates and file-backed skills are Research Guidance, not a
plugin marketplace. Their Settings-only management does not create a
specialized request taxonomy, an embedded agent runtime, or automatic
philosophical authority.

Use Finder for authoritative Markdown, attachments, and checkpoint folders. Use
Zotero for bibliographic management and PDF reading when the researcher wants
it. Use external agents for Dialogue or other open-ended work only when the
researcher chooses to do so.

## 19. Implementation sequence and migration boundary

This guide changes target behavior, not existing vault bytes or app-owned records. Implement and migrate deliberately:

1. Remove obsolete Proposal/Revision/Research Session assumptions from product documents and UI contracts without deleting existing user data.
2. Complete stable note identity, exact-source autosave, external-edit conflict handling, and shared multiwindow ownership.
3. Implement safe create, duplicate, import, rename, move, Set Aside, Trash, automatic incoming-link updates, and identity recovery.
4. Unify Human Review, comments, qualification, Note History, and the vault-wide Properties configuration.
5. Implement concise one-note and multi-note Dialogue records, optional transient agent-instruction generation, automatic pre-agent checkpoints, and CLI replies.
6. Implement self-contained manual/automatic checkpoints, Finder reveal, comparison, and selective/full restoration.
7. Remove app-managed Works projects while preserving existing files, then
   complete Critiques, prompt templates, file-backed skill management, and
   source-located Critique navigation over ordinary Works folders.
8. Complete unified Search and Attention, canonical Connections, view-only Canvas, and optional read-only Zotero integration.
9. Perform interactive visual, accessibility, conflict, recovery, multiwindow, CJK, and performance acceptance in the isolated QA app before release packaging.

Current source, tests, README, and operational handbook remain the authority for what is implemented today. No code, vault, or app-owned data is migrated merely because this canonical guide changed.

## Appendix A. Default Critique prompt for Works

```text
Critique the Work identified in the Scholium request using the standards and
questions of a careful specialist in the relevant field. Apply those standards
without presenting yourself as a human specialist.

Critique scope: {{critique_scope}}
Critique lens: {{critique_lens}}
Selected passages or requested focus: {{selected_ranges}}
Additional instructions: {{additional_instructions}}

Inspect the relevant Analyses and Topics in the Triptych. Distinguish what those
notes report, support, dispute, or leave uncertain from your own reconstruction
or evaluation. Do not treat neutral links or transitive paths as evidence.

For an Overall Critique, explain the target's main strengths, major weaknesses,
source coverage, important omissions, objections or alternatives, and priorities
for change. Assess whether important claims, premises, and arguments are
adequately traceable to the available Analyses and Topics.

For Specific Comments, identify the target line or passage, the issue, why it
matters, the relevant research basis, and a concrete recommendation.

Use the default sections Overall Assessment, Strengths, Major Concerns, Source
Support, Objections and Alternatives, Revision Priorities, Specific Findings,
and Materials Consulted and Limitations. You may label source-related findings
Traced, Untraced, Disputed, or Beyond Sources. These are your attributed
judgments, not Scholium statuses.

Always identify the materials actually consulted and any limitations. Write the
result to the designated Critique document. Do not modify the target Work unless
the researcher's instruction asks you to do so.
```
