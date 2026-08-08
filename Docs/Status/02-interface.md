# Implementation Status: Reachable Interface

Part of the dated status set rooted at [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md).
This chapter records the user-facing interface reachable in the current build.
It does not define the target design or retain visual decision history. Target
behavior belongs to the Specification; outstanding acceptance belongs in
[Open Work](03-open-work.md); dated journeys belong in
[Verification Evidence](04-verification.md).

## App root, scenes, and shell

- Starting, Ready, and Storage Unavailable are separate app-root states.
  Storage Unavailable is a compact nonmodal page with Retry, selectable
  Details, and Quit; workspace commands remain disabled until validation
  succeeds.
- Bootstrap is a separate narrow window whose fixed Welcome, Triptych, Agent,
  and Ready artwork fields sit beside the real folder-selection and
  authorization controls without the former progress header or centered-symbol
  pages. The approved starting-point cards now drive two real paths: create one
  nonoverwriting Triptych root with Analyses, Topics, Works, and `.scholium`, or
  connect three existing folders and confirm the detected parent directly.
  On first setup, confirmation advances directly to optional Agent CLI, prompt,
  second-confirmation, and Set Up Later tasks while registration finishes in
  the background; failure returns to Triptych review and Ready remains gated.
  Later Triptych and recovery setup does not repeat Agent preparation. Ready
  explicitly opens the configured workspace,
  which uses one native
  Library–Document–Inspector split with AppKit-owned geometry and one stable
  toolbar.
- Each workspace window owns its Triptych assignment, shell presentation,
  selected Triptych workspace, three retained Library states and Document-tab
  groups, per-workspace Document/Inspector modes, Search, Attention, Research
  Action presentation, and exact-window command routing. Research Records is a
  separate Triptych-keyed utility window rather than focused-window state.
- Native Sidebar and Inspector toolbar controls remain immediately before
  their logical pane separators, mirror Show/Hide state, and have no persistent
  underline or selected enclosure. Toolbar commands and pull-downs now use
  AppKit's small toolbar-bezel control size with the original system body font
  and body-medium SF Symbol scale, so the system owns their native geometry,
  hover, press, focus, menu tracking, and disabled feedback. The
  Sidebar control remains reachable after native collapse without adding
  pane-corner duplicates or another geometry owner.
- One full-height document-navigation depth cue is reachable at the
  Sidebar–Document edge. It falls only into Library, mirrors for right-to-left
  presentation, adapts to appearance and display-accessibility settings, and
  leaves AppKit's thin tracking separator as the sole interactive divider.

## Library and navigation

- The Library presents the three workspace destinations through the vertical
  `ScholiumTriptychWorkspaceNavigator`. Each full-width row has one persistent
  selected surface, restrained hover/focus feedback, and a muted exact active-
  Note total. Selection performs the complete
  save/conflict-safe workspace transition rather than a vault-only Scope
  filter: each destination restores its Location, filters, sort, disclosure,
  tabs, selected document, Document mode, and Inspector mode. Rapid input
  converges on the latest destination; a failed preparation retains the origin.
  One shared SwiftUI/AppKit content-interaction resolver now supplies shallow
  hover and keyboard-focus surfaces to the file tree, workspace rows,
  Inspector modes and rows, Location controls, and Attention. Content hover
  uses one low-opacity semantic-ink veil that follows the native toolbar's
  relative light/dark feedback on each content plane; keyboard focus retains a
  stronger raised blend rather than collapsing hover, focus, and selection
  into one state. Custom
  button-like controls use one shared pointer-neutral, keyboard-complete focus
  policy rather than inspecting the current AppKit event after activation or
  changing focus behavior window-wide. The BrandHeader retains
  one transparent-at-rest Triptych Attention entry whose visible number is the
  aggregate queue total; zero keeps the entry without a number. The symbol and
  number share a text baseline and the 4pt label/accessory gap. Hover, focus,
  press, and the open popover surface the complete symbol-and-count target.
  The selected workspace's Location header and native scrolling source
  hierarchy remain. After a safe workspace commit, only Source List content
  settles downward from a shallow top origin while fading in; rapid input
  interrupts the presentation and Reduce Motion switches immediately. The
  LocationPicker and ordinary icons no longer use persistent Accent;
  LocationPicker now uses Regular secondary ink at rest, promotes to primary
  ink on interaction, and suppresses the native Menu hover enclosure. Matching
  Filter, disclosure, and Add controls reuse one exact 28pt editorial-control
  hover, focus, and press treatment across the complete native Button or Menu frame through one
  nonintercepting AppKit tracking adapter. Icon-only Menu hosts suppress their
  otherwise additional circular hover enclosure, leaving that shared rounded-
  rectangle surface as the sole feedback shape. Library, Set Aside, and Trash share the
  hierarchy and state presentation without mixing their lifecycle meanings.
- Add and blank-space context menus expose New Note and New Folder. Folder and
  Note context menus provide the relevant create, rename, move, lifecycle,
  relative-path, and Finder actions; equivalent accessibility actions and
  non-drag move routes remain available.
- The native outline owns row selection, keyboard traversal, restrained hover,
  disclosure, process-local drag, full-row drop feedback, autoscroll, and
  Folder destinations. The Location header owns the sole vault-root drop
  target. Source and destination rows update immediately after a committed
  move while derived state converges.
