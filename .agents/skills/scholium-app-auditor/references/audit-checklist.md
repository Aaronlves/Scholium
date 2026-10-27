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

## Change review and re-review

Bind the review to its baseline, candidate revision, requested intent, and checked
paths; for uncommitted work identify the captured diff or content hashes.
Distinguish introduced or newly exposed failures from pre-existing issues and
uncertain provenance. A changed line alone does not establish causation.

On re-review, verify earlier fixes and inspect the new diff plus the callers,
invariants, and failure paths it can affect. Carry forward each prior finding's
disposition and reason. Reopen a fixed or dismissed finding only with new
counterevidence; keep unresolved findings visible without posting them as new.
Report a shared bug class with its demonstrated instances so the correction
addresses the cause. Keep unrelated pre-existing issues outside patch findings
unless the requested audit covers them.

Do not run repeated whole-app passes just to find something else. When review
and repair cycle without new evidence or progress, revisit the causal model and
smallest discriminating check. Continue authorized corrections; an unresolved
consequential failure is not a clean review. Stop when requested coverage and
finding dispositions are accounted for, stating any blocked proof.

Adapted from [How the Claude Code team does code review](https://claude.dev/blog/solving-code-review-at-anthropic/).
Its review-convergence experience informs this method; local authority still
owns approval, acceptance, and release requirements.
