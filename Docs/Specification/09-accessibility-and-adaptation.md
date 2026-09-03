# Specification: Accessibility and Adaptation

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Section 20.

## 20. Accessibility and adaptation

### Visual adaptation

- Support System, Light, and Dark appearance; inactive windows; Accent changes;
  Increase Contrast; Reduce Transparency; Reduce Motion; 200% document text;
  enlarged interface text; and English, Simplified Chinese, and mixed content.
- Ordinary small text meets at least **4.5:1** contrast; large or bold text
  meets at least **3:1**. Important custom targets below 28 × 28pt require
  explicit audit.
- Important state uses at least two suitable channels. Color, motion, sound,
  location, hover, drag, secondary click, gesture, and arrow direction are
  never the sole meaning or route.
- Increase Contrast strengthens semantic surfaces and boundaries and may remove
  soft elevation. Structural depth cues are decorative, noninteractive,
  accessibility-hidden, logical-edge-based, and removable without losing
  hierarchy.
- Text and controls grow or reflow instead of clipping. Enlarged prose has no
  page-level horizontal reading scroll; intrinsically wide technical objects
  keep bounded local overflow or scaling.

### Input, focus, and semantics

- Every core task is keyboard- and accessibility-operable with visible,
  predictable focus. App commands use the macOS menu bar; frequent or
  high-value commands may additionally use toolbar or direct pointer controls.
  Field-local and standard native controls need not be duplicated into a menu
  or toolbar.
- Interruptible work exposes cancellation when stopping is safe and meaningful.
  Failure or consequential mutation exposes recovery only when an applicable
  repair, retained state, or reversal exists. Drag and secondary click remain
  redundant.
- Focus is visible and predictable. Native presentations preserve initiating
  modality and return focus to the initiator or next valid semantic target.
  Custom features do not override native focus restoration. Shared custom
  controls alone own their traversal behavior.
- Controls expose accurate name, role, value, selection, availability,
  consequence, error, and recovery. Decorative and duplicate symbols stay out
  of the accessibility tree.
- Meaningful state changes are announced once and remain inspectable. Progress
  animation is supplementary; persistent errors and recovery facts do not time
  out.
- Operation feedback exposes semantic type, complete message, and Dismiss or
  repair in reading order. Field-specific validation remains programmatically
  associated with its field.
- Automation may inspect accessibility structure or drive a real system
  service, but cannot establish human VoiceOver, Voice Control, Dictation, Full
  Keyboard Access, installed input-method, or perceptual acceptance.

### Workspace, Library, and navigation

- The no-document state is one read-only VoiceOver group with no duplicate
  creation action.
- Triptych navigation is one vertical single-choice group with Up/Down
  traversal, selected state, localized Note totals, and unavailable-state
  semantics. Progressive loading preserves available Library routes and focus.
- Back/Forward, Sidebar, Inspector, Notifications, filters, folder disclosure,
  Add, file actions, and hierarchy remain named and reachable without hover.
- Library rows preserve selected, focused, inactive, disclosed, drop-target,
  disabled, loading, stale, empty, and failure distinctions. Note/Folder Move,
  root placement, system-Trash deletion, and contextual creation have non-drag
  accessibility actions.
- Expanded Library and Inspector remain readable or collapse natively; they do
  not remain open in an unusably compressed state.
- Attention exposes group, issue, Note, locator, state, actions, freshness, and
  Retry in a coherent order.
- Agent Change notifications expose exact Note, operation, time,
  current/Earlier Revision state, and valid actions. A multi-change disclosure
  states its count; keyboard/pointer expansion and collapse are equivalent.
  Reduce Motion changes transition, not content or state.
- Settings and workspace feedback remain in window reading order without moving
  existing controls or obscuring their owners.

### Document and editor

- Managed New Note announces once, opens Edit, and places insertion at the exact
  body start. Durable-source/editor-failure names Retry Edit and Source without
  inviting another creation.
- Review, Edit, and Source expose current mode, content state, and one coherent
  focus order. Mode, window, external-change, conflict, and recovery transitions
  preserve dirty buffer, composition, selection, Undo, scroll, and recovery.
- First Edit activation without retained presentation places a collapsed
  insertion point at the end of the inline Note title. Returning to a still-open
  or window-restored Note restores its last title/body focus and fingerprint-
  valid editor selection. Explicit source navigation and Managed New Note's
  body-start insertion take precedence. Closing the tab ends that retained
  focus history.
- Review selection and Edit formatting remain exact and keyboard reachable.
- Suggestion lists retain document focus and one listbox selection. They do not
  open during marked-text composition.
- Document Find exposes query, options, count, navigation, replacement
  availability, and close in one keyboard order; closing restores the exact
  editor selection.
