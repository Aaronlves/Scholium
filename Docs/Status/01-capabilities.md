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
- Search contract 14 has independent Note and Research Record providers. Note
  title identity uses managed Analysis title then filename, and filename for
  Topics and Works; body headings remain independently searchable. All
  runs both and returns separate rankings, totals, offsets, continuations, and
  generations; Notes and Records are dedicated paths. Record scope follows
  exact current Note references and never treats a reference as query text.
- Strict portable Research Records are reachable under
  `.scholium/inquiry-records/v1/`. Create, substantive append, paged read, and
  append-only clerical correction preserve external-Agent attribution,
  Record-file CAS fingerprints, chronological history, and exact Note
  references. A damaged file is isolated from valid Records.

## External Agent collaboration

- `scholium mcp serve` exposes exactly ten MCP tools:
  `scholium_workspace_status`, `scholium_search`, `scholium_read_note`,
  `scholium_read_record`, `scholium_list_links`, `scholium_create_note`,
  `scholium_update_note`, `scholium_trash_note`,
  `scholium_record_progress`, and `scholium_correct_record_step`.
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
  reveals the bundled `scholium-core-protocol` Skill. Scholium stores no Agent
  credential, session, task, Run, or host preference.
- The Core Protocol directs the Agent to maintain one continuing Record per
  independently developing question after substantive steps. MCP itself only
  validates identity, request shape, current revisions, and storage. Record
  writes produce no Agent Change and never imply permission or acceptance.

## Deliberately unavailable

- The App contains no Agent chat, Agent lifecycle, Research Actions, Handoff,
  Reading Leads, passage Discussion, or Review Comment subsystem.
- The MCP server exposes no Resources, Prompts, Tasks, model invocation,
  acceptance, or research-result endpoints.
- Research Record deletion, merge/split, and write suspension plus Handoff
  remain future §22 decisions, not current implementation claims.
