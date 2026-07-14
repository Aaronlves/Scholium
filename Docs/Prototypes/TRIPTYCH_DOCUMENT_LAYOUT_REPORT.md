# Scholium Triptych Document Prototype Report

**Status:** Researcher-preferred frontend layout and page-logic report

**Prototype:** `triptych-document-layout.html`

**Reviewed:** 2026-07-14

**Traceability audit:** Checked against the current prototype, the complete
prototype-review conversation, `PRODUCT_GUIDE.md`, and `DESIGN_HANDBOOK.md` on
2026-07-14. Known prototype departures are recorded in Section 6.

## 1. Purpose and authority

This report records the researcher's requirements, bans, implementation
direction, and flexibility rules developed through repeated review of the
Triptych document prototype.

The prototype is Scholium's preferred baseline for main-window composition and
page logic. It is not:

- a frozen pixel specification;
- evidence that a function is implemented;
- a complete inventory of every future function;
- an editor-behavior specification; or
- a backend contract.

The `PRODUCT_GUIDE.md` owns product behavior and terminology. The
`DESIGN_HANDBOOK.md` owns stable interface rules and exact interface language.
This report explains how the prototype should inform future frontend work.
When they conflict, the Product Guide, Design Handbook, source fidelity,
accessibility requirements, and current Apple guidance take precedence.

### Frontend-only boundary

This report may guide hierarchy, placement, density, transitions, responsive
priority, native control choice, focus, keyboard behavior, accessibility, and
visual QA. It does not authorize changes to:

- Markdown editing or rendering mechanics;
- autosave or save transactions;
- repository, persistence, or version semantics;
- indexing or search-engine behavior;
- YAML, schemas, or property storage;
- filesystem coordination, vault identity, or bookmarks;
- CLI or API contracts; or
- agent permissions, execution, or direct-write behavior.

If a desired frontend surface appears to require a missing backend contract,
record the dependency as unresolved. Do not invent the contract while
implementing the layout.

## 2. My requirements

### 2.1 Overall character

1. Scholium is a document-first humanities research application, especially
   for philosophy. The open research document remains the dominant object.
2. The final interface must be native macOS 26, using SwiftUI and AppKit where
   appropriate.
3. Liquid Glass is the native material language for navigation and controls.
   The HTML only approximates its spatial effect.
4. The document, dense lists, expanded Properties, source, diffs, and
   diagnostics remain calm, opaque, and highly legible.
5. Scholium serves both a researcher and optional external agents. Researcher
   judgment, agent authorship, derived diagnostics, source content, and
   provenance remain visibly distinct.
6. The interface must remain usable for work beyond a dissertation: papers,
   books, chapters, teaching material, and long-term research.

### 2.2 Main-window composition

1. Use a three-region document-first model:
   - an optional leading Library sidebar;
   - a dominant central document region; and
   - one optional trailing contextual region.
2. Opening or closing the leading or trailing region must reflow the available
   space. The readable document column remains optically centered in the
   remaining document region.
3. The trailing panel enters from the right and narrows the document instead
   of unexpectedly covering it.
4. Use small native toolbar controls and groups rather than one monolithic
   toolbar panel.
5. Open-note tabs occupy the central toolbar band at the same vertical level as
   the other toolbar controls.
6. Open notes use native tab-view semantics and appearance, not a segmented
   control. Tabs must be bounded, clearly selected, closable, and capable of
   overflow, with dirty/conflict state, an accessible full name, keyboard
   cycling, and per-tab presentation restoration. At narrow widths, shorten
   labels before removing tabs. The current HTML's static three-tab strip is a
   layout approximation; closable tabs and overflow remain native target work.
7. Search sits adjacent to the open-note tabs as an icon. Activating it reveals
   and focuses a wider native Search field. The expanded field uses the native
   search symbol and no visible placeholder prose; scope and accessibility
   communicate its purpose.
8. Use one prominent document-local action: **Open Scholia…**. At narrow
   widths it becomes a centered icon with the full accessible name; it does not
   disappear.
9. Note History and Inspector use a paired two-button control: History on the
   left, Inspector on the right. Only one trailing panel is visible at a time.

### 2.3 Scholium and Triptych identity

1. Present **Scholium** as a distinctive identity in the leading sidebar.
2. Present the workspace caption in the form **Triptych — Moral Philosophy** or
   the equivalent Triptych-domain name.
