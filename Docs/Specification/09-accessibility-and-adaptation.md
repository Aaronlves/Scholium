# Specification: Accessibility and Adaptation

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Section 20.

## 20. Accessibility and adaptation

### Visual adaptation

- Support System, Light, and Dark without hard-coded inversion. Preserve
  hierarchy under Increase Contrast, Reduce Transparency, Reduce Motion,
  inactive windows, Accent changes, English and Simplified Chinese interface
  text, 200% document text, and enlarged interface text.
- Ordinary small text meets at least **4.5:1** contrast; large or bold text
  meets at least **3:1**. Audit every important custom target below 28 × 28pt.
- Important state uses at least two suitable channels. Color, motion, sound,
  location, hover, drag, secondary click, gesture, and arrow direction are
  never the sole source of meaning or access.
- Custom elevation is secondary. Increase Contrast removes soft shadows and
  strengthens semantic boundaries; Reduce Transparency and inactive-window
  presentation may weaken them. Floating content remains distinguishable by
  surface, boundary, label, focus, and placement.
- Structural depth cues are decorative, noninteractive, hidden from
  accessibility, mirrored at logical edges, and removable without losing the
  underlying pane relationship.
- Text and controls grow or reflow rather than clip. At 200% document text,
  prose has no page-level horizontal reading scroll; only intrinsically wide
  tables, code, mathematics, and diagrams may scroll or scale inside their own
  containers.

### Input, focus, and semantics

- Every core task has keyboard, menu or toolbar, pointer, focus, accessibility,
  cancellation, and recovery coverage appropriate to the platform control.
  Drag and secondary click remain redundant routes.
- Focus is visible and predictable. Native macOS controls and presentations let
  AppKit preserve the initiating modality: keyboard dismissal returns to the
  initiating control or the next valid semantic target, while pointer dismissal
  does not synthesize a keyboard-only focus ring. Feature call sites do not add
  unconditional `FocusState` restoration around native Buttons, sheets, or
  segmented controls. The shared activation-focus adapter remains limited to
  custom controls whose keyboard owner cannot be expressed natively. Removal
  follows a stable next, previous, then owning-container sequence.
- Custom controls expose current names, roles, values, selected state,
  availability, errors, consequences, and recovery actions. Decoration and
  duplicate symbols stay out of the accessibility tree. Help and hints add
  missing meaning rather than repeating visible text.
- State changes that matter without focus movement are announced once and
  remain inspectable. Progress animation is never the only Running signal;
  persistent errors remain reachable after announcement.
- Synthetic events cannot certify genuine VoiceOver, Voice Control, Dictation,
  Full Keyboard Access, installed input methods, or system text services.
  Release acceptance retains the corresponding human gates.

### Workspace, Library, and navigation

- With no document selected, Document exposes the title and instruction in
  §18.2 as one read-only VoiceOver group. Its symbol is decorative and the state
  adds no duplicate creation action or focus target.
- The Triptych workspace navigator is one vertical single-choice group with
  selected state, Up/Down traversal, localized Note totals, and inert hidden
  workspaces. Switching preserves focus on the selected destination until the
  resulting Document route requires another focus target.
- Back and Forward expose stable names and current availability in both the
  toolbar and View menu. A successful visit updates them without moving focus;
  revisiting a document uses the ordinary source-safe transition and preserves
  the current content when its destination is unavailable.
- Library exposes Triptych identity, Attention, Location, filters, disclosure,
  Add, hierarchy, selected row, and lifecycle actions without requiring hover.
  Note and Folder move, root move, Put Back, Expand/Collapse All, and contextual
  creation retain named non-drag accessibility routes.
- The expanded Library is either at least its declared readable width or
  natively collapsed. An open but unreadably compressed Sidebar is forbidden.
  English and Simplified Chinese variants retain workspace, Location, row, and
  action reachability at that boundary.
