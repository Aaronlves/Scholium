# Scholium Design Handbook

**Status:** Authoritative interface-design language and stable interface decisions

**Applies to:** Scholium for macOS 26 and later

**Last reviewed:** 2026-07-14

Scholium is a local-first macOS research workbench for sustained humanities research. This handbook defines how Scholium should feel, organize information, communicate authority, and support human–agent work. It guides design, implementation, review, and visual QA. It does not replace target product behavior in `PRODUCT_GUIDE.md`, release-oriented requirements synthesis in `PRD.md`, current implementation status in `IMPLEMENTATION_STATUS.md`, setup information in `README.md`, or Apple documentation.

**Rule status:** These rules are binding for Scholium’s user-facing interface, interaction behavior, accessibility, visual presentation, and design review. Future work must comply with them unless the researcher explicitly approves a documented exception. A stable rule changes only through an intentional edit to this handbook and, when applicable, the decision record. Current code that diverges from a rule is implementation debt, not an alternative design authority.

**Scope boundary:** This handbook may name existing application state only to
specify how the interface presents it. It does not define repository,
persistence, filesystem coordination, indexing, schema, CLI or API, or agent
execution contracts. A layout or interaction decision recorded here does not
create new backend behavior.

## 1. Authority and terminology

Use these categories when proposing or reviewing an interface decision:

- **Apple HIG guidance** means a rule supplied by the authoritative local `apple-hig` skill.
- **Apple API documentation** means implementation behavior or availability verified in the selected Xcode installation's Developer Documentation, SDK, and compiler.
- **Platform convention** means behavior conventionally supplied by macOS, SwiftUI, AppKit, WebKit, or the responder chain.
- **Scholium decision** means a product-specific choice arising from Scholium’s research-integrity and workflow model.
- **Current implementation** describes reachable behavior in the present source tree. It is evidence, not automatically a permanent design decision.
- **Future or unresolved** identifies a planned capability or a decision that still requires testing or product judgment.

Authority is divided deliberately:

1. `PRODUCT_GUIDE.md` owns target product role, Triptych workflows, terminology, and feature boundaries.
2. This handbook owns stable interface structure, visual language, interaction principles, accessibility, and recorded design decisions. Within it, Section 10 is the canonical contract for exact target user-visible state meanings and action labels, including save, conflict, refresh, Dialogue, Critique, checkpoint, and restore actions.
3. `PRD.md` synthesizes the Product Guide and this handbook into release-oriented requirements, gates, risks, and traceability; it does not override either authority.
4. `IMPLEMENTATION_STATUS.md` maps current behavior to the target and design authorities; it does not redefine them.
5. The project `README.md`, live construction call sites, executable tests, and scripts establish current implementation status.
6. The repository `HANDBOOK.md` is only a concise entry point and authority map.

`apple-hig` is the authoritative local reference for Apple Human Interface Guidelines. It owns HIG rules, measurements, patterns, components, and platform distinctions; this handbook applies that guidance to Scholium without duplicating it. The selected Xcode installation's Developer Documentation, SDK, and compiler remain authoritative for implementation-facing API behavior and availability. Apple guidance does not define Scholium's research model.

If a stable Scholium decision conflicts with `apple-hig`, record the conflict explicitly and obtain researcher approval for a documented exception or handbook change. Do not restate the HIG rule to make the conflict disappear.

Do not claim that Apple prescribes Scholium’s Triptych, evidence hierarchy, relationship semantics, Dialogue, Critique, Review, or governance model. Those are Scholium decisions.

### 1.1 Prototype and layout baseline

`Docs/Prototypes/triptych-document-layout.html` is the researcher-approved
preferred reference for Scholium's main-window composition and page logic. In
particular, its current Scholia composition around line 4230 records the
decision to keep existing whole-note Comments visible while collapsing the new
Comment composer so that formal Review or Critique remains primary.

The prototype is a strong design reference, not a frozen specification:

- Use it to reason about hierarchy, placement, density, panel transitions,
  responsive priority, and the relationship among navigation, document, and
  contextual work.
- Do not treat its pixels, CSS, breakpoints, fixture data, disabled commands,
  simulated controls, or temporary interactions as product requirements or
  evidence that a feature is implemented.
- It governs frontend composition only. It does not define Markdown editing or
  rendering mechanics, autosave, repositories, persistence, indexing, schema,
  filesystem coordination, CLI/API behavior, or agent execution.
- Future designers and agents may add, consolidate, move, or replace UI
  elements when a real researcher task needs a better home. Preserve the
  document-first hierarchy and the semantic distinctions in this handbook,
  and record the reason for a material departure from the preferred baseline.
- If the prototype conflicts with `PRODUCT_GUIDE.md`, Section 10, source
  fidelity, accessibility, or current Apple guidance, those authorities take
  precedence.

## 2. Design mission and target researcher

Scholium helps a researcher sustain an argument across sources, topic synthesis, governed commitments, and authored prose without losing the origin or status of an idea.

The target researcher:

- works primarily with long-form Markdown and may migrate from or interoperate with Obsidian, Zotero, PDFs, and agent tools; none of these integrations is required for the core academic workflow;
- needs to distinguish sources, interpretation, personal analysis, provisional synthesis, and finished prose;
- works across independently located vaults and may organize many bodies of writing with ordinary Works folders;
- may be writing a dissertation now but will continue producing papers, books, teaching material, or other humanities research;
- expects precise keyboard and pointer behavior, resizable windows, selectable text, and durable state;
- may work in English, Chinese, mixed scripts, or another language;
- values source fidelity and recoverability more than visual novelty.

The primary actor is the **researcher**. Under the Product Guide, the
researcher may optionally instruct an external agent to inspect and directly
edit Triptych files. Scholium makes comments, paths, fingerprints, checkpoints,
conflicts, provenance, and recovery legible without becoming an agent chat or
task manager. Obsidian and Zotero are optional interoperability, not
prerequisites: the core academic workflow must be completable in Scholium
without them installed.

## 3. Core design principles

### 3.1 Research document first

**Scholium decision.** The document is the largest and most stable region of the main window. Navigation, properties, relations, diagnostics, and agent assistance remain subordinate to reading and writing.

- Preserve readable line length and a calm, opaque document surface.
- Do not make the researcher cross a dashboard before opening a note.
- Do not let indexing, graph activity, or agent features cover routine reading and editing.
- At constrained widths, preserve the document before the inspector or secondary navigation.

### 3.2 Trustworthy and local first

**Scholium decision, informed by Apple privacy guidance.** Local files and their exact revisions are authoritative. Ask for filesystem or network access only at the point of use and explain what will be accessed.

- Keep app-generated state outside research vaults.
- Do not transmit note content, citations, claims, paths, or review feedback without an explicit contextual action.
- Show the target vault and note before a consequential operation.
- Never imply that an index, cached render, graph, or agent output is authoritative source content.

### 3.3 Source fidelity and reversibility

**Scholium decision.** Every presentation is a reversible projection of one authoritative Markdown source.

- Read, Live Preview, and Source must not silently normalize or regenerate Markdown.
- Preserve selection, focus, scroll position, and the nearest semantic location across mode changes where possible.
- Route Scholium-authored writes and version restoration through the same conflict-aware repository. Treat direct agent writes as concurrent filesystem changes requiring a fresh read and explicit conflict handling.
- Keep editor undo distinct from version restoration.
- Show failures without discarding the current buffer or typed property value.

