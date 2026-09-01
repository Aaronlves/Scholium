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

### 15.2 Portable Analysis binding and task context

A portable `AnalysisZoteroBinding` relates one stable Analysis identity to one
exact user/group library and normalized item key. It is not YAML, Metadata,
bibliographic evidence, or source content. Scholium never infers it from
filenames, titles, identifiers, similarity, or custom YAML.

Only dedicated set/clear operations change the binding. Rename, Move, and
system-Trash source deletion retain it by stable identity; Duplicate explicitly
copies it. Markdown, Metadata, direct Undo, and save recovery do not alter it.

Every current Analysis offers **Link Zotero Item…** or **Manage Zotero Link…**.
The sheet searches accessible local libraries, preserves library-qualified
ambiguity, and uses exact lookup for an entered item key. Fresh preview names
the exact item, proposed applicable Metadata fills, and retained conflicts.
**Link and Fill** or **Rebind and Fill** is the single commit action. A bound
Analysis also offers Open, Refresh Metadata, and confirmed Clear. None changes
Markdown, authored YAML, or Zotero.

Link and Fill uses two explicit portable transactions: revision-check and write
the binding, then add only absent applicable managed Metadata. It never
overwrites a researcher value. If Metadata commit conflicts after the binding
commits, retain the binding and report the partial outcome. Commit rereads the
same server, library, item, source, binding, and Metadata revisions reviewed in
the preview.

Scholium MCP does not fold Zotero data into automatic Note context. A current
task may use the separately configured Zotero MCP to read a fresh exact item or
attachment route. That adapter grants no Scholium write, Markdown, or
independent discovery authority, and bibliographic results are not cached as a
cross-task research context.

Bibliographic context remains distinct from paper content and philosophical
evidence. Zotero attachments, Notes, annotations, PDFs, and full text do not
enter automatic Scholium context. An Agent may retrieve the selected paper
through its separately configured Zotero capability when the research task
requires it, reporting what was and was not available.

Link/Refresh may map only applicable bibliographic fields into managed Metadata:
source type, title, creator roles, publication date, language, container,
series, volume, issue, pages, edition, publisher/place, DOI, ISBN, ISSN, and
URL. Abstract, tags, citation key, Collections, and modification time never
become managed values; abstract and tags never become authored `summary` or
`keywords`. Refresh requires a new preview, fills absences, updates only
explicitly displayed differing mapped values, and never deletes local values
because Zotero omitted them.

### 15.3 Optional external-agent Zotero MCP

Beta supplies a protected Zotero integration Skill and a supported local MCP
service or installation route. The Skill owns stable research and safety
instructions; installed CLI help and tool schemas own current transport
details.

The integration may check readiness, search, inspect exact metadata and bounded
attachment pointers, retrieve paper data for the current task, and import
BibTeX/RIS. Any write requires an explicit current-task request for the exact
record and destination, dry run, confirmation, and readback. Prior search,
reading, analysis, or import grants no standing permission.

Never access Zotero's live SQLite directly, guess ambiguous items or
destinations, or treat metadata and attachment identity as evidence. If the MCP
route is unavailable, report that boundary without database bypass or broad
configuration scans.

## 16. Onboarding

Before workspace construction, bootstrap state is **Starting**, **Registry
Recovery**, **Ready**, or **Storage Unavailable**. Only Ready has a validated
Application Support root and healthy workspace registration. Other states
replace the app root, disable workspace commands, retain diagnostic detail, and
offer only their safe Retry, Relink, or Quit route. No temporary or implicit
read-only workspace is constructed.

First launch, **New Triptych…**, and missing registration use one Bootstrap
window. After Welcome the researcher chooses:

- **Create a New Triptych**: select a name and parent, preview, then atomically
  create Analyses, Topics, Works, and `.scholium` without replacement; or
- **Connect Existing Folders**: select Analyses, Topics, Works, then authorize
  the detected Works parent through standard Open panels.

Bootstrap asks one decision at a time, preserves input on failure, and opens the
configured workspace only after registration succeeds. It contains no inert
workspace shell, project model, feature tour, or duplicate navigation.

Agent setup is not part of first launch. The workspace remains fully usable
without an Agent, CLI, or external host configuration. Later, Settings →
Research Guidance → **Agent Integration** reports only what Scholium can verify
locally: whether the App bridge and compatible CLI are available.

The page provides user-scope Codex and Claude setup commands using the verified
absolute CLI path and a Finder route to the bundled Core Protocol. Copying or
revealing performs no research read and grants no write authority. Scholium
does not edit external host settings, install Skills, store a readiness flag,
or claim the copied command was run. A missing CLI offers only the official
standalone installation instructions.

The App never embeds, updates, removes, or configures the external Agent. The
standalone CLI retains explicit, verified, architecture-matched, recoverable
self-update of only its executable and adjacent resource bundle; it never runs
in the background or edits PATH, shell profiles, or the App.

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

- permanent LLM chat, project/task management, a plugin marketplace, fourth
  vault, or All Notes mode;
- an embedded Agent runtime, reasoning monitor, background Agent manager,
  streamed tool viewer, relay, cloud orchestrator, or second proposal/approval
  layer;
- an automatic judge of philosophical support, truth, sufficiency, settlement,
  prose authorization, quality, or researcher competence;
- a Zotero replacement, embedded PDF reader, proprietary backup format, or
  arbitrary Obsidian-theme host; or
- a source of generic instructions purporting to teach philosophy.

The target keeps one protected Core Protocol, one fixed local MCP tool surface,
optional researcher-owned method Skills, and bounded Zotero/local Agent
transports. Finder remains authoritative for Markdown and attachment bytes;
the external host owns its Skills; Zotero remains authoritative for its library
and PDFs; external Agents remain authoritative for optional open-ended work.

Outside Beta/1.0 are document/project/HTML/PDF/DOCX export, executable
extensions and Skill marketplace/evolution/sharing, Work finding overlays,
active-table-cell hybrid editing, and PDF attachment presentation. A future PDF
route may use Quick Look, Open, and Reveal in Finder but not become an embedded
reader.

Beta/1.0 interface localization covers English and Simplified Chinese.
Additional translations, right-to-left chrome/navigation, and complete RTL
input acceptance remain deferred; exact Unicode preservation is mandatory.

External-host Skill registrations are nonauthoritative discovery pointers, not
Scholium state, capability, evidence, or permission. Researcher Skill edits
remain host-owned and are never silently replaced by Scholium. The protected
Core Protocol follows the compatible CLI release.

Scholium defines no separate durable Agent memory or ontology. Analyses,
Topics, Works, and authored Markdown remain the research context. A future
lightweight Handoff requires its own approved contract and cannot become a
hidden research object or permission mechanism.
