# Specification: Accessibility and Adaptation

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Section 20.

## 20. Accessibility and adaptation

### Visual adaptation

- Support System, Light, and Dark appearance; inactive windows; Accent changes;
  Increase Contrast; Reduce Transparency; Reduce Motion; 200% document text;
  enlarged interface text; and English, Simplified Chinese, and mixed content.
- Ordinary small text meets at least **4.5:1** contrast; large or bold text
  meets at least **3:1**. Custom macOS controls target 28 × 28pt and never fall
  below 20 × 20pt; an important target below 28 × 28pt requires explicit audit
  of spacing, precision, and alternative routes.
- Important state uses at least two suitable channels. Color, motion, sound,
  location, hover, drag, secondary click, gesture, and arrow direction are
  never the sole meaning or route.
- Increase Contrast strengthens semantic surfaces and boundaries and may remove
  soft elevation. Structural depth cues are decorative, noninteractive,
  accessibility-hidden, logical-edge-based, and removable without losing
  hierarchy.
- Native macOS controls retain complete labels, state, focus, and target geometry
  when system appearance, window activity, Increase Contrast, or Reduce
  Transparency changes. Material is never the sole boundary around research
  content or the sole indication of state.
- The native Sidebar material retains the supported system's complete
  Light/Dark, active/inactive, Increase Contrast, and Reduce Transparency
  adaptation. Its warm Paper underlay is decorative context, not the sole source
  of separation, selection, focus, or meaning.
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

### Workspace and navigation

§18.2 owns shell composition, command placement and retained state; §18.3 owns
Library/Search/Notifications interaction. Their accessibility obligations are:

- The no-document presentation is one read-only VoiceOver group, without a
  duplicate creation action. Expanded peripherals remain readable or collapse.
- Workspace and Library/Chat selectors expose complete localized names,
  selection, availability and collapse even when labels become symbols. The
  source list follows effective system row size and enlarged interface text.
- Library exposes hierarchy, item type, title, disclosure, drop target and state
  without duplicate decorative symbols. Truncated identities remain available.
  Note/Folder creation, Move, root placement and Trash have non-drag actions.
  Native selection/focus feedback has no second emphasis or perimeter renderer.
- Back/Forward, Search, Notifications, filters, Add, file actions and Inspector
  remain discoverable without hover. The bell's nonzero state has a distinct
  shape and an exact accessible count in Help, without an unread implication.
- Notifications expose category, issue, Note/locator, revision freshness and
  valid actions in reading order. Background delivery follows system settings;
  denial or timeout cannot hide a necessary local error or recovery action.
- File and Window menus retain named Triptych/window routes. The window subtitle
  disambiguates multiple Triptychs only when needed; complete identity remains
  accessible without a repeated Sidebar heading.

### Document and input services

§18.4 owns editor modes, title, Find, completion, previews, attachments and
Metadata interaction; §18.6 owns state/action wording. Verify:

- Managed creation announces once and places insertion at the exact body start.
  Durable-source/editor failure exposes Retry Edit and Source rather than
  inviting duplicate creation. Edit entry announces its valid restored or mapped
  selection without unexpectedly taking title focus.
- Mode, window, external-change, conflict and recovery transitions preserve
  source, dirty input, composition, selection, Undo and reading context. Native
  focus returns to the initiator or next valid target.
- The app-owned filename title is the first Review/Edit accessible heading.
  Its Edit field is named **Note title**, exposes rename rejection and keeps
  IME/text behavior. Authored headings retain semantic levels; Source exposes
  only exact authored hierarchy. Visible title/heading padding and blank lines
  remain pointer-addressable under §18.4.
- Review selection, Edit formatting, statistics and system spelling/grammar
  routes remain accessible. Statistics identify body versus nonempty selection.
- Suggestions expose one listbox selection while retaining editor focus and
  yield immediately to marked text. Find exposes query, options, count,
  navigation, replacement availability and close in keyboard order, then restores
  exact selection. Neither consumes input-method candidate commands.
- Tables, mathematics, Mermaid, footnotes, Callouts, links, embeds and previews
  expose their semantic content, source/fallback, navigation and bounded scroll.
  Unicode cursor/selection remains coherent within the declared support scope;
  technical direction isolation never changes surrounding prose or source.
- Footnote and annotation previews have equivalent pointer/focus disclosure,
  explicit activation, dismissal and return context. Inactive annotated links
  expose a named expanded/collapsed superscript control; exact source remains
  editable without reliance on hover or color.
- Attachments expose complete filename, availability, count, selected position,
  native Quick Look and the copy/reference consequence. Single-file presentation
  omits selection. Preparation errors stay accessible at the owning Note;
  opening/closing preserves mode and source selection. No preview requires hover.