### 3.4 Explicit provenance, uncertainty, conflict, and authorship

**Scholium decision, informed by Apple guidance for generative AI and machine learning.** Every derived or generated result must disclose what it is, where it came from, and what remains uncertain.

- Label agent authorship before agent-generated content.
- Show source anchors and resolution status for links, diagnostics, and relationships.
- Mark inferred, ambiguous, broken, stale, or unverified states in text, not color alone.
- Treat search results as retrieval leads, not evidence.
- Treat untyped and transitive graph paths as neutral connections.

### 3.5 Human control over consequential changes

**Scholium decision.** Researchers decide whether to use an agent, what to ask
an agent to do, and remain responsible for the scope of that instruction.

- Dialogue records the scholarly interaction and may generate transient
  copyable instructions; it does not transmit research automatically or
  maintain hidden permissions.
- Show selected notes, exact paths, comments, and advisory fingerprints before copying agent instructions.
- Create the automatic **Before Agent Work** checkpoint defined by the Product Guide, while keeping manual checkpoints available.
- Treat direct agent edits as external filesystem changes. Refresh clean notes and preserve dirty buffers through conflict recovery.
- Preserve a complete non-agent path for reading, editing, Review, comments,
  checkpoints, recovery, and research judgment. Critique and Dialogue remain
  optional extensions.

### 3.6 Calm native macOS behavior

**Apple guidance and platform convention, interpreted for Scholium.** Prefer familiar Mac structure and standard controls over branded chrome.

- Use native windows, split views, inspectors, toolbars, menus, sheets, alerts, controls, selection, focus, and file panels.
- Keep modality brief and task-scoped.
- Let standard controls adopt the current macOS appearance and Liquid Glass. Do not preserve obsolete custom chrome merely for compatibility with pre-macOS 26 systems.
- Use motion only to clarify continuity. Never delay interaction for decoration.

## 4. Information architecture

### 4.1 Workspace and vaults

**Scholium decision.** A Scholium Triptych contains exactly three independently located research roots: **Analyses**, **Topics**, and **Works**. There is no fourth vault or All Notes mode. The recommended fields for the three vaults are defined in `PROPERTY_PROFILES.md`; they do not migrate or replace existing YAML.

- Recommend sibling folders for portability, but do not require relocation into one parent.
- Keep each vault’s identity, access bookmark, review state, versions, and derived indexes distinct.
- Show human-readable vault names and roles; reveal filesystem paths only where location is actionable.
- Do not present the dissertation as the universal model. Use general research language in shared app chrome.
- Let the researcher register several complete Triptychs for substantially different domains. Keep one Triptych per window; open another Triptych in another window rather than adding an in-document Triptych selector.

### 4.2 Main window

The ordinary hierarchy is:

1. **Navigation sidebar:** workspace scope, vault choice, search, attention queues, hierarchy, and filters.
2. **Content list when necessary:** notes or results within a broad selected scope. Do not add a column when the sidebar already contains the complete shallow list.
3. **Document detail:** header, properties, reader/editor, and document-local commands.
4. **Trailing research inspector:** contextual incoming/outgoing Connections, Zotero source identity, document-local Attention, and source-located diagnostics.

**Platform convention.** Prefer `NavigationSplitView` and the native inspector when they supply correct resizing and restoration. Use AppKit split primitives only when tested behavior requires them.

- The sidebar is hideable and bounded to a useful width.
- The inspector is trailing, hideable, resizable, and state-restoring.
- At narrow widths, hide the inspector before shrinking the document below a usable reading width.
- Do not add blank strips or fixed spacers merely to align unrelated chrome.
- Windows receive independent view state, a persisted selected Triptych identity, and focused-window commands. Repositories, identity and workspace registries, indexes, and watchers are shared by vault identity rather than recreated by each window.
- Keep tabs, navigation history, selection, document mode, search, inspector mode, scroll position, Dialogue/History presentation, and Canvas selection in a per-window session model. Route commands to the focused window or document.
- At ordinary widths, prefer the prototype's triptych composition: a bounded
  leading navigation sidebar, a dominant centered document, and one optional
  trailing contextual region. A separate note-list column remains appropriate
  when a broad scope or result set genuinely needs it; the prototype's empty
  space does not prohibit another useful native column.
- Opening or closing a sidebar or trailing panel reflows the available content
  and keeps the readable document column centered within the remaining
  document region. Contextual panels must not unexpectedly cover document
  commands or leave the prose aligned to a vanished panel.

### 4.3 Sidebar and search

The sidebar contains broad peer-level scopes and genuine hierarchy, not a stack of decorative cards.

- Use disclosure only for real folder or research hierarchy.
- Keep search scope and active filters explicit.
- Search results show ranked snippets and source context; they do not become ordinary alphabetized file rows.
- Keep global/workspace search, Quick Open, and in-note Find conceptually and visually distinct.
- Preserve selection when focus moves to the editor or inspector.
- Provide loading, zero-result, malformed, conflict, and inaccessible-vault states without blanking the whole library.
- Prefer the prototype's leading hierarchy: Scholium and Triptych identity;
  the **Analyses | Topics | Works** segmented scope; restrained Attention;
  genuine folders and note rows; a compact **Unclassified** destination above
  the location utilities; and **Set Aside** and **Trash** anchored at the
  bottom. These are levels of one navigation system, not peer decorative
  cards.
- Attention opens a task-scoped centered presentation when the queue needs
  sustained judgment rather than replacing the Library. Set Aside and Trash
  may open as mutually exclusive compact upward cards over part of the Library,
  with a clear depth relationship and without shifting or jittering the list.
  The final native implementation must preserve keyboard, VoiceOver, Reduce
  Transparency, and non-motion alternatives.

### 4.4 Document area and modes

Read, Live Preview, and Source are **modes of one document**, not tabs or separate files.

- **Read** presents selectable, semantic prose, links, callouts, tables, code, and footnotes.
- **Live Preview** edits the exact Markdown body through a visual projection and reveals syntax around the active construct. It hides YAML frontmatter and line-number gutters.
- **Source** exposes the complete Markdown and YAML as text and may show line numbers.

The current implementation uses CodeMirror 6 for Source and Live Preview and a sanitized WKWebView for Read, with a native fallback. This is a Scholium implementation decision, not an Apple prescription. These surfaces must still meet native expectations for selection, marked-text composition, undo, Find, focus, keyboard access, services, accessibility, and large-document performance.

Prefer one compact, single-icon pull-down for Read, Live Preview, and Source in
the document command area. An alternate native presentation requires a clear
usability reason. Do not make the modes resemble open-document tabs.

### 4.5 Navigation, history, and tabs

Keep these models separate:

- **Back/Forward** traverses visited locations.
- **Search and Quick Open** jump to a target.
- **Recent Notes** returns to the current window's most recently visited,
  vault-qualified notes through **Navigate → Recent Notes**. It is a bounded
  MRU command, not Back/Forward history, a tab list, Search, Quick Open, or a
  permanent sidebar or toolbar surface.
- **Open in New Window** supports parallel work. Per-window session state and shared workspace services are implemented; sustained interactive acceptance remains pending.
- **Native window tabs** are user-controlled window grouping.
- **In-window document tabs** are a deliberately bounded workspace aid.