3. Present **Analyses | Topics | Works** as one native segmented control.
4. Do not repeat redundant role or domain subtitles in the central title bar.
5. One window belongs to one complete Triptych. The interface does not need an
   in-document Triptych switcher.

### 2.4 Library and note hierarchy

1. The Library supports real folders with standard disclosure and visible
   hierarchy.
2. Use title as the dominant note-row information. Secondary metadata is
   compact, quiet, and role-aware.
3. Separate adjacent note rows with short, inset, hairline-gray dividers. Omit
   a custom divider only when the native grouped-list treatment supplies an
   equivalent boundary.
4. Use role-aware secondary metadata rather than one template for every vault:
   Analyses may show author and year; Topics show useful recency such as
   **12 min ago**; Works may show document kind and lifecycle state.
5. Status text is normally neutral gray. Use semantic color only for a real
   exceptional or actionable state, and never as the only cue.
6. Filters are dense, grouped, and native-looking. The preferred initial set is
   **Changed since review**, **Needs attention**, **Explicit connections**, and
   **Malformed metadata**, with a compact **Clear** action. Add another filter
   only when existing frontend-facing state supports it.
7. Search uses the canonical Product Guide scopes: **Triptych** and
   **This Note**. Quick Open remains a separate navigation command.
8. Library is the persistent base layer; Attention is a task doorway and
   lifecycle cards are transient overlays. Do not add a custom Library color,
   shadow, or floating treatment without researcher review and native-material
   testing.

### 2.5 Attention, Unclassified, Set Aside, and Trash

1. **Attention** sits beneath the Triptych segmented control. It is restrained,
   with a small symbol and subtle light-yellow boundary rather than a loud
   warning card.
2. Activating Attention opens a centered, task-scoped presentation for the
   whole window. It does not replace the Library.
   Attention is derived and recoverable; it never makes a philosophical
   judgment. It may show possible-orphan conditions, Changed Since Review,
   Broken Connections, reliance on an Unqualified Analysis, malformed
   metadata, or unresolved identity. Do not infer Superseded status, warn from
   age alone, or present automatic untraced-premise judgment. Items remain
   dismissible according to the existing Settings duration.
3. **Unclassified** is a compact, quiet row fixed near the bottom of the
   Library, above Set Aside and Trash.
4. Activating Unclassified opens a compact centered classification sheet.
   Note titles are primary; secondary origin text is smaller. The arrangement,
   destination control, and action should explain the task without tutorial
   paragraphs. Use a restrained-width, vertically scrollable sheet with dense
   rows so a large Unclassified set remains usable. Destination selection and
   confirmation remain visibly researcher-controlled.
5. **Set Aside** and **Trash** remain fixed at the bottom of the sidebar, with
   a short light divider between them and no extra heading.
6. Set Aside and Trash open as mutually exclusive compact cards that rise over
   only part of the Library. They preserve the Library as the primary layer.
7. The background Library may be blurred or dimmed to express depth, with an
   opaque Reduce Transparency alternative.
8. Lifecycle-card note rows contain only the title. Render that title in
   compact secondary-weight/color typography, left-aligned and vertically
   centered in each row.
9. A short rounded gray grabber at the top collapses the card. A back chevron
   is unnecessary.
10. Set Aside rises from its own anchor over only part of the Library and
    leaves Trash visible. Trash rises from its own anchor, closes or supersedes
    an open Set Aside card, and occupies the higher transient layer.
11. The anchored utilities and Library geometry remain stationary. Opening,
    clicking, or dismissing the cards must not make the Library shift or jitter.
12. If a lifecycle scope notice is necessary, show one compact line of
    secondary gray text without a border, tint, callout bar, or card.
13. **Set Aside** is the action and location name and asks for no reason.
    **Move to Trash** is the action; **Trash** is the location. Provide
    context-appropriate Restore, explicit permanent deletion, and Cancel paths.
    Permanent-deletion confirmation must state that related Comments, Dialogue,
    Critique association, Human Review, and checkpoint recoverability are also
    removed. These are presentation requirements over the Product Guide's
    existing behavior, not new backend semantics.

### 2.6 Document context and reading surface

1. Place the document-mode control and heading outline together immediately to
   the left of the compact Properties summary.
