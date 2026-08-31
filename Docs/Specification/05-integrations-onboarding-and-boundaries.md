# Specification: Integrations, Onboarding, and Boundaries

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 15–17.

## 15. Zotero integration

### 15.1 Local read-only API

The optional built-in integration reads Zotero through its localhost API; it
uses neither an online Web API credential nor a researcher-deployed server.
Its absence blocks no core workflow.

**Settings → Research Guidance → External Tools & Citations → Zotero** shows
connection status, **Open Zotero**, one **Check Connection** action, **Clear
Connection History**, last successful time, and a concise local/read-only
privacy statement.
When disabled, direct the researcher to **Allow other applications on this
computer to communicate with Zotero** in Zotero's Advanced settings.

### 15.2 Portable Analysis binding and task context

An `AnalysisZoteroBinding` in portable `.scholium/` relates one stable Analysis
Note UUID to one exact Zotero user or group library identity and normalized
item key. It is not YAML, a Metadata field, bibliographic metadata, or researcher
source. A `zotero_item_key` found in Markdown is ordinary custom source and
grants no integration behavior or authority. Scholium never infers a binding
from YAML, path, filename, title, authors, identifier, date, or similarity.

Only dedicated set/clear Zotero-binding operations may change it;
`modify_markdown`, `modify_source`, and `modify_metadata` cannot. Rename,
Move, and system-Trash source deletion retain it by stable identity so Finder
restoration can reconcile the Analysis. Duplicate Analysis explicitly copies
the relationship. The Zotero
integration surface provides visible open, clear, and rebind paths. Agent direct Undo and
interrupted-save recovery change Markdown only and leave it unchanged.

Overview gives every current Analysis one quiet **Link Zotero Item…** or
**Manage Zotero Link…** action. Its central sheet searches the local user and
group libraries, displays enough bibliographic and library context for an
exact researcher selection, and treats an entered eight-character item key as
an exact lookup rather than a metadata search. It uses only the exact-item
endpoint for each accessible library identity needed to preserve ambiguity;
a missing key never falls through to an item-collection query. If the same key
resolves in more than one accessible library, every library-qualified result
remains distinct and the researcher chooses one. Once a library is selected,
preparation and commit read only that exact library/item endpoint. Selecting a
result performs a fresh exact read and
shows the managed Metadata fields that would be filled plus every conflicting
existing value that will be retained. **Link and Fill** or **Rebind and Fill**
is the single explicit completion action. A bound Analysis also exposes quiet
**Open in Zotero** and **Refresh Zotero Metadata…**; Manage supports confirmed
Clear. The Inspector displays neither the key nor fetched metadata inline, and
no integration action changes Markdown, authored YAML, or Zotero data.

Link and Fill is one Application-owned operation over two separate portable
transactions. It first revision-checks and writes the stable library identity
plus normalized item key, then uses the current Metadata-record revision to add
only absent, catalogued fields applicable to the effective Analysis source
type. It never replaces an existing managed value. Matching values remain
unchanged; conflicts remain researcher-owned and are named before commit. A
binding that committed before a Metadata conflict is retained and the partial
outcome is reported truthfully rather than rolled back across participants.
The proposal and commit both resolve the same stable Analysis identity and
exact source revision. Commit rereads the exact item and requires the same
local `Zotero-Server-ID`, library identity, item key, and item metadata that the
researcher reviewed. Any drift fails closed and requires a new preview.