If in-window tabs remain, show a recognizable document identity. Author and year may supplement the title but must not be the only identity when ambiguity is possible. Provide a visible selected state, close command, overflow route, accessible full name, conflict/dirty state, keyboard cycling, and per-tab presentation restoration. Autosave or surface an exact conflict; do not block switching with a vague “save or cancel” message.

At ordinary widths, place the bounded open-note strip in the central toolbar
band, with scoped Search adjacent. Tabs share the toolbar's vertical rhythm,
shorten gracefully, and move excess documents into a native overflow route.
Back and Forward remain distinct navigation commands but do not require
permanent toolbar buttons; menu and keyboard access may be the calmer home.

### 4.6 Document header and properties

The document header is a restrained recognition surface above the body. Show only meaningful available values, such as title, author, year, research type, lifecycle or review state, cluster/folder context, and malformed/conflict status.

- Put properties below document commands and above the body.
- Use one collapsible property region; do not show empty fields to prove a schema exists.
- Group researcher-facing properties as **About**, **Source**, **Progress**, **Use**, and **History** when applicable.
- Reuse the canonical Triptych keys for recurring concepts across Analyses, Topics, and Works; interpret controlled values through the assigned vault role.
- Keep machine IDs, schema markers, and citation/Zotero keys preserved in source but out of the ordinary summary.
- Distinguish absent, empty, invalid, derived, and not-applicable values.
- Use Source mode for exact YAML and structured controls only for targeted changes.
- Prefer a compact context row whose mode and heading-outline controls sit
  immediately before the property summary. The complete row, expanded
  property details, and prose column align to one centered readable measure;
  properties do not span the full window merely because space is available.

### 4.7 Research inspector

The inspector follows the selected note. Its stable top-level modes are **Incoming**, **Outgoing**, and **Research**.

- Use clear section headings, counts, disclosures, and one normal vertical scroll region.
- Show predicate, direction, explicit/inferred status, resolution status, target identity, and source anchor in text.
- Put decision-relevant content first and collapse empty secondary sections.
- Every result opens the exact note and source location through pointer, keyboard, menu, and accessibility action.
- Do not use a separately styled dark HUD or a graph as the only relationship interface.
- Research may show document-local Attention only for the categories defined by the Product Guide. Every item is dismissible, names its derived status, and opens its source line when one exists. Dismissal duration is a Triptych-local setting and defaults to seven days.
- Inspector and Note History share one trailing contextual region and are
  mutually exclusive at the top level. A paired control may switch between
  them, with History on the left and Inspector on the right. The active panel
  slides or appears from the trailing edge, moves its control with it, and
  reflows the document instead of covering the panel header or prose.

### 4.8 Review, Dialogue, Critique, and recovery

**Human Review** records the researcher’s fingerprint-bound assessment and
qualification of an Analysis or Topic. **Dialogue** records concise scholarly
Comments and Responses and may package selected-note context into transient
copyable instructions. **Critique** is an optional attributed agent assessment
of one Work and remains separate from Work prose.

- Use **Open Scholia…** as the single prominent document-local doorway for
  Comments, Human Review or Critique, and Dialogue. Opening it presents one
  role-aware Scholia panel rather than several competing sheets or toolbar
  actions.
- For Analyses and Topics, the Scholia segmented control is **Comments &
  Review** and **Dialogue**. For Works, it is **Comments & Critique** and
  **Dialogue**. Default to the first segment and retain the selected segment
  for the current window session.
- Sharing a panel is a presentation decision only. Comment records, Review
  qualification and notes, Critique requests and responses, Dialogue records,
  checkpoints, and Note History entries retain separate eligibility,
  provenance, completion, and recovery behavior.
- Keep whole-note Comments subordinate to the formal Review or Critique task.
  Show existing Comments normally, but keep the new whole-note Comment composer
  collapsed behind a compact add-Comment control until the researcher invokes
  it. A **Review Note** remains the single prominent note-level judgment field
  during Human Review.
- Use the exact target actions and meanings in Section 10.
- Keep Human Review, Dialogue entries, Critique associations, and checkpoint versions visibly distinct in Note History.
- Let the researcher select one or several notes and provide one overall
  Dialogue Comment or instruction without forcing predefined task types.
- Keep prompt templates and assembled technical instructions out of Dialogue,
  Critique, and future research-workflow surfaces. These surfaces show the
  selected research context and scholarly inputs but no template body,
  placeholder list, preview, picker, or one-run prompt editor.
- Use restrained text actions to open **Settings → Research Guidance** at the
  applicable template. Preserve the workflow's selected notes, Comments,
  scope, and keyboard focus path while the Settings window is open.
- Show Critique authorship, target, target fingerprint, materials consulted, limitations, and source anchors before the body.
- Do not imply that a Dialogue entry is a document version or that a Critique judgment is Human Review qualification.
- Do not require technical prompts, hidden instructions, model parameters, or
  paragraph-level AI provenance in the scholarly Dialogue record.
- When an agent changes notes, foreground a concise academic change summary;
  routine file-operation details remain secondary.
- Keep checkpoint comparison keyboard navigable and label created, changed, moved, and deleted files in text rather than color alone.

For save and conflict recovery, preserve these exact distinctions:

| State | Meaning | Required action language |
| --- | --- | --- |
| **Edited** | The in-memory source differs from its committed fingerprint. | Use standard edited state only when it accurately represents this condition. |
| **Saving** | The repository is validating, snapshotting, and attempting the atomic write. | Show quiet document-local progress. |
| **Save Failed** | No authoritative commit returned; the buffer remains uncommitted. | **Retry Save** when retry is meaningful; **Keep Editing** always. |
| **Conflict** | Disk no longer matches the expected revision, so the write was rejected. | **Compare Changes**, **Reload from Disk**, **Keep Editing** when comparison exists. |
| **Saved** | Validation, snapshot, atomic write, and authoritative document update completed. | Quiet document-local confirmation; no routine alert. |
| **Refreshing** | Derived consumers are catching up to an already saved revision. | Name the affected derived scope when useful. |
| **Derived State Stale** | A derived consumer is known to represent an older committed revision. | Keep the affected scope and revision visible until recovery. |
| **Refresh Failed** | Source saved, but a derived consumer failed. | **Retry Refresh**; do not imply that source saving failed. |
| **Fully Up to Date** | Source and all derived consumers represent one committed revision. | Use only when convergence is useful to communicate; it is not the meaning of **Saved**. |

Conflict comparison uses **Return to Editing** and **Reload from Disk** and keeps both revision identities visible. Version history uses **Restore This Version** through the normal conflict-aware transaction. `Command-Z` remains editor undo and never means version restore.

### 4.9 Settings, onboarding, errors, and help

- Open global settings with `Command-,` and use stable panes for the Triptych vaults, document styles, Zotero, Properties, and other genuine app-wide settings.
- Use **Research Guidance** as the sole pane for managing prompt templates and
  skills. Present two stable collections, **Prompt Templates** and **Skills**,
  in one navigable list-and-detail structure with one native multiline editor.
  Do not collapse a workflow template and a reusable skill into the same item
  type.
- Let a workflow deep-link to its exact template in **Research Guidance**.
  Built-in templates may be customized and reset; researcher-created templates
  may be created, duplicated, renamed, deleted, and assigned to a workflow.
  Inline validation reports structural problems only and never judges
  philosophical quality.