2. The mode control is one icon pull-down for **Read**, **Live Preview**, and
   **Source**. It is not a tab strip.
3. The mode menu layers above the document and is never hidden behind prose.
4. Treat mode, outline, and compact Properties as one centered context cluster
   whose total width equals the readable document measure. Expanded Properties
   and the main document use that same measure.
5. Properties are an independent compact element, not a full-window strip.
6. Show only useful, available, role-aware summary fields. For an Analysis,
   show **Rating**, not a generic Progress value.
   Candidate expanded Analysis fields are Source Type, Source Access, Human
   Review, Use, Reliability, Connections, Modified By, and Last Modified. Show
   only available, useful values and adapt the set by vault role; this list is
   not a schema mandate.
7. The main reading measure must be narrower than the early prototype and
   comfortable for sustained prose reading.
8. Show the actual document title. Remove generic fixture eyebrows such as
   `RESEARCH ANALYSIS, SYNTHETIC FIXTURE`.
9. The heading outline is dense, hierarchical, and easily scanned.
10. Semantic note links show a restrained type icon and provide a hover or
    keyboard-focus preview popover. Type, destination, and context remain
    legible without implying unsupported evidence.
11. This prototype does not settle Live Preview, Source, editor selection,
    syntax projection, or Markdown rendering behavior.
12. When applicable, group expanded Properties as **About**, **Source**,
    **Progress**, **Use**, and **History**. Distinguish absent, empty, invalid,
    derived, and not-applicable values. Exact YAML remains a Source-mode concern.
13. Properties visibility, order, disclosure, and human-editable allowlist are
    configured per vault, not per folder or individual note. This report
    governs their presentation only.

### 2.7 Inspector and Note History

1. Inspector and Note History share one mutually exclusive trailing region.
2. Inspector uses **Incoming | Outgoing | Research** as a native segmented
   control.
3. Inspector content uses one normal vertical scroll region and compact,
   readable sections.
4. Connections show relation type, direction, explicit or neutral status,
   destination, and exact source location in text.
5. Research content may present provenance, diagnostics, Human Review status,
   and bounded Zotero access without becoming a second dashboard.
6. Human Review must have a distinctive but restrained hierarchy. Status
   symbols align correctly, and phrases such as **Current revision** must not
   look like action buttons.
7. Note History keeps Human Review, Comments, Dialogue, Critique associations,
   and Checkpoints visually separate. Entries reopen the appropriate UI home.
8. Floating controls move with or remain outside the active trailing region;
   they never cover its header or content.

### 2.8 Open Scholia

1. **Open Scholia…** is the single shared entry point for Comments, Human
   Review, Critique, and Dialogue.
2. Analyses and Topics show **Comments & Review | Dialogue**.
3. Works show **Comments & Critique | Dialogue**.
4. These are native segmented controls within one centered role-aware panel.
5. Sharing a doorway and panel does not merge their meanings, records,
   provenance, completion, or recovery behavior.
   Opening Scholia alone creates no record or note change and defaults to the
   role-appropriate Comments segment.
6. Existing Comments appear above Review or Critique. The new whole-note
   Comment composer stays collapsed behind a compact Add Comment control.
7. During Human Review, **Review Note** is the single prominent note-level
   judgment field.
8. Qualification choices are horizontal, compact, and native. Completion
   requires **Qualified** or **Unqualified** plus a nonempty Review Note of at
   most 500 characters. Show a counter and never truncate automatically. Use
   **Complete Review**, **Save as Draft**, and **Cancel**; the visible state is
   **Review**, **Continue Review**, **Qualified**, or **Unqualified** as
   applicable.
9. Dialogue may use a selected-notes column and an instruction/context column
   at wide widths; stack them at narrow widths. The body scrolls independently.
   Included notes are grouped by vault and may support pointer and keyboard
   reordering only if the existing frontend-facing model can preserve order;
   otherwise record reordering as unresolved rather than simulating it.
   Dialogue may show Requested Destination, Comment-inclusion choices, and a
   generated instruction preview. Its actions are **Copy Instructions for
   Agent** and **Cancel**.
10. Secondary-window fields use compact typography, but not below native
    legibility or accessibility requirements. The suggested 10-point size is a
    starting preference, not an unconditional rule.
11. Actions belong with their content. Avoid a visually detached teaching
    footer.
