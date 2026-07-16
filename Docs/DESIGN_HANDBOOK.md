# Scholium Design Handbook

**Status:** Authoritative interface-design language and stable interface decisions

**Applies to:** Scholium for macOS 26 and later

**Last reviewed:** 2026-07-16

Scholium is a local-first macOS research workbench for sustained humanities
research. This handbook owns stable interface structure, visual language,
interaction, accessibility, and design review. Product behavior belongs to
`PRODUCT_GUIDE.md`; release synthesis to `PRD.md`; current evidence to
`IMPLEMENTATION_STATUS.md`; current reachability to `README.md`, source, and
tests; Apple platform guidance remains external authority.

**Rule status:** These rules are binding for Scholium’s user-facing interface, interaction behavior, accessibility, visual presentation, and design review. Future work must comply with them unless the researcher explicitly approves a documented exception. A stable rule changes only through an intentional edit to this handbook and, when applicable, the decision record. Current code that diverges from a rule is implementation debt, not an alternative design authority.

**Scope boundary:** This handbook may name existing application state only to
specify its presentation. It does not define repository, persistence,
filesystem, indexing, schema, CLI/API, or agent-execution contracts; a layout
decision does not create backend behavior.

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

`apple-hig` is the authoritative local reference for Apple Human Interface Guidelines. It owns HIG rules, measurements, patterns, components, and platform distinctions; this handbook applies that guidance to Scholium without duplicating it. The selected Xcode installation's Developer Documentation, SDK, and compiler remain authoritative for implementation-facing API behavior and availability. Apple guidance does not define Scholium's research model.

If a stable Scholium decision conflicts with `apple-hig`, record the conflict explicitly and obtain researcher approval for a documented exception or handbook change. Do not restate the HIG rule to make the conflict disappear.

Do not claim that Apple prescribes Scholium’s Triptych, evidence hierarchy, relationship semantics, Dialogue, Critique, Review, or governance model. Those are Scholium decisions.

### 1.1 Prototype and layout baseline

`Docs/Prototypes/triptych-document-layout.html` is the researcher-approved
preferred reference for Scholium's main-window composition and page logic. Its
document-first topology remains useful, but its Scholia doorway and segmented
panel are superseded by decision D-026's editor-only Research Strip and typed
function panel. The retained composition principle is that existing whole-note
Comments remain visible while the new Comment composer stays subordinate to
formal Review or Critique.

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
- may be developing one long-form project now while also producing papers, books, teaching material, or other humanities research;
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
- Do not present any one long-form project as the universal model. Use general research language in shared app chrome.
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
- Keep tabs, navigation history, selection, document mode, search, inspector mode, scroll position, and Dialogue/History presentation in a per-window session model. Route commands to the focused window or document.
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
- Consolidate the Library's research-state, tag, metadata, and sort choices in
  one compact native **Filter** menu. Keep the Unreviewed and Unqualified
  judgment toggles visible because they describe the current review task, not
  merely a hidden query option.
- Treat Debate Importance as a scoped comparison: expose its numeric ordering only after one Debate Scope filter is active, keep unrated matching Analyses visible after rated ones, and never imply that ratings from different debates form one scale.
- Search results show ranked snippets and source context; they do not become ordinary alphabetized file rows.
- Keep shared Search and Quick Open conceptually distinct: Search exposes
  **This Note**, **This Vault**, and **Triptych**, while Quick Open remains a
  separate navigation command and Command-F activates **This Note** in the
  shared Search surface. There is no separate in-note Find interface.
- Present shared Search as a centered, two-stage Spotlight-style overlay. Its
  empty state is one broad Liquid Glass search bar over a softly obscured
  window. A committed query expands that same surface downward, then reveals
  the three-scope segmented control and native result list. Do not show a large
  empty results sheet before the user enters text, and do not reproduce
  Spotlight's app-category chips or Finder actions.
- Keep lexical results and scholarly expansion visibly distinct. FTS5 results
  show why and where they matched. A separate **Related** section may show only
  direct, resolved Connections from one exact Topic title or alias; it never
  changes Search ranking or implies support through proximity or multi-hop
  paths.
- Beta Search does not use vectors, embeddings, AI query interpretation,
  AI ranking, or a chat-style question box. Scholium's existing Vector-Link
  terminology names explicit Markdown relations, not a retrieval technology.
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

- Float Properties and its two frequent document controls above the scrolling
  body. Reserve enough initial body inset for legibility, but allow scrolled
  prose to remain visible through the regular glass so the surface reads as a
  lightweight document control rather than an opaque second toolbar.