- In **Skills**, distinguish **Bundled** from **Triptych** in text. Show only
  bundled skills and user packages discovered at
  `.scholium/skills/<skill-id>/SKILL.md`. Let the researcher edit Triptych-local
  `SKILL.md` source directly, duplicate a bundled skill, rename or delete a
  Triptych-local skill, reset a customized bundled skill, and use **Reveal
  Skills Folder** to open the supported location. Keep invalid packages visible
  with an inline structural error and never imply that validation certifies
  philosophical accuracy or methodological quality.
- Skill management does not add a skill picker, skill source, or one-run skill
  override to Dialogue, Critique, or another research workflow. Any future
  workflow binding requires a separate approved product decision.
- Use **New Triptych…**, **Open Triptych**, **New Window**, and **Manage Triptychs…** consistently. Settings lists complete Triptychs and edits the selected Triptych’s three roots; it never presents Works folders as projects.
- Keep task-specific settings near their task, except prompt-template mechanics,
  which remain centralized in **Research Guidance** under decision D-028.
- First launch explains local-first behavior, vault access, generated-state location, and the agent boundary, then gets the researcher to usable folders quickly. After Works is chosen, use a standard Open panel for the one-time authorization of its containing folder so the sibling `.scholium/` directory remains reachable in the sandbox; explain that this is not a fourth vault.
- Use standard Open panels for vault and import selection. The 0.1 target has
  no export workflow requiring a Save panel; document, HTML, PDF, and DOCX
  export are deferred future capabilities rather than permanent boundaries.
- Put recoverable errors beside the affected object. Reserve alerts for uncommon, critical decisions.
- Use specific titles and recovery actions such as **Choose Another Vault**, **Retry Indexing**, or **Compare Changes**. Do not use a generic **Error** / **OK** pair when the app knows the affected operation.
- Keep onboarding contextual and optional after initial vault assignment. Do not require a feature tour.

### 4.10 Preferred composition and UI homes

**Scholium decision.** The prototype establishes the preferred topology at
ordinary window sizes, while native macOS scope and frequency determine where
each capability belongs. Every reachable frontend capability needs one
intentional primary home:

| UI home | Appropriate content |
| --- | --- |
| **Menu bar** | Complete command access, keyboard discovery, and infrequent app-, window-, or document-level actions. |
| **Toolbar** | A small number of frequent actions for the focused window or document, including the bounded open-note strip, Search, **Open Scholia…**, and paired History/Inspector controls when applicable. |
| **Document context row** | Document mode, heading outline, compact role-aware Properties, and persistent document-local lifecycle or conflict state. |
| **Sidebar or content list** | Triptych scope, folders, queues, locations, notes, and result navigation. |
| **Inspector or Note History** | Persistent context for the selected note, including Connections, Research information, diagnostics, provenance, and chronological records. |
| **Popover or pull-down** | Compact transient selection, search, filtering, or a short command choice that does not require a multi-step decision. |
| **Sheet or centered panel** | Bounded, consequential, or multi-step work such as Attention triage, classification, Scholia, conflict comparison, and checkpoint recovery. |
| **Context menu** | A short accelerator set for the clicked object; never the sole route to a core action. |

Before adding permanent chrome, consolidate with an existing home or explain
why the new task has a different scope. A feature does not earn a toolbar
button merely because it exists. Conversely, the prototype is not an
exhaustive feature inventory: a new capability may justify a native column,
window, sheet, popover, inspector section, or menu command when that placement
keeps the document primary and makes the task clearer.

Preferred ordinary-width composition:

- the leading sidebar contains Triptych identity, role scope, Attention,
  folder hierarchy, Unclassified, Set Aside, and Trash;
- the central toolbar contains bounded open-note tabs with Search adjacent and
  one prominent **Open Scholia…** doorway;
- the context row combines the single-icon document-mode pull-down, heading
  outline, and restrained Properties on the same readable measure as the
  document;
- the document remains an opaque, calm, centered prose surface;
- Inspector and Note History occupy one mutually exclusive trailing region;
- Scholia appears as one centered, role-aware panel; at wide widths Dialogue
  may use a selected-notes column beside its instruction/context column and
  stack them at narrower widths.

Responsive priority is semantic, not tied to the prototype's numeric
breakpoints. Shorten tab labels and secondary metadata first; convert
**Open Scholia…** to a centered icon with its full accessible name before
hiding it; collapse the trailing region before harming readable text measure;
then hide or overlay the leading sidebar. Preserve controls for active
conflict, recovery, and consequential work.

The production realization is native macOS 26. Use SwiftUI or AppKit windows,
toolbars, split views, inspectors, lists/outlines, segmented controls, search
fields, menus, pull-downs, popovers, and sheets so the system supplies correct
Liquid Glass behavior. Do not port the prototype's CSS, traffic lights, blur,
shadows, radii, colors, or simulated glass literally. Liquid Glass belongs to
the navigation and control layer; prose, dense lists, expanded Properties,
diagnostics, diffs, and exact source remain calm and legible on opaque content
surfaces with Reduce Transparency and Increase Contrast adaptations.

## 5. Visual language

### 5.1 Typography

**Apple guidance:** interface chrome uses system typography and semantic text styles.
**Scholium decision:** document typography has two specialized roles.

- Use the macOS system font for menus, toolbars, sidebars, inspectors, buttons, settings, alerts, labels, and other application chrome.
- Use **Alegreya** for Read prose and the prose projection in Live Preview.
- Use **Victor Mono** for Source, code, exact source excerpts, line-anchored review content, revision identities, and diff text.
- Use **12pt** as the document body baseline. Scale headings as H1 **150%**, H2 **130%**, H3 **115%**, and H4–H6 **100%** of Body.
- Callout body text inherits Body by default. A role-specific size is an explicit exception; Orientation is currently the approved **80%** exception.
- Do not use either document font as a branding layer over standard controls.
- Provide explicit reader/editor scaling and verify useful enlargement to at least 200%. Larger text must not clip controls or force horizontal scrolling of ordinary prose.

### 5.2 Color and appearance

- Use semantic dynamic colors and respect the system accent color.
- Support System, Light, and Dark appearance without hard-coded inversion.
- Pair every status color with text, a symbol, shape, or accessible value.
- Reserve red for errors, blockers, destructive effects, or unqualified status; orange for warnings, stale state, or needed attention; green for confirmed positive state. Do not infer philosophical value from these colors.
- Keep agent authorship explicit in words; a purple tint or sparkle symbol is only a redundant cue.
- Test Increase Contrast and accent-color changes. Selection, syntax, links, warnings, and focus must remain distinguishable.
- Target at least 4.5:1 contrast for ordinary small text and 3:1 for large or bold text. Audit every important custom target below 28 by 28 points; do not make it smaller than 20 by 20 points.

### 5.3 Spacing, hierarchy, and surfaces

- Use standard control sizes, paddings, list rows, section spacing, and split-view dividers before inventing custom measurements.
- Use dividers to express real structural boundaries, not as repeated decoration.
- Keep the document, diffs, diagnostics, and dense properties opaque and legible.
- Let native toolbars, sidebars, inspectors, sheets, and popovers receive system materials or Liquid Glass where the active SDK provides it.
- Under Reduce Transparency, replace material hierarchy with opaque semantic backgrounds and clear separators.
- Use one restrained accent hierarchy. Avoid nested translucent cards, gradients behind text, and feature-specific miniature design systems.

