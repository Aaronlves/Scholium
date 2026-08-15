# Specification: Integrations, Onboarding, and Boundaries

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 15–17.

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

### 15.2 Portable Analysis binding and task context

An `AnalysisZoteroBinding` in portable `.scholium/` relates one stable Analysis
Note UUID to one exact Zotero user or group library identity and normalized
item key. It is not YAML, a Property, bibliographic metadata, or researcher
source. A `zotero_item_key` found in Markdown is ordinary custom source and
grants no integration behavior or authority. Scholium never infers a binding
from YAML, path, filename, title, authors, identifier, date, or similarity.

Only dedicated set/clear Zotero-binding operations may change it;
`modify_markdown` and `modify_properties` cannot. Rename, Move, Set Aside, and
Trash retain it by stable identity. Duplicate Analysis explicitly copies the
relationship; permanent deletion removes it. The Zotero integration surface
provides visible open, clear, and rebind paths. Agent direct Undo and
interrupted-save recovery change Markdown only and leave it unchanged.

Overview gives every current Analysis one quiet **Link Zotero Item…** or
**Manage Zotero Link…** action. Its central sheet searches the local user and
group libraries, displays enough bibliographic and library context for an
exact researcher selection, and persists only stable library identity plus the
normalized item key. A bound Analysis also exposes quiet **Open in Zotero**;
Manage supports explicit Rebind and confirmed Clear. The Inspector displays
neither the key nor fetched metadata, and no binding action changes Markdown or
Zotero data.

When Analyze or another eligible Analysis Action begins preparation with a
binding, Application performs one exact local item read and automatically
attaches the catalogued `scholium-zotero-integration` System Skill. The
authenticated Run Context carries that Skill and its capability contract in one
typed optional Zotero Integration Adapter. The adapter is present only when the
Action targets an Analysis, its immutable snapshot contains Zotero context, and
the Platform Action permits Zotero use. It explains how to handle the already
bounded integration but grants no transport, capability, read, write, or
Markdown authority. The immutable Action snapshot is labelled **Zotero
bibliographic metadata** and may carry item key, item type, title, complete
creator roles, date/year,
language, container, volume, issue, pages, edition, series, publisher, place,
DOI, ISBN, ISSN, citation key, URL, abstract, tags, Collections, and
modification time.

The same Run reuses that snapshot when resumed; every new Run reads Zotero
again. No metadata cache crosses tasks. Unavailable Zotero, a missing item, or
an invalid response adds one nonblocking warning and never prevents the Agent
from continuing with available evidence or leaving unnecessary fields absent.
No binding and non-Analysis targets perform no read, emit no warning, attach no
adapter, and authorize no independent integration discovery.