- Use one collapsible property region; do not show empty fields to prove a schema exists.
- Group researcher-facing properties as **Research Status**, **About**, **Source**, **Progress**, and **Use** when applicable.
- Present the YAML `research_unit` mapping as **Research Status**, not as a raw metadata object. Show **Scope** first and show **Limitations** only when non-empty. A role-specific top-level Status may appear in the same visual group but remains semantically separate.
- Keep Research Status inside the existing collapsible Properties region. It does not receive a new document type, card, panel, inspector mode, toolbar item, or permanent status badge.
- Creation and modification times belong to app-owned Note History. Do not present them as researcher- or agent-maintained frontmatter fields. Preserve existing timestamp YAML in Source without making it part of the structured default profile.
- Use the note's role and identity for type and source identity, and use Connections for linked targets and reverse navigation. Do not duplicate backlinks, relation counts, or derived coverage percentages inside Research Status.
- Reuse the canonical Triptych keys for recurring concepts across Analyses, Topics, and Works; interpret controlled values through the assigned vault role.
- Keep machine IDs, schema markers, and citation/Zotero keys preserved in source but out of the ordinary summary.
- Distinguish absent, empty, invalid, derived, and not-applicable values.
- Use Source mode for exact YAML and structured controls only for targeted changes.
- Prefer a compact context row whose mode and heading-outline controls share
  one restrained control group immediately before the role-aware property
  summary. The complete summary strip is the disclosure target; do not limit
  expansion to its trailing label or chevron. Show only a few available facts
  in the strip and progressively omit secondary facts before allowing them to
  crowd the document.
- Give the compact controls and Properties strip one height and one vertical
  centerline. Their combined width, including the inter-column gap, equals the
  document's centered readable measure. The expanded details panel uses that
  same complete measure; neither state extends beyond the prose column merely
  because the editor region is wider. The compact controls and summary use
  restrained
  regular Liquid Glass with subtle depth. The expanded panel uses one matching
  regular material surface with generous whitespace, clear text hierarchy,
  a soft shadow cast directly onto the scrolling document, and an opaque
  semantic fallback under Reduce Transparency; it does not nest
  translucent field cards or span the full window merely because space is
  available.

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

### 4.8 Research Strip, function panels, and recovery

**Human Review** records the researcher’s fingerprint-bound assessment and
qualification of an Analysis or Topic. **Dialogue** records concise scholarly
Comments and Responses and may package selected-note context into transient
copyable instructions. **Critique** is an optional attributed agent assessment
of one Work and remains separate from Work prose.

- Mount one restrained Research Strip at the bottom of the editor whenever an
  Analysis, Topic, or Work is open. Reserve matching editor space so prose and
  source controls are never obscured. With no selected note there is no editor,
  Strip, or function panel.
- Show **Dialogue · Develop · Review · Fidelity** for Analyses and Topics and
  **Critique · Revise · Dialogue · Fidelity · Manuscript** for Works, in that
  order. These one-word controls are the only permanent function choices.
- Choosing one function opens the shared Research Function panel directly at
  that function. Do not recreate an omnibus segmented Scholia panel or a
  second-level mode chooser. The panel title and sections adapt to the selected
  function while the Target remains fixed.
- Select additional notes only inside the panel. Present them as read-only
  Materials and make Target duplication impossible. Scope is **Whole |
  Passage**; a current editor selection defaults relevant functions to Passage.
- Human Review, Comments, Dialogue, Critique, Fidelity, checkpoints, and Note
  History retain separate eligibility, provenance, completion, and recovery
  behavior even when their controls are adapted into one function panel.
- Keep whole-note Comments subordinate to the formal Review or Critique task.
  Show existing Comments normally, but keep the new whole-note Comment composer
  collapsed behind a compact add-Comment control until the researcher invokes
  it. A **Review Note** remains the single prominent note-level judgment field
  during Human Review.
- Use the exact target actions and meanings in Section 10.
- Keep Human Review, Dialogue entries, Critique associations, and checkpoint versions visibly distinct in Note History.
- Let the researcher select Materials and provide one overall Dialogue Comment
  or instruction without exposing philosophical submodes. Dialogue is read-only
  unless an external agent explicitly promotes it to Develop or Revise through
  the function API.
- Keep prompt templates and assembled technical instructions out of Dialogue,
  Critique, and future research-workflow surfaces. These surfaces show the
  selected research context and scholarly inputs but no template body,
  placeholder list, preview, picker, or one-run prompt editor.
- Use restrained text actions to open **Settings → Research Guidance** at the
  applicable template. Preserve the workflow's selected notes, Comments,
  scope, and keyboard focus path while the Settings window is open.
- Show Critique authorship, target, target fingerprint, materials consulted, limitations, and source anchors before the body.
- Combine former overall and focused Critique choices into one **Critique**
  function using Whole or Passage. Review contains Analysis or Topic Comments;
  Critique contains Work Comments. Fidelity contains **Content** and
  **Citations** checks and must show when Citations needs a bound Researcher
  Skill.
