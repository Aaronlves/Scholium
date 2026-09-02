# Specification: Release and Open Decisions

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 21–22.

## 21. Release requirements and acceptance

### 21.1 Evidence hierarchy

Evidence strength is: live source/construction, executable tests, isolated QA
on disposable fixtures, then dated status. Target prose, previews, and
compilation alone prove no workflow, accessibility, package, signing, or
performance result. [Implementation Status](../IMPLEMENTATION_STATUS.md) owns
dated evidence; acceptance reports link rather than copy it.

### 21.2 Primary acceptance journeys

Release acceptance is profile-scoped. **Core App** covers the local manual
research environment and never depends on an Agent or standalone CLI.
**Agent Collaboration** adds the external host, compatible CLI, local stdio MCP,
Core Protocol, live App bridge, current retrieval, guarded mutations, Agent
Changes, and recovery to an already accepted Core App. Evidence or failure in
one profile does not silently pass or block the other. Release names and notes
state the accepted profile; an unaccepted optional profile is labelled
**Preview** and is never represented as part of the Core App verdict.

**Usable Core** must cover:

- Bootstrap, registration/restoration, independent windows, and storage failure;
- create/open/read/edit/autosave, Review/Edit/Source, Find/Replace, Search,
  Metadata/About, Settle, Library, tabs, and cross-vault navigation;
- formatting, Callouts, Wikilinks, multiline link annotations, Analysis references, image
  Import/Index, statistics, spelling, and exact YAML/source fidelity;
- native split behavior, focus, keyboard, light/dark, enlarged text, minimum
  supported width, and core VoiceOver; and
- external edits, conflicts, rename/move, system-Trash Note/Folder deletion and
  partial recovery, Finder restoration, interrupted saves, and multiple-window
  dirty-peer behavior.

**Agent Collaboration Beta/1.0** additionally covers applicable Research
Guidance and Settings, Core Protocol discovery, user-scope Codex and Claude
configuration, the seven MCP tools, multi-Triptych selection, App-unavailable
behavior, source/index currentness, exact paging, role filtering, fingerprinted
create/update/system-Trash, Agent Changes, direct Undo, outcome-unknown
recovery, incoming/outgoing authored link occurrences and annotations, Attention, Zotero read-only/unavailable behavior, and
App/CLI/MCP parity. Exact initial frames and coordinates remain implementation
defaults rather than release thresholds.

Search acceptance covers scope/provider authorization, Metadata and direct-link
provenance, `link_annotation` matches, Explain/completion, Saved Search re-evaluation, App/CLI/MCP parity,
stale refusal, corruption rebuild, and
incremental/clean equivalence. Retrieval success never establishes
philosophical relevance, evidential support, or researcher acceptance.

Agent evidence includes both copied setup commands; user-scope stdio launch;
the current-user-only authenticated App bridge; single and ambiguous Triptych
selection; current status followed by search/read/link retrieval; one body
update and one create or system-Trash mutation; stale/conflict and uncertain
outcome recovery; exact Agent Change comparison; direct Undo; accessibility;
and App-unavailable fallback. It does not require an embedded or
provider-specific Agent runtime.

These are functional evidence categories, not one serial clean-account or human
script. Deterministic fixtures own protocol variants and failure branches;
packaged acceptance owns downloaded artifact, independent installation,
version, and production-bridge boundaries; §20 owns one representative human
Agent journey. Do not repeat every deterministic variant in the packaged or
human path merely to restate its coverage.

Core Protocol acceptance follows §8.5. Before the first Agent Collaboration
Beta it passes representative complete-source, partial-source,
conceptually-neighboring, conflicting-note, read-only, requested-update,
stale-revision, and uncertain-outcome cases. Later releases repeat only affected
cases after a material Core Protocol/tool change and retain a small regression
set. Optional researcher-owned method Skills are not release artifacts or
general philosophical certification. This cadence never relaxes a known
fabrication, source-fidelity, researcher-authority, privacy, or permission
defect.

Evidence that exercises research content uses disposable nonprivate fixtures.
Focused development evidence records the procedure or command, inputs,
environment, and result only to the extent needed to reproduce its bounded
claim; inapplicable source-revision, artifact, or fixture fields are omitted.
Evidence presented for a release or gate records the exact source revision,
toolchain, build/artifact, fixture identity, procedure or command, and result.
A carried §20 human baseline keeps its original exact artifact/environment and
the current release's change-impact record; it is not reported as execution on
the current artifact.

### 21.3 Release gates

