# Scholium

Scholium is a local-first macOS research workbench where researchers and external agents develop source-grounded work across Scholium Triptychs.

## Documentation

Use the smallest authority set that answers the question:

1. [Scholium Specification](Docs/SCHOLIUM_SPEC.md): the sole target authority
   for product behavior, interface design, Scholarly Editorialism,
   accessibility, release requirements, and active decisions.
2. [Implementation Architecture](Docs/IMPLEMENTATION_ARCHITECTURE.md): the
   subordinate structural contract for modules, runtimes, state ownership, and
   the CodeMirror/WKWebView boundary.
3. [Implementation Status](Docs/IMPLEMENTATION_STATUS.md): current
   reachability, evidence, migration debt, and open acceptance.
4. This README, live construction call sites, executable tests, and scripts:
   setup plus current reachability evidence.

Target rules are not implementation claims. Live construction call sites, executable tests, and scripts remain the final evidence for current reachability.

Additional operational references include
[CSS Snippets](Docs/CSS_SNIPPETS.md), the
[first-party Zotero MCP transport](Docs/ZOTERO_MCP.md), and the bundled
[Product Skill Packages](ScholiumCore/Resources/Skills/README.md).
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

All SwiftPM build products, dependency checkouts, compiler indexes, and test
artifacts live under the ignored repository `.build/` directory. This is safe
because the checkout itself lives outside Desktop, Documents, CloudStorage,
and other File Provider-managed locations. Do not redirect build caches or
indexes to `/tmp`.

### Development storage

To inspect, open, or clean Scholium's development storage, double-click
[`Manage Scholium Development Storage.command`](Manage%20Scholium%20Development%20Storage.command)
in Finder. The native menu provides these operations:

- **Show Storage Report** reports the size and exact location of the active
  `.build`, stale development artifacts, and packaged builds.
- **Open** commands reveal `.build`, temporary directories, Xcode DerivedData,
  or `~/Applications/Scholium Builds` in Finder.
- **Delete Stale Artifacts** removes obsolete Scholium temporary files,
  DerivedData, QA apps, and caches left by the retired external-build layout.
  It preserves the active repository `.build`.
- **Delete All Rebuildable Artifacts** removes the same stale files and the
  active `.build`. The next build will download dependencies as needed, compile
  again, and rebuild its indexes.

The cleaner refuses to run while Swift, Xcode, or Scholium is active. Its
deletion allowlist is limited to recognized Scholium development paths. It
never removes source files, application state, packaged builds, Triptych
files, or portable `.scholium/` data.

The same operations are available from the command line:

```bash
./Tools/Scripts/manage-development-storage.sh report
./Tools/Scripts/manage-development-storage.sh clean-stale
./Tools/Scripts/manage-development-storage.sh clean-all
```

The two clean commands are dry runs by default: they print every candidate and
the recoverable space without deleting anything. Add `--delete` only after
reviewing that list:

```bash
./Tools/Scripts/manage-development-storage.sh clean-stale --delete
./Tools/Scripts/manage-development-storage.sh clean-all --delete
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
`com.scholium.qa` and a disposable copy of the directory selected by
`SCHOLIUM_TEST_VAULTS` (default: `~/Desktop/TestVaults`). They do not package a
release or open a real research vault.

Before adopting a future build, compare an old QA app and its candidate against
one disposable Triptych and one isolated application home:

```bash
./Tools/Scripts/verify-qa-upgrade-safety.sh \
  --baseline /tmp/Scholium-Previous-QA.app \
  --candidate /tmp/Scholium-QA.app \
  --output /tmp/Scholium-Upgrade-Evidence
```

The gate seeds BOM, CRLF, LF, no-final-newline, comment, unknown and multiline
YAML, Unicode/CJK, and empty-note cases. It records path, byte size, SHA-256,
permissions, and modification time before launch and after each app, then fails
if any file in Analyses, Topics, or Works changes. Portable `.scholium/` changes
also fail unless their path is explicitly reviewed in
`Tools/Fixtures/qa-upgrade-portable-allowlist.txt`. Logs, manifests, and both
`.xcresult` bundles remain in the requested evidence directory. Passing with
identical app hashes proves the harness only; release-to-release evidence needs
distinct baseline and candidate builds.

Packaging, signing, notarization, and distribution are separate release work and are not part of ordinary verification.

## Source-first beta distribution

The planned first external build is `0.1.0-beta.1`: public tagged source under
`GPL-3.0-or-later` plus an optional ad-hoc-signed Scholium app ZIP and SHA-256
checksum on the same GitHub release page. The public beta has no separate CLI
asset; the app contains its matching Scholium CLI helper for explicit user-local
installation from Research Guidance.

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

The researcher-facing workspace and CLI use only the current three-vault
Triptych contract. Pre-release role aliases and positional Search syntax are
not accepted.

## Scholium CLI

From a packaged app, open **Settings → Research Guidance → Skills → Advanced →
Scholium CLI** and choose **Install**. Scholium installs the version-matched helper
to `~/.local/bin/scholium`, reports whether that directory is discoverable in
the current PATH, and offers a PATH setup command without editing shell files.

The shipped [Scholium CLI Contract](ScholiumCore/Resources/Skills/Scholium%20System%20Skills/scholium-research-integration/references/cli-contract.md)
defines the exact agent lifecycle and failure behavior. The
[Zotero MCP guide](Docs/ZOTERO_MCP.md) covers the optional first-party Zotero
transport. This README remains the concise human installation entry point.

For a source checkout, build and install the current CLI locally:

```bash
chmod +x Tools/Scripts/install-cli.sh
Tools/Scripts/install-cli.sh
```

Inspect available commands rather than relying on examples that may become stale:

```bash
scholium version --format json
scholium doctor --format json
scholium help function
scholium function prepare --help
```

The CLI supports registered-vault inspection, shared search, links, graph
traces, canonical workspace catalog and Attention output, exact reads,
Dialogue replies, resumable Research Functions, Recommended Bibliography, and
revision-checked direct note operations. JSON Function results include typed
next actions; use `function show` for recovery and `function prepare-fidelity`
after a changed Develop or Revise run. Existing-note mutations require the
current SHA-256 returned by `scholium read --format json`.

For isolated CLI testing:

```bash
SCHOLIUM_HOME=/tmp/scholium-cli-check swift run \
  scholium --help
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
                           Contract and boundary tests
Tests/ScholiumCoreTests/   Core unit and integration tests
Tests/ScholiumApplicationTests/
                           Runtime, operation, event, and delivery-parity tests
Tests/ScholiumAppTests/    Window composition and interface architecture tests
UITests/                   Isolated macOS UI tests
Docs/SCHOLIUM_SPEC.md      Product, interface, and release target authority
Docs/IMPLEMENTATION_STATUS.md
                           Current evidence and migration ledger
Docs/IMPLEMENTATION_ARCHITECTURE.md
                           Module, runtime, state, and editor ownership
Docs/CSS_SNIPPETS.md       Supported document-style customization contract
ScholiumCore/Resources/Skills/README.md
                           Bundled product-skill architecture and evidence boundary
Docs/BETA_RELEASE.md       Source-first beta policy and release gates
Tools/Scripts/             Build, verification, QA, and release scripts
Docs/PERFORMANCE_BENCHMARK.md
                           RDF-1 fixture and packaged-app G7 protocol
```
