# Synchronization Primitives

Use these primitives only when shared state needs synchronous access. For task-oriented access that can suspend, prefer an actor. A primitive is safe only when every access follows one documented ownership invariant.

## Contents

- [Availability for Scholium](#availability-for-scholium)
- [Decision guide](#decision-guide)
- [OSAllocatedUnfairLock](#osallocatedunfairlock)
- [Mutex](#mutex)
- [Atomic](#atomic)
- [Actors and locks](#actors-and-locks)
- [Review checklist](#review-checklist)

## Availability for Scholium

Scholium deploys to macOS 26. Verify this availability table against the
resolved compiler and SDK before using it:

| Primitive | Module | macOS availability | Scholium policy |
|---|---|---:|---|
| `OSAllocatedUnfairLock<State>` | `os` | 13+ | Available option for scoped protection of compound state. |
| `Mutex<Value>` | `Synchronization` | 15+ | Preferred modern option for new compound synchronous state when its API fits the ownership invariant. |
| `Atomic<Value>` | `Synchronization` | 15+ | Use only for a reviewed scalar invariant and explicit memory ordering. |
| `NSLock` | Foundation | compatible with current target | Existing correct code may remain; do not reject it merely by claiming it is non-`Sendable`. |

Verify these facts against the selected SDK before applying the guidance to a different toolchain or deployment target. Primary documentation: [Synchronization](https://developer.apple.com/documentation/synchronization), [`OSAllocatedUnfairLock`](https://developer.apple.com/documentation/os/osallocatedunfairlock), [`Mutex`](https://developer.apple.com/documentation/synchronization/mutex), and [`Atomic`](https://developer.apple.com/documentation/synchronization/atomic).

## Decision guide

Apply these questions in order:

1. Can callers suspend, and is serialized asynchronous access natural? Use an actor.
2. Must a synchronous callback or hot path read or mutate compound state immediately? Use a state-protecting lock compatible with the deployment target.
3. Is the state one independent integer, Boolean, or pointer with a fully specified ordering invariant? Consider `Atomic` when available.
4. Does the operation coordinate multiple values or publish other memory? Prefer a lock or actor over an atomic.
5. Is performance the only reason to replace an actor or existing lock? Measure the real path before and after.

Do not build an abstract lock wrapper merely to hide availability. The concrete primitive should make the protected state and minimum OS explicit.

## OSAllocatedUnfairLock

`OSAllocatedUnfairLock<State>` heap-allocates the underlying unfair lock so copied wrapper values refer to the same stable lock allocation. Prefer the state-protecting initializer:

```swift
import os

final class Metrics: Sendable {
    private let counts = OSAllocatedUnfairLock(initialState: [String: Int]())

    func increment(_ key: String) {
        counts.withLock { state in
            state[key, default: 0] += 1
        }
    }

    func snapshot() -> [String: Int] {
        counts.withLock { $0 }
    }
}
```

Keep all mutable state private, route every access through the same lock, and never let a mutable reference escape the critical section. `withLockIfAvailable` is suitable only when skipping work under contention is semantically correct.

Manual `lock()` and `unlock()` exist but are easier to misuse. Prefer scoped closures. The lock is nonrecursive, and an attempt to acquire it again on the same thread is an error.

## Mutex

`Mutex<Value>` stores the protected value with the lock and exposes scoped access:

```swift
import Synchronization

final class Cache: Sendable {
    private let storage = Mutex<[String: Data]>([:])

    func value(for key: String) -> Data? {
        storage.withLock { $0[key] }
    }

    func insert(_ value: Data, for key: String) {
        storage.withLock { $0[key] = value }
    }
}
```

Use `withLockIfAvailable` only for optional best-effort work. Do not introduce an availability branch whose two implementations have subtly different ordering or failure behavior.

## Atomic

`Atomic<Value>` is for a small value conforming to the atomic representation protocols. Its memory-ordering choice is part of the correctness argument:

- `.relaxed` is appropriate only when the value is independent and does not publish or order access to other state.
- Acquire/release orderings coordinate visibility across matching operations.
- Sequential consistency is not a default substitute for understanding the invariant.

If a counter or flag protects another value, or several fields must change together, use a lock or actor. Document why the chosen operation and ordering are sufficient and add a concurrency stress test.

## Actors and locks

An actor protects its own isolated state. Do not add a lock around that same state. An actor method may be reentrant across `await`, so restore invariants before suspension and recheck assumptions afterward.

A synchronous critical section must never contain `await`:

```swift
let data = try await loadData()
cache.withLock { state in
    state[key] = data
}
```

Holding a lock while suspending can block a cooperative executor, starve unrelated work, or deadlock when resumed work needs the same resource. Likewise, keep file I/O, networking, callbacks, and expensive computation outside the lock whenever possible.

## Review checklist

- [ ] The protected state and every access path are identified.
- [ ] The primitive is available on the deployment target.
- [ ] No lock is held across `await`, re-entered, or nested in an inconsistent order.
- [ ] Mutable state does not escape the protected closure.
- [ ] Actor isolation is used where asynchronous access is the natural API.
- [ ] Atomic memory ordering has a written invariant rather than a speed-based guess.
- [ ] Any `@unchecked Sendable` wrapper documents and tests its synchronization guarantee.
- [ ] Performance-motivated changes include before/after measurements.
