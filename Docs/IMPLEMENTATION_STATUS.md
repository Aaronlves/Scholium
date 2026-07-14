# Scholium Implementation Status

**Audited:** 2026-07-14
**Authority:** [PRODUCT_GUIDE.md](PRODUCT_GUIDE.md) defines target product behavior, [DESIGN_HANDBOOK.md](DESIGN_HANDBOOK.md) defines the interface contract, and [PRD.md](PRD.md) synthesizes requirements; this file records current evidence only.

## Reachable target behavior

- Multiple complete Scholium Triptychs, each with independently chosen **Analyses**, **Topics**, and **Works** locations. One Triptych is selected per window; File commands create a Triptych, open a registered Triptych in its own window, or create another independent window for the focused Triptych.
- Portable `.scholium` state beside Works for the manifest, vault-wide Properties configuration, Critique settings and associations, stable note identities, imported Unclassified Markdown, and researcher-managed Skills packages under `.scholium/skills/<skill-id>/SKILL.md`.
- Application Support state for Human Review, comments, Dialogue, checkpoints, search indexes, CSS snippets, machine-local access data, and legacy Canvas migration records that are no longer presented in the stable UI.
- Exact-source `NoteDocument`, targeted YAML changes, transactional autosave, external-change conflicts, symlink/traversal rejection, and readback verification.
- Safe create, duplicate, move/rename, Set Aside, Trash, restore, and permanent deletion through `VaultRepository`. Confirmed permanent deletion removes the source note and a Work's separate current Critique Markdown together with repository versions, Human Review/comments, every Dialogue containing either stable identity, Critique associations, portable identity state, and every checkpoint containing either identity. A durable transaction journal restores exact pre-commit state after ordinary failures or process interruption and completes privacy cleanup after the commit decision; a concurrently recreated path is never replaced and retains its recovery version for explicit resolution.
- Confirmed app moves use a Triptych coordinator that preflights the destination and every vault-qualified incoming-link revision, then updates only links that both the supplied and freshly derived workspace graphs resolve to the moved note. Ambiguous or stale resolutions are never guessed.
- Multi-file move and Unclassified-classification failures roll back exact bytes where revision checks still permit it. If a concurrent change prevents complete rollback, Scholium persists a file-by-file recovery record outside the vaults and keeps a visible recovery surface; it does not claim cross-filesystem atomicity.
- Stable identities and app-owned Human Review/comment state follow confirmed app moves.
- Imported Markdown is copied into Unclassified, remains editable, and can be classified into any Triptych vault without changing the original external file. Destination creation and Unclassified-copy removal use duplicate-safe rollback and persistent recovery when rollback cannot be verified.
- Human Review for Analyses and Topics with fingerprint-bound Qualified/Unqualified verdicts, required concise review note, drafts, and line/whole-note comments.
- Works use one current, separately attributed Critique document under `Works/Critiques` and an editable Triptych-wide prompt template. Every request updates the current target path and fingerprint, records a checkpoint-bound request round, and preserves earlier Critique source in checkpoint history. New and migrated Critiques carry targeted provenance metadata; their bodies remain read-only in Scholium, while ordinary external edits remain allowed.
- Critique provenance appears before the body with agent attribution, target Work and fingerprint, current/earlier-version and metadata-mismatch state, plus structured Specific Finding destinations. Explicit target lines, headings, and unique quotations open the corresponding Work passage; ambiguous quotations are never guessed. App lifecycle commands allow movement within `Critiques`, Set Aside, Trash, and restoration but block crossing the Critique boundary or duplicating a current Critique.
- Generic one-note or multi-note Dialogue, automatic **Before Agent Work** checkpoint, copied researcher instructions, CLI replies, and per-note Note History. Dialogue preserves the initial researcher Comment plus chronological researcher follow-up Comments and attributed agent Responses; migrated records without follow-ups remain readable.
- Self-contained Triptych checkpoints outside the vaults, latest-ten automatic retention, manual checkpoints, comparison, selective note restore, complete restore, and Finder access. Restore defers automatic retention until the selected checkpoint has been applied, so creating the pre-restore safety checkpoint cannot remove the selected recovery source mid-operation.
- Note History separates Human Review, comments, Dialogue, Critique association, and checkpoint versions; ordinary autosaves do not create visible versions.
- Direct CLI note create/replace/move/Set Aside/Trash/delete commands. Existing-note mutations require the current SHA-256 fingerprint.
- Canonical Vector-Link v1 semantics: `[[B]]`, `+[[B]]`, `-[[B]]`, and `?[[B]]`; neutral and transitive paths never become evidence, and retired typed aliases/arrows remain source-preserving neutral links with diagnostics.
- One workspace-scoped `GraphSnapshot` resolves deterministic links across the Triptych while preferring same-vault matches. Incoming, Outgoing, Research, Search diagnostics, and Attention consume this graph; the legacy parallel relationship parser has been removed.
- CodeMirror Source/Live Preview, sanitized Read mode, callouts, footnotes, protected CSS snippets, and bundled Alegreya/Victor Mono document fonts.
- Shared SQLite FTS5 human/CLI search contracts, Unicode/CJK behavior, deterministic Connection diagnostics, and one canonical Attention contract. Attention is limited to possible-orphan structure, Changed Since Review, broken or ambiguous Connections, explicit source-anchored reliance on an Unqualified Analysis, malformed metadata, and unresolved identity. Every item is dismissible; the Triptych-local duration is stored in `.scholium` and defaults to seven days, while per-item dismissal deadlines remain machine-local. Retired workflow gates and governance queues are absent from the Research inspector and Attention surface.
- Per-vault Properties fields, explicit display order, human-editable allowlists, and starting disclosure state; sparse Triptych navigation; Settings-only Dialogue and Critique prompt templates; bundled and Triptych-local file-backed Skills; and localhost-only read-only Zotero access.
- An atomic v2 workspace registry stores multiple stable Triptych assignments while preserving the legacy one-workspace files unchanged. Window snapshots persist selected Triptych identity, and shared registry actors prevent per-window last-writer duplication.
- Retained compatibility readers are fixture-audited: every supported legacy vault-role spelling re-encodes canonically; legacy property aliases remain read-only projections with canonical-key precedence; v0 Triptych, sparse window, per-vault presentation, retired Search-scope, and Canvas records remain readable. Missing historical fields receive bounded defaults, while malformed present fields and unknown roles fail without rewriting their files.
- One shared `WorkspaceStore` owns registered vaults and shared repository, watcher, index, graph, review, Dialogue, Critique, and diagnostic services. Each window keeps only its independent Triptych selection, tabs, modes, chronological History, Recent Notes MRU, scroll, inspector, and search presentation state.
- Confirmed app moves and externally reconciled renames migrate stable identity plus Note History references, Human Review/comments, Dialogue references, Critique associations, window snapshots, and Canvas references. Ambiguous external identity changes require explicit confirmation rather than guessing.
- The Research inspector shows only the current Analysis's Zotero source or the unique keyed Zotero items of Analyses named by outgoing links in the opened Topic or Work. Analysis lookup uses item key, DOI/ISBN, citation key, then exact title + author + year; non-unique matches remain visibly ambiguous. Compact metadata includes authorship, publication, volume/issue/pages, stable identifiers, and citation key, with abstract, publisher, edition, URL, collections, and modification time under disclosure when available. Incoming backlinks, bibliography entries, transitive paths, Unclassified notes, and the wider library are excluded. The only source action is **Open in Zotero**; Scholium does not enumerate or open attachments.

