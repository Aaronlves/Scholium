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
  About editing, Settlement, Zotero bindings, transaction recovery,
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

- `scholium mcp serve` exposes eighteen MCP tools:
  `scholium_workspace_status`, `scholium_browse`, `scholium_search`, `scholium_read_note`,
  `scholium_list_links`, `scholium_show_note`, `scholium_list_attachments`, `scholium_read_attachment`, `scholium_create_note`, `scholium_update_note`,
  `scholium_preview_move`, `scholium_move_note`, `scholium_list_changes`, `scholium_read_change`, `scholium_undo_change`,
  `scholium_update_metadata`, `scholium_update_attachment`, and `scholium_trash_note`.
- The stdio server connects only to a running Scholium App for the current
  user. It does not launch the App, construct a headless workspace runtime, or
  read and write Triptych files itself.
- A single open Triptych can be selected implicitly. Multiple open Triptychs
  require an exact stable Triptych identity. Every mutating request flushes
  matching live editors, enters the Application source-operation gate, and
  checks the exact target fingerprint where applicable.
- Browse lists role roots or immediate directory/Note children, including empty
  directories, with bounded pagination and listing-revision checks. It reuses the
  current Library inventory and visibility rule; stable identities survive rename.
- Agent Metadata patches and document-attachment add/replace/remove use current
  Note/record versions, scoped Ask previews, Agent Changes and guarded Undo.
  Attachment sources are existing registered documents; files survive unlink/Undo.
- Note reads can explicitly include local managed Metadata and its revision,
  the exact saved Analysis Zotero binding and a first attachment-list page.
  This reuses current record owners and does not retrieve Zotero or file contents.
- Attachment listing proves current document relationships or registered authored
  images. Reads preserve file fingerprints, UTF-8 slice offsets and explicit PDF
  page coverage. Existing bookmark/containment owners govern originals and copies;
  PNG derivatives remain bounded, and empty extraction never implies a blank page.
  Chat distinguishes these observations from Note reading and mutation evidence.
- Note/passage display validates exact source and uses an explicitly named key
  window. Chat binds display to its admitted visible conversation and window
  instance. Changed, dirty, hidden, cancelled or superseded requests refuse;
  successful dispatch retains existing tabs and uses the ordinary locator.
  Native arrival/focus/selection remains human acceptance, not tool success.
- Link listing returns one authored occurrence per row, including exact
  occurrence/link/annotation markup, annotation text, local context, source
  fingerprint, and whole/link/annotation locators. It exposes only authored
  occurrence data.
- Update accepts body/source replacement or 1–100 exact UTF-8 range edits in
  one original revision. Insert, replace and delete share the same preview,
  source writer and Agent Change; invalid or stale patches fail without mutation.
- Create, update, move and trash write machine-local Agent Change evidence. Each
  update retains its own fingerprint-validated exact Before and After bytes;
  review compares the recorded After fingerprint with freshly loaded
  authoritative source and marks a superseded ending as an Earlier Revision.
  Confirmed update evidence supports direct Undo only while that ending remains
  current. Create and trash retain their actual operation evidence without
  inventing an empty text preimage or deletion comparison. This evidence is not
  portable research history or a second source authority.
- Move impact can be previewed through MCP: paged path/link effects and blockers
  carry exact identities and revisions. Chat identifies this as a preview of the
  current Note, with no write or Agent Change. Execution requires that exact
  plan, preserves stable identity/Metadata, and records every linked-source rewrite
  in one bounded Agent Change. Controlled inverse restores exact original bytes
  only if all identities/revisions and restored link resolution remain safe;
  partial failures retain existing per-file Recovery evidence.
- Agent Changes can be listed and compared through MCP with bounded results.
  Undo validates the exact Note/Change binding and current ending revision;
  repeated or ineligible recovery is refused. Chat Ask uses the reverse comparison,
  and successful Undo updates the original receipt without a new edit record.
- Settings exposes Agents & Chat instructions for Codex and Claude Code and
  reveals the bundled `scholium-core-protocol` Skill. External-host setup
  stores no credentials. In-app Chat separately retains public conversation
  state and selected runtime configuration; its token-scoped capability tools
  can manage runtime Skills, discovery roots, MCP connections and next-turn
  Chat settings through the existing owner.
- The Core Protocol uses ordinary Note operations for explicitly requested
  question/discussion writing. Substantive discussion does not authorize an
  automatic write or create an application-managed inquiry lifecycle.

- Chat offers a persistent Zotero read-only preset through its existing versioned
  runtime configuration editor. Disabled state survives reconnect; native
  Settings changes wait for idle, while explicit in-app Agent capability calls
  may configure the runtime during the admitted turn. Same-name custom
  connections are retained. Local API checks
  report disabled/unavailable/available separately from MCP connection state.
  The first-party read-only CLI publishes seven read tools and rejects imports
  before contacting Zotero. Annotation listing/selected reads verify the exact
  PDF relationship and snapshot; text, comment, printed label and physical page
  stay separate. Binding, Chat/Sources and MCP share validated Zotero locators.
  Original reads verify bounded local bytes, metadata and API-resolved paths,
  then return the selected text/page/image and original fingerprint through the
  shared attachment reader. Sources retains matching runtime material reports
  by turn/location, identifying server/tool, representation, fingerprint and
  bounded excerpts without promoting reported access to independent verification.

## Deliberately unavailable

- The App contains no Research Actions, Reading Leads, passage Discussion,
  or Review Comment subsystem. In-app Chat is the bounded runtime client
  specified in §8.7; it is not a research-task lifecycle.
- The MCP server exposes no Resources, Prompts, Tasks, model invocation,
  acceptance, or research-result endpoints.
- There is no external-host conversation handoff service. The in-app client
  supports explicit source-selection attachment under §8.7; its current interface
  is recorded in the reachable-interface chapter.
