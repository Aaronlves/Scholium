# Specification: Release and Open Decisions

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Sections 21–22.

## 21. Release requirements and acceptance

### 21.1 Evidence hierarchy

Evidence order is live source and construction, executable tests, isolated QA
on disposable fixtures, and dated status. Target prose, previews, and
compilation alone prove no workflow, accessibility, package, signing, or
performance result. Acceptance reports link to the owning Specification,
Architecture, Status, and evidence rather than copying them into another pack.

### 21.2 Primary acceptance journeys

**Usable Core** covers:

- Bootstrap success/failure, registration/restoration, and independent windows;
- create/open/read/edit/save, Document Find/Replace, versioned Note Search, and
  explicit cross-vault navigation;
- Edit/Source fidelity, formatting, Review passage Comment, and Markdown
  Callout authoring, Wikilink aliases, Analysis Reference completion, image
  attachment import, Document statistics, native spelling routes, and mode
  changes;
- categorized About/Properties, optional top-level Research fields, Settle,
  and simplified Actions;
- native split resize/visibility, Document tabs without shell reconstruction,
  focus, keyboard, light/dark, scaling, minimum width, and core VoiceOver; and
- external edits, conflicts, stable rename, Set Aside, Trash, checkpoints,
  restore/interruption, and cross-window dirty-peer behavior.

Later Beta/1.0 additionally cover applicable Research Actions, Skill
registrations, exact-Wikilink Practices, Action Profiles and Result Contracts,
Triptych collaboration, process-bound pairing/Sessions, Bounded Write Sets,
Research Context, portable Research Records and Researcher Evaluation,
hierarchical Materials, Research Guidance/Recovery, Connections, Attention,
Zotero unavailable/read-only behavior, CLI parity, shared Record Search,
deletion/restore, adaptations, and
1380/1080/900/minimum-width workspaces.
Search acceptance separately covers provider/scope authorization, literal
top-level Property presence and exact string matching, direct relation
direction, Record attribution and statement locators, Explain/completion,
Saved Search re-evaluation, App/CLI parity, stale refusal, corruption rebuild,
and incremental/clean-build equivalence. Passing retrieval fixtures does not
establish philosophical relevance, evidential support, or researcher
acceptance.

Direct-Agent evidence includes one researcher-copied handoff with the Run
locator, one-use Pairing Code, and Agent-owned CLI steps; pairing-code input
through stdin; single-use secure pairing; authenticated local Session;
app-process restart invalidation and same-Run re-pairing; no Pairing Code in an
argument, URL, vault, file, later prompt, Result, Record, or log; no Session
secret in any prompt or copied handoff; packaged local-bridge integrity; current-Run
scope; reload; Research Context; explicit End Action; bounded multi-document
write and recovery; keyboard/VoiceOver; and an unavailable fallback. It does
not require an embedded or provider-specific Agent runtime.

For material evidence, use disposable fixtures and retain command, source
revision, Xcode/SDK, build, fixture identity, result, and artifact location.

### 21.3 Release gates

| Gate | Required condition |
| --- | --- |
| **G1 Functional completeness** | Every in-scope requirement has evidence or waiver. |
| **G2 Workflow independence** | Manual core works without Obsidian, Zotero, agents, or manual filesystem work. |
| **G3 Source integrity** | Exact-source tests cover malformed YAML, unknown fields, BOM/newlines, comments, targeted edits, atomic failure, and readback. |
| **G4 Recovery and deletion** | Conflict, checkpoints/restore, Trash/purge, external rename, and derived failures pass fixture journeys. |
| **G5 Scholarly transparency** | Authoritative Markdown, Discussion turns, Action outputs, Settle, Critique, Fidelity, provenance, authority, agent feedback, and uncertainty remain visibly distinct. |
| **G6 Accessibility/localization** | Section 20's English and Simplified Chinese interface and declared accessibility threshold is met. |
| **G7 Performance** | The packaged-app protocol in §21.4 passes on the frozen fixture and approved reference machine. |
| **G8 Documentation consistency** | Specification, architecture, status, README, source, and tests do not silently conflict. |
| **G9 Distribution integrity** | External binaries use a clean exact tag, corresponding GPL source/licenses, no private state, accurate signing/architecture, checksum, and clean-account smoke test. |
| **G10 Agent research collaboration** | Skill/Practice routing, Profiles/Result Contracts, Triptych collaboration, process-bound Sessions, bounded writes, Research Context, Records/Evaluation, and local bridges pass their journeys. |