- Attention exposes heading, filter, groups, selected task, issue, Note,
  locator, state, and actions in one linear order. Loading, stale, and
  recoverable failure preserve current rows and name Retry.

### Document and editor

- Managed New Note announces the created Note once, opens Edit, and places the
  insertion point at the exact body start without an intermediate Review or
  Library focus stop. A committed-source/editor-failed state names **Retry
  Edit** and **Source** and never invites duplicate creation.
- Review, Edit, and Source expose their current mode, exact content state, and
  one coherent focus order. Mode changes, external updates, conflict,
  recovery, window inactivity, and container reconstruction never discard a
  dirty buffer, composition, selection, Undo, or recovery authority.
- The Document Mode toolbar button exposes its stable label and current Review,
  Edit, or Source value. Pointer help is supplementary; menu and keyboard routes
  remain complete.
- Review Comment and Edit formatting surfaces are keyboard reachable and stay
  attached to the finalized selection. The Comment field names its line range
  and Return, Shift-Return, and Escape behavior without erasing the underlying
  selection.
- Edit suggestions retain document focus and one listbox selection. Up/Down
  moves, Return accepts, Escape closes, and pointer acceptance has the same
  result. Marked-text composition opens no suggestion list or forced selection.
- English, Simplified Chinese, and mixed English/Chinese Source lines keep the
  visual cursor, selection, and installed input method consistent with visible
  content. Other Unicode source remains exact and Source-visible without a
  complete RTL input or bidirectional-layout promise. Code, mathematics, and
  inert raw HTML remain isolated technical regions without forcing surrounding
  prose direction.
- Tables, footnotes, mathematics, Callouts, links, and Mermaid preserve semantic
  names, source navigation, focus, and selectable fallback. Generated Mermaid
  content is not itself a passage Comment target; authored accessibility text
  is used when present and exact source remains the nonvisual fallback.
- Link previews and embedded Notes expose one target identity, complete
  read-only content, a named open route, and a keyboard-scrollable bounded
  viewport without repeating relationship-type copy. Their nested content
  never adds a second writable source, focus owner, or recursive embed tree.
- Autosave Failed, Conflict, and cleanup warnings state the retained-buffer or
  committed-source consequence and expose the applicable recovery. Checkpoint
  Restored is transient and never moves Document focus.

### Properties and portable settings

- Settings names the selected role, exact YAML editor, fixed delimiters,
  source-type picker, Agent-required checkboxes, About fields, structured-edit
  fields, validation location, dirty/save/conflict state, and separate restore
  or clear consequences in one keyboard order. Its multiline YAML editor keeps
  selection, Undo/Redo, Find, mixed-script text, and an LTR technical region.
- Source-type switching retains every unsaved requirements draft. Invalid
  fields in another role or type remain named and prevent the single atomic
  save. Revision conflict preserves the draft and offers **Reload Saved
  Settings**; errors are never color-only or a generic alert.
- Complete Properties exposes existing key, label, value/summary, editability,
  source-only state, and not-typical status. **Add a Property…** is a searchable
  grouped chooser with one listbox selection, keyboard acceptance, Escape
  cancellation, and focus return. YAML-free insertion explicitly distinguishes
  **Add YAML Properties…** from **Keep Without YAML**.
- About group headings participate in the reading hierarchy without becoming
  duplicate top-level sections. The complete fact grid preserves row/column
  association under enlargement and reflow. Tags are individually readable
  neutral tokens in source order, not color-coded status or unlabeled chips.

### Search, Inspector, and Research Actions

- Search exposes provider, scope, query, result count, match reason, freshness,
  and destination without color-only meaning. Completion and results share one
  listbox position; only one owns selection. Explain Query is keyboard and
  VoiceOver reachable and presents the Application explanation without
  reparsing the query.
- Invalid, ambiguous, provider-mismatch, unavailable, stale, and empty Search
  states remain distinct and retain an edit or retry target. Note and Record
  results identify their source context and restore focus at the exact available
  destination.
