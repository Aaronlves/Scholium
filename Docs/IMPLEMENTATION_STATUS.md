# Scholium Implementation Status

- **Audited:** 2026-08-09
- **Target authority:** [SCHOLIUM_SPEC.md](SCHOLIUM_SPEC.md)
- **Scope:** current reachability, open implementation and acceptance work,
  and dated verification evidence.

This file is the sole entry point and closed manifest for dated implementation
status. Its chapters cannot redefine the target specification or architecture.
Completed sequencing, superseded decisions, and per-change transcripts remain
in Git history rather than as parallel current-state documentation.

This set is a snapshot, not a roadmap archive. A reachable claim describes the
current build; an open item names work or acceptance still required; a
verification claim names its date, environment, and boundary. Once a migration
or decision no longer changes the current state, it is removed from this set.

## Status chapters

| Question | Chapter |
| --- | --- |
| What product capabilities are reachable now? | [Reachable Capabilities](Status/01-capabilities.md) |
| What user-facing interface is reachable now? | [Reachable Interface](Status/02-interface.md) |
| What implementation, acceptance, performance, or release work remains? | [Open Work](Status/03-open-work.md) |
| What is the latest dated proof boundary? | [Verification Evidence](Status/04-verification.md) |

Each current claim, measurement, or open gate belongs to exactly one status
chapter. A before/after explanation appears only when it is necessary to
interpret a still-current measurement; otherwise Git owns it.
