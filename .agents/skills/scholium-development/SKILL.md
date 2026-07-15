---
name: scholium-development
description: Develop, diagnose, test, package, or document the Scholium macOS research workbench and its agent-facing CLI inside the Scholium repository. Use for changes to ScholiumCore, ScholiumApp, ScholiumCLI, Dialogue, Critique, checkpoints, legacy proposal migration, vault safety, Triptych registration, Swift 6 or Xcode-beta builds, fixtures, packaging, and release verification. Do not use for substantive philosophy research, paper analysis, dissertation writing, or ordinary vault-note maintenance.
---

# Scholium Development

Preserve Scholium's human–agent trust boundary while making the smallest complete, verified change.

## Locate the checkout

Do not infer the checkout from this skill's installed location; plugin skills may run from a cache. Bind one repository root containing `AGENTS.md`, `Package.swift`, `ScholiumCore/`, and `Scholium/`. If the current scope does not contain one unique root, stop and request the checkout. Treat that root as the working directory for commands and source paths.

## Establish live context

1. Read `AGENTS.md`, `README.md`, `Package.swift`, and directly relevant source files.
2. Inspect the current worktree before editing. Preserve unrelated and uncommitted work.
3. Treat live code and tests as authority over remembered behavior.
4. Resolve the canonical non-production fixture root identified by the package `README.md`, then use only disposable copies of those fixtures. If that root is unavailable, use generated temporary vaults. Do not assume a package-local `TestVaults/` directory and never use a real research vault for development validation.

## Resolve document authority

Do not flatten every handbook, report, and test into one source of truth:

- `AGENTS.md` supplies repository enforcement and the complete documentation hierarchy.
- `Docs/PRODUCT_GUIDE.md` owns target product role, Triptych workflows, terminology, and feature boundaries.
- `Docs/DESIGN_HANDBOOK.md` owns stable interface design and the exact target user-visible state and action contract.
- The workspace `WORKFLOW_AND_YAML_ARCHITECTURE_REPORT.md` supplies the upstream humanities-workflow and schema rationale. Treat a newer workflow or research-aim artifact supplied by the user as task input, not as permission to mutate an external workspace.
- `Docs/IMPLEMENTATION_STATUS.md` is the current-to-target conformance and migration ledger. It does not redefine the Product Guide or prove that code remains reachable.
- The package `README.md`, live construction call sites, executable tests, and current scripts establish implemented and reachable behavior.
- A performance test name or threshold is regression evidence only. Product acceptance requires the active benchmark protocol and a measured artifact from the required build, fixture, state, and sample set.

## Route specialist work

Use this skill as the repository-wide base and final verification layer. Pair it with the narrow owner when applicable:

- exact Markdown/YAML parsing or mutation: `scholium-markdown-yaml-fidelity`;
- FSEvents, external edits, autosave races, bookmarks, filesystem inventory, cache invalidation, or watcher generations: `scholium-vault-file-coordination`;
- filesystem authorization, proposals, snapshots, or data-loss risk: `scholium-trust-boundary-audit`;
- CodeMirror, WKWebView Read, exact-buffer synchronization, editor focus/selection, or native fallback work: `scholium-markdown-editor-integration`;
- search, links, relationships, query semantics, index contents, or full/incremental rebuild equivalence: `scholium-derived-index-integrity`;
- GUI journeys: `scholium-ui-automation`;
- measured latency or resource use: `scholium-performance-audit`;
- interface and accessibility semantics: `scholium-apple-design`;
- SwiftUI scenes, state ownership, navigation, layout, presentation, AppKit mounting, or Liquid Glass implementation: `scholium-swiftui-implementation` plus `scholium-apple-design` for the design decision;
- Swift language, concurrency, API naming, or test-framework mechanics: the corresponding Swift skill.
- Rust library, CLI, Cargo, unsafe, or Swift-boundary work: `rust-language`.
- Rust-backed search/index adoption or design: `scholium-rust-index-engine` plus the existing index-integrity and performance skills.

For current compatibility involving workflow roles, schema profiles, linter diagnostics, Research Sessions, attention queues, readiness gates, workspace bridges, or proposals, trace the live contract through `WorkflowSchema.swift`, `WorkflowLint.swift`, `ResearchSession.swift`, `WorkspaceCatalog.swift`, `WorkflowBridge.swift`, and their tests. Treat these as current implementation unless `Docs/PRODUCT_GUIDE.md` retains them as target behavior. Workflow metadata must never be promoted into an automated judgment of philosophical truth, evidential sufficiency, or settlement.

## Preserve product invariants