12. Use minimal explanatory copy. Hierarchy, labels, controls, validation, and
    restrained status should guide the researcher.
13. Critique offers **Overall Critique**, **Specific Comments**, or **Both**,
    plus optional focus and prompt editing. Show authorship, target Work and
    fingerprint, materials consulted, limitations, source anchors, and response
    state. Its copy action remains **Copy Instructions for Agent**.
14. Before a Dialogue copy action, the panel may present the selected notes,
    paths, advisory fingerprints, and included Comments, and identify the
    **Before Agent Work** checkpoint required by the Product Guide. Dialogue
    history is not a restorable document version.
15. The Comments area remains the home for existing and selection-anchored
    Comments even though the whole-note composer is collapsed. Informal,
    app-owned Comments and the durable fingerprint-bound Review Note must be
    visually and verbally distinct.

### 2.9 Responsive and adaptive behavior

At narrower widths, adapt in this order:

1. shorten tab titles and secondary metadata;
2. convert **Open Scholia…** and comparable labelled controls to centered
   accessible icons;
3. collapse the trailing region before harming the reading measure;
4. hide or temporarily overlay the leading sidebar only after secondary
   content has compressed; and
5. preserve active conflict, recovery, and consequential controls.

All important layouts must work with:

- Light, Dark, and System appearance;
- Increase Contrast;
- Reduce Transparency;
- Reduce Motion;
- 100%, 150%, and 200% document scaling;
- long and localized labels;
- mixed Chinese and Latin text;
- keyboard-only use; and
- VoiceOver and Voice Control, with speakable visible names.

### 2.10 Search, Quick Open, and note commands

1. Scholium uses one shared Search field with exactly **Triptych** and
   **This Note** modes. **Triptych** searches the currently selected Analyses,
   Topics, or Works segment and preserves the query when the segment changes.
2. The standard Find command activates **This Note** in the shared Search
   field. Do not create a separate production Find field or advanced-search
   workspace merely because the HTML models an in-note Find bar.
3. Search results are retrieval leads, not evidence. Show ranked snippets,
   field or source context, and exact destination; do not make them look like
   ordinary file rows.
4. **Quick Open** / **Go to Note…** remains a separate keyboard- and
   menu-invoked centered chooser for title, path, and alias navigation. It uses
   a focused empty search field and dense keyboard-selectable results.
5. Note context menus are short and scope-sensitive. They may accelerate Open,
   Open in New Tab, Open in New Window, Reveal in Finder, opening Scholia at
   Dialogue, and lifecycle actions when those capabilities exist. Library
   notes offer Set Aside and Move to Trash; Set Aside notes offer Restore and
   Move to Trash; Trash notes offer Restore and explicit Delete Permanently.
   The menu is never the only route, and unmodeled capabilities remain
   truthfully disabled or omitted.
6. Do not retain a standalone **Create Dialogue…** workflow. A contextual
   accelerator may open the same **Open Scholia…** panel with Dialogue selected,
   but must be labelled and implemented as that same doorway.

### 2.11 Visible state, modal behavior, and recovery

1. Preserve the canonical document states: **Edited**, **Saving**, **Saved**,
   **Save Failed**, **Conflict**, **Refreshing**, **Derived State Stale**,
   **Refresh Failed**, and **Fully Up to Date**. Saving and derived refresh are
   distinct presentations.
2. Use the canonical recovery labels: **Keep Editing**, **Retry Save**,
   **Compare Changes**, **Reload from Disk**, **Return to Editing**, and
   **Retry Refresh** as applicable. Keep the current buffer open, show both
   revisions during comparison, and never make reload the default.
3. Each Library, Search, Properties, Inspector, History, and sheet surface must
   define ready, loading, empty, unavailable, malformed, stale, conflict, and
   error states appropriate to its task. One unavailable scope must not blank
   unaffected content.
4. Never borrow another note's provenance, Review, relationship, Properties, or
   History fixture when the selected note has no modeled context. Show a
   truthful neutral empty or **Not modeled** state.
5. A modal sheet closes transient menus and incompatible find/search surfaces,
   makes the underlying workspace unavailable to interaction, focuses the first
   relevant control, traps keyboard focus within the sheet, closes safely with
   Escape, and restores focus to the invoker or relevant document location.
