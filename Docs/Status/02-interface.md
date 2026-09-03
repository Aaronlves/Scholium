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
- Review and inactive Edit show a link annotation from one trailing superscript
  marker in the shared bounded preview surface, never as a block inserted into
  prose. Hover or focus reveals it, click keeps it open, and Escape or outside
  interaction dismisses it. Review previews linked Notes on hover; Edit follows
  the macOS Command-hover and Command-click convention with visible armed-link
  feedback, including links inside projected Callouts.
- Named and inline footnotes use the same superscript ordinal, bounded rendered
  preview, and Review end-note presentation. Review activation navigates to the
  end note and back; Edit activation reveals the exact named definition or
  inline range without adding another end section or writable text owner.
  Insert exposes neighboring Footnote and Inline Footnote commands with
  configurable Option-Command-N and Option-Shift-Command-N defaults.
- First ordinary Edit activation focuses the inline Note title at its end.
  Returning to an open Note restores its title/body focus and exact valid
  selection; final window persistence retains this lightweight state only for
  tabs that remain open, while explicit source locations and Managed New Note
  insertion take precedence.
- Review/Edit keep the visible Note title when a mode handoff occurs at the
  document start. Inactive Edit headings remove their opening Markdown marker
  from inline measure; active heading and quotation prefixes appear at the
  line's full computed size outside the prose measure without moving its text or
  neighboring blocks. Every authored blank separator remains one stable
  prose-height Edit row, without duplicate paragraph-end spacing or overlap. Exact
  spaces retain their authored width without acquiring visible whitespace
  markers. Normal prose uses language-aware line breaking and keeps closing
  punctuation with an adjacent footnote locator. Review and Edit use identical
  body and heading ink: body prose is a subtle Primary Text/Paper mix, while
  titles and headings retain Primary Text without creating another semantic
  color role.
- Review and Edit show Note-level document attachments directly below the
  filename title in one compact, horizontally scrolling capsule strip. Full
  filenames remain available through Help/accessibility despite bounded middle
  truncation; primary activation opens native Quick Look. The trailing Add
  control reveals on note entry and title/strip hover or focus without moving
  layout, while File provides permanent **Attach a Copy…** and **Reference
  Original…** routes. Source omits this source-neutral projection.
- Inspector presents Overview and Connect. Overview exposes current About,
  file, Settlement, Critique, and applicable Zotero facts and operations.
  Connect presents exact incoming or outgoing link occurrences, their local
  context, and any source-owned Markdown annotation. Incoming annotations are
  read-only and route editing to the source Note. It has no Actions mode.
- Search defaults to **All** and presents separate Notes and Research Records
  sections without cross-provider ranking. Notes and Records are directly
  selectable provider paths; scope remains This Note, This Vault, or Triptych.
  A Record hit opens the same Triptych-bound Records window at the matched
  Record and step.
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
  Agent picker, session, task, activity stack, or result-review workflow.
- **Research Records** opens a compact separate read-only window. Its fixed,
  non-collapsible left index scans current questions and last substantive times
  with system Record Search. The centered reading plane pins the question above
  independently scrolling chronological attributed steps. Each step presents
  its basis/modified Notes in one right-growing horizontal attachment strip;
  overflow scrolls, while each compact native button retains hover/focus/press
  feedback and adds Earlier/Unavailable only when needed. Step prose renders
  bounded basic Markdown; headings and unsupported constructs remain literal.
  A hidden title-bar style removes the separate toolbar band while preserving
  native window controls; Records refreshes automatically while visible.
  Escape closes the window, and opening an attachment dismisses Records after
  opening the Note in the exact originating Workspace window; it never creates
  another Workspace window. There is no Record content editor or detached
  evidence inspector.
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