- Statistics identify body versus selection scope. Spelling/grammar preserve
  system routes. Image Import/Index name the copy-versus-reference consequence
  and preserve source/focus on failure.
- English, Chinese, mixed content, and other Unicode source retain consistent
  visible cursor/selection within the declared support boundary. Technical
  regions are directionally isolated without changing surrounding prose.
- Tables, footnotes, mathematics, Callouts, links, Mermaid, previews, and embeds
  expose semantic names, source/fallback, navigation, and bounded scrolling.
  Exact source remains the fallback for generated Mermaid.
- Autosave Failed and Conflict state the retained-buffer consequence and
  applicable recovery. Proven Saved state is silent. Agent Undo reports each
  outcome without moving Document focus.
- The app-owned filename title is the first accessible heading in the
  Review/Edit document plane. In Edit its inline text field is named **Note
  title**, supports ordinary text selection and IME input, commits through
  Return or focus departure, cancels through Escape, announces a rejected
  rename, and never masquerades as Markdown editing. Its surrounding visible
  spacing has the same pointer route as the field. Authored H1–H6 expose
  section-heading levels beneath it without changing source markers; their
  padding and authored blank lines remain pointer-addressable. Source exposes
  the exact authored hierarchy without adding the projected title.

### Metadata and portable settings

- Settings exposes search, navigation group, selected destination, scope, and
  detail in predictable order. Empty search retains the query and names the
  absence.
- Hotkeys expose command, menu location, binding, recording state, validation,
  Save, Clear, and Restore. Invalid drafts never change menus.
- Metadata settings expose role, field definitions, applicability, About
  always-shown order, dirty/save/conflict state, and exact recovery consequence.
  Invalid or conflicting drafts remain local and named.
- Field definitions expose immutable key/kind; editable label/description,
  field/choice order, and choice addition; lifecycle, scope, and use count.
  Archive/Restore retain stored values and change no Note automatically.
- Metadata/About use visible and accessible semantic group headings and retain
  field labels, contributor structure, source-authority distinction, and
  complete values at narrow width and enlarged text. Empty always-shown fields
  expose their editable purpose rather than disappearing. Inline Save, Cancel,
  validation, and conflict state remain programmatically associated with the
  field; read-only file and Settlement facts expose their source and state.
  Hover-revealed actions remain in keyboard/accessibility order without reflow.
- Zotero link/refresh exposes exact item and library identity, current values,
  proposed fills/updates, retained conflicts, progress, partial commit,
  cancellation, and retry. Abstract/tags/YAML/Markdown/non-write boundaries are
  visible before commit.

### Search, Inspector, and Agent integration

- Research Search and Document Find have distinct names, shortcuts, focus,
  scope, and results.
- Search exposes provider, scope, query, completion/result selection, count,
  match reason, freshness, destination, and Explain Query. Invalid, ambiguous,
  provider mismatch, unavailable, partial, stale, and empty remain distinct.
- Inspector Overview/Connect and Incoming/Outgoing are labelled single-choice
  groups with visible selection and keyboard traversal. No-document Inspector
  remains a nonempty read-only state.
- Connect states the authored occurrence direction textually. Each row names
  source or destination, local context, and whether a link annotation is
  present. Incoming annotations are identified as read-only at the destination;
  destination navigation and **Edit at Source** remain separately named.
- An inactive annotated Wikilink exposes one adjacent disclosure with its linked
  title and expanded/collapsed state. Keyboard and pointer activation reveal
  the same Markdown annotation, focus remains predictable, and source editing
  exposes the exact delimiters without relying on color or icon alone.
- Document Rail exposes the state-valid Settle, Settle Again, or Mark Unsettled
  researcher action without a parallel review milestone or Agent launcher.
  Opening Inspector does not alter reading or focus order.
- Agent Integration in Settings exposes App/bridge/CLI state, the two distinct
  setup-copy actions, and the Core Protocol Finder route in one predictable
  order. Command and path text is selectable; copied-command success is not
  represented as host configuration success.
- MCP operations neither activate the App nor move focus. `app_unavailable`,
  workspace selection, stale revision, conflict, and uncertain outcome have
  distinct names and recovery.

### Research Records

- The Records window exposes its Triptych, collection/result count, selected
  Record, current question, chronological step count and position, step time,
  Agent attribution, revision relation, and current/earlier/unavailable Note
  references in one predictable reading order.
- Collection and reading plane remain independently named regions. Every
  step-local Note attachment is keyboard reachable in the same reading order
  as the step that declares it. At narrow width or enlarged text, its
  single-line strip scrolls horizontally instead of wrapping, compressing prose,
  or moving provenance elsewhere; focus traversal also reveals an off-screen
  attachment.
