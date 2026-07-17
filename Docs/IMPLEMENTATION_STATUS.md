# Scholium Implementation Status

**Audited:** 2026-07-18
**Target authority:** [SCHOLIUM_SPEC.md](SCHOLIUM_SPEC.md)
**Scope:** current reachability, verification evidence, migration debt, and open
acceptance only. This ledger cannot redefine the target specification.

## Reachable target behavior

- Multiple complete Scholium Triptychs, each with independently chosen **Analyses**, **Topics**, and **Works** locations. One Triptych is selected per window; File commands create a Triptych, open a registered Triptych in its own window, or create another independent window for the focused Triptych.
- Portable `.scholium` state beside Works for the manifest, vault-wide Properties configuration, Critique settings and associations, stable note identities, imported Unclassified Markdown, and researcher-managed Skills packages under `.scholium/skills/<skill-id>/SKILL.md`.
- Application Support state for Human Review, comments, Dialogue, checkpoints, search indexes, CSS snippets, and machine-local access data.
- Exact-source `NoteDocument`, targeted YAML changes, transactional autosave, external-change conflicts, symlink/traversal rejection, and readback verification.
- Safe create, duplicate, move/rename, Set Aside, Trash, exact-path Put Back, and permanent deletion through `VaultRepository`. Confirmed permanent deletion removes the source note and a Work's separate current Critique Markdown together with repository versions, Human Review/comments, every Dialogue containing either stable identity, Critique associations, portable identity state, and every checkpoint containing either identity. A durable transaction journal restores exact pre-commit state after ordinary failures or process interruption and completes privacy cleanup after the commit decision; a concurrently recreated path is never replaced and retains its recovery version for explicit resolution.
- Confirmed app moves use a Triptych coordinator that preflights the destination and every vault-qualified incoming-link revision, then updates only links that both the supplied and freshly derived workspace graphs resolve to the moved note. Ambiguous or stale resolutions are never guessed.
- Multi-file move and Unclassified-classification failures roll back exact bytes where revision checks still permit it. If a concurrent change prevents complete rollback, Scholium persists a file-by-file recovery record outside the vaults and keeps a visible recovery surface; it does not claim cross-filesystem atomicity.
- Stable identities and app-owned Human Review/comment state follow confirmed app moves.
- Imported Markdown is copied into Unclassified, remains editable, and can be classified into any Triptych vault without changing the original external file. Destination creation and Unclassified-copy removal use duplicate-safe rollback and persistent recovery when rollback cannot be verified.
- Human Review for Analyses and Topics with fingerprint-bound Qualified/Unqualified verdicts, a required concise review note, drafts, and source-anchored Comments. Comment storage and decoding require an anchor; note-level judgment remains the Review note rather than a second whole-note Comment field.
- Works use one current, separately attributed Critique document under `Works/Critiques` and an editable Triptych-wide prompt template. Every request updates the current target path and fingerprint, records a checkpoint-bound request round, and preserves earlier Critique source in checkpoint history. New and migrated Critiques carry targeted provenance metadata; their bodies remain read-only in Scholium, while ordinary external edits remain allowed.
- Critique provenance appears before the body with agent attribution, target Work and fingerprint, current/earlier-version and metadata-mismatch state, plus structured Specific Finding destinations. Explicit target lines, headings, and unique quotations open the corresponding Work passage; ambiguous quotations are never guessed. App lifecycle commands allow movement within `Critiques`, Set Aside, Trash, and Put Back but block crossing the Critique boundary or duplicating a current Critique.
- The editor-only Research Strip exposes **Dialogue · Develop · Review ·
  Fidelity** for Analyses and Topics and **Critique · Revise · Dialogue ·
  Fidelity · Manuscript** for Works. Review combines Human Review and Comments
  without creating an agent packet. Agent-facing typed panels lock the Target
  and select read-only Materials, Whole or Passage scope, applicable Comments,
  and Content or Citations checks. The toolbar, sidebar, generic Open Scholia
  doorway, omnibus Scholia panel, and duplicate Critique request sheet are no
  longer reachable.
- Conditional resources use a same-run, read-only preflight. The external
  agent finalizes the applicable methods, templates, and checklists—including
  an explicit empty selection when the complete primary method is sufficient—
  through `function select-resources`. The deprecated `select-methods` spelling
  remains an undocumented Beta compatibility alias. The preflight has already
  persisted the normal checkpoint
  and Dialogue or Critique record; finalization retains that run, record,
  checkpoint, and preparation identity, while completion remains unavailable
  beforehand. The Strip exposes no method controls, and the finalized packet
  records only the exact resources attached to that run.
