# Motion improvement plan template

```markdown
# NNN — <Imperative title>

- **Status:** TODO
- **Commit:** <git rev-parse --short HEAD>
- **Severity:** HIGH | MEDIUM | LOW
- **Authority:** <product, platform, framework, or attributed craft source>
- **Scope:** <files and reachable workflow>

## Confirmed problem

Describe the observed behavior, cite `file:line`, identify the affected task,
and separate code evidence from any visual or runtime evidence still required.

## Target behavior

Specify the observable result. Reuse existing product tokens and platform
behavior. Include exact values only when they come from a cited authority,
existing convention, or verified experiment.

## Steps

1. Name the file and bounded edit.
2. Preserve product, accessibility, and recovery behavior outside the change.
3. Stop and report if the cited code or authority has drifted.

## Boundaries

- List files, behaviors, and dependencies that must not change.
- Do not introduce a new product state or platform convention through a motion fix.

## Verification

- **Mechanical:** exact build or test command appropriate to the stack.
- **Behavioral:** complete entry, exit, reversal, cancellation, and repeated activation.
- **Accessibility:** exercise reduced motion and every relevant non-motion input path.
- **Visual/runtime:** state the required capture, profiler, device, or fixture evidence.
- **Done when:** observable completion criteria and acceptable residual uncertainty.
```

Create one plan per independently verifiable finding. Merge findings only when
they share the same root cause, files, target behavior, and verification path.