- Rendered Record paragraphs, emphasis, lists, block quotations, inline code,
  and links retain semantic accessibility. Unsupported syntax remains
  selectable literal text. The current question is the sole page heading;
  step prose cannot create an authored heading hierarchy.
- Search-opened Records expose the matched step without discarding the complete
  question/step context. Empty, loading, stale, invalid-file, and unavailable
  states name scope, consequence, and applicable Retry without synthesizing
  content or hiding valid neighbor Records.
- Agent Changes names Note, operation, exact change position and revisions,
  `change_id`, and Earlier Revision, Created by External Agent, or system-Trash
  state as applicable. Before/After and inserted, removed, or changed structure
  remain perceivable without color. Previous and Next have keyboard, pointer,
  focus, and accessibility equivalents. Progressive detail exposes complete
  path and fingerprints.
- Closing Agent Changes records no review state and never changes Settlement.
  Document Rail retains the accessible Settle route. Direct Undo states its
  current-fingerprint prerequisite and exact outcome.
- Source deletion and Agent Change recovery use distinct labels,
  consequences, and focus restoration. Any future Record deletion interaction
  must define the same properties in its own §22 contract.

### Evidence and representative human acceptance

Deterministic conformance covers every declared core workflow at the boundaries
it exposes: semantic names, roles, values, and state; menu and keyboard
reachability for app commands; predictable focus for interaction; cancellation
for interruptible work; recovery for recoverable failure or consequential
mutation; localization; reflow; non-color meaning; and retained source and
conflict behavior. A workflow adds no inapplicable route merely to complete
this list. Accessibility-tree inspection, unit/integration tests, and XCUITest
remain automated evidence even when they drive a real system service or capture
speech.

A Beta with no retained passing deterministic UI baseline for its named profile
runs the complete current UI matrix on an isolated QA build from the exact
release source. Each later Beta reruns repository static/unit/integration guards
and the UI journeys affected by a changed workflow or state, accessibility
contract, framework owner, fixture, or build environment. A new supported macOS
baseline and 1.0 each trigger the complete matrix. A failing current guard or
affected journey invalidates carry-forward. Exact-artifact UI journeys remain
governed by §21.5.

Human acceptance is selected by independent failure mode, not by multiplying
every workflow, state, width, appearance, adaptation and input method. Reuse one
representative journey across several native, AppKit, SwiftUI and WebKit
surfaces; add another only for a distinct custom interaction, input-service,
perceptual, or high-consequence recovery boundary.

Core App acceptance keeps four bounded human checks:

1. one genuine VoiceOver journey through shell, Library/Search, Document mode,
   and one persistent error or recovery surface, judging naming, grouping,
   reading order, announcements and focus continuity;
2. one physical Full Keyboard Access journey through menu/toolbar, Library,
   editor, a sheet, cancellation and recovery;
3. one installed Simplified Chinese input-method journey in Edit and Source,
   including nondefault candidate selection, mixed-script selection, Undo,
   save, reopen and exact-source comparison; and
4. one representative visual-adaptation set spanning populated content and one
   consequential error/recovery state. Across that set, exercise ordinary and
   minimum width, Light and Dark, Increase Contrast, Reduce Transparency,
   Reduce Motion, inactive-window treatment, enlarged interface text and 200%
   document text at least once, without requiring their Cartesian product.

Voice Control and Dictation are targeted human compatibility checks only when a
release explicitly claims those routes or a change touches command naming,
discoverability or text-service integration. Agent Collaboration adds one
representative human journey across Settings setup, current status, retrieval,
one mutation, Agent Changes, and recovery; it does not repeat the matrix for
every tool or error state.

A Beta with no retained accepted baseline for its named profile completes all
applicable bounded human checks on the exact packaged artifact. A later Beta
reruns only a check whose representative journey, named failure-mode owner,
relevant framework boundary, or supported macOS baseline changed, or when a new
independent human failure mode appears. Core App and Agent Collaboration 1.0
repeat all applicable checks on their exact artifacts. A carried check retains
its original artifact/environment evidence and the current release records why
its coverage remains applicable; it is never relabelled as current-artifact
human execution.

### Acceptance threshold

Test long English and Simplified Chinese labels, mixed content, enlarged text,
minimum supported widths, file/error/recovery states, and native/editor focus
transitions at deterministic layers. Beta/1.0 G6 evidence follows the
deterministic and human baseline/change-impact cadence above. Every release runs
current static/unit/integration accessibility and localization guards, any
affected deterministic UI journeys, and has no unresolved critical or
high-severity accessibility defects. Automation never becomes human acceptance;
human acceptance does not require every covered state or adaptation combination.
Additional languages and complete RTL acceptance remain deferred.
