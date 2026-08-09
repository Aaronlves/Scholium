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
  One shared native content-interaction resolver now supplies shallow hover,
  press, selection, and keyboard-focus surfaces to workspace rows, Inspector
  modes and rows, Location controls, Attention, and matching Records controls.
  Ordinary SwiftUI Buttons use one shared transient-state owner through their
  semantic styles; native Menu labels use one bounded AppKit tracking adapter.
  Content hover
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
  hover, focus, and press treatment across the complete native frame. Buttons
  use the shared style; Menus alone use the nonintercepting tracking adapter.
  Icon-only Menu hosts suppress their
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
- The Research Records window opens as a full-width Records or Reading Leads
  collection with a native-toolbar shallow-surface View index, no underline,
  and one adaptive content header for continuous search and native Scope/filter
  menus with plain host presentation and one Menu-label feedback adapter. The
  toolbar index is the visible identity and carries no count; search
  expands into the available width.
  Rule-separated compact 48pt rows use one continuous rounded hover/focus/press
  surface, omit duplicated long synopsis, resolve their bounded scroll range
  before interaction, and use no automatic selection. Identity has no
  explanatory subtitle. Triptych Records show an unlabeled Attention gutter,
  one two-line Record cell, Action, and Date. Record uses the strict frozen
  title and the second line is muted focal-Note context; This Note omits that
  redundant line. Attention shows only an explicit
  exception for Blocked or limited/unavailable/missing Analyze
  Reliability/Coverage; normal rows stay empty. Action is a centered text-only
  neutral capsule without icon or category color. Completed is implicit, and
  source and Method remain in detail. The collection is flat, defaults to finish
  date descending, and offers provider-owned Record, Action, and Date sorting.
  It shows no visible content title, Pin, generated Research Result synopsis,
  source line, note count, or date group. Reading Leads share the same header,
  row-height, separator, and interaction rhythm. Their visible header begins
  with Title; a visually unlabeled 32pt checkbox track retains the accessible
  Handled label 8pt before it, followed by Author(s), Year, and Publication.
  Academic Record and Lead values use regular 12pt Scholarly body, Note names
  and unavailable-field state remain Sans, and capsules use 10pt. Reason,
  uncertainty, locators, researcher note, and parent context live in detail.
  Whole-row destinations omit redundant trailing
  chevrons while Handled remains independent. One item replaces the collection;
  each ledger loads exact 100-row slices and shows its exact filtered total in
  the first content-column header; later-page failure retains loaded rows and
  exposes Retry.
  native-toolbar Back retains collection state. A selected Record uses a
  reading-first plane and a default-expanded, toolbar-collapsible Evidence &
  Judgment rail on one Document background with one divider and one
  full-height reading-evidence depth cue cast into the rail. A Reading Lead
  uses one centered reading flow rather than a second split workspace. Its
  header disposition button publishes a prominent **Mark as handled** to
  neutral **Handled** transition immediately while the atomic Record write and
  Workspace refresh continue, then reconciles or rolls back. A selectable muted
  full citation sits above the adaptive information band. Bibliography retains
  structured publication facts, DOI, and Zotero key in the wider column while
  Discovery Locators uses the bounded peer column; the two groups stack at
  narrow widths before the academic reason and uncertainty. The
  window now removes `fullSizeContentView`, so AppKit's content-layout rectangle
  prevents every collection and detail scroll owner from entering the titlebar.
  Toolbar and automatic shared-item backgrounds remain hidden without Liquid
  Glass or a masking overlay.
  Its nonduplicative header omits repeated completion while important empty
  sections state their condition. Reading-plane sections share one heading recipe;
  statements align colored, labelled Researcher/Agent authorship beside Serif
  academic prose. The prototype-derived Evidence ledger aligns every section
  header, uses Sans Note/Record names, `mutedText` provenance, Serif testimony,
  and quotation symbols for Context Used. Participants and Context Used preview three useful
  rows and open complete native popovers; Effects and saved researcher judgment
  remain visible. Safe destinations use complete rounded rows; unresolved
  locators stay selectable. Evaluation opens a draft-protected sheet, Technical
  Details folds schema/provenance, and Bibliography and technical identity reuse
  Inspector About's adaptive label/value grid with 12pt scholarly or exact
  values. `trash` owns confirmed deletion.
  Inline comparison and Method Feedback are absent. Same-Triptych
  requests reuse one window; different Triptychs remain isolated.

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
  authored content that still needs a decision. Their WebKit hover, press,
  keyboard-focus, and listbox-selection presentations now consume the same
  semantic interaction resolver as matching native content controls rather
  than a separate raised-surface recipe. Callout disclosure and document
  control focus rings use the shared Accent role.