## Removed from the reachable target UI

- Proposal/Revision review sheets.
- Research Task and Research Session sheets.
- Agent Assessment and legacy Agent Review.
- Active-note HTML/PDF export.
- Canvas authoring, annotation editing, drag/drop insertion, and edge conversion.
- The view-only Canvas surface is also temporarily removed from the stable UI. Legacy Canvas records and snapshot fields remain read/migration compatibility only until the core document workflow is stable.
- Optional Zotero data-folder/SQLite access.
- Additional-vault and All Notes presentation.
- Generated `_index.md`, `_agent-index.json`, and `_agent-context.json` paths.

The obsolete Proposal, Research Session, workflow-bridge/readiness/lint, old Review-store, and Add Dated Reference implementations have been removed from the app, Core, and CLI. Existing legacy files on disk are deliberately left untouched: Scholium neither reads them into the current interface nor deletes or rewrites them. Researchers may archive those files manually in Finder.

## Current interface consolidation

- The native shell now follows the Triptych Document Prototype Report: one reflowing Library sidebar, one dominant document region, and one optional trailing Research inspector. The former separate workspace-navigation and note-list columns are no longer reachable.
- The toolbar owns title-first open-note tabs, the shared Search action, **Open Scholia…**, and paired History/Inspector controls. Permanent Back/Forward toolbar buttons are removed; their menu and keyboard routes remain.
- The document context row owns Read/Live Preview/Source, heading outline, and compact Properties. Sidebar note rows use full-width selection instead of rounded card hover treatments.
- Search is one surface with **Triptych** and **This Note** scopes. The custom Read Find bar and WebView Find bridge are removed; Quick Open remains a separate Triptych-wide title, path, and alias navigation command with vault-qualified results.
- **Navigate → Recent Notes** exposes a bounded, per-window, vault-qualified MRU list with human-readable vault roles and duplicate-title disambiguation. It persists with the window session, follows confirmed moves, drops unavailable or permanently deleted notes, can be cleared, and routes directly from registered vault identity without depending on Search or graph readiness.
- **Open Scholia…** is the single prominent document-local doorway. A Dialogue accelerator opens that panel with Dialogue selected instead of creating a second standalone route.
- Note History presents Dialogue as a concise, role-labelled scholarly exchange and lets the researcher append a follow-up Comment or record an attributed agent Response without exposing prompt mechanics. The default Dialogue response contract asks agents to foreground academic changes and unresolved questions or required researcher review.
- Note History and the Research inspector now share one mutually exclusive trailing context region. Switching between them is an atomic per-window state change, so the document does not acquire competing trailing panels.
- Unclassified opens as a centered classification surface. Set Aside and Trash remain anchored below Library and rise as mutually exclusive compact Liquid Glass cards over the preserved Library geometry; dense note rows and destructive confirmations remain opaque and native.
- Liquid Glass is limited to the navigation and control layer: toolbar/context controls, compact Properties disclosure, transient status, lifecycle cards, and primary actions. Document prose, source, dense metadata, diagnostics, and comparison content retain opaque system backgrounds for legibility.
- First launch now presents the required Triptych setup as one native grouped sheet. Before any folder picker opens, it explains the three researcher-controlled vault locations, the portable `.scholium` and machine-local Application Support boundary, and the optional external-agent boundary. Later **New Triptych…** and **Manage Triptychs…** editors remain concise instead of replaying onboarding.
- At wide widths (`>= 1200`) the document keeps its reflowing trailing Research Inspector or Note History context. Medium and compact widths collapse that context before constraining document content, and reopen it through the same toolbar routes as a scoped sheet. At compact widths the document is the initial surface and Library remains available through the standard sidebar command.
- Slow initial graph publication no longer aborts workspace activation with a modal error. Graph work continues in `WorkspaceStore`, while Search reports its own inline unavailable/retry state until the shared derived state is current.
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