- Do not imply that a Dialogue entry is a document version or that a Critique judgment is Human Review qualification.
- Do not require technical prompts, hidden instructions, model parameters, or
  paragraph-level AI provenance in the scholarly Dialogue record.
- When an agent changes notes, foreground a concise academic change summary;
  routine file-operation details remain secondary.
- Keep checkpoint comparison keyboard navigable and label created, changed, moved, and deleted files in text rather than color alone.

The Research Strip is a Scholium-specific macOS control surface inspired by the
researcher's requested bottom ornament placement; it is not Apple's visionOS
Ornament component. Apple macOS guidance generally cautions against making the
bottom edge the only home for critical actions because a window can extend
below the display. The researcher approves this documented exception because
the Strip remains inside the visible editor layout and every function has a
direct Research-menu route, keyboard/focus behavior, and accessibility action.

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
  `SKILL.md` source directly, duplicate a permitted official package into a
  new independent Triptych package, rename or delete a Triptych-local skill,
  and use **Reveal Skills Folder** to open the supported location. System
  Skills expose no duplicate action. Keep invalid packages visible
  with an inline structural error and never imply that validation certifies
  philosophical accuracy or methodological quality.
- Skill management does not add a skill picker, skill source, package
  identifier, or one-run override to Dialogue, Critique, or another research
  function. **Research Guidance → Skills → Research Methods** presents one
  one-word function at a time and uses friendly method names to choose the
  built-in or a compatible Triptych-local primary method, Supplements, and
  exact Practices. Application alone validates and persists the semantic
  binding used by later runs; package identifiers never appear in the Strip.
- A Triptych-local Researcher Skill that explicitly opts into maintenance may
  copy an external proposal request containing its complete current package,
  revision, and maintenance purpose; import the returned complete package JSON;
  and show per-file current/proposed comparison, evaluation status, **Apply**,
  and **Restore** in Research Guidance. Keep proposal, evaluation, expected
  revision, confirmation, and rollback as distinct visible stages. Bundled
  System and Workflow Skills expose no evolution action, and no research
  function opens this maintenance flow automatically.
- Keep **Recovery** as a global Skills section independent of the currently
  selected package. Valid snapshots remain selectable when their package is
  missing or malformed and when a different snapshot is corrupt. A selected
  snapshot names its package, revision, current state, and full-replacement
  consequence before offering **Restore…**. Confirmation uses **Restore
  Complete Package** and **Cancel**, explains that files absent from the
  snapshot are removed, and states whether Scholium will create an undo
  snapshot of the displaced package or reinstall a missing package.
- Use **New Triptych…**, **Open Triptych**, **New Window**, and **Manage Triptychs…** consistently. Settings lists complete Triptychs and edits the selected Triptych’s three roots; it never presents Works folders as projects.
- Keep task-specific settings near their task, except prompt-template mechanics,
  which remain centralized in **Research Guidance** under decision D-028.
- First launch is a narrow, no-scroll, multi-step window. Present only one
  decision at a time: Analyses, Topics, Works, then the bounded authorization
  beside Works. Use short labels, standard Open panels, enabled/disabled
  progression, and visible step progress to teach by doing. Longer storage and
  agent-boundary explanations belong in Help or Settings; show a concise
  permission explanation only when its Open panel is requested.
- Use the same preferred width and height as the Triptych Interface. Place both
  states in the screen's leading-middle region: one half-interface-width from
  the leading screen edge and vertically centered. Finishing first-run setup
  transitions once into the Interface and must not re-present the guide.
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
| **Toolbar** | A small number of frequent window or document actions, including the bounded open-note strip, Search, and paired History/Inspector controls when applicable. |
| **Document context row** | Document mode, heading outline, compact role-aware Properties, and persistent document-local lifecycle or conflict state. |
| **Editor Research Strip** | One role-aware row of direct scholarly functions for the open note. It is absent outside the editor and never becomes a folder- or multi-selection toolbar. |
| **Sidebar or content list** | Triptych scope, folders, queues, locations, notes, and result navigation. |
| **Triptych Interface** | When no note is open, the main window contracts to a narrow left-middle Library anchor. Its top-right control is Triptych management only. Selecting a note reveals the document from behind its trailing edge; management and **Collapse Note** then form one compact group. No Home or dashboard intervenes. |
| **Inspector or Note History** | Persistent context for the selected note, including Connections, Research information, diagnostics, provenance, and chronological records. |
| **Popover or pull-down** | Compact transient selection, search, filtering, or a short command choice that does not require a multi-step decision. |
| **Sheet or centered panel** | Bounded, consequential, or multi-step work such as a Research Function, Attention triage, classification, conflict comparison, and checkpoint recovery. |
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
- the central toolbar contains bounded open-note tabs with Search adjacent;
- the context row combines the single-icon document-mode pull-down, heading
  outline, and restrained Properties on the same readable measure as the
  document;
