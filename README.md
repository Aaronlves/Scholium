# Scholium

[English](README.md) | [简体中文](README.zh-Hans.md)

> A local-first, document-authoritative research environment for philosophy
> and the humanities.

**Current public Beta:** [v0.1.1-beta1](https://github.com/Aaronlves/Scholium/releases/tag/v0.1.1-beta1) ·
[Download Scholium for Apple silicon](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-v0.1.1-beta1-macos-arm64.dmg) ·
[Download the independent CLI](https://github.com/Aaronlves/Scholium/releases/download/v0.1.1-beta1/Scholium-CLI-macos.zip)

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
depend on an agent. When an external agent is invited, Scholium records the
Run, exact targets, revisions, operations, outcomes, and scholarly result so
assistance remains attributable, reviewable, and recoverable without repeated
permission prompts.

## Product position

Scholium is a scholarly knowledge base and research workbench, not a chat
wrapper or a standalone Agent-memory product. Across Agents and sessions,
research continuity comes from the same inspectable documents, sources,
Research Records, methods, and explicit researcher judgments—not from hidden
model state or a parallel private database. This knowledge base can therefore
serve as an Agent's external long-term research memory, but Agent inheritance
is a way of using Scholium rather than a second product or content owner.

The researcher is a constitutive participant in the knowledge base, not merely
the reviewer of memories chosen by a model. Exact writing, declared scope and
limitations, Settle, attributed Discussion, Critique dispositions, Researcher
Evaluation, and deliberate next steps retain their own narrow meanings. A
later Agent may rely only on what the relevant owner, actor, revision, scope,
and action semantics actually establish. Opening, dwelling, silence, or
permission to write does not become acceptance, importance, or belief.

Source claims, interpretations, Agent reconstructions, researcher commitments,
objections, and later revisions remain distinguishable rather than being
flattened into unattributed facts or one confidence score. Derived Search
indexes, graph snapshots, caches, rankings, and machine-generated summaries
are disposable projections. They may improve discovery and context assembly,
but they never replace exact Markdown, sources, Research Records, or explicit
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
- [Research method resources](ScholiumCore/Resources/Skills/README.md)

## Current implementation

Scholium is a compiler-enforced modular monolith. Immutable values and use-case
protocols live in `ScholiumContracts`; internal repositories, stores, indexes,
watchers, and filesystem I/O live in `ScholiumCore`; one headless
`ScholiumApplication` layer is shared by the native app and CLI. Neither
delivery target imports Core.

The current product supports independent Triptychs and windows, exact-source
Markdown editing, Search and Connections, note/folder file operations, external-edit
conflicts, transaction-only interrupted-save recovery, Settle, unified Discussion,
Critique, and Research Actions with researcher-owned, externally editable
Action Skill folders and academic Profiles. Search v9 gives the app, CLI, Research
Records, and authenticated Research Context one typed retrieval owner for
lexical, canonical structured Metadata, explicit direct-relation, authored-summary, and Record
queries without turning the index into research authority.

An invited external Agent can pair locally with one researcher-created Run,
receive bounded research context, register additional relevant targets in the
Run Activity Ledger without another approval, perform revision-checked direct
edits, submit one result, leave a portable Research Record, and continue through
a separate Run. Process-bound Sessions provide attribution; exact transaction
leases, conflicts, recovery, and one Record-owned Researcher Evaluation preserve
researcher control. For a new Analysis, the standalone CLI first asks Scholium for the
current Analyses vault, applicable managed fields, optional Settings
preferences, the fixed `summary`/`keywords` scaffold, root-managed destination,
and path/identity/source recovery state; only
a ready preflight can start consequential creation. Analyze Records may carry
Literature Recommendations. Selected local or Zotero source material remains a
separately validated evidence channel, and the optional first-party Zotero MCP
transport remains available. Researcher-selected subfolders use a researcher-
created existing Analysis target rather than an Agent path assertion.
For a researcher-selected local source, authenticated Research Context delivers
bounded exact binary pages against the Run-frozen source fingerprint without
exposing its path, bookmark, or general filesystem access. After a confirmed
Agent write, reload and the supplied exact reread advance to that committed
revision while later external drift still fails closed.

These paths establish current engineering reachability, not that long-term
Agent inheritance or philosophical research quality has already been accepted.
Sustained research use, assistive-technology review, clean-account App/CLI and
external-Agent acceptance, and comparative evaluation remain explicit evidence
gates.

Library uses one native AppKit folder-and-note outline. It creates notes and
folders and retains menu, keyboard, accessibility, and drag alternatives for
organization. Note and Folder deletion use the macOS system Trash; Finder owns
restoration, while Scholium durably resumes separately disclosed associated
Research Record cleanup. A durably created, moved, or absent source is
published immediately in its owning window while disposable Search, graph, and
diagnostic projections refresh in the background.

Each Note has a vault-qualified stable identity distinct from its exact source
fingerprint. Renames and folder moves can therefore preserve editor, tab, and
research identity while every mutation still revalidates the current source
revision and destination before commit.

The public app, CLI, delivery contracts, and records use Action identity.
Protected Local Execution remains an internal containment, completion,
conflict, and recovery mechanism. Its stable authority envelope is independent
of the evolving private payload, so payload changes do not make unrelated Notes
undeletable. Unsupported payloads remain unparsed and nonauthorizing. If an old
file lacks a valid envelope, or a selected Note participates in a valid envelope
whose payload is unreadable, an explicit confirmation can archive its exact
bytes inside protected local storage and disable that old Run. Valid envelopes
keep this recovery Note-scoped; opaque files remain store-scoped. There is no
legacy decoder, migration, or compatibility command.

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

Packaged performance is a separate release gate. Its normative thresholds,
fixture, sampling, provenance, and evidence requirements are in
[Specification §21.4](Docs/Specification/10-release-and-open-decisions.md#214-packaged-performance-gate);
current results and gaps are in Implementation Status.

## Source-first Beta distribution

Source-first Beta releases publish exact tagged source under
`GPL-3.0-or-later` plus an architecture-labelled App DMG and independent
`Scholium-CLI-macos.zip`, with SHA-256 checksums on the same GitHub release
page. The tag and both artifacts' package provenance and versions must agree.
The App is sandboxed and does not contain or install the CLI. Opening the DMG
presents Scholium beside an Applications alias so installation is one ordinary
Finder drag.

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
All four published assets were downloaded again from GitHub and matched the
release checksums. The complete automated UI run plus the focused clean-account
closure established 88 functional passes; genuine VoiceOver remained
conditionally skipped when unavailable. Human mounted-DMG, visual, and
assistive-technology acceptance remain open rather than becoming passed
evidence. See [Verification Evidence](Docs/Status/04-verification.md) for exact
test counts and boundaries.

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

## Scholium CLI

During first-launch Agent preparation, or later under **Settings → Research
Guidance → External Tools & Citations → Scholium CLI**, choose **Copy CLI
Installation Instructions** and give that prompt to the external Agent. The
prompt authorizes only the official CLI release archive and only the executable
and adjacent resource bundle under `~/.local/bin`; it forbids `sudo`, PATH or
profile edits, alternative downloads, and quarantine mutation. The App does
not inspect, execute, install, update, remove, or report status for the CLI.
The copied instruction downloads only the
[official independent CLI archive](https://github.com/Aaronlves/Scholium/releases/latest/download/Scholium-CLI-macos.zip).

For a source checkout:

```bash
Tools/Scripts/install-cli.sh
export PATH="$PWD/.build/cli-prefix/bin:$PATH"
scholium version --format json
scholium doctor --format json
scholium help agent
scholium help agent start
```

The source-checkout installer keeps the development executable and its resource
bundle under `.build/cli-prefix`. The verified `scholium update` commands are
for the separately installed release pair under `~/.local/bin`.

The CLI shares Application capabilities for registered Triptychs, Search,
links and graph traces, workspace catalog and Attention, exact reads,
Discussion replies, resumable Actions with structured Analyze recommendations,
explicit `record list --note <stable-note-uuid>` and `record read <record-uuid>`
retrieval, and revision-checked Note operations. Record retrieval returns the
portable Record owner and its exact fingerprint without creating a Note
dossier. Existing-note mutations require the current SHA-256 returned by
`scholium read --format json`; text-mode `scholium read` emits the exact source
bytes without adding a final newline.

`Tools/Scripts/package-app.sh` emits the independent
`Scholium-CLI-macos.zip`, whose provenance reports the verified architecture.
Its `install.sh` performs the same
user-local first installation used by the copied Agent instructions without
changing shell or macOS security configuration. It resumes only an exact
partial copy from the same package and refuses to replace a complete install;
use `scholium update` for replacement. Installer and updater share one lock,
so concurrent attempts cannot publish a mixed executable/resource pair.
An installed CLI can explicitly check the official release with
`scholium update --check` or install a newer verified release with
`scholium update`; self-update does not run in the background or edit PATH and
leaves the existing executable/bundle unchanged when verification fails.

The installed `scholium agent` commands let an external Agent start a Run for a
selected Triptych or pair with one researcher-created Run, obtain its typed
context, record document activity, perform revision-checked mutations, submit
one result, continue research, and end
the Run through a mutually authenticated loopback bridge. `agent start` stores the protected
Session credential locally and needs no Pairing Code. Pairing the GUI-created
route still reads the one-time code through standard input;
the App alone creates the bridge's process-generation secret and the Agent uses
it through the installed CLI rather than minting a key. Scholium does not
launch or supervise the Agent. Action Skill folders are researcher-owned:
Settings assigns or reveals them, while Scholium never reads or edits their
contents. The project-discovered
[Core Protocol](ScholiumCore/Resources/Skills/Scholium%20System%20Skills/scholium-core-protocol/SKILL.md)
governs entry and is identified again by authenticated context for the Agent
Run workflow; installed command help owns current CLI syntax.
See [Zotero MCP](Docs/ZOTERO_MCP.md) for the optional first-party Zotero
transport.

## Storage and safety

Authoritative research remains in the selected Markdown folders. The small
portable `.scholium/` control structure beside Works contains only the bounded
Triptych manifest, portable settings and Skills, current researcher-owned
state, active Discussion, and whitelisted Research Records defined by the
specification.

Bookmarks, absolute paths, window sessions, indexes, saved queries, protected
execution, recovery, transport state, Agent Sessions, the local bridge
namespace, assembled instructions, and unsupported pre-production bytes remain
machine-local under:

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
