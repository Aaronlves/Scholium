# Scholium

Scholium is a local-first macOS research workbench where researchers and external agents develop source-grounded work across Scholium Triptychs.

## Documentation

Use one authority for each question:

1. [Product Guide](Docs/PRODUCT_GUIDE.md): what Scholium should become—Triptych structure, research workflows, terminology, feature boundaries, and non-goals.
2. [Design Handbook](Docs/DESIGN_HANDBOOK.md): how Scholium should look and behave, including exact interface state meanings and action labels.
3. [Product Requirements Document](Docs/PRD.md): a release-oriented synthesis of the Product Guide and Design Handbook into numbered requirements, gates, risks, and traceability. It does not override either authority above it.
4. [Implementation Status](Docs/IMPLEMENTATION_STATUS.md): what the current build demonstrates, where it differs from the target, and migration evidence.
5. This README, live construction call sites, executable tests, and scripts: setup plus current reachability evidence.

`AGENTS.md` enforces this hierarchy and provides repository rules; it does not
redefine the product or interface contract. Repository-specific development
skills are maintained in the tracked `.agents/skills/` tree; bundled product
skills remain separately governed under `Skills/`.

Target rules are not implementation claims. Live construction call sites, executable tests, and scripts remain the final evidence for current reachability.

Additional reference documents include the subordinate
[Implementation Architecture](Docs/IMPLEMENTATION_ARCHITECTURE.md),
[Editor Architecture](Docs/EDITOR_ARCHITECTURE.md),
[Property Profiles](Docs/PROPERTY_PROFILES.md),
[CSS Snippets](Docs/CSS_SNIPPETS.md), and the bundled
[Product Skill Packages](Skills/README.md).
The [Beta Performance Benchmark](Docs/PERFORMANCE_BENCHMARK.md) separates
internal regression microbenchmarks and scenario-only runs from the unexecuted
packaged-app G7 gate, and defines RDF-1 plus its fail-closed runner.

## Current implementation

The current build is a compiler-enforced modular monolith: immutable values and
use-case protocols live in `ScholiumContracts`, internal I/O lives in
`ScholiumCore`, and one headless `ScholiumApplication` layer is shared by the
macOS app and CLI. Core is not a public product and neither delivery target can
import it. Reachable behavior includes multi-Triptych registration
and window routing, Triptych control, safe note lifecycle, Human Review,
Dialogue, Critique, Note History, whole-Triptych checkpoints, direct
revision-checked CLI writes, vault-wide Properties, Unclassified import,
unified search, protected CSS snippets, localhost-only Zotero reading, and a
first-party optional Zotero MCP service for external agents. The Canvas feature
has been removed from the product. Works folders remain ordinary
researcher-managed folders; Scholium does not register or manage projects. See
[Implementation Architecture](Docs/IMPLEMENTATION_ARCHITECTURE.md) for code
ownership and [Implementation Status](Docs/IMPLEMENTATION_STATUS.md) for
precise evidence and remaining gaps.

## Requirements

Running a packaged build requires macOS 26 or later. Testers do not need Xcode.

Building Scholium requires a complete Xcode installation with the compiler and
SDK required by `Package.swift`. The repository resolver honors an explicit
valid `DEVELOPER_DIR`, a complete `xcode-select` selection, or a conventional
beta or release Xcode bundle. Node.js is needed only when rebuilding the
TypeScript editor bundle.

## Build and test

Run development commands from the repository root.

Run the complete repository verification:

```bash
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
DEVELOPER_DIR="$developer_dir" ./Tools/Scripts/verify.sh
```

Useful development commands:

```bash
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
DEVELOPER_DIR="$developer_dir" swift build
DEVELOPER_DIR="$developer_dir" swift test
DEVELOPER_DIR="$developer_dir" swift run ScholiumApp
```

The optional external-agent Zotero transport is provided by the separately
built `scholium` CLI. See [Zotero MCP](Docs/ZOTERO_MCP.md) for its supported
source installation path, agent configuration, and guarded import contract.

When `WebEditor/` changes:

```bash
./Tools/Scripts/build-editor.sh
./Tools/Scripts/verify-editor-bundle.sh
```

These scripts install the locked npm dependencies in temporary storage rather
than the synced worktree. An in-tree `WebEditor/node_modules` is rejected;
remove it and rerun the repository script.

For deterministic interface work, use only the isolated QA app and disposable fixture copy:

```bash
./Tools/Scripts/build-qa-app.sh
./Tools/Scripts/run-ui-tests.sh
```

These commands use `/tmp/Scholium-QA.app` with bundle identifier
`com.kbmanager.qa` and a disposable copy of the directory selected by
`SCHOLIUM_TEST_VAULTS` (default: `~/Desktop/TestVaults`). They do not package a
release or open a real research vault.

Packaging, signing, notarization, and distribution are separate release work and are not part of ordinary verification.

## Source-first beta distribution

The planned first external build is `0.1.0-beta.1`: public tagged source under
`GPL-3.0-or-later` plus an optional ad-hoc-signed Scholium app ZIP and SHA-256
checksum on the same GitHub release page. The public beta contains the app only;
the standalone CLI is not a beta asset.

