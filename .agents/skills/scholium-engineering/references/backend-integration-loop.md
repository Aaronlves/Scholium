# Backend integration loop

Use this in Cross-layer Integration mode when established repository owners and
mechanisms can implement the requested behavior. It is the default build–prove–
connect loop, not a technology-selection exercise.

## Trace one vertical slice

1. Name the observable result and follow one representative request from its
   caller through application policy, domain values, ports, adapters,
   persistence or generated state, and returned projection.
2. Identify the owner of every mutable fact, the transaction or generation
   boundary, lifetime, cancellation, failure, recovery, and prohibited effects.
3. Inspect repository-owned callers, focused tests, and the current dependency
   APIs and types before changing the contract.

## Build and close the slice

1. Change policy at its current owner and keep delivery adapters declarative.
2. Add or update the lowest deterministic contract or service test that can
   reject the behavior, including one relevant failure or cancellation path.
3. Connect one real end-to-end consumer through the same typed boundary; do not
   create a second route for GUI, CLI, agent, or test delivery.
4. Run the owning test after each causal correction. Inspect retained evidence
   instead of rerunning an unchanged failure.
5. When an internal contract is replaced, update every repository-owned caller
   and remove the superseded implementation in the same bounded change.
6. Reconcile architecture and dated status only when ownership, dependency, or
   verified reachability actually changed.

## Route distinct owners

Use source fidelity for exact parsing or mutation, file coordination for
external participants and watcher races, trust for authorization or loss
boundaries, derived-index integrity for generated search/link state, editor
integration for CodeMirror/WebKit, Swift concurrency for isolation mechanics,
and performance only for a measured runtime target.

Report the vertical path, changed contract, owner, exercised failure boundary,
tests run, and any caller or environment not verified.
