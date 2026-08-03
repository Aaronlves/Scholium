# Scholium

[English](README.md) | [简体中文](README.zh-Hans.md)

> A quiet, local-first writing room for philosophical work.

Scholium is a native macOS research workbench for attentive reading, source-
faithful analysis, conceptual development, and philosophical writing. The
research document—not a dashboard, task board, or chat transcript—remains the
primary interface object. A field of inquiry takes shape as a **Triptych**:
**Analyses** of sources, **Topics** that gather concepts and debates, and
**Works** in which the researcher develops arguments of their own.

Markdown remains ordinary, inspectable text in folders selected by the
researcher. Reading, writing, Search, Connections, review, and recovery do not
depend on an agent. When an external agent is invited, Scholium freezes exact
Targets, Materials, revisions, methods, and permissions so assistance remains
bounded, attributable, reviewable, and recoverable.

## Documentation

Use the smallest authority set that answers the question:

1. [Scholium Specification](Docs/SCHOLIUM_SPEC.md) is the sole target-authority
   manifest. Its declared chapters own product behavior, interface design,
   accessibility, release requirements, and active decisions.
2. [Implementation Architecture](Docs/IMPLEMENTATION_ARCHITECTURE.md) routes to
   the chapters that own modules, runtimes, state, and editor boundaries.
3. [Implementation Status](Docs/IMPLEMENTATION_STATUS.md) routes to current
   reachability, remaining work, completed migrations, the latest verification
   baseline, and open acceptance.
4. This README, live construction, tests, and scripts provide setup and current
   implementation evidence.

Target prose is not proof of implementation. The completed migration roadmap
and superseded decision records remain available through Git history rather
than as parallel authorities.

Task-specific operational references remain separate:

- [CSS Snippet Contract](Docs/CSS_SNIPPETS.md)
- [First-party Zotero MCP transport](Docs/ZOTERO_MCP.md)
- [Product Skill packages](ScholiumCore/Resources/Skills/README.md)

## Current implementation

Scholium is a compiler-enforced modular monolith. Immutable values and use-case
protocols live in `ScholiumContracts`; internal repositories, stores, indexes,
watchers, and filesystem I/O live in `ScholiumCore`; one headless
`ScholiumApplication` layer is shared by the native app and CLI. Neither
delivery target imports Core.

The current product supports independent Triptychs and windows, exact-source
Markdown editing, Search and Connections, note/folder lifecycle, external-edit
conflicts, checkpoints and per-Note recovery, Settle, unified Discussion,
Critique, Research Actions, editable Working Methods, Researcher Skills,
standing permissions, agent Note-change requests with independently bounded
child phases, portable Research Records, Recommended Bibliography, local
read-only Zotero context, and an optional first-party Zotero MCP transport.

Library, Set Aside, and Trash share one native AppKit folder-and-note outline
and the same browsing grammar. Library creates notes and folders and retains
menu, keyboard, accessibility, and drag alternatives for organization; Set
Aside and Trash remain browsable, and Put Back is direct and reversible. A
durably created or moved source is published immediately in its owning window
while disposable Search, graph, and diagnostic projections refresh in the
background.

Each Note has a vault-qualified stable identity distinct from its exact source
fingerprint. Renames and folder moves can therefore preserve editor, tab, and
research identity while every mutation still revalidates the current source
revision and destination before commit.

The public app, CLI, delivery contracts, and records use Action identity.
Protected Local Execution v2 remains an internal containment, revision,
completion, conflict, and recovery mechanism. Unsupported pre-production data
is left byte-unchanged, invisible, unparsed, and nonauthorizing; there is no
legacy-data product entry or compatibility command.

See [Implementation Status](Docs/IMPLEMENTATION_STATUS.md) for exact evidence
and unresolved human, accessibility, performance, packaging, and release work.

## Requirements

Running a packaged build requires macOS 26 or later. Testers do not need Xcode.

