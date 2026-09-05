# Implementation Status: Reachable Interface

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Current user-facing reachability.

## App root and workspace shell

- Ordinary command buttons share a native style adapter with neutral Ink;
  destructive roles retain semantic tint. Window roots, independently hosted
  split regions, and sheet/popover content install the same default; local form choices use its shared
  entry. Icon Buttons, icon Menus, and Notifications share one native chrome
  recipe. Feature-owned prominent styles and local tint overrides are removed;
  selection, links, and explicit status indicators retain their semantic colors.
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
- AppKit's Sidebar split item now owns the complete regular Liquid Glass
  navigation plane. The adjacent Document Paper surface extends beneath it
  through the native safe-area contract; Sidebar content adds no custom fill,
  visual-effect host, or edge shadow. Document and Apparatus remain continuous
  through the transparent titlebar with no separate toolbar band. Standard
  AppKit toolbar items own their native Liquid Glass, and compact Sidebar-header
  controls retain their established 28pt targets. The 70 × 20 Inspector
  projection control and split geometry remain unchanged.
- The Sidebar header presents the Scholium wordmark as its primary brand title,
  with Search and Notifications controls at the logical trailing edge and no
  persistent Triptych selector. File owns New/Open Triptych, Settings manages
  registrations, and Window owns switching among open windows. Distinct
  concurrently open Triptychs receive native window subtitles; one Triptych
  does not. A nonzero
  queue uses one Accent dot on the
  bell, keeps its exact count accessible, and never prints a numeric counter.
  The toolbar shows Agent Changes only while confirmed local changes exist.

## Library, Document, and Inspector

- Library presents Analyses, Topics, and Works through a native source-list
  navigator whose shared input-modality adapter keeps pointer selection quiet
  and enables native emphasized-row focus for keyboard entry and navigation.
  The selected row is the sole visible focus indicator, so the source-list
  containers suppress their duplicate perimeter rings. AppKit still owns
  selection drawing, first-responder routing, active/inactive appearance,
  pointer behavior, and Up/Down traversal. Its native outline likewise owns row
  selection, focus, disclosure, and drag feedback;
  both lists follow AppKit's effective source-list size, with the large system
  row style used for enlarged interface presentation. Scholium supplies
  semantic text colors, exact counts, content, and valid actions. Scholium is
  the brand title and Library is its muted subordinate section; the Library's
  Organize and Add actions are separate borderless native menus, with global
  Folder disclosure inside Organize. File-tree rows use the Finder-style native grid: AppKit owns
  the Folder disclosure gutter and its state, monochrome Folder and Note symbols
  share the item-type column, and their titles share the following text column.
  The 16pt Library hierarchy step is applied through AppKit's native outline
  indentation property rather than custom row positioning.
  The projection omits the application-owned root `Attachments` directory and
  descendants without altering their stored files.
- Library distinguishes a filtered empty result from a genuinely empty tree,
  retaining its existing Clear route. Organize separates link-annotation presence
  from Integrity, combines Metadata into one group, and exposes sorting choices
  directly. Note context menus and accessibility actions share the same file
  command list, including Move Note. Both native lists receive enlarged-interface
  row sizing on creation and subsequent presentation updates.
- Standard Sidebar controls and navigation rows retain their native macOS
  cursors. The Sidebar adds no global pointing-hand remapping, custom row-hover
  tracker, parallel selection painter, or custom disclosure gesture. Existing
  custom and WebKit link-equivalent surfaces outside this slice retain their
  bounded cursor adapters.
- Document Find floats at the Document's upper trailing corner with an AppKit
  search field, native options menu, and shared native Liquid Glass. Its short slide
  and fade leave the document viewport fixed and interactive; Reduce Motion
  disables the transition. Replace expands downward with aligned fields and a
  distinct menu route. The panel adds no document padding or scroll headroom.
  Narrow reflow retains field identity, active
  options stay visible, and dismissal restores native editor focus.
- Search, progress overlays, and notification banners share the native floating
  material entry. Operation feedback and derived-refresh notices use one banner
  component; transient lifetime, persistent dismissal, and queue ownership remain
  with their existing policies. Inline integrity/recovery content stays opaque.
- Editor and reader previews now use native glass containers with inert local
  WebKit content. Completion retains CodeMirror's keyboard and AX listbox while
  native rows project the results. A native parent separates their geometry and
  accessibility from the document WebView; no source or history is moved.
- Document retains Review, Edit, and Source over one exact source buffer.
  Edit selection has no floating formatting bar; native menus, shortcuts, and
  Markdown input retain formatting and insertion commands.
  Markdown is the sole written annotation authority; there is no separate
  Review Comment or passage Discussion UI.
- Appearance profiles include Source font and size. Settings lists installed
  font families without restricting them to monospaced choices; saved changes
  update the retained Source presentation without changing source or selection.
  Profiles missing the required Source settings fail the existing manifest
  validation and remain byte-unchanged and nonmodifiable; this pre-production
  cutover adds no automatic conversion of older appearance profiles.
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
- First ordinary Edit activation focuses the authored body start after YAML,
  or an exactly mapped Review selection when no retained editor selection exists.
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
- Inspector presents Overview, Outgoing, and Incoming through a native
  icon-only toolbar group. Overview exposes current About, file, Settlement,
  Critique, and applicable Zotero facts and operations. Outgoing and Incoming
  present flat exact occurrence lists without peer-role folders, including
  local context and source-owned Markdown annotation. Incoming annotations are
  read-only and route editing to the source Note. It has no Actions mode.
- Search defaults to **All** and presents separate Notes and Research Records
  sections without cross-provider ranking. Notes and Records are directly
  selectable provider paths; scope remains This Note, This Vault, or Triptych.
  A Record hit opens the same Triptych-bound Records window at the matched
  Record and step.
- System-Trash confirmation describes the exact source and any managed Critique
  moved with it. Recovery stays with the existing bounded transaction owner.
- One separately spaced native Settlement toolbar button sits immediately before
  Document Mode. It presents **Settle** or **Settle Again**, keeps Unsettled
  monochrome, uses a filled Confirmed bookmark for Settled, and a distinct
  Attention bookmark for Changed Since Settle. It keeps ordinary native material
  and updates immediately without a custom animation timer. Its accessible label
  distinguishes the retained state as well as the next action. An external source
  change does not clear or rewrite Settlement;
  only the researcher's explicit settlement action records a new revision.

## Agent Integration and Agent Changes

- Settings includes **Agent Integration**, with copyable Codex and Claude Code
  MCP registration commands, live App/bridge/CLI availability, and a Finder
  route to the bundled Core Protocol Skill.
- Agent conversation remains in the external host. Scholium shows no chat,
  Agent picker, session, task, activity stack, or result-review workflow.
- **Research Records** opens a compact separate read-only window. Its list
  scans current questions and last substantive times with system Record Search.
  Its task-only native titlebar and content follow the selected light/dark scheme.
  Selecting a Record opens its detail; Back returns to the retained selection.
  The centered reading plane pins the question above
  independently scrolling chronological attributed steps. Each step presents
  its basis/modified Notes in one right-growing horizontal attachment strip;
  overflow scrolls, while each compact native button retains hover/focus/press
  feedback and adds Earlier/Unavailable only when needed. Step prose renders
  bounded basic Markdown; headings and unsupported constructs remain literal.
  The native titlebar names Research Records without a Triptych subtitle;
  Records refreshes automatically while visible.
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
