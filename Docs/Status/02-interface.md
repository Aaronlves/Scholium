# Implementation Status: Reachable Interface

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Current user-facing reachability.

Selection Actions now use the existing native floating surface in Review, Edit
and Source. Ask Agent and the Research-menu shortcut stage a checked passage in the
existing Chat composer, preserve its draft, and never send automatically.
Review currently maps source-identical blocks; formatted/synthesized blocks
require Edit or Source. Material source opening verifies the excerpt and revision,
then restores its exact Review selection where renderable, otherwise its Source
range for editable Notes. Unrepresentable read-only ranges retain their preview
and a visible limitation. Ordinary line references retain line arrival. Native
composer first-responder transitions now drive the focus binding; revealing
already-visible Chat does not toggle the Sidebar closed.

## App root and workspace shell

- Buttons and menus use native styles directly across roots, split regions,
  sheets and popovers. Shared neutral-tint wrappers and neutral button tints in
  Search and Connections have been removed. Icon controls retain native chrome;
  explicit semantic action colors remain local to their actions.
- Starting, Registry Recovery, Ready, and Storage Unavailable are distinct app
  roots. Failure states retain Details, Retry, and the applicable recovery or
  Quit route while workspace commands remain disabled.
- Bootstrap now offers create/connect directly on Welcome. Each route uses one
  scrollable form with directory preview or all three folder selections and inline
  parent authorization; registration opens the workspace without review/Ready pages.
  Input survives cancellation and failure, and a prepared new root is reused on
  registration retry. System appearance replaces the illustration sidebar; the hand
  artwork remains only on Welcome. Configured windows use one native
  Library–Document–Inspector split and one stable toolbar.
- View offers a window-local Focus Layout with a configurable Control–Command–L
  shortcut. It hides the native toolbar and both peripheral panes, then restores
  their prior visibility and widths; explicit pane-opening commands exit it.
  Existing document hosts, modes, text appearance, and source remain unchanged.
  Native full screen now requires focus, locks the checked menu toggle, and
  restores the preceding windowed focus state on exit. The independent windowed
  toggle remains available. Shift–Command–F and View → Advanced Search always open
  the existing advanced window; quick search remains in Sidebar's field.
- Native Sidebar and Inspector controls mirror actual split visibility. AppKit
  owns window, toolbar, divider, collapse, resize, fullscreen, and focus
  behavior. Each workspace window retains its own Library, document tabs,
  Document mode, Inspector mode, Search, and Attention presentation.
- AppKit's Sidebar split item now owns the complete regular Liquid Glass
  navigation plane. The adjacent Document Paper surface extends beneath it
  through the native safe-area contract; Sidebar content adds no custom fill,
  visual-effect host, or edge shadow. The Document scroll plane stays in the native
  safe area; only its background reaches the transparent titlebar, while standard
  AppKit toolbar items retain their native Liquid Glass.
  In ordinary windows, Document and Apparatus remain continuous through the
  transparent titlebar with no separate toolbar band. Full screen uses Focus
  Layout rather than exposing the system toolbar backing.
  Compact Sidebar-header controls retain their
  established 28pt targets. The native Inspector projection control and split
  geometry remain unchanged.
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

- Native Library multiselection has group Move/Trash menus, keyboard/accessibility
  routes and same-vault dragging. Selection is separate from the active Document;
  a native folder picker and retained per-item results provide retry and Recovery.
  Mixed Folder/Note selections do not expose Note batch mutations. File, Folder,
  batch and Trash sheets share native content-fitting forms, bounded file lists
  and trailing actions; the Library header retains only its menu controls.

- A window-wide native content-tab collection retains documents across Library
  role changes. AppKit renders tabs; guarded selection and close retain source
  safety. File exposes Close Tab and View exposes tab navigation and overflow.
- Main-window Review/Edit is followed by a native Note Actions **More** menu;
  separate windows extend their existing single More. Shared note actions use
  the owning window's document and retain its specific transfer/close routes.
  Passage menus connect to exact-range actions and a source-comparison preview
  for extraction, move and copy; merge is note-level. Current native mapping,
  clipboard and integration limitations are recorded in Open Work.
- Library presents Analyses, Topics, and Works through native single-choice
  segments. Complete localized labels adapt to role symbols at narrow widths;
  selection and disabled-workspace semantics remain native. The file tree keeps
  source-list selection, keyboard focus, disclosure, and normal native row size.
  AppKit owns row emphasis without a pointer/keyboard override; hosted text follows
  the native cell background. Note-only trailing row actions reuse guarded Trash
  preparation. Exploratory QA observed accent selection and gray selection after
  entering the editor; physical swipe feedback and confirmation/cancellation remain
  unverified after the Computer Use connection failed. No test suite was run.
  Organize and Add remain separate native menus. File-tree rows use the Finder-style native grid: AppKit owns
  the Folder disclosure gutter and its state, monochrome Folder and Note symbols
  share the item-type column, and their titles share the following text column.
  The 16pt Library hierarchy step is applied through AppKit's native outline
  indentation property rather than custom row positioning.
  The projection omits the application-owned root `Attachments` directory and
  descendants without altering their stored files.