The convenience app is not Developer ID signed or notarized. Testers do not
need Xcode, but must approve the trusted download through **System Settings →
Privacy & Security → Open Anyway** after the first launch attempt. Developer ID
and notarization remain optional future distribution improvements. See the
[Beta Release Guide](Docs/BETA_RELEASE.md) for the exact gates and installation
instructions.

## Triptych setup

First launch asks the researcher to choose independently located **Analyses**, **Topics**, and **Works** folders. Because portable `.scholium/` data sits beside Works, macOS also asks once for access to the folder containing Works; that folder is an access boundary, not a fourth vault. Co-location under one parent is recommended but not required. Add or change complete Triptychs later through **Manage Triptychs…** in Scholium Settings.

Use **File → New Triptych…** to configure another complete research domain, **File → Open Triptych** to open a registered Triptych in a separate window, and **File → New Window** to open another independent window for the focused Triptych. Every Triptych still contains exactly Analyses, Topics, and Works; Works subfolders are not app-managed projects.

Each Triptych needs its own Works parent because its portable `.scholium/` control directory sits beside Works. Scholium rejects two Triptychs whose Works folders would share that control directory.

The researcher-facing workspace always uses the three Triptych vaults. Stored legacy role aliases and the one-release legacy CLI search syntax remain read/command compatibility; the CLI no longer registers arbitrary vaults outside a complete Triptych.

## Agent CLI

Install the current CLI locally:

```bash
chmod +x Tools/Scripts/install-cli.sh
Tools/Scripts/install-cli.sh
```

Inspect available commands rather than relying on examples that may become stale:

```bash
scholium --help
scholium vault --help
scholium search --help
scholium links --help
```

The CLI supports registered-vault inspection, shared search, links, graph traces, canonical workspace catalog and Attention output, exact reads, Dialogue replies, and revision-checked direct note operations. Existing-note mutations require the current SHA-256 returned by `scholium read --format json`.

For isolated CLI testing:

```bash
SCHOLIUM_HOME=/tmp/scholium-cli-check swift run scholium --help
```

## Storage and safety

Authoritative research remains in the selected Markdown vaults. Machine-local reviews, Dialogue, checkpoints, indexes, saved searches, and other device state remain under:

```text
~/Library/Application Support/Scholium/
```

A small portable `.scholium/` directory beside Works stores only the Triptych manifest, Triptych-local settings, Properties configuration, Critique configuration and associations, identity mappings, Unclassified Markdown, and researcher-managed direct Skill packages under `.scholium/skills/<skill-id>/`. Each package has `SKILL.md` and may have bounded one-level `references/` or `templates/` resources. It contains no project registry, bookmarks, absolute paths, passwords, indexes, window sessions, or private review history.

Every authoritative app write must validate containment and the expected revision, preserve the previous bytes, validate frontmatter, write atomically, and report conflicts without discarding the editor buffer. Derived search, graph, render, and diagnostic state is disposable and must never reconstruct writable source.

Do not use real research vaults for development tests. Point
`SCHOLIUM_TEST_VAULTS` to a nonprivate fixture root, or use generated temporary
vaults for tests that do not require the UI harness.

## License

Unless otherwise noted, Scholium's original source code is licensed under the
[GNU General Public License, version 3 or later](LICENSE)
(`GPL-3.0-or-later`). Third-party components remain under their respective
licenses; see [Third-Party Notices](THIRD_PARTY_NOTICES.md).

## Repository map

```text
ScholiumContracts/         Immutable values, protocols, source semantics, errors
ScholiumCore/              Internal repositories, stores, indexes, watchers, I/O
ScholiumApplication/       Headless runtimes and capability implementations
Scholium/                  macOS app and human-facing interaction
ScholiumCLI/               CLI parsing, formatting, and Contracts handlers
WebEditor/                 TypeScript and CodeMirror sources
Tests/ScholiumContractsTests/
                           Boundary fidelity and compatibility tests
Tests/ScholiumCoreTests/   Core unit and integration tests
Tests/ScholiumApplicationTests/
                           Runtime, operation, event, and delivery-parity tests
Tests/ScholiumAppTests/    Window composition and interface architecture tests
UITests/                   Isolated macOS UI tests
Docs/PRODUCT_GUIDE.md      Target product authority
Docs/DESIGN_HANDBOOK.md    Interface and exact UI-contract authority
Docs/PRD.md                Requirements synthesis and release traceability
Docs/IMPLEMENTATION_STATUS.md
                           Current evidence and migration ledger
Docs/IMPLEMENTATION_ARCHITECTURE.md
                           Module, runtime, delivery, and state ownership
Docs/EDITOR_ARCHITECTURE.md
                           CodeMirror, WebKit, and editor-session boundary
Docs/PROPERTY_PROFILES.md   Target researcher-facing property vocabulary
Docs/CSS_SNIPPETS.md       Supported document-style customization contract
Skills/README.md           Bundled product-skill architecture and evidence boundary
Docs/BETA_RELEASE.md       Source-first beta policy and release gates
AGENTS.md                  Repository design/build rules and authority routing
.agents/skills/            Repository-specific development-agent skills
Tools/Scripts/             Build, verification, QA, and release scripts
Docs/PERFORMANCE_BENCHMARK.md
                           RDF-1 fixture and packaged-app G7 protocol
```