### 5.4 Selection and focus

- Use native selection and focus effects.
- Keep list selection visible when the editor has keyboard focus; distinguish selection from focus.
- Never move focus because search, indexing, file watching, backlinks, or diagnostics refreshed.
- Restore focus after sheets, alerts, popovers, Quick Open, Dialogue, Critique, conflict comparison, and checkpoint/history close.
- Do not use a custom low-contrast focus outline.

### 5.5 Symbols and decoration

- Prefer familiar SF Symbols for standard commands.
- Pair unfamiliar research, relationship, provenance, review, or agent symbols with visible text until their meaning is independently clear.
- Give icon-only toolbar controls a current accessible name and concise tooltip.
- Do not encode meaning through arrow direction, icon shape, or color alone.
- Use cards, capsules, borders, and shadows only when they establish grouping or state. Do not put every row in a card.

## 6. Interaction principles

### 6.1 Command parity

Every important action must have the appropriate routes for its frequency and context:

- toolbar for frequent document-local actions;
- menu bar for complete command access and keyboard discoverability;
- context menu for a short set of relevant accelerators;
- keyboard shortcuts for frequent operations;
- pointer actions with standard targets and feedback;
- named accessibility actions where a normal control cannot express the task.

Every toolbar action also belongs in a menu. A context menu is never the only path. Route commands to the focused document or window rather than an unrelated global selection.

### 6.2 Native controls and clear language

- Use buttons for actions, checkboxes/toggles for persistent Boolean state, pop-up controls for one value, pull-down menus for one of several commands, and disclosures for optional detail.
- Use direct, stable, verb-led action labels. Do not use vague labels such as “Process,” “Continue,” or “Copy Agent Request” when the result can be named.
- Keep unavailable commands visible and disabled when that preserves discoverability; explain material prerequisites nearby.
- A placeholder is not a field label.

### 6.3 Keyboard, pointer, hover, and drag

- Preserve standard shortcuts and responder-chain editing behavior.
- Support Full Keyboard Access throughout the sidebar, document, inspector, Review, Dialogue, Critique, checkpoint, conflict, and settings tasks.
- Hover may reveal a convenience but is never the only discovery or activation route.
- Every drag operation has a keyboard or menu alternative.
- Do not require color discrimination, precise dragging, a gesture, or a secondary click for a core task.

### 6.4 Cancellation and recovery

- Every sheet has a clear completion and cancellation path; Escape performs the safe cancellation when appropriate.
- Preserve edits if a popover or sheet can be dismissed accidentally.
- Keep the buffer, selection, and error visible after save failure or conflict.
- Use Undo for reversible editing operations, version restore for durable recovery, and explicit comparison before destructive reload.
- Routine autosave succeeds quietly. Persistent failures remain attached to the affected document until resolved.

## 7. Semantic distinctions that must remain visible

| Distinction | Required presentation |
| --- | --- |
| Source material vs researcher writing | Label vault role, document type, and source provenance. Do not use one undifferentiated content color as the only cue. |
| Authoritative content vs derived diagnostics | Name diagnostics as derived, include scope/freshness/source anchors, and never write them into the note implicitly. |
| Human Review vs Critique | Human Review qualifies an Analysis or Topic; Critique is an attributed assessment of a Work and never becomes qualification. |
| Dialogue vs agent edit | Dialogue records concise researcher Comments, agent Responses, and follow-up exchanges; transient transport instructions are not the scholarly record, and authoritative file changes remain detectable through fingerprints and checkpoints. |
| Extracted source vs user note vs agent inference | Separate with headings, labels, and reading order. Do not blend them into one prose block. |
| Editor undo vs version restore | `Command-Z` reverses editing operations; **Restore This Version** performs a repository transaction. |
| Navigation history vs tabs vs modes | Back/Forward visits locations; tabs keep bounded documents open; Read/Live Preview/Source changes one document’s presentation. |
| Explicit relation vs inferred/neutral connection | Show predicate, direction, source anchor, and explicit/inferred status in words. Proximity and transitivity never imply evidence. |
| Saved source vs refreshed derived state | A completed source commit is **Saved** even while search or relationships are **Refreshing**. Report derived failure separately. |

## 8. Accessibility and adaptation requirements

Accessibility is an end-to-end task outcome, not the presence of modifiers.

### 8.1 Required adaptations

- **Light, Dark, and System:** use semantic colors and backgrounds; test selection, links, syntax, warnings, callouts, footnotes, and diffs in each appearance.
- **Increase Contrast:** maintain clear boundaries, focus, selection, and status without relying on subtle opacity.
- **Reduce Transparency:** keep document text, diagnostics, Dialogue, Critiques, checkpoints, and controls legible on opaque fallbacks.
- **Reduce Motion:** preserve state meaning without animation and permit immediate interaction.
- **Larger text:** support at least 200% document scaling and long system/translated labels without clipping or overlap.
- **VoiceOver:** expose headings, landmarks, lists, links, labels, values, current state, source anchors, validation, and named actions in a logical reading order.
- **Full Keyboard Access:** complete opening, searching, reading, editing, Review, Dialogue, Critique, checkpoint restoration, conflict recovery, and settings without a pointer.
- **Voice Control:** visible control names must be speakable and match accessible names.

### 8.2 Framework boundaries

- SwiftUI controls retain correct labels, values, selected state, focus, enabled state, and restoration.
- CodeMirror and WKWebView must expose a truthful editable/read-only role, source value, selection, headings, links, lists, code, tables, callouts, and footnotes.
- Automatic render or save refresh must not reset focus or VoiceOver to the start of a long note.
- Graph and canvas views always have a source-anchored list or table equivalent.
- Mixed Chinese/Latin text, marked-text composition, paragraph direction, punctuation, selection, and source ranges require explicit testing.

### 8.3 Nonvisual state

Communicate each important state through at least two suitable channels. Color, motion, sound, spatial position, or arrow direction alone is insufficient. Conflicts, failures, stale Critiques, unresolved links, and blockers remain inspectable without a time limit.

### 8.4 Release accessibility pass threshold

The following is the pass threshold for Beta and 1.0, not a claim that the
current 0.1 Experimental build already satisfies it:

- 100% of the core academic workflow has a Full Keyboard Access path and a
  VoiceOver path. No required action depends on a mouse, drag-and-drop, hidden
  gesture, or color alone.
- The tested workflow includes setup, opening and editing notes, Human Review,
  comments, Dialogue presentation, Search, Connections, checkpoint restore,
  conflict recovery, and Trash/restore.
- Light and Dark appearance, Increase Contrast, Reduce Transparency, Reduce
  Motion, and 100%, 150%, and 200% document scaling preserve usable layout
  without clipping or overlap.
- English, Simplified Chinese, Traditional Chinese, mixed Chinese/English,
  Greek, Latin, and Unicode content remains searchable, editable, renderable,
  selectable, and accessible across the supported editor boundary.
- Zero unresolved critical or high-severity accessibility defects remain. A
  provisional ceiling of five medium-severity defects may be used only with
  the release owner's explicit disposition.

## 9. Component guidance

### Sidebars

- Use broad peer-level areas and shallow hierarchy.
- Keep the selected vault and note explicit.
- Use full-width native selection, not isolated pill selection.
- Keep **Manage Triptychs…** and **Reveal Current Vault in Finder** in standard menus as well as local conveniences.
- At narrow widths, allow the sidebar to hide; do not clip it into an unusable strip.

