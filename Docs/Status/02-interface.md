# Implementation Status: Reachable Interface

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Current user-facing reachability.

## App root and workspace shell

- Starting, Registry Recovery, Ready, and Storage Unavailable are distinct app
  roots. Failure states retain Details, Retry, and the applicable recovery or
  Quit route while workspace commands remain disabled.
- Bootstrap is a separate narrow window for creating or connecting one
  Triptych, optional first-launch Agent preparation, and explicit workspace
  entry. Configured windows use one native Library–Document–Inspector split and
  one stable toolbar.
- Each window retains its selected workspace, Library state, role-partitioned
  Document tabs, Document mode, Inspector mode, Search, Attention, and Action
  presentation. Research Records remains a separate Triptych-keyed window.
- Native Sidebar and Inspector controls mirror actual split visibility.
  The platform owns window, toolbar, divider, collapse, resize, fullscreen, and focus
  behavior; the document-navigation depth cue is decorative and noninteractive.

## Library and navigation

- Library presents Analyses, Topics, and Works as peer workspace destinations
  with stable selection, keyboard navigation, and ordinary-active-Note totals.
  Switching saves or fails safely, then restores that workspace's Location,
  filters, ordering, disclosure, tabs, Document mode, and Inspector mode.
- On live opening, the selected Vault's usable Library can replace the initial
  full-page Loading state before the remaining two Vaults finish. Their rows
  retain unavailable counts and selection until the complete generation; the
  existing derived-state progress presentation remains visible without
  blocking the available list or moving focus.
- Library, Set Aside, and Trash share one native hierarchical source list while
  retaining their distinct actions. Add, context-menu, keyboard, drag, menu,
  and accessibility routes converge on the same source mutations.
- New Note and New Folder are immediate. Successful source mutations publish
  their exact selected destination before disposable derived views finish
  refreshing; failures preserve the prior presentation. New Note installs one
  Edit session directly, focuses its exact body start after editor
  acknowledgement, and retains committed source behind Retry Edit / Source if
  startup fails.
- Triptych Attention has one stable Sidebar entry. Zero is quiet, nonzero shows
  the exact aggregate count, and unavailable first load never claims zero.

## Document and Research Inspector

- Document presents the selected role's tabs and one live Review, Edit, or
  Source mode. No selection, exact empty body, loading, unavailable source,
  rendering failure, save failure, conflict, and recovery remain distinct.
- Review owns reading, navigation, previews, and passage Comment. Edit owns
  source-preserving semantic projection, formatting, suggestions, and task
  interaction. Source exposes the complete exact text. Conflict comparison and
  recovery remain Document-owned.
- Document Find stays inside the Document rather than opening workspace Search.
  Edit and Source expose explicit Import Image and Index Image commands in the
  formatting, Format, and Insert routes; native selection and native image
  paste converge on the same editor transaction. The lower status reports
  body/selection statistics, while missing indexed absolute paths produce a
  nonauthorizing reminder.
- Complete Properties is one Analysis/Topic/Work Note sheet with direct
  source-safe controls, a searchable source-type-aware Add a Property chooser,
  reversible pending removal, and an Edit in Source route for unsupported or
  malformed source. Semantic groups use shared whitespace rather than repeated
  visible headings; labels carry concise Help, and the reserved field-action
  slot reveals on hover or focus without reflow. Custom fields remain together. A YAML-free Note first
  presents Add YAML Properties… and Keep Without YAML; choosing insertion opens
  only a draft and Save remains unavailable until one canonical value is valid.
- Inspector presents Overview, Connect, and Actions through the shared
  segmented control. Overview shows Needs Attention, Review, then About; Connect switches Incoming
  and Outgoing direct relations; Actions shows role-valid Platform Actions and
  Settle. A pending Review is one full-row route. Its exact pending activity set
  auto-presents the retained Document session's attached Review task once;
  closing suppresses that set without changing Review truth, and a later Agent
  activity presents again.
- Every current Analysis Overview exposes **Link Zotero Item…** or **Manage
  Zotero Link…**; a bound Analysis also exposes **Open in Zotero**. The central
  binding sheet searches local user and group libraries, keeps exact library
  identity visible during selection, supports Rebind, and confirms Clear while
  changing neither Markdown nor Zotero data.
- Action sheets expose academic inputs, target and mutation consequence,
  handoff, active Run state, continuation, cancellation, and recovery without
  exposing credentials, registration keys, protocol internals, or
  implementation hashes. Finalized Result, Evaluation, and Method Feedback now
  appear only in the exact Research Record.
