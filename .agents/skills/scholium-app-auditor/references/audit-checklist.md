# Scholium app audit coverage

Use this for coverage accounting, not as a command to run every expensive test.
Derive active, deferred, removed, and unsupported preserved inputs from current
authority and live implementation. Mark each applicable area checked, not
checked, blocked, or out of scope with its evidence.

## Coverage areas

- **Repository and build:** selected toolchain, targets, dependencies,
  generated assets, scripts, warnings, local changes, reproducibility, and
  documentation-to-reachability drift.
- **Domain correctness:** stable identity, malformed and boundary inputs,
  ordering, locale and Unicode, failure, cancellation, and partial effects.
- **Source and vault safety:** containment, current revisions, exact unchanged
  bytes, snapshot, atomic replacement, external mutation, conflict, and recovery.
- **Trust and privacy:** untrusted inputs, injection boundaries, content and
  navigation containment, operation-level authorization, bounded work,
  dependency provenance, secrets, and research data in diagnostics.
- **Language and errors:** unsafe or unchecked assumptions, swallowed errors,
  cleanup, value/reference semantics, external representations, and live
  availability.
- **Concurrency and lifecycle:** isolation, sendability, task ownership,
  cancellation, continuations, locks, observation teardown, window/vault
  scope, and cross-participant races.
- **Resources:** closure cycles, delegates, streams, Web views, file and
  database resources, security-scoped access, processes, and measured cache growth.
- **Derived state:** rebuild/incremental equivalence, access scope, search and
  link semantics, deterministic ordering, current persistence contract, and
  corruption recovery without source mutation.
- **Interface and accessibility:** binding workflow authority, reachable normal
  and consequential states, input/focus routes, framework boundaries,
  researcher/source/agent distinctions, adaptation, and recovery.
- **Performance:** explicit scenario and metric, main-thread or repeated work,
  identity and invalidation, correctness preservation, and evidence class.
- **Tests and diagnostics:** meaningful oracles, boundary/failure/race coverage,
  deterministic isolation, private-data exclusion, and honest sanitizer or
  static-analysis claims.
- **Packaging and release:** packaged artifacts, identity, resources,
  entitlements, signing/notarization when applicable, clean-state behavior,
  cutover, denial, rollback, and absence of development-only material.

## Audit discipline

Use candidate searches only to locate evidence; inspect context and
reachability before admitting a finding. Prefer focused deterministic checks
that can invalidate a claim. Release configuration, human acceptance,
performance acceptance, and source-level correctness are independent.

For each finding state the affected task, controlling target, live evidence,
consequence, owner, smallest correction, regression proof, and uncertainty.
Do not transform a read-only audit into implementation or expand a local issue
into a speculative rewrite.
