---
name: rust-language
description: "Implement or review Scholium Rust components and Swift FFI, or evaluate a proposed Rust adoption."
---

# Rust Language

Use Rust only for a bounded capability with a verified advantage. Preserve
Scholium's Swift-owned authorization, recovery, and authoritative-write
boundary.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).

## Adoption decisions

For a proposed adoption or boundary change, inspect the live Swift owner,
toolchain, dependency, and packaging evidence. Existing Rust corrections do
not reopen the adoption decision. Do not change global tooling without
authorization.

Adopt Rust only when measured performance, portability, a well-audited library,
or process isolation justifies the added build, packaging, and maintenance
cost. A disposable experiment may establish evidence but does not become the
production boundary merely because it passes. Keep UI, bookmarks, researcher
authorization, snapshots, conflicts, and authoritative writes in their
existing Swift owners.

## Design one narrow boundary

For an FFI failure, trace allocation, borrowing, transfer, and release on both
sides, including error and cancellation paths. Distinguish a returned owned
buffer from a pointer borrowed only for the call. Identify which runtime must
free it; a successful round trip does not establish lifetime correctness.
Check length units, encoding, nullability, and integer-width conversions against
the actual boundary types before changing wrappers.

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