- New Note starts writing without a configuration sheet. The exact source and
  stable identity commit first; the selected row and Empty Note document state
  appear before a complete background rebuild. Filters clear only when they
  exclude the destination.
- Put Back is a direct row action available by pointer, keyboard focus,
  context menu, and accessibility action. Moving the currently presented Note
  to Set Aside or Trash clears Document rather than silently opening another
  lifecycle location.

## Search, Attention, and auxiliary Records

- Search exposes This Note, This Vault, and Triptych scopes with shared query
  parsing, completion, results, freshness, and explicit unsupported-field
  errors. Results route to exact Notes, source ranges, Records, or statements.
- Attention opens one transient anchored popover per workspace from Sidebar,
  Inspector, or Window menu. It retains the current queue on loading failure,
  dismisses natively, and keeps Inspect, Resynthesize, and Leave Unchanged
  explicit.
- The Research Records window uses a Navigation/Document split, independent
  Records and Recommendations views, a native Scope menu, shared search and
  filters, comparison, deletion, provenance navigation, recommendation
  handling, and researcher notes. Same-Triptych requests reuse one window;
  different Triptychs remain isolated.

## Document and editor

- One Document area owns one role-partitioned tab controller and presents only
  the selected workspace's group. Each group retains its selected tab, while
  one live Review/Edit/Source mode per workspace carries across that group's
  Note and tab changes and participates in window-session persistence. It also
  owns Heading Outline, This Note Search, This Note Records, and Inspector
  visibility. No selected
  document, empty source, loading, unavailable source, rendering failure,
  conflict, and retained recovery each have a distinct presentation.
- Page- and pane-level state copy is now rendered by one stateless Content
  State component across Document, Library, Search, Research Records,
  Attention, Checkpoint, Recovery, and applicable Settings regions. It keeps
  the approved restrained no-document scale, adapts between centered and
  compact-leading placement, and keeps repair actions in normal content flow;
  each workflow still owns its domain state and transition.
- Review and Edit share semantic document rhythm while Source remains exact
  text. Review owns its direct line-Comment surface; Edit owns formatting,
  Wikilink/Vector Link, task, context-menu, and input-suggestion interactions;
  Source owns none of those projections.
- Selection bars and suggestion panels remain anchored to the selected range
  or caret while scrolling, clamp or flip within the viewport, dismiss on the
  correct focus/mode boundary, and retain a draft only when the researcher has
  authored content that still needs a decision.
- Review footnotes, previews, navigation, and return remain read-only. Edit
  preserves one source caret, exact markers on active structures, source-line
  pointer mapping, list/task geometry, and one Undo transaction per semantic
  command.
- Conflict comparison binds the displayed editor and disk revisions, defaults
  to Compare, and enables Reload only for the still-current displayed disk
  revision. Recovery candidates remain available through the dedicated sheet.

## Inspector and Research Actions

- The Inspector has an equal-column Overview, Connect, and Actions ModeIndex
  with one retained selection per Triptych workspace and one window-wide native
  visibility state.
  Selection uses one shallow semantic editorial-control surface rather than an
  underline or shared segmented band; unselected hover uses a quieter surface
  with the same corner recipe, a 4pt adjacent-state gap, and no animation.
  Overview presents current
  Attention, role-aware About fields, Edit Properties, and Open in Zotero only
  for a keyed Analysis. Empty fields and protected machine keys remain quiet.
- Connect switches the same direct graph between native Incoming Links and
  Outgoing Links segments. Neutral and Incompatible relations appear in both
  with one source anchor. Visible Sans relationship subheadings carry symbol,
  complete name, and count; quiet Note rows preserve major-group counts and a
  separate named source-anchor action inside the Inspector's existing scroll
  owner.
- Actions presents the closed Platform catalog under Research and Review, with
  Settle under Judgment. Rows invoke the exact current-window route; Action
  availability clears while rechecking instead of retaining stale authority.
  Active Discussions resume from their own rows.
- The common Action sheet presents academic Profile inputs, target identity,
  whether the Action may change the document, Copy Handoff, Copy New Handoff,
  End Action, current result or recovery state, and explicit next steps. It
  does not expose implementation hashes, schema data, internal protocol prose,
  or a separate Pairing Code field.
- A Discussion sheet preserves passage Comments, whole-note turns, focal Notes,
  attributed replies, Copy Handoff, nonterminal Close, Finish, and End
  Discussion as distinct actions.

## Appearance, design system, and localization

- System, Light, and Dark appearance choices use one semantic native/WebKit
  role resolver. Navigation, Document, and Inspector/Apparatus surfaces remain
  distinct; Accent and Paper are the only configurable color inputs.
- Named Appearance configurations provide shared line width, Body and heading
  typography, and semantic Callout presentation. The built-in WebKit values
  derive from `DocumentAppearanceSettings.defaultSettings`; no parallel Native
  heading table remains. Advanced CSS operates on managed sanitized copies
  with validation, Safe Mode, and Disable All Snippets recovery.
- Semantic typography, grid, boundary, elevation, symbol, and purpose-named
  motion components are shared across workspace, editor, Inspector, and
  Research Records. Increase Contrast strengthens boundaries and removes
  custom soft shadows; Reduce Motion removes custom animation.
- English and Simplified Chinese catalogs are reachable. Stable identifiers,
  paths, exact Markdown, researcher-authored titles and prose, and Skill names
  remain verbatim.