Building Scholium requires a complete Xcode installation with the compiler and
SDK required by `Package.swift`. The repository resolver honors an explicit
valid `DEVELOPER_DIR`, a complete `xcode-select` selection, or a conventional
beta or release Xcode bundle. Node.js is needed only when rebuilding the
TypeScript editor bundle.

## Build and test

Run commands from the repository root. The complete repository gate is:

```bash
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
DEVELOPER_DIR="$developer_dir" ./Tools/Scripts/verify.sh
```

Common development commands:

```bash
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
DEVELOPER_DIR="$developer_dir" swift build
DEVELOPER_DIR="$developer_dir" swift test
./Tools/Scripts/run-debug-app.sh
./Tools/Scripts/run-ui-tests.sh smoke
./Tools/Scripts/run-ui-tests.sh complete
```

The UI runner uses a disposable TestVault copy and isolated state beneath the
ignored repository `.build/` directory. `smoke` runs the canonical journey;
`complete` enumerates the current suite, builds once, and runs serially. These
are automated development checks, not human visual or assistive-technology
acceptance.

When `WebEditor/` changes, rebuild and verify its checked-in bundle:

```bash
./Tools/Scripts/build-editor.sh
./Tools/Scripts/verify-editor-bundle.sh
```

When a documentation manifest, canonical chapter, or README link changes,
validate the closed authority sets and local links:

```bash
python3 Tools/Scripts/validate-documentation-authority.py
```

The upgrade-safety runner compares distinct disposable QA builds without using
a research vault:

```bash
./Tools/Scripts/verify-qa-upgrade-safety.sh \
  --baseline .build/upgrade/baseline/Scholium-QA.app \
  --candidate .build/qa-runtime/Scholium-QA.app \
  --output .build/upgrade/evidence
```

All SwiftPM scratch, Xcode DerivedData, QA apps, fixture copies, indexes, logs,
and result bundles stay under repository-local ignored `.build/` paths. The
checkout itself must remain outside Desktop, Documents, CloudStorage, and other
File Provider-managed locations.

Use `Manage Scholium Development Storage.command` in Finder, or inspect and
clean rebuildable state from the command line:

```bash
./Tools/Scripts/manage-development-storage.sh report
./Tools/Scripts/manage-development-storage.sh clean-stale
./Tools/Scripts/manage-development-storage.sh clean-all
```

Clean commands are dry runs unless `--delete` is supplied after reviewing the
exact allowlisted targets. They never remove source, app state, packaged builds,
Triptych files, or portable `.scholium/` data.