Usable Core/0.1 require G1–G4, G6, and G8; G9 applies to any distributed
artifact. G6/G7 baselines and gaps must not be misrepresented as Beta passes.
Beta requires every applicable gate including G10. No release gate requires
provider-specific task creation, auto-submission, background Agent execution,
or **Run with Codex**. Current evidence belongs only in
[Implementation Status](../IMPLEMENTATION_STATUS.md).

### 21.4 Packaged performance gate

Performance evidence has three noninterchangeable classes:

1. regression microbenchmarks detect internal slowdowns;
2. scenario measurements exercise an incomplete fixture, fewer than 30
   retained samples, or a nonrelease artifact; and
3. product-gate measurements exercise the exact packaged Release app, frozen
   RDF-1, complete visible boundaries, and the full retained sample set.

Only the third class can satisfy G7. Debug builds, unit tests, internal timers,
human stopwatches, and partial memory series are never substitutes.

The non-Editor candidate Beta thresholds remain subject to explicit
release-owner approval. If approved, use nearest-rank p95 over exactly 30 valid
samples after five excluded warm-ups:

| Interaction | Candidate p95 limit |
| --- | ---: |
| Warm library launch to a usable note list | `< 1,000 ms` |
| Indexed Note Search query to complete visible results | `< 100 ms` |
| Warm Review-note activation to interactive rendering | `< 300 ms` |
| Application-cold 5,000-word Review-note activation to interactive rendering | `< 1,000 ms` |

The release owner has approved these Editor Beta limits. Each p95 uses the same
five-warm-up/30-retained-sample nearest-rank protocol; every retained sample
must also remain below its maximum:

| Editor interaction | p95 limit | Every-sample maximum |
| --- | ---: | ---: |
| Committed key input to first painted edit | `< 100 ms` | `< 200 ms` |
| Edit/Source request to visible and accessible requested mode | `< 100 ms` | `< 200 ms` |
| Cached-preview request to visible and accessible preview | `< 100 ms` | `< 200 ms` |
| Warm Edit activation to visible, accessible, interactive editor | `< 200 ms` | `< 300 ms` |
| Application-cold 5,000-word Edit activation to visible, accessible, interactive editor | `< 750 ms` | `< 1,000 ms` |
| One visible-range projection | `< 3 ms` | `< 5 ms` |

An interaction that cannot complete within 100 ms must expose nonblocking,
accessible progress feedback within `< 100 ms`; feedback does not convert an
unfinished interaction into a latency pass. During input and scrolling,
Editor work on the main thread targets `< 5 ms` per callback and must yield
before one display-refresh interval. A product-gate report that omits any
approved Editor latency metric, its every-sample maximum, correctness, or the
retained-memory series fails closed.