6. At wide and ordinary widths, opening the leading sidebar reflows the
   document. At narrow widths, it may become an intentional temporary overlay
   after the responsive compression priorities have been exhausted.
7. Checkpoint discovery and chronology live in Note History. Provide
   **Create Checkpoint…** there and in the menu bar where appropriate.
   **Checkpoint Comparison** names the checkpoint and reason, labels created,
   changed, moved,
   deleted, and unchanged files, and provides selective/full recovery through a
   centered sheet. Use **Restore from Checkpoint…** and keep **Restore This
   Version** distinct from editor Undo. **Reveal Checkpoints in Finder** remains
   a menu command. Dialogue History has no restore action and no separate global
   Dialogue History.
8. A multi-note Dialogue appears in each selected note's History with its shared
   selected-note context. It remains a chronological scholarly record, not a
   restorable document version.

## 3. My bans

The following are rejected frontend patterns.

### 3.1 Scope and implementation bans

- Do not infer or change backend behavior from the prototype.
- Do not present fixture interactions as implemented product behavior.
- Do not copy HTML/CSS translucency as literal Liquid Glass.
- Do not copy synthetic counts, prose, disabled commands, numeric breakpoints,
  simulated traffic lights, shadows, blur, radii, or colors into production.
- Do not redesign editor behavior through this prototype report.
- Do not imply that agent-related UI itself grants direct-write authority.

### 3.2 Window and toolbar bans

- No monolithic full-width toolbar panel.
- No permanent Back or Forward toolbar buttons. Navigation semantics may remain
  in menus and keyboard commands.
- No duplicate ellipsis menus.
- No explicit appearance switch in the window toolbar; use the menu bar or
  Settings.
- No toolbar control that disappears merely because the window becomes narrow.
- No permanent toolbar item merely because a feature exists.
- No separate toolbar buttons for Comments, Review, Critique, and Dialogue.
- No **Source** command duplicated outside the document-mode pull-down.
- No **Find in Note** command buried in a custom overflow menu; use the menu bar
  and focused Search behavior.
- No separate production Find field: `Command-F` activates **This Note** in the
  one shared Search field.
- No **Open in New Window** command available only from a global overflow;
  place it in the note context menu and menu bar.

### 3.3 Hierarchy and content bans

- No dashboard or agent conversation competing with the document.
- No decorative stack of unrelated cards pretending to be hierarchy.
- No redundant **Folders** heading beneath **Library**.
- No redundant **LOCATIONS** heading above Set Aside and Trash.
- No redundant central subtitle such as `Works — Moral Philosophy`.
- No middle-dot separators in note metadata.
- No oversized Attention symbol or highly dominant Attention card.
- No loud or oversized Unclassified card.
- No rainbow of status colors; ordinary metadata stays quiet.
- No Topic metadata that pretends author or source count is its useful identity.
- No generic fixture eyebrow above the document.
- No overly wide prose column.
- No empty property fields displayed merely to demonstrate a schema.
- No ordinary Properties summary filled with machine IDs, schema markers, or
  citation/Zotero keys.

### 3.4 Presentation and interaction bans

- No sidebar or trailing panel that unexpectedly covers the document or its
  controls.
- No popover or menu hidden behind document content.
- No floating toolbar controls covering the Inspector header.
- No Library jitter when lifecycle cards open, close, or receive clicks.
- No Set Aside/Trash overlay that erases the Library's primary hierarchy.
- No Attention workflow that replaces the Library.
- No back chevron on the lifecycle card when a grabber expresses collapse.
- No separately styled dark HUD for the Inspector.
- No relationship graph as the only relationship interface.
- No document modes presented as open-note tabs.
- No status communicated by color, motion, spatial position, or icon alone.
- No core action reachable only through hover, drag, secondary click, or a
  custom gesture.
- No generic **Error** / **OK** response when a specific recovery action exists.
- No blanking the entire Library because one scope is loading or unavailable.
- No borrowed fixture context: a note without Properties, Review, Connections,
  provenance, or History shows an honest empty/unmodeled state.
- No detached instructional footer panel in Scholia, Attention, Unclassified,
  or similar sheets.
- No long tutorial text where the design itself can communicate the task.

### 3.5 Scholia and research-governance bans

- Do not create competing Comments, Review, Critique, or Dialogue sheets.
- Do not retain standalone **Create Dialogue…** UI that creates a parallel
  doorway; contextual access opens Scholia with Dialogue selected.
