# Scholium observability

## Categories

Use stable `Logger` categories for launch, vault, repository, indexing, search, rendering, editor bridge, relationships, canvas, Zotero, proposals, and packaging. Log a lifecycle or failure boundary, not every function call.

## Privacy

- Treat note bodies, titles, tags, citations, search queries, Zotero metadata, full paths, and proposal content as private.
- Prefer vault UUID, redacted relative-path hashes, counts, byte sizes, durations, and typed error codes.
- Never enable public interpolation merely to make local debugging convenient.
- Keep diagnostic artifacts outside vaults and require an explicit user action before collecting content-bearing evidence.

## Signposts and metrics

Bracket operations with clear start/end or interval signposts:

- vault open and initial scan;
- index build and incremental refresh;
- search query evaluation;
- note load, detached Markdown projection, Read WKWebView navigation/interactive readiness, and source-line focus;
- CodeMirror bundle startup, editor-ready handshake, document transfer, bounded delta application, any save-buffer reconciliation, and autosave commit;
- HTML/PDF export rendering and destination write as separate intervals;
- relationship rebuild;
- save, snapshot, conflict check, and post-save refresh;
- canvas layout/load/persist.

Attach counts and sizes that explain workload. Keep the signpost name stable so Instruments comparisons remain meaningful.

## Diagnostic discipline

- Correlate one user interaction across services with a non-content identifier.
- Preserve underlying error categories while presenting user-safe messages.
- Avoid logging the same failure at every layer; record ownership once and propagate context.
- Make verbose diagnostics opt-in and bounded.
- Report which build and logging level produced a trace.

Observability is evidence collection, not proof of correctness. Pair traces with the relevant fidelity and trust-boundary tests.
