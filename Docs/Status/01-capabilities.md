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
- Search is Note-only. This Note and available vault-scoped lexical search use
  current source and rebuildable projections; no removed research-object corpus
  participates.

## External Agent collaboration

- `scholium mcp serve` exposes exactly seven MCP tools:
  `scholium_workspace_status`, `scholium_search_notes`,
  `scholium_read_note`, `scholium_list_links`,
  `scholium_create_note`, `scholium_update_note`, and
  `scholium_trash_note`.
- The stdio server connects only to a running Scholium App for the current
  user. It does not launch the App, construct a headless workspace runtime, or
  read and write Triptych files itself.
- A single open Triptych can be selected implicitly. Multiple open Triptychs
  require an exact stable Triptych identity. Every mutating request flushes
  matching live editors, enters the Application source-operation gate, and
  checks the exact target fingerprint where applicable.
- Create, update, and trash write machine-local Agent Change evidence. Confirmed
  update evidence supports direct Undo only while current source still equals
  the recorded after fingerprint. This evidence is not portable research
  history or a second source authority.
- Settings exposes Agent Integration instructions for Codex and Claude Code and
  reveals the bundled `scholium-core-protocol` Skill. Scholium stores no Agent
  credential, session, task, Run, or host preference.

## Deliberately unavailable

- The App contains no Agent chat, Agent lifecycle, Research Actions, Handoff,
  Research Records, Reading Leads, passage Discussion, or Review Comment
  subsystem.
- The MCP server exposes no Resources, Prompts, Tasks, model invocation,
  acceptance, or research-result endpoints.
- Future Research Records and Handoff remain specification targets under §22,
  not current implementation claims.