- reader and editor text-size commands remain in the **View** menu with their
  keyboard shortcuts and per-window persistence rather than occupying the
  permanent context row;
- the document remains an opaque, calm, centered prose surface;
- the bottom editor edge contains one restrained role-aware Research Strip with
  matching reserved space and complete menu and keyboard alternatives;
- Inspector and Note History occupy one mutually exclusive trailing region;
- one Research Function appears in the centered shared panel at a time; at wide
  widths Materials may sit beside its function-specific draft and stack at
  narrower widths.

Responsive priority is semantic, not tied to the prototype's numeric
breakpoints. Shorten tab labels and secondary metadata first; keep the Strip's
one-word labels and order intact while using compact native spacing; collapse
the trailing region before harming readable text measure; then hide or overlay
the leading sidebar. Preserve the Research menu and keyboard path if a Strip
item is unavailable at the current width, and always preserve active conflict,
recovery, and consequential work.

The production realization is native macOS 26. Use SwiftUI or AppKit windows,
toolbars, split views, inspectors, lists/outlines, segmented controls, search
fields, menus, pull-downs, popovers, and sheets so the system supplies correct
Liquid Glass behavior. Do not port the prototype's CSS, traffic lights, blur,
shadows, radii, colors, or simulated glass literally. Liquid Glass belongs to
the navigation and control layer. Prose, dense lists, diagnostics, diffs, and
exact source remain calm and legible on opaque content surfaces. The one
expanded Properties surface may use restrained regular material as a bounded
continuation of its disclosure control, but its fields remain content-first
and become opaque under Reduce Transparency.

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

- Feature views use semantic design tokens, never literal hex values or raw
  palette names. The reviewed light and dark palettes are mapped through
  `ScholiumColorRole`; WebKit uses the identical role vocabulary.
- Light appearance uses **Ivory Leaf** `#FFFCF5` for the document,
  **Parchment** `#EFE9DF` for navigation, **Vellum Surface** `#F7F1E7` for
  opaque panels, and **Raised Stone** `#DED3C5` for hover, selection, or raised
  emphasis. Use **Carbon Ink** `#17191C` for primary text, **Sepia Ink**
  `#514D48` for secondary text, **Muted Ink** `#706B65` for metadata or icons,
  and **Binding Rule** `#C8BCAE` for borders and separators.
- **Vermilion Copper** `#A94C22` is the light-appearance accent for primary
  actions, links, active emphasis, and progress; **Deep Copper** `#7A2917` is
  its hover, pressed, and increased-contrast companion. Native controls still
  own their platform focus, selection, disabled, and interaction rendering.
- In light appearance, notification/highlight uses **Ochre** `#B47617`,
  Attention uses `#976015`, Confirmed uses `#2C7048`, Destructive uses
  `#A13235`, and Information uses **Lapis** `#315F88`. Information identifies
  an informational or source-location cue; it never establishes evidential
  support or source authority.
- Dark appearance is an **evening library**, not an inversion of light mode.
  It uses **Walnut Document** `#302A26`, **Cordovan Navigation** `#3A2B2B`,
  **Leather Surface** `#3A322D`, and **Raised Walnut** `#423831`. Primary,
  secondary, and muted text use **Parchment** `#F4E8D5`, `#D4C2AD`, and
  `#B6A38F`; the separator is `#807064`.
- Dark accent and notification use **Luminous Copper** `#EF8D5B`, its hover
  companion `#F5AA7B`, and **Ochre** `#E1B64F`. Dark Attention uses
  `#E0AB61`, Confirmed uses `#7FC39A`, Destructive uses `#EA817C`, and
  Information uses **Lapis** `#84B0D4`. Increase Contrast uses the reviewed
  stronger variants in the shared token implementation rather than replacing
  either appearance with generic black, white, or system accent colors.
- Support System, Light, and Dark appearance without hard-coded inversion.
- Pair every status color with text, a symbol, shape, or accessible value.
- Reserve red for errors, blockers, destructive effects, or unqualified status; orange for warnings, stale state, or needed attention; green for confirmed positive state. Do not infer philosophical value from these colors.
- Keep philosophical support teal and incompatibility purple. They are
  relationship meanings, not green success or red failure.
- Keep agent authorship explicit in words; a purple tint or sparkle symbol is only a redundant cue.
- Test Increase Contrast and accent-color changes. Selection, syntax, links, warnings, and focus must remain distinguishable.
- Target at least 4.5:1 contrast for ordinary small text and 3:1 for large or bold text. Audit every important custom target below 28 by 28 points; do not make it smaller than 20 by 20 points.

### 5.3 Spacing, hierarchy, and surfaces

