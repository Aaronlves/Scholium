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
**Agent Collaboration** adds external-Agent, CLI, Run, Session, Context, and
Record-production behavior to an already accepted Core App. Evidence or failure
in one profile does not silently pass or block the other. Release names and
notes state the accepted profile; an unaccepted optional profile is labelled
**Preview** and is never represented as part of the Core App verdict.

**Usable Core** must cover:

- Bootstrap, registration/restoration, independent windows, and storage failure;
- create/open/read/edit/autosave, Review/Edit/Source, Find/Replace, Search,
  Metadata/About, Settle, Library, tabs, and cross-vault navigation;
- formatting, Comments, Callouts, Wikilinks, Analysis references, image
  Import/Index, statistics, spelling, and exact YAML/source fidelity;
- native split behavior, focus, keyboard, light/dark, enlarged text, minimum
  supported width, and core VoiceOver; and
- external edits, conflicts, rename/move, system-Trash Note/Folder deletion and
  partial recovery, Finder restoration, Agent direct Undo, interrupted saves,
  and multiple-window dirty-peer behavior.

**Agent Collaboration Beta/1.0** additionally covers applicable Research
Actions, Skills and routed references, Profiles/Results, direct Agent start and
GUI handoff, secure
process-bound Sessions, Activity Ledgers, Research Context, portable Records,
Follow-up/feedback, Connections, Attention, Zotero read-only/unavailable
behavior, CLI parity, Record Search, adaptations, and resizable auxiliary-window
usability at its supported bounds. Exact initial frames and coordinates remain
implementation defaults rather than release thresholds.

Search acceptance covers scope/provider authorization, Metadata and relation
provenance, Record attribution/locators, Explain/completion, Saved Search
re-evaluation, App/CLI parity, stale refusal, corruption rebuild, and
incremental/clean equivalence. Retrieval success never establishes
philosophical relevance, evidential support, or researcher acceptance.

Agent evidence includes one direct start and one copied one-use handoff;
stdin-only code exchange; Session secrecy, expiry, restart invalidation, and
re-pairing; authenticated local bridge; current-Run scope; reload; bounded
Context and multi-document writes; End; recovery; accessibility; and
unavailable fallback. It does not require an embedded or provider-specific
Agent runtime.

These are functional evidence categories, not one serial clean-account or human
script. Deterministic fixtures own protocol variants and failure branches;
packaged acceptance owns downloaded artifact, independent installation,
version, and production-bridge boundaries; §20 owns one representative human
Agent journey. Do not repeat every deterministic variant in the packaged or
human path merely to restate its coverage.

Method-content acceptance follows §8.1. Before the first Agent Collaboration
1.0, each shipped bundled template has one bounded representative run and
independent review; later releases review only new or materially changed
templates. Sustained real-research use and comparative Method evaluation do not
block a release or certify general philosophical adequacy. This cadence never
relaxes a known fabrication, source-fidelity, researcher-authority, privacy, or
permission defect.

Evidence that exercises research content uses disposable nonprivate fixtures.
Focused development evidence records the procedure or command, inputs,
environment, and result only to the extent needed to reproduce its bounded
claim; inapplicable source-revision, artifact, or fixture fields are omitted.
Evidence presented for a release or gate records the exact source revision,
toolchain, build/artifact, fixture identity, procedure or command, and result.

### 21.3 Release gates

| Gate | Required condition |
| --- | --- |
| **G1 Functional completeness** | Every in-scope requirement has evidence or explicit waiver. |
| **G2 Workflow independence** | Manual core works without Obsidian, Zotero, Agents, or manual filesystem repair. |
| **G3 Source integrity** | Exact-source tests cover malformed/unknown YAML, BOM/newlines, targeted edits, atomic failure, and readback. |
| **G4 Recovery and deletion** | Conflict, Agent Undo, save recovery, system-Trash receipts/cleanup, external deletion/restore/rename, and derived failure pass. |
| **G5 Scholarly transparency** | Source, researcher/Agent content, Discussion, Result, Settle, Critique, Fidelity, provenance, and uncertainty remain distinct. |
| **G6 Accessibility/localization** | §20's complete deterministic conformance and bounded representative human threshold are met for the named profile. |
| **G7 Performance** | The packaged-app protocol in §21.4 passes. |
| **G8 Documentation consistency** | Specification, architecture, status, README, source, and tests do not silently conflict. |
| **G9 Distribution integrity** | Distributed artifacts match an exact clean tag, source/licenses, signatures, architecture, checksum, and clean-account smoke test. |
| **G10 Agent collaboration** | Skills, Profiles/Results, Sessions, Ledger writes, Context, Records, and local bridges pass their journeys. |

Usable Core/0.1 requires G1–G4, G6, and G8. **Core App Beta** requires G1–G6,
G8, and G9 within the Core App profile and does not require G10. Beta
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
Separate generated Record fixtures cover current schema and attribution. Fixture
generators and runner ownership belong to
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

Before Core App distribution, verify the exact clean tag, source/privacy audit,
repository gates, package contents, metadata, entitlements, architectures,
signatures, icons, checksums, licenses, read-only DMG, clean-account App
installation, and representative first-launch, edit/save, Search,
conflict/recovery, and unavailable-optional-integration journeys.

Agent Collaboration distribution additionally verifies independent CLI
installation and version, production-bridge availability, and one representative
Action route through Session, Context, an applicable write or recovery, and
Result, plus the unavailable-App fallback. Include CLI self-update when the
updater or installer changes and for 1.0. Deterministic suites retain checksum/provenance
rejection, interruption stages, direct-start/handoff variants, restart,
re-pairing, expiry, preflight field and destination states, stale/replay/
conflict, and outcome-unknown coverage. Do not multiply those variants into the
clean-account or §20 human journey. Use disposable fixtures only.

A future notarized channel must rebuild from the exact release commit and repeat
external verification; never re-sign an already accepted artifact.

## 22. Unresolved target decisions

Only current questions that can still change the target belong here:

- decide whether any provisional interface metric should become normative after
  §20's representative adaptation and human visual-acceptance set.

Resolution updates the owning chapter and removes the question in the same
patch. Git, not this specification, retains decision history.
