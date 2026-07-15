# Swift concurrency review hotspots

Scan these patterns first. A match is a prompt to inspect context, not proof of a defect.

| Pattern | Verify |
|---|---|
| `Task {}` in a loop | Whether structured concurrency, cancellation, ordering, and error propagation were lost |
| `Task.detached` | Whether breaking actor, priority, task-local, and cancellation inheritance is intentional |
| stored `Task` | Ownership, cancellation on replacement or deinit, and long-lived captures |
| `withCheckedContinuation` | Exactly one resume on every success, error, and cancellation path |
| `AsyncStream` closure initializer | Producer lifetime, `onTermination`, cancellation, and bounded buffering |
| `@unchecked Sendable` | A documented lock or immutability invariant covering every mutable field |
| actor state used after `await` | Reentrancy and stale check-then-act assumptions |
| force unwrap after `await` | Whether actor or external state could invalidate the checked condition |
| `MainActor.run` | Whether static `@MainActor` isolation states the contract more accurately |
| `DispatchQueue` or lock | Whether framework interop or synchronous low-level access justifies it; no lock across `await` |
| semaphore or blocking wait | Cooperative-pool starvation or deadlock |
| `try?` inside a task | Whether errors and cancellation are being swallowed |
| catching `CancellationError` | Whether normal task cancellation is propagated rather than retried, alerted, or recorded as ordinary failure |

## Review order

1. Establish the target's Swift version, strict-concurrency settings, and default actor isolation.
2. Trace task ownership and cancellation from the caller to child work.
3. Trace every cross-actor value and mutable reference for `Sendable` safety.
4. Mark each suspension point where actor state is assumed before and after `await`.
5. Inspect continuation and stream termination on success, failure, cancellation, and owner deallocation.
6. Only then consider stylistic modernization.

## Structured alternatives

- Use `async let` for a fixed, small set of child operations.
- Use throwing task groups when all dynamic children contribute results and failure should cancel siblings.
- Use discarding task groups when only completion and errors matter.
- Bound active children for large collections; task groups are structured but not automatically rate-limited.
- Keep unstructured tasks for explicit lifetime boundaries whose handles are owned and cancelled.
