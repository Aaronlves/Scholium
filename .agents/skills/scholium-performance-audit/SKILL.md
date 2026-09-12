---
name: scholium-performance-audit
description: "Diagnose or fix a concrete Scholium performance problem using measurements; excludes speculative optimization."
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

## Test a causal hypothesis

Bind the symptom to a build, fixture, action, metric, and correctness oracle.
Separate cold startup from steady state and user-visible latency from aggregate
CPU or memory. Follow current benchmark authority for acceptance thresholds;
a diagnostic scenario does not create a product gate.

Choose the next observation that separates plausible causes. If time is spent
before rendering, inspect upstream work rather than tuning view appearance.
Count invalidations or transfers only when they explain the measured delay.
For memory, distinguish retained growth across repeated completed lifecycles
from transient peaks or an intentionally retained cache.

Use [trace tools](references/instruments-trace-tools.md) for trace capture or
inspection, [observability](references/observability.md) for logging boundaries,
and [presentation hypotheses](references/swiftui-performance-checks.md) for a
measured SwiftUI/AppKit path. Native-container ownership diagnosis is needed
when the evidence points to competing geometry, identity, or lifecycle owners.

In Remediate mode, change one causal factor and repeat the same scenario and
correctness checks. Record sampling variability before calling a small change
an improvement. If evidence contradicts the hypothesis, revise it rather than
accumulate optimizations. In Diagnose mode, report the strongest supported cause
and the next discriminating observation where causality remains uncertain.
For a new mechanism, use [backend research](../scholium-engineering/references/backend-decision-research.md).

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
