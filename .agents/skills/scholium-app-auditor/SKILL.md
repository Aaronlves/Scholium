---
name: scholium-app-auditor
description: "Audit Scholium architecture, defects, conformance, or release readiness read-only across contracts; bounded audits stay with their subsystem owner."
---

# Scholium App Auditor

Audit the live app through reproducible evidence. Remain read-only unless the
researcher separately requests a fix.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).

## Select one mode

- **Architecture/decomposition:** classify the current structure and return the
  smallest justified boundary using the shared
  [architecture method](../scholium-engineering/references/architecture-classification-and-decomposition.md).
- **Defect audit:** inspect reachable correctness failures through the
  [audit coverage guide](references/audit-checklist.md).
- **Contract conformance:** trace target rules to status, reachability, and
  evidence using [contract conformance](references/contract-conformance.md).
- **Release acceptance:** build an evidence ledger and decision using
  [release acceptance](references/release-acceptance.md).

Route a bounded Agent collaboration, source, file, trust, editor, index, interface,
motion, performance, language, or test audit to its narrow owner. A decomposition
opportunity, implementation divergence, superseded-path residue, open gate,
and confirmed defect are different claims.

## Admit findings from evidence

Follow the selected mode's authority and live construction path. Begin with the
requested user task or contract; use repository-wide searches to find candidates,
not to manufacture whole-app coverage. State which reachable paths were checked.

For each candidate, try to disprove it: is it reachable, does a caller already
enforce the invariant, and is the alleged failure actually permitted behavior?
Distinguish a target divergence, an implementation defect, a structural risk,
and a preference. A large file, missing keyword, or unused-looking symbol is
not sufficient evidence for any of them.

Trace the shortest input-to-consequence path and, when possible, reproduce it
through an existing test or disposable fixture. Read-only work may propose a
regression test but does not add it. Mark uncertainty if the relevant runtime,
platform, or source is unavailable; do not promote a plausible story to a bug.

Group manifestations with the same causal owner into one finding. Rank by
reachable consequence under current release and trust rules. Stop extending
the audit once the requested coverage is accounted for; leave unrelated leads
explicitly outside its evidence.

## Report

Lead with findings or the requested decision. For each item state its class,
confidence, controlling authority, reachable evidence, consequence, smallest
credible correction or cut, proof required, and uncertainty. Distinguish audit
coverage, automated checks, GUI evidence, human acceptance, packaging, and
release readiness.