RDF-1 is the frozen deterministic 800-Note fixture for Library, Search, Review,
Edit, large CJK source, folders, links, and malformed-frontmatter coverage.
Research Record provider fixtures remain separate generated inputs with strict
current-schema attribution, participants, actually-used Materials, calendar
boundaries, and exact fingerprints. All are disposable test data, never
research source or product authority. Their generator, manifest, and runner
ownership belong to [Documents and Editor](../Architecture/06-documents-and-editor.md#documents-and-codemirror).

The gate must use the exact app produced by the release packager from one clean,
reviewed, exactly tagged commit. App provenance, tag, commit, source-clean
state, architecture, and fixture manifest must match. One unchanged machine
record covers macOS, hardware, power mode, display, foreground applications,
window size, accessibility settings, and logging. Each metric uses isolated
Application Support, preferences, bookmarks, and derived state.

The measured boundary is user-visible and accessible: a selectable, unblocked
library; complete visible Search results; or rendered, interactive Review/Edit
content after native publication and editor-renderer readiness. Semantic
projection or an internal callback alone is insufficient. Retain raw durations, p50, p95,
maximum, mean, valid and invalid sample counts with reasons, correctness,
machine record, artifact identity, fixture identity, and raw outputs outside
every research vault. Missing process roles, changed process sets, provenance
mismatch, incomplete samples, or unapproved thresholds fail closed.

The 100,000-CJK fixture must remain editable at beginning, middle, and end with
working undo, mode switching, and byte-exact save. After 50 note/mode switches,
retained editor-renderer counts and total app-plus-renderer memory must converge
rather than grow monotonically. These are correctness and stability conditions,
not percentile results. Current measurements and remaining activation work
belong only in [Implementation Status](../IMPLEMENTATION_STATUS.md).

### 21.5 Source-first Beta distribution

The first external release identity is:

- tag and public label `v0.1.0-beta.1`;
- app marketing version `0.1.0`, build `1`, minimum macOS 26;
- exact tagged source under `GPL-3.0-or-later`; and
- an optional architecture-labelled, ad-hoc-signed Scholium app ZIP plus its
  SHA-256 checksum on the same release page.

The app bundle includes its version-matched `scholium` helper. There is no
separate public CLI asset. The release also includes applicable license texts
and notices, identifies verified architectures without overstating universal
support, and contains no real vault, Application Support state, bookmark,
credential, index, absolute private path, or research content.

Ad-hoc signing is not Developer ID signing, notarization, publisher
verification, or Gatekeeper acceptance. Testers may approve the trusted GitHub
download through **System Settings → Privacy & Security → Open Anyway** after
the first launch attempt. Documentation must never advise disabling Gatekeeper,
recursively removing quarantine, or installing an untrusted root certificate.

Before tagging or upload, freeze a reviewed clean commit; audit the tree and
history for private material; run complete repository verification with
disposable fixtures; package with the clean-source requirement; inspect app and
helper metadata, resources, entitlements, architecture, signatures, icon, ZIP,
checksum, and licenses; pass G7; and exercise the exact expanded ZIP in a clean
macOS account through first launch, Triptych setup, read/edit/save, Search,
conflict/recovery, Inspector/Action, restoration, and unavailable integrations.
No real research vault may be opened during release verification.

Developer ID signing, notarization, and stapling are optional future channel
improvements. If adopted, rebuild from the exact release commit and repeat the
complete external smoke test; never re-sign an already tested artifact or
share a certificate private key outside its responsible organization.

### 21.6 Change control

Every approved target change updates the affected canonical rule and removes
the text it replaces in the same patch. Git owns prior versions; this document
does not preserve supersession chains or compatibility narratives for an
unreleased product. Architecture records structural consequences, and status
records current reachability, open work, verification, acceptance, and release
evidence. Completed migration narratives remain in Git history. Temporary code
or visuals never become authority accidentally.

## 22. Unresolved target decisions

Sections 1–21 are the complete current contract. Git history owns replaced
rules and decision chronology. Implementation and acceptance gaps belong in
[Implementation Status](../IMPLEMENTATION_STATUS.md).

Only questions that can still change the target remain here:

- promote or revise provisional interface metrics only after the complete
  adaptation and human visual-acceptance matrix; and
- approve the remaining non-Editor packaged G7 p95 thresholds before they
  become release limits.

Resolving an item updates its owning canonical section and removes the item
from this list in the same patch.
