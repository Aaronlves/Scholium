# Implementation Status: Reachable Interface

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Current user-facing reachability.

## App root and workspace shell

- Starting, Registry Recovery, Ready, and Storage Unavailable are distinct app
  roots. Failure states retain Details, Retry, and the applicable recovery or
  Quit route while workspace commands remain disabled.
- Bootstrap creates or connects one Triptych and explicitly enters the
  workspace. Configured windows use one native Library–Document–Inspector split
  and one stable toolbar.
- Native Sidebar and Inspector controls mirror actual split visibility. AppKit
  owns window, toolbar, divider, collapse, resize, fullscreen, and focus
  behavior. Each workspace window retains its own Library, document tabs,
  Document mode, Inspector mode, Search, and Attention presentation.

## Library, Document, and Inspector

- Library presents Analyses, Topics, and Works as peer destinations with stable
  selection, keyboard navigation, filters, ordering, disclosure, and source
  mutation routes.
- Document retains Review, Edit, and Source over one exact source buffer.
  Markdown is the sole written annotation authority; there is no separate
  Review Comment or passage Discussion UI.
- Inspector presents Overview and Connect. Overview exposes current About,
  file, Settlement, Critique, and applicable Zotero facts and operations.
  Connect presents exact incoming or outgoing link occurrences, their local
  context, and any source-owned Markdown annotation. Incoming annotations are
  read-only and route editing to the source Note. It has no Actions mode.
- Search presents Note results only and never mixes removed research-object
  results into its scope or completion vocabulary.
- System-Trash confirmation describes the exact source and any managed Critique
  moved with it. Recovery stays with the existing bounded transaction owner.
- The Document Rail presents **Settle Again** for both Settled and Changed since
  settlement. An external source change does not clear or rewrite Settlement;
  only the researcher's explicit settlement action records a new revision.

## Agent Integration and Agent Changes

- Settings includes **Agent Integration**, with copyable Codex and Claude Code
  MCP registration commands, live App/bridge/CLI availability, and a Finder
  route to the bundled Core Protocol Skill.
- Agent conversation remains in the external host. Scholium shows no chat,
  Agent picker, session, task, activity stack, result review, or Research
  Records window.
- **Agent Changes** presents one machine-local MCP mutation at a time in
  confirmation order, with Previous/Next controls and an exact position. Every
  retained update is bound to one `(change ID, Note ID)` and presents its own
  Before and After unified source comparison. Removed and inserted rows use
  restrained semantic red/green fields plus `−`/`+` markers; source blank lines
  remain visually blank. Markers, line numbers, and accessibility semantics
  preserve the distinction without color, while Revision Details progressively
  discloses line-ending, fingerprint, and BOM evidence.
- A recorded After revision that is no longer authoritative is labelled
  **Earlier Revision** rather than overlaid on current prose. A confirmed update
  offers direct Undo only while its exact After fingerprint remains current,
  after native confirmation. Create shows content only when the created
  revision is still current; trash shows identity, location, and Finder-owned
  recovery without a fabricated text diff. Agent Changes does not express
  researcher acceptance or Settlement.
