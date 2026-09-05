# Swift concurrency

Resolve compiler mode, isolation settings, SDK, and diagnostics from the selected
toolchain. Identify every executor, callback, or task reaching the mutable
resource before adding annotations.

- Choose one owner: immutable value transfer, a UI/custom actor, or an audited
  synchronous primitive suited to actual callers. UI mutations stay on their
  required actor; heavy or blocking work must not remain there accidentally.
- Trace crossing values, suspension points, reentrancy, lifetime, cancellation,
  and cleanup. Prefer structured children; unstructured or detached tasks need
  explicit ownership and a justified lifetime.
- An unchecked Sendable conformance requires a real, documented, tested
  synchronization invariant. Do not silence a diagnostic before it is true.
- Never hold a synchronous lock across suspension or protect actor-owned state
  with a competing lock. Atomics need a reviewed scalar invariant and memory
  ordering argument.
- Resume continuations exactly once; reject stale callbacks and preserve
  ordering and cancellation across callback/queue bridges.
- Remove obsolete isolation shims when replacing their contract.

Recompile the narrow correction and exercise affected interleavings, failure,
cancellation, deallocation, and responsiveness. Widen annotations only when
ownership requires it; report any concurrency boundary not exercised.