- Dialogue is note-nonmutating by default and creates no checkpoint. It may
  read the fixed Target and selected Materials and append attributed responses
  to Dialogue/Note History. It preserves the initial
  researcher Comment plus chronological researcher follow-up Comments and
  attributed agent Responses; an external agent must prepare Develop or Revise
  before changing the current note. Develop, Revise, Manuscript, and Critique
  create **Before Agent Work** checkpoints; Review and Fidelity do not.
- The shared function API persists revision-bound preparations and attributed
  completions in the existing Dialogue or Critique authorities. Write-capable
  runs first persist their exact final Target revision as **Awaiting Fidelity**.
  The external agent then prepares an independent read-only Fidelity child
  against that final fingerprint with the same Materials, scope kind, Comments,
  and checks; the parent advances only after a later completion links that
  validated child. Direct Fidelity outcomes on the write run are rejected.
  Missing checks remain **Unverified**; later Target, Material, or Comment
  changes make outcomes stale. Exact Fidelity evidence keys reuse completed
  evidence instead of persisting a duplicate audit, without implying that
  Scholium ran an agent or background audit.
  Reuse and Manuscript child selection consult the authoritative record stores,
  so a committed completion remains discoverable even while a derived-snapshot
  refresh is repeatedly failing.
- Self-contained Triptych checkpoints outside the vaults, latest-ten automatic retention, manual checkpoints, comparison, selective note restore, complete restore, and Finder access. Restore defers automatic retention until the selected checkpoint has been applied, so creating the pre-restore safety checkpoint cannot remove the selected recovery source mid-operation.
- Note History separates Human Review, comments, Dialogue, Critique association, and checkpoint versions; ordinary autosaves do not create visible versions.
- Direct CLI note create/replace/move/Set Aside/Trash/delete commands. Each
  invocation creates one snapshot-mode `WorkspaceRuntime` and routes workspace,
  discovery, document, Dialogue, Skill, workflow, and Zotero operations through
  `ScholiumApplication`; the CLI no longer constructs repositories, indexes,
  registries, watchers, research stores, or Zotero server authorities.
  Existing-note mutations require the
  current SHA-256 fingerprint. The shared Application operations now give GUI
  and CLI the same trust behavior: ordinary moves safely rewrite resolved
  incoming links, moving `Set Aside/<path>` to Trash uses the canonical
  `Trash/<path>`, creation records portable stable identity, and permanent
  deletion coordinates research-record, checkpoint, history, and identity
  cleanup.
- Canonical Vector-Link v1 semantics: `[[B]]`, `+[[B]]`, `-[[B]]`, and `?[[B]]`; neutral and transitive paths never become evidence, and retired typed aliases/arrows remain source-preserving neutral links with diagnostics.
- One workspace-scoped `GraphSnapshot` resolves deterministic links across the Triptych while preferring same-vault matches. Incoming, Outgoing, Research, Search diagnostics, and Attention consume this graph; the legacy parallel relationship parser has been removed.
- CodeMirror Source/Live Preview, sanitized Read mode, callouts, footnotes, protected CSS snippets, and bundled Alegreya/Victor Mono document fonts.
- The editor boundary now uses one typed, identity- and generation-checked
  `callAsyncJavaScript` dispatcher with a checked Swift mirror, full-buffer
  reconciliation, CRLF reconstruction, bounded recovery snapshots, and
  deterministic content-process reload. Native focused Format, Insert,
  Paste as Markdown, contextual table, and Add Comment routes target only the
  active editor session. TypeScript tests cover exact commands, guarded
  list/table behavior, inert clipboard conversion, single-step undo/redo,
  Lezer representative projection, and shared Contracts semantic fixtures; a
  native WKWebView test covers exact CRLF editing, recovery generation, and
  Paste as Markdown. It now also covers raw UTF-8/UTF-16 preservation for
  decomposed accents, emoji, Arabic/Hebrew, and selection-preserving dirty
  mirror recovery. Isolated QA also proves Live Preview editing and
  commit-before-Search plus native Format, Insert, and editor-context command
  reachability, plus a Debug-only fault-injected dirty-buffer reload followed
  by a byte-exact Read commit. Complete real editor VoiceOver, Voice Control,
  Dictation, text-service, CJK IME, appearance, and sustained-performance
  acceptance remains open.
