# Scholium Implementation Status

**Audited:** 2026-07-16
**Authority:** [PRODUCT_GUIDE.md](PRODUCT_GUIDE.md) owns target behavior;
[DESIGN_HANDBOOK.md](DESIGN_HANDBOOK.md) owns the interface contract; [PRD.md](PRD.md)
synthesizes requirements. This ledger records current evidence only.

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
- Human Review for Analyses and Topics with fingerprint-bound Qualified/Unqualified verdicts, required concise review note, drafts, and line/whole-note comments.
- Works use one current, separately attributed Critique document under `Works/Critiques` and an editable Triptych-wide prompt template. Every request updates the current target path and fingerprint, records a checkpoint-bound request round, and preserves earlier Critique source in checkpoint history. New and migrated Critiques carry targeted provenance metadata; their bodies remain read-only in Scholium, while ordinary external edits remain allowed.
- Critique provenance appears before the body with agent attribution, target Work and fingerprint, current/earlier-version and metadata-mismatch state, plus structured Specific Finding destinations. Explicit target lines, headings, and unique quotations open the corresponding Work passage; ambiguous quotations are never guessed. App lifecycle commands allow movement within `Critiques`, Set Aside, Trash, and Put Back but block crossing the Critique boundary or duplicating a current Critique.
- The editor-only Research Strip exposes **Dialogue · Develop · Review ·
  Fidelity** for Analyses and Topics and **Critique · Revise · Dialogue ·
  Fidelity · Manuscript** for Works. One typed, target-locked function panel
  selects read-only Materials, Whole or Passage scope, applicable Comments, and
  Content or Citations checks. The toolbar, sidebar, generic Open Scholia
  doorway, omnibus Scholia panel, and duplicate Critique request sheet are no
  longer reachable.
- Conditional Workflow references use a same-run, read-only preflight. The
  external agent finalizes semantic method references—including an explicit
  empty selection when the primary method is sufficient—through `function
  select-methods`. The preflight has already persisted the normal checkpoint
  and Dialogue or Critique record; finalization retains that run, record,
  checkpoint, and preparation identity, while completion remains unavailable
  beforehand. The Strip exposes no method controls, and the finalized packet
  records only the exact resources attached to that run.
- Dialogue is read-only and creates no checkpoint. It preserves the initial
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
  by a byte-exact Read commit. The dated evidence and open manual matrix are in
  [EDITOR_INTERACTION_ACCEPTANCE.md](EDITOR_INTERACTION_ACCEPTANCE.md).
  Complete real accessibility, IME, appearance, and
  sustained-performance acceptance remains open.
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
  self-evolution are not Strip functions or Workflow packages.
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
- Dialogue response defaults are stored per Triptych, and each new Dialogue receives an immutable response-contract snapshot. Legacy entries remain readable with an explicit fallback label. The optional external Zotero MCP descriptor is separate from the built-in localhost reader; ordinary status only reports configuration, while an explicit `--probe` performs the read-only initialize lifecycle check.
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

- The Product Guide now defines a minimal nested `research_unit` mapping with `scope` and optional `limitations`, presented as **Research Status**. The current Properties region now has a role-neutral Research Status group and a targeted two-field editor. Absent, declared, and invalid mappings remain distinct; nested edits are serialized as a bounded mapping and unrelated source bytes remain covered by Core tests. New Analysis creation now requires and writes the declared scope through the native lifecycle sheet. Manual visual and accessibility acceptance is still open.
- The target profile requires Research Unit for new durable Analyses while keeping it optional for Topics and Works and preserving existing notes without migration. New Analysis creation now guides and enforces the scope; existing notes remain readable without bulk migration.
- Creation and modification time are app-owned History data rather than properties that researchers or agents fill. Analysis, Topic, and Work default property profiles no longer expose timestamp fields, repository saves always pass no timestamp mutation, and the registered Analyses vault now resolves to the current project-neutral `analysis` profile unless a legacy schema marker explicitly requires compatibility. Existing timestamp YAML remains exact preserved source. App-owned version history remains separate from Markdown.
- Continuous long-source analysis remains a supported research practice: one
  source-level Analysis can be updated as bounded units accumulate, and the
  current Research Status editor records scope and limitations. Scholium does
  not ship a Source Analysis Workflow package or Strip button; the researcher
  asks an available agent to inspect the source directly and uses Develop for
  an authorized Analysis update. A dedicated long-source progress presentation
  remains future work.
