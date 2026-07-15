---
name: scholium-content-audit
description: Audit an exact version of philosophical content in Scholium as a second pass for source fidelity, conceptual accuracy, argument reconstruction, interpretive discipline, evidential-role accuracy, scope, modality, and non-fabrication. Use after substantive source analysis, note integration, philosophical development, drafting, or revision. Do not use for broad peer review, prose polish, citation-style enforcement, workflow permission, readiness judgments, or independent source analysis from scratch.
---

# Scholium Content Audit

Apply `scholium-core-protocol`. Audit accuracy and evidential use; do not convert the audit into stylistic editing, peer review, or workflow governance.

## Select an audit target

Use the narrowest applicable target type:

- `source-report-audit`;
- `note-integration-audit`;
- `draft-passage-audit`;
- `concept-or-argument-audit`;
- `user-content-audit`.

## Establish the audit packet

```text
Mode: audit
Target type and exact target:
Target fingerprint:
Audit scope:
Declared Research Unit: absent | exact scope and limitations
Available primary sources:
Available verified passages or analyses:
Available researcher notes:
Missing sources:
Read set:
Write set:
Permission:
Output:
Stop condition:
Durability:
Prior audit for this fingerprint and scope: none | reference
```

Audit read-only by default. Do not overwrite researcher-authored content unless the current task explicitly requests and authorizes the revision. Do not repeat an audit already satisfied for the same fingerprint, scope, and evidence unless the researcher requests reconsideration.

## Load the method

Read [references/method.md](references/method.md) completely.

## Apply selected Philosophical Practices

If an explicit Practice is selected, load only that researcher-owned reference plus `COMPOSITION-RULES.md`, and record its stable ID and package revision; otherwise load no Practice. Compatible Practices are `historical-interpreter`, `conceptual-analyst`, `argument-reconstructionist`, and `reviewer`. A Practice may sharpen a check but cannot replace the official audit categories or evidence hierarchy.

## Execute

1. Extract the target's substantive claims and philosophical relations.
2. Classify each by claim type and evidential layer.
3. Check each against the highest-priority available evidence.
4. Assign an evidence verdict and identify overstatement or missing support.
5. Check terminology, scope, modality, burden, inferential role, and locators.
6. Compare every material claim with the declared Research Unit; flag claims that exceed it and flag a misleading Research Unit without silently rewriting the property.
7. Identify false attribution, conceptual drift, invalid reconstruction, and unsupported source roles.
8. Propose the smallest accurate fix.
9. Edit only if the exact target and revision are authorized; otherwise return findings.

## Return

```text
Verdict: Pass | Revise | Reject | Unverified
Scope:
Sources checked:
Sources missing:
Findings:
- [BLOCKER | MAJOR | MINOR | SUGGESTION] Claim or passage:
  Problem:
  Evidence:
  Fix:
Required revisions:
Residual risks:
File edits made:
Researcher decision needed:
```

An audit may flag a quotation, locator, attribution, or one-source/one-claim relation as unsupported by the available evidence. It does not impose a universal citation style or discipline-specific bibliographic convention. Route those tasks to a researcher-installed citation skill. Never schedule another content audit from inside this audit.
