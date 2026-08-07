# Specification: Integrations, Onboarding, and Boundaries

Part of the canonical document set rooted at [SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md).
This chapter owns Sections 15–17: Zotero, onboarding, permanent boundaries, and deferred capabilities; sibling chapters do not restate it.

## 15. Zotero integration

### 15.1 Local read-only API

The optional built-in integration reads Zotero through its localhost API; it
uses neither an online Web API credential nor a researcher-deployed server.
Its absence blocks no core workflow.

**Settings → Research Guidance → Sources & Integrations → Zotero** shows
connection status, **Open Zotero**, one **Check Connection** action, **Clear
Connection History**, last successful time, and a concise local/read-only
privacy statement.
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

### 15.3 Literature Recommendations and the Zotero boundary

Literature Recommendations are optional structured output from Analyze, not a
separate product object, Research Action, Method binding, CLI lifecycle,
Sidebar item, Settings capability, or Zotero write path. Analyze may report a
reading lead only when the exact inspected source grounds both its citation and
reason. A reference-list occurrence, in-text citation, substantive discussion,
praise, criticism, centrality, verified metadata, and independent inspection
remain distinct; a recommendation by itself establishes none of them.

The parent Analyze Research Record is the only portable product authority and
provenance owner. It supplies the Action, Method/Profile, Analysis and
participating Notes, exact revisions, source reference, date, and agent
authorship. Machine-local protected completion evidence may retain the agent's
submission only for idempotency and missing-Record repair; it has no
disposition, recommendation ID, index, or product read path. The portable
recommendation therefore does not copy a second source status, target match,
verification score, refresh lifecycle, or category taxonomy. Researcher
handling state belongs to that one occurrence and has only Unprocessed or
Handled plus an optional note, as defined in §8.2.

The Triptych Recommendations view may group occurrences by an exactly
normalized DOI or Zotero item key when no other supplied identifier conflicts.
It never queries Zotero to infer a match, never writes Zotero, and never treats
a grouped result as a matched Analysis or evidence. DOI and Zotero identity are
grouping hints only; all occurrence-level content and disposition remain in
their parent Records.

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
either **Starting**, **Registry Recovery**, **Ready**, or **Storage
Unavailable**. Only Ready contains the validated Application Support location
and a healthy machine-local Triptych registry, and may construct workspace
state or services. Storage Unavailable replaces the app root with a nonmodal
recoverable failure page; **Retry** is the default action, **Details** reveals
selectable diagnostic text, and **Quit** remains available. Registry Recovery
also replaces the app root. For a malformed current registry, **Relink
Triptych** is the default action: it preserves the existing registry as a
timestamped machine-local recovery file, then opens ordinary Bootstrap so the
researcher explicitly selects Analyses, Topics, and Works again. A newer
registry schema or registry I/O failure remains in place with Details, Retry,
and Quit; Scholium never replaces it. New Window, New Triptych, and all
workspace commands stay disabled outside Ready. Retry performs a fresh
validation and enters the ordinary workspace or onboarding route only after it
succeeds; no temporary or implicit read-only workspace exists in the meantime.

First launch, **New Triptych…**, and missing registration use one narrow
Bootstrap window. It asks one decision at a time—Analyses, Topics, Works, then
bounded authorization beside Works—through standard Open panels. It constructs
no workspace split, toolbar, inert regions, tabs, feature tour, project model,
or explanatory manual.

Bootstrap silently adopts **Ask Me Every Time** for additional Run write-set
members and next Actions and states: “Agent changes will ask for permission
every time. You can change this later for this Triptych in Research Guidance
Settings.” It does not ask the researcher to understand a permission matrix
before opening the workspace.

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

The researcher-governed Skills contract requires protected platform protocol;
one current editable primary Markdown Skill registration per available Action;
exact-Wikilink Practices; optional local folder-path registration; optional
hidden Manuscript; academic-only Action Profiles; one Triptych collaboration
policy; Run-owned Bounded Write Sets; portable Research Records; and protected
Zotero and local Agent transports.

Deferred beyond experimental release: document/project/HTML/PDF/DOCX export;
Skill marketplace, executable extensions, automated Skill evolution,
inheritance and sharing; and Work finding overlays.

Direct local Agent pairing is a bounded Run connection, not an embedded
runtime, background Agent manager, auto-submission system, streamed tool-state
viewer, general host-approval surface, relay, or cloud orchestration service.
Scholium does not launch or supervise an Agent merely because a Run exists.
Collaboration settings therefore expose only one Triptych policy. Scholium has
no global Agent prompt or configuration, selected-Agent preference, remembered
Agent application, or launch control; the current Run's copied handoff is the
only researcher-to-Agent setup surface.

File-backed primary Skills, Practices, registrations, and Action Profiles are
Settings-owned Research Guidance, not packages, a marketplace, executable
runtime, specialized request taxonomy, or philosophical authority. Finder
remains authoritative for Markdown, ordinary Skill-folder contents,
attachments, and checkpoint folders; Zotero for bibliography/PDFs; external
Agents for optional open-ended work.

Scholium defines no separate durable research-handoff packet, memory object, or ontology.
Analyses, Topics, Works, and researcher-authored Markdown remain the durable
research context; a researcher may create an ordinary Markdown handoff note if
useful. An Action may assemble a bounded transient external-agent handoff from
authorized inputs, but the assembly is neither an additional research object
nor portable Research Record content.
