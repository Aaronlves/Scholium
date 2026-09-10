# Implementation Status: Reachable Interface

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Current user-facing reachability.

Selection Actions now use the existing native floating surface in Review, Edit
and Source. Ask Agent and the View-menu shortcut stage a checked passage in the
existing Chat composer, preserve its draft, and never send automatically.
Review currently maps source-identical blocks; formatted/synthesized blocks
require Edit or Source. Material source opening verifies the excerpt and revision,
then restores its exact Review selection where renderable, otherwise its Source
range for editable Notes. Unrepresentable read-only ranges retain their preview
and a visible limitation. Ordinary line references retain line arrival. Native
composer first-responder transitions now drive the focus binding; revealing
already-visible Chat does not toggle the Sidebar closed.

## App root and workspace shell

- Ordinary command buttons share a native style adapter with neutral Ink;
  destructive roles retain semantic tint. Window roots, independently hosted
  split regions, and sheet/popover content install the same default; local form choices use its shared
  entry. Icon Buttons, icon Menus, and Notifications share one native chrome
  recipe. Some feature routes, including Chat Send, use native prominence and shared Accent;
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
  controls retain their established 28pt targets. The native Inspector
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
  changes close stale Settlement popovers. Inspector controls expose the
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
- Notification row pointer tracking clips to its visible bounds and clears
  transient state on detach/window changes. Pointer acceptance remains open.
- Notification delivery now uses one App-level UserNotifications owner for
  confirmed background MCP changes. First delivery requests system permission;
  foreground activity remains in the bell/local Note state. Generic system text
  carries no Note title, path, or source, and click routes validate exact receipts.
  The top overlay, global priority/expiry stack, and Settings feedback queue are
  removed. Operation failures remain persistent locally; ordinary success is quiet.
- Editor and reader previews now use native glass containers with inert local
  WebKit content. Completion retains CodeMirror's keyboard and AX listbox while
  native rows project the results. A native parent separates their geometry and
  accessibility from the document WebView; no source or history is moved.
- Document retains Review, Edit, and Source over one exact source buffer.
  Edit selection has no floating formatting bar; native menus, shortcuts, and
  Markdown input retain formatting and insertion commands.
  Markdown is the sole written annotation authority; there is no separate
  Review Comment or passage Discussion UI.
- Appearance exposes body and Source font/size, line width/spacing, plus a
  scrollable typography form for paragraph/indent spacing, alignment,
  role-specific Bold/Italic faces, heading type, weight, spacing and level
  hierarchy. Letter/word spacing, hyphenation and kerning/ligatures are no
  longer structured profile fields or native controls; Advanced CSS is their
  explicit content-layer surface. CSS snippets remain separately managed with
  a Finder route, guide and explicit reload. Invalid or stale external edits
  cannot replace the loaded appearance or be overwritten by a stale GUI save;
  document CSS and text colors remain content-layer values.
- About and Metadata expose managed values only; authored YAML has no field
  editor. YAML remains at the authored beginning above the title: Review shows
  source text and Edit keeps the exact, source-located YAML directly editable
  with quiet presentation marks. Source retains exact source. No title
  positioning pass, disclosure control, or automatic collapse remains. Ordinary
  New Note creates no YAML scaffold.
- Document readiness covers live WebKit until the requested mode and its
  source-located presentation are converged; retained-editor reconstruction
  owns scroll and selection without an opening-position special case.
- Settings now uses six native preference panes with scope expressed by named
  groups and adjacent state text rather than page-wide notices, static search
  routing, and Interaction/Integrations child selectors. Selection Actions use
  a compact native table, explicit Edit… sheets, and the real selection-toolbar
  preview. Ordinary groups use headings and whitespace instead of repeated
  rules. The Agents & Chat pane keeps connection state and primary connection
  actions visible while custom connection paths, Skills and Tools, and
  External Agent Hosts use explicit native child sheets. App chrome does not add an accent or
  appearance picker and follows system-resolved colors; pane changes
  interpolate from the current top-left corner while native content remains
  flexible during resizing. Appearance now owns the complete reading and
  typography surface in one pane; low-frequency letter spacing, word spacing,
  hyphenation and kerning/ligatures use the separately managed Advanced CSS
  surface rather than structured profile fields.
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
- Inspector simplification verification (2026-09-08): 154 owning checks passed,
  followed by 7 toolbar checks including the two-segment control and its overflow
  menu. Isolated QA confirmed About/Links, removal of the Outline menu and statistics
  entry, light/dark appearance, empty/populated Links and About field Tab/Shift-Tab
  traversal. Both panes share content spacing; ordinary controls use native colors.
  Full assistive-technology and contrast/transparency/motion acceptance remains open.