- Do not present a permanently expanded whole-note Comment box beside a Review
  Note.
- Do not imply that Dialogue is a document version.
- Do not imply that Critique is Human Review.
- Do not give Works a Qualified or Unqualified state through Critique.
- Do not merge comment, Review, Critique, Dialogue, History, or Checkpoint
  records merely because they share one panel.
- Do not foreground technical prompts, model parameters, token counts, hidden
  instructions, or file-operation logs as the scholarly record.
- Do not automatically transmit research content through opening Scholia.

## 4. What to do

### Priority 0 — Preserve hierarchy and interaction continuity

1. Implement the document-first shell with optional leading and trailing
   regions.
2. Make sidebar and trailing-panel transitions reflow and recenter the document.
3. Establish correct overlay and z-order behavior for menus, popovers, sheets,
   lifecycle cards, and the trailing panel.
4. Eliminate Library jitter and prevent controls from covering panel headers.
5. Preserve one clear focus path when surfaces open or close.

### Priority 1 — Establish native macOS controls and UI homes

1. Replace simulated HTML chrome with native macOS 26 controls.
2. Build the bounded open-note strip, adjacent Search, Open Scholia entry, and
   paired History/Inspector controls in the toolbar layer.
3. Build the mode/outline/Properties context row on the same measure as the
   document.
4. Build the Library as real hierarchical navigation with fixed Unclassified,
   Set Aside, and Trash locations.
5. Build Attention, classification, Scholia, and recovery work as native
   sheets or panels appropriate to their scope.
6. Replace the prototype's stale Search/Find split with the canonical one-field
   Search contract while keeping Quick Open separate.
7. Add truthful empty/loading/error states and canonical conflict/recovery
   labels before polishing materials.

### Priority 1 — Consolidate Scholia without collapsing meanings

1. Use the role-aware segmented composition specified above.
2. Keep existing Comments visible and the new whole-note composer collapsed.
3. Keep Human Review or Critique visually primary in the formal segment.
4. Keep Dialogue selected-note context and instructions separate from formal
   Review/Critique controls.
5. Keep History destinations and provenance distinctions explicit.

### Priority 2 — Enforce the settled Comment and Review distinction

Whole-note Comments remain informal, app-owned, threaded or revisable
discussion. Review Note is the durable fingerprint-bound qualification
rationale. Keep existing Comments visible and keep the whole-note composer
collapsed behind Add Comment so the two roles never appear as equally
prominent, indistinguishable text boxes. The existence of whole-note Comments
is settled; richer preservation and reflection modes remain future work.

### Priority 2 — Complete responsive and accessibility acceptance

1. Define wide, ordinary, narrow, and minimum-window states semantically rather
   than copying the HTML breakpoints.
2. Verify icon conversion, tab shortening, panel collapse, text measure, and
   action persistence at every state.
3. Verify keyboard, focus restoration, VoiceOver order, appearance,
   transparency, contrast, motion, scaling, localization, and mixed-script use.
4. Verify Voice Control with speakable visible names, safe Escape behavior, and
   focus restoration after Quick Open, Scholia, conflict, checkpoint, and
   History presentations.

## 5. How to do it

### 5.1 Choose the UI home by scope and frequency

| UI home | Use it for |
| --- | --- |
| **Menu bar** | Complete command access; Back/Forward; Find; appearance and Settings; New/Open Triptych; New Window; checkpoint and infrequent commands. |
| **Toolbar** | Bounded open-note tabs, adjacent activation for the one shared Search field, **Open Scholia…**, and paired History/Inspector controls. |
| **Document context row** | Mode pull-down, heading outline, compact Properties, and persistent document-local lifecycle or conflict presentation. |
| **Sidebar or content list** | Triptych scope, folders, queues, locations, notes, and search results. |
| **Inspector or Note History** | Persistent selected-note context and chronological records. |
| **Popover or pull-down** | Mode, outline, filters, link preview, and other compact transient choices. |
| **Centered sheet or panel** | Quick Open, Attention, Unclassified classification, Scholia, conflict comparison, and checkpoint recovery. |
| **Context menu** | A short set of accelerators for the clicked note; never the only route to a core command. |

Before adding chrome, try to consolidate the capability with an existing home.
Add a new column, window, sheet, popover, inspector section, or menu command
only when the task has a genuinely different scope.

