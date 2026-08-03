# Specification: Accessibility and Adaptation

Part of the canonical document set rooted at [SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md).
This chapter owns Section 20: accessibility and adaptation requirements; sibling chapters do not restate it.

## 20. Accessibility and adaptation

- Support System, Light, and Dark without hard-coded inversion.
- Meet at least **4.5:1** contrast for ordinary small text and **3:1** for large
  or bold text; audit every important custom target below 28 × 28pt.
- Preserve hierarchy under Increase Contrast, Reduce Transparency, Reduce
  Motion, inactive windows, 200% document text, and accent changes.
- Give every important state two suitable channels; never rely only on color,
  motion, sound, location, or arrow direction.
- Actions exposes every official and researcher-enabled operation as a linear
  accessible list without requiring hover. Research Record exposes its list,
  filters, dialogue order, participants, anchors, and Record Details with
  complete keyboard navigation inside its fixed readable utility-window size.
- Inspector acceptance covers Overview, Connect, and Actions at **320pt** and
  **278pt**, plus long English, mixed English/Chinese, right-to-left layout,
  empty facts, long values, unavailable Actions, and 200% readability. The
  ModeIndex remains one logical horizontal group; a FactGrid stays horizontal
  or stacks as one whole; Action error and recovery text remains complete.
- Overview exposes the complete Needs Attention summary as one button with the
  current-Note count and scope, while the About heading exposes the
  **Edit Properties** action without absorbing selectable values into the
  control. A current Analysis with a valid Zotero item key exposes one
  keyboard- and VoiceOver-reachable **Open in Zotero** button inside About;
  neither the key nor metadata enters the accessibility tree. Each Connect
  Note row is one primary button whose accessible name
  states its relationship; its cluster glyph is decorative and hidden from
  accessibility. A distinct source anchor remains a named accessibility action
  after the visual trailing glyph is removed.
- Provide complete keyboard and visible-focus paths. Restore focus after
  sheets, alerts, Search, popovers, Action sheets, conflict comparison, and
  Research Record close.
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
  distinct elements. ScopeIndex is one logical horizontal group with current
  selection and reading-direction-aware arrow navigation, and exposes no
  Attention values. The conditional Sidebar alert exposes
  **Open Attention** with its selected Scope and exact count; zero contributes
  no element or gap. If its last item disappears while it owns keyboard focus,
  focus moves to LocationPicker. Collapsing Sidebar adds no Attention element,
  count, value, or reserved gap to the Document toolbar; the contextual route
  returns when Sidebar is shown, while an applicable Inspector summary remains
  independently reachable.
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
- Recommended Bibliography is exposed after the Library source region as one
  **Triptych Recommended Bibliography** group. Its accessible scope does not
  rely on fixed position or surface color, and its full workflow remains
  keyboard and VoiceOver reachable across Scope and Location changes. The
  compact band contains one **Open Recommended Bibliography** button whose value
  is **No recommendations** or the recommendation count; no candidate inside
  the compact preview becomes a separate accessibility target.
- Keep VoiceOver names, roles, values, headings, anchors, selection, errors,
  and consequences current. Hide decoration from accessibility.
- A running Action exposes its Action name and **Running** state together while
  retaining a distinct, explicitly named Cancel control in the same linear
  Actions order. Its progress animation is not the sole state channel.
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
- The Appearance Line width slider has a localized label and help text, exposes
  its current value in character-width units, and supports standard keyboard
  adjustment and VoiceOver without requiring pointer dragging.
- Test long labels, mixed English/Chinese, right-to-left chrome, minimum width,
  every lifecycle/error state, and editor/native-container focus transitions.
- At the Library boundary, verify both permitted narrow outcomes: expanded at
  **300pt or wider**, or natively collapsed. The open-but-unreadable compressed
  state is forbidden. All three Triptych scopes, the current Location, and
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
  focus order, and failure text. It remains legible under Increase Contrast and
  does not rely on animation, transparency, or color to communicate failure or
  recovery.

Beta and 1.0 require complete keyboard and VoiceOver coverage for the declared
core and no unresolved critical/high-severity accessibility defects. A medium-
severity ceiling remains a release-owner judgment.
