# Specification: Integrations, Onboarding, and Boundaries

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 15–17.

## 15. Zotero integration

### 15.1 Local API and Connector

The built-in integration connects to Zotero Desktop through its localhost API
and Connector. It uses no online Web API credential, researcher-deployed
server, community MCP, Python runtime or private SQLite access. Zotero remains
the sole library authority. Reads and confirmed, version-checked item
modifications are available to the independent `scholium-zotero` MCP connection;
the local API preference remains a Zotero-owned prerequisite. Researchers can
continue importing BibTeX and RIS directly in Zotero. Agent import tools are
unavailable until a Zotero interface can bind the destination before writing.

Settings shows connection status, **Open Zotero**, **Check Connection**, clear
history, last successful time, and a concise local privacy statement.
When disabled, it names the exact Zotero setting required to allow local
applications.

### 15.2 Authored Zotero links and task context

Notes may contain any number of exact Zotero item/PDF/annotation links.
The Links Inspector derives these occurrences from committed Markdown, alongside
outgoing Note links, using the existing toolbar-selected Links surface. Each
occurrence retains its authored label and exact library-qualified reference,
including page and annotation when present. Repeated occurrences remain visible.
There is no Note-to-item binding, title matching, Link-and-Fill, or whole-Note
Refresh Metadata operation. Deleting a source link removes that relation.

Opening a link requests Zotero navigation; it proves neither reading nor
philosophical support. Scholium does not fetch bibliography while projecting
Links or reading ordinary Note context. An authorized Agent may use Scholium's
independent Zotero connection when its task needs source data or an explicitly
requested Zotero library change.

### 15.3 Independent Zotero connection in Chat

In-app Chat injects the managed `scholium-zotero` local MCP server alongside
the Scholium workspace server. The Agent may use its bounded Zotero surface:
search, item/collection/tag/group/child inspection, indexed full text,
originals, annotations, file URLs, BibTeX/citation export, and local-API item
updates. PDF originals use a page-specific read with
an exact one-based physical page; non-PDF text and image originals use the
separate bounded file read. Item updates require explicit confirmation, the
exact library, and the current Zotero item version. Zotero controls local API
write authorization and may ask the researcher to allow Scholium. A Zotero
write receipt followed by failed readback is an uncertain outcome; inspect
the current item before retrying.

No separate runtime installation or user-configurable Zotero connection is
required. If Zotero is closed or its local API/Connector is disabled, Chat
reports that exact local boundary. Scholium never bypasses Zotero through
SQLite or unrelated configuration scans. Metadata, indexed attachment text,
annotations and original local bytes remain distinct and do not by themselves
constitute source evidence.

Never access Zotero's live SQLite directly, guess ambiguous items or
destinations, or treat metadata and attachment identity as evidence.

### 15.4 Exact references and selected material

One library-qualified reference identifies an item, a PDF attachment at an
optional one-based physical page, or an annotation within that attachment.
Native link navigation and tool results use the same `zotero://select` or
`zotero://open-pdf` representation. A printed page label remains separate from
the physical page; a reference proves neither successful arrival nor reading.
Unsupported routes, malformed keys, duplicate parameters, and nonpositive
pages or group IDs are rejected rather than guessed or downgraded.

Zotero results may retain locators and coverage claims, but Scholium does not
manufacture an App-side read report or promote them to source evidence. Indexed
attachment text, metadata, annotations and original local file bytes remain
distinct; a successful capability lookup alone is not proof that an original
was read.

### 15.5 Manuscript citations and bibliography

Manuscript citation editing uses Zotero Desktop's HTTP document integration.
Zotero owns source search/selection, multi-source clusters, locators,
prefixes/suffixes, suppress-author, citation style and CSL rendering. Scholium
supplies ordered manuscript fields and persists accepted changes; it neither
bundles a CSL processor nor writes library items through this route. The
independent Agent connection retains §15.3's confirmation boundary. Only inline
citation styles are supported. Note styles and automatic footnote/endnote
conversion are unavailable; requests leave source unchanged and explain the
limitation.

Exact Markdown carries each citation as a standard link with a readable fallback
label and versioned `scholium-zotero:1:` destination. The encoded payload retains
stable host occurrence identity and opaque Zotero field data, including supplied
item references and metadata. Bibliography is readable Markdown between paired
field comments; a document comment retains Zotero document/style data and the
accepted field state. No hidden rich text or sidecar becomes citation authority.
Citekeys and title matching cannot replace Zotero's library-qualified references.

Each operation stages callbacks against the current exact source and selection.
Only a validated accepted candidate applies in one Undo, preserving bytes outside
changed ranges. Completion alone confirms protocol cleanup, not acceptance.
Composition, selection, mode or document changes revoke pending acceptance;
cancellation or failure preserves typed input and source. Protocol cleanup cannot
publish partial fields.