When Analyze or another eligible Analysis Action begins preparation with a
binding, Application performs one exact local item read and automatically
attaches the catalogued `scholium-zotero-integration` System Skill. The
authenticated Run Context carries that Skill and its capability contract in one
typed optional Zotero Integration Adapter. The adapter is present only when the
Action targets an Analysis, its immutable snapshot contains Zotero context, and
the Platform Action permits Zotero use. It explains how the Agent can use the
already-bound external data route but grants no transport, capability, read,
write, or Markdown authority. The Agent may independently retrieve the exact
paper or attachment through its configured Zotero/MCP capability; Scholium
does not proxy that retrieval. The immutable Action snapshot is labelled
**Zotero bibliographic metadata** and may carry item key, item type, title, complete
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
PDFs, and full text never enter Scholium's automatic context, but an Agent may
retrieve them directly from Zotero when the selected Analyze task requires
paper data. Scholium never caches, proxies, or automatically transfers that
external content into the vault or a Record. Built-in integration never changes
Zotero data, files, or live SQLite. Connection, opening, and Action preparation
never write, refresh, reconcile, or override Analysis Metadata. Link and Fill
maps only bounded bibliographic fields into Scholium Metadata: source type,
title, supported structured creator roles, publication date, language,
container, series, volume, issue, pages, edition, publisher and place, DOI,
ISBN, ISSN, and URL where applicable. Zotero abstract, tags, citation key,
Collections, and modification time never become managed Metadata; in
particular abstract never becomes authored `summary` and tags never become
authored `keywords`. There is no continuous sync or automatic refresh. A later
refresh begins only from the bound Analysis, reads only its exact library/item
endpoint, and requires another explicit preview and current-revision
transaction. The preview names every absent field to fill and every nonempty
mapped Zotero value that differs from current managed Metadata. **Refresh
Metadata** adds the absent values and replaces only those displayed differing
mapped values after confirmation. It never deletes a managed field merely
because Zotero omits it or returns an empty value, and it leaves every
unmapped, inapplicable, authored, or custom value unchanged. An existing
managed source type remains the effective profile and is not replaced by
refresh. Commit rereads
only the same exact item and revalidates the local server, item, source,
binding, and Metadata revisions.

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
participating Notes, exact revisions, Scholium source reference when present,
the frozen Zotero bibliographic context when that is the selected route, date,
and agent authorship. Machine-local protected completion evidence may retain
the agent's submission only for idempotency and missing-Record repair; it has no
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
pointers, retrieve paper data through the Agent's Zotero capability when the
current task requires it, identify an import target, and import BibTeX/RIS. A
real import needs
an explicit current-task request for the exact record and destination,
successful dry run, tool confirmation, and read-back. Prior reading, search,
analysis, or import grants no standing write permission.

Never read/write Zotero's live SQLite directly, select ambiguous records or
destinations silently, or treat metadata, tags, abstracts, or attachment
identity as evidence. A Zotero binding plus an Agent-originated Analyze Run
permits the Agent to retrieve and analyze the paper independently of
Scholium's source-access store; the Agent must still report exactly what was
retrieved and what remained unavailable. Citation formatting requires an
explicit Triptych-local binding. If MCP is unavailable, report the boundary
without global configuration scans or database bypass.

## 16. Onboarding

Before onboarding or workspace restoration, one app-owned bootstrap state is
either **Starting**, **Registry Recovery**, **Ready**, or **Storage
Unavailable**. Only Ready contains the validated Application Support location
and one healthy machine-local workspace registration containing Triptych
membership, vault identity/access, and portable-container access, and may construct workspace
state or services. Storage Unavailable replaces the app root with a nonmodal
recoverable failure page; **Retry** is the default action, **Details** reveals
selectable diagnostic text, and **Quit** remains available. Registry Recovery
also replaces the app root. For a malformed current workspace registration,
**Relink Triptych** is the default action: it preserves that single damaged
owner as a timestamped machine-local recovery file, then opens ordinary
Bootstrap so the researcher explicitly selects Analyses, Topics, and Works
again. A newer registry schema or any registry I/O,
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
global Agent-configuration edits, alternative download sources, and quarantine
mutation. Its separate project-preparation authority permits only the exact
instruction files and host-specific project Skill links below. It verifies the
absolute CLI path, accepts the version JSON only from
the required `product` and `cli_version` fields while ignoring additional
fields, runs `doctor`, and reads `scholium help agent`. The App never embeds,
installs, updates, removes, executes, fingerprints, or reports machine status
for the CLI.

The standalone CLI owns explicit self-update commands. `scholium update
--check` downloads the fixed official archive and adjacent SHA-256 file,
verifies release provenance, architecture, and code signature, and performs no
installation write. `scholium update` performs the same checks and
transactionally replaces only the user-local CLI executable and adjacent Core
resource bundle when the release is newer. It never runs in the background,
edits PATH or shell profiles, uses `sudo`, or changes the App's installation or
sandbox boundary;
an interrupted replacement must recover the previous verified pair.

The same prompt tells the Agent to inspect applicable ancestor and root
`AGENTS.md` and `CLAUDE.md`. When no applicable `AGENTS.md` exists, the Agent
uses the CLI's protected workspace-bootstrap candidate and promotes it only
after exact-root validation; it never improvises, overwrites, merges, or shadows
instructions. Claude Code may add only a minimal missing `CLAUDE.md` that
refers to the applicable `AGENTS.md`.

The CLI's read-only project Skill-source manifest contains every installed
release-managed Protocol and every enabled current Action Skill folder for the
selected Triptych, including an explicitly registered machine-local folder.
It scans no arbitrary directory, creates nothing, and never invents a missing
source. The concise setup instruction tells the external Agent to register each
exact returned source through its own host's project-level Skill mechanism and
reload discovery if that host requires it. Scholium does not prescribe or
simulate a host-specific link, copy, package, plug-in, or global installation
scheme. Setup edits no source bytes. After discovery, the researcher and Agent
may read or edit the researcher-owned Action Skill folder directly; that file
access is outside Scholium authority and never applies to release-managed
Protocols. Registration grants no `.scholium` mutation, research read,
Action, Session, Run, or write authority.