### Note lists and search results

- Make title the primary row content; use modified time, author/year, type, review, or status as restrained secondary facts.
- Use symbols and status text redundantly.
- Truncate predictably and expose the full title through accessibility and help.
- Search rows include snippet, field/context, and exact destination rather than pretending to be file rows.

### Document headers

- Keep the title and note identity legible without competing with the body.
- Place one text-labelled **Open Scholia…** action prominently. It opens the
  role-appropriate Comments-and-Review or Comments-and-Critique segment by
  default and also provides Dialogue. At narrow widths, preserve the action as
  a centered icon with the full accessible name and help text rather than
  hiding it.
- Keep document mode, properties, history, and inspector controls grouped by purpose.
- Do not show a large permanent “Saved” badge.

### Property panels

- Use persistent labels and controls appropriate to the value type.
- Group coherent fields; do not nest decorative cards.
- Show validation beside the field and preserve the typed value.
- Keep exact YAML available in Source mode.

### Semantic callouts

- Use only the preferred semantic roles **Orientation** (`orient`), **Source** (`cite`), **Connections** (`connect`), **Statement** (`state`), **Illustration** (`illustrate`), **Quotation** (`quote`), and **Caution** (`flag`) for newly created callouts.
- Keep the role label visible for Source, Connections, Statement, Illustration, Quotation, and Caution even when a user supplies a title. Orientation is the deliberate visual exception: its role and any title remain semantic and accessible metadata but are not shown in Read or Live Preview. Color, glass tint, and edge treatment are redundant emphasis, never the sole carrier of meaning.
- Treat `state` as an isolated claim-like object, not an endorsement; `cite` as a source record, not proof of support; and `flag` as a local interpretive caution, not workflow status.
- Keep Source borderless and free of a card surface or shadow. Its only decorative boundary is a line beneath the role heading, anchored at the left edge and fading to transparent at the midpoint. The line is redundant decoration and never carries source status or evidential meaning.
- A callout without a fold marker is fixed and expanded. Add `+` immediately after the closing `]` to make it collapsible and expanded by default, or `-` to make it collapsible and folded by default. Read uses the native disclosure interaction; Live Preview and the native fallback keep the exact source editable and hide the marker outside the active construct.
- Use one restrained glass-like material grammar, but differentiate roles through silhouette, border placement, density, title scale, and body typesetting—not color alone. Provide an opaque Reduce Transparency fallback and clear Increase Contrast boundaries. Keep callout bodies fully selectable and structurally semantic.
- Preserve legacy identifiers and unknown callouts without rewriting source. Render known legacy identifiers through their documented semantic alias; render unknown identifiers neutrally with a diagnostic.

### Research inspectors

- Use one trailing native inspector with Incoming, Outgoing, and Research modes.
- Give sections true headings, counts, empty explanations, and source-location actions.
- Treat warnings and heuristics as derived and configurable where applicable.
- Do not expose retired workflow gates, settlement, prose-permission, source-check, bridge-authorization, or project-readiness judgments as inspector warnings.
- Do not use empty regions, fixed alignment spacers, or independent custom chrome.

### Checkpoint comparison

- Name the selected checkpoint and its creation reason before content.
- Show created, changed, moved, deleted, and unchanged files with text labels and keyboard traversal.
- Make selective restoration available without requiring a full-Triptych rollback.
- Keep **Restore from Checkpoint…** distinct from editor Undo and ordinary navigation.

### Conflict recovery

- Keep the current buffer open.
- State that disk changed and identify both revisions.
- Offer **Compare Changes**, **Reload from Disk**, and **Keep Editing** when comparison is available.
- Make reload visibly destructive to uncommitted work and never the default.
- Return from comparison to the same conflict decision.

### Empty, loading, unavailable, malformed, and error states

- Keep cached or unaffected content usable.
- State what is empty or unavailable and at what scope.
- Show honest progress when work is noticeable; permit cancellation only when safe.
- A malformed note remains readable and exposes a repair path; do not silently rewrite it.
- An inaccessible vault offers a specific access-recovery action.
- A failed derived refresh does not relabel saved source as unsaved.
- Avoid transient toasts for conflicts, failed writes, permission loss, malformed source, or failed checkpoint restoration.

## 10. Canonical interface state and action contract

Use these meanings and labels everywhere: document chrome, alerts, menus, accessibility values, user-facing logs, help, and UI automation. Omit an unavailable capability rather than renaming another action to imply it.

### 10.1 Document and derived-state meanings

| State | Exact meaning | Presentation rule |
| --- | --- | --- |
| **Edited** | The in-memory source buffer differs from its committed fingerprint. | Use the standard window edited state only when it accurately represents this condition. |
| **Saving** | The conflict-aware repository transaction is validating, snapshotting, and attempting the atomic write. | Show quiet document-local progress without removing recovery paths. |
| **Saved** | The repository returned a committed revision after validation, pre-write snapshot, atomic disk write, and authoritative model update. | This is authoritative commit success. It may coexist with **Refreshing**. |
| **Save Failed** | No authoritative commit was returned; the current buffer remains uncommitted. | Keep the editor, buffer, selection, and error visible. |
| **Conflict** | The expected revision no longer matches the authoritative disk revision, so the write was rejected. | Keep the buffer open and never imply that reload is harmless. |
| **Refreshing** | One or more derived consumers are catching up to an already committed revision. | Name the affected scope when useful; do not relabel the document as unsaved. |
| **Derived State Stale** | A derived consumer represents an older revision than committed source. | Keep the stale scope visible until it catches up or is safely dismissed. |
| **Refresh Failed** | Source commit succeeded, but a derived consumer failed to reach it. | Preserve **Saved** and provide a separate persistent recovery path. |
| **Fully Up to Date** | Disk, repository model, search, links, relationships, rendering, and review diagnostics represent the same committed revision. | Use only when full convergence is useful to communicate; it is not the definition of **Saved**. |

Autosave after a short idle delay and safe lifecycle transitions. Do not require an ordinary Save button. Keep routine **Saved** feedback quiet and attach persistent status to the affected document or subsystem rather than a global toast.

### 10.2 Save, conflict, refresh, and restore actions

| Lifecycle | Exact actions | Rules |
| --- | --- | --- |
| Non-conflict validation failure | **Keep Editing** | Focus or reveal the invalid field or source range. Do not offer reload when disk has not changed. |
| Transient permission or write failure | **Retry Save**, **Keep Editing** | Show **Retry Save** only when repeating the transaction can plausibly succeed. |
| External conflict without comparison | **Reload from Disk**, **Keep Editing** | **Keep Editing** is the cancel path. Reload is never the default. |
| External conflict with comparison | **Compare Changes**, **Reload from Disk**, **Keep Editing** | Comparison preserves the buffer and returns to the same decision. |
| Conflict comparison | **Return to Editing**, **Reload from Disk** | Keep exact current and disk revision identities visible. |
| Derived refresh failure after commit | **Retry Refresh** | Scope the action to the failed consumer; do not imply that source bytes are unsafe. |

Native multi-level editor Undo remains distinct from durable recovery. `Command-Z` reverses editing operations. Triptych checkpoint restoration uses **Restore from Checkpoint…** and the same conflict-aware repository path as an ordinary save.

### 10.3 Scholia, Dialogue, Review, Critique, and checkpoints