- Inspector's Overview, Connect, and Actions form one horizontal single-choice
  group. Selection remains identifiable without hover. At regular, compact,
  enlarged-text, and supported English, Simplified Chinese, and mixed-script
  presentations, About fields adapt as one complete grid and error/recovery
  text remains untruncated.
- Connect exposes one named Link Direction control with Incoming and Outgoing
  values. Changing direction keeps focus on the control, returns the scroll
  owner to the beginning, and announces an empty destination. Undirected rows
  state that they appear in both directions.
- Each Action remains a linear named operation. Running combines Action name and
  state while retaining a distinct End Action control. Unavailable Actions name
  the first executable repair; ordinary defaults do not repeat title summaries.
- Pairing and re-pairing expose one linear order through target, local-connection
  explanation, Copy Handoff, status, and recovery. One-use codes remain inside
  the complete copied handoff; credentials and opaque identifiers are never
  separate fields the researcher must read or enter.
- Bounded Write Set permission lists each document, role, operation, and stale
  or unavailable state, supports exact subset selection, and never makes one
  member appear authorized because another was selected.
- Copy Handoff success closes preparation and returns focus to the originating
  Action row. Result arrival announces no focus change; the Action row and
  actionable notification remain explicit routes to the exact Record.
- The combined Researcher Response editor orders Evaluation before Method
  Feedback and exposes one atomic Save Response state. Dirty, saving, stale,
  failed, and explicit-clear confirmation are named without relying on color.

### Research Records

- Scope and View are separately named controls. Collections expose ordered
  headers, sort direction, exact filtered total, loading and Retry at the list
  boundary, and one complete destination per row. Loaded rows remain available
  during later-page failure.
- Record rows communicate exceptional Attention, Action, focal Note, and date
  in one accessible row value. Reading Lead rows expose the independently
  operable handled control before the bibliographic destination; handled means
  processed only, never read, accepted, cited, verified, or endorsed.
- Selecting detail removes the collection from the active accessibility tree.
  Back restores the retained collection. Evidence Shown/Hidden is a current
  value; hiding removes the rail from the active tree without disturbing the
  reading order.
- Record detail reads author before attributed prose. Participants and Context
  Used disclose totals and become controls only when a complete popover exists;
  dismissal returns focus to the heading. Unresolved provenance remains
  selectable and noninteractive.
- The reading plane exposes Researcher Response before the Evidence rail. The
  rail reads Changes, Effects, Context Used, Participants, and Technical
  Details in that order at minimum width and enlarged mixed-script settings.
  Compare Changes exposes document
  disclosure state, selected complete documents, changed rows, folded unchanged
  counts, and per-document undo outcomes; focus returns to the Result or
  Conflict owner selected by its footer action.
- A newly pending Note Review activity set announces its attached Document task
  once without moving focus. Closing the task removes it from the active tree;
  the Overview Review row remains the named route that can present it again.
- Reading Lead detail retains one order from disposition and full citation
  through bibliography, discovery, reason, uncertainty, note, source, parent,
  and technical identity. Narrow or enlarged presentation stacks complete
  groups without changing that order.
- Permanent deletion and evaluation editing use distinct named controls,
  confirmation, current state, consequences, and focus restoration. Empty,
  unavailable, partial, and error states remain named and keyboard reachable.

### Acceptance threshold

Test long labels in English and Simplified Chinese, mixed English/Chinese
content, minimum width, every lifecycle/error state, and native/editor focus
transitions. Beta and 1.0 require complete keyboard and VoiceOver coverage for
the declared core and no unresolved critical or high-severity accessibility
defects. Their interface-language threshold covers only English and Simplified
Chinese resources, layout, and accessible names. Additional translations,
right-to-left chrome and navigation, and complete human acceptance of RTL
document input are deferred under §17; exact Unicode source preservation remains
mandatory. The release owner decides the acceptable medium-severity ceiling.
