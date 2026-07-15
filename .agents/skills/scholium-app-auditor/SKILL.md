---
name: scholium-app-auditor
description: Perform a read-only, evidence-backed audit of the Scholium macOS app and CLI for correctness, Swift defects, security, vault safety, source fidelity, concurrency, lifecycle, accessibility, performance risks, tests, dependencies, and release readiness. Invoke only when the user explicitly requests `$scholium-app-auditor`, names this skill, or explicitly asks for a Scholium app/code audit. Do not invoke for ordinary implementation, review, diagnosis, or testing requests.
---

# Scholium App Auditor

Audit the live app, not an abstract Swift checklist. Prefer a small number of reproducible findings over a large list of suspicions. Remain read-only unless the user separately asks to fix findings.

## Bind the audit target

Locate one repository root containing `AGENTS.md`, `Package.swift`, `ScholiumCore/`, `Scholium/`, and `ScholiumCLI/`. Stop and request the checkout if the root is not unique. Run repository commands from that root.

Treat the requested scope literally:

- For a named subsystem, file set, commit, or diff, audit that boundary and the directly affected callers, tests, and contracts.
- For an unqualified “audit the app,” audit the whole repository using the staged workflow below.
- Never inspect real research vault contents. Use source code, committed fixtures, disposable copies of the canonical test corpus, or generated temporary vaults.

## Establish current authority

1. Read `AGENTS.md`, `Docs/PRODUCT_GUIDE.md`, `Docs/DESIGN_HANDBOOK.md`, `README.md`, `Package.swift`, and the requested subsystem's implementation and tests. Read `Docs/IMPLEMENTATION_STATUS.md` for current-to-target migration evidence; never let it redefine the Product Guide or substitute for live proof.
2. Inspect `git status`, the selected Xcode and Swift compiler, Swift language mode, deployment target, dependencies, build scripts, and CI or verification entry points.
3. Treat live code and executable tests as implementation evidence. Treat the handbooks as intended behavior. Report contradictions; do not silently choose one.
4. For GUI claims, inspect `Tools/Scripts/build-qa-app.sh`, `Tools/Scripts/run-ui-tests.sh`, `UITests/ScholiumUITests.swift`, and a current result artifact when one exists. The isolated `com.kbmanager.qa` Debug bundle proves only the exercised development journey; it is not a packaged, signed, clean-account, or release artifact. Do not require or trust a historical QA-log path that is absent from the live tree.
5. Use `scholium-development` as the repository base. Load a narrow owner skill when a candidate finding concerns its subsystem; that owner supplies the invariant and verification method.

## Audit in feasible stages

For a whole-app audit, proceed in this order and stop expanding a stage when evidence is already sufficient to report the issue:

1. **Baseline:** inventory targets, dependencies, generated code, verification scripts, test targets, and uncommitted work. Check generated/install-only trees for suspicious numbered duplicates or stale copies; use the lockfile-driven clean rebuild to prove reproducibility instead of patching generated dependencies.
2. **Automated evidence:** run the cheapest relevant build and tests. Use `./Tools/Scripts/verify.sh` for a claimed full audit unless it is unavailable, unsafe, or prohibitively slow; report any limitation.
3. **Hotspot scan:** search for risky constructs, then inspect every reported candidate in context. A token match is not a finding.
4. **Contract tracing:** trace representative write, read/render, async, search/index, Dialogue/checkpoint, and failure paths end to end. Expand only where the checklist or code evidence indicates risk.
5. **Focused proof:** reproduce credible defects with an existing test, a minimal disposable fixture, or a narrow added test only if the user has authorized file changes. Without write authorization, provide the exact proposed regression test.
6. **Coverage accounting:** mark each checklist area checked, not applicable, not checked, or blocked. Never equate a clean build with a clean audit.

Use [references/audit-checklist.md](references/audit-checklist.md) as the complete coverage and hotspot guide. It complements generic coding checks with Scholium's trust, exact-source, macOS, and research-workflow boundaries.

## Judge findings strictly

Report an item only when it has all of:

- a violated requirement, invariant, documented contract, or demonstrable correctness property;
- a reachable code path or reproducible scenario;
- concrete evidence with file and line, command output, test, or minimal trace;
- an observable consequence;
- a bounded remediation and verification method.

Keep these separate:

- **Confirmed defect:** reproduced or proved from a complete reachable path.
- **Probable defect:** strong code evidence, but one environmental or runtime step remains unverified.
- **Coverage gap:** a consequential behavior lacks a credible test or assertion.
- **Maintainability concern:** raises defect likelihood but is not itself incorrect.

Do not report style preferences, speculative future scale problems, harmless force unwraps in proven test-only invariants, or broad architectural alternatives as defects. Do not count the same root cause multiple times.

## Rank severity

- **P0 — Critical:** plausible data loss, stale or out-of-scope vault write, vault escape, checkpoint-integrity failure, secret exposure, or release-blocking corruption.
- **P1 — High:** crash or silent corruption in a normal workflow, cross-vault identity error, stale overwrite, exploitable trust failure, or systematic source-fidelity loss.
- **P2 — Medium:** bounded incorrect behavior, race, leak, inaccessible core workflow, misleading state, or missing recovery with material user impact.
- **P3 — Low:** localized robustness, diagnostics, maintainability, or test weakness with a credible failure mechanism.

Severity follows consequence and reachability, not code ugliness.

## Route specialist evidence

- Exact Markdown/YAML bytes or serialization: `scholium-markdown-yaml-fidelity`.
- Filesystem races, external edits, bookmarks, or watchers: `scholium-vault-file-coordination`.
- Researcher control, containment, direct-edit revision checks, checkpoints, privacy, rendered input, or loss risk: `scholium-trust-boundary-audit`.
- Reader/editor, TextKit, CodeMirror, source ranges, focus, or undo: `scholium-markdown-editor-integration`.
- Search, links, relationships, or derived indexes: `scholium-derived-index-integrity`.
- Triptych roles, Properties profiles, Human Review, qualification, Dialogue, Critique, Attention, or provenance behavior: inspect the Product Guide, live Core types, CLI/UI callers, and focused tests together; do not let a status ledger override code or philosophical judgment.
- Measured latency, hangs, CPU, or memory: `scholium-performance-audit`.
- Interface or accessibility: `scholium-apple-design`; add `scholium-swiftui-implementation` for SwiftUI mechanics and use `scholium-ui-automation` for reachable journeys.
- Swift semantics, API naming, concurrency, or tests: the matching Swift skill.
- Rust or Swift–Rust code: `rust-language`; add `scholium-rust-index-engine` for the derived index engine.

Loading a specialist does not authorize implementation. Use it to test the suspected invariant and avoid duplicate or contradictory advice.

## Report the audit

Lead with findings, ordered P0 to P3. For each finding provide:

1. severity, confidence, and classification;
2. concise defect statement;
3. affected file and line;
4. evidence or reproduction;
5. user or system consequence;
6. smallest safe remediation;
7. focused regression test.

Then report:

- commands and tests run, including failures;
- the exact Debug QA or release artifact used for GUI evidence and what it cannot establish;
- a compact coverage table for every checklist section;
- assumptions, blocked checks, and residual uncertainty;
- “No confirmed findings” when appropriate, without implying the unchecked surface is safe.

Do not modify code during an audit-only request. If the user asks to fix the findings, begin a separate implementation pass through `scholium-development` and the relevant narrow owners, then run focused tests and `./Tools/Scripts/verify.sh`.
