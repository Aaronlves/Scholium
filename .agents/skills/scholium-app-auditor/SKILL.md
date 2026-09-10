---
name: scholium-app-auditor
description: "Audit Scholium architecture, defects, contract conformance, or release acceptance read-only. Use for whole-app or cross-contract questions; route bounded Agent, source, file, interface, performance, language, or test audits to their owners."
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

## Audit in stages

1. Reopen the product, architecture, and dated-status manifests, follow their
   declared routes at the depth required by the selected mode, then inspect
   live construction, tests, scripts, and worktree state. Do not load unrelated
   authority chapters merely to imply whole-app coverage.
2. Establish exact scope and coverage; mark uninspected or blocked areas rather
   than implying completeness.
3. Trace credible candidates through ownership, reachability, state, failure,
   cancellation, recovery, and focused tests. Search matches and code shape are
   only leads.
4. Reproduce a defect with an existing test or disposable fixture when
   possible. In read-only work, specify the smallest regression proof instead
   of adding it.
5. Admit a finding only when evidence establishes a violated contract or a
   precisely named structural risk and its consequence.

Rank confirmed defects by consequence and reachability under the live release
and trust rules; do not keep a severity table or subsystem inventory here.
Never report the same root cause twice or promote preference into defect.

## Report

Lead with findings or the requested decision. For each item state its class,
confidence, controlling authority, reachable evidence, consequence, smallest
credible correction or cut, proof required, and uncertainty. Distinguish audit
coverage, automated checks, GUI evidence, human acceptance, packaging, and
release readiness.
