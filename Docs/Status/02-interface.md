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
- The Sidebar begins with a persistent native Search field, a neutral workspace
  segmented control, and the muted Library operation row. It has no wordmark
  header. Notifications uses a native toolbar button with a nonnumeric
  badge and exact count in native Help. It aligns with the expanded Sidebar
  trailing edge and reflows natively when Sidebar collapses. File/Settings/Window retain Triptych management.
  Every toolbar component now uses native state rendering and one window-derived
  enablement route for presentation, toolbar/overflow validation, and action
  dispatch. There are no custom unavailable animations or Settlement icon tints.
  Invalidation cancels subscriptions and detaches controls; document/revision
  changes close stale Settlement popovers. Outline and Inspector expose the
  same no-document prerequisite through native disabled state and Help.

## Library, Document, and Inspector

- Library presents Analyses, Topics, and Works through native single-choice
  segments. Complete localized labels adapt to role symbols at narrow widths;
  selection and disabled-workspace semantics remain native. The file tree keeps
  source-list selection, keyboard focus, disclosure, and normal native row size.
  Organize and Add remain separate native menus. File-tree rows use the Finder-style native grid: AppKit owns
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
  command list, including Move Note. The native outline receives enlarged-interface
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
- Notification row pointer tracking now clips its observation view to its own
  bounds, intersects the visible region, retains tracking identity, and clears
  published hover on detach/window changes. Viewport bounds changes reconcile
  a stationary pointer after scrolling. On 2026-09-06, six focused tracking and
  interaction tests passed. The native probe reproduced parent-sized visible
  rectangles before clipping; QA scrolling no longer showed accumulated row
  fills. The updated disposable QA remains open for researcher pointer acceptance.
- Notification delivery now uses one App-level UserNotifications owner for
  confirmed background MCP changes. First delivery requests system permission;
  foreground activity remains in the bell/local Note state. Generic system text
  carries no Note title, path, or source, and click routes validate exact receipts.
  The top overlay, global priority/expiry stack, and Settings feedback queue are
  removed. Operation failures remain persistent locally; ordinary success is quiet.
  On 2026-09-06, 48 focused tests passed, including first authorization, denial,
  concurrent delivery, foreground cancellation, coalescing, exact click routing,
  and a memory-only cold-window handoff that cannot replay during restoration.
  Disposable 500-Note QA checked light/dark, 500-point width, local warning
  wrapping/actions, dismissal with editor focus, the bell, and Settings.
  The complete verifier passed Core, Contracts, and Application but failed App
  tests on editor, typography, scroll, and localization assertions. Two new raw
  typography references were corrected and rechecked; other failures remain.
  Real system permission/click delivery, full VoiceOver, and system accessibility
  adaptations remain unverified. No release or human acceptance is claimed.
- Editor and reader previews now use native glass containers with inert local
  WebKit content. Completion retains CodeMirror's keyboard and AX listbox while
  native rows project the results. A native parent separates their geometry and
  accessibility from the document WebView; no source or history is moved.
- Document retains Review, Edit, and Source over one exact source buffer.
  Edit selection has no floating formatting bar; native menus, shortcuts, and
  Markdown input retain formatting and insertion commands.
  Markdown is the sole written annotation authority; there is no separate
  Review Comment or passage Discussion UI.
- Appearance exposes body and Source font/size, line width/spacing. Advanced typography remains in editable `appearances.json` with
  a Finder route, guide and explicit reload. Invalid or stale external edits
  cannot replace the loaded appearance or be overwritten by a stale GUI save.
- About and Metadata expose managed values only; authored YAML has no field
  editor. YAML remains above the title: Review shows source text and Edit allows direct
  editing. Initial title positioning leaves it above the viewport; Source retains
  exact source. Disclosure controls and automatic collapse have been removed. Ordinary New Note creates no YAML scaffold.
- Document activation now resets opening position separately from editor
  reconstruction. Readiness is keyed to each opening; pending Edit no longer
  exposes a temporary Review layout. Mathematics and cached reopening pass
  regression checks. A user recording subsequently captured one YAML frame
  before title positioning; post-readiness geometry tests alone missed it.
  Pending presentation now covers live WebKit instead of hiding its layout,
  and readiness awaits CodeMirror's measured title-position writes.
  A 25-second disposable QA recording (1,427 decoded frames) had no YAML OCR
  hits during repeated switching; visual review and upward-scroll/reopening
  checks passed. Four focused regression tests passed. This is bounded QA,
  not proof against every compositor timing. Four-opening measurements showed
  roughly 60 ms additional warm-opening latency; no fixed delay was added.
- Frontmatter scroll cutover: title-position and exact-source/Undo integration
  checks pass, including deferred scroll restoration. Disposable QA confirms
  opening at the title and scrolling upward to the indented YAML region.
