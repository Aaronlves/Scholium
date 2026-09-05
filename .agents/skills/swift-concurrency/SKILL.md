---
name: swift-concurrency
description: "Resolve Swift concurrency diagnostics or design data-race-safe async code. Use for Sendable, actor isolation, strict-concurrency adoption, structured tasks, cancellation, background work, synchronization, or callback and GCD bridging; do not trigger for ordinary synchronous Swift."
---

# Swift Concurrency

Make the smallest change that establishes a truthful ownership and isolation
boundary while preserving behavior.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Resolve compiler mode, isolation settings, SDK, deployment target, diagnostics,
and API availability from the selected live toolchain and primary Swift or
Apple documentation. Do not preserve version tables in this skill.

## Method

1. Identify the mutable resource and every executor, thread, callback, or task
   that can reach it.
2. Choose its owner: immutable value transfer, a UI or custom actor, or an
   audited synchronous primitive suited to actual callers.
3. Trace every cross-boundary value, suspension point, task lifetime,
   cancellation path, and cleanup path.
4. Apply the narrowest fix, recompile, and widen annotations only when the
   ownership model requires it.
5. Test interleaving, cancellation, failure, deallocation, and UI responsiveness
   as applicable; report the invariant and residual risk.

## Invariants

- UI state and UI mutations stay on their required actor; blocking or heavy work
  must not remain there accidentally.
- Prefer immutable sendable values. An unchecked conformance is acceptable only
  when a real, documented, tested synchronization invariant makes it true.
- Prefer structured children. Every unstructured task needs an owner, lifetime,
  actor context, and cancellation route; detached work needs stronger evidence.
- Never hold a synchronous lock across suspension, add a lock to protect an
  actor's own state, or use atomics without a reviewed scalar invariant and
  memory-ordering argument.
- Resume continuations exactly once and preserve ordering, reentrancy, and
  cancellation when bridging callbacks or queues.
- Do not use compatibility annotations to retain an obsolete isolation path;
  fix the owning boundary and remove superseded annotations and shims.
- Do not silence a diagnostic until the ownership model makes the claim true.
