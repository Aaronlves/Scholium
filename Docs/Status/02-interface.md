# Implementation Status: Reachable Interface

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Current user-facing reachability.

## App root and workspace shell

- Starting, Registry Recovery, Ready, and Storage Unavailable are distinct app
  roots. Failure states retain Details, Retry, and the applicable recovery or
  Quit route while workspace commands remain disabled.
- Registry Recovery identifies the single workspace-registration owner,
  preserves that damaged file, and retains Retry-only behavior for unsafe or
  unreadable state.
- Bootstrap is a separate narrow window for creating or connecting one
  Triptych, optional first-launch Agent preparation, and explicit workspace
  entry. Configured windows use one native Library–Document–Inspector split and
  one stable toolbar.
- Restore Access keeps exact-folder renewal primary and adds a confirmed
  **Remove Registration…** escape when that Triptych is gone or must be set up
  again. The confirmation distinguishes machine registration from unchanged
  Analyses, Topics, Works, and portable `.scholium` content before returning to
  ordinary Bootstrap.
- An incompatible or damaged portable owner uses the same bounded sheet (or
  retained Bootstrap review) to confirm **Archive and Rebuild…**. The copy
  states that the whole `.scholium` folder is preserved without migration and
  that Analyses, Topics, and Works are untouched.
- Each window retains its selected workspace, Library state, role-partitioned
  Document tabs, Edit-default live Document mode, Inspector mode, Search, Attention, and Action
  presentation. Research Records remains a separate Triptych-keyed window.
- Native Sidebar and Inspector controls mirror actual split visibility.
  The platform owns window, toolbar, divider, collapse, resize, fullscreen, and focus
  behavior; the document-navigation depth cue is decorative and noninteractive.

## Library and navigation

- Library presents Analyses, Topics, and Works as peer workspace destinations
  with stable selection, keyboard navigation, and ordinary Note totals.
  Switching saves or fails safely, then restores that workspace's
  filters, ordering, disclosure, tabs, Document mode, and Inspector mode.
- On live opening, the selected Vault's usable Library can replace the initial
  full-page Loading state before the remaining two Vaults finish. Their rows
  retain unavailable counts and selection until the complete generation; the
  existing derived-state progress presentation remains visible without
  blocking the available list or moving focus.
- Library is the only source-list destination. Add, context-menu, keyboard,
  drag, menu, and accessibility routes converge on the same source mutations.
  Note and Folder rows expose **Move to Trash…**; File-menu Command-Delete and
  named accessibility actions reach the same bounded confirmation.
- System-Trash confirmation lists every filesystem item, associated active
  Discussion, whole finished Record, and unaffected multi-Note participant,
  and states that Finder restoration cannot restore deleted Records. Recovery
  distinguishes forward cleanup from the outcome-unknown **Retain Records and
  Resolve** route.
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
- Edit applies heading presentation as soon as a valid ATX marker and separator
  exist, and preflights a caret-owned blank line at its eventual prose line box
  so first input does not move the caret or surrounding source lines.
- Document Find stays inside the Document rather than opening workspace Search.
  Edit and Source expose explicit Import Image and Index Image commands in the
  formatting, Format, and Insert routes; native selection and native image
  paste converge on the same editor transaction. The lower status reports
  body/selection statistics, while missing indexed absolute paths produce a
  nonauthorizing reminder.
- Complete Metadata is one Analysis/Topic/Work Note sheet with typed controls,
  a searchable source-type-aware Add a Field chooser, and reversible pending
  removal. Semantic groups use shared whitespace rather than repeated visible
  headings; labels carry concise Help, and the reserved field-action slot
  reveals on hover or focus without reflow. It edits only identity-keyed
  Scholium Metadata and never inserts or changes YAML. Authored `summary` and
  `keywords` remain visible through About and editable in Source.
- Workspace access recovery distinguishes one fingerprinted invalid Metadata
  record from an unsupported complete portable-control owner. Its confirmation
  names the direct record and archives only that unchanged file before retrying
  Triptych configuration.