- Use standard control sizes, paddings, list rows, section spacing, and split-view dividers before inventing custom measurements.
- Use dividers to express real structural boundaries, not as repeated decoration.
- Keep the document, diffs, diagnostics, and exact source opaque and legible.
- A single bounded expanded Properties panel may use regular material when it
  preserves field contrast and has an opaque Reduce Transparency fallback; do
  not use clear glass, nested translucent cards, or material for each field.
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
| Declared Research Unit vs derived research coverage | Research Status shows the note's declared scope and material limitations. Connections and any future aggregate coverage view remain derived and must not be written back as proof that a source, debate, or Work has been completely analyzed. |
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
- Graph views always have a source-anchored list or table equivalent.
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
  conflict recovery, and Trash/Put Back.
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
- Do not add a generic Open Scholia or function doorway to the header. Direct
  research functions belong to the bottom editor Strip and Research menu.
- Keep document mode, properties, history, and inspector controls grouped by purpose.
- Do not show a large permanent “Saved” badge.

### Property panels

- Use persistent labels and controls appropriate to the value type.
- Group coherent fields; do not nest decorative cards.
- Make the entire compact Properties summary one standard disclosure target.
  Keep the expanded panel visually continuous with that trigger while
  preserving content legibility and one calm material layer.
- Render Research Unit as the **Research Status** group with an accessible Scope value and, when present, a Limitations list. Preserve an undeclared Research Unit as an honest absent state rather than fabricating scope.
- Keep app-owned creation and modification time in History rather than editable Properties.
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
| Set Aside or Trash recovery | **Put Back** | Return the note to its exact original vault-relative path. Do not expose a destination field, silently rename it, or choose another folder. Report a conflict if that path is occupied. |

Native multi-level editor Undo remains distinct from durable recovery. `Command-Z` reverses editing operations. Triptych checkpoint restoration uses **Restore from Checkpoint…** and the same conflict-aware repository path as an ordinary save.

### 10.3 Research Strip, functions, records, and checkpoints

The bottom editor Research Strip exposes exact one-word function labels. For an
Analysis or Topic it shows **Dialogue**, **Develop**, **Review**, and
**Fidelity**. For a Work it shows **Critique**, **Revise**, **Dialogue**,
**Fidelity**, and **Manuscript**. It opens one typed function panel directly;
there is no Open Scholia doorway or mode-segmented second level. The Research
menu exposes the same role-valid functions. `Command-Shift-D` opens Dialogue;
`Command-R` opens Review for an Analysis or Topic and Critique for a Work.

Every panel names the fixed Target before other content. **Materials** are
chosen inside the panel, remain read-only, and cannot include the Target.
Where scope applies, use **Whole | Passage**; a current selection defaults to
Passage. Keep panel draft, selected Materials, Comments, Fidelity checks,
progress, cancellation, and errors bound to one presentation identity. A note,
Triptych runtime, window, or Target change invalidates a stale preparation.

**Review** adapts the existing Human Review and Analysis or Topic Comments. It
shows existing Comments before the review controls and keeps the new whole-note
Comment composer collapsed until invoked. Completion requires **Qualified** or
**Unqualified** plus a non-empty **Review Note** of at most 500 characters. Its
actions remain **Complete Review**, **Save as Draft**, and **Cancel**.

**Critique** adapts Work Comments and one attributed assessment. Whole and
Passage replace separate overall and focused buttons. A Critique identifies
agent authorship, Target Work and fingerprint, Materials consulted,
limitations, source anchors, scope, and response state. It never presents
Qualified or Unqualified as a Work status and never silently revises the Work.

**Dialogue** contains the fixed Target, selected Materials, one overall
researcher Comment or instruction, included Comments, and optional transient
transport context. Its actions are **Copy Instructions for Agent** and
**Cancel**. It is read-only unless an external agent promotes the request to
Develop or Revise through the function API. Dialogue remains a scholarly
Comment-and-Response record, not a document version or a hidden permission
system.

**Develop** and **Revise** are explicit write-capable functions. Develop serves
Analysis or Topic exploration, concept and argument development, synthesis,
and expression without showing those as additional interface modes. Revise
serves the current Work, including substantive writing and received-feedback
disposition. **Manuscript** coordinates isolated phases while the current Work
remains the only document Target.

**Fidelity** contains **Content** and **Citations**. If no valid citation-method
binding is active, keep Citations visible but unavailable and explain the
repair in Research Guidance. Show **Awaiting Fidelity**, **Unverified**,
**Verified**, and **Stale** only according to the exact revision-specific
function outcome; never imply that an external audit ran automatically.
After a write function records its substantive final fingerprint, show
**Awaiting Fidelity** until an independently prepared Fidelity run for that
exact revision is completed and linked back to it. Do not present pre-edit
Fidelity, direct outcomes submitted on the write run, or duplicate evidence as
a completed final audit.

If preparation requires agent-selected conditional methods, the panel remains
read-only while the external agent finalizes that same run through the function
API. It exposes no method selector or package identifier and must not present
mutation instructions or a completed state before explicit selection,
including an explicit empty base-only selection.

