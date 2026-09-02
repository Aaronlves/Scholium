# Scholium

[English](README.md) | [简体中文](README.zh-Hans.md)

> A local-first, document-authoritative research environment for philosophy
> and the humanities.

**Current public Core App Beta:** [v0.1.1-beta1](https://github.com/Aaronlves/Scholium/releases/tag/v0.1.1-beta1) ·
[Download Scholium for Apple silicon](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-v0.1.1-beta1-macos-arm64.dmg) ·
[Agent collaboration Preview: download the independent CLI](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-CLI-macos.zip)

Scholium is a native macOS research environment for sustained work in
philosophy and the humanities. Its content core is a researcher-governed,
document-authoritative scholarly knowledge base that one researcher and
invited external Agents may maintain together. The research document—not a
dashboard, task board, Agent conversation, or memory store—remains the primary
interface object. A field of inquiry takes shape as a **Triptych**:
**Analyses** of sources, **Topics** that gather concepts and debates, and
**Works** in which the researcher develops arguments of their own.

Markdown remains ordinary, inspectable text in folders selected by the
researcher. Reading, writing, Search, Connections, review, and recovery do not
depend on an Agent. When an external Agent is invited, the conversation remains
in its MCP host. Scholium exposes current retrieval and exact Note mutations
through the local MCP adapter, and records only machine-local Agent Change
evidence for confirmed mutations.

The Core App Beta verdict covers the local manual research environment. External
Agent collaboration and the independently installed CLI remain a separate
Preview until their own acceptance profile passes.

## Product position

Scholium is a scholarly knowledge base and research workbench, not a chat
wrapper or a standalone Agent-memory product. Across Agents and sessions,
research continuity comes from the same inspectable documents, sources, and
explicit researcher judgments—not from hidden model state or a parallel
private database.

The researcher is a constitutive participant in the knowledge base, not merely
the reviewer of memories chosen by a model. Exact writing, declared scope and
limitations, Settle, Critique dispositions, and deliberate next steps retain
their own narrow meanings. Opening, reading, silence, or permission to write
does not become acceptance, importance, or belief.

Source claims, interpretations, Agent reconstructions, researcher commitments,
objections, and later revisions remain distinguishable rather than being
flattened into unattributed facts or one confidence score. Derived Search
indexes, graph snapshots, caches, rankings, and machine-generated summaries
are disposable projections. They may improve discovery and context assembly,
but they never replace exact Markdown, sources, or explicit
researcher judgment as authority.

The manual core works without Obsidian, Zotero, or Agents. Scholium is not
project management, reference management, permanent AI chat, or a full
Obsidian replacement.

## Documentation

Use the smallest authority set that answers the question:

1. [Scholium Specification](Docs/SCHOLIUM_SPEC.md) is the sole target-authority
   manifest. Its declared chapters own product behavior, interface design,
   accessibility, release requirements, and active decisions.
2. [Implementation Architecture](Docs/IMPLEMENTATION_ARCHITECTURE.md) routes to
   the chapters that own modules, runtimes, state, and editor boundaries.
3. [Implementation Status](Docs/IMPLEMENTATION_STATUS.md) routes to current
   reachable capabilities and interface, open work, dated verification, and
   acceptance boundaries.
4. This README, live construction, tests, and scripts provide setup and current
   implementation evidence.

Target prose is not proof of implementation. The completed migration roadmap
and superseded decision records remain available through Git history rather
than as parallel authorities.

Task-specific operational references remain separate:

- [Advanced CSS target boundary](Docs/Specification/07-document-and-research-interface.md#1841-advanced-css-boundary)
- [First-party Zotero MCP transport](Docs/ZOTERO_MCP.md)
- [Scholium Core Protocol](ScholiumCore/Resources/Skills/Scholium%20System%20Skills/scholium-core-protocol/SKILL.md)

## Current implementation

Scholium is a compiler-enforced modular monolith. Immutable values and use-case
protocols live in `ScholiumContracts`; internal repositories, stores, indexes,
watchers, and filesystem I/O live in `ScholiumCore`; one headless
`ScholiumApplication` layer is shared by the native app and CLI. Neither
delivery target imports Core.

The current product supports independent Triptychs and windows, exact-source
Markdown editing, Search and Connections, Note and Folder file operations,
external-edit conflicts, interrupted-save recovery, Settle, Critique, Zotero,
and a fixed local MCP collaboration surface. Search remains one disposable
Note-only projection for the App, CLI, and MCP adapter.
Ordinary Wikilinks may carry source-owned multiline Markdown annotations with
`[[Target]]{{annotation}}`; Connect, Search, Review, Edit, and MCP all project
the same authored occurrence without inventing semantic classification.

The installed `scholium` executable exposes `scholium mcp serve`. It connects
an external MCP host only to the currently running Scholium App; it does not
launch the App, open a headless workspace, or read Triptych files directly.
The surface is exactly workspace status, Note search/read/link retrieval, and
explicit create/update/system-Trash mutations. Stable Note identities,
fingerprint compare-and-swap, editor flush, atomic write/readback, and derived
coherence remain App-owned.

Every confirmed MCP mutation produces one machine-local Agent Change with exact
revision evidence. Agent Changes support comparison and eligible direct Undo
for updates; they are not chat, permission, review, acceptance, Settlement, or
Research Records. Replacement Research Record and Handoff contracts remain
unavailable until their separate specification decision.

The release bundles only the thin Scholium Core Protocol Skill. Researcher-owned
method Skills live in the external Agent host; Scholium does not register,
inspect, or execute them. These paths establish engineering reachability, not
human acceptance or general philosophical adequacy.

See [Implementation Status](Docs/IMPLEMENTATION_STATUS.md) for exact evidence
and unresolved human, accessibility, performance, packaging, and release work.

## Requirements

Running a packaged build requires macOS 26 or later. The current public Beta is
for Apple silicon (`arm64`). Testers do not need Xcode.

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

Packaged performance uses a strict G7 baseline gate. Specification §21.3
defines when a complete campaign is required; a performance-affecting Beta runs
the affected packaged series. Normative thresholds, fixture, sampling,
provenance, and evidence requirements are in
[Specification §21.4](Docs/Specification/10-release-and-open-decisions.md#214-packaged-performance-gate);
current results and gaps are in Implementation Status.

## Source-first Beta distribution

Source-first Core App Beta releases publish exact tagged source under
`GPL-3.0-or-later` plus an architecture-labelled App DMG and SHA-256 checksum on
the same GitHub release page. An Agent Collaboration Preview may additionally
publish an independent version-matched `Scholium-CLI-macos.zip` and checksum.
Every emitted artifact must agree with the tag and package provenance. The App
is sandboxed and does not contain or install the CLI. Opening the DMG presents
Scholium beside an Applications alias so installation is one ordinary Finder
drag.

The current release is
[v0.1.1-beta1](https://github.com/Aaronlves/Scholium/releases/tag/v0.1.1-beta1):

- [Scholium App DMG for macOS arm64](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-v0.1.1-beta1-macos-arm64.dmg)
  ([SHA-256](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-v0.1.1-beta1-macos-arm64.dmg.sha256));
- [independent Scholium CLI](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-CLI-macos.zip)
  ([SHA-256](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-CLI-macos.zip.sha256)); and
- [exact tagged source](https://github.com/Aaronlves/Scholium/tree/v0.1.1-beta1).

After downloading an artifact and its adjacent checksum file into the same
folder, verify it before opening or installing:

```bash
shasum -a 256 -c Scholium-v0.1.1-beta1-macos-arm64.dmg.sha256
shasum -a 256 -c Scholium-CLI-macos.zip.sha256
```

On the exact tagged commit, the complete repository gate, optimized Release
build, DMG structure and signature checks, isolated CLI installation and PATH
launch, package checksums, and fixed 5 + 30 packaged performance gate passed.
That release used the then-current fixed sampling rule; current development uses
the bounded predeclared protocol in Specification §21.4. All four published
assets were downloaded again from GitHub and matched the release checksums. The
complete automated UI run plus the focused clean-account
closure established 88 functional passes; the opt-in VoiceOver-service
automation remained conditionally skipped when unavailable. The bounded human
VoiceOver, keyboard, IME and visual-adaptation checks in §20 remain open rather
than becoming passed evidence. See [Verification Evidence](Docs/Status/04-verification.md)
for exact test counts and boundaries.

The convenience app is not Developer ID signed or notarized. For a DMG release,
after downloading it from the trusted project release and verifying the
checksum:

1. open the DMG;
2. drag **Scholium** onto the **Applications** alias and eject the DMG;
3. try to open Scholium from Applications once;
4. open **System Settings → Privacy & Security** and choose **Open Anyway**;
5. authenticate and confirm **Open**.

For the historical `v0.1.0-beta.6` App ZIP, expand it and move **Scholium** to
Applications before following steps 3–5.

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

## Scholium MCP setup

Open **Settings → Research Guidance → Agent Integration** to inspect App,
bridge, and CLI availability, copy a host-specific setup command, or reveal the
bundled Core Protocol Skill. Scholium copies commands but never edits host
configuration or claims installation succeeded.

For a source checkout, build or install the CLI and register its absolute path:

```bash
Tools/Scripts/install-cli.sh
codex mcp add scholium -- "$PWD/.build/cli-prefix/bin/scholium" mcp serve
claude mcp add scholium --scope user -- "$PWD/.build/cli-prefix/bin/scholium" mcp serve
```

The App must already be running with the intended Triptych open. The stdio
helper uses a current-user-authenticated local bridge and fails explicitly when
the App, bridge, selected Triptych, or current state is unavailable. It never
falls back to direct filesystem or headless workspace access.

The first release publishes exactly seven tools:
`scholium_workspace_status`, `scholium_search_notes`,
`scholium_read_note`, `scholium_list_links`,
`scholium_create_note`, `scholium_update_note`, and
`scholium_trash_note`. MCP Resources, Prompts, Agent Sessions, Research
Actions, Handoff, and Research Records are not exposed.

An ordinary Wikilink may carry multiline, source-owned Markdown annotation as
`[[Target]]{{annotation}}`. Connect, Search, and `scholium_list_links` preserve
each occurrence's direction, annotation, local context, and source location;
they expose only the authored occurrence and never assign a relationship class.

## Storage and safety

Authoritative research remains in the selected Markdown folders. The small
portable `.scholium/` control structure beside Works contains the bounded
Triptych manifest, portable settings, stable identities, Metadata, Settlement,
Critique, and recovery state defined by the specification.

Bookmarks, absolute paths, window sessions, indexes, saved queries, recovery,
local bridge authentication, exact Agent Change evidence, and unsupported
pre-production bytes remain machine-local under:

```text
~/Library/Application Support/Scholium/State-v1/
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
Docs/Status/              Capabilities, interface, open work, and dated proof
Docs/ZOTERO_MCP.md         Non-normative first-party Zotero operator guide
Tools/Scripts/             Build, verification, QA, performance, and release tools
```