- Inspector presents About, Links and Related Material through a native rounded
  icon-only toolbar group. About exposes current About, file, Settlement,
  and applicable Zotero facts and operations. Metadata uses aligned native
  borderless text fields, native selection controls and explicit revision-bound recovery.
  One NSGridView aligns system-sized labels and values with an adaptive label column; creator rows retain
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
  scope, Clear Filters, and the quick-only Advanced Search entry.
  The advanced window retains query/results when opening a Note, keeps Saved
  Searches in a compact action line, and exposes concise query conditions in a
  transient information popover. Native Search-field composition owns input;
  there is no second query draft or centered overlay.
  Results now use the native inset List's selection, with interface typography,
  document symbols, a bounded snippet, and compact location/reason text.
  Native content-state views distinguish the initial query prompt, empty results,
  and actual provider failure; unqueried default availability is not displayed.
- Search presents Note results; questions in Works use the same result and opening path.

- System-Trash confirmation describes the exact selected source scope. Recovery stays with the existing bounded transaction owner.
- One separately spaced native Settlement toolbar button sits immediately before
  Document Mode. It presents **Settle** or **Settle Again**, keeps Unsettled
  monochrome, uses a filled Confirmed bookmark for Settled, and a distinct
  Attention bookmark for Changed Since Settle. It keeps ordinary native material
  and updates immediately without a custom animation timer. Its accessible label
  distinguishes the retained state as well as the next action. An external source
  change does not clear or rewrite Settlement;
  only the researcher's explicit settlement action records a new revision.

- Related Material (2026-09-08) captures explicit unsaved editor selections and
  returns ranked exact paragraphs through the existing local index and source loader.
  Cards retain separate paragraphs from one Note, show readable excerpts and open
  checked source locations or stage provider-neutral Chat context without sending.
  Focused Core, Contracts, Application and App checks cover paragraph boundaries,
  Unicode/CRLF, ranking, cancellation, freshness, missing sources and context staging.
  Isolated light/dark QA verified three relevant paragraphs, cross-vault navigation,
  compact material previews, unchanged drafts and stale-source refusal/refresh.
  Formal persistent paragraph citations and additional Agent runtime adapters are
  not implemented; supported-minimum-width and human adaptation acceptance remain open.

## Agents & Chat and Agent Changes

- Settings includes **Agents & Chat**, with copyable Codex and Claude Code
  MCP registration commands, live App/bridge/CLI availability, and a Finder
  route to the bundled Core Protocol Skill.
