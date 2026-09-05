# Scholium observability

## Categories

Derive `Logger` categories from the current owning subsystems and keep their
names stable once emitted. Log lifecycle or failure boundaries, not every
function call; do not preserve the current subsystem inventory here.

## Privacy

- Treat research source, metadata, queries, imported data, full paths,
  researcher or agent-authored records, and recovery content as private.
- Prefer vault UUID, redacted relative-path hashes, counts, byte sizes, durations, and typed error codes.
- Never enable public interpolation merely to make local debugging convenient.
- Keep diagnostic artifacts outside vaults and require an explicit user action before collecting content-bearing evidence.

## Signposts and metrics

Bracket the affected current operation with clear start/end or interval
signposts at its user action, owning service, external boundary, commit, and
visible-ready or failure points. Derive the exact signposts from live
construction and the measurement question rather than copying a workflow list.

Attach counts and sizes that explain workload. Keep the signpost name stable so Instruments comparisons remain meaningful.

## Diagnostic discipline

- Correlate one user interaction across services with a non-content identifier.
- Preserve underlying error categories while presenting user-safe messages.
- Avoid logging the same failure at every layer; record ownership once and propagate context.
- Make verbose diagnostics opt-in and bounded.
- Report which build and logging level produced a trace.

Observability is evidence collection, not proof of correctness. Pair traces with the relevant fidelity and trust-boundary tests.
