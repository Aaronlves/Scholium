# Specification: Accessibility and Adaptation

Part of the canonical document set rooted at [SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md).
This chapter owns Section 20: accessibility and adaptation requirements; sibling chapters do not restate it.

## 20. Accessibility and adaptation

- Support System, Light, and Dark without hard-coded inversion.
- Meet at least **4.5:1** contrast for ordinary small text and **3:1** for large
  or bold text; audit every important custom target below 28 × 28pt.
- Preserve hierarchy under Increase Contrast, Reduce Transparency, Reduce
  Motion, inactive windows, 200% document text, and accent changes.
- Treat custom elevation only as a secondary depth cue. Increase Contrast
  removes its soft shadow and strengthens the semantic boundary; Reduce
  Transparency and inactive-window presentation may weaken it. The surface,
  boundary, label, focus, and placement must keep every floating action or
  presentation distinguishable when elevation is absent.
- Treat the Workspace's document-navigation boundary cue as decoration. It is
  outside the accessibility tree, receives no hit testing, changes no layout,
  and remains visually continuous across the titlebar/toolbar background and
  content region. It follows the logical Sidebar edge in right-to-left
  presentation. Dark appearance, Reduce Transparency, and inactive windows
  weaken it under §19.3; Increase Contrast removes it completely. The native
  tracking separator and semantic Navigation/Document surface difference must
  preserve the structural hierarchy when the cue is absent.
- Give every important state two suitable channels; never rely only on color,
  motion, sound, location, or arrow direction.
- Actions exposes every official and researcher-enabled operation as a linear
  accessible list without requiring hover. Research Records exposes Scope,
  View, lists, filters, recommendation status, dialogue order, participants,
  anchors, provenance, and Record Details with complete keyboard navigation
  throughout its resizable **700 × 520pt** minimum.
- Inspector acceptance covers Overview, Connect, and Actions at **320pt** and
  **278pt**, plus long English, mixed English/Chinese, right-to-left layout,
  empty facts, long values, unavailable Actions, and 200% readability. The
  ModeIndex remains one logical horizontal group; a FactGrid stays horizontal
  or stacks as one whole; Action error and recovery text remains complete.
  Mode selection remains identifiable from persistent surface, font weight,
  native selected state, and accessibility value when pointer hover is absent.
- Connect exposes one named **Link Direction** segmented control whose visible
  **Incoming Links** and **Outgoing Links** segments expose the current selected
  value through native keyboard and VoiceOver behavior. Changing direction
  keeps focus on the control, returns the Connect scroll owner to its beginning,
  and announces an empty selected direction without hiding the other segment.
  Related and Incompatible rows remain available in both directions and state
  accessibly that their relation is undirected rather than implying two authored
  edges.
- Overview exposes the complete Needs Attention summary as one button with the
  current-Note count and scope, while the About heading exposes the
  **Edit Properties** action without absorbing selectable values into the
  control. A current Analysis with a valid Zotero item key exposes one
  keyboard- and VoiceOver-reachable **Open in Zotero** button inside About;
  neither the key nor metadata enters the accessibility tree. Each Connect
  Note row is one primary button whose accessible name
  states its relationship; its cluster symbol is decorative and hidden from
  accessibility. A distinct source anchor remains a named accessibility action
  after the visual trailing symbol is removed.
- Provide complete keyboard and visible-focus paths. Restore focus after
  sheets, alerts, Search, popovers, Action sheets, conflict comparison, and
  Research Records close.
- Search exposes provider, visible scope, query text, result count, matched
  field/relation, source freshness, and destination without relying on color.
  Provider-specific completion and results share one listbox position: only one
  owns selection at a time; Up/Down Arrow moves it, Return accepts or opens,
  Escape closes the current layer, and pointer acceptance preserves the same
  semantics. Accepting completion edits plain query text and restores the
  insertion point. **Explain Query** is keyboard and VoiceOver reachable and
  reads the Application response's provider, clauses, relation direction,
  normalization, ordering, and limitations. A compact summary may expose the
  complete explanation on demand, but the complete fields remain reachable
  through keyboard and VoiceOver without requiring hover or pointer-only
  discovery; no accessibility presentation reparses the query or substitutes a
  view-local explanation. Invalid, ambiguous,
  provider-mismatch, not-applicable, Graph-unavailable, stale, and empty states
  are separately named and keep a usable edit or retry target. Note results
  identify their source context; Record results identify Record and speaker,
  and opening either restores focus at the exact available destination.
