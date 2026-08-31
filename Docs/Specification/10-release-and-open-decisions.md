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

Beta/1.0 additionally covers applicable Research Actions, Skills and routed
references, Profiles/Results, direct Agent start and GUI handoff, secure
process-bound Sessions, Activity Ledgers, Research Context, portable Records,
Follow-up/feedback, Connections, Attention, Zotero read-only/unavailable
behavior, CLI parity, Record Search, adaptations, and declared window sizes.

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

All material evidence uses disposable fixtures and records command, source
revision, toolchain, build/artifact, fixture identity, and result.

### 21.3 Release gates

| Gate | Required condition |
| --- | --- |
| **G1 Functional completeness** | Every in-scope requirement has evidence or explicit waiver. |
| **G2 Workflow independence** | Manual core works without Obsidian, Zotero, Agents, or manual filesystem repair. |
| **G3 Source integrity** | Exact-source tests cover malformed/unknown YAML, BOM/newlines, targeted edits, atomic failure, and readback. |
| **G4 Recovery and deletion** | Conflict, Agent Undo, save recovery, system-Trash receipts/cleanup, external deletion/restore/rename, and derived failure pass. |
| **G5 Scholarly transparency** | Source, researcher/Agent content, Discussion, Result, Settle, Critique, Fidelity, provenance, and uncertainty remain distinct. |
| **G6 Accessibility/localization** | §20's English/Simplified Chinese and accessibility threshold is met. |
| **G7 Performance** | The packaged-app protocol in §21.4 passes. |
| **G8 Documentation consistency** | Specification, architecture, status, README, source, and tests do not silently conflict. |
| **G9 Distribution integrity** | Distributed artifacts match an exact clean tag, source/licenses, signatures, architecture, checksum, and clean-account smoke test. |
| **G10 Agent collaboration** | Skills, Profiles/Results, Sessions, Ledger writes, Context, Records, and local bridges pass their journeys. |

Usable Core/0.1 requires G1–G4, G6, and G8; G9 applies to every distributed
artifact. Beta requires every applicable gate including G10. Baseline or partial
evidence must not be presented as a gate pass.

### 21.4 Packaged performance gate

Performance evidence has three distinct classes:

1. microbenchmarks detect internal regression;
2. scenario measurements use incomplete samples or nonrelease artifacts; and
3. product-gate measurements use the exact packaged Release app, frozen fixture,
   complete visible boundary, and full retained sample set.

Only product-gate evidence satisfies G7. Each latency metric uses five excluded
warm-ups and exactly 30 valid retained samples; p95 is nearest-rank.

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

Work exceeding 100 ms must expose accessible nonblocking progress within
100 ms; progress does not turn incomplete work into a pass. Editor callbacks
during input/scroll target under 5 ms and yield before a display-refresh
interval.

The frozen performance fixture contains 800 Notes and representative folders,
links, malformed frontmatter, large CJK, and 5,000-word Review/Edit content.
Separate generated Record fixtures cover current schema and attribution. Fixture
generators and runner ownership belong to
[Documents and Editor](../Architecture/06-documents-and-editor.md#documents-and-codemirror).

The gate uses one clean exactly tagged packaged app, prepared measurement
driver, unchanged reference-machine record, isolated Application Support and
preferences, and user-visible/accessibility-complete boundaries. Retain raw
durations, summary statistics, invalid-sample reasons, correctness, memory,
machine/artifact/fixture identities, and raw outputs outside research vaults.
Provenance mismatch, changed process set, missing metrics, incomplete samples,
or unapproved thresholds fails closed.

The large-CJK fixture must remain byte-exact and editable at beginning, middle,
and end with Undo and mode switching. Repeated Note/mode switching must show
stable editor/renderer counts and bounded decelerating memory growth rather
than a constant leak. This is a correctness/stability condition, not a
percentile substitute.

### 21.5 Source-first Beta distribution

Each source-first Beta release requires:

- exact public prerelease tag/package provenance;
- recorded app version/build and minimum supported macOS;
- corresponding `GPL-3.0-or-later` tagged source and license notices;
- architecture-labelled DMG containing the ad-hoc-signed App plus Applications
  alias; and
- separate version-matched CLI archive, with checksums for both artifacts.

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

Before distribution, verify the exact clean tag, source/privacy audit,
repository gates, package contents, metadata, entitlements, architectures,
signatures, icons, checksums, licenses, read-only DMG, clean-account App
installation, independent CLI installation, and representative first-launch,
edit/save, Search, conflict/recovery, Action, and unavailable-integration
journeys. Use disposable fixtures only.

A future notarized channel must rebuild from the exact release commit and repeat
external verification; never re-sign an already accepted artifact.

## 22. Unresolved target decisions

Only current questions that can still change the target belong here:

- decide whether any provisional interface metric should become normative after
  the complete adaptation and human visual-acceptance matrix.

Resolution updates the owning chapter and removes the question in the same
patch. Git, not this specification, retains decision history.
