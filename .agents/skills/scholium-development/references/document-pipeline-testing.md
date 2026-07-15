# Scholium document-pipeline testing

## Choose a testable boundary

- Keep exact bytes, parsing boundaries, targeted patches, fingerprints, path authorization, proposal identity, and relationship semantics in `ScholiumCore` when shared by app and CLI.
- Extract deterministic app logic into an importable library target or add a dedicated testable target when it cannot be tested through `ScholiumCoreTests`.
- Do not preserve an untestable actor or view dependency merely to avoid a small target-boundary change.
- Keep AppKit, security-scoped bookmark, FSEvents, and packaged-resource checks as integration or packaged-app tests when platform behavior is the subject.

## Required layers

| Layer | Primary assertions |
|---|---|
| Exact document | byte ranges, BOM/newlines, YAML validation, targeted delta |
| Repository | conflict, containment, snapshot-before-write, rollback, readback |
| Parser parity | core and active app projections agree on boundaries and supported values |
| Search/link | deterministic query and resolution semantics; full/incremental equivalence |
| Watcher | event reconciliation, cancellation, rename/delete, self-write acknowledgement |
| Editor | UTF-16 range safety, source identity, selection/undo/focus preservation |
| Packaged app | resources, sandbox bookmarks, menus, accessibility, real responder chain |

## Fixture policy

- Resolve the canonical non-production fixture root from the package `README.md` and use disposable copies, generated fixtures, or temporary vaults only. Do not assume a package-local `TestVaults/` directory.
- Give each test exclusive temporary storage unless the suite is intentionally serialized.
- Include malformed and legacy files; do not test only canonical happy paths.
- Assert exact bytes after every attempted write, including failures.
- Record the random seed for generated or fuzz fixtures and persist the minimized regression case.

## Completion gate

Run the narrow suite during iteration and `./Tools/Scripts/verify.sh` before handoff. For behavior reachable only in the packaged app, package the exact build and report the smoke path separately; do not call it unit coverage.