- Shared SQLite FTS5 human/CLI search contracts, Unicode/CJK behavior, deterministic Connection diagnostics, and one canonical Attention contract. Attention is limited to possible-orphan structure, Changed Since Review, broken or ambiguous Connections, explicit source-anchored reliance on an Unqualified Analysis, malformed metadata, and unresolved identity. Every item is dismissible; the Triptych-local duration is stored in `.scholium` and defaults to seven days, while per-item dismissal deadlines remain machine-local. Retired workflow gates and governance queues are absent from the Research inspector and Attention surface.
- Per-vault Properties fields, explicit display order, human-editable allowlists, and starting disclosure state; the role-neutral Research Status presentation/editor for the bounded research_unit mapping; sparse Triptych navigation; Settings-only Dialogue and Critique prompt templates; bundled and Triptych-local file-backed Skills; and localhost-only read-only Zotero access.
- The Beta Skill boundary is packaged as protected, typed, bounded resources:
  the catalog separates stable function support from legacy modes and automatic
  System activation; bundled and Triptych-local resources reject traversal and
  symlink escapes; permitted official duplication copies the complete bounded
  package under a new local ID; package revisions cover `SKILL.md`, references,
  templates, and evals; function assembly records only the conditional
  resources actually loaded; and Manuscript coordinates independently
  permissioned child runs rather than flattening them.
- Exactly five bundled Workflow packages remain: Development, Critique,
  Revision, Content Fidelity, and Manuscript. Dialogue remains System
  infrastructure, Human Review has no Skill, and Source Analysis and
  self-evolution are not Strip functions or Workflow packages. The bundled
  catalog now restores Source Analyzer as a complete copy-on-adoption
  Researcher Skill with `analyze` mode and no supported Research Function; the
  Skills CLI can assemble it directly with Core Protocol, and official
  duplication copies its complete bounded reference set.
- Dialogue optional modules and selected Philosophical Practices now receive
  flexible, evidence-sensitive methodological effort. Every selection is
  genuinely considered, but only warranted and materially useful influence is
  reported; no selection may be silently skipped and no filler finding is
  manufactured. Academic Outcome and universal integrity rules remain
  mandatory. Practice selection cannot change Target, Materials, permissions,
  checkpoints, or write boundaries.
- The protected Core Protocol now makes the shared scholarly orientation explicit: every package is philosophy-facing, truth-pursuing without claiming automatic truth, fidelity-caring, and knowledge-base-constructing. CLI, file, metadata, and MCP operations remain subordinate mechanisms, while application design and coding stay under separate development Skills.
- The bundled catalog includes an optional copy-on-adoption APA 7 citation-verification starter in the Researcher ownership class. It is editable after adoption, never activates automatically, and does not establish a universal citation convention.
- Citations is available inside Fidelity only after Core validates an explicit
  Triptych-local package-and-style binding. Research Guidance distinguishes a
  bundled starter, installed candidates, an active binding, legacy package-only
  state requiring style repair, and malformed binding state. The selected
  semantic citation style and its exact resource revision enter the phase
  snapshot and Fidelity evidence key; neither the app nor CLI scans global
  plugin directories or infers capability from filenames.
- **Research Guidance → Skills → Research Methods** now activates compatible
  Triptych-local Researcher Skills for Develop, Critique, Revise, Fidelity, or
  Manuscript as an optional primary replacement, supplemental methods, and
  exact Practices. Saves are revision-checked and role/function validated; the
  Strip receives no package IDs or method controls.
- Opted-in Triptych-local Researcher Skills support explicit Research Guidance
  maintenance through a copyable complete-current-package proposal request,
  returned whole-package JSON import, per-file comparison, deterministic
  structural validation, separately attributed revision-bound evaluation,
  confirmation, atomic replacement, durable snapshot, and restore. Bundled
  System and Workflow packages remain immutable, and maintenance is never
  routed from a research function. Proposed packages pass the same declared
  resource, Practice foundation, citation-resource, dependency, and cycle rules
  as installed packages. Replacement uses descriptor-relative no-follow I/O and
  rejects linked control ancestors or parent substitution without touching the
  redirected filesystem state. A global Recovery inventory loads independently
  of the selected or valid package, preserves valid snapshots when another
  entry is corrupt, and can reinstall a missing package or replace a safely
  fingerprinted malformed package. Restore confirms complete replacement,
  rechecks the current present-or-missing state, and snapshots any displaced
  package for immediate undo. Snapshot enumeration and reads remain
  descriptor-relative and no-follow.
- The bundled catalog includes a separate optional copy-on-adoption Prose Control starter in the Researcher ownership class. It carries an editable academic-style profile and semantic preservation ledger, composes with the official Writing workflow for permission and durability, never activates automatically, and does not establish a universal Scholium prose style.
- Dialogue response defaults are stored per Triptych. Each Dialogue panel keeps
  Academic Outcome fixed, lets the researcher select the five optional response
  modules for that request, and persists the effective immutable response
  contract. An explicit empty selection therefore requests Academic Outcome
  only; changing Settings after preparation cannot change the recorded entry.
  Legacy entries remain readable with an explicit fallback label. The optional
  external Zotero MCP descriptor is separate from the built-in localhost
  reader; ordinary status only reports configuration, while an explicit
  `--probe` performs the read-only initialize lifecycle check.