**Open Scholia…** opens one document-local panel and does not itself create a
record or modify a note. Analyses and Topics show **Comments & Review** and
**Dialogue** in a segmented control. Works show **Comments & Critique** and
**Dialogue**. Context menus and menu-bar commands may open the same panel at a
specific segment; they must not create parallel versions of these workflows.

In **Comments & Review**, Comments and Human Review share a presentation but
not a record. Existing Comments appear before the review controls. The
whole-note Comment composer is collapsed by default and expands only after the
researcher invokes the compact add-Comment control. Human Review retains its
own verdict, **Review Note**, draft state, and completion actions.

In **Comments & Critique**, Comments and Critique likewise share a presentation
but not a record. Critique retains attributed agent authorship, target Work and
fingerprint, materials consulted, limitations, source anchors, request scope,
and response state.

For one or several selected notes, **Dialogue** contains the selected-note
list, one overall researcher Comment or instruction, included line or
whole-note Comments, and optional transient transport context. Its actions are
**Copy Instructions for Agent** and **Cancel**. An external agent is optional.

Dialogue does not display or permit selection, preview, or one-run editing of
the active template or assembled technical instructions. Secondary text says
that Dialogue uses the template configured for the Triptych and provides
**Edit Dialogue Template…**, which opens **Settings → Research Guidance** at
that template. The researcher verifies selected notes, Comments, scope, paths,
and other consequential context rather than prompt mechanics.

Before copying, Scholium completes pending autosaves and creates **Before Agent
Work**. The transient instructions identify selected notes by name,
vault-relative path, and advisory fingerprint. They may tell the agent to
inspect and directly modify other relevant Triptych files, but Scholium does
not transmit research automatically. Every selected note receives the
scholarly Dialogue record in Note History. The record shows researcher
Comments, selected-note association, checkpoint, and attributed Responses and
follow-ups; it does not require raw technical prompts, model metadata, or
paragraph-level AI provenance. It is not a document version and exposes no
restore action.

Analyses and Topics expose Human Review within **Comments & Review**. Completion requires a **Qualified** or **Unqualified** verdict and a non-empty **Review Note** of at most 500 characters. The actions are **Complete Review**, **Save as Draft**, and **Cancel**. A draft changes the relevant in-panel action to **Continue Review** without marking the fingerprint reviewed.

Works expose Critique within **Comments & Critique** rather than Human Review
qualification. The request offers **Overall Critique**, **Specific Comments**,
or **Both**, plus optional scholarly scope such as a selection, section, focus,
or disciplinary lens. It does not expose additional technical instructions,
the active template, assembled instructions, or one-run prompt editing.
Secondary text says **Critiques use the template configured for this
Triptych.** and provides **Edit Critique Template…**, which opens **Settings →
Research Guidance → Prompt Templates → Critique**. A Critique identifies agent
authorship, target Work, target fingerprint, source anchors, materials
consulted, and limitations. It never presents Qualified or Unqualified as a
Work status.

If an active Dialogue or Critique template is structurally invalid, preserve
all current workflow inputs, state that the template needs attention, keep the
applicable Settings action available, and disable instruction copying or the
Critique request until the blocking structural error is resolved. Do not reveal
the malformed template in the workflow.

Checkpoint commands are **Create Checkpoint…**, **Restore from Checkpoint…**,
and **Reveal Checkpoints in Finder**. Comparison labels files as created,
changed, moved, deleted, or unchanged in text. Selective and full restoration
remain explicit and are never editor Undo. A clean note may refresh quietly
after an external edit; a dirty note keeps its buffer and uses the conflict
actions above. Permanent deletion purges associated Dialogue, comment, Review,
Critique, and checkpoint-copy records, or invalidates a checkpoint that cannot
be scrubbed safely. If a shared multi-note Dialogue cannot be partitioned
safely, the shared record is deleted in full. Scholium does not claim to recover
uncheckpointed external work.

When an agent changes notes, the default closing response foregrounds the
concise academic change and any unresolved question or required researcher
review. It does not foreground a detailed file-operation log. Richer
reflection modules and alternative comment-preservation modes remain future
design work.

### 10.4 Verification evidence and design reporting

For material interface work, record the source revision or working tree, build configuration, macOS and SDK, fixture root, command, result, and retained result bundle or screenshot when available. Use nonprivate fixtures. A preview, test name, historical screenshot, or prior QA note does not prove the current build exercised a workflow. The isolated QA app is Debug evidence, not release, signing, sandbox, or distribution evidence.

A design review reports the researcher task, affected object, current problem, relevant Apple guidance, Scholium decision, ready/empty/loading/error/conflict/accessibility behavior, menu/keyboard/pointer/focus paths, Liquid Glass or content-surface role, exact verification performed, and remaining uncertainty.

## 11. Stable decision record