Task metadata is never written into Markdown or displayed in Inspector.
Abstract, tags, and Collections remain bibliographic metadata, never source
content or philosophical evidence. Attachments, Zotero Notes, annotations,
PDFs, and full text never enter automatic context. Built-in integration never
changes Zotero data, files, or live SQLite. Binding never creates a
bibliographic snapshot: connection, binding, opening, and Action preparation
never write, refresh, reconcile, or override Analysis Properties. A future
fill operation requires a separate explicit, field-bounded,
current-fingerprint source transaction.

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
Handled plus an optional note, presented under
[§18.5](07-document-and-research-interface.md#185-contextual-research-and-actions).

The Reading Leads collection may group occurrences by an exactly
normalized DOI or Zotero item key when no other supplied identifier conflicts.
It never queries Zotero to infer a match, never writes Zotero, and never treats
a grouped result as a matched Analysis or evidence. DOI and Zotero identity are
grouping hints only; all occurrence-level content and disposition remain in
their parent Records.

### 15.4 Optional external-agent Zotero MCP

Beta also supplies a protected `scholium-zotero-integration` System Skill and a
supported local MCP service or installation route. The skill is an instruction
contract; MCP is transport, not an embedded runtime. The Skill routes stable
capabilities and safety rules; installed CLI help and MCP tool schemas own
current command names, fields, and return shapes.

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
and healthy machine-local Triptych, vault-identity, and portable-access
registries, and may construct workspace
state or services. Storage Unavailable replaces the app root with a nonmodal
recoverable failure page; **Retry** is the default action, **Details** reveals
selectable diagnostic text, and **Quit** remains available. Registry Recovery
also replaces the app root. For a malformed current Triptych registry or a
damaged vault-identity or portable-access registry, **Relink Triptych** is the
default action: it preserves only the damaged owner as a timestamped
machine-local recovery file, keeps a valid sibling registry unchanged, then
opens ordinary Bootstrap so the researcher explicitly selects Analyses,
Topics, and Works again. A newer registry schema or any registry I/O,
unsafe-type, or unreadable-file failure remains in place with Details, Retry,
and Quit; Scholium never replaces it. New Window, New Triptych, and all
workspace commands stay disabled outside Ready. Retry performs a fresh
validation and enters the ordinary workspace or onboarding route only after it
succeeds; no temporary or implicit read-only workspace exists in the meantime.

First launch, **New Triptych…**, and missing registration use one narrow
Bootstrap window. After Welcome it asks the researcher to **Create a New
Triptych** or **Connect Existing Folders**. Create asks for one name and parent
location, previews the result, and only after confirmation creates Analyses,
Topics, Works, and `.scholium` together without reusing or overwriting an
existing destination. Connect asks one decision at a time—Analyses, Topics,
Works, then bounded authorization of the parent detected from Works—through
standard Open panels; that authorization panel opens at the detected folder so
the researcher does not browse the tree again. Triptych configuration,
optional Agent preparation, and Ready complete the narrative; Ready explicitly
opens the configured workspace. Bootstrap constructs no workspace split,
toolbar, inert regions, tabs, feature tour, project model, or explanatory
manual.

Only first-launch registration offers one optional machine-level **Prepare an
Agent** step. **New Triptych…**, relinking, and later launches do not repeat it.
After any create-new filesystem transaction succeeds, a confirmed selection
advances directly to Agent while Application registration continues in the
background. Routine registration success adds no status page or confirmation;
failure returns to the retained Triptych review with the exact error. Agent
completion cannot advance to Ready until registration succeeds. The step
presents the exact authorized Triptych container as the external Agent's
project and workspace root and offers **Set Up Later** without warning,
nagging, or reduced workspace capability.

**Copy Prompt** is immediately available. It copies one provider-neutral setup
instruction that authorizes the external Agent to download the independently
distributed, compatible Scholium CLI only from the fixed official release URL
and install only its executable and adjacent resource bundle under the
researcher's user-local directory. The instruction forbids `sudo`, shell or
Agent-configuration edits, alternative download sources, and quarantine
mutation. It verifies the absolute CLI path, accepts the version JSON only from
the required `product` and `cli_version` fields while ignoring additional
fields, runs `doctor`, and reads `scholium help agent`. The App never embeds,
installs, updates, removes, executes, fingerprints, or reports machine status
for the CLI.

The same prompt tells the Agent to inspect applicable ancestor and root
`AGENTS.md` and `CLAUDE.md`; create only the applicable missing instruction
file without overwriting, merging, or shadowing an existing one; prefer
Scholium tools for research work; preserve Scholium's exact-source and
`.scholium/` boundaries; make no research read or pairing request before the
stated authorization; and await a specific Run handoff. Copying is not
readiness. After the Agent reports Ready, **I’ve Set Up My Agent** requires a
second researcher confirmation. Scholium accepts only that confirmation and
never claims to inspect or verify the external project or CLI.
The illustration and its key metaphor are decorative and absent from the
accessibility tree; the numbered text and native controls provide the complete
linear task.

Bootstrap silently adopts **Ask Me Every Time** for additional Run write-set
members and next Actions and states: “Agent changes will ask for permission
every time. You can change this later for this Triptych in Research Guidance
Settings.” It does not ask the researcher to understand a permission matrix
before opening the workspace.

Failure retains setup input. Success opens one configured workspace after the
optional Agent step is either confirmed or deferred, and closes Bootstrap only
after that exact workspace route has attached its native window, split, and
toolbar; they never compete. Recoverable Workspace routes restore
directly. The presented Bootstrap default is used only when no
recoverable Workspace exists. Bootstrap starts at **760 × 740**; this is an
initial size, not a minimum. Expired folder access instead uses the workspace's
bounded **Restore Access** sheet and preserves its active document. If the
registered Triptych no longer exists or the researcher no longer intends to
reconnect it, **Remove Registration…** requires explicit confirmation, removes
only that Triptych's machine-local registration, leaves every research folder,
portable `.scholium` byte, and unrelated registration unchanged, then returns
through ordinary Bootstrap. Removal never decodes, migrates, or repairs an
unsupported portable schema and is unavailable while that Triptych has an
active workspace runtime. If an existing `.scholium` owner is old-schema or
damaged, registration performs a read-only whole-bundle preflight before any
machine-local registration write. Bootstrap or Restore Access then offers
confirmed **Archive and Rebuild…**: Scholium atomically renames the entire
`.scholium` directory to one unique sibling recovery name, verifies that the
same filesystem object was preserved, never interprets or migrates its files,
and creates current control state only after preservation succeeds. Analyses,
Topics, and Works remain byte-unchanged. Removing only the machine registration
does not resolve this unsupported portable owner. Neither archive nor removal
is available while that Triptych has an active workspace runtime. Settings
**Manage Triptychs…** lists registrations,
edits their three locations, creates another, and opens one in a separate
window.

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

Outside the Beta/1.0 scope: document/project/HTML/PDF/DOCX export;
Skill marketplace, executable extensions, automated Skill evolution,
inheritance and sharing; Work finding overlays; active-table-cell hybrid
editing; and PDF attachment presentation. A later PDF attachment route uses
Quick Look, Open, and Reveal in Finder over ordinary attachment bytes and never
becomes an embedded PDF reader.

Additional researcher-facing interface translations beyond English and
Simplified Chinese, right-to-left interface chrome and navigation, and complete
RTL document-input support and human acceptance are deferred beyond 1.0.

Direct local Agent pairing is a bounded Run connection, not an embedded
runtime, background Agent manager, auto-submission system, streamed tool-state
viewer, general host-approval surface, relay, or cloud orchestration service.
Scholium does not launch or supervise an Agent merely because a Run exists.
Collaboration settings therefore expose only one Triptych policy. Scholium has
no selected-Agent preference, remembered Agent application, launch control, or
durable Agent-readiness authority. The bounded first-launch preparation prompt
configures only an external project's ordinary environment and grants no
research access; the current Run's copied handoff remains the only surface that
establishes a researcher-to-Agent research Session.

File-backed primary Skills, Practices, registrations, and Action Profiles are
Settings-owned Research Guidance, not packages, a marketplace, executable
runtime, specialized request taxonomy, or philosophical authority. Finder
remains authoritative for Markdown, ordinary Skill-folder contents,
and attachment bytes. The portable attachment catalog under
`.scholium/attachments/v1/` records stable identities plus either an imported
vault-relative path or an indexed absolute path. Machine-local read-only
bookmark data for an indexed path stays outside the Triptych and cannot repair
or replace that path. Zotero remains authoritative for bibliography and Zotero-managed PDFs;
external Agents remain authoritative for optional open-ended work.

Scholium defines no separate durable research-handoff packet, memory object, or ontology.
Analyses, Topics, Works, and researcher-authored Markdown remain the durable
research context; a researcher may create an ordinary Markdown handoff note if
useful. An Action may assemble a bounded transient external-agent handoff from
authorized inputs, but the assembly is neither an additional research object
nor portable Research Record content.