- Autosave failure, conflict and recovery expose the retained-buffer consequence
  and valid repair; proven save remains silent. Agent Undo names each outcome
  without moving Document focus.

### Inspector, Settings and integrations

§18.5 owns Inspector composition and passage navigation, Appendix A owns field
configuration, and §§8 and 15 own integrations. Verify:

- Outline/About/Links is one named single-choice native group with selection,
  Help and keyboard traversal. Outline exposes hierarchy, current section and
  disclosure, followed by statistics. No Document and No Headings are distinct.
- About exposes complete labels/values, contributor identity/order and the
  source-authority distinction. Configured empty fields remain discoverable;
  enlarged text and narrow width preserve values. Native field traversal,
  commit, cancellation, validation and revision-conflict repair remain associated
  with the field. Hover-revealed actions stay in keyboard order without reflow.
- Links direction, query and grouped occurrences are independently named.
  Group headings expose count/disclosure; passage activation is not a checked
  value or persistent selection. Source context and annotation remain available.
  Incoming **Edit at Source** and destination navigation have distinct names.
  Arrival does not replace text selection or rely on its highlight. Reduce Motion
  reveals the same target with a static brief marker and no animated scroll/fade.
- Settlement exposes state and state-valid action through wording, symbol, Help,
  accessible value and its menu route. It remains a milestone, with no inferred
  task-completion state. Inspector visibility changes no research judgment.
- Settings exposes search, selected category, scope and content in predictable
  order. Empty search retains the query. Appearance reload and Metadata settings
  preserve invalid/conflicting drafts and name the exact field and safe repair.
  Definitions expose immutable key/kind, order, scope, lifecycle and use count;
  Archive/Restore describes its effect on stored values. Frontmatter's named
  route and direct source editing retain composition and source authority.
- Hotkeys expose command, menu location, binding, recording state, validation,
  Save, Clear and Restore. An invalid draft never alters active commands.
- Zotero linking/refresh names exact item/library, proposed fills/updates,
  retained conflicts, progress, partial commit, cancellation and retry. The
  read-only Zotero and non-YAML/Markdown boundaries are visible before commit.
- Agent Integration exposes App/bridge/CLI state, distinct setup-copy actions
  and the Finder route. Commands/paths are selectable; copy success does not
  claim host configuration. MCP failures retain distinct unavailable, scope,
  stale/conflict and uncertain-outcome explanations.
- Chat exposes list/detail, Back, New Conversation, archive/restore, permission,
  approval, Send, Stop and file/comparison routes. Labels and alignment distinguish
  speakers without relying on bubbles. Streaming steals neither focus nor scroll;
  drafts and uncertain delivery remain inspectable. Activity names action,
  target and status; file summaries distinguish reads, no-ops, recorded edits
  and runtime reports. Closing a comparison returns to its origin. Native
  transparency/contrast and Reduce Motion preserve readable status.

### Agent Changes

§8.4 owns evidence and Undo; §18.5 owns comparison presentation. Each comparison
exposes Note, operation, exact revisions/position, `change_id` and applicable
Earlier Revision, Created by External Agent or system-Trash state. Before/After
and inserted/removed/changed structure remain perceivable without color.
Previous/Next and progressive path/fingerprint detail have keyboard, pointer,
focus and accessibility equivalents. Closing implies no review or Settlement.
Undo states its current-fingerprint prerequisite and outcome. Source deletion
and Agent Change recovery retain different consequences and return context.

### Evidence and representative human acceptance

Deterministic conformance covers every declared core workflow at the boundaries
it exposes: semantic names, roles, values, and state; menu and keyboard
reachability for app commands; predictable focus for interaction; cancellation
for interruptible work; recovery for recoverable failure or consequential
mutation; localization; reflow; non-color meaning; and retained source and
conflict behavior. A workflow adds no inapplicable route merely to complete
this list. Accessibility-tree inspection, unit/integration tests, and UI
automation remain automated evidence even when they drive a real system service
or capture speech.

A Beta with no retained passing deterministic UI baseline for its named profile
runs the complete current UI matrix on an isolated QA build from the exact
release source. Each later Beta reruns repository static/unit/integration guards
and the UI journeys affected by a changed workflow or state, accessibility
contract, presentation owner, fixture, or build environment. A new supported
macOS baseline and 1.0 each trigger the complete matrix. A failing current guard
or affected journey invalidates carry-forward. Exact-artifact UI journeys remain
governed by §21.5.

Human acceptance is selected by independent failure mode, not by multiplying
every workflow, state, width, appearance, adaptation and input method. Reuse one
representative journey across navigation, document, transient, and embedded-
editor surfaces; add another only for a distinct custom interaction, input-
service, perceptual, or high-consequence recovery boundary.

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