| ID | Stable Scholium decision | Basis | Status |
| --- | --- | --- | --- |
| D-001 | The research document is the primary object and largest stable region. | Scholium product model; Apple layout guidance | Stable |
| D-002 | Research files remain local by default; app state stays outside vaults. | Scholium trust model; Apple privacy guidance | Stable |
| D-003 | One exact Markdown source underlies Read, Live Preview, and Source. | Source-fidelity architecture | Stable and implemented |
| D-004 | Interface chrome uses system typography; Alegreya serves prose, Victor Mono serves exact/source text, the document body is 12pt, headings use 150/130/115/100% scales, and Callout body text inherits Body unless a role-specific exception is approved. | Apple typography guidance plus Scholium reading decision | Stable and implemented |
| D-005 | Dense document, diff, and diagnostic surfaces are opaque; materials belong mainly to navigation and controls. | Legibility, Reduce Transparency, current macOS appearance | Stable |
| D-006 | Provenance, relations, coverage, and diagnostics live in a trailing inspector. | Contextual-information model; native inspector convention | Stable and implemented |
| D-007 | Read/Live Preview/Source are document modes, not tabs. | Scholium mental model | Stable and implemented |
| D-008 | Navigation history, in-window tabs, native window tabs, and document modes remain distinct. | Apple navigation/window patterns plus Scholium model | Stable and implemented; sustained interactive multiwindow acceptance pending |
| D-009 | In-window tabs are bounded and use recognizable document identity; author/year is supplementary. | Canonical interface contract and ambiguity prevention | Stable; current implementation requires alignment |
| D-010 | Human Review applies to Analyses and Topics; Works use optional attributed Critique. Dialogue is a concise scholarly Comment-and-Response history; transient copyable instructions are transport, not the permanent record. These meanings remain separate even when presented together. | Product Guide authority model | Stable target; full interactive accessibility acceptance pending |
| D-011 | Researchers may choose whether to use agents. Dialogue exposes selected-note context, Comments, and Responses, while checkpoints and conflicts provide recovery for direct external edits. | Product Guide authority model | Stable target; full interactive acceptance pending |
| D-012 | **Saved** describes authoritative source commit; derived refresh has separate state. | Canonical interface contract | Stable and implemented |
| D-013 | CSS snippets affect documented document selectors only and cannot restyle protected research signals or app chrome. | Source/provenance legibility and security | Stable and implemented |
| D-014 | Every graph or canvas has a keyboard-accessible, source-anchored list equivalent. | Apple accessibility guidance plus provenance requirements | Stable; source-anchored list implemented, final accessibility audit incomplete |
| D-015 | Scholium supports research beyond a dissertation. Researchers may organize additional bodies of writing with ordinary Works folders; Scholium does not register or manage projects. | Long-term product mission and Product Guide | Stable and implemented; project-management UI removed |
| D-016 | Scholium targets macOS 26 or later and uses Liquid Glass as the primary native material for navigation and controls. APIs newer than the selected compiler and SDK remain gated until the toolchain advances. | Personal-app modern platform baseline | Stable |
| D-017 | Callouts use seven protected semantic roles; all roles except Orientation retain visible text labels. Orientation is presented as an unlabelled guide while its semantic role, source identity, and accessibility metadata remain protected. Visual emphasis never establishes endorsement, evidence, or workflow state. | Knowledge-base semantic specification; Scholium provenance model | Stable and implemented |
| D-018 | Vector links render as a protected SF Symbol plus note name, retain exact punctuation in Source, and communicate neutral connection, support direction, or symmetric incompatibility through text as well as icon and color. | Scholium relationship model; accessibility requirements | Stable and implemented |
| D-019 | The default workspace uses Analyses, Topics, and Works as concise researcher-facing labels. Their role-scoped profiles share canonical YAML keys for recurring concepts, retain legacy aliases as read compatibility, and never perform automatic bulk migration. | Research workflow evidence; source-fidelity architecture | Stable and implemented |
| D-020 | Scholium may register several complete Triptychs; one window belongs to one Triptych, and different Triptychs open in separate windows. Shared services belong to one `WorkspaceStore`; presentation state belongs to each window session. | Product Guide §3.2; window/session isolation | Stable and implemented; sustained interactive acceptance pending |
| D-021 | Scholium's core academic workflow is completable without Obsidian; Obsidian import and interoperability are optional and must not become a core workflow dependency. | Product Guide §2.1; standalone academic workflow requirement | Stable target; clean-environment acceptance pending |
| D-022 | Reader and editor text size are controlled and persisted per window without changing source. | Apple accessibility guidance plus per-window presentation model | Stable and implemented; 200% manual acceptance pending |
| D-023 | Scholium does not require technical prompt logs, hidden instructions, model parameters, token counts, paragraph-level AI provenance, or a separate AI audit dashboard. Agent responses foreground concise academic change. | Scholarly Dialogue boundary | Stable target; response presentation acceptance pending |
| D-024 | External agents, Zotero, and research skills are optional extensions; the manual academic workflow remains complete without them. | Product Guide and standalone workflow requirement | Stable target; clean-environment acceptance pending |
| D-025 | Document, HTML, PDF, and DOCX export are deferred after 0.1, not permanent product prohibitions. | Product Guide release boundary | Stable target; export not in 0.1 |
| D-026 | **Open Scholia…** is the shared document-local doorway for Comments, role-appropriate Human Review or Critique, and Dialogue. Its role-aware segmented panel combines navigation only; it does not merge records, provenance, completion, or backend behavior. | Scholium interface composition decision | Stable layout target; native Liquid Glass implementation pending |
| D-027 | `triptych-document-layout.html` is the preferred, non-binding baseline for main-window composition and page logic. It may evolve when a real frontend capability needs a better UI home, provided the document remains primary, semantic distinctions remain visible, and no layout decision is treated as a backend contract. | Researcher-reviewed prototype; native macOS adaptation | Stable design method; native Liquid Glass implementation pending |
| D-028 | Prompt templates and assembled technical instructions are configuration, not scholarly workflow content. They are visible and editable only in **Settings → Research Guidance**; Dialogue, Critique, and future research workflows expose scholarly inputs and a direct Settings link but no template picker, preview, or one-run prompt editor. | Researcher-approved prompt-mechanics boundary; Settings and text-entry guidance | Stable target; current Critique interface requires alignment |
| D-029 | **Research Guidance** manages both **Prompt Templates** and **Skills** while preserving them as distinct item types. User skills are editable file-backed packages discovered only at `.scholium/skills/<skill-id>/SKILL.md`; the workflow UI gains no skill picker or one-run override. | Researcher-approved skill-management boundary; local-first storage and Settings guidance | Stable target; implementation required |
| D-030 | **Recent Notes** is a per-window, vault-qualified, bounded MRU list exposed through the Navigate menu. It remains independent of chronological Back/Forward history and derived Search state, persists with the window session, and adds no permanent chrome. | Researcher return-to-work task; Apple macOS menu and recents conventions | Stable and implemented |

## 12. Future and unresolved design questions

Do not present these as completed behavior:

- sustained interactive acceptance of restored multiwindow sessions and native window grouping;
- in-note Find, heading outline, saved-search management, and Recent Notes are implemented;
- sustained manual VoiceOver, Full Keyboard Access, Voice Control, contrast, scaling, and localization verification across the CodeMirror/WebKit boundary;
- final keyboard and assistive-technology acceptance for the implemented view-only Canvas and source-anchored list presentation;
- whether Quick Open should remain a sheet or become a lightweight keyboard-first panel after focus-restoration testing;
- the most compact usable presentation for multi-note Dialogue entries in Note History;
- the final preservation modes for verbose or trivial Comments and richer
  Dialogue reflection modules;
- manual 200% acceptance for the implemented per-window reader/editor text-size controls.

Resolve these through current Apple guidance, this handbook's interface contract, fixture-based testing, and recorded researcher tasks. Do not infer a stable decision from a temporary implementation.

## 13. Design-review checklist

Before accepting an interface change, answer all of the following:

- Is the researcher’s task and affected research object explicit?
- Does the document remain primary at minimum and large window sizes?
- Is the choice grounded as Apple guidance, platform convention, Scholium decision, current implementation, or unresolved work?
- For an implementation-facing Apple claim, were both the relevant current HIG
  page and the exact API in the selected Xcode installation's Developer
  Documentation consulted?
- Are source, researcher writing, derived state, and agent content distinguishable?
- Are exact lifecycle meanings and action labels consistent with Section 10?
- Does every consequential action show target, consequence, provenance, and recovery?
- Are menu, toolbar, keyboard, pointer, focus, and accessibility routes present where appropriate?
- Can the task be completed without hover, drag, color, motion, secondary click, or a custom gesture?
- Are cancel, undo, restore, retry, comparison, and conflict paths correct and distinct?
- Does the design work in light/dark, Increase Contrast, Reduce Transparency, Reduce Motion, 200% document text, keyboard-only, and VoiceOver use?
- Does it survive long labels, Chinese/Latin mixed text, right-to-left chrome, and the minimum supported window?
- Are empty, loading, unavailable, malformed, stale, conflict, error, and completion states specified?
- Is Liquid Glass limited to an appropriate navigation or control role, with dense research content remaining calm and legible?
- Does each capability have an intentional UI home appropriate to its scope and frequency, without adding permanent chrome merely because a feature exists?
- Does the change preserve the prototype's preferred document-first topology, or record why a native alternative better serves the researcher task?
- Is the result a native macOS and Liquid Glass realization rather than a literal translation of HTML/CSS effects?
- Does any frontend wording accidentally imply new persistence, indexing, repository, schema, filesystem, CLI/API, or agent-execution behavior?
- Were the complete task and adjacent recovery states verified with nonprivate fixtures, and is remaining uncertainty recorded?

If any answer is unknown, mark it unresolved. Do not turn an untested assumption into a Scholium design rule.
