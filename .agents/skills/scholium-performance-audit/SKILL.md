---
name: scholium-performance-audit
description: "Diagnose or remediate a measured Scholium performance problem. Use for latency, CPU, memory, hangs, rendering, indexing, or regressions; preserve source fidelity and vault safety, and exclude speculative optimization."
---

# Scholium Performance Audit

Optimize only a concrete, measured problem. Performance evidence never relaxes
source fidelity, current-revision checks, accessibility, or researcher control.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).

## Modes

- **Diagnose:** reproduce, measure, identify the causal owner, and remain
  read-only.
- **Remediate:** after the request authorizes a fix, change the measured owner,
  preserve its correctness oracle, and remeasure the identical scenario.

## Method

1. State the user-visible symptom, build, environment, fixture class, and
   interaction. Classify the evidence as diagnostic, regression, or product
   acceptance before measuring.
2. Reopen the current construction path and product benchmark authority. Do not
   copy its fixtures, thresholds, or sampling rules into this skill.
3. Establish a reproducible baseline and a correctness oracle before changing
   code.
4. Narrow the cause from cheap tracing to targeted instrumentation. For trace
   capture or supplied trace bundles, load the
   [trace-tools procedure](references/instruments-trace-tools.md); for logging
   boundaries, load [observability](references/observability.md). For a
   SwiftUI or hybrid AppKit presentation path, load the
   [presentation hypotheses](references/swiftui-performance-checks.md) and
   route native-container ownership to `scholium-interface-design` before
   optimizing rendering symptoms.
5. In Remediate mode, remove repeated or misplaced work at the measured owner,
   then rerun the same scenario and correctness checks. In Diagnose mode, stop
   with the causal finding and smallest credible correction.

For a new backend, dependency, or architectural mechanism, apply the shared
[backend decision research](../scholium-engineering/references/backend-decision-research.md)
before implementation.

## Invariants

- Code suspicion, profiler evidence, scenario measurements, regression tests,
  and product-gate evidence are distinct claims.
- Confirm the reachable implementation before naming a bottleneck or recovery
  path.
- Prefer reducing repeated work, observation fan-out, unstable identity, or
  main-thread work before adding caches or abstractions.
- Never cache or reserialize authoritative Markdown in a way that bypasses
  revision, conflict, refresh, or exact-source rules.
- Keep research content out of logs, labels, traces, and shared artifacts.
- A measurement describes only the tested build, machine, data, state, and
  interaction. Product acceptance requires the complete live benchmark protocol.

## Evidence

Report baseline and result with their units and sampling context, correctness
checks, measured versus inferred causes, tests or traces used, and remaining
uncertainty. Run the owning regression suite. Do not claim a product gate from
a microbenchmark or a diagnostic recording.