- New default Analysis Properties replace contextual project-relevance and app-owned timestamp fields with optional paired Debate Importance and Debate Scope fields. Debate Importance is a scoped 0–10 prioritization aid with no pass grade; existing relevance or timestamp YAML remains preserved as legacy or custom source.
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
  contrast floors are covered by automated architecture tests. The Design
  Handbook remains the authority for the palette values and their meanings.
- The native shell follows the Design Handbook's preferred prototype topology: one reflowing Library sidebar, one dominant document region, and one optional trailing Research inspector. The former separate workspace-navigation and note-list columns are no longer reachable.
- Triptych Home is no longer reachable or written. With no current note, the window renders the narrow left-middle **Triptych Interface** through a visually titleless native window frame that retains the standard traffic lights and accessible window identity. Its fixed-size top-right ellipsis exposes Triptych management without a redundant indicator; selecting a note reveals the document toward its trailing side and adds **Collapse Note** beside management without discarding the open-tab session. The redundant system **Hide Sidebar** toolbar item is suppressed, so the Interface and the matching menu command own this transition. Closing the last tab or choosing Collapse Note returns to the Interface. Historical `home`, `search`, and `canvas` window destinations decode to the document compatibility state.
- The toolbar owns title-first open-note tabs, the shared Search action, and
  paired History/Inspector controls. Permanent Back/Forward buttons and the
  former Open Scholia doorway are absent; their applicable menu and keyboard
  routes remain.
- The floating document context surface groups Read/Live Preview/Source and heading outline in one restrained icon-only control surface followed by one role-aware Properties disclosure. Both compact surfaces use the same 40-point height and vertical centerline; together with their 10-point gap they occupy the same centered 920-point measure as the Read/editor body. The expanded single-layer panel also occupies exactly 920 points. The opaque boundary band is removed: document content begins below the surface but can scroll visibly beneath its regular glass and softened shadow. Summary facts progressively reduce from three to one before crowding. Document text size remains in **View → Document Text Size** and its keyboard shortcuts instead of occupying permanent document chrome.
- The Library consolidates research-state, tag, metadata, and sort choices in one native **Filter** menu while keeping visible Unreviewed and Unqualified task toggles. The bounded research-state filters remain Changed since review, Needs attention, Explicit connections, and Malformed metadata. Analyses prefer author/year secondary metadata, Topics retain relative modification time, and Works prefer document kind/lifecycle state when available. After one exact Debate Scope is selected through the metadata filter, the Library also permits numeric high-to-low Debate Importance sorting with unrated matching Analyses last; it does not compare ratings across scopes.
- Search is one centered, two-stage Spotlight-style Liquid Glass overlay. Its empty state is a single wide search bar over a softly obscured window; committing text expands the same surface downward and then exposes **This Note**, **This Vault**, and **Triptych** scopes above a selectable native result list. **This Note** is restricted to the open note's exact vault-qualified path, **This Vault** uses only the selected vault index, and **Triptych** federates the three vault indexes. FTS5 results expose clean visible-text snippets, field context, exact source lines, highlights, stable selection, arrow-key movement, Return-to-open, and Escape-to-close. One exact Topic title or alias may add a separate **Related** section containing only direct resolved graph connections; these items expose their relationship, never change FTS ranking, and never infer transitive support. Stale asynchronous responses cannot replace a newer query. The former full-document Search destination is no longer written or reachable; historical window snapshots containing `search` or `canvas` restore to the document. The custom Read Find bar and WebView Find bridge are removed; Quick Open remains a separate Triptych-wide title, path, and alias navigation command with vault-qualified results. Beta Search has no vectors, embeddings, AI query interpretation, AI ranking, or chat-style interface.
- **Navigate → Recent Notes** exposes a bounded, per-window, vault-qualified MRU list with human-readable vault roles and duplicate-title disambiguation. It persists with the window session, follows confirmed moves, drops unavailable or permanently deleted notes, can be cleared, and routes directly from registered vault identity without depending on Search or graph readiness.
- One bottom editor Research Strip opens the selected one-word function
  directly. It is absent when no note is open, reserves editor space rather
  than covering prose, retains every role-valid function at compact widths,
  and has direct Research-menu parity. `Command-Shift-D` opens Dialogue;
  `Command-R` opens Review for an Analysis or Topic and Critique for a Work.
  Materials are selected only inside the shared panel, while Target identity
  and revision remain fixed for that presentation.
