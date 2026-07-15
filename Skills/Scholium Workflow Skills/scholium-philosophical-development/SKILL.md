---
name: scholium-philosophical-development
description: Develop philosophical concepts, definitions, distinctions, arguments, objections, replies, and candidate positions in Scholium. Use when a researcher wants to clarify a concept, construct or repair reasoning, compare formulations, pressure-test a position, or jointly revise a load-bearing concept and its dependent argument. Preserve source positions, researcher commitments, and agent proposals as distinct layers. Do not use for full source analysis, prose polishing, or independent peer review.
---

# Scholium Philosophical Development

Apply `scholium-core-protocol`. This package contains Scholium's complete base method for concept and argument development.

## Select a submode

Read [references/submodes.md](references/submodes.md) and select exactly one:

- `concept`;
- `argument`;
- `joint`.

Use `joint` only when one task changes both a load-bearing conceptual formulation and reasoning that depends on it.

## Establish the development packet

```text
Mode: develop
Submode:
Target and current role:
Research purpose:
Source and note basis:
Read set:
Write set:
Permission:
Output:
Stop condition:
Durability:
```

Default to candidate output when adopting a formulation would create or change a researcher commitment.

## Load the method

Read [references/method.md](references/method.md) completely.

Read [references/definition-impact.md](references/definition-impact.md) when a proposed definition or conceptual formulation is load-bearing across several arguments, sources, objections, or notes.

## Apply selected Philosophical Practices

If an explicit Practice is selected, load only that researcher-owned reference plus `COMPOSITION-RULES.md`, and record its stable ID and package revision; otherwise load no Practice. Compatible Practices are `conceptual-analyst`, `argument-reconstructionist`, `dialectical-partner`, `historical-interpreter`, `systematizer`, and `thesis-architect`.

## Execute

1. Identify the exact concept, formulation, claim, inference, objection, reply, or dependency being developed.
2. State its current epistemic and authorial status.
3. Inspect only the sources, analyses, notes, and Dialogue needed for the target.
4. Apply the selected submode without collapsing concept and argument records.
5. Generate the strongest relevant pressure and possible replies or alternatives.
6. State what each candidate changes, costs, preserves, and leaves unresolved.
7. Edit only exact authorized targets; keep dependent changes as candidates unless they are separately in scope.

## Return

```text
Target and status:
Source and note basis:
Current formulation or argument:
Developed map:
Strongest pressure:
Replies, repairs, or alternatives:
Costs and dependencies:
Researcher commitment versus agent proposal:
Evidence limits and unresolved questions:
Researcher decisions needed:
```

If the result is turned into substantial prose, begin `scholium-philosophical-writing` with a new task packet. If it becomes a finished work requiring independent evaluation, use `scholium-philosophical-review`.
