# Specification: Integrations, Onboarding, and Boundaries

Part of the canonical document set rooted at [SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md).
This chapter owns Sections 15–17: Zotero, onboarding, permanent boundaries, and deferred capabilities; sibling chapters do not restate it.

## 15. Zotero integration

### 15.1 Local read-only API

The optional built-in integration reads Zotero through its localhost API; it
uses neither an online Web API credential nor a researcher-deployed server.
Its absence blocks no core workflow.

**Settings → Integrations → Zotero** shows connection status, **Open Zotero**,
one **Check Connection** action, **Clear Connection History**, last successful
time, and a concise local/read-only privacy statement.
When disabled, direct the researcher to **Allow other applications on this
computer to communicate with Zotero** in Zotero's Advanced settings.

### 15.2 Protected Analysis task context

`zotero_item_key` is an Analysis-only protected-machine field. It is absent
from About and ordinary Properties. Scholium has no **Create Analysis from
Zotero**, matching, comparison, confirmation, or metadata-overwrite flow. Only
a protected machine or authorized agent mutation may write the key through the
current-fingerprint boundary.

When the current Analysis has a valid normalized key, Overview exposes one quiet
**Open in Zotero** action that opens that exact item in Zotero Desktop. The
action displays neither the key nor fetched Zotero metadata, performs no
matching or confirmation, and is absent for Topics, Works, and Analyses without
a valid key.

When Analyze or another eligible Analysis Action begins preparation with a
non-empty key,
Application performs one exact local item read and automatically attaches the
catalogued `scholium-zotero-integration` System Skill. The immutable Action
snapshot is labelled **Zotero bibliographic metadata** and may carry item key,
item type, title, complete creator roles, date/year, language, container,
volume, issue, pages, edition, series, publisher, place, DOI, ISBN, ISSN,
citation key, URL, abstract, tags, Collections, and modification time.

The same run reuses that snapshot when resumed; every new run reads Zotero
again. No metadata cache crosses tasks. Unavailable Zotero, a missing item, or
an invalid response adds one nonblocking warning and never prevents the agent
from continuing with available evidence or leaving unnecessary fields absent.
No key and non-Analysis targets perform no read and emit no Zotero warning.

Task metadata is never written into Markdown or displayed in Inspector.
Abstract, tags, and Collections remain bibliographic metadata, never paper
content or philosophical evidence. Attachments, Zotero Notes, annotations,
PDFs, and full text never enter automatic context. Built-in integration never
changes Zotero data, files, or live SQLite.

### 15.3 Recommended Bibliography

One Triptych-wide **Recommended Bibliography** utility is fixed at the
Sidebar bottom outside Library's Scope-, Location-, selection-, filter-, and
source-list ownership. It remains in the same position when Analyses, Topics,
Works, Library, Set Aside, or Trash changes, and only a Triptych change changes
its research boundary. Its compact band uses the heading, fixed sibling
position, structural boundary, and **Triptych Recommended Bibliography**
accessibility group to express that ownership; it adds no explanatory subcopy.
The complete band is one button: its heading row shows the nonzero count and a
quiet forward chevron, while the second row shows **No recommendations** or one
static `Author, Year, Title` preview. It contains no compact horizontal list,
individual candidate action, or diagonal-open glyph. Activating any part of the
band opens the complete researcher-facing surface for handling agent-
recommended literature. It is not Library content, a vault projection, a
Research Action, Inspector launcher, note appendix, Zotero write path, or
evidence store.

Optional goals are Background Reading, Core Positions, Historical
Predecessors, Objections, Replies, Companion Literature, Alternative
Approaches, Missing Citations, Recent Developments, and Classic Works, with an
optional purpose. No selected goal requests neutral source-centred screening.
Source Analyzer is the complete default method; Advanced may bind one compatible
Triptych-local replacement. Broken explicit bindings show Repair and never
silently fall back.

Preparation locks Triptych identity and selected-note fingerprints, snapshots
exact methods/resources, and treats zero candidates as success. The agent
distinguishes reference-list occurrence, in-text citation, substantive
discussion, praise, criticism, centrality, verified metadata, and independent
inspection. Unread candidates receive no Debate Importance or relevance score.

Store the atomic portable projection at
`.scholium/recommended-bibliography.json`. Match by verified scoped Zotero key,
DOI, guarded ISBN, citation key, then exact normalized title + complete author
identity + year. Never auto-merge chapters/books, editions/translations,
conflicting or incomplete authors, or ambiguous titles. A matched Analysis
proves no coverage beyond its Research Unit and evidence.

Rows show title, authors/year, goals, one short reason, and verification/match
state. Actions are **Open Analysis** when a matched Analysis exists and
**Dismiss**. The section provides **Recommend…**, **Copy Instructions**,
**Cancel**, and **Update Recommendations**; preserves prior results on refresh
failure; and distinguishes empty, successful-zero, preparing, awaiting-agent,
stale, malformed, duplicate, ambiguous, Zotero-unavailable, and general error
states through text/symbol plus accessible focus and narrow adaptation.

