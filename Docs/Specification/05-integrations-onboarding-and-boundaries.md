# Specification: Integrations, Onboarding, and Boundaries

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 15–17.

## 15. Zotero integration

### 15.1 Local read-only API

The optional built-in integration reads Zotero through its localhost API. It
uses no online Web API credential or researcher-deployed server, writes no
Zotero data, and blocks no core workflow.

Settings shows connection status, **Open Zotero**, **Check Connection**, clear
history, last successful time, and a concise local/read-only privacy statement.
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
Links or reading ordinary Note context. An authorized Agent may use the Codex
host's Zotero capability when its task needs source data.
Citation generation is deferred. Before adding a future adapter, evaluate
whether Zotero's existing capabilities already serve the Agent's need.

### 15.3 Codex-hosted Zotero reading in Chat

In-app Chat uses the host Codex Zotero capability when it is available. This
route is read-only: the Agent may search the library, inspect metadata and
read indexed attachment text when the host reports that material as available.
Scholium does not require users to install a community Zotero server, Python
runtime or separate dependency set, and it does not expose a separate
user-configurable Zotero connection.

The host capability, Zotero Desktop local API availability and material
observations remain independent. If the host capability is unavailable, Chat
reports that boundary and ordinary Note collaboration remains available.
Scholium never bypasses the host through direct SQLite access or an unrelated
configuration scan. Chat does not import or modify Zotero records. The native
Zotero integration remains limited to the local API connection status and
library search used by App settings and links; it is not a Chat fallback or a
second Chat source projection.

Never access Zotero's live SQLite directly, guess ambiguous items or
destinations, or treat metadata and attachment identity as evidence. If the
host capability is unavailable, report that boundary without database bypass
or broad configuration scans.

### 15.4 Exact references and selected material

One library-qualified reference identifies an item, a PDF attachment at an
optional one-based physical page, or an annotation within that attachment.
Native link navigation and tool results use the same `zotero://select` or
`zotero://open-pdf` representation. A printed page label remains separate from
the physical page; a reference proves neither successful arrival nor reading.
Unsupported routes, malformed keys, duplicate parameters, and nonpositive
pages or group IDs are rejected rather than guessed or downgraded.

Host Zotero results may retain host locators and coverage claims, but Scholium
does not manufacture an App-side read report or promote them to source
evidence. Indexed attachment text, metadata, annotations and original local
file bytes remain distinct; a successful capability lookup alone is not proof
that an original was read.

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
- an automatic judge of philosophical support, truth, sufficiency, settlement,
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

Outside Beta/1.0 are document/project/HTML/PDF/DOCX export, executable
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