Changed field identities, codes or order mark citation state stale. Manual
fallback edits remain source; Zotero handles their citation consequences on
Refresh. **Refresh Citations** delegates the complete ordered clusters and
bibliography to Zotero; **Citation Style…** changes style there. Library metadata
changes require explicit Refresh. Offline Notes retain exact fields and their
last readable fallback; disconnected formatting is Unavailable, never fresh
output. Unknown versions, malformed/duplicate fields and unresolved sources retain
bytes. Stale/unresolved state stays visible in a native Document notice with guarded
**Refresh Citations** and **Source** repair; identity is never guessed. §18.4 owns
insertion and export presentation.

## 16. Onboarding

Before workspace construction, bootstrap state is **Starting**, **Registry
Recovery**, **Ready**, or **Storage Unavailable**. Only Ready has a validated
Application Support root and healthy workspace registration. Other states
replace the app root, disable workspace commands, retain diagnostic detail, and
offer only their safe Retry, Relink, or Quit route. No temporary or implicit
read-only workspace is constructed.

First launch, **New Triptych…**, and missing registration use one Bootstrap
window. Welcome briefly explains Analyses, Topics, and Works and directly offers
**Create a New Triptych** and **Connect Existing Folders**.

- **Create a New Triptych** keeps name, parent selection, and a live preview of
  the destination and fixed directory structure on one page. **Create and Open**
  atomically creates Analyses, Topics, Works, and `.scholium` without replacement,
  registers the Triptych, and opens its workspace.
- **Connect Existing Folders** shows the Analyses, Topics, and Works directory
  rows together on one page. Each role has a named native folder picker and can
  be changed without losing the other selections. The same page identifies the
  detected Works parent and explains and requests its exact-directory access
  through a standard Open panel. **Connect and Open** registers the selected
  folders and opens their workspace.

The selected destinations and operation's consequence remain visible beside the
final action; no separate starting-point, review, or completion page is required.
Back preserves the draft. Cancelling a picker retains its previous selection.
Registration shows actual progress, prevents duplicate submission, and retains
all input with persistent, actionable errors on the same setup page. Workspace
routing remains closed until registration succeeds.

Bootstrap uses the auxiliary-window presentation defined by Design (§19).
One small decorative hand illustration may accompany Welcome; setup pages give
space to the form and complete folder identities, without an illustration side
field. Content reflows or scrolls at narrow widths and with enlarged text under
§20. Bootstrap contains no inert workspace shell, project model, feature tour,
or duplicate navigation.

Agent setup is optional and deferred until after first launch. §8.2 owns
external-host commands and Core Protocol discovery; §8.7 owns in-app runtime
connection through the App-bundled helper. §21.5 owns App distribution.
Onboarding explains application operations, not how to conduct philosophy.

Success attaches one native workspace window before Bootstrap closes. Expired
access uses **Restore Access** without discarding active document state.
**Remove Registration…** deletes only the selected machine-local registration
after confirmation and leaves all research and portable bytes unchanged.

If existing portable control state is damaged or from an unsupported schema,
registration first performs a read-only whole-bundle preflight. Confirmed
**Archive and Rebuild…** atomically renames the entire unchanged `.scholium`
directory to one unique sibling before creating current control state.
Research vaults remain byte-exact. Archive, removal, and rebuild are unavailable
while that Triptych has an active workspace runtime. Settings manages and opens
registered Triptychs.

## 17. Permanent boundaries and deferred capabilities

Scholium does not become:

- a general LLM chat product, project/task management, a plugin marketplace, fourth
  vault, or All Notes mode;
- a self-built Agent harness, private-reasoning monitor, independent execution
  scheduler, cloud orchestrator, or second proposal/approval lifecycle;
- an automatic judge of philosophical support, truth, sufficiency,
  prose authorization, quality, or researcher competence;
- a Zotero replacement, embedded PDF reader, proprietary backup format, or
  arbitrary Obsidian-theme host; or
- a source of generic instructions purporting to teach philosophy.

The target keeps one protected Core Protocol, one bounded local MCP tool surface,
optional researcher-owned Skills, and bounded Zotero/local Agent
transports. Finder remains authoritative for Markdown and attachment bytes;
the selected runtime owns its Skills and tools, with in-app management under §8.7;
Zotero remains authoritative for its library
and PDFs; external Agents remain authoritative for optional open-ended work.

Outside Beta/1.0 are multi-Note/project export, executable
extensions and Skill marketplace/evolution/sharing, Work finding overlays,
and active-table-cell hybrid editing. Note attachments already have the target
Quick Look and external-opening routes in §18.4; a persistent embedded PDF
reader remains excluded.

§18.7 owns the localization scope. Additional translations, right-to-left
chrome/navigation, and complete RTL input acceptance remain deferred; exact
Unicode preservation is mandatory.

§8 owns Skill authority and runtime scope. The in-app client may manage
runtime-owned Skills, tools, concurrent and scheduled work under §8.7 without
creating a Skill marketplace, second execution loop or credential store.

Scholium defines no separate durable Agent memory or ontology. Analyses, Topics, Works,
and authored Markdown remain the research context. Chat provides explicit selection
handoff under §8.7; its snapshots and conversation state cannot become hidden research
authority.