- Note History presents Dialogue as a concise, role-labelled scholarly exchange and lets the researcher append a follow-up Comment or record an attributed agent Response without exposing prompt mechanics. The default Dialogue response contract asks agents to foreground academic changes and unresolved questions or required researcher review.
- Note History and the Research inspector now share one mutually exclusive trailing context region. Switching between them is an atomic per-window state change, so the document does not acquire competing trailing panels.
- Unclassified opens as a centered classification surface. Set Aside and Trash remain anchored below Library and rise as mutually exclusive compact Liquid Glass cards over the preserved Library geometry; dense note rows and destructive confirmations remain opaque and native.
- Liquid Glass is limited to the navigation and control layer: toolbar/context controls, compact Properties disclosure, one bounded expanded Properties panel, transient status, lifecycle cards, and primary actions. The expanded Properties panel uses one regular-material layer with no nested translucent fields and an opaque Reduce Transparency fallback. Document prose, source, diagnostics, and comparison content retain opaque system backgrounds for legibility.
- First launch now uses the Triptych Interface's narrow measure and left-middle position for a five-step native flow with no scrolling page: Welcome, Analyses, Topics, Works, and final name/authorization. Each folder is chosen through a standard Open panel, progression remains disabled until the current choice is complete, and longer storage or agent-boundary prose is absent from the primary setup surface. Its initial completion clears the setup route before Triptych activation publishes a vault, preventing a duplicate guide from appearing over the Interface. Later **New Triptych…** and **Manage Triptychs…** editors remain separate.
- At wide widths (`>= 1200`) the document keeps its reflowing trailing Research Inspector or Note History context. Medium and compact widths collapse that context before constraining document content, and reopen it through the same toolbar routes as a scoped sheet. At compact widths the document is the initial surface and Library remains available through the standard sidebar command.
- Slow initial graph publication no longer aborts workspace activation or
  blocks lexical Search. Graph work continues independently in the Application
  runtime; Search waits only for the vault indexes required by its selected
  scope. The last good derived snapshot remains visible with explicit current,
  stale, or failed status and affected-vault evidence; committed writes report
  post-commit refresh failure without inviting unsafe mutation retry.
- Vault inventory and FSEvents now derive relative paths by normalized URL components rather than character-count slicing. Equivalent macOS paths such as `/tmp` and `/private/tmp` therefore preserve the complete vault-relative path, remain containment checked, and no longer bypass role-specific behavior such as Critique provenance.
- External-edit conflict recovery now binds the complete editor and disk sources to visible SHA-256/byte-count revision identities. The comparison labels editor-only and disk-only lines without inferring authorship, returns focus to the editor, and keeps dense diff content on an opaque system surface. **Compare Changes** is the nondestructive default; **Reload from Disk** is destructive and accepts only the exact disk revision shown. If the file changes again, the local buffer remains open and Scholium requires a fresh comparison. Reload uses the document's incremental projection path rather than a full-vault rescan.

Manual accessibility and narrow-window visual acceptance is not yet complete. Automated responsive acceptance now passes at 1380, 1080, and 900 points using the real window frame plus stable toolbar and menu routes. It deliberately avoids treating sidebar-descendant snapshots as a state oracle and does not claim manual visual or assistive-technology acceptance.

## Three audit-and-fix passes

### Pass 1 — product reachability

- Replaced visible per-save Version History with the canonical Note History.
- Added portable Triptych control, Properties configuration, identities, Unclassified staging, Critique associations, Human Review, Dialogue, and checkpoints.
- Added safe lifecycle UI and direct CLI note operations.
- Added source-located incoming-link updates and explicit Unqualified-Analysis-reliance Attention.

### Pass 2 — trust and data boundaries

- Verified full Markdown/YAML fidelity, conflict, snapshot, checkpoint, relationship, search, and performance tests.
- Removed writable metadata caches and legacy generated agent indexes.
- Restricted Zotero to bounded contextual metadata GETs over `127.0.0.1`; no attachment enumeration/download, Zotero database, online API access, or write request remains. Matching exposes unavailable, insufficient, missing, and ambiguous states rather than guessing.
- Consolidated the isolated QA harness into one deterministic, one-process researcher journey against disposable fixtures; the corrected journey now passes.

### Pass 3 — surface and redundancy