- Inspector presents Overview, Connect, and Actions through the shared
  segmented control. Overview shows Needs Attention, Review, then About; Connect switches Incoming
  and Outgoing direct relations; Actions shows role-valid Platform Actions and
  Settle. A pending Review is one full-row route. Its exact pending activity set
  auto-presents the retained Document session's attached Review task once;
  closing suppresses that set without changing Review truth, and a later Agent
  activity presents again.
- An already-visible Inspector with no selected Document presents a restrained
  No Document Selected state instead of a blank plane or stale origin content.
- Every current Analysis Overview exposes **Link Zotero Item…** or **Manage
  Zotero Link…**; a bound Analysis also exposes **Open in Zotero**. The central
  sheet accepts an exact item key or bibliographic search, keeps exact library
  identity visible during selection, previews empty fields to fill and existing
  conflicts to retain, exposes **Link and Fill** or **Rebind and Fill**, and
  confirms Clear while changing neither Markdown nor Zotero data. Clear retains
  previously filled managed Metadata. A bound Analysis additionally exposes
  **Refresh Zotero Metadata…**. Its direct sheet reads only the linked item,
  presents fields to fill or update with current and Zotero values, retains
  Cancel while reading, and presents **Done** when every mapped value is current.
- Action sheets keep Profile Research Request visible, place only other
  optional inputs under Additional Instructions, and explain target mutation,
  read-only Additional Context, and later extra-Note approval. The bounded
  extra-write sheet has one denial, **Continue Without Additional Notes**;
  **End Action** remains separate. Sheets also expose
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
- The Saved Searches menu exposes archive-and-reset only while its local file
  is unreadable. Methods likewise exposes bounded, confirmed repair actions
  only for its typed invalid local owner.
- Attention is one transient anchored popover per workspace. It keeps current
  rows available during refresh or recoverable failure and preserves explicit
  Inspect, Resynthesize, Leave Unchanged, dismiss, and Retry routes.
- The Workspace Records control opens This Note scope for a resolved selected
  Note and remains available without a Document by opening Triptych scope.
  Research Records opens to Records or Reading Leads with toolbar View,
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
  presentation installs no unconditional feature-local focus return, so
  pointer dismissal does not paint a keyboard-only focus ring while AppKit
  retains keyboard focus behavior.

## Appearance, adaptation, and localization

- Settings now uses one searchable grouped sidebar: Application contains
  Triptychs, Appearance, and Hotkeys; This Triptych contains Metadata
  and Attention; Research Guidance contains Methods & Practices, Action
  Profiles, Agent Access, and External Tools & Citations. Triptych selection
  remains inside the Triptychs detail, and search uses only static Settings
  metadata.
- Hotkeys persists a machine-local closed command catalog, records Command-
  based shortcuts, rejects standard reservations and active duplicates, and
  updates the same SwiftUI menu commands that execute the actions. Per-command
  clear/default and complete default restoration are reachable.
- Appearance keeps the common profile and Body controls visible, moves Body
  details, Headings, Callouts, and CSS behind explicit disclosures, adds Revert
  to Saved and built-in-default restoration, and confirms before a profile
  switch can discard an unsaved draft.
- Settings → Metadata uses the shared segmented role selector and three
  deliberately independent sections: stable Managed Fields for the
  selected role, source-type-specific optional Agent preferences for Analyses,
  and About visibility/order. Custom rows expose editable labels and
  descriptions, controlled-choice extension, lifecycle, use counts, and named
  Archive/Restore without permitting key/kind mutation or value deletion.
  Adding a field does not populate Notes or select it in Agent or About settings;
  reset, clear, revert, reload after
  conflict, and atomic Save are separate actions. Current-schema repair keeps
  the decoded candidate and frozen exact-byte revision; unsupported or damaged
  schema states preserve their source and do not expose editable defaults.
  Invalid preferences identify their source type and field. Fixed New Note
  YAML is not configurable in Settings.
- Settings Metadata and Complete Metadata disable their complete editing
  surface while a save is pending, so no post-submit keystroke can be silently
  overwritten or discarded when the acknowledged result arrives.
- System, Light, and Dark use one semantic resolver across native and document surfaces. Accent and
  Paper are the only configurable color inputs; Interface, Scholarly, and Exact
  are the native text families.
- Inspector Mode, Connect direction, Search scope, Metadata role and creator
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