- Direct root creation has the Library Add menu's pointer and accessibility
  routes for both **New Note** and **New Folder**; unoccupied-space context
  actions are redundant. **New Note** additionally has **File → New Note** and
  its keyboard shortcut. A successful note action moves selection to the created
  note, exposes its selected Library row even when filters or collapsed
  ancestors previously hid the destination, and leaves keyboard focus on its
  natural post-command destination. A failure before that transition leaves the
  current Library presentation and selection unchanged and reports the reason
  without opening a naming dialog.
- An ordinary Note exposes Rename and Move as distinct accessibility actions.
  Dragging the Note to a Folder or the Library LocationHeader is a redundant
  pointer route with a system Move operation and visible target feedback; File
  retains **Move Note…** for keyboard and menu access. Successful placement
  keeps the moved Note selected, while a rejected or failed drop leaves source,
  selection, and disclosure unchanged and reports the failure.
- An ordinary Folder exposes Move Folder as a named accessibility action.
  Folder-to-Folder and Folder-to-LocationHeader dragging is a redundant pointer
  route with system Move feedback; invalid self, descendant, current-parent,
  cross-vault, protected, and ambiguous targets never advertise acceptance.
  The adaptive disclosure button exposes its current Expand All Folders or
  Collapse All Folders action to keyboard and VoiceOver; automatic current-Note
  reveal moves neither Library nor Document focus.
- With no selected document, Document exposes the title and instruction from
  §18.2 as one read-only VoiceOver group. Its symbol stays hidden from
  accessibility, and the state never accepts focus or duplicates a Library,
  File-menu, keyboard, or toolbar action.
- Library exposes the static Scholium wordmark and Triptych identity menu as
  distinct elements. The Triptych identity row additionally exposes one stable
  **Open Triptych Attention** control whose accessible value names checking,
  unavailable, zero, or the exact aggregate count. Its warning symbol, count,
  text role, complete-target interaction surface, and accessible value keep
  Attention distinct from neutral Note totals without using color alone. Rest
  has no background; hover, keyboard focus, press, and the open popover expose
  the same complete target without making the number a badge. Zero removes only
  visible count and emphasis, not the route. Collapsing Sidebar adds no Attention
  element, count, value, or reserved gap to the Document toolbar; the
  contextual route returns when Sidebar is shown, while an applicable
  Inspector summary remains independently reachable.
  TriptychWorkspaceNavigator is one logical vertical group with current
  selection and Up/Down Arrow navigation. Selection remains identifiable
  through a persistent Navigation surface, font weight, native/accessibility
  selected state, and position when pointer hover is absent. Each row exposes
  its localized ordinary-active-Note count as neutral, noninteractive metadata;
  zero remains a real value and an unavailable first result is not announced as
  zero. Workspace rows expose no Attention value. Switching by keyboard keeps
  focus on the selected row; cross-workspace Note navigation follows its exact
  destination focus contract. Inactive workspace Library, tab group, Document,
  and Inspector content is inert and accessibility-hidden.
  LocationPicker exposes its localized current Location, expanded state, and
  selected native menu item; optional Location counts are values, not badges or
  selection state. Inactive Location content is accessibility-hidden. The
  hover-revealed Put Back control is also shown for keyboard focus; the row's
  named Put Back accessibility action remains available without hover, and row
  removal follows the next/previous/LocationPicker focus sequence defined in
  §18.3.
  Settings remains available through standard application routes, not as a
  Library destination.
- Attention exposes its popover heading, filter, three group headings,
  selected task, issue, resolved Note title, locator, state, and available
  actions in one linear keyboard and VoiceOver order. Loading retains that
  structure; refreshing, stale, and recoverable failure keep the last complete
  rows operable while status and Retry remain named. When the selected task
  disappears, focus follows the next/previous/filter sequence in §18.3.
