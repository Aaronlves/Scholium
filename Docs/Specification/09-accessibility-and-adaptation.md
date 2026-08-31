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

- Every core task has appropriate keyboard, menu/toolbar, pointer, focus,
  cancellation, recovery, and accessibility routes. Drag and secondary click
  remain redundant.
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
- Synthetic automation cannot establish genuine VoiceOver, Voice Control,
  Dictation, Full Keyboard Access, installed input method, or system text
  service acceptance.

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
- Action activity banners expose exact Run identity, state, target, and valid
  actions. A multi-activity disclosure states its count; keyboard/pointer
  expansion and pin/collapse are equivalent. Reduce Motion changes transition,
  not content or state.
- Settings and workspace feedback remain in window reading order without moving
  existing controls or obscuring their owners.

### Document and editor

- Managed New Note announces once, opens Edit, and places insertion at the exact
  body start. Durable-source/editor-failure names Retry Edit and Source without
  inviting another creation.
- Review, Edit, and Source expose current mode, content state, and one coherent
  focus order. Mode, window, external-change, conflict, and recovery transitions
  preserve dirty buffer, composition, selection, Undo, scroll, and recovery.
- Review Comment and Edit formatting remain attached to the finalized
  selection and keyboard reachable. Comment markers state line range and count;
  stale locators state **Earlier revision** without false navigation.
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
  Generated Mermaid is not a Comment target; exact source remains its fallback.
- Autosave Failed and Conflict state the retained-buffer consequence and
  applicable recovery. Proven Saved state is silent. Agent Undo reports each
  outcome without moving Document focus.

### Metadata and portable settings

- Settings exposes search, navigation group, selected destination, scope, and
  detail in predictable order. Empty search retains the query and names the
  absence.
- Hotkeys expose command, menu location, binding, recording state, validation,
  Save, Clear, and Restore. Invalid drafts never change menus.
- Metadata settings expose role, field definitions, applicability, About order,
  Agent preferences, dirty/save/conflict state, and exact recovery consequence.
  Invalid or conflicting drafts remain local and named.
- Field definitions expose immutable key/kind, editable label/description,
  choices, lifecycle, scope, and use count. Archive/Restore retain stored values
  and change no Note automatically.
- Metadata/About retain accessible semantic groups, field labels, contributor
  structure, source-authority distinction, and complete values at narrow width
  and enlarged text. Hover-revealed actions remain in keyboard/accessibility
  order without reflow.
- Zotero link/refresh exposes exact item and library identity, current values,
  proposed fills/updates, retained conflicts, progress, partial commit,
  cancellation, and retry. Abstract/tags/YAML/Markdown/non-write boundaries are
  visible before commit.

### Search, Inspector, and Research Actions

- Research Search and Document Find have distinct names, shortcuts, focus,
  scope, and results.
- Search exposes provider, scope, query, completion/result selection, count,
  match reason, freshness, destination, and Explain Query. Invalid, ambiguous,
  provider mismatch, unavailable, partial, stale, and empty remain distinct.
- Inspector Overview/Connect and Incoming/Outgoing are labelled single-choice
  groups with visible selection and keyboard traversal. No-document Inspector
  remains a nonempty read-only state.
- Connect states direction textually; undirected rows say they appear in both
  directions. Navigation and source-return routes remain separately named.
- Document Action rail exposes Research Actions and Settle without a parallel
  review milestone. Icon-only buttons have complete names, Help, availability,
  and first executable repair. Opening Inspector does not alter reading or
  focus order.
- Pairing and re-pairing present one linear flow. Codes remain inside copied
  handoff; secrets and opaque identifiers are never separate researcher fields.
  Agent updates neither activate the app nor move focus.
- Follow-up exposes lineage, statement, next Action, request, and optional
  default-collapsed Method Feedback with distinct dirty/saving/stale/error/clear
  states.

### Research Records

- Records remains available with Triptych scope when no Document is selected
  and This Note scope when one is selected.
- Scope/View, collection headers, ordering, exact total, pagination, loading,
  partial state, and Retry are named. Loaded rows survive later-page failure.
- Selecting detail removes the collection from the active tree; Back restores
  it. Evidence visibility changes the tree without disturbing reading order.
- Record detail reads authorship before attributed prose. Links use native
  semantics; unresolved destinations remain exact nonactions.
- Follow Up and Method Feedback precede Evidence. Change comparison exposes
  document selection, changed/unchanged structure, and per-document Undo.
- A Settlement reminder names the Note, exact pending state, and Agent-change
  count when present. A nonzero count is followed by Review Changes in reading
  order; no such action is invented otherwise. Agent Changes names the
  Note, Action/Run, exact activity position and revisions, change kind, and any
  Earlier Revision or Created by this Run state. Before/After and inserted,
  removed, or changed structure remain perceivable without color. Previous and
  Next have keyboard, pointer, focus, and accessibility equivalents. Neither
  surface has Settle or Dismiss; closing Agent Changes records no review state,
  and the Document Action Rail retains the accessible Settle route.
- Reading Lead detail preserves the order of disposition, citation,
  bibliography, discovery, reason, uncertainty, note, source, parent, and
  technical identity.
- Source deletion, permanent Record deletion, and feedback editing use distinct
  labels, confirmations, consequences, recovery, and focus restoration.

### Acceptance threshold

Test long English and Simplified Chinese labels, mixed content, enlarged text,
minimum supported widths, file/error/recovery states, and native/editor focus
transitions. Beta/1.0 require complete keyboard and VoiceOver coverage for the
declared core and no unresolved critical or high-severity accessibility
defects. Human acceptance is required for assistive technologies and input
methods; additional languages and complete RTL acceptance remain deferred.