### 5.2 Map the prototype to native macOS

- Use `NavigationSplitView` or tested AppKit split-view primitives for the
  leading/document/trailing structure.
- Use a native toolbar and toolbar groups for frequent document-local controls.
- Use a native segmented `Picker` or AppKit segmented control for
  Analyses/Topics/Works, Inspector modes, and Scholia modes.
- Use a native `Menu` or pull-down control for Read/Live Preview/Source.
- Use native lists or outline views for folders and dense note rows.
- Use the native inspector when it supplies correct trailing-panel behavior;
  use tested AppKit coordination when it does not.
- Use popovers for compact outline, filter, and link-preview content.
- Use one expanding/focused Search field for Triptych and This Note. Use a
  separate centered chooser for Quick Open.
- Use sheets or centered panels for bounded consequential workflows.
- Use `Commands`, the responder chain, and menu validation for complete
  keyboard-discoverable command access.

Use AppKit where it supplies more reliable Mac behavior for bounded tabs,
window restoration, split resizing, dense outline/list presentation, focus, or
accessibility. Do not force every surface through one framework.

### 5.3 Apply Liquid Glass correctly

1. Let native macOS controls and containers supply Liquid Glass.
2. Use glass primarily for toolbar, navigation, sidebar, inspector, popover,
   sheet, and control layers.
3. Keep prose, source, Properties details, diagnostics, diffs, and dense lists
   on opaque semantic content surfaces. A sidebar navigation container may use
   material while its dense rows remain calm and legible.
4. Use custom glass APIs only after standard components are insufficient and
   only when the selected SDK supports them.
5. Under Reduce Transparency, replace blur/material depth with opaque semantic
   backgrounds and clear boundaries.
6. Under Increase Contrast, strengthen boundaries and state without creating a
   new color system.
7. Use dynamic semantic colors and the system accent. Target at least 4.5:1
   contrast for ordinary small text and 3:1 for large or bold text. Do not make
   a custom target smaller than 20 by 20 points, and audit every important
   custom target below 28 by 28 points.

### 5.4 Preserve focus, semantics, and adaptation

- Give every icon-only button a full accessible name and concise help text.
- Expose selected, pressed, expanded, disabled, and current values truthfully.
- Restore focus to the invoking control or relevant document location after a
  sheet or popover closes.
- Keep list selection visible when document or inspector focus changes.
- Do not let refreshes move keyboard focus or VoiceOver unexpectedly.
- Provide keyboard and menu equivalents for hover previews, drag, and context
  actions.
- Use system typography and semantic colors in application chrome.
- Pair status color with text and a symbol, shape, or accessible value.
- Pair unfamiliar research, provenance, relationship, or agent symbols with
  visible text until the symbol is independently clear.
- Escape safely cancels a modal task when appropriate, without discarding work
  that the surface has promised to preserve.

### 5.5 Keep prototype-only behavior honest

The HTML intentionally does not model real file loading, real mutation,
editor mechanics, persistence, new windows, Finder integration, or complete
History for every fixture. Disabled or prototype-only controls are evidence of
scope, not product bans.

In production:

- omit an unavailable capability or show it truthfully disabled;
- bind frontend surfaces only to existing frontend-facing state and actions;
- never generate fake completion, save, classification, or agent activity; and
- record any missing product/backend dependency rather than simulating it.

## 6. Required departures from the current HTML

The current prototype contains several deliberate approximations or stale
labels. Native implementation must not copy them as target behavior:

1. The HTML Search popover shows **This Vault | Triptych**. The target contract
   is one shared field with **Triptych | This Note**. Triptych searches the
   selected Analyses, Topics, or Works segment.
2. The HTML models a separate in-note Find bar. The target standard Find command
   activates **This Note** in the shared Search field.
3. The HTML conflict strip says **Reload**, **Compare**, and **Cancel**. Use the
   canonical labels **Reload from Disk**, **Compare Changes**, and **Keep
   Editing**, plus the other state-specific labels in Section 2.11.
4. The HTML open-note strip uses three static examples without close or overflow
   behavior. Native tabs require close, overflow, state, keyboard cycling, and
   restoration.
5. The HTML note context menu contains **Create Dialogue…**. Native contextual
   access opens the one Scholia panel with Dialogue selected and does not create
   a parallel workflow surface.
