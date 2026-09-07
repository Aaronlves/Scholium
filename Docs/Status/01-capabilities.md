# Implementation Status: Reachable Capabilities

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Current product reachability.

## Workspace and source authority

- Registered Triptychs retain distinct Analyses, Topics, and Works vaults.
  Exact Markdown bytes and stable Note identities are authoritative; portable
  `.scholium` control state and machine-local Application Support state remain
  separate authorities.
- Repository reads and mutations enforce vault containment, regular-file
  identity, expected fingerprints, coordinated replacement, canonical readback,
  native system Trash, and recoverable uncertainty.
- Managed Note creation uses the common source scaffold and stable-identity
  transaction for App, researcher CLI, and MCP callers. Metadata settings,
  About editing, Settlement, Critique, Zotero bindings, transaction recovery,
  and source conflict handling remain reachable through their existing owners.
- Search contract 16 searches Notes through one source-authoritative path.
  Note title identity uses its filename; Analysis academic title Metadata and
  body headings remain independently searchable. Question-centered Works Notes
  use ordinary editing, Search, links and file operations.
- Review, Edit and Source retain one document session and exact-source authority.
  [Reachable Interface](02-interface.md) owns title, syntax, geometry and input
  presentation evidence; these are not separate product capabilities.
- Notes can bind regular document files independently of Markdown: copy stores
  exact bytes under `Attachments`, reference retains the Finder-owned file, and
  both persist a stable-Note relationship in portable control state with only
  machine-local access credentials. Quick Look resolves current availability;
  media files remain on the inline image/audio path. Attachment projection does
  not change source, editor generation, selection, Undo, or scroll.

## External Agent collaboration

- `scholium mcp serve` exposes exactly seven MCP tools:
  `scholium_workspace_status`, `scholium_search`, `scholium_read_note`,
  `scholium_list_links`, `scholium_create_note`, `scholium_update_note`,
  and `scholium_trash_note`.
- The stdio server connects only to a running Scholium App for the current
  user. It does not launch the App, construct a headless workspace runtime, or
  read and write Triptych files itself.
- A single open Triptych can be selected implicitly. Multiple open Triptychs
  require an exact stable Triptych identity. Every mutating request flushes
  matching live editors, enters the Application source-operation gate, and
  checks the exact target fingerprint where applicable.
- Link listing returns one authored occurrence per row, including exact
  occurrence/link/annotation markup, annotation text, local context, source
  fingerprint, and whole/link/annotation locators. It exposes only authored
  occurrence data.
- Create, update, and trash write machine-local Agent Change evidence. Each
  update retains its own fingerprint-validated exact Before and After bytes;
  review compares the recorded After fingerprint with freshly loaded
  authoritative source and marks a superseded ending as an Earlier Revision.
  Confirmed update evidence supports direct Undo only while that ending remains
  current. Create and trash retain their actual operation evidence without
  inventing an empty text preimage or deletion comparison. This evidence is not
  portable research history or a second source authority.
- Settings exposes Agent Integration instructions for Codex and Claude Code and
  reveals the bundled `scholium-core-protocol` Skill. External-host setup stores no credentials. In-app Chat separately retains
  public conversation state and selected runtime configuration.
- The Core Protocol uses ordinary Note operations for explicitly requested
  question/discussion writing. Substantive discussion does not authorize an
  automatic write or create an application-managed inquiry lifecycle.

## Deliberately unavailable

- The App contains no Research Actions, Reading Leads, passage Discussion,
  or Review Comment subsystem. In-app Chat is the bounded runtime client
  specified in §8.7; it is not a research-task lifecycle.
- The MCP server exposes no Resources, Prompts, Tasks, model invocation,
  acceptance, or research-result endpoints.
- There is no external-host conversation handoff service. The in-app client
  supports explicit source-selection attachment under §8.7; its current interface
  is recorded in the reachable-interface chapter.
