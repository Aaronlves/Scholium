# Mixed-Mode Protocol

## 1. Phase declaration

Declare every phase before executing it:

```text
Phase:
Mode:
Purpose:
Required Method Skill:
Required System adapter, if any:
Linked or explicitly relevant Practices:
Read set:
Write set:
Permission:
Output:
Stop condition:
Durability expectation:
Expected handoff:
Audit state:
```

The phase purpose must be a necessary part of the original researcher instruction. Do not add a phase merely because another skill is available.

## 2. Scope and permission

- Treat the original task scope as the upper boundary.
- Make each phase's read set the smallest sufficient subset or permitted extension of the original read boundary.
- Make each phase's write set a subset of the original write boundary.
- Determine permission independently for every phase and target.
- Do not infer write permission from the preceding phase, from a related target, or from the usefulness of an edit.
- Do not use Mixed mode to turn candidate output into direct edits.

If a phase discovers a necessary target outside the original scope, stop that phase, preserve the discovery as a candidate, and report the new target and why it matters.

## 3. State reset

Before every phase, including the first:

1. reread the original instruction;
2. clear the preceding retrieval set, write set, permission, status assumptions, method instructions, and stop condition;
3. select the phase's exact Method Skill;
4. rebuild context from sources and explicit handoffs;
5. determine optional Practices for this phase only;
6. record the phase's own durability expectation.

Do not treat the previous phase's reconstruction, criticism, synthesis, or proposal as accepted. It enters the new phase with its provenance and uncertainty intact.

## 4. Handoff contract

At phase completion, return:

```text
Phase result:
Evidence status:
Sources and notes actually checked:
Interpretation, reconstruction, evaluation, or proposal status:
Researcher commitments preserved:
Unresolved questions:
Candidate next targets:
Checks still required:
Files changed, if authorized:
Durability:
```

A handoff is an input, not settled knowledge. The receiving phase must reassess it under its own method.

## 5. Common phase boundaries

### Source examination to Analyze

Pass source claims, locators, reconstructions, and unresolved alternatives. Do not pass project-use candidates as accepted commitments.

### Analyze to Synthesize

Pass the source-facing analysis, access limits, locators, layer labels, proposed evidential role, exact target candidates, and unresolved checks. Select `scholium-research-integration` independently; the analysis phase supplies neither write permission nor settled project use.

### Analyze or Synthesize to Write

Pass the selected or still-competing formulations, argument structure, objections, replies, costs, and researcher decisions. If no formulation is selected, writing must preserve the alternatives rather than choose silently.

### Write to Check Fidelity

Pass the exact changed fingerprint, source-dependent claims, substantive changes, and outstanding content or researcher-installed specialist checks.

### Critique to Write

Pass findings as proposed burdens. A review does not supply feedback disposition or edit permission. Record which findings the researcher accepts before revision when the choice is substantive.

### Feedback to Write

Pass the faithful feedback item, researcher disposition, bounded revision task, and checks to rerun. A recommended disposition is insufficient.

## 6. Stop conditions

Stop the affected phase when:

- required evidence or a stable target is unavailable;
- scope would need to expand;
- permission is missing or ambiguous;
- an optional Practice conflicts with the Core Protocol;
- proceeding would require silently choosing a philosophical commitment;
- a prior phase's output cannot support the assumed handoff;
- concurrent changes make the target revision uncertain.

Continue with later phases only when they remain meaningful and authorized despite the stopped phase. Otherwise end the Mixed workflow and report the blocker.

## 7. Audit scheduling

Collect pending Check Fidelity handoffs by exact Target fingerprint, scope, selected checks, evidence revisions, and package-resource revisions. Prepare one terminal Check Fidelity Action for each distinct final audit key after the last substantive edit. Reuse an existing completion for the same key, mark it stale when Target or evidence changes, and never let Check Fidelity schedule itself.

If the target changes after audit, mark the previous result stale for the new fingerprint. If a matching audit already exists for the same fingerprint, scope, and evidence, reuse it and report that decision.

## 8. Durability

The final Mixed result cannot be more durable than the most restrictive applicable boundary. A durable update in one phase does not make candidate outputs from another phase durable. Report durability separately by phase and once for the final workflow.
