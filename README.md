# Scholium

Scholium is a local-first macOS research workbench where researchers and external agents develop source-grounded work across Scholium Triptychs.

## Documentation

Use one authority for each question:

1. [Product Guide](Docs/PRODUCT_GUIDE.md): what Scholium should become—Triptych structure, research workflows, terminology, feature boundaries, and non-goals.
2. [Design Handbook](Docs/DESIGN_HANDBOOK.md): how Scholium should look and behave, including exact interface state meanings and action labels.
3. [Product Requirements Document](Docs/PRD.md): a release-oriented synthesis of the Product Guide and Design Handbook into numbered requirements, gates, risks, and traceability. It does not override either authority above it.
4. [Implementation Status](Docs/IMPLEMENTATION_STATUS.md): what the current build demonstrates, where it differs from the target, and migration evidence.
5. This README, live construction call sites, executable tests, and scripts: setup plus current reachability evidence.
6. The repository [HANDBOOK](HANDBOOK.md): a concise entry point and authority map.

`AGENTS.md` enforces this hierarchy and provides repository rules; it does not redefine the product or interface contract. Private development-agent skills are intentionally maintained outside this repository.

Target rules are not implementation claims. Live construction call sites, executable tests, and scripts remain the final evidence for current reachability.

Additional reference documents include [Property Profiles](Docs/PROPERTY_PROFILES.md) and [CSS Snippets](Docs/CSS_SNIPPETS.md).

## Current implementation

The current build has a trust-first Markdown core plus reachable multi-Triptych registration and window routing, Triptych control, safe note lifecycle, Human Review, Dialogue, Critique, Note History, whole-Triptych checkpoints, direct revision-checked CLI writes, vault-wide Properties, Unclassified import, unified search, protected CSS snippets, and localhost-only Zotero reading. Canvas is temporarily absent from the stable UI while the document workflow is stabilized. Works folders remain ordinary researcher-managed folders; Scholium does not register or manage projects. See [Implementation Status](Docs/IMPLEMENTATION_STATUS.md) for precise evidence and remaining gaps.

## Requirements

Running a packaged build requires macOS 26 or later. Testers do not need Xcode.

Building Scholium requires the authorized beta Xcode installation at
`/Applications/Xcode.app` and Swift 6. Node.js is needed only when rebuilding
the TypeScript editor bundle.

## Build and test

Run development commands from the repository root.

Run the complete repository verification:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./Tools/Scripts/verify.sh
```

Useful development commands:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run ScholiumApp
```

When `WebEditor/` changes:

```bash
./Tools/Scripts/build-editor.sh
./Tools/Scripts/verify-editor-bundle.sh
```

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

Authoritative research remains in the selected Markdown vaults. Machine-local reviews, Dialogue, checkpoints, indexes, Canvas state, saved searches, and other device state remain under:

```text
~/Library/Application Support/Scholium/
```

A small portable `.scholium/` directory beside Works stores only the Triptych manifest, Triptych-local settings, Properties configuration, Critique configuration and associations, identity mappings, Unclassified Markdown, and researcher-managed Skills under `.scholium/skills/<skill-id>/SKILL.md`. It contains no project registry, bookmarks, absolute paths, passwords, indexes, window sessions, or private review history.

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
ScholiumCore/              Documents, repositories, identities, semantics, search
Scholium/                  macOS app and human-facing interaction
ScholiumCLI/               Current CLI and migration surface
WebEditor/                 TypeScript and CodeMirror sources
Tests/ScholiumCoreTests/   Core unit and integration tests
UITests/                   Isolated macOS UI tests
Docs/PRODUCT_GUIDE.md      Target product authority
Docs/DESIGN_HANDBOOK.md    Interface and exact UI-contract authority
Docs/PRD.md                Requirements synthesis and release traceability
Docs/IMPLEMENTATION_STATUS.md
                           Current evidence and migration ledger
Docs/BETA_RELEASE.md       Source-first beta policy and release gates
HANDBOOK.md                Concise repository authority map
Tools/Scripts/             Build, verification, QA, and release scripts
```