- Removed dead `AgentSkillService`, `IndexGenerator`, obsolete render caches, `selectedKB`, Proposal/Session/Export views, and Canvas authoring controls.
- Consolidated Attention into one dismissible derived-issue contract and removed Workflow Gates, settlement/prose-permission, source-check, bridge, and project-readiness warnings from reachable surfaces.
- Updated the documentation hierarchy so target, design, current evidence, and repository procedures remain distinct.

## Remaining completion work

1. Complete deterministic isolated execution for the clean-account folder-selection journey, Critique finding navigation, conflicts, lifecycle, settings, multiwindow sharing, and recovery. The clean-account XCUITest now drives all three standard Open panels, opens a note, verifies the portable manifest, relaunches with the same isolated home, and checks that registration restores without setup; the target builds but this journey has not completed interactively. The Critique journey passes a supplementary accessibility-driven disposable-workspace run. Conflict comparison and stale-reload journeys are checked in, but interactive XCUITest execution remains blocked before app launch by the local macOS automation-mode timeout.
2. Complete manual VoiceOver, Full Keyboard Access, 200% text, appearance, contrast, reduced-transparency, and reduced-motion acceptance.

Permanent deletion no longer advertises checkpoint or Note History recovery for deleted content. The coordinated implementation is verified on disposable filesystems; its remaining acceptance work is the broader lifecycle and recovery UI journey listed above.