- An atomic v2 workspace registry stores multiple stable Triptych assignments while preserving the legacy one-workspace files unchanged. Window snapshots persist selected Triptych identity, and shared registry actors prevent per-window last-writer duplication.
- Retained compatibility readers are fixture-audited: every supported legacy vault-role spelling re-encodes canonically; legacy property aliases remain read-only projections with canonical-key precedence; v0 Triptych, sparse window, per-vault presentation, and retired Search-scope records remain readable. Missing historical fields receive bounded defaults, while malformed present fields and unknown roles fail without rewriting their files.
- The compiler-enforced module and runtime boundaries documented in
  [IMPLEMENTATION_ARCHITECTURE.md](IMPLEMENTATION_ARCHITECTURE.md) are
  reachable. App and CLI depend only on Contracts plus Application; Core is not
  a public product and cannot leak through imports or Application's public
  symbol graph. One live Application runtime serves the macOS adapter while
  per-window controllers retain independent UI state. Package, source, I/O,
  and symbol-graph guards enforce those ownership boundaries.
- Confirmed app moves and externally reconciled renames migrate stable identity plus Note History references, Human Review/comments, Dialogue references, Critique associations, and window snapshots. Ambiguous external identity changes require explicit confirmation rather than guessing.
- The Research inspector shows only the current Analysis's Zotero source or the unique keyed Zotero items of Analyses named by outgoing links in the opened Topic or Work. Analysis lookup uses item key, DOI/ISBN, citation key, then exact title + author + year; non-unique matches remain visibly ambiguous. Compact metadata includes authorship, publication, volume/issue/pages, stable identifiers, and citation key, with abstract, publisher, edition, URL, collections, and modification time under disclosure when available. Incoming backlinks, bibliography entries, transitive paths, Unclassified notes, and the wider library are excluded. The only source action is **Open in Zotero**; Scholium does not enumerate or open attachments.

## Adopted boundaries with remaining acceptance work

- The specification defines a minimal nested `research_unit` mapping with
  `scope` and optional `limitations`, presented as **Research Status**. The
  current Properties region has a role-neutral Research Status group and a
  targeted two-field editor. Absent, declared, and invalid mappings remain
  distinct; nested edits are serialized as a bounded mapping and unrelated
  source bytes remain covered by Core tests. New Analysis creation offers
  **Declare Now** or **Not Yet**. Not Yet writes no mapping or sentinel and
  blocks only **Complete Review** until later declaration. Existing notes
  receive no migration. Focused tests are present; the current refactor still
  requires final visual, accessibility, and repository verification.
- Creation and modification time are app-owned History data rather than properties that researchers or agents fill. Analysis, Topic, and Work default property profiles no longer expose timestamp fields, repository saves always pass no timestamp mutation, and the registered Analyses vault now resolves to the current project-neutral `analysis` profile unless a legacy schema marker explicitly requires compatibility. Existing timestamp YAML remains exact preserved source. App-owned version history remains separate from Markdown.
- Continuous long-source analysis remains a supported research practice: one
  source-level Analysis can be updated as bounded units accumulate, and the
  current Research Status editor records scope and limitations. Scholium does
  not ship a Source Analysis Workflow package or Strip button. It does ship the
  independent Source Analyzer Researcher Skill for a directly instructed agent
  with access to the source; Scholium need not store the source or control
  Zotero. Any later Analysis-note update remains a separate researcher-
  authorized action. A dedicated long-source progress presentation remains
  future work.
- Recommended Bibliography is reachable only for an Analysis in the Research
  inspector, after Zotero and before Connections. Its compact presentation
  labels candidates as **Reading leads, not evidence**, supports optional goals
  and purpose, and keeps refresh failures from replacing prior results. The
  dedicated Contracts/Application/Core/CLI lifecycle snapshots Source Analyzer,
  accepts zero recommendations, conservatively discriminates identities, and
  stores records atomically in `.scholium/recommended-bibliography.json`
  without changing Markdown or Zotero. Focused controller, executable CLI, and
  disposable UI automation cover routing and transport; philosophical value
  and genuine spoken VoiceOver judgment remain researcher-owned acceptance.
- New default Analysis Properties replace contextual project-relevance and
  app-owned timestamp fields with optional paired Debate Importance and Debate
  Scope fields. Debate Importance accepts only a whole integer from 0 through
  10, requires its scope, and has no pass grade; Project Relevance is inactive,
  while existing relevance or timestamp YAML remains byte-preserved as legacy
  or custom source.
- Protected Skill identifiers cannot be replaced by a Triptych-local package. A conflicting local package remains visible as an invalid, recoverable item so the researcher can rename or delete it; the bundled package remains separately visible and authoritative.

## Removed from the reachable target UI