6. The HTML truthfully disables unmodeled New Tab, New Window, Finder, and
   restore behavior. Disabled fixture commands are not product bans; implement
   them only when their existing contracts are reachable.
7. Only selected fixtures contain complete Properties, Inspector, and History
   data. Other notes must show neutral empty/unmodeled states, never borrowed
   context from the detailed fixture.
8. The HTML's visual blur, fixed breakpoints, colors, typography measurements,
   and simulated window chrome remain prototype devices rather than native
   implementation specifications.

## 7. Flexible decisions

Future designers and agents may adjust the following with a documented reason:

- exact widths, breakpoints, spacing, radii, blur, shadows, material intensity,
  animation curves, and icon choices;
- exact readable-column maximum width, provided it remains comfortable and
  aligned with context chrome;
- exact lifecycle-card height and coverage fraction;
- exact density of note rows and secondary metadata;
- exact status palette, provided semantic states remain redundant and calm;
- exact internal grouping of Scholia and Inspector content;
- whether a broad scope needs a separate content-list column at wide widths;
- whether a new function belongs in a new window, sheet, popover, inspector
  section, menu command, or additional native column; and
- alternate native control choices when testing shows they better serve the
  researcher task.

Move or add an element only when:

1. a real researcher task lacks a coherent UI home;
2. the new placement preserves the document-first hierarchy;
3. semantic distinctions remain visible;
4. wide and narrow states remain usable;
5. keyboard and accessibility routes remain complete; and
6. the reason and verification are recorded.

## 8. Prototype anchors

Use these regions as orientation, not immutable line contracts:

| Prototype area | Approximate source location |
| --- | --- |
| Window shell, tabs, Search, and Open Scholia | lines 3774–3838 |
| Sidebar, folders, and lifecycle hierarchy | lines 3842–3916 |
| Document mode, outline, and Properties | lines 3919–3970 |
| Semantic link preview | around line 4002 |
| Inspector and Note History | lines 4018–4163 |
| Attention and Scholia panels | lines 4176–4315 |
| Collapsed whole-note Comment composer | around line 4230 |
| Checkpoint creation and comparison | lines 4324–4362 |
| Unclassified and Quick Open sheets | lines 4364–4393 |
| Scope-sensitive note context menu | lines 4396–4405 and 5887–5916 |
| In-note Find fixture | lines 3973–3984 and 5316–5393 |
| Modal focus and inert-background behavior | lines 5563–5675 |
| Responsive and reduced-transparency rules | lines 3533–3760 |

Line numbers may move as the prototype evolves. Prefer element IDs, semantic
roles, and visible behavior when reviewing a later version.

## 9. Frontend acceptance checklist

Before accepting a native implementation or major prototype revision, verify:

- the document remains the dominant and optically centered object;
- sidebar and trailing-panel transitions reflow without overlap or jitter;
- tab, mode, navigation history, Triptych scope, and Inspector modes remain
  conceptually distinct;
- each capability has one intentional primary UI home;
- Open Scholia remains the single prominent doorway;
- Comments, Review, Critique, Dialogue, and History remain semantically
  distinct;
- the one Search field exposes only Triptych and This Note, standard Find
  activates This Note, and Quick Open remains a separate chooser;
- tabs expose close, overflow, dirty/conflict state, accessible names, keyboard
  cycling, and presentation restoration;
- Properties and document context align to the readable measure;
- menus, popovers, sheets, and panels layer above the correct surface;
- modal sheets isolate interaction, trap focus, cancel safely, and restore focus;
- lifecycle cards preserve their exact overlay hierarchy and do not shift the
  Library or anchored utilities;
- document and derived-state labels/actions match the canonical interface
  contract, including Compare Changes, Reload from Disk, and Keep Editing;
- empty or unmodeled notes never display borrowed fixture context;
- narrow layouts preserve consequential actions;
- no prototype fixture is mistaken for real implementation evidence;
- no frontend decision creates or changes a backend contract;
- native Liquid Glass is used for navigation and controls rather than copied
  from HTML effects;
- Light/Dark, contrast, transparency, motion, scaling, localization, keyboard,
  and VoiceOver states remain usable; and
- any departure from the preferred prototype is explained by a concrete
  researcher task and verified with nonprivate fixtures.
