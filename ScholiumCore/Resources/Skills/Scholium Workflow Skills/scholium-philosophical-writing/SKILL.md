---
name: scholium-philosophical-writing
description: Plan, draft, substantively revise, or explain philosophical prose in Scholium while preserving or explicitly negotiating the researcher's intended thesis, concepts, source roles, uncertainty, and argumentative burdens. Use for articles, chapters, proposals, notes, abstracts, responses, literature prose, definitions, arguments, objections and replies, historical exposition, phenomenological description, normative reasoning, and thought experiments. For meaning-preserving improvements to existing prose without philosophical change, select the standalone researcher-owned scholium-prose-control specialist alongside this Workflow Skill. Do not use as the primary workflow for source analysis, independent peer review, received-feedback processing, or specialist citation formatting.
---

# Scholium Philosophical Writing

Apply `scholium-core-protocol`. Treat writing as the expression of philosophical relations, not as surface fluency detached from claims and reasons.

## Select a submode

Read [references/submodes.md](references/submodes.md) and choose one permission submode:

- `advisory-only`;
- `patch-proposal`;
- `authorized-file-edit`.

## Establish the writing packet

```text
Mode: write
Submode:
Exact target:
Genre, audience, length, and stage:
Local passage or section function:
Researcher thesis or controlling claim:
Source and citation constraints:
Read set:
Write set:
Permission:
Output:
Stop condition:
Durability:
```

## Load the method

Read [references/method.md](references/method.md) completely for substantial work.

Read [references/output-contracts.md](references/output-contracts.md) only when a structured drafting, review, revision, argument-repair, objection-and-reply, or literature-review output will materially improve the handoff.

## Apply selected Philosophical Practices

If an explicit Practice is selected, load only that researcher-owned reference plus `COMPOSITION-RULES.md`, and record its stable ID and package revision; otherwise load no Practice. Compatible Practices are `thesis-architect`, `philosophical-expositor`, `systematizer`, `conceptual-analyst`, and `dialectical-partner`.

## Compose with Prose Control only when selected

When the request is limited to improving existing prose without changing its philosophy, select the researcher-owned `scholium-prose-control` specialist and its exact package revision. This official Workflow Skill continues to supply the write mode, permission submode, and durability boundary, but it does not duplicate the Prose Control method or style profile.

If Prose Control exposes a needed change to thesis, claims, concepts, inference, dialectical relations, source roles, scope, modality, qualification, or status, keep that repair separate. Perform substantive revision through this Workflow Skill only after a fresh scope and permission determination.

## Execute

1. Identify the local philosophical function and controlling claim.
2. State what must be preserved and what level of intervention is authorized.
3. Build the logical, interpretive, explanatory, or dialectical route before polishing prose.
4. Verify load-bearing source use or leave explicit checks.
5. Draft or revise according to genre and audience.
6. Separate any thesis-changing alternative from the requested revision.
7. Recheck scope, terminology, source roles, objection-reply relations, and status labels.
8. Report the academic change rather than routine file operations.

## Return

For substantial work, include:

```text
Genre, audience, stage, and local function:
What was preserved:
Controlling claim and burden:
Logical or dialectical route:
Draft or revision:
Academic change summary:
Substantive alternatives kept separate:
Source and support checks:
Remaining philosophical pressure:
Researcher decisions needed:
```

After substantive or source-dependent drafting, mark the exact resulting fingerprint `audit-needed`. Run `scholium-content-audit` once under the Core Protocol's version-bound schedule. A fluent draft is not thereby accurate or philosophically adequate.
