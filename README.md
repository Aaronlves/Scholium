<p align="center">
  <img src="Docs/Assets/scholium-icon.svg" width="128" height="128" alt="Scholium app icon: a hand pointing to a written page">
</p>

<h1 align="center">Scholium</h1>

<p align="center">
  <strong>A native macOS research environment for philosophy and the humanities.</strong><br>
  Read sources, develop ideas, and write your own arguments.<br>
  Keep your research in local Markdown, with optional Agent collaboration.
</p>

<p align="center">
  <a href="https://github.com/Aaronlves/Scholium/releases/download/v0.4.2-beta.2/Scholium-v0.4.2-beta.2-macos-arm64.dmg"><img src="https://img.shields.io/badge/macOS-Download_Beta-8B613E?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="Download Scholium Beta for macOS, Apple silicon"></a>
</p>

<p align="center">
  <a href="https://github.com/Aaronlves/Scholium/actions/workflows/verify.yml"><img src="https://github.com/Aaronlves/Scholium/actions/workflows/verify.yml/badge.svg?branch=main" alt="Repository verification on main"></a>
  <a href="https://github.com/Aaronlves/Scholium/releases"><img src="https://img.shields.io/github/v/release/Aaronlves/Scholium?include_prereleases&amp;label=beta&amp;color=8B613E" alt="Latest published beta release"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/macOS-26%2B-555555?logo=apple&amp;logoColor=white" alt="Requires macOS 26 or later"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&amp;logoColor=white" alt="Swift tools 6.2"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-587549" alt="License: GPL-3.0-or-later"></a>
</p>

<p align="center">
  <a href="https://github.com/Aaronlves/Scholium/releases">Releases</a> ·
  <a href="#getting-started">Getting started</a> ·
  <a href="Docs/SCHOLIUM_SPEC.md">Documentation</a> ·
  <a href="README.zh-Hans.md">简体中文</a>
</p>

---

## Research begins with the document

Scholium brings source analysis, conceptual work, and sustained writing into one
research environment. Your documents remain ordinary Markdown in folders you
choose. The manual research core works without Obsidian, Zotero, or an Agent.

Each field of inquiry takes the form of a **Triptych**:

| Workspace | What belongs here |
| --- | --- |
| **Analyses** | Close readings and reusable analyses of papers and other sources. |
| **Topics** | Concepts, distinctions, debates, objections, and syntheses across sources. |
| **Works** | Your plans, arguments, drafts, assessments, and finished writing. |

Move between **Review**, **Edit**, and **Source** as you read and write. Search
across your research, follow authored links and their annotations, and consult
Writing References while developing a draft. Retrieval helps you find material;
it does not establish evidence for a claim.

Exact Markdown remains authoritative. Autosave, Changes, conflict handling, and
recovery support work alongside other editors. Sources, interpretations, Agent
contributions, and your own judgments retain distinct roles. You decide what
becomes part of your research.

## Getting started

**Requires macOS 26 or later and an Apple silicon Mac.** You do not need Xcode
to run the packaged app.

