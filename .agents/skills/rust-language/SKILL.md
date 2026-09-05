---
name: rust-language
description: "Implement, review, debug, or test Rust and Swift-facing native code in Scholium. Use for Cargo, ownership, errors, concurrency, performance, unsafe or FFI boundaries, packaging, or Rust-adoption decisions; exclude Swift-only work and unmeasured rewrites."
---

# Rust Language

Use Rust only for a bounded capability with a verified advantage. Preserve
Scholium's Swift-owned authorization, recovery, and authoritative-write
boundary.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).

## Decide before adopting

Inspect the live Swift boundary, selected Rust toolchain, manifests,
dependencies, packaging route, and tests. Do not install or change global
tooling without authorization.

Adopt Rust only when measured performance, portability, a well-audited library,
or process isolation justifies the added build, packaging, and maintenance
cost. A disposable experiment may establish evidence but does not become the
production boundary merely because it passes. Keep UI, bookmarks, researcher
authorization, snapshots, conflicts, and authoritative writes in their
existing Swift owners.

## Design one narrow boundary

- Pass immutable owned values and typed results across a versioned boundary.
- Keep research content out of logs, panics, and diagnostics.
- Treat expected failure as data; prevent panic or foreign exceptions from
  crossing the boundary.
- Keep unsafe code absent or isolated behind a documented safe contract and
  adversarial proof.
- Choose subprocess, C-compatible, or generated binding mechanisms from live
  toolchain and packaging evidence rather than a stored preference.
- For a Rust dependency, add transitive native code, build-script behavior,
  target-architecture support, and FFI exposure to the repository dependency
  evaluation required by `AGENTS.md`.

For an adopted Rust or Swift-facing boundary, load the concise
[engineering and FFI procedure](references/rust-engineering-and-ffi.md) and use
current official Rust, Cargo, FFI, and candidate-library documentation at task
time. For substantial backend design, also apply the shared
[backend decision research](../scholium-engineering/references/backend-decision-research.md).

## Verify and report

Run the repository and crate's current formatting, lint, test, build, boundary,
and packaging checks appropriate to the task. Add corruption, cancellation,
round-trip, and unsafe-sensitive proof in proportion to risk. Report the
decision, boundary, measured benefit, dependency and unsafe surface, evidence
actually obtained, and unsupported environments without storing command or
target inventories in this skill.