- Optional in-app Codex Chat appears beside Library in the left sidebar.
  Agents & Chat now exposes runtime Skill discovery, inspection and
  effective enable/disable, plus MCP tool names and reported connection state.
  Its Skills and Tools sheet presents the bundled Core Protocol in a separate
  always-included, protected card with a read-only Finder reveal route; optional
  Skills remain independently selectable. The default sheet presents names,
  purposes and live status; concrete paths, endpoints and source locations stay
  behind explicit Finder or configuration actions.
  Shared-setting writes have confirmation; active executions block changes.
  Composer Skill selection persists in drafts and sent messages, sends explicit
  Skill inputs and blocks unavailable choices. The installed official runtime
  passed isolated local Skill discovery/disable/enable without inference.
  Local folder association/removal is reachable through the native folder picker;
  configuration-scoped launch preferences survive reconnect. Missing folders and
  unconfirmed application have Refresh/removal repair routes. Official-runtime
  checks confirm discovery and withdrawal without changing Skill bytes. Connected
  Tools now offers native remote/local Add, Edit, enable/disable and Remove forms.
  Version-checked saves preserve other configuration fields; stale forms have
  explicit Reload. Advanced access fields name environment variables without
  displaying values. Other-layer connections remain inspectable and noneditable.
  Invocation-specific presentation remains open. Tools requiring
  authentication now have Sign In and pending Continue Sign-In routes, with
  runtime-confirmed results and configuration-bound shared-scope confirmation.
  Fixture checks cover failure/retry, active-conversation availability, callback
  scope, unsafe URL exclusion and disconnect; actual provider login remains unaccepted.
  Light/dark offscreen Settings images were inspected; live folder-picker and
  confirmation interaction acceptance remains open.
  Add Material now offers a searchable native Note picker. Whole-Note source is
  captured through the document/editor owner and attached to the original
  conversation without sending. Chips and previews distinguish whole Notes from
  passages, saved source from editor snapshots, and known vault roles. Current
  history uses schema 7; unsupported archives remain preserved and nonauthorizing.
  Saved-source capture and fixture sending preserve BOM, line endings and text;
  a dirty unavailable editor rejects capture without substituting saved content.
  Populated and empty picker renders were inspected in light/dark mode. Actual
  editor-snapshot, picker keyboard/focus and VoiceOver acceptance remain open.
  Local PDF, UTF-8 text and supported single-image files have picker, file-URL
  paste and drop routes into retained snapshots. PDF input is extracted text by
  page, with empty pages disclosed; images require reported model support.
  Failed preparation preserves a visible material, and invalid retained files
  preserve the draft before delivery. Details offer replacement, source location,
  page coverage, system Quick Look and image thumbnails. Text/failed PDF detail
  renders have light/dark evidence. Real file-panel, paste/drop, thumbnail/Quick
  Look and provider image-input acceptance remain open.
  The native message editor accepts explicit clipboard image paste and copy-drops
  of image data without changing draft text, selection or text Undo. File references
  outrank icon images; marked text and ordinary text transfer retain their native
  editor route. Drag entry checks types without reading bytes; acceptance captures
  the snapshot. Clipboard and drop origins remain distinct in preview, persistence
  and provider input. TIFF conversion preserves captured bytes alongside the PNG.
  Named-pasteboard, native drag-callback, actual text Undo and fixture-delivery
  checks pass; light/dark detail renders were inspected. Physical cross-app image
  drag, system Paste, installed-IME and complete adaptation acceptance remain open.
  PDF details now offer explicit page-image selection, including scanned PDFs.
  The native form accepts physical ranges, rejects invalid or excessive requests,
  and prepares a replacement without sending. Original PDF and per-page image
  fingerprints remain attached to the material. Native rendering and fixture
  delivery verified selected-page-only input; the form and a generated page were
  inspected offscreen. Actual provider interpretation and live sheet/IME/Quick
  Look acceptance remain open.
  Conversation-owned model/reasoning and web-search menus are wired to official
  runtime configuration. Context and Usage opens reported token/quota values,
  manual compaction and a ledger of staged materials, quoted replies and
  Skills; public plans have native disclosure and retained terminal state.
  These additions have offscreen presentation evidence, not live UI or
  signed-in inference acceptance.
  Browsing and execution are independent: other conversations can run while one
  waits for input. Each owns its approvals, Stop, error and tool token. Rows show
  running, waiting and retained terminal states; the Chat selector reflects any
  pending input. Light/dark offscreen list renders were inspected; no live
  window or accessibility interaction acceptance is claimed.
  The list searches retained titles and public messages, including plans and
  supplied material passages, within its active/archived scope. Detail options
  expose Find in Conversation and Rename. Find navigates matching messages,
  reveals matching activities and preserves input; native fields keep marked
  text intact. These routes have deterministic and offscreen component evidence;
  live scrolling/focus and human accessibility acceptance remain open.
  Native detail/message menus now branch through a selected ended turn and
  open the original conversation. A confirmed branch keeps settings, exact
  retained messages and prior receipt identities; unsent input remains with
  the original. Pending creation has Cancel even for an archived source. The
  deterministic runtime covers truncation, persistence, resumed branch input,
  failure, cancellation, disconnect and selection changes. Branch list images
  were inspected; live menu/focus and signed-in official fork acceptance remain open.
  Edit Earlier Request and the message menu now prepare an opening request in a
  branch before its turn. The first request yields empty history; later requests
  keep earlier exchanges. Original text, materials and Skills enter the ordinary
  draft without sending, and the origin records the excluded boundary. Same-turn
  additional input has no independent edit action. Fixture checks cover exact
  boundaries, preserved source drafts, explicit sending and failed confirmation;
  failed and interrupted turns also expose an explicit Retry in New Branch
  route; live menu/composer focus and official-runtime execution remain
  unaccepted.
  Research questions now use a separate native form with unselected choices,
  option descriptions, permitted custom answers, secure fields and Reply/Skip.
  Answers remain with their owning conversation until runtime confirmation;
  pending submission is read-only. Public records preserve nonsecret responses
  and distinguish pending input from approval; secrets are excluded. Invalid
  forms fail without an allow-operation action. Fixture tests and light/dark
  renders cover these states; provider question execution, native option/field
  keyboard interaction, IME and VoiceOver remain unaccepted.
  Ask-mode Note updates now offer a read-only exact comparison before approval.
  Preview and execution share the Application source transformation; opening
  the preview neither flushes editors nor creates an Agent Change. Its sheet
  reuses the existing comparison surface and answers the exact request. Native
  light/dark images were inspected, including corrected shared comparison
  localization. Real file-operation tests cover untouched preview/decline and
  stale rejection after approval. Live sheet keyboard/focus and provider-driven
  modification acceptance remain open.
  Runtime approvals now present actual command/terminal input, network destination,
  file effects/diffs and complete requested permission rules with optional technical
  detail. Once, turn and session grants are separate explicit actions; submitted
  decisions await exact confirmation. Unsupported persistent policy amendments
  cannot grant access. Tool-origin input identifies its tool and offers Stop Turn;
  secret answers/options and tool arguments stay out of retained history. Focused
  protocol checks and light/dark native renders cover these paths; actual provider
  approval execution and live keyboard/focus/accessibility remain unaccepted.
  Public delegation now displays coordination requests, target identities/states
  and attributed reports through native disclosure. Completed coordination calls
  remain distinct from child completion and retain their visible reports.
  Search, saving, branching and reconnect preserve these observations; they do
  not create child conversations or authorize child tools. Light/dark narrow
  renders were inspected. Reported targets now open a native Agent detail after
  runtime ancestry verification, including descendants reached through multiple
  parents. Public history supports explicit older pages and excludes private
  reasoning; nontext material is separately disclosed. Stop rereads the exact
  active turn, requests interruption and checks for its end without stopping the
  parent or siblings. Disconnected snapshots are labelled prior observations.
  Reports inside the detail open verified destinations within one native
  navigation stack. Back retains the earlier inspection and its separate draft;
  Done closes all inspections without stopping execution. Revisited targets
  return to their existing position, and the original parent opens its local
  conversation. Closed or disconnected inspections cannot open more targets.
  Scope, pagination, cancellation and stale-turn tests cover this slice; direct
  messaging, child approvals and live-provider/native interaction acceptance
  remain open.
  Child detail now provides Ask Parent and Open Parent, with a separate retained
  adjustment draft. Parent receipt, unavailable and unknown delivery have distinct
  native labels. Ordinary parent drafts/materials/Skill selections and visible
  conversations remain independent. Public adjustment targets remain inspectable
  in history and editable branches; a branch cannot send to an original target
  unless it is explicitly removed or the researcher returns to the parent.
  Offscreen light/dark detail and narrow branch images cover this presentation;
  live keyboard/IME, accessibility and provider delivery remain unaccepted.
  Questions, operation approvals, material provenance/content, PDF page selection
  and child adjustment input now use native grouped content cards. Agent detail
  and Context/Account Usage use macOS grouped tabs, with a stable composer and
  persistent state outside the tab content. System surfaces own the material;
  no extra glass or custom selection plate wraps research text. A disposable
  live QA journey verified tab switching, retained Chinese pasted draft/focus,
  parent receipt, question selection/Skip, and light/dark native presentation.
  This is synthetic-runtime Computer Use evidence, not provider or human motion,
  IME, VoiceOver or full visual-adaptation acceptance.
  Background Chat completion, failure and pending input now use the shared macOS
  notification service with generic content, per-conversation coalescing and
  validity checks before delivery. Answered/stopped/superseded requests become
  ineligible; history hydration does not notify. Click routing opens exact retained
  or archived Chat without connecting, sending or changing the current Note.
  Window-model checks preserve unsaved source and unrelated drafts. Narrow
  light/dark destination renders were inspected, including native placeholder
  contrast and localized speaker/model labels. Actual system authorization,
  delivered banners, clicks and cold-launch acceptance remain open.
  Outline and statistics entries are withdrawn; Inspector modes share layout. Chat provides
  history, draft retention, connection/sign-in, permission, native approval
  requests, sending, steering, interruption and stable Note references. While a
  turn is active, the composer distinguishes immediate steering from an ordered
  Next turn queue; queued input stays in a compact card with explicit Send Next
  and removal actions. Idle chats
  can be archived/restored through temporary multi-selection from the list-header
  archive menu. Whole rows open detail or toggle selection; Cancel exits without
  mutation. Detail has no archive action; Library and Chat share one quiet trailing
  header action group with native plain rendering. Sidebar-owned outer/content
  insets align Search, workspace navigation, cards and text; AppKit distributes
  workspace segments equally without manually assigned segment widths. Connection is one click; manual paths and connection
  editing are in Settings. Detail options open conversation-scoped Agent Changes.
  The View menu adds the selected editor passage to Chat without sending it.
  Chat inherits the Sidebar background, with connected native cards grouped by day,
  list-to-detail navigation and a glass composer. Speaker labels and alignment
  distinguish messages; user bubbles use the shared Accent at 30% opacity, while
  both message bodies use the adaptive Chat system type and primary ink.
  Composer secondary icons are borderless and Send uses an Accent circle;
  typography and controls remain native. A native multiline editor now owns the full
  input rectangle and conversation-bound drafts. The 2026-09-08 input correction
  passed 106 owning Chat/presentation checks, including native whitespace geometry,
  wrapping, Return/Shift-Return and marked-text dispatch. Isolated QA verified blank
  clicks, character-level caret placement, Undo, conversation draft retention,
  disconnected Return preservation and one successful multiline send through the
  simulated runtime. Installed-IME and real inference acceptance remain open.
  Current activity lives on the Agent side of the transcript. Runtime-labelled
  public commentary and individual tool calls share a per-turn process disclosure,
  which collapses after completion while final answers remain visible. Unknown
  phases are not hidden as presumed reasoning. Reply files use compact unfilled
  cards; a clear floating file count opens operation history with exact comparisons.
  The composer floats over scrolling content, with native bottom clearance and a
  neutral latest-arrow action. /, @ and $ open bounded native candidate lists;
  the editor preserves marked text, exact query replacement and native Undo.
  Final replies provide Copy and Sources. Sources retains explicit Note, web and
  other locators independently of file-operation records; opening uses existing
  Note or external-URL owners. Same-turn scoped Note reads now expose revision,
  actual line coverage and bounded exact excerpts; completed runtime web open/find
  reports expose access only. Sources now contain only explicit reply locators;
  supplied materials have their own Materials action and popover using existing
  previews. Missing observations remain unknown. Foundation Markdown retains paragraphs, quotes,
  lists, code and comparison rows. The bounded live research loop now passes;
  Verification records the remaining accessibility and integration limits.

- **Agent Changes** has a menu entry listing the most recent receipt per Note;
  exact receipt links open only that change. Older evidence remains retained. Closing a notification does not
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
