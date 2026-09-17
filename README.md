# Scholium

[English](README.md) | [简体中文](README.zh-Hans.md)

> A local-first, document-authoritative research environment for philosophy
> and the humanities.

**Current Core App Beta:** [v0.2.4-beta](https://github.com/Aaronlves/Scholium/releases/tag/v0.2.4-beta) ·
[Download Scholium for Apple silicon](https://github.com/Aaronlves/Scholium/releases/download/v0.2.4-beta/Scholium-v0.2.4-beta-macos-arm64.dmg)

This is the current App-only Beta distribution. The release owner performs UI
and accessibility acceptance separately; this release preparation does not
claim those checks as automated evidence.

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
Agent collaboration remains a separate
Preview until their own acceptance profile passes.

## Product position

Scholium is a scholarly knowledge base and research workbench, not a chat
wrapper or a standalone Agent-memory product. Across Agents and sessions,
research continuity comes from the same inspectable documents, sources, and
explicit researcher judgments—not from hidden model state or a parallel
private database.

Sources, interpretations, Agent reconstructions and researcher judgments remain
distinct. Derived indexes and renderings never replace exact Markdown or turn
permission to write into acceptance.

The manual core works without Obsidian, Zotero, or Agents. Scholium is not
project management, reference management, a general Agent harness, or a full
Obsidian replacement.

## Documentation

- [Specification](Docs/SCHOLIUM_SPEC.md): target product behavior, interface,
  accessibility and release contracts; includes [Design](Design.md).
- [Architecture](Docs/IMPLEMENTATION_ARCHITECTURE.md): module, state-owner,
  transaction and editor boundaries, not a source-code inventory.
- [Implementation Status](Docs/IMPLEMENTATION_STATUS.md): compact implementation
  scope, remaining work and dated proof. Reachability is not acceptance.
- [AGENTS.md](AGENTS.md): development and verification rules.

Each entry routes to its owning chapter. This README provides setup, not another
maintained feature list; Git preserves superseded decisions and change history.

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
./Tools/Scripts/lint.sh
./Tools/Scripts/lint.sh --fix
./Tools/Scripts/run-debug-app.sh
./Tools/Scripts/run-ui-tests.sh smoke
./Tools/Scripts/run-ui-tests.sh complete
```

`lint.sh` checks Swift source with the repository's `swift-format` configuration
and type-checks the WebEditor in isolated temporary dependencies. `--fix`
formats Swift source in place before checking it.

The UI runner uses a disposable TestVault copy and isolated state beneath the
ignored repository `.build/` directory. `smoke` runs the canonical journey;
`complete` runs the retained critical UI suite serially after one build. Neither
establishes human visual or assistive-technology acceptance. Use AGENTS.md to
select the scoped checks required for a change; the complete gate is not the
default for every task.

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

Scholium.app is the sole supported installation. Packaging produces an
architecture-labelled App DMG and SHA-256 checksum from an exact clean tag,
with corresponding GPL-3.0-or-later source and notices. The signed connection
helper and Core Protocol ship inside the App and update with it. There is no
standalone CLI distribution, installer or self-updater.

Opening the DMG presents Scholium beside an Applications alias. Verify the
adjacent SHA-256 file before installing. Current source changes do not alter
previously published artifacts; release acceptance and exact artifact evidence
remain in [Implementation Status](Docs/IMPLEMENTATION_STATUS.md).

The convenience app is not Developer ID signed or notarized. For a DMG release,
after downloading it from the trusted project release and verifying the
checksum:

1. open the DMG;
2. drag **Scholium** onto the **Applications** alias and eject the DMG;
3. try to open Scholium from Applications once;
4. open **System Settings → Privacy & Security** and choose **Open Anyway**;
5. authenticate and confirm **Open**.

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

Open **Settings → Integrations → Agents & Chat → External Agent Hosts** to inspect App,
bridge, and bundled-helper availability, copy a host-specific setup command, or reveal the
bundled Core Protocol Skill. Scholium copies commands but never edits host
configuration or claims installation succeeded.

Use the copied command for the installed App. It names that App's absolute
helper path; no separate installation is needed. After moving the App, copy and
run its setup command again. Updating in place retains the configured path.

The App must already be running with the intended Triptych open. The stdio
helper uses a current-user-authenticated local bridge and fails explicitly when
the App, bridge, selected Triptych, or current state is unavailable. It never
falls back to direct filesystem or headless workspace access.

The collaboration surface exposes the current bounded Note tools documented in
[Agent Collaboration §8.3](Docs/Specification/03-agent-collaboration-and-workflows.md#83-tool-contract).
It covers retrieval, source-linked attachments, guarded Note operations and
Agent Change comparison/recovery; capability controls remain in-app only.

An ordinary Wikilink may carry multiline, source-owned Markdown annotation as
`[[Target]]{{annotation}}`. Connect, Search, and `scholium_list_links` preserve
each occurrence's direction, annotation, local context, and source location;
they expose only the authored occurrence and never assign a relationship class.

## Storage and safety

Authoritative research remains in the selected Markdown folders. The small
portable `.scholium/` control structure beside Works contains the bounded
control state listed in
[§3.3](Docs/Specification/01-foundation-and-triptych.md#33-scholium-and-machine-local-state).
Research prose and assessments remain ordinary Markdown; save recovery is machine-local.

Bookmarks, absolute paths, window sessions, indexes, saved queries, recovery,
local bridge authentication, exact Agent Change evidence, and unsupported
pre-production bytes remain machine-local under:

```text
~/Library/Application Support/Scholium/State-v1/
```

Writes preserve exact source and report concurrent-edit conflicts without
discarding unsaved text. Safety and recovery contracts belong to
[Save and Recovery §14](Docs/Specification/04-connect-search-and-recovery.md#14-save-agent-changes-and-recovery);
their mechanisms belong to Architecture and acceptance gaps to Status.

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
ScholiumApplication/       Application capabilities shared by App and helper
Scholium/                  Native macOS app and human-facing interaction
WebEditor/                 TypeScript and CodeMirror source
Tests/                     Contract, Core, Application, and App tests
UITests/                   Isolated disposable macOS UI journeys
Docs/SCHOLIUM_SPEC.md      Canonical target-authority manifest and reading routes
Docs/Specification/       Normative product, interface, accessibility, and release chapters
Docs/IMPLEMENTATION_ARCHITECTURE.md
                           Subordinate architecture manifest and reading routes
Docs/Architecture/        Module, runtime, state, editor, presentation, and boundary chapters
Docs/IMPLEMENTATION_STATUS.md
                           Current-evidence manifest and reading routes
Docs/Status/              Remaining work and current proof
Tools/Scripts/             Build, verification, QA, performance, and release tools
```

### In-app Codex Chat (development integration)

The left sidebar switches between Library and Chat; the right document Inspector
switches between Links and Related Material. Chat uses native macOS text and controls; replies may
be full research discussions, while operation activity remains expandable.
In Chat, choose a compatible official Codex executable
and the App-bundled connection helper. Connect and sign in through Codex.
Login and runtime state use a shared machine-local Codex configuration directory;
choosing an existing configuration inherits that environment's tools and settings.
Each Triptych's `.scholium` is its Chat working directory. Edit `AGENTS.md` there
for local instructions and place Skills in `skills/<name>/SKILL.md`; Codex discovers
them automatically. Settings offers Open Chat Workspace in Finder and Refresh,
with no Skill-folder path setup. Existing files are preserved on reconnect.

Use View → Add Selection to Chat (Command-Shift-L) from Edit or Source. Adding
material does not send it. Select Ask for Approval or Full Access, then Send.
Note references open in the central document region. Operation History retains
actual MCP changes and eligible Undo. A disconnected or uncertain request is
never automatically resent. Provider authentication, account availability,
cloud execution and signed-distribution acceptance require their own checks.

### First-party Zotero MCP (optional integration)

Enable Zotero's local API in Zotero Settings → Advanced → **Allow other
applications on this computer to communicate with Zotero**. In Scholium Settings
→ Integrations → Agents & Chat → Skills and Tools, **Set Up Zotero…** uses the
bundled helper with `zotero mcp serve --read-only`. **Check Connection** reports
the API and MCP server separately; it does not read a source.

The helper exposes seven bounded read tools and rejects imports. External hosts
use the helper inside the installed App at
`Contents/Helpers/ScholiumAgentHelper`; moving the App requires copying the
setup command again. There is no standalone installation or updater. The
supported scope and exact reference rules are in [Specification §15](Docs/Specification/05-integrations-onboarding-and-boundaries.md#15-zotero-integration).