- Review footnotes, previews, navigation, and return remain read-only. Edit
  preserves one source caret, exact markers on active structures, source-line
  pointer mapping, list/task geometry, and one Undo transaction per semantic
  command. Review preview delegation treats pointer and keyboard focus as
  equivalent entry routes and closes when either leaves the originating link
  or footnote.
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
- The Action sheet and the Research Records Reading Lead note and Researcher
  Evaluation sheets now share one editorial layout grammar: primary-title
  header, independently scrolling content, structural rules, and a fixed
  trailing action region. Purpose-owned size constraints and workflow state
  remain separate; native sheet presentation and elevation remain AppKit-owned.
- When the authenticated Agent chooses Continue Research, the completed child
  is shown beneath the parent Action in one read-only continuation section; the
  Action sheet exposes no Continue Research command or credential.
- A Discussion sheet preserves passage Comments, whole-note turns, focal Notes,
  attributed replies, Copy Handoff, nonterminal Close, Finish, and End
  Discussion as distinct actions.

## Appearance, design system, and localization

- System, Light, and Dark appearance choices use one semantic native/WebKit
  role resolver. Navigation, Document, and Inspector/Apparatus surfaces remain
  distinct; Accent and Paper are the only configurable color inputs.
- Native feature views now select semantic foreground, surface, boundary, and
  status roles without direct system primary/secondary styles, AppKit palette
  access, or leaf-owned percentage tints. Search highlight and structural
  shadow are named system-effect exceptions; Bootstrap narrative art and the
  fixed Markup highlight remain the closed nonconfigurable exceptions.
- WebKit document HTML receives its resolved Light, Dark, and Increase Contrast
  declarations from `ScholiumWebDesignTokens`. Authored Editor CSS only
  consumes the generated properties and no longer carries a fallback palette.
- Named Appearance configurations provide shared line width, Body and heading
  typography, and semantic Callout presentation. The built-in WebKit values
  derive from `DocumentAppearanceSettings.defaultSettings`; no parallel Native
  heading table remains. Advanced CSS operates on managed sanitized copies
  with validation, Safe Mode, and Disable All Snippets recovery.
- Native custom text uses one three-family resolver: Interface, Scholarly, and
  Exact. Feature-specific Library, Apparatus, Research Records, and Chrome font
  aliases are absent; a shared 17pt Interface primary title and 20pt Scholarly
  research-object title replace them. Emphasis and tabular figures remain
  orthogonal inputs. Brand/Bootstrap hero typography and component-owned Symbol
  scale are the bounded exceptions. Presentations no longer declare fixed point
  sizes, raw SwiftUI text styles, direct SwiftUI system fonts, or leaf-owned
  font weights. Standard controls remain platform-owned, all bundled Alegreya
  and Victor Mono faces resolve through AppKit, and Document remains CSS-owned.
  Grid, boundary, elevation, corner, symbol, and purpose-named motion
  components remain shared. Custom corner geometry now has one closed semantic
  owner across Native and WebKit: leaf Views and resource styles contain no raw
  radius, Search uses container-concentric geometry for its nested availability
  banner, and native and Review Comment multiline editors share the same
  editorial-text-editor recipe. Increase Contrast
  strengthens boundaries and removes custom soft shadows; Reduce Motion removes
  custom animation.
- The shared native spacing foundation is now explicit at every matching leaf
  call site: 4/8/12/16/20pt gaps and insets consume the purpose-named Grid
  roles. Zero spacing, native geometry, window/component dimensions, Document
  CSS rhythm, and remaining component-specific cadence are not reclassified as
  shared spacing merely because their values are numeric.
- Research Guidance now has one component-level layout owner for its category
  Sidebar constraints and explanatory Method/Profile/Practice collection rows.
  The shared row preserves the existing left-copy/right-action structure and
  measurements without taking ownership of setting values or operations.
- English and Simplified Chinese catalogs are reachable. Stable identifiers,
  paths, exact Markdown, researcher-authored titles and prose, and Skill names
  remain verbatim.