- Proposal/Revision review sheets.
- Research Task and Research Session sheets.
- Agent Assessment and legacy Agent Review.
- Active-note HTML/PDF export.
- Canvas has been removed from the product and active state. The only retained path is a read-only decoder that maps legacy window snapshots to the document surface without preserving or writing Canvas fields.
- Optional Zotero data-folder/SQLite access.
- Additional-vault and All Notes presentation.
- Generated `_index.md`, `_agent-index.json`, and `_agent-context.json` paths.

The obsolete Proposal, Research Session, workflow-bridge/readiness/lint, old Review-store, and Add Dated Reference implementations have been removed from the app, Core, and CLI. Existing legacy files on disk are deliberately left untouched: Scholium neither reads them into the current interface nor deletes or rewrites them. Researchers may archive those files manually in Finder.

## Current interface consolidation

- The current app follows the scoped controller, typed presentation,
  stable-identity document-session, metadata-authority, and semantic-token
  boundaries recorded in
  [IMPLEMENTATION_ARCHITECTURE.md](IMPLEMENTATION_ARCHITECTURE.md). Native and
  WebKit palette parity, appearance mappings, relationship variants, and
  contrast floors are covered by automated architecture tests. The
  specification remains the authority for the palette values and their
  meanings.
  Document typography now exposes Body, heading-level, and Exact Source roles;
  interface typography exposes identity, section-title, row-title, and metadata
  roles. The dormant AppKit editor implementation now consumes that same 12pt
  body and heading contract rather than retaining a separate 17pt baseline; it
  has no production construction call. Both Connection inspectors consume one
  direction-aware title, symbol, and semantic-color presentation. The 28pt
  preferred and 20pt minimum custom target thresholds are centralized without
  changing native control sizing; the floating document context surface retains
  its feature-owned 40pt height.
- The native shell follows the specification's workspace topology: one
  reflowing Library sidebar, one dominant document region, and one optional
  trailing Research inspector. The former separate workspace-navigation and
  note-list columns are no longer reachable.
- The current tree uses separate Onboarding and Workspace metrics, one stable
  configured `NavigationSplitView`, one vault-qualified selected document per
  window session, and decorative light/dark artwork in the no-note detail.
  Completing first-run setup is the sole application-driven expansion;
  selecting or replacing a note does not contract the configured workspace.
  The standard Show/Hide Sidebar toolbar item and View command now own Library
  visibility without clearing the document; the former Collapse Note command,
  custom `<<` control, and AppKit suppression of the native item are absent.
  `NativeWindowTabCoordinator` gives complete window scenes one
  common AppKit tabbing identity and groups **Open in New Tab** with its source
  window. Custom document tabs, Back/Forward, Recent Notes, and Quick Open are
  absent from active state and commands; legacy tab/history fields remain
  decode-only. Focused native-tab UI automation verifies grouping, note-derived
  titles, standard tab commands, and `Command-W`; automated responsive journeys
  verify stable frame behavior at 1380, 1080, and 900 points. Manual assistive-
  technology and system-setting acceptance remains pending.
- The document context surface groups Read/Live Preview/Source and heading
  outline in one restrained control surface followed by one role-aware
  Properties disclosure. Both compact surfaces use the same 40-point height
  and vertical centerline; together with their 10-point gap they occupy the
  same centered 920-point measure as the Read/editor body. The expanded
  single-layer panel also occupies exactly 920 points. Current source replaces
  the former custom glass recipe with an opaque editorial surface and fine
  boundary; initial editor clearance scrolls away so later content may travel
  beneath it. Summary facts progressively reduce before crowding. Document
  text size remains in **View → Document Text Size** and its keyboard
  shortcuts instead of occupying permanent document chrome.
- The Library consolidates research-state, tag, metadata, and sort choices in one native **Filter** menu while keeping visible Unreviewed and Unqualified task toggles. The bounded research-state filters remain Changed since review, Needs attention, Explicit connections, and Malformed metadata. Analyses prefer author/year secondary metadata, Topics retain relative modification time, and Works prefer document kind/lifecycle state when available. After one exact Debate Scope is selected through the metadata filter, the Library also permits numeric high-to-low Debate Importance sorting with unrated matching Analyses last; it does not compare ratings across scopes.
- Search is one centered Spotlight-style overlay whose empty state shows **This
  Note**, **This Vault**, and **Triptych** immediately without an empty results
  sheet. Exact title, alias, filename, and path matches rank above body matches,
  so Search also owns known-note navigation. `Command-F` temporarily enters
  **This Note** and dismissal restores the ordinary general scope unless the
  researcher explicitly changes it. Dismissal cancels pending work and rejects
  stale results. Presenting Search first flushes the registered editor and does
  not open the retrieval surface when that save fails, so navigation cannot
  race an uncommitted Live Preview edit. Beta Search has no vectors, embeddings,
  AI interpretation, AI ranking, or chat-style interface. Focused architecture
  and UI journeys verify visible scopes, current-note results and no-results
  state, compact geometry, stable dismissal, immediate rejection of a prior
  query's result projection, and the commit-before-Search boundary.