- Research Records exposes **Scope** as a named native menu and **View** as a
  named toolbar editorial index of native buttons; its labels remain **Records**
  and **Reading Leads** without appended counts. Selection and availability
  remain current without relying on position or color. Left/Right
  Arrow moves between View choices without coupling the Scope value. Each
  collection exposes one ordered, readable column header; Record, Action, and
  Date headers expose current sort direction and keyboard-operable sorting.
  The exact filtered total is announced with the first content-column header,
  not as part of a toolbar control. Incremental loading preserves the current
  rows, exposes loading and recoverable Retry status at the list boundary, and
  never changes the announced total to the loaded slice size. Each Record row
  exposes one complete destination without requiring a navigation glyph. Its
  unlabeled visual Attention gutter receives a semantic accessibility label
  only when an exception exists; the Action capsule is included as a value in
  the row label and is not exposed as a separate control; the focal Note and
  finished date are included in the row label. Each
  Literature Recommendation occurrence exposes its independently operable,
  labelled Handled checkbox first, then Title, Author(s), Year, and Publication
  in one detail destination. The checkbox may omit visible row text but retains
  its complete name and current value. Detail preserves one linear order from
  scholarly identity and the independently operable header disposition button
  through the selectable full citation, Bibliography, Discovery Locators,
  reason, uncertainty, researcher note, source, parent, and technical identity.
  The muted full citation precedes the visual information band and remains
  exposed as a complete citation; Bibliography keeps Zotero identity with the
  other structured bibliographic fields. Bibliography and Discovery Locators may share a
  regular-width visual row, but enlarged text or a narrow width stacks the two
  complete groups in the same accessibility order. The detail button exposes
  the action **Mark as handled** or **Mark as unprocessed**, the current
  Unprocessed/Handled value, concise Help, keyboard focus, and the semantic
  hint that processing implies no reading, acceptance, citation, verification,
  or endorsement. Its immediate clock/checkmark and text response is not the
  only state channel and becomes motionless under Reduce Motion. Label/value
  grids expose labels and values in source order even when their visual layout
  changes from columns to stacked rows.
  Group headings never imply a shared handled state. Empty, load-error, and
  partially unsupported Record states remain named and keyboard reachable.
  Participants and Context Used headings expose their total and bounded-preview
  state, and become keyboard-operable controls only when a complete popover is
  available. Popover rows retain headings, source labels, exact unavailable
  provenance, selection, and source-opening routes in a linear order; Escape or
  dismissal returns focus to the originating heading. Native-toolbar Back and
  Evidence controls have distinct names, help, roles, focus, and immediate
  pressed feedback. Evidence exposes **Shown / Hidden** as its current value;
  hiding the rail removes it from the active accessibility tree without
  disturbing reading-plane order, and showing it restores the same first
  Evidence heading. The Record-header permanent-delete icon has a distinct
  name, help, role, focus, and pressed feedback; delete is not communicated by icon shape or destructive color alone,
  and confirmation dismissal returns focus to it. Attributed statements expose
  author before prose in reading order; Researcher and Agent remain distinct by
  visible label and symbol when authorship color is unavailable. Their fixed
  visual columns reflow prose without clipping at the window minimum. Evidence
  section headings retain one heading level and aligned target rhythm; quotation
  and document symbols are decorative supplements rather than the sole
  distinction between Context Used and Participants.
- Keep VoiceOver names, roles, values, headings, anchors, selection, errors,
  and consequences current. Hide decoration from accessibility.
- A running Action exposes its Action name and **Running** state together while
  retaining a distinct, explicitly named **End Action** control in the same
  linear Actions order. Its progress animation is not the sole state channel.
- Pairing and re-pairing expose one linear keyboard order from Run identity and
  local-connection explanation through Copy Handoff and status. One-time-code
  expiry, invalid attempt, Session expiry/revocation, app-restart invalidation,
  missing local Skill-folder path, and bridge unavailable are named in text
  with one executable recovery route. The one-time code remains inside the
  complete copied handoff and is never a separate visual or accessibility
  field. Secrets, hashes, and opaque registration keys are never presented as
  fields the researcher must read or enter.