The prompt otherwise prefers Scholium tools for research work, preserves
Scholium's exact-source and `.scholium/` boundaries, and makes no research read
or pairing request during preparation. A later researcher instruction may
begin an eligible direct `agent start`; a GUI-created Run still requires its
specific handoff. The Agent uses its host's own Skill listing to confirm every
returned name resolves from the registered project source. A required restart or new
task is a preparation blocker rather than Ready. After confirmed discovery and
the Agent's Ready report, **I’ve Set Up My Agent** requires a second researcher
confirmation. Scholium accepts only that confirmation and never claims to
inspect or verify the external project, registration, Agent host, or CLI. Every
copied GUI handoff and direct-start help also carries the same short conditional
first-workspace initialization instruction before Session creation or Pairing
Code consumption.
The illustration and its key metaphor are decorative and absent from the
accessibility tree; the numbered text and native controls provide the complete
linear task.

Bootstrap explains that a paired Agent may add task-relevant documents and
continue related research without repeated approval sheets; Scholium records
those operations and forms a Research Record. It does not ask the researcher
to configure or understand a permission matrix before opening the workspace.

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
active workspace runtime. If an existing `.scholium` owner has an unsupported
schema or is damaged, registration performs a read-only whole-bundle preflight before any
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
  Skill system, or second pre-write proposal/approval object;
- automatic philosophical support, settlement, sufficiency, truth, prose
  authorization, or untraced-premise verdicts;
- Zotero replacement, embedded PDF reader, proprietary backup export, or
  arbitrary Obsidian-theme compatibility; or
- bundled general instructions purporting to teach researchers philosophy.

The researcher-governed Skills contract requires protected platform protocol;
one current editable Skill registration per available Action; Skill-routed
ordinary references, including philosophical lenses; optional local
folder-path registration;
academic-only Action Profiles; Run-owned Activity Ledgers; portable Research
Records; and protected Zotero and local Agent transports. Scholium does not add
per-document or per-continuation approval policy on top of the researcher's Run.

Outside the Beta/1.0 scope: document/project/HTML/PDF/DOCX export;
Skill marketplace, executable extensions, automated Skill evolution,
inheritance and sharing; Work finding overlays; active-table-cell hybrid
editing; and PDF attachment presentation. A later PDF attachment route uses
Quick Look, Open, and Reveal in Finder over ordinary attachment bytes and never
becomes an embedded PDF reader.

Additional researcher-facing interface translations beyond English and
Simplified Chinese, right-to-left interface chrome and navigation, and complete
RTL document-input support and human acceptance are deferred beyond 1.0.

Direct local Agent start and pairing are bounded Run connections, not an embedded
runtime, background Agent manager, auto-submission system, streamed tool-state
viewer, general host-approval surface, relay, or cloud orchestration service.
Scholium does not launch or supervise an Agent merely because a Run exists.
Scholium has no selected-Agent preference, remembered Agent application, launch control, or
durable Agent-readiness authority. The bounded first-launch preparation prompt
configures only an external project's ordinary environment and grants no
research access. A direct `agent start` request or the current Run's copied
handoff establishes the researcher-initiated research Session; Pairing Code is
required only for the GUI-created handoff route.

Action-folder registrations and Action Profiles are Settings-owned Research
Guidance; Action Skill contents remain ordinary researcher-owned files. None are a
marketplace, executable
runtime, specialized request taxonomy, or philosophical authority. Finder
remains authoritative for Markdown, ordinary Skill-folder contents, and
attachment bytes; §3.3 owns the portable catalog and machine-local bookmark
boundary. Zotero remains authoritative for bibliography and Zotero-managed PDFs;
external Agents remain authoritative for optional open-ended work.

Project-level Agent registrations are nonauthoritative discovery pointers to
the release-managed Protocol folders and the current researcher-owned Action
Skill folders. They create no second editable copy, package lifecycle,
inheritance, sharing, capability, or permission. Researcher changes remain in
the selected folder and Scholium never silently replaces, repairs, or restores
them merely because a release ships different template bytes. The protected
Core Protocol is not researcher-editable and follows the compatible installed
CLI resource bundle across upgrades. Conditional adapters are registered System
Skills and become required only when the typed Run Context names them.

Scholium defines no separate durable research-handoff packet, memory object, or ontology.
Analyses, Topics, Works, and researcher-authored Markdown remain the durable
research context; a researcher may create an ordinary Markdown handoff note if
useful. An Action may assemble a bounded transient external-agent handoff from
authorized inputs, but the assembly is neither an additional research object
nor portable Research Record content.