| Gate | Required condition |
| --- | --- |
| **G1 Functional completeness** | Every in-scope requirement has evidence or explicit waiver. |
| **G2 Workflow independence** | Manual core works without Obsidian, Zotero, Agents, or manual filesystem repair. |
| **G3 Source integrity** | Exact-source tests cover malformed/unknown YAML, BOM/newlines, targeted edits, atomic failure, and readback. |
| **G4 Recovery and deletion** | Conflict, Agent Change Undo, save recovery, system-Trash receipts/cleanup, external deletion/restore/rename, and derived failure pass. |
| **G5 Scholarly transparency** | Source, researcher/Agent content, Agent Changes, Research Records, Settle, Critique, Fidelity, provenance, and uncertainty remain distinct. |
| **G6 Accessibility/localization** | §20's current guards, required UI baseline/affected journeys, bounded human threshold, and severity threshold are met for the named profile. |
| **G7 Performance** | The packaged-app protocol in §21.4 passes. |
| **G8 Documentation consistency** | Specification, architecture, status, README, source, and tests do not silently conflict. |
| **G9 Distribution integrity** | Distributed artifacts match an exact clean tag, source/licenses, signatures, architecture, checksum, and clean-account smoke test. |
| **G10 Agent collaboration** | Core Protocol, Codex/Claude setup, MCP tools, currentness, guarded mutations, Agent Changes, recovery, and local bridge pass their journeys. |

Usable Core/0.1 requires G1–G4, G6, and G8. **Core App Beta** requires G1–G6,
G8, and G9 within the Core App profile and does not require G10. Human and
complete deterministic UI evidence follow §20's baseline/change-impact cadence;
current repository guards and affected UI journeys remain required. Beta
performance evidence is change-triggered: when a release changes a measured
runtime owner, visible or correctness boundary, fixture, prepared driver,
threshold, or process attribution, run the affected packaged series. A focused
pass remains **Incomplete** rather than G7, and an unchanged performance surface
does not trigger a complete campaign. **Core App 1.0** requires G1–G9; any
release explicitly designated as a new performance baseline also requires G7.

**Agent Collaboration Beta** requires an accepted Core App Beta, G10, and the
Agent-scoped parts of G1, G3–G6, and G9; Core performance changes follow the
same change-triggered rule. **Agent Collaboration 1.0** requires an accepted
Core App 1.0 plus G10 and the Agent-scoped parts of G1, G3–G6, and G9. G9
applies only to artifacts actually distributed for the named profile.
Baseline, partial, waived, or other-profile evidence must not be presented as a
gate pass.

### 21.4 Packaged performance gate

Performance evidence has three distinct classes:

1. microbenchmarks detect internal regression;
2. scenario measurements use incomplete samples or nonrelease artifacts; and
3. product-gate measurements use the exact packaged Release app, frozen fixture,
   complete visible boundary, and full retained sample set.

Only a complete product-gate campaign satisfies G7. A focused product-gate
report is eligible change-triggered series evidence under §21.3 but never a G7
pass. Before capture, each latency series declares 2–5 excluded warm-ups and
20–50 retained samples; the ordinary plan is 3 + 20. The count may differ
between series when prior scenario evidence justifies it, but it cannot change
after gate values are inspected. Nearest-rank p95 uses every valid retained
sample. This bounded plan is a pragmatic release comparison, not a statistical-
confidence claim.

| Interaction | p95 | Maximum when required |
| --- | ---: | ---: |
| Warm Library launch to usable list | < 1,000 ms | — |
| Indexed Note Search to complete visible results | < 200 ms | — |
| Warm Review activation to interactive rendering | < 300 ms | — |
| First-use 5,000-word Review activation | < 1,000 ms | — |
| Key input to first painted edit | < 100 ms | < 200 ms |
| Edit/Source request to visible accessible mode | < 100 ms | < 200 ms |
| Cached preview to visible accessible preview | < 100 ms | < 200 ms |
| Warm Edit activation | < 200 ms | < 300 ms |
| First-use Edit after cold-launch Review | < 750 ms | < 1,000 ms |
| One visible-range projection | < 3 ms | < 5 ms |

An operation that would otherwise leave its owner blank exposes an accessible
loading state immediately; progressive work retains trustworthy content when
available. Long or unbounded work exposes accessible nonblocking progress and
safe cancellation when applicable. No universal duration threshold requires a
transient progress indicator, and progress never turns incomplete work or a
missed interaction threshold into a pass. Editor callbacks during input/scroll
target under 5 ms and yield before a display-refresh interval.

