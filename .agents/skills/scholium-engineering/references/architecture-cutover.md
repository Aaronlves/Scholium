# Scholium architecture cutover

Use this mode only when the requested change alters module dependencies,
runtime composition, state ownership, or delivery boundaries. Ordinary
implementation remains under the engineering entry workflow.

Before selecting this mode, apply [architecture classification and
decomposition](architecture-classification-and-decomposition.md). Record the
current and target at the same abstraction level and on the affected axes, then
choose the justified cut. A file or extension extraction that leaves ownership,
dependencies, lifecycle, and runtime composition unchanged is code organization,
not an architecture cutover.

## Establish the cutover contract

1. Read the current implementation architecture, package graph, construction
   roots, state owners, call sites, and focused tests.
2. Record current and target classifications, dependency edges, changed
   constraints, arrow direction, and every repository-owned importer.
3. Record each mutable fact's owner, lifetime, consumers, mutation routes,
   persistence, cancellation, teardown, transaction, and recovery behavior.
4. Separate target architecture, reachable implementation, superseded-path
   residue, unsupported preserved data, and verified acceptance.
5. Identify the enforced boundary that prevents the old ownership from
   returning without splitting required state or a durable transaction.

Do not justify a cutover through aesthetics, file size, framework novelty, or a
remembered diagram alone.

## Execute one bounded cutover

- Introduce or strengthen the narrow contract required by the target owner.
- Move the complete bounded responsibility and every repository-owned consumer
  in the same change; keep delivery adapters thin.
- Give each window feature one bounded owner; do not replace one god object with
  several mutually mutating objects.
- Route cross-feature effects through typed intents or application capabilities
  rather than direct controller mutation.
- Keep authoritative source and backend resources out of presentation models.
- Preserve cancellation, teardown, focused commands, window isolation,
  conflict handling, exact-source behavior, and recovery.
- Delete the superseded implementation, decoder, adapter, alias, fallback, and
  tests whose only purpose is to keep that path reachable. Do not leave a
  parallel route or temporary compatibility owner in reachable construction.

## Update the whole contract surface

Reconcile the package graph and import-boundary tests, runtime construction and
deallocation tests, state ownership and independent-window tests, affected
fixtures, implementation architecture, dated status, and developer guidance.
Unsupported pre-production data remains byte-unchanged and nonauthorizing; it
does not justify a decoder or product route.

Do not edit `Docs/SCHOLIUM_SPEC.md` merely to describe an implementation
refactor. Change target authority only when the researcher separately adopts a
product, interface, or release decision.

## Verify and report

Compile the dependency boundary, run narrow ownership and removal regressions,
then run the repository verifier once after the cutover stabilizes because this
mode is cross-layer implementation. Exercise representative
multiwindow, cancellation, save/conflict, and recovery behavior when the moved
responsibility affects them.

Report before/after dependency edges, ownership transfer, deleted paths,
compiler enforcement, tests executed, and any unverified environment. A
cutover is incomplete while the superseded route remains reachable.