- Library distinguishes a filtered empty result from a genuinely empty tree,
  retaining its existing Clear route. Organize separates link-annotation presence
  from Integrity, groups source properties, and exposes sorting choices
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
- Editor and reader link, footnote and annotation previews use native popovers
  with inert local WebKit content measured before display. Slash commands and
  other candidates retain CodeMirror's keyboard and AX listbox with native rows,
  retained filtering width and opening edge. Editor-owned choices use AppKit's
  quieter secondary selection. Pending queries
  retain the container while stale source/selection callbacks are refused.
  Selection Actions use native accessory buttons with hover borders. A native
  parent separates floating geometry from the document; source and history stay put.
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
  an app-owned folder route, automatic discovery/watch, guide and explicit
  reload. Public `.callout` selectors project to both Review and Edit while
  internal projection classes remain protected. Invalid or stale external
  edits cannot replace the loaded appearance or be overwritten by a stale GUI
  save; document CSS and text colors remain content-layer values.
- User properties remain in source-located YAML. Review/Edit project the
  filename title, YAML and body in the shared document plane; Source keeps exact
  text. No field editor or separate Metadata panel remains.
- Document readiness covers live WebKit until the requested mode and its
  source-located presentation are converged; retained-editor reconstruction
  owns scroll and selection without an opening-position special case.
- Settings uses five sidebar categories, static bilingual search, and native
  Interaction/Integrations child selectors. The compact toolbar keeps the pane
  title; category changes retain window dimensions. Previously opened pages
  retain their draft state in attached native hosts; inactive hosts are hidden,
  excluded from accessibility, and unregister their default actions. Only the
  selected host follows window resizing. Appearance font pickers share an
  asynchronously refreshed catalogue. Preferences use native grouped
  forms, including shortcut rows; Selection Actions retains its native table
  with adjacent actions and an accessible fixed footer. Notifications drafts bind
  their original Triptych and revision, with explicit reload after a mismatch.
  Agents & Chat keeps connection state and primary actions visible; custom
  connection paths, Skills and Tools, and External Agent Hosts use native child
  sheets. Appearance holds reading, source fonts, typography and heading levels;
  low-frequency letter/word spacing, hyphenation, kerning/ligatures and bounded
  Callout overrides remain in Advanced CSS. Auxiliary chrome follows system
  appearance and Accent.
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
- Inspector now contains Links and Related Material using the existing native
  toolbar selector. Links separates Incoming, Outgoing and External; external destinations derive from source. Attachment
  links remain in the Document and use bounded native Quick Look. The old About
  field editor, attachment preview panel and Zotero binding controls are removed.
  Scoped disposable-fixture QA verified the three native tabs, selected-only labels,
  direct passage/annotation navigation in Edit and Review, YAML property search,
  attachment Quick Look, insertion/Undo and five Settings panes. Complete adaptation
  and release acceptance remain open.
  Outgoing and Incoming
  group exact occurrences by peer Note. Stronger document headings contain native
  passage cards; annotations use a divider, inset comment symbol and secondary text.
  Source line numbers are not displayed.
  The whole Note heading toggles disclosure; its contextual action opens the
  peer. Passage targets use ordinary native buttons with hover feedback; their
  selected-occurrence state, toggles and selected accessibility traits are removed.
  Review reveals the source locator and briefly highlights its visual line without
  replacing the reading selection; Edit/Source add a transient line decoration
  to the existing explicit navigation. The marker expires, repeats on activation,
  and clears on replacement/teardown without source writes or history entries.
  It fades in, holds and fades out; Reduce Motion keeps it static. Outgoing destination navigation remains
  separately available. Source-owned Markdown annotations remain visible. Links contains no annotation editor; clicking a passage or annotation locates its source. Ordinary links retain the
  current Document mode and locate the rendered block or editor line after
  presentation readiness. It has no Actions mode.