Recommended Bibliography preparation and completion remain separate from
Research Actions. CLI provides `bibliography prepare`, `show`, `complete`,
and `cancel`; Scholium owns normalization and duplicate discrimination.

### 15.4 Optional external-agent Zotero MCP

Beta also supplies a protected `scholium-zotero-integration` System Skill and a
supported local MCP service or installation route. The skill is an instruction
contract; MCP is transport, not an embedded runtime.

It may report readiness, search, inspect exact metadata and bounded attachment
pointers, identify an import target, and import BibTeX/RIS. A real import needs
an explicit current-task request for the exact record and destination,
successful dry run, tool confirmation, and read-back. Prior reading, search,
analysis, or import grants no standing write permission.

Never read/write Zotero's live SQLite directly, select ambiguous records or
destinations silently, or treat metadata, tags, abstracts, or attachment
identity as evidence. Source analysis remains separately requested; citation
formatting requires an explicit Triptych-local binding. If MCP is unavailable,
report the boundary without global configuration scans or database bypass.

## 16. Onboarding

Before onboarding or workspace restoration, one app-owned bootstrap state is
either **Starting**, **Ready**, or **Storage Unavailable**. Only Ready contains
the validated Application Support location and may construct workspace state
or services. Storage Unavailable replaces the app root with a
nonmodal recoverable failure page; **Retry** is the default action, **Details**
reveals selectable diagnostic text, and **Quit** remains available. New Window,
New Triptych, and all workspace commands stay disabled. Retry performs a fresh
validation and enters the ordinary workspace or onboarding route only after it
succeeds; no temporary or implicit read-only workspace exists in the meantime.

First launch, **New Triptych…**, and missing registration use one narrow
Bootstrap window. It asks one decision at a time—Analyses, Topics, Works, then
bounded authorization beside Works—through standard Open panels. It constructs
no workspace split, toolbar, inert regions, tabs, feature tour, project model,
or explanatory manual.

Bootstrap silently adopts **Ask Me Every Time** for agent-requested additional
note changes and write-capable child phases and states: “Agent changes will ask
for permission every time. You can change this later for each Triptych or Skill
in Research Guidance Settings.” It does not ask the researcher to understand a
permission matrix before opening the workspace.

Failure retains setup input. Success opens one configured workspace and closes
Bootstrap only after that exact workspace route has attached its native window,
split, and toolbar; they never compete. Recoverable Workspace routes restore
directly. The presented Bootstrap default is used only when no
recoverable Workspace exists. Bootstrap starts at **720 × 720**; this is an
initial size, not a minimum. Expired folder access instead uses the workspace's
bounded **Restore Access** sheet and preserves its active document. Settings
**Manage Triptychs…** lists registrations, edits their three locations, creates
another, and opens one in a separate window.

## 17. Permanent boundaries and deferred capabilities

Never add:

- permanent LLM chat, project/task management, plugin marketplace, fourth
  vault, or All Notes mode;
- an embedded agent runtime, agent-reasoning monitor, unrestricted executable
  Skill system, or Proposal approval layer;
- automatic philosophical support, settlement, sufficiency, truth, prose
  authorization, or untraced-premise verdicts;
- Zotero replacement, embedded PDF reader, proprietary backup export, or
  arbitrary Obsidian-theme compatibility; or
- bundled general instructions purporting to teach researchers philosophy.

The researcher-governed Skills contract requires protected System Skills;
directly editable Working Method Skills
for Discuss, Analyze, Synthesize, Write, Critique, and Content Fidelity;
optional hidden Manuscript; declarative Action Profiles; bounded installation;
standing permissions; agent change requests; portable Research Records; and
protected Zotero and agent-tool transports.

Deferred beyond experimental release: document/project/HTML/PDF/DOCX export;
Skill marketplace, executable extensions, automated Skill evolution,
inheritance and sharing; and Work finding overlays.

**Run with Codex** is outside the 1.0 boundary. Background/noninteractive
execution, auto-submission, streamed thread/tool state, general agent-host
approval or interruption control, and App Server or SDK orchestration require
a future product decision. The current typed note-change request does not
broaden into those capabilities, and **Open in Codex** implies none of them.

File-backed Method Skills and Action Profiles are Settings-owned Research
Guidance, not a marketplace, runtime, specialized request taxonomy, or
philosophical authority. Finder remains authoritative for Markdown,
attachments, and checkpoint folders; Zotero for bibliography/PDFs; external
agents for optional open-ended work.

Scholium defines no separate durable research-handoff packet or ontology.
Analyses, Topics, Works, and researcher-authored Markdown remain the durable
research context; a researcher may create an ordinary Markdown handoff note if
useful. An Action may assemble a bounded transient external-agent handoff from
authorized inputs, but the assembly is neither an additional research object
nor portable Research Record content.