- One bottom editor Research Strip opens the selected one-word function
  directly. It is absent when no note is open, reserves editor space rather
  than covering prose, retains every role-valid function at compact widths,
  and has direct Research-menu parity. `Command-Shift-D` opens Dialogue;
  `Command-R` opens Review for an Analysis or Topic and Critique for a Work.
  Agent-facing Materials are selected only inside the shared panel, while
  Target identity and revision remain fixed for that presentation. Review uses
  the combined Human Review and Comments presentation without Materials.
- Note History presents Dialogue as a concise, role-labelled scholarly exchange and lets the researcher append a follow-up Comment or record an attributed agent Response without exposing prompt mechanics. The default Dialogue response contract asks agents to foreground academic changes and unresolved questions or required researcher review.
- Note History and the Research inspector now share one mutually exclusive trailing context region. Switching between them is an atomic per-window state change, so the document does not acquire competing trailing panels.
- Unclassified opens as a centered classification surface. Set Aside and Trash
  remain anchored below Library and rise as mutually exclusive compact opaque
  editorial panels over the preserved Library geometry; dense note rows and
  destructive confirmations remain opaque and native.
- Current source has removed Scholium-owned Liquid Glass, blur, vibrancy, and
  regular-material recipes from the Library, document context, Properties,
  Search, Research Strip, lifecycle, transient-status, and primary-action
  surfaces. These use semantic opaque planes, fine boundaries, and restrained
  elevation while system-owned controls keep native macOS appearance. A
  current bounded QA matrix passes native sidebar and ellipsis behavior,
  responsive widths, Search, Properties and inspector presentation, light/dark
  Research Strip behavior, 200% document text, and the canonical journey.
  This automated evidence does not close real system-setting or assistive-
  technology visual acceptance.
- First launch uses the narrow Onboarding measure and left-middle position for a
  five-step native flow with no scrolling page: Welcome, Analyses, Topics,
  Works, and final name/authorization. Each folder is chosen through a standard
  Open panel and progression remains disabled until the current choice is
  complete. Initial completion clears the setup route before Triptych
  activation publishes a vault, then expands once into the stable Workspace
  measure. Later **New Triptych…** and **Manage Triptychs…** editors remain
  separate.
- At wide widths (`>= 1200`) the document keeps its reflowing trailing Research Inspector or Note History context. Medium and compact widths collapse that context before constraining document content, and reopen it through the same toolbar routes as a scoped sheet. At compact widths the document is the initial surface and Library remains available through the standard sidebar command.
- Slow initial graph publication no longer aborts workspace activation or
  blocks lexical Search. Graph work continues independently in the Application
  runtime; Search waits only for the vault indexes required by its selected
  scope. The last good derived snapshot remains visible with explicit current,
  stale, or failed status and affected-vault evidence; committed writes report
  post-commit refresh failure without inviting unsafe mutation retry.
- Vault inventory and FSEvents now derive relative paths by normalized URL components rather than character-count slicing. Equivalent macOS paths such as `/tmp` and `/private/tmp` therefore preserve the complete vault-relative path, remain containment checked, and no longer bypass role-specific behavior such as Critique provenance.
- External-edit conflict recovery now binds the complete editor and disk sources to visible SHA-256/byte-count revision identities. The comparison labels editor-only and disk-only lines without inferring authorship, returns focus to the editor, and keeps dense diff content on an opaque system surface. **Compare Changes** is the nondestructive default; **Reload from Disk** is destructive and accepts only the exact disk revision shown. If the file changes again, the local buffer remains open and Scholium requires a fresh comparison. Reload uses the document's incremental projection path rather than a full-vault rescan.
- The interface variable layer now exposes the approved semantic surface,
  elevation, boundary, typography, feature-metric, motion, and provisional
  renderer-rhythm contracts. Repeated Library, Search, Properties, context,
  lifecycle, transient-status, and Research Strip treatments consume those
  contracts; surface roles resolve their own default boundary and elevation,
  with permanent document, navigation, apparatus, and evidence planes defaulting
  to no elevation; structural partitions use one environment-aware semantic
  rule rather than local line literals. Native controls retain native sizing
  and state appearance. Document prose remains 12-point Alegreya, production
  mono remains Victor Mono, and the preview catalog contains the pending
  Victor/system-mono proof plus injectable contrast, transparency, motion, and
  active-window states for deterministic component review. Thirty-two focused
  architecture tests currently cover these contracts and prohibit custom glass
  or material APIs in production Swift source.
