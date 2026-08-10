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
- Library, Set Aside, and Trash share one native hierarchical source list while
  retaining their distinct actions. Add, context-menu, keyboard, drag, menu,
  and accessibility routes converge on the same source mutations.
- New Note and New Folder are immediate. Successful source mutations publish
  their exact selected destination before disposable derived views finish
  refreshing; failures preserve the prior presentation.
- Triptych Attention has one stable Sidebar entry. Zero is quiet, nonzero shows
  the exact aggregate count, and unavailable first load never claims zero.

## Document and Research Inspector

- Document presents the selected role's tabs and one live Review, Edit, or
  Source mode. No selection, empty source, loading, unavailable source,
  rendering failure, save failure, conflict, and recovery remain distinct.
- Review owns reading, navigation, previews, and passage Comment. Edit owns
  source-preserving semantic projection, formatting, suggestions, and task
  interaction. Source exposes the complete exact text. Conflict comparison and
  recovery remain Document-owned.
- Inspector presents Overview, Connect, and Actions as one mutually exclusive
  index. Overview shows current Attention and About; Connect switches Incoming
  and Outgoing direct relations; Actions shows role-valid Platform Actions and
  Settle.
- Action sheets expose academic inputs, target and mutation consequence,
  handoff, active Run state, result, evaluation, cancellation, and recovery
  without exposing credentials, registration keys, protocol internals, or
  implementation hashes. This remains the pre-cutover result presentation;
  Records is not yet the sole result-processing route.
- Action, Reading Lead note, and Researcher Evaluation sheets share the same
  fixed-header, scrolling-body, fixed-action layout while retaining separate
  workflow state and dimensions.
- The Action and Record routes still expose separate Evaluation presentation,
  but their adapters now save through the atomic Researcher Response
  capability and preserve the other partition. The combined Response sheet,
  fixed result-processing rail, Change Decision, and Compare Changes UI are not
  yet reachable.

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
  loading. Selecting a row replaces the collection with one retained detail
  route; Back restores the collection state.
- Record detail uses a dominant reading plane and optional Evidence & Judgment
  rail. Reading Lead detail uses one reading flow with independent handled
  state, complete citation, bibliographic and discovery facts, reason,
  uncertainty, researcher note, source, parent, and technical identity.
- Record deletion, Evaluation editing, evidence popovers, unresolved provenance,
  and recommendation handling retain named keyboard and accessibility routes.

## Appearance, adaptation, and localization

- System, Light, and Dark use one semantic resolver across native and document surfaces. Accent and
  Paper are the only configurable color inputs; Interface, Scholarly, and Exact
  are the native text families.
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