1. Download the DMG and its SHA-256 file from
   [v0.4.2-beta.2](https://github.com/Aaronlves/Scholium/releases/tag/v0.4.2-beta.2).
   Run `shasum -a 256 Scholium-v0.4.2-beta.2-macos-arm64.dmg` and compare the
   result with the accompanying checksum.
2. Open the DMG, drag **Scholium** to **Applications**, and eject the DMG.
3. Open Scholium once. This Beta is ad-hoc signed and is not Developer ID signed
   or notarized. If macOS blocks it, open **System Settings → Privacy & Security →
   Open Anyway**, authenticate, and confirm **Open**. Keep Gatekeeper enabled.
4. Choose the **Analyses**, **Topics**, and **Works** folders for your Triptych.
   A common parent is convenient; independently located folders are supported.
   macOS also requests access to the folder containing Works for the portable
   `.scholium/` control data beside it.

Use **File → New Triptych…** for another research domain, **File → Open Triptych**
to open a registered Triptych, or **File → New Window** for another window on the
current one. Two Triptychs cannot share the same Works-side control directory.

The public distribution is **Core App Beta**. External Agent collaboration and
optional in-app Chat remain **Preview**. Packaged-release evidence and outstanding
human UI, accessibility, and performance acceptance are recorded in
[Implementation Status](Docs/IMPLEMENTATION_STATUS.md) and the
[release notes](https://github.com/Aaronlves/Scholium/releases/tag/v0.4.2-beta.2).

## Optional integrations

### Agents and Chat · Preview

Use the in-app Chat with a compatible official Codex executable, or connect an
external Agent host through Scholium MCP. The App-bundled helper requires
Scholium to be running with the intended Triptych open.

**In-app Chat:** switch the left sidebar to **Chat**, select the Codex executable
and bundled connection helper, then connect and sign in through Codex. Choose
**Ask for Approval** or **Full Access** before sending a request. Add selected
text from Edit or Source with **View → Add Selection to Chat** (`⇧⌘L`); adding
material does not send it. Operation History retains actual MCP changes and
eligible Undo. An interrupted or uncertain request is never automatically resent.

Each Triptych's `.scholium/` is its Chat working directory. Put local instructions
in `AGENTS.md` and Skills in `skills/<name>/SKILL.md`. Settings offers **Open Chat
Workspace in Finder** and **Refresh**. Codex authentication and runtime settings
use a shared machine-local configuration; selecting an existing configuration
inherits its tools and settings.

**External hosts:** open **Settings → Agents → External Access**, then copy and
run the command for your host. It uses the installed
App's exact helper path. After moving the App, copy and run the command again;
updating in place retains the path. Scholium copies commands without editing
host configuration. External conversations stay in their host.

Scholium MCP provides retrieval, source-linked attachments, guarded Note
operations, and Agent Change comparison/recovery. The helper fails explicitly
when the App or selected Triptych is unavailable. See the
[tool contract](Docs/Specification/03-agent-collaboration-and-workflows.md#83-tool-contract)
for the supported surface.

### Zotero

Enable **Allow other applications on this computer to communicate with Zotero**
in **Zotero Settings → Advanced**. Chat uses the bundled `scholium-zotero`
connection to search and read library material, export citations, and modify
items when explicitly confirmed and authorized by Zotero's local API. BibTeX
and RIS imports remain in Zotero. No separate community server or Python runtime
is required.

To read original PDFs, open **Scholium Settings → Zotero → Original File Access →
Choose Zotero Library Folder…**, then confirm **Allow Read Access**. You can also
grant access to linked-file folders or individual originals. Access is read-only,
stored on This Mac, and removable in Settings.

Zotero remains the library authority; Scholium does not access its private
database directly. See [Zotero integration](Docs/Specification/05-integrations-onboarding-and-boundaries.md#15-zotero-integration)
for supported operations and citation behavior.

## Documentation

| Read | For |
| --- | --- |
| [Specification](Docs/SCHOLIUM_SPEC.md) | Product workflows, interface, accessibility, and release requirements. |
| [Design](Design.md) | Global design philosophy and visual identity. |
| [Architecture](Docs/IMPLEMENTATION_ARCHITECTURE.md) | Modules, state ownership, transactions, and editor boundaries. |
| [Implementation Status](Docs/IMPLEMENTATION_STATUS.md) | Current reachability, open work, and dated verification evidence. |
| [Development rules](AGENTS.md) | Contribution scope, verification, and disposable-fixture requirements. |

## Development

Build with a complete Xcode installation providing the compiler and SDK required
by [Package.swift](Package.swift). Node.js is needed when rebuilding the
TypeScript editor bundle. Run commands from the repository root:

```bash
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
export DEVELOPER_DIR="$developer_dir"
swift build
./Tools/Scripts/run-debug-app.sh
```

The resolver honors a valid `DEVELOPER_DIR`, a complete `xcode-select` selection,
or a conventional beta or release Xcode bundle. Keep the checkout outside
Desktop, Documents, CloudStorage, and other File Provider-managed locations.
All build caches, QA state, fixture copies, and logs belong under ignored
repository-local `.build/` paths. Test only disposable, nonprivate fixtures.

<details>
<summary><strong>Verification and development tools</strong></summary>

Choose checks appropriate to the change under [AGENTS.md](AGENTS.md).

| Task | Command |
| --- | --- |
| Swift tests | `swift test` |
| Swift formatting and editor typecheck | `./Tools/Scripts/lint.sh` |
| Apply Swift formatting, then check | `./Tools/Scripts/lint.sh --fix` |
| Daily repository gate | `./Tools/Scripts/verify.sh --ci` |
| Complete repository gate | `./Tools/Scripts/verify.sh` |
| Canonical UI journey | `./Tools/Scripts/run-ui-tests.sh smoke` |
| Retained critical UI suite | `./Tools/Scripts/run-ui-tests.sh complete` |
| Rebuild the editor bundle | `./Tools/Scripts/build-editor.sh` |
| Verify the checked-in editor bundle | `./Tools/Scripts/verify-editor-bundle.sh` |
| Validate documentation authority and links | `python3 Tools/Scripts/validate-documentation-authority.py` |

Push and pull-request CI reports **Repository verification**. Verified edits to
an allowlist of existing Markdown files use `verify.sh --docs`; other changes
use the daily gate. Daily verification omits two expensive WebView suites and
the Release build/helper checks, which remain in the full gate. Logs, timings,
summaries, and skips are retained under `.build/ci-verification/runs/`.

Before publishing a beta, run the full gate locally and select **full** in the
manual **Verify** workflow for the exact candidate ref. Complete the applicable
packaged smoke, artifact, and performance gates as well. CI skips calibrated
measurement and display-dependent evidence through
`SCHOLIUM_SKIP_MEASUREMENT_EVIDENCE` and `SCHOLIUM_SKIP_DISPLAY_EVIDENCE`;
those checks require a development Mac. Automated checks do not establish human
visual or assistive-technology acceptance. Release requirements belong to
[the specification](Docs/Specification/10-release-and-open-decisions.md).

The UI runner copies the standard 500-note [TestVaults](TestVaults/README.md)
fixture into isolated `.build/` state. Register its three vaults separately;
never mutate the source fixture or test against a real research vault.

For opt-in scale diagnostics:

```bash
python3 Tools/Scripts/generate-stress-vaults.py .build/stress-fixture
SCHOLIUM_STRESS_FIXTURE="$PWD/.build/stress-fixture" \
  swift test --filter LargeVaultStressDiagnosticTests
SCHOLIUM_TEST_VAULTS="$PWD/.build/stress-fixture" ./Tools/Scripts/run-ui-tests.sh stress
```

The stress generator defaults to 5,000 synthetic Notes (`--notes` accepts
500–20,000); complete diagnostics require at least 508. Both diagnostics copy
the fixture. Scenario measurements do not establish the packaged performance gate.

Use `Manage Scholium Development Storage.command` in Finder or
`./Tools/Scripts/manage-development-storage.sh report` to inspect storage.
`clean-stale`, `clean-all`, and `clean-editor` default to dry runs; add `--delete`
only after reviewing the allowlisted targets. Editor dependencies are removed
only by `clean-editor`.

</details>

## Your files and local state

Research prose and assessments remain ordinary Markdown in your selected
folders. Portable control data stays in the bounded `.scholium/` structure beside
Works. Bookmarks, absolute paths, sessions, indexes, saved queries, recovery,
bridge authentication, and exact Agent Change evidence stay on this Mac under:

```text
~/Library/Application Support/Scholium/State-v1/
```

See [storage boundaries](Docs/Specification/01-foundation-and-triptych.md#33-scholium-and-machine-local-state)
and [save and recovery](Docs/Specification/04-connect-search-and-recovery.md#14-save-agent-changes-and-recovery).
The App, bundled helpers, and Core Protocol update together; there is no
standalone CLI distribution or self-updater.

## License

Scholium's original source code is licensed under the
[GNU General Public License, version 3 or later](LICENSE) (`GPL-3.0-or-later`),
unless otherwise noted. Third-party components retain their own licenses;
see [Third-Party Notices](THIRD_PARTY_NOTICES.md).