- The former atmospheric artwork/material Library treatment is superseded.
  Current source presents Library, document, and trailing apparatus as opaque
  editorial planes separated by tone and fine rules; note titles and
  apparatus headings use the approved content-derived editorial hierarchy
  while operational controls retain system typography. Existing native
  sidebar, ellipsis, responsive, Search, Properties/inspector, light/dark, and
  200% text journeys pass against the current Scholarly Editorialism source and
  remain bounded automated behavior and geometry evidence, not final visual
  acceptance. Real Increase Contrast, Reduce Transparency, Reduce Motion,
  inactive-window, mixed-script, and assistive-technology acceptance remains
  open.
- A fail-closed release-to-release QA gate now copies one disposable Triptych,
  seeds byte-hostile Markdown fixtures, launches the baseline and candidate
  sequentially with one isolated application home, and compares path, byte
  size, SHA-256, permissions, and modification time after each launch. The
  portable-state allowlist is explicit and retained with the manifests and
  `.xcresult` evidence. After an identical-build harness proof, a distinct
  preserved baseline and current candidate also passed with all 195
  authoritative files unchanged.

Manual accessibility and visual acceptance is not yet complete. Automated responsive acceptance passes at 1380, 1080, and 900 points using the real window frame plus stable toolbar and menu routes, and the current 200% document-text journey passes. These tests deliberately avoid treating sidebar-descendant snapshots as a state oracle and do not claim manual visual or assistive-technology acceptance.

## Remaining completion work

1. Complete manual Full Keyboard Access, visual 200% text, localization, and real system-setting propagation acceptance for Light/Dark appearance, Increase Contrast, Reduce Transparency, and Reduce Motion. Complete the editor-specific real VoiceOver, Voice Control, Dictation, standard text-service, Simplified and Traditional Chinese, Japanese, Korean, dead-key, emoji, bidirectional-cursor, composition-conflict, and composition-recovery journeys. Existing automated tests prove source preservation and bridge policy but do not substitute for those operating-system interactions.
2. Approve the proposed strict p95 thresholds, freeze and exactly tag a clean reviewed commit, package that exact source, and run the packaged Release-app G7 protocol against frozen RDF-1 on Reference Machine R1. Complete-boundary instrumentation, the external XCUITest driver, strict report validator, thermally bounded fail-closed 5-warm-up/30-sample runner, build provenance, and privacy-safe environment capture are implemented. Warm Search and Read reuse one process; only process-boundary metrics relaunch. Internal SQLite and semantic-projection microbenchmarks remain regression checks only.
3. Continue explainable lexical-ranking evaluation beyond the current 2,056-note disposable collision fixture, including broader ranking-usability review and eventual release-owner approval. The current field-weighted contract ranks Title, Alias, Heading, and Body matches deterministically, verifies equal-rank path ordering, and labels their context explicitly. Beta remains deterministic local SQLite FTS5 plus separately labelled direct graph relations; vector search, embeddings, AI ranking, and chat-style search are explicitly out of scope.

Permanent deletion no longer advertises checkpoint or Note History recovery for deleted content. The coordinated implementation, destructive confirmation, checkpoint invalidation, durable recovery notice, file-by-file inspection, and record-only resolution paths are verified on disposable filesystems.

## Verification evidence

This ledger keeps representative current evidence and the interpretation of
each result. Run-by-run XCUITest and repository-verify snapshots are
intentionally compacted. Temporary `/tmp` result bundles are not durable
evidence and are not described as retained after they disappear; superseded
details remain available in repository history. All research-content fixtures
were disposable. The optional Zotero MCP boundary was additionally exercised
against the running local service for bounded reads and against a disposed
temporary profile for one synthetic import; no live-library write or private
library value is retained in the evidence.