The frozen performance fixture contains 800 Notes and representative folders,
links, malformed frontmatter, large CJK, and 5,000-word Review/Edit content.
Fixture generators and runner ownership belong to
[Documents and Editor](../Architecture/06-documents-and-editor.md#documents-and-codemirror).

The retained-memory series similarly predeclares 30–60 mode transitions; its
ordinary plan is 40. It retains the existing two-tail convergence and stable-
process-set oracle rather than treating a shorter run as proof of no leak.

A gate campaign may capture all series together or combine focused series from
the same exact app, fixture, reference-machine configuration, threshold set, and
prepared driver. A focused report is eligible series evidence but is always
**Incomplete**, never a G7 pass. A recorded driver, environment, or correctness
failure invalidates that series; rerun that series rather than every completed
unaffected series. A valid threshold failure remains failure evidence and cannot
be erased by choosing a new sample count or repeating the unchanged series.

The gate uses one clean exactly tagged packaged app, prepared measurement
driver, unchanged reference-machine record, isolated Application Support and
preferences, and user-visible/accessibility-complete boundaries. Retain raw
durations, summary statistics, invalid-series reasons, correctness, memory,
machine/artifact/fixture identities, and raw outputs outside research vaults.
Provenance mismatch, changed process set, missing campaign series, incomplete
planned samples, or unapproved thresholds fails closed.

The large-CJK fixture must remain byte-exact and editable at beginning, middle,
and end with Undo and mode switching. Repeated Note/mode switching must show
stable editor/renderer counts and bounded decelerating memory growth rather
than a constant leak. This is a correctness/stability condition, not a
percentile substitute.

### 21.5 Source-first Beta distribution

Each source-first Core App Beta release requires:

- exact public prerelease tag/package provenance;
- recorded app version/build and minimum supported macOS;
- corresponding `GPL-3.0-or-later` tagged source and license notices;
- architecture-labelled DMG containing the ad-hoc-signed App plus Applications
  alias; and
- a checksum for the App artifact.

An Agent Collaboration Beta additionally requires the separate version-matched
CLI archive and its checksum. Packaging and provenance checks apply to every
artifact actually emitted; a Core App-only release does not manufacture or
validate a CLI merely to satisfy another profile.

The App bundle contains no CLI or installation authority. The CLI archive
contains only its executable, adjacent release resources, and user-local
installer. Neither artifact contains real vaults, private paths, credentials,
bookmarks, indexes, or generated user state.

CLI self-update uses only fixed official assets, verifies checksum,
architecture, signature, and provenance, and replaces executable/resources as
one recoverable transaction. It is explicit, never background, and never edits
PATH, shell profiles, quarantine, or the App.

Ad-hoc signing is not Developer ID signing, notarization, or Gatekeeper
acceptance. Documentation may describe **Open Anyway** for the trusted download
but never advise disabling Gatekeeper, stripping quarantine, or installing a
root certificate.

Before every Core App distribution, rerun repository gates and artifact checks
for the exact clean tag and provenance, package contents, metadata,
entitlements, architectures, signatures, private-path disclosure, icon
resource/reference, checksums, licenses, and read-only DMG. Run a source/privacy audit for a Beta
only when a change can alter permissions, credentials, source containment,
external-data disclosure, generated state or logs, or package ownership; scope
it to the affected boundaries and their adversarial cases. Core App 1.0 repeats
the complete audit. Unchanged owners do not require another manual audit and
never waive the per-artifact checks or safety requirements above. Every
distributed Core App also completes one exact mounted-and-copied clean-account smoke:
Bootstrap, connect one disposable Triptych, open one Note, edit/save with exact
readback, relaunch and reopen. Unavailable optional integrations must not block
that Agent-independent Core path.

A Beta runs human icon inspection in Finder, Dock, standard small sizes,
Light/Dark, and the packaged App only when no retained accepted baseline exists
or when the canonical artwork, icon generation, bundle metadata, package
presentation, or supported macOS icon presentation changes. Core App 1.0
repeats the complete icon inspection. Structural icon checks remain per artifact.

For a Beta, packaged Search, Inspector, conflict/recovery, Finder restoration,
and integration-specific journeys are change-triggered by their functional
owner or package boundary. Core App 1.0 includes one representative packaged
journey for each of those distinct boundaries. Deterministic suites retain
state variants, and §20 retains its bounded human checks; do not repeat either
matrix in every clean-account artifact smoke.

When the Finder-restoration journey needs human judgment, limit that judgment
to Finder-owned Trash naming/collision presentation and restoration
discoverability. Receipt stages, separately moved
Critiques, dirty peers, File Provider/sync races, original-path reappearance,
Trash emptying, and cleanup recovery remain deterministic or system-integration
dimensions; they do not each create another human process interruption. Reuse
an applicable §20 representative check instead of duplicating it.

Agent Collaboration distribution additionally verifies independent CLI
installation and version, both user-scope setup commands, Core Protocol
availability, production-bridge availability, and one representative route
through current status, retrieval, a mutation, Agent Changes, recovery, and the
unavailable-App fallback. Include CLI self-update when the updater or installer
changes and for 1.0. Deterministic suites retain checksum/provenance rejection,
interruption stages, multiple-workspace selection, stale/conflict,
outcome-unknown, App restart, and path/fingerprint rejection coverage. Do not
multiply those variants into the clean-account or §20 human journey. Use
disposable fixtures only.

A future notarized channel must rebuild from the exact release commit and repeat
external verification; never re-sign an already accepted artifact.

## 22. Unresolved target decisions

Only current questions that can still change the target belong here:

- decide whether any provisional interface metric should become normative after
  §20's representative adaptation and human visual-acceptance set.
- define the replacement Research Record storage, continuing-question/step
  structure, creation and editing authority, Search fields, and activation of
  its interface before enabling Record production.
- define a lightweight, nonauthorizing Handoff and its complete-copy fallback
  before Scholium offers a route from a Note or selection into an external
  Agent conversation.

Resolution updates the owning chapter and removes the question in the same
patch. Git, not this specification, retains decision history.