No function panel displays or permits selection, preview, or one-run editing of
the active template, workflow package, assembled instructions, or package ID.
An applicable **Edit Template…** or **Open Research Guidance…** action may open
Settings without discarding the panel draft. A structurally invalid binding or
template preserves inputs, names the required repair, and disables preparation
until repaired.

Before Develop, Revise, Manuscript, promoted Dialogue, or Critique preparation,
Scholium completes pending autosaves and creates the required **Before Agent
Work** checkpoint. Review and Fidelity create none. The transient instructions
identify the Target and Materials by human-readable identity, vault-relative
path, and advisory fingerprint. Scholium does not transmit research
automatically.

Checkpoint commands remain **Create Checkpoint…**, **Restore from
Checkpoint…**, and **Reveal Checkpoints in Finder**. Comparison labels created,
changed, moved, deleted, and unchanged files in text. Selective and full
restoration remain explicit and are never editor Undo. Human Review, Comments,
Dialogue, Critique, Fidelity, and checkpoint records remain evidentially and
visually distinct. When an agent changes notes, the closing response
foregrounds the concise academic change and any unresolved question or required
researcher review, not a detailed file-operation log.

### 10.4 Research Guidance methods and Skill recovery

**Research Methods** belongs only in **Settings → Research Guidance → Skills**.
Its Function picker uses the same one-word function names as the Strip. The
primary **Method** picker shows **Built-in** plus compatible Triptych-local
researcher-facing names; **Supplements** and **Practices** are explicit
independent selections. Do not show a package identifier, filename, routing
role, or one-run override in the Strip or function panel.

The Skills sidebar contains one global **Recovery** section. It is populated
independently of the selected Skill and remains available when the current
package is absent or structurally malformed. Unsafe snapshot entries appear
under **Recovery Issues** without hiding valid snapshots. A snapshot detail
uses **Restore…** to open **Restore Complete Researcher Skill?**. Its exact
confirmation actions are **Restore Complete Package** and **Cancel**. The
message names the complete-package replacement and removal of files absent
from the snapshot, and identifies the undo-snapshot or missing-package
reinstall consequence. Restore success returns to the recovered package; it
does not imply that Scholium judged the package philosophically sound.

### 10.5 Verification evidence and design reporting

For material interface work, record the source revision or working tree, build configuration, macOS and SDK, fixture root, command, result, and retained result bundle or screenshot when available. Use nonprivate fixtures. A preview, test name, historical screenshot, or prior QA note does not prove the current build exercised a workflow. The isolated QA app is Debug evidence, not release, signing, sandbox, or distribution evidence.

A design review reports the researcher task, affected object, current problem, relevant Apple guidance, Scholium decision, ready/empty/loading/error/conflict/accessibility behavior, menu/keyboard/pointer/focus paths, Liquid Glass or content-surface role, exact verification performed, and remaining uncertainty.

## 11. Stable decision record

