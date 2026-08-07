# Implementation Status: Verification Evidence

Part of the dated status set rooted at [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md).
This chapter owns the latest dated automated, UI, performance, visual, and
distribution evidence. A passing result proves only the stated checkout,
fixture, environment, and boundary; it does not redefine the target or close
human, packaged, or release acceptance unless explicitly stated.

## Current verification evidence

**Latest documentation-only check:** 2026-08-07
**Latest complete repository gate:** 2026-08-04

### Documentation authority

**Current passing result**

`validate-documentation-authority.py` passed the reorganized closed set with
three manifests, 22 chapters, and 102 checked local links. `git diff --check`
also passed.

**Boundary of the claim**

Documentation structure, local links, anchors, chapter ownership, and patch
whitespace only. No source build, product test, UI journey, packaging, or
release gate was rerun for this documentation-only cutover.

### Workspace registry recovery

**Current passing result**

On 2026-08-07, the Xcode 27 beta toolchain ran the focused Core workspace,
Application runtime, and App bootstrap suites against repository-local
disposable fixtures. The exercised path distinguishes malformed current-schema,
newer-schema, and I/O registry health; rejects broken current-schema references
without projecting an empty workspace; preserves malformed bytes before
relinking; retains newer or unreadable state in place; and changes a failed
relink to Retry-only I/O recovery. Existing runtime membership tests also cover
the unchanged live/snapshot ownership boundary.

**Boundary of the claim**

Focused Core/Application/App-controller evidence only. No full UI automation,
genuine VoiceOver or Full Keyboard Access exercise, installed App/CLI journey,
package artifact, complete repository gate, or researcher acceptance was
rerun.

### Research Context contract cutover

**Current passing result**

On 2026-08-07, the Xcode 27 beta toolchain ran the focused Research Context
contract, process-bound Agent Session, and local bridge suites against
repository-local disposable fixtures. The exercised path covers closed clauses,
typed Property/direct-Relation provenance, CRLF mixed-script exact-source
pages, continuation byte reconstruction, stale query/revision cursors,
surrogate-pair range rejection, and complete bridge-envelope size for a maximum
legal exact-source page.

**Boundary of the claim**

Focused Contracts/Application/bridge evidence only. No complete repository
gate, installed App/CLI journey, package artifact, assistive-technology test, or
researcher acceptance was rerun.

### Repository gate

**Current passing result**

`verify.sh` passed the closed 3-manifest, 23-chapter documentation authority and all 93 checked local
links; 11 shipped `SKILL.md` roots; research-owner zero-residue guards; 185 WebEditor tests
and reproducible editor, mathematics, Mermaid, and license resources; deterministic RDF-1 v2 for
800 notes; 424 Core tests plus 3 isolated performance tests; 118 Contracts; 180 Application; 8 Local
Agent bridge; 1 serialized architecture measurement; 453 App tests; and 6 executable Research
Action/CLI boundary journeys. The executable journeys cover strict parsing, provider-discriminated
Search-v6 text and JSONL, Pairing through standard input, protected Session reload, bounded writes
and retries without exposed write identities, one canonical Result plus Continue Research, and one
separately authenticated Method-improvement Run. The gate also passed the public symbol graph,
sandboxed AF_UNIX bridge, isolation/dead-path checks, and an optimized Release build in 162.92
seconds.

**Boundary of the claim**

Automated source and disposable-fixture evidence, not a release artifact or human acceptance.

The same gate includes the direct-relation resolver and Search owner-range
evidence. Production residue guards found no parallel Research Memory, Search,
or research-authority path.

### Saved Search contract compatibility

**Current passing result**

With the Xcode 27 beta toolchain selected explicitly, the focused Search
contract suite passed 17 tests and the focused Window Search controller suite
passed 8 tests. The tests cover the explicit compatible-version declaration,
fail-closed handling of older and newer unrecognized versions,
raw-query-preserving editing diagnostics, and the no-execution stale Saved
Search path.

**Boundary of the claim**

Focused contract and window-owner evidence only. No complete repository gate,
packaged application, GUI adaptation matrix, or researcher acceptance was
rerun.

### Search Case Pack

This is a minimal, disposable-fixture case set for researcher review. It
records query, scope, expected locator or field, observed result, and the
current boundary without copying contract versions, test counts, measurements,
or open-work ledgers.

#### Case A: Property provenance and discovery

- Query and scope: `property:language="  ANCIENT Greek  "`, Triptych; completion probe `property:lan`.
- Expected: one Note with the exact Property value range; a scoped candidate may complete `property:language`.
- Observed: `Topic.md` is returned with Property mode `exact_string_value`; the value range resolves to `Ancient   Greek`. Without `propertyKeys` context completion is empty; with authorized `language` context it returns `property:language`.
- Boundary: Property retrieval and source attribution are bounded. Whether the additional candidate materially improves discovery remains open to researcher review.

#### Case B: Direct relation direction

- Query and scope: `from-note:Anchor relation:supports`, Triptych; completion probe `from-note:Anch`.
- Expected: direct target only, with containing-Note source and relation direction.
- Observed: `Target.md` is returned; the relationship remains `supports`, direction `fromNote`, source `Anchor.md`; no transitive or anchor result is added. Without `noteIdentities` context completion is empty; with authorized `Anchor` context it returns `from-note:Anchor`.
- Boundary: Direct relation search is bounded and source-attributed. Whether the identity candidate improves discovery remains a researcher question, not an implementation claim.