- Earlier 2026-09-06 verification: appearance file reload, invalid/stale edits, exact
  YAML projection and Undo passed focused tests. Disposable 500-note QA
  visually checked light/dark Appearance, pane resizing, reload/error recovery,
  YAML on/off in Review/Edit, full Source, managed About and YAML-free creation.
  The follow-up resolved all 10 baseline failures: native Settings has an
  explicit system-style boundary, preview tests use the native host, and newer
  focus requests supersede delayed navigation callbacks. The complete repository
  gate passes, including 609 App tests, symbol-graph validation and Release build.
  Computer Use checked Settings, navigation-to-Review focus and native annotation
  previews. One isolated QA remains available at the researcher's request.
  VoiceOver and system accessibility overrides were not manually exercised;
  a successful Release build is not packaged-release acceptance.
- Subsequent Settings polish shortens the two integration toolbar labels and
  anchors native frame interpolation at the current top-left corner. The
  scene's flexible content boundary prevents pane layout from interrupting
  expansion. The researcher accepted the animation; Computer Use checked all
  seven panes after spacing adjustments, including short-pane search visibility.
  Metadata single-field lookup no longer rebuilds the complete presentation
  catalog. Owning suites passed (44 tests; final spacing follow-up 24 tests).
  This scoped follow-up did not repeat the earlier complete repository gate.
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
  from inline measure; short active delimiters expand inside the measure with
  reversible local motion. Leading prefixes can borrow available whitespace
  when their reveal alone would wrap prose. Expanded Callouts keep their editable
  source lines, role label, and header/body surface across activation; folding
  is a separate source-neutral disclosure. Literal HTML no longer swaps widgets. Every authored blank separator remains one stable
  prose-height Edit row, without duplicate paragraph-end spacing or overlap. Exact
  spaces retain their authored width without acquiring visible whitespace
  markers. Normal prose uses language-aware line breaking and keeps closing
  punctuation with an adjacent footnote locator. Review and Edit use identical
  body and heading ink: body prose is a subtle Primary Text/Paper mix, while
  titles and headings retain Primary Text without creating another semantic
  color role.
- Overview shows document attachments through native previews over the retained
  document session, with consistently actionable filenames above previews, one multi-file selection
  menu/count, bounded
  thumbnail access, system Quick Look with its native opening actions,
  and File-menu copy/reference. The old document
  strip and its editor/reader protocol routes are removed.
- Inspector presents About and Links through a native rounded
  icon-only toolbar group. About exposes current About, file, Settlement,
  and applicable Zotero facts and operations. Metadata uses aligned native
  fields with visible editing frames and explicit revision-bound recovery.
  One NSGridView aligns labels and values at 13 points; creator rows retain
  Last Name then First Name across editing, commit and cancellation. Escape
  restores the acknowledged value without replacing the native field editor.
  Zotero is separated by a divider; dates and Settlement appear in collapsed
  File Information below attachments. Note notifications use the existing
  session to summarize all categories, independently of its prior filters.
  Fields use one stable native text control, commit on focus departure, and
  traverse creator subfields and adjacent fields with Tab/Shift-Tab. Return
  submits; Escape discards only changes since the last acknowledged save.
  The inline Save/Cancel footer is removed. Inspector projection changes save
  without discarding drafts; Note/window departure drains the active field before proceeding. Errors preserve the current Note
  and restore its Library selection; successful retry clears that failure.
  Outgoing and Incoming
  group exact occurrences by peer Note, with counts and source line context.
  The whole Note heading toggles disclosure; its contextual action opens the
  peer. Passage targets use ordinary native buttons with hover feedback; their
  selected-occurrence state, toggles and selected accessibility traits are removed.
  Review reveals the source locator and briefly highlights its visual line without
  replacing the reading selection; Edit/Source add a transient line decoration
  to the existing explicit navigation. The marker expires, repeats on activation,
  and clears on replacement/teardown without source writes or history entries.
  It fades in, holds and fades out; Reduce Motion keeps it static. Outgoing destination navigation remains
  separately available. Source-owned Markdown annotations remain visible. Incoming annotations are
  read-only and route explicit editing to Source. Ordinary links retain the
  current Document mode and locate the rendered block or editor line after
  presentation readiness. It has no Actions mode.
- Search uses a persistent native field. Its magnifying-glass menu contains
  scope, content type, Clear Filters, and the quick-only Advanced Search entry.
  The advanced window retains query/results when opening a Note, keeps Saved
  Searches in a compact action line, and exposes concise query conditions in a
  transient information popover. Native Search-field composition owns input;
  there is no second query draft or centered overlay.
  Results now use the native inset List's selection, with interface typography,
  document symbols, a bounded snippet, and compact location/reason text.
  Native content-state views distinguish the initial query prompt, empty results,
  and actual provider failure; unqueried default availability is not displayed.
- Search presents Note results; questions in Works use the same result and opening path.

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

- **Operation History** has an independent menu entry and a native collection
  over retained machine-local Agent Changes. Closing a notification does not
  remove it. Inspector controls and notification search menus use AppKit
  presentation on purpose-owned backgrounds; no custom Paper button skin remains
  in the changed Inspector controls.
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