- Search uses a persistent native field. Its magnifying-glass menu contains
  This Vault / Triptych scope, Clear Filters, and the quick-only Advanced Search
  entry. The duplicate adjacent close button and This Note scope menu item are
  removed; the native clear button restores the retained Library.
  The advanced window retains query/results when opening a Note, keeps Saved
  Searches in a compact action line, and exposes concise query conditions in a
  transient information popover. Native Search-field composition owns input;
  there is no second query draft or centered overlay. Insert Term Group opens the
  local collection or its native management sheet. Matching Paragraphs opens a
  native popover with independently accessible location buttons and bounded
  expansion; both result rows and the advanced toolbar provide an entry.
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
  Insert Paragraph Link checks a complete current paragraph, saves a new anchor
  when needed and inserts its live reference at the retained writing cursor.
  Partial/stale results and dirty sources refuse; a saved anchor followed by failed
  insertion is reported separately. Supported-minimum-width and human adaptation
  acceptance remain open.

## Agents & Chat and Agent Changes

- Settings includes **Agents & Chat**, with copyable Codex and Claude Code
  MCP registration commands, live App/bridge/helper availability, and a Finder
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
  Triptych-local Skills use the automatic `.scholium/skills` directory. Settings
  identifies This Triptych and opens its Chat workspace in Finder; directory
  association controls are removed. Failed discovery exposes Refresh repair. Connected
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
  history uses schema 12; unsupported archives remain preserved and nonauthorizing.
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
  runtime configuration. Separate Context and Account Usage surfaces open reported token/quota values,
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
  supplied material passages, within its current or archived scope.
  Native list rows expose archive/delete/restore and read/important actions,
  with persisted markers and Unread/Important filters. Only archived idle
  conversations can be permanently deleted, with native confirmation. Detail options
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
  parent or siblings. Snapshots are labelled prior observations, with their
  observation time in Details. Reading state, loading history and checking
  interruption have distinct text. Replacing a snapshot resets its paging cursors.
  Reports inside the detail open verified destinations within one native
  navigation stack. Back retains the earlier inspection;
  Done closes all inspections without stopping execution. Revisited targets
  return to their existing position, and the original parent opens its local
  conversation. Closed or disconnected inspections cannot open more targets.
  Scope, pagination, cancellation and stale-turn tests cover this slice; direct
  messaging, child approvals and live-provider/native interaction acceptance
  remain open.
  A compact Agent-count button beside Changes deduplicates retained child work,
  including ended Agents. Its popover reads ancestry-verified metadata, grouping
  observed active, idle and unavailable work with timestamps and explicit refresh
  failure; historical states remain distinct. Each row opens the existing detail.
  A flat stable-identity list retains current row content when metadata moves groups.
  Changes retains its original history entry after the pending count reaches zero.
  Delegation and transcript plans use compact disclosures; the active plan step
  stays in its transcript summary. Header options own Outline, Find, Rename,
  Account Usage and Diagnostics. Context is a small indicator beside the composer
  model; unavailable/last-reported occupancy has named Help and accessible text.
  The header provides Context while requests or archives hide the composer.
  Its content-sized popover leads with occupancy and has one bounded Details
  disclosure containing cumulative use and the prepared-context list, without
  the GroupBox that triggered the automation service crash. Account Usage has
  an independent native sheet. Composer materials and quotations share the input
  surface. Compact actions share target geometry and pointer feedback; floating
  Changes/Agents use native glass buttons. Native settings and recovery actions
  no longer mix ordinary controls with per-button cursor overrides.
  Composer catalogs separate commands, Note/material references and Skills under
  `/`, `@` and `$`. The Add menu has four ordinary named entries; gray native
  placeholder text and accessible Help explain the prefixes. All candidates stay
  reachable in a bounded list outside the input's clipping boundary. Selection
  follows candidate identity through refresh, and command handoff is one native
  Undo step without replacing surrounding draft prose.
  Model/reasoning opens Chat Settings with permission and web-search choices,
  while Full Access remains visibly identified when enabled. Message actions
  are direct icons revealed by whole-message native pointer observation or
  descendant focus; assistive technology retains visible controls and AX routes.
  Header turn pickers and duplicate Changes/plan entries are removed. Multiple
  queued messages start collapsed to a count and retain expansion during editing.
  Stop stays at the trailing edge during work. A normal Send button owns delivery
  and Command-Return; its adjacent menu offers this message's immediate/queued
  action without altering the configured Return default.
  Child detail centers on public requests, progress and output, with Refresh and
  Stop above the reading area and technical facts in one Details disclosure.
  Open Parent and Done provide navigation; there are no message controls or tabs.
  Stored child draft text is inert, with no pending-draft marker. Ordinary Chat
  input, queue delivery and retained target references keep their existing owners.
  Questions, approvals, materials and PDF page selection retain native grouped
  content; Context and Account Usage remain separate. Real-provider, VoiceOver,
  physical IME and full visual-adaptation acceptance remain open.
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