#### Case C: Summary field locator

- Query and scope: `summary:inheritance`, Triptych.
- Expected: a summary-bearing Note only, with summary field and exact source range.
- Observed: `Summary.md` is the sole result, matched field `summary`, and the source range covers `inheritance`; a body-only Note is excluded.
- Boundary: Summary remains a discovery lead with exact source recovery; it is not evidence or a summary-only object.

The Property and relation completion probes are also captured by the Search
contract test so the boundary is reproducible without private material. The
case set is candidate evidence only; Imna's representative-result and
research-use judgment remains open.

### Search performance gate

**Current passing result**

The Search v6/schema 9 fixed 2,056-note mixed-script fixture recorded 817.019 ms cold rebuild,
19.915 ms incremental-publication p95, 30.352 ms warm-query p95, 52,171,976 database bytes, and
153,518,080 peak RSS bytes.

**Boundary of the claim**

One threshold-conformance run on Mac16,12 / macOS 27.0 / Xcode 27 beta; it does not establish
causation or packaged GUI latency.

### Architecture-focused UI

**Current passing result**

Current isolated journeys passed the exact-window Agent sheet (16.808 s), two-window projection
convergence (51.864 s), and the stable native-toolbar Sidebar/Inspector pointer journey (24.384 s).
The last journey resolves each Show/Hide state strictly beneath the real Toolbar accessibility
subtree and confirms one control identifier per peripheral. The 2026-08-04 Storage Unavailable
journey passed in 27.611 seconds, covering compact collapsed and expanded states, an unsuccessful
Retry that remains compact, and successful recovery to the Workspace frame.
Research Records journeys additionally passed Recommendations handling and parent-Record routing
(84.235 s), one keyed window reused by two same-Triptych Workspaces (55.143 s), comparison and
permanent deletion (54.721 s), and independent cross-Triptych windows with the 760 × 680 default,
the 700 × 520 minimum content size, native Scope-menu exposure, and View-index keyboard traversal
(139.596 s). A separate deterministic RTL journey passed mirrored View order and directional-key
traversal in 33.653 seconds.

Representative populated Records and Recommendations windows were also inspected directly in
Light and Dark after the leading-navigation placement change; both retained the semantic
Navigation/Document surfaces and one control treatment without transparent-material fallback.

The explicit direct-relation Search journey is implemented and compiles. XCTest attempts on
2026-08-04 did not enter the test body because the host timed out while enabling automation mode;
that harness result remains environment-blocked rather than a product failure. The same bounded
journey was then exercised directly in the isolated Debug QA app with the disposable nonprivate
fixture: the explicit `from-note` plus `relation:supports` query returned only `QA Autosave A`,
explained the direct-support relation without presenting the anchor Topic as a parallel result, and
opened the target Note in Source. This is a passing product-level manual automation observation,
not a substitute for a future XCTest regression run.

**Boundary of the claim**

Representative Debug/QA paths only; headless tests own durable, authentication, and transaction
claims. The direct-relation Search behavior is accepted for the Search Foundation engineering
handoff; a successful XCTest host-automation run remains test-infrastructure closure work.

### Complete UI baseline

**Current passing result**

The latest complete serial profile on 2026-07-28 enumerated all 74 then-current ordinary journeys.
Three harness failures and the actionable compact-width skip passed focused revalidation; genuine
VoiceOver speech remained conditionally skipped.

**Boundary of the claim**

It predates the final architecture batches; affected boundaries received focused tests, builds, and
the journeys above, but the complete UI profile was not rerun.

### Upgrade safety

**Current passing result**

A distinct-build disposable byte-hostile Triptych preserved path, size, SHA-256, permissions, and
mtime for all 195 authoritative files; only allowlisted manifest/identity changes occurred.

**Boundary of the claim**

QA-build evidence only; rerun for every release.

### Researcher visual evidence

**Current passing result**

On 2026-07-30 the researcher accepted representative 72ch behavior, mixed-script flow, 100%/200%
reflow, and Light/System and Dark document rhythm. The former RTL claim used an inert raw-HTML
surrogate and is withdrawn.

**Boundary of the claim**

Corrected Arabic/Hebrew direction remains open for direct reacceptance. Existing evidence is bounded
visual acceptance, not genuine assistive-technology, installed-IME, packaged-runtime, or release
acceptance.

### Distribution

**Current passing result**

Local source-first assembly passed metadata, licenses, resources, path-disclosure checks, signing
structure, standalone and bundled CLI execution, ZIP, and checksum smoke from an isolated temporary
output on 2026-08-04. The delivered smoke bundle was ad hoc signed. The latest complete repository
gate also passed an optimized Release build.

**Boundary of the claim**

No clean exact tag, external installation, published artifact provenance, G7 packaged sampling, G9,
or public release.


The source-first `v0.1.0-beta.1` target and G7/G9 protocols remain canonical in
[Specification §21](../Specification/10-release-and-open-decisions.md#21-release-requirements-and-acceptance).
Developer ID and notarization remain a future distribution-channel choice,
not a current Beta gate.