| ID | Stable Scholium decision | Basis | Status |
| --- | --- | --- | --- |
| D-001 | The research document is the primary object and largest stable region. | Scholium product model; Apple layout guidance | Stable |
| D-002 | Research files remain local by default; app state stays outside vaults. | Scholium trust model; Apple privacy guidance | Stable |
| D-003 | One exact Markdown source underlies Read, Live Preview, and Source. | Source-fidelity architecture | Stable and implemented |
| D-004 | Interface chrome uses system typography; Alegreya serves prose, Victor Mono serves exact/source text, the document body is 12pt, headings use 150/130/115/100% scales, and Callout body text inherits Body unless a role-specific exception is approved. | Apple typography guidance plus Scholium reading decision | Stable and implemented |
| D-005 | Dense document, diff, diagnostic, and exact-source surfaces are opaque; materials belong mainly to navigation and controls. One bounded expanded Properties panel may use regular material with an opaque Reduce Transparency fallback and no nested translucent fields. | Legibility, Reduce Transparency, current macOS appearance | Stable |
| D-006 | Provenance, relations, derived aggregate coverage, and diagnostics live in a trailing inspector. A note's declared Research Unit is presented as Research Status in Properties. | Contextual-information model; native inspector convention | Stable and implemented; manual visual/accessibility acceptance pending |
| D-007 | Read/Live Preview/Source are document modes, not tabs. | Scholium mental model | Stable and implemented |
| D-008 | Navigation history, in-window tabs, native window tabs, and document modes remain distinct. | Apple navigation/window patterns plus Scholium model | Stable and implemented; sustained interactive multiwindow acceptance pending |
| D-009 | In-window tabs are bounded and use recognizable document identity; author/year is supplementary. | Canonical interface contract and ambiguity prevention | Stable and implemented; manual visual and assistive-technology acceptance pending |
| D-010 | Human Review applies to Analyses and Topics; Works use optional attributed Critique. Dialogue is a concise scholarly Comment-and-Response history; transient copyable instructions are transport, not the permanent record. These meanings remain separate even when presented together. | Product Guide authority model | Stable target; full interactive accessibility acceptance pending |
| D-011 | Researchers may choose whether to use agents. Dialogue exposes selected-note context, Comments, and Responses, while checkpoints and conflicts provide recovery for direct external edits. | Product Guide authority model | Stable target; full interactive acceptance pending |
| D-012 | **Saved** describes authoritative source commit; derived refresh has separate state. | Canonical interface contract | Stable and implemented |
| D-013 | CSS snippets affect documented document selectors only and cannot restyle protected research signals or app chrome. | Source/provenance legibility and security | Stable and implemented |
| D-015 | Scholium supports multiple kinds of long-form research. Researchers may organize bodies of writing with ordinary Works folders; Scholium does not register or manage projects. | Long-term product mission and Product Guide | Stable and implemented; project-management UI removed |
| D-016 | Scholium targets macOS 26 or later and uses Liquid Glass as the primary native material for navigation and controls. APIs newer than the selected compiler and SDK remain gated until the toolchain advances. | Personal-app modern platform baseline | Stable |
| D-017 | Callouts use seven protected semantic roles; all roles except Orientation retain visible text labels. Orientation is presented as an unlabelled guide while its semantic role, source identity, and accessibility metadata remain protected. Visual emphasis never establishes endorsement, evidence, or workflow state. | Knowledge-base semantic specification; Scholium provenance model | Stable and implemented |
| D-018 | Vector links render as a protected SF Symbol plus note name, retain exact punctuation in Source, and communicate neutral connection, support direction, or symmetric incompatibility through text as well as icon and color. | Scholium relationship model; accessibility requirements | Stable and implemented |
| D-019 | The default workspace uses Analyses, Topics, and Works as concise researcher-facing labels. Their role-scoped profiles share canonical YAML keys for recurring concepts, retain legacy aliases as read compatibility, and never perform automatic bulk migration. | Research workflow evidence; source-fidelity architecture | Stable and implemented |
| D-020 | Scholium may register several complete Triptychs; one window belongs to one Triptych, and different Triptychs open in separate windows. Shared services belong to one `WorkspaceStore`; presentation state belongs to each window session. | Product Guide §3.2; window/session isolation | Stable and implemented; sustained interactive acceptance pending |
| D-021 | Scholium's core academic workflow is completable without Obsidian; Obsidian import and interoperability are optional and must not become a core workflow dependency. | Product Guide §2.1; standalone academic workflow requirement | Stable target; clean-environment acceptance pending |
| D-022 | Reader and editor text size are controlled and persisted per window without changing source. The complete commands and shortcuts live in the View menu rather than permanent document chrome. | Apple accessibility guidance plus per-window presentation model | Stable and implemented; 200% manual acceptance pending |
| D-023 | Scholium does not require technical prompt logs, hidden instructions, model parameters, token counts, paragraph-level AI provenance, or a separate AI audit dashboard. Agent responses foreground concise academic change. | Scholarly Dialogue boundary | Stable target; response presentation acceptance pending |
| D-024 | External agents, Zotero, and research skills are optional extensions; the manual academic workflow remains complete without them. | Product Guide and standalone workflow requirement | Stable target; clean-environment acceptance pending |
| D-025 | Document, HTML, PDF, and DOCX export are deferred after 0.1, not permanent product prohibitions. | Product Guide release boundary | Stable target; export not in 0.1 |
| D-026 | One editor-only bottom **Research Strip** replaces Open Scholia and exposes direct one-word, role-valid functions: Dialogue, Develop, Review, and Fidelity for Analyses/Topics; Critique, Revise, Dialogue, Fidelity, and Manuscript for Works. One typed panel opens directly for the selected function; Target is fixed and Materials are selected inside. The bottom placement is a researcher-approved Scholium-specific macOS exception with complete menu, keyboard, focus, and accessibility parity, not Apple's visionOS Ornament component. | Researcher-approved function architecture; document-first composition; Apple macOS command-parity and accessibility guidance | Implemented; final manual accessibility and appearance acceptance remains open |
| D-027 | `triptych-document-layout.html` is the preferred, non-binding baseline for main-window composition and page logic. It may evolve when a real frontend capability needs a better UI home, provided the document remains primary, semantic distinctions remain visible, and no layout decision is treated as a backend contract. | Researcher-reviewed prototype; native macOS adaptation | Stable and implemented; manual visual and assistive-technology acceptance pending |
| D-028 | Prompt templates and assembled technical instructions are configuration, not scholarly workflow content. They are visible and editable only in **Settings → Research Guidance**; Dialogue, Critique, and future research workflows expose scholarly inputs and a direct Settings link but no template picker, preview, or one-run prompt editor. | Researcher-approved prompt-mechanics boundary; Settings and text-entry guidance | Stable target; current Critique interface requires alignment |
| D-029 | **Research Guidance** manages both **Prompt Templates** and **Skills** while preserving them as distinct item types. User skills are editable file-backed packages discovered only at `.scholium/skills/<skill-id>/SKILL.md`; **Research Methods** activates compatible Triptych-local primary, supplemental, and exact Practice bindings without adding package IDs or a one-run picker to the Strip. Permitted official packages duplicate under a new independent identifier; protected packages expose no reset or replacement path. A global Recovery inventory remains reachable for missing or malformed packages, confirms complete replacement, and preserves an undo snapshot whenever a current package is displaced. | Researcher-approved skill-management and recovery boundary; local-first storage and Settings guidance | Stable and implemented; final Beta accessibility acceptance pending |
| D-030 | **Recent Notes** is a per-window, vault-qualified, bounded MRU list exposed through the Navigate menu. It remains independent of chronological Back/Forward history and derived Search state, persists with the window session, and adds no permanent chrome. | Researcher return-to-work task; Apple macOS menu and recents conventions | Stable and implemented |
| D-031 | Beta Search uses deterministic local FTS5 retrieval. Exact Topic title or alias resolution may expose direct resolved graph connections in a separate Related section; graph relations never alter lexical ranking. Vector search, embeddings, AI ranking, and chat-style query interpretation are excluded from Beta. | Researcher-approved scholarly retrieval boundary | Stable and implemented; bounded Title/Alias/Heading/Body ranking acceptance passes, while broader evaluation remains pending |
| D-032 | Scholium has no Triptych Home. With no selected note, the narrow left-middle Library is the **Triptych Interface**. Its navigation material extends through a visually titleless native window frame while preserving the standard traffic-light controls and accessible window identity. Its fixed-size top-trailing ellipsis has no redundant disclosure indicator. Selecting a note keeps that Interface fixed and reveals the document toward its trailing side; **Collapse Note** retracts it without discarding the open-tab session. The Interface is visually above the document like a document box or drawer. The resize is calm, spatially coherent, interruptible, and immediate under Reduce Motion. | Researcher-approved simplification; document-first principle; Apple window and motion guidance | Stable and implemented; clean-account plus retract/reveal focused automation pass, while manual motion and assistive-technology acceptance remain pending |
| D-033 | Research Unit is a minimal YAML scope declaration presented as **Research Status** inside Properties. It stores only Scope and optional Limitations, creates no new note type or panel, and never stores app-owned timestamps or graph-derived coverage. | Researcher-approved epistemic-scope model; Apple hierarchy, progressive-disclosure, and concise-label guidance | Stable and implemented; new Analysis creation enforces Scope, while dedicated long-source progress and manual visual/accessibility acceptance remain pending |
| D-034 | The floating document context surface contains one restrained mode/outline control group and one role-aware Properties disclosure. Both compact surfaces share one height and centerline; their complete combined width equals the document measure, and the expanded single-layer panel uses that same width. Scrolled prose remains perceptible through the glass beneath a soft shadow. Secondary facts disappear before crowding, and text-size commands remain in View. | Researcher-approved prototype refinement; Apple disclosure, toolbar-frequency, materials, motion, and accessibility guidance | Stable and implemented; focused geometry and disclosure automation plus disposable-fixture visual inspection pass, while Reduce Transparency, Increase Contrast, VoiceOver, and Full Keyboard Access acceptance remain pending |
| D-035 | Scholium uses one semantic color-token vocabulary across native and WebKit surfaces. The approved light appearance combines Ivory Leaf, Parchment, Carbon Ink, Vermilion Copper, and a plural semantic chorus; the approved dark appearance is an evening-library composition of Walnut, Cordovan, Parchment, and Luminous Copper rather than a mechanical inversion. Attention, Confirmed, Destructive, Information, teal Support, plum Incompatible, and explicit violet Agent Authorship remain distinct and never establish philosophical value by color alone. | Researcher-approved layered-humanist palette; Apple semantic-color, appearance, contrast, and non-color-cue guidance | Stable and implemented; automated light/dark token-value, vocabulary, relationship-variant, and foreground-contrast checks pass, while full manual inactive-window and accessibility appearance acceptance remains pending |

## 12. Future and unresolved design questions

Do not present these as completed behavior:

- sustained interactive acceptance of restored multiwindow sessions and native window grouping;
- final usability evaluation for heading outline, saved-search management, and Recent Notes;
- sustained manual VoiceOver, Full Keyboard Access, Voice Control, contrast, scaling, and localization verification across the CodeMirror/WebKit boundary;
- keyboard and assistive-technology acceptance must be re-established before
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