- Removed dead `AgentSkillService`, `IndexGenerator`, obsolete render caches, `selectedKB`, Proposal/Session/Export views, and the Canvas feature.
- Consolidated Attention into one dismissible derived-issue contract and removed Workflow Gates, settlement/prose-permission, source-check, bridge, and project-readiness warnings from reachable surfaces.
- Updated the documentation hierarchy so target, design, current evidence, and repository procedures remain distinct.

## Remaining completion work

1. Complete manual Full Keyboard Access, visual 200% text, localization, and real system-setting propagation acceptance for Light/Dark appearance, Increase Contrast, Reduce Transparency, and Reduce Motion. The clean-account XCUITest already drives the three vault Open panels plus the containing-folder authorization panel, verifies the portable manifest, relaunches with the same isolated home, and renames the Triptych without a `manifest.json` permission error. The focused Critique XCUITest verifies agent attribution, deterministic Specific Findings disclosure, and exact Source navigation on a disposable Triptych.
2. Approve the proposed strict p95 thresholds, freeze and exactly tag a clean reviewed commit, package that exact source, and run the packaged Release-app G7 protocol against frozen RDF-1 on Reference Machine R1. Complete-boundary instrumentation, the external XCUITest driver, strict report validator, thermally bounded fail-closed 5-warm-up/30-sample runner, build provenance, and privacy-safe environment capture are implemented. Warm Search and Read reuse one process; only process-boundary metrics relaunch. Internal SQLite and semantic-projection microbenchmarks remain regression checks only.
3. Continue explainable lexical-ranking evaluation beyond the current 2,056-note disposable collision fixture, including broader ranking-usability review and eventual release-owner approval. The current field-weighted contract ranks Title, Alias, Heading, and Body matches deterministically, verifies equal-rank path ordering, and labels their context explicitly. Beta remains deterministic local SQLite FTS5 plus separately labelled direct graph relations; vector search, embeddings, AI ranking, and chat-style search are explicitly out of scope.

Permanent deletion no longer advertises checkpoint or Note History recovery for deleted content. The coordinated implementation, destructive confirmation, checkpoint invalidation, durable recovery notice, file-by-file inspection, and record-only resolution paths are verified on disposable filesystems.

## Verification evidence

This ledger keeps representative current evidence and the interpretation of
each result. Run-by-run XCUITest and repository-verify snapshots are
intentionally compacted; retained `.xcresult` bundles remain under
`/tmp/Scholium-UITests/Logs/Test/`, and superseded details remain available
in repository history and retained artifacts. All research-content fixtures
were disposable. The optional Zotero MCP boundary was additionally exercised
against the running local service for bounded reads and against a disposed
temporary profile for one synthetic import; no live-library write or private
library value is retained in the evidence.

