# Scholium UI coverage derivation

The canonical specification manifest routes target workflows, visible
meanings, labels, and release requirements. The status manifest, live
construction, and current test harness establish reachability and evidence.
This reference defines how to derive a matrix; it deliberately contains no
feature inventory.

## Build the current matrix

For each affected task:

1. Read the controlling specification workflow and repository interface rules.
2. Classify each required state or action as reachable, migration debt,
   deferred, removed, or superseded-path residue using implementation status
   and live construction.
3. Inventory current deterministic tests and map each assertion to an
   observable user outcome; do not infer coverage from names or counts.
4. Record entry points, states, actions, recovery, accessibility adaptations,
   artifact class, and evidence still requiring a human.
5. Test unsupported artifacts only for exact preservation, visible rejection,
   or absence of authority; never reconstruct UI or a decoder from historical
   fixtures.

## Cross-cutting coverage categories

Apply the relevant categories to every workflow discovered above:

| Category | Stable questions |
|---|---|
| Identity and launch | Are selection, cancellation, persisted access, restoration, and same-named objects coherent? |
| Source authority | Do editing, rendering, properties, save, undo, and mode changes preserve the authoritative source and revision? |
| Navigation and focus | Do menu, keyboard, pointer, focus, window, and source-opening paths reach the same result? |
| Lifecycle states | Are ready, loading, empty, unavailable, stale, malformed, cancellation, completion, and retry distinct? |
| Failure and recovery | Does failure preserve researcher work, explain scope, and provide the documented recovery action? |
| Concurrency | Do independent windows, external edits, delayed work, and refreshes converge without stale overwrite or duplicate mutation? |
| Derived projections | Do search, links, diagnostics, rendering, and other projections identify their source revision and stale state? |
| Trust and provenance | Are authorship, authority, evidence class, privacy, and consequential actions visible and bounded? |
| Accessibility and input | Are meaningful labels, keyboard access, assistive technologies, system adaptations, speech, IME, and non-motion alternatives covered as applicable? |
| Artifact boundary | Is the claim limited to the exact unit, integration, QA, release, or human evidence actually exercised? |

## Artifact choice

- Use the repository's isolated QA app and disposable fixtures for routine
  deterministic interaction work.
- Use the exact release artifact only for claims about packaging, signing,
  entitlements, persisted access, clean installation, first launch, or release
  performance.
- Use exploratory computer control only as complementary visual or
  accessibility-tree evidence when no deterministic assertion exists.
- Never run any path against a private research vault.

## Human acceptance boundary

Automate setup and safeguards, but retain an explicit human gate for behavior
that genuinely depends on human speech, assistive-technology judgment, or IME
candidate selection. Synthetic events do not certify those conditions.

## Failure artifacts

Preserve only synthetic, test-owned evidence: build and fixture identity,
observed step and expected state, bounded timeout, relevant screenshot or
accessibility hierarchy, and redacted logs. Never attach private research
content or paths.