- Action, Reading Lead note, and combined Researcher Response sheets share the same
  fixed-header, scrolling-body, fixed-action layout while retaining separate
  workflow state and dimensions.
- Record reading detail shows progressive Researcher Response; its Evidence
  rail shows Changes, Effects, Context Used, Participants, and Technical
  Details without repeating the Changes count under Effects. The Response
  heading shares the reading plane's content baseline. One combined editor
  atomically saves Evaluation and optional Method
  Feedback. The shared folding exact comparison remains read-only until an
  explicitly granted whole-document recovery. Notification clicks produce the
  validated exact result route and its Records-window-lifetime direct-Undo
  grant; ordinary Records browsing does not receive the grant.
- Copy Handoff success closes the preparation sheet and returns focus through
  the existing Action-row focus owner. Actions project Waiting, Running, Needs
  Attention, and repair text from durable execution truth. Waiting and Running
  open a compact status sheet; a finalized Record ends the Action row.
- Foreground completion presents a dismissible Review Result banner only in
  the source window. Authorized background completion uses a private system
  notification; click routing retains its exact Triptych, Record, and finalized
  fingerprint even when no main window remains. Arrival alone never opens,
  retargets, focuses, or activates Records. Delivery is one-shot and independent
  of Note Review.

## Search, Attention, and Research Records

- Search is a compact command surface with visible scope, typed diagnostics,
  provider-aware completion and results, freshness, Saved Searches, and Explain
  Query. Opening a result routes to the exact current Note, source range,
  Record, or attributed statement.
- Attention is one transient anchored popover per workspace. It keeps current
  rows available during refresh or recoverable failure and preserves explicit
  Inspect, Resynthesize, Leave Unchanged, dismiss, and Retry routes.
- Research Records opens to Records or Reading Leads with toolbar View,
  window-local Scope, search, filters, sorting, exact total, and incremental
  loading. View uses the same quiet-track, raised-selection segmented control
  as the Workspace surfaces and has no shared Liquid Glass background. Selecting a row
  replaces the collection with one retained detail route; Back restores the
  collection state. Record detail omits the generic toolbar title.
- Record detail uses a dominant reading plane and optional Evidence
  rail. Reading Lead detail uses one reading flow with independent handled
  state, complete citation, bibliographic and discovery facts, reason,
  uncertainty, researcher note, source, parent, and technical identity.
- Record deletion, Response editing, folding comparison,
  evidence popovers, unresolved provenance, and recommendation handling retain
  named keyboard and accessibility routes. Native Response and comparison
  presentation no longer installs unconditional feature-local focus return, so
  pointer dismissal does not paint a keyboard-only focus ring while AppKit
  retains keyboard focus behavior.

## Appearance, adaptation, and localization

- Settings → Properties uses the shared segmented role selector and the ordered New Notes,
  Agent-Created Analyses, and About sections. Exact seed
  delimiters are visible but not editable; source errors stay inline; Agent
  requirements remain source-type-specific; reset, clear, revert, reload after
  conflict, and atomic Save are separate actions. Current-schema repair keeps
  the decoded candidate and frozen exact-byte revision; unsupported or damaged
  schema states preserve their source and do not expose editable defaults.
  Seed refusals identify their role and structured line/column; choosing the
  diagnostic returns focus and selection to that source line.
- Settings Properties and Complete Properties disable their complete editing
  surface while a save is pending, so no post-submit keystroke can be silently
  overwritten or discarded when the acknowledged result arrives.
- System, Light, and Dark use one semantic resolver across native and document surfaces. Accent and
  Paper are the only configurable color inputs; Interface, Scholarly, and Exact
  are the native text families.
- Inspector Mode, Connect direction, Search scope, Properties role and creator
  kind, and Records View now share one equal-segment control with an adaptive
  neutral track and selection plate, continuous corners, Left/Right traversal,
  and no Accent-filled selection.
- Shared semantic owners cover surfaces, boundaries, transient elevation,
  structural depth, interaction feedback, corner geometry, symbols, typography,
  spacing, component cadence, and purpose-named motion. Native system controls
  retain platform presentation.
- Increase Contrast strengthens semantic boundaries and removes custom soft
  shadows. Reduce Motion removes custom animation. Content and controls reflow
  rather than clip where the declared adaptation permits growth.
- English and Simplified Chinese catalogs are reachable. Stable identifiers,
  paths, exact Markdown, researcher-authored text, and Skill names remain
  verbatim.
