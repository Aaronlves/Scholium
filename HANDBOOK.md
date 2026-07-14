# Scholium Workspace

Scholium is a local-first macOS research workbench for sustained humanities research. This file is the repository entry point and authority map; it does not duplicate product, design, or implementation documentation.

## Authority map

1. [`Docs/PRODUCT_GUIDE.md`](Docs/PRODUCT_GUIDE.md) defines the target product, Scholium Triptych, workflows, terminology, boundaries, and non-goals.
2. [`Docs/DESIGN_HANDBOOK.md`](Docs/DESIGN_HANDBOOK.md) defines stable interface design, accessibility, exact state meanings, and action labels.
3. [`Docs/IMPLEMENTATION_STATUS.md`](Docs/IMPLEMENTATION_STATUS.md) records current-build evidence, target differences, and migration status.
4. [`README.md`](README.md) provides setup, build, test, storage, and repository orientation.
5. [`AGENTS.md`](AGENTS.md) enforces these authorities during repository work.

Target rules are not implementation claims. Live code and executable tests establish current reachability.

## Non-negotiable invariants

- Exact Markdown bytes are authoritative; rendered HTML, parsed YAML, caches, and indexes are projections.
- Preserve BOM, newline style, comments, unknown YAML, ordering, quoting, multiline values, and final newlines outside explicitly changed ranges.
- Treat Scholium, Obsidian, external agents, sync tools, Finder, and other editors as concurrent filesystem participants.
- Never silently replace a dirty buffer after an external change.
- Keep source, researcher writing, agent content, review records, and derived diagnostics visibly distinct.
- Treat neutral links and transitive paths as Connections, never philosophical evidence.
- Store generated state outside research vaults except for the small portable `.scholium/` structure explicitly defined by the Product Guide.
- Test only with disposable nonprivate fixture vaults, never real research vaults.

## Development entry point

```bash
cd /path/to/Scholium
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./Tools/Scripts/verify.sh
```

See the README for all other development and QA commands.