| Evidence class | Latest recorded result | Interpretation |
| --- | --- | --- |
| Repository verification | The 2026-07-18 complete `verify.sh` record passed the product-skill mirror and protected-reference guards, editor typecheck and 43 editor tests, reproducible bundle verification, deterministic RDF-1 at 800 notes with tree hash `5a7a320c43f19352056e59db88d55c27a340c5284d3c4872dfe43ca667a30319`, the complete Swift suite, executable workflow and Function CLI verification, public-Application symbol-graph isolation, and the SwiftPM production build. The verifier now resolves and exports the complete Xcode developer directory before invoking Swift, so SwiftUI macro availability is part of the reproducible repository path rather than ambient `xcode-select` state. | Repository/build evidence; no package was created and this is not packaged Release-app G7 evidence. |
| Beta Skill architecture | The five Workflow packages, protected System layer, function-aware dependency closure, citation bindings, guarded Researcher Skill evolution, Dialogue transport, bootstrap, and Zotero boundaries pass focused suites and the complete verifier. A disposable Settings journey also passed complete-package comparison, structural validation, revision-bound attributed fixture evidence, atomic Apply, byte-and-revision persistence after relaunch, Recovery selection, complete restore, and creation of an undo snapshot. Real local-service reads and an isolated synthetic import/read-back also passed. [Skills/README.md](../Skills/README.md) owns the package architecture and [REAL_WORKFLOW_ASSESSMENT.md](../Skills/evals/REAL_WORKFLOW_ASSESSMENT.md) owns the twelve field trials. | Structural and transport/gating evidence only. The supplied evolution evaluation was synthetic and establishes no philosophical quality; the researcher-owned field trials and manual accessibility acceptance remain open, so G10 and J-014–J-016 are not complete. |
| Focused Function contracts and CLI | Isolated focused runs passed Contracts, controller, Application mutation, installer, and Settings-state tests for per-request Dialogue modules, immutable response contracts, stale-result rejection, reset, routing isolation, application-bundled CLI installation, and preservation of a live Triptych activation during a broader Settings failure. The real executable lifecycle then passed cold-start help, version, doctor, strict option parsing, preferred `function available`, explicit Dialogue modules, immutable show/reply/completion, typed Dialogue promotion, Revise conditional-resource selection and fingerprint-checked edit, Awaiting Fidelity, independent Fidelity completion and parent linkage, reusable audit relinking, idempotent cancellation, Recommended Bibliography, stdin/file and JSON/Markdown transport, and the specified malformed, stale, wrong-role, target-duplication, confirmation, and premature-completion failures. | Executable transport, persistence, and orchestration evidence; philosophical adequacy remains researcher-owned. |
| Search and derived state | The focused SearchIndex suite passed against a synthetic 2,056-note collision fixture, covering deterministic Title/Alias/Heading/Body precedence, equal-rank path ordering, repeat-query stability, and safe replacement of an incompatible generated contract; an isolated UI run verified the same visible field-context order. Broader ranking-usability evaluation remains open. | Semantic and isolated UI evidence. |
| Current UI journeys | A 2026-07-17 complete-class run executed 58 journeys: 41 passed and 17 failed. Focused reruns then passed the canonical acceptance journey, selective checkpoint restore, stable-identity dirty external rename, ambiguous external-rename confirmation, application-bundled Scholium CLI installation in Settings, and Research Guidance Skill reachability and collision repair. The Settings journeys also verified that an unhydrated broad Settings projection no longer produces the misleading incomplete-Triptych management alert while a live activation exists. The remaining complete-class failures cover existing editor-command, Search, responsive/trailing-context, Zotero, Human Review dismissal, 200% text, and VoiceOver-state routes; the complete class has not yet been rerun green. | Automated disposable-fixture evidence. The focused note-safety and Settings routes are green, but the complete UI acceptance gate remains open and this is not packaged Release evidence. |
| Upgrade safety | `verify-qa-upgrade-safety.sh` passed a differential baseline/candidate run against one disposable Triptych and one isolated home. Baseline SHA-256 `587b93a0a710bac273601c1fa86ad4db1578702c6cf34884f525c3fb8df8000c` and candidate SHA-256 `b7b3e109cb37e83e4dd3d6c76dac26f04abac1fed019bf85ef518a446480e551` were distinct. All 195 files under Analyses, Topics, and Works retained exact path, size, SHA-256, permissions, and modification time after both launches. Only `.scholium/identities.json` and `.scholium/manifest.json` changed under the retained explicit portable allowlist. | Differential disposable-fixture upgrade evidence for these two QA builds. Future releases must rerun the gate with their own preserved baseline and candidate; this is not installed-app or private-vault evidence. |
| Performance | Complete-boundary instrumentation, the external XCUITest driver, strict validator, privacy-safe capture, and fail-closed runner are implemented. Debug scenario runs validated the plumbing, but their temporary reports are not retained evidence. The canonical RDF-1 protocol requires the exact packaged Release app on R1 and five warm-ups plus 30 retained samples; no packaged Release gate run or threshold approval exists. | Scenario-only; G7 remains open. |
| Distribution | A 2026-07-15 local arm64 Release preflight passed signature, metadata, checksum, license, and resource checks, but recorded `source_clean=false` and no exact tag. | Local preflight; not clean-tagged G9 evidence or a release asset. |

The source-first beta policy is now fixed in `BETA_RELEASE.md`: the intended
`v0.1.0-beta.1` GitHub release pairs exact `GPL-3.0-or-later` source with an
optional ad-hoc-signed app-only ZIP and SHA-256 checksum. Bundle metadata and
the packaging script are aligned to that target. This records policy and
local packaging evidence only: no clean tagged artifact, external-install smoke
test, Developer ID signature, notarization result, or public GitHub release has
yet passed the release gates.