Packaged performance is a separate release gate. Its normative thresholds,
fixture, sampling, provenance, and evidence requirements are in
[Specification §21.4](Docs/Specification/10-release-and-open-decisions.md#214-packaged-performance-gate);
current results and gaps are in Implementation Status.

## Source-first Beta distribution

The planned first external release is `v0.1.0-beta.1`: exact tagged source under
`GPL-3.0-or-later` plus an optional architecture-labelled, ad-hoc-signed app ZIP
and SHA-256 checksum on the same GitHub release page. The app contains its
version-matched CLI helper; there is no separate CLI asset.

The convenience app is not Developer ID signed or notarized. After downloading
from the trusted project release and verifying the checksum:

1. expand the ZIP and move **Scholium** to Applications;
2. try to open it once;
3. open **System Settings → Privacy & Security** and choose **Open Anyway**;
4. authenticate and confirm **Open**.

Never disable Gatekeeper or recursively remove quarantine. Exact release gates,
artifact contents, clean-account verification, and future signed-channel rules
are maintained in
[Specification §21.5](Docs/Specification/10-release-and-open-decisions.md#215-source-first-beta-distribution).

## Triptych setup

First launch asks the researcher to choose independently located **Analyses**,
**Topics**, and **Works** folders. Portable `.scholium/` data sits beside Works,
so macOS also requests access to the folder containing Works; that access
boundary is not a fourth vault. Co-location under one parent is recommended but
not required.

Use **File → New Triptych…** for another research domain, **File → Open
Triptych** for a registered Triptych in a separate window, and **File → New
Window** for another independent window on the focused Triptych. Two
Triptychs may not share the same Works-side control directory.

## Scholium CLI

From a packaged app, open **Settings → Research Guidance → Sources &
Integrations → Scholium CLI** and choose **Install**. Scholium installs its
version-matched helper at `~/.local/bin/scholium`, verifies it, and reports PATH
guidance without editing shell profiles.

For a source checkout:

```bash
Tools/Scripts/install-cli.sh
scholium version --format json
scholium doctor --format json
scholium help action
scholium action prepare --help
```

The CLI shares Application capabilities for registered Triptychs, Search,
links and graph traces, workspace catalog and Attention, exact reads,
Discussion replies, resumable Actions, Recommended Bibliography, and
revision-checked Note operations. Existing-note mutations require the current
SHA-256 returned by `scholium read --format json`.

`scholium agent mcp serve` exposes cooperative mid-run Note-change requests to
an external agent over stdio and the private same-user app bridge. It neither
launches Scholium nor grants writes. See the shipped
[CLI contract](ScholiumCore/Resources/Skills/Scholium%20System%20Skills/scholium-research-integration/references/cli-contract.md)
for the exact lifecycle and [Zotero MCP](Docs/ZOTERO_MCP.md) for the optional
first-party Zotero transport.

## Storage and safety

Authoritative research remains in the selected Markdown folders. The small
portable `.scholium/` control structure beside Works contains only the bounded
Triptych manifest, portable settings and Skills, current researcher-owned
state, active Discussion, and whitelisted Research Records defined by the
specification.

Bookmarks, absolute paths, window sessions, indexes, saved queries, protected
execution, recovery, transport state, assembled instructions, and unsupported
pre-production bytes remain machine-local under:

```text
~/Library/Application Support/Scholium/
```

Every authoritative write validates containment and the expected revision,
preserves displaced bytes, validates targeted source, writes atomically, and
reports conflicts without discarding a dirty editor buffer. macOS file
coordination negotiates access with other participants while descriptor-
relative validation remains the write authority; prewrite recovery retains
exact interrupted-save candidates rather than treating watcher events or an
incomplete operation as authority. Acceptance against a configured File
Provider domain remains explicitly open in Implementation Status. Derived
Search, graph, render, and diagnostic state is disposable and never
reconstructs writable source.

Never use real research vaults for development tests.

## License

Unless otherwise noted, Scholium's original source code is licensed under the
[GNU General Public License, version 3 or later](LICENSE)
(`GPL-3.0-or-later`). Third-party components retain their own licenses; see
[Third-Party Notices](THIRD_PARTY_NOTICES.md).

## Repository map

```text
ScholiumContracts/         Immutable values, protocols, and source semantics
ScholiumCore/              Internal repositories, indexes, watchers, and I/O
ScholiumApplication/       Headless capabilities shared by app and CLI
Scholium/                  Native macOS app and human-facing interaction
ScholiumCLI/               CLI parsing, formatting, and delivery adapters
WebEditor/                 TypeScript and CodeMirror source
Tests/                     Contract, Core, Application, and App tests
UITests/                   Isolated disposable macOS UI journeys
Docs/SCHOLIUM_SPEC.md      Canonical target-authority manifest and reading routes
Docs/Specification/       Normative product, interface, accessibility, and release chapters
Docs/IMPLEMENTATION_ARCHITECTURE.md
                           Subordinate architecture manifest and reading routes
Docs/Architecture/        Module, runtime, state, editor, and delivery chapters
Docs/IMPLEMENTATION_STATUS.md
                           Current-evidence manifest and reading routes
Docs/Status/              Reachability, debt, migrations, proof, and open acceptance
Docs/CSS_SNIPPETS.md       Advanced document-style customization contract
Docs/ZOTERO_MCP.md         Optional first-party Zotero transport guide
Tools/Scripts/             Build, verification, QA, performance, and release tools
```