| Evidence class | Latest recorded result | Interpretation |
| --- | --- | --- |
| Repository verification | The 2026-07-16 complete `verify.sh` record passed editor typecheck and 40 editor tests, reproducible bundle verification, deterministic RDF-1 at 800 notes with tree hash `5a7a320c43f19352056e59db88d55c27a340c5284d3c4872dfe43ca667a30319`, 377 Core tests across 37 suites, 18 Contracts tests across 4 suites, 53 `ScholiumApplicationTests` across 13 suites, 86 `ScholiumAppTests` across 13 suites, executable workflow CLI verification, public-Application symbol-graph isolation, and the SwiftPM Release build. The architecture guards reject delivery-target Core imports, unapproved Application imports, frontend authority construction and I/O, and public Application signatures containing Core types. | Repository/build evidence; no package was created and this is not packaged Release-app G7 evidence. |
| Beta Skill architecture | Catalog/resource resolution, local routing and dependencies, workflow contracts, stateless audit planning, bootstrap, Dialogue transport, and Zotero boundaries pass focused suites and the complete verifier. Real local-service reads and an isolated synthetic import/read-back also passed. The privacy-safe ledger is [SKILL_ARCHITECTURE_BETA_EVIDENCE.md](SKILL_ARCHITECTURE_BETA_EVIDENCE.md). | Structural implementation evidence; ten philosophical field trials, the Dialogue response-module UI journey, and manual accessibility acceptance remain open, so G10 and J-014–J-016 are not complete. |
| Focused Core and CLI contracts | Research Status, lossless source, protected Skills, Dialogue response snapshots, workspace bootstrap, and first-party Zotero transport suites passed in isolated scratch paths. The architecture-focused record includes 52 tests across 5 suites plus 10 Dialogue-transport/Zotero tests across 2 suites. | Contract/build evidence; philosophical adequacy and manual acceptance remain separate. |
| Search and derived state | The focused SearchIndex suite passed against a synthetic 2,056-note collision fixture, covering deterministic Title/Alias/Heading/Body precedence, equal-rank path ordering, repeat-query stability, and safe replacement of an incompatible generated contract; an isolated UI run verified the same visible field-context order. Broader ranking-usability evaluation remains open. | Semantic and isolated UI evidence. |
| Current UI journeys | Canonical one-process, Search/Related, Recent Notes, 200% document text, responsive 1380/1080/900-point, clean-account, Dialogue chronology, Critique navigation, multiwindow/rename, lifecycle, checkpoint, deletion, and interruption-recovery journeys passed against disposable fixtures. On 2026-07-16, the post-editor-boundary canonical journey passed Search, Properties, inspector routing, Review validation, cross-vault Back/Forward, the precise Zotero-unavailable state, Live Preview editing and flush-before-Search, and an independent second window. A focused editor journey then proved that Format, Insert, and the editor context menu expose their commands to the focused Live Preview session. Focused journeys also passed external-edit conflict comparison with exact dirty-buffer retention, interrupted-transaction inspection and record-only resolution, and selective checkpoint restore with exact source preservation. A two-window dirty-peer UI attempt stopped before its conflict assertion when XCUITest opened the mode menu behind the overlapping peer window; deterministic App tests still passed clean-peer convergence, dirty-peer retention, runtime replacement, watcher ownership, and shutdown. Earlier the revised clean-account journey passed through the narrow no-scroll guide, completion without duplicate presentation, note reveal, relaunch, and Triptych rename; the focused Metadata journey verified that controls plus Properties and the expanded panel each equal the 920-point document measure; and the retract/reveal journey verified the persistent Triptych Interface with **Triptych management** and **Collapse Note**. Focused Research Strip XCUITests then passed explicit Materials selection and preparation: the immutable Target was excluded, candidates began unselected, Cancel discarded draft selection and instructions, and the copied preparation contained only the chosen Material. Forced Light and Dark launches kept the Analysis/Topic Strip and Dialogue panel visible, ordered, and hittable. Accessibility assertions verified the **Research functions** group and one-word controls, Dialogue's Target/Materials/Scope semantics, and Review's Target-before-Comments order. With VoiceOver enabled, the focused spoken-traversal journey then restored keyboard focus to Dialogue, synchronized the VoiceOver cursor once, tolerated unrelated editor focus stops, and captured **Dialogue → Develop → Review → Fidelity** in order while retaining its transcript. | Current reachable behavior has focused scenario evidence; explicit Materials selection, forced Light/Dark rendering, Research Strip accessibility semantics, and spoken VoiceOver traversal are automated. Real system-setting propagation for appearance, contrast, transparency, and motion remains unverified; Full Keyboard Access, localization, and broader recovery acceptance also remain open. This is not the packaged RDF-1 performance gate. |
| Superseded UI runs | Earlier Triptych Home and full-document Search-destination runs are retained only as historical evidence. Current D-032 removes Home, and historical `search`/`canvas` window destinations decode to the document compatibility state. | Historical; do not use as current reachability evidence. |
| Performance | Complete-boundary instrumentation, the external XCUITest driver, strict validator, privacy-safe capture, and fail-closed runner are implemented. One four-metric Debug scenario run validated the plumbing. The canonical RDF-1 protocol requires the exact packaged Release app on R1 and five warm-ups plus 30 retained samples; no packaged Release gate run or threshold approval exists. | Scenario-only; G7 remains open. |
| Distribution | A 2026-07-15 local arm64 Release preflight passed signature, metadata, checksum, license, and resource checks, but recorded `source_clean=false` and no exact tag. | Local preflight; not clean-tagged G9 evidence or a release asset. |

The source-first beta policy is now fixed in `BETA_RELEASE.md`: the intended
`v0.1.0-beta.1` GitHub release pairs exact `GPL-3.0-or-later` source with an
optional ad-hoc-signed app-only ZIP and SHA-256 checksum. Bundle metadata and
the packaging script are aligned to that target. This records policy and
local packaging evidence only: no clean tagged artifact, external-install smoke
test, Developer ID signature, notarization result, or public GitHub release has
yet passed the release gates.
