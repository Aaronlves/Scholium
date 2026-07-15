---
name: swift-concurrency
description: "Resolve Swift concurrency compiler errors, adopt approachable concurrency, and write data-race-safe async code. Use when fixing Sendable conformance errors, actor-isolation warnings, or strict-concurrency diagnostics; when adopting Default Actor Isolation, @concurrent, nonisolated(nonsending), or Task.immediate; when designing actor-based architectures, structured concurrency, background work offloading, synchronous state protection, or migration from @preconcurrency to full Swift 6 checks."
---

# Swift Concurrency

Make the smallest change that establishes a clear isolation boundary and preserves behavior. Shared mutable state must be protected, but an actor is not the only valid mechanism: choose between actor isolation and an audited synchronous primitive according to how callers access the state.

## Establish the actual build context

Before interpreting a diagnostic, record these independently:

1. selected Xcode and Swift compiler version;
2. Swift language mode;
3. strict-concurrency setting and enabled upcoming features;
4. Default Actor Isolation and Approachable Concurrency settings;
5. SwiftPM tools version, SDK, and deployment target.

Do not equate SwiftPM tools version with Swift language mode. Approachable Concurrency does not itself make a module `MainActor`-isolated; that requires Default Actor Isolation to be set to `MainActor`. In Swift 6 language mode, complete strict-concurrency checking is the baseline rather than a `Minimal` or `Targeted` migration setting.

## Route to focused references

- Read [references/diagnostics.md](references/diagnostics.md) for diagnostic-to-fix routing and migration checks.
- Read [references/approachable-concurrency.md](references/approachable-concurrency.md) for Default Actor Isolation, `nonisolated(nonsending)`, isolated conformances, and `@concurrent`.
- Read [references/concurrency-patterns.md](references/concurrency-patterns.md) for structured tasks, global state, task startup, newer cleanup APIs, and build settings.
- Read [references/synchronization-primitives.md](references/synchronization-primitives.md) when deciding between actors, `Mutex`, `Atomic`, `OSAllocatedUnfairLock`, and legacy locks.
- Read [references/bridging-interop.md](references/bridging-interop.md) for continuations, delegates, callbacks, streams, and GCD migration.
- Read [references/swiftui-concurrency.md](references/swiftui-concurrency.md) for SwiftUI and Observation boundaries.
- Read [references/async-algorithms.md](references/async-algorithms.md) for AsyncSequence composition, debounce, throttle, merge, and combineLatest.
- Read [references/review-hotspots.md](references/review-hotspots.md) for a broader audit of unstructured tasks, captures, and cancellation.

Load only references relevant to the reported problem.

## Diagnose in this order

1. Identify the mutable resource and every executor or thread that can reach it.
2. Decide which isolation domain should own it: `MainActor`, a custom actor, immutable value transfer, or a synchronous lock/atomic boundary.
3. Trace each value crossing that boundary and determine whether it is actually `Sendable`.
4. Find suspension points, cancellation paths, task lifetimes, and any unstructured task that can outlive its owner.
5. Apply the narrowest fix, then recompile before widening annotations.

## Choose the ownership mechanism

### Actor or global actor

Use an actor when access is naturally asynchronous, serialized hops are acceptable, or the state participates in a larger async workflow. Use `MainActor` for UI-bound state and UI mutations. Keep CPU-heavy and blocking work off `MainActor`; use a documented nonisolated boundary and `@concurrent` where supported and appropriate.

Do not add a lock inside an actor to protect the actor's own state. Do not assume `nonisolated async` automatically means background execution under approachable-concurrency behavior.

### Immutable or value transfer

Prefer immutable `Sendable` values across isolation boundaries. Capture only the values a task needs. Avoid making a reference type `@unchecked Sendable` unless its synchronization invariant is real, documented, and tested.

### Synchronous primitive

Use a synchronous primitive when callers are synchronous, actor hops are impossible or disproportionate, or low-level interoperability requires immediate access.

- Scholium targets macOS 26, so `Mutex` and `Atomic` from `Synchronization` and `OSAllocatedUnfairLock` from `os` are all available. Choose by ownership semantics, not by an obsolete compatibility floor.
- Existing `NSLock` code is not automatically wrong. Replace it only when the new primitive improves the ownership invariant and the measured or correctness case is clear.
- Never hold any lock across `await`, re-enter a nonrecursive lock, or perform slow/blocking work while holding the lock.

Use atomics only for small scalar state with a reviewed memory-ordering argument. A lock or actor is usually clearer for compound invariants.

## Structured concurrency and cancellation

- Prefer `async let` for a fixed number of child operations and task groups for dynamic fan-out.
- Give each unstructured `Task` an explicit owner, lifetime, cancellation path, and actor context. Detached tasks require a stronger justification.
- Propagate cancellation through loops and bridges, and use cancellation handlers for prompt cleanup.
- Resume every checked continuation exactly once on every path.
- Do not use sleeps to coordinate tasks when a structured event, clock, stream, or confirmation can express the dependency.
- Gate beta or newly introduced cleanup APIs against the selected compiler, SDK, and deployment target. Host-OS availability does not prove that the resolved compiler accepts an API.

## Interoperability and migration

- Treat `@preconcurrency` as a temporary bridge around an external module, with a documented removal condition.
- Prefer isolated conformances or correct actor annotations over blanket `nonisolated` declarations.
- Audit delegates and callback bridges for double resume, missing cancellation, and non-Sendable captures.
- Preserve ordering, reentrancy, and cancellation semantics when replacing queues with actors or tasks.

## Verify the fix

1. Build with the repository's strict Swift 6 settings and selected Xcode toolchain.
2. Run focused tests under repetition; include cancellation, deallocation, interleaving, and failure paths.
3. Use Thread Sanitizer or concurrency diagnostics when the boundary warrants it, while recognizing that absence of a report is not proof of correctness.
4. Check UI responsiveness when work crosses `MainActor` and benchmark lock changes when performance motivated them.
5. Report the chosen isolation invariant, deployment availability, any temporary compatibility annotation, and remaining risk.

Do not silence a diagnostic with `@unchecked Sendable`, `nonisolated`, detached work, or a lock until the ownership model makes the safety claim true.
