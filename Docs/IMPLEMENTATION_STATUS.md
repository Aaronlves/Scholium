# Scholium Implementation Status

- **Audited:** 2026-08-03
- **Target authority:** [SCHOLIUM_SPEC.md](SCHOLIUM_SPEC.md)
- **Scope:** current reachability, remaining implementation and acceptance
  work, completed architecture boundaries, and the latest verification
  baseline.

This file is the sole entry point and closed manifest for dated implementation
status. Its chapters cannot redefine the target specification or architecture.
Completed sequencing, superseded decisions, and per-change transcripts remain
in Git history rather than as parallel current-state documentation.

## Status chapters

| Question | Chapter |
| --- | --- |
| What product behavior is reachable now? | [Reachable Behavior](Status/01-reachable-behavior.md) |
| What interface is implemented and what acceptance remains? | [Interface Boundary](Status/02-interface-boundary.md) |
| What implementation, acceptance, performance, or release work remains? | [Remaining Work](Status/03-remaining-work.md) |
| Which architecture migrations are complete and which invariants remain? | [Completed Migrations](Status/04-completed-migrations.md) |
| What is the latest proof boundary? | [Verification Baseline](Status/05-verification-baseline.md) |

Each current claim, measurement, open gate, or migration belongs to exactly one
status chapter. Historical before/after narratives remain only when they are
required to interpret the current evidence boundary.