- Researcher Evaluation follows the returned result in the Action sheet and
  uses the same label, help, choice, note, error, save-status, and focus order
  in the Record-detail sheet opened by its named section heading. Observed
  Issues, the mutually exclusive no-issue option,
  Valuable Discovery, note, Save, and Clear are fully keyboard operable. Draft,
  saving, saved, stale revision, conflict, deletion, and failure are announced
  without color, hover, or visual position as the sole channel. Save returns a
  useful focus target without moving focus away from the result unexpectedly;
  a close confirmation keeps the unsaved draft available when cancelled.
- Bounded Write Set permission presents every requested document identity,
  role, operation, and stale/unavailable state in a linear group and supports
  exact subset selection without drag, secondary click, or color. Rejecting or
  disabling one member does not make another appear authorized.
- Document-owned Autosave Failed and Conflict toasts announce their state,
  retained-buffer consequence, and available recovery action. Persistent
  failure remains reachable after its announcement; the transient Checkpoint
  Restored confirmation is announced once without moving document focus.
- Keep accessibility labels and hints semantically complete but nonduplicative
  under §19.6. The visible two-line authoring budget never removes information
  needed to distinguish source, state, authority, consequence, or recovery.
- The separate Review Comment bar and Edit formatting bar are keyboard
  reachable and expose every visible command by name. Review's Comment field announces the inclusive line
  range, Return-to-save, Shift-Return-to-insert-line, and Escape-to-cancel
  behavior without moving or erasing the underlying document selection.
- Edit input suggestions retain document focus and expose one current listbox
  selection: Up/Down Arrow moves through results, Return accepts, Escape closes,
  and primary click accepts the pointed row. Closing or accepting returns to the
  same CodeMirror caret; scrolling keeps the list attached to it. Note title and
  path remain distinguishable at enlarged interface text, long paths truncate
  without hiding the title, and empty or ambiguous results never trap focus.
  Completion names, roles, selected state, and result count remain available to
  VoiceOver without exposing SF Symbols as duplicate labels. Marked-text
  composition opens no suggestion list and receives no forced selection.
- The Appearance Line width slider has a localized label and help text, exposes
  its current value in character-width units, and supports standard keyboard
  adjustment and VoiceOver without requiring pointer dragging.
- Test long labels, mixed English/Chinese, right-to-left chrome, minimum width,
  every lifecycle/error state, and editor/native-container focus transitions.
- At the Library boundary, verify both permitted narrow outcomes: expanded at
  **300pt or wider**, or natively collapsed. The open-but-unreadable compressed
  state is forbidden. All three Triptych workspaces, their Note totals, the
  current Location, and
  applicable Library actions remain reachable at the threshold; localized and
  right-to-left variants are covered by the adaptation matrix. Library rows
  grow vertically rather than clipping enlarged interface text.
- Keep the configured minimum inline separation from both structural dividers.
  At 200% document text, prose must reflow without page-level horizontal
  reading scroll; only wide tables, code, and mathematics may scroll inside
  their own containers.
- Synthetic events cannot certify real VoiceOver, Voice Control, Dictation,
  Full Keyboard Access, or CJK IME; retain manual gates where required.
- A lifecycle timeout preserves the affected editor buffer, restores a useful
  focus target, and exposes retry without treating local presentation-state
  persistence as research-content failure.
- The Storage Unavailable root page exposes an immediate, keyboard-default
  Retry; selectable Details; and Quit with current VoiceOver names, values,
  focus order, and failure text. Registry Recovery uses the same linear root
  order; a repairable malformed registry instead makes Relink Triptych the
  keyboard default and names that it preserves the original file before setup.
  A newer-schema or I/O registry failure keeps Retry as the default and has no
  destructive action. Both root states remain legible under Increase Contrast
  and do not rely on animation, transparency, or color to communicate failure
  or recovery.

Beta and 1.0 require complete keyboard and VoiceOver coverage for the declared
core and no unresolved critical/high-severity accessibility defects. A medium-
severity ceiling remains a release-owner judgment.