- Keep authoritative vault writes behind `VaultRepository` revision checks, pre-write snapshots, validation, and atomic writes.
- Follow the Product Guide's target direct-agent-edit model. Dialogue creates copyable instructions; external agent writes are concurrent filesystem inputs, not hidden app approvals.
- Use the implemented direct-edit boundary: explicit vault-relative paths, containment checks, fresh fingerprints, transactional repository writes, conflicts, Before Agent Work checkpoints, and checkpoint recovery. Proposal is legacy migration data, not a reachable authorization path.
- For Scholium CLI mutations introduced by that migration, require explicit paths, canonical containment, fresh fingerprints, snapshots, validation, atomic writes, and accurate attribution. General external tools remain outside Scholium's enforcement boundary.
- Store reviews, comments, Dialogue replies, checkpoints, indexes, and other generated state in the locations assigned by the Product Guide; never put replaceable indexes or caches in a vault.
- Preserve exact UTF-8 source, BOM, newline style, comments, unknown YAML fields, ordering, quoting, multiline values, and final newlines outside explicitly changed ranges.
- Reject traversal, nonexistent targets, symlink escape, stale fingerprints, malformed proposed frontmatter, and cross-vault identity mismatch.
- Treat neutral `[[wikilinks]]` and transitive paths as connections, never philosophical evidence.
- Allow independently located source, knowledge, and project vaults. Recommend co-location without requiring it.
- Keep accepted research content, user notes, source evidence, and agent inference visibly distinct.

## Implement changes

- Put document, repository, identity, Dialogue/checkpoint, legacy-proposal migration, and relationship trust logic in `ScholiumCore/` when it must be shared by app and CLI.
- Put human review and macOS interaction in `Scholium/`.
- Put agent commands in `ScholiumCLI/` and keep their output script-friendly.
- Add or update focused tests in an importable target for every behavior change. Keep shared trust logic and its tests in `ScholiumCore` when app and CLI both depend on it.
- Read [references/document-pipeline-testing.md](references/document-pipeline-testing.md) when app-service logic is not reachable from the existing test target.
- Update `README.md` only with behavior that is built and reachable.
- When `WebEditor/` changes, rebuild and verify the committed CodeMirror bundle:

```bash
./Tools/Scripts/build-editor.sh
./Tools/Scripts/verify-editor-bundle.sh
```

- For material GUI changes, build the isolated `com.kbmanager.qa` Debug app from a disposable fixture copy and run the macOS UI-test harness:

```bash
./Tools/Scripts/build-qa-app.sh
./Tools/Scripts/run-ui-tests.sh
```

These QA scripts are the development interaction harness, not release packaging or release evidence.

## Resolve Xcode deliberately

Never embed a remembered Xcode path, version, compiler, or SDK as current. Resolve the developer directory through the repository helper, which honors an explicit valid `DEVELOPER_DIR`, then a complete `xcode-select` selection, then conventional beta and release bundle locations:

```bash
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
DEVELOPER_DIR="$developer_dir" xcodebuild -version
DEVELOPER_DIR="$developer_dir" xcrun swift --version
DEVELOPER_DIR="$developer_dir" xcodebuild -showsdks
```

Use that same directory for inspection, export, builds, and tests. Do not change the machine-wide selected developer directory unless the user specifically requests it. Scholium targets macOS 26 or later, but every implementation-facing API claim still requires verification against the resolved compiler and SDK.

## Verify proportionally

Run the narrow test during iteration, then finish code changes with:

```bash
./Tools/Scripts/verify.sh
```

For CLI changes, use an isolated home and fixture vault:

```bash
SCHOLIUM_HOME=/tmp/scholium-cli-check swift run scholium --help
```

Do not package during ordinary active development. For an explicitly requested release, packaging, signing, or app-identity change, also run:

```bash
./Tools/Scripts/package-app.sh
codesign --verify --deep --strict --verbose=2 "${SCHOLIUM_PACKAGE_OUTPUT:-${HOME}/Applications/Scholium Builds}/Scholium.app"
codesign --verify --strict --verbose=2 "${SCHOLIUM_PACKAGE_OUTPUT:-${HOME}/Applications/Scholium Builds}/scholium"
```

Use the Computer Use skill for reachable GUI smoke tests. For a local ad-hoc artifact, remove only the approved Finder or File Provider metadata handled by `Tools/Scripts/package-app.sh`, then re-run strict verification. Never re-sign an already signed or notarized distribution artifact after its smoke test. If signed contents changed, rebuild and repeat the complete signing and notarization workflow.

For Developer ID distribution, notarization, universal-binary work, or release automation, read `references/release-verification.md`. Treat the current scripts and bundle identity as authoritative; do not replace them with a generic SwiftPM template.

## Report completion accurately

State what changed, which trust invariants were exercised, tests and builds run, artifact paths, and anything intentionally deferred. Never claim full multi-vault GUI support, notarization, performance acceptance, accessibility completion, or philosophical source fidelity unless directly verified in the current task.