## Verification evidence

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Tools/Scripts/verify.sh` passed on 2026-07-14: deterministic TypeScript typecheck and bundle verification, 277 Swift tests across 30 suites, the 800-note indexed-search gate, the 5,000-word cold-render gate, and Debug and Release builds. Recent Notes coverage includes bounded unique MRU ordering, Triptych restriction, vault-scoped normalization, compatibility decoding, and rename deduplication. Quick Open coverage includes Triptych-wide title, path, legacy-compatible alias, CJK, diacritic, deterministic ranking, result limiting, and vault-qualified identity behavior. Conflict coverage now includes aligned insertion/removal rendering, repeated lines, and exact editor/base/disk revision binding. Permanent-deletion coverage includes coordinated Work/current-Critique removal, repository-history purge, app-owned record and identity purge, checkpoint invalidation, rollback at every cleanup stage, fresh-runtime recovery before and after the commit decision, and concurrent path-recreation protection. Legacy compatibility coverage uses immutable fixtures for sparse window and Search state, v0 Triptych identity, all retained role and property aliases, and Canvas migration data; read operations preserve fixture bytes and malformed present values fail closed. Research Guidance coverage includes prompt-template migration and validation plus bounded Skills discovery, malformed/non-UTF-8 visibility, symlink and traversal rejection, revision-checked management, and instruction assembly. Dialogue coverage includes chronological follow-up persistence, migration retention, legacy decoding, and the current academic-response contract. Vault-relative path coverage includes the `/tmp` and `/private/tmp` alias that previously truncated initial-scan and watcher paths. The deferred Canvas projection suite remains removed.
- `xcodebuild ... build-for-testing` passed for `ScholiumUITests` on 2026-07-14 with the complete clean-account setup, conflict comparison, and changed-again disk-revision journeys compiled. The clean-account journey uses a fresh test-owned `SCHOLIUM_HOME`, verifies the local-files, generated-state, and agent-boundary disclosures, selects generated Analyses, Topics, and Works roots through three standard Open panels, opens a fixture note, checks `.scholium/manifest.json`, and relaunches to verify registration restoration. The Debug-only panel-directory launch variable controls only the initial displayed directory; it does not select or authorize a folder. This is build evidence only; the unchanged automation-mode startup timeout was not rerun and is not recorded as an interaction pass.
- The focused Triptych-wide Quick Open alias XCUITest and its disposable QA application compiled on 2026-07-14. Its earlier runner attempt timed out while enabling macOS automation mode before the test body launched, so that attempt remains compile evidence only.
- After XCTest automation access was enabled, the focused Recent Notes journey passed on 2026-07-14 against disposable fixtures. It crossed vaults, used Back to change actual recency, reopened the Topic through **Navigate → Recent Notes**, cleared the list, and verified the disabled empty state without invoking Search or Quick Open. The retained result bundle is `/tmp/Scholium-UITests/Logs/Test/Test-ScholiumUITests-2026.07.14_10-43-00-+0800.xcresult`.
- The default isolated canonical acceptance journey passed again on 2026-07-14 after XCTest automation access was enabled. It exercised unified Search, Properties, Inspector, Scholia/Review validation, cross-vault Back/Forward, Zotero unavailable state, Live Preview commit-before-navigation, and independent-window handling. The retained result bundle is `/tmp/Scholium-UITests/Logs/Test/Test-ScholiumUITests-2026.07.14_10-45-08-+0800.xcresult`.
- **Research Guidance is reachable:** Settings is the sole visible prompt-template and Skills manager; Dialogue and Critique use active Triptych-local templates and valid skill instructions without persisting technical source in the scholarly Dialogue record. Bundled Skills are read-only until duplicated, Triptych-local Skills support validation and revision-checked management, and malformed packages remain visible but unavailable to instruction assembly.
- Focused graph/search regression verification passed 28 tests after generation-aware graph publication was hardened.
- The corrected isolated one-process canonical researcher journey passed again on 2026-07-14 after the responsive-layout change, against disposable fixtures. Three focused journeys also passed for mode/inspector/Search reachability, dirty-editor commit before Search, and independent window open/close. The window-close test now activates the native close control; `Command-W` correctly remains the separate Close Tab command.
- The focused responsive-document journey passed on 2026-07-14 at 1380, 1080, and 900 points. It verifies the wide inline context, medium and compact adaptive Inspector sheet, enabled native sidebar route, and preserved document surface without relying on a sidebar-descendant accessibility snapshot.
- The post-prototype UI run passed the canonical journey and the isolated Note History/Research Inspector shared-region journey (2 tests, 0 failures). The canonical journey exercised the unified Search popover, Scholia, cross-vault navigation, Live Preview commit-before-navigation, and independent-window handling.
- The focused Research Guidance Skills journey passed on 2026-07-14 against disposable fixtures. It verified Settings routing, shared-runtime readiness, bundled-skill selection, and the bundled Duplicate/Reveal action boundary.
- The focused Dialogue chronology journey passed on 2026-07-14 against disposable fixtures. It verified the initial researcher Comment, a persisted follow-up Comment, an attributed agent Response, chronological presentation, and close/reopen persistence. The canonical isolated journey then passed again with the same production changes. Note History identity-snapshot decoding now uses the production ISO-8601 contract covered by checkpoint tests.
- A supplementary accessibility-driven Critique journey passed on 2026-07-14 against a disposable `/tmp` Triptych: the Critique was identified as agent-authored, Specific Findings exposed deterministic collapsed and expanded states, and the traced finding opened `QA Work.md` in Source at line 3 with `[[QA Topic]]`. The equivalent focused XCUITest is checked in, but the local runner timed out while enabling automation before app launch; the retained result bundle is `/tmp/Scholium-UITests/Logs/Test/Test-ScholiumUITests-2026.07.14_08-17-28-+0800.xcresult`. This infrastructure failure is not recorded as an application pass.
- A Debug build also passed with Xcode 27 beta 3 / Swift 6.4 after removing Finder/provenance metadata from the local resource directory and using a clean `/tmp` scratch path. The app continues to target the macOS 26 Liquid Glass API surface.
- The full repository verification passed again on 2026-07-14 after the
  source-first beta documentation, metadata, packaged-license, and archive
  changes: the editor bundle remained reproducible, all 277 Swift tests across
  30 suites passed, and the Release build completed.
- A disposable ad-hoc packaging check passed outside the checkout on
  2026-07-14. The generated ZIP had exactly one top-level item,
  `Scholium.app`; its checksum verified; the expanded app passed strict
  `codesign` verification; metadata reported version `0.1.0` build `1` and
  macOS `26.0`; the executable reported `arm64`; and the app embedded the GPL,
  third-party notices, and seven complete runtime-license files. Gatekeeper
  rejected the ad-hoc app as expected. All disposable artifacts were removed.

The source-first beta policy is now fixed in `BETA_RELEASE.md`: the intended
`v0.1.0-beta.1` GitHub release pairs exact `GPL-3.0-or-later` source with an
optional ad-hoc-signed app-only ZIP and SHA-256 checksum. Bundle metadata and
the packaging script are aligned to that target. This records policy and
packaging capability only: no clean tagged artifact, external-install smoke
test, Developer ID signature, notarization result, or public GitHub release has
yet passed the release gates.
