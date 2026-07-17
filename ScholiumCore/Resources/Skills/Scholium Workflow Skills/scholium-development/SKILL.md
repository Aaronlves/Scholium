---
name: scholium-development
description: Develop an Analysis or Topic by exploring a question, clarifying concepts, constructing or repairing arguments, synthesizing selected materials, or expressing the result in the current note. Use only for an Analysis or Topic Target. The agent chooses the needed intellectual method from the actual work; the interface does not expose internal modes. Do not use for a Work revision, independent Critique, source analysis from an unavailable paper, or broad Fidelity checking.
---

# Scholium Development

Apply scholium-core-protocol. Treat the current Analysis or Topic as the one Target and every additionally selected note as read-only Material.

## Establish the function packet

Record the immutable Target identity, role, current fingerprint, instruction, selected passage if any, Materials and their fingerprints, read set, write set, and permission. Stop if the Target is not an Analysis or Topic, if a Material duplicates the Target, or if any required revision has changed.

Default to candidate output. A direct edit requires explicit current-task permission for the Target and a Before Agent Work checkpoint supplied by Scholium. Permission never extends to Materials.

## Load the method

Read references/method.md completely.

When the packet is marked as a resource-selection preflight, inspect the Target
and Materials read-only, choose the semantic conditional references warranted
by the real work, and call `scholium function select-resources` with the same run
and confirmation token. An explicit empty `resources` array means the complete
primary method is sufficient, including ordinary concept clarification or
argument construction and repair. Execute only the finalized packet. Do not
load an unattached conditional reference with `scholium skills show`, because
that retrieval would not become function-run evidence.

In the finalized packet, use only the conditional references attached by
Application:

- references/exploration.md when orienting to a question, tension, domain, or research direction;
- references/synthesis.md when relating several already inspected Materials;
- references/expression.md when turning a developed result into Analysis or Topic prose;
- references/definition-impact.md when a conceptual change is load-bearing across several arguments, sources, or notes.

These are internal method choices, not researcher-facing modes. Combine them only when the request genuinely requires more than one, and keep every handoff provisional until assessed by the next method.

## Apply selected Practices

Load the Philosophical Practices package entry and only explicitly selected Practice files. Record exact revisions. Consider each selected Practice flexibly as a supplement; it cannot replace this complete method or widen evidence, scope, or permission.

## Execute

1. Preserve the researcher's question, commitments, uncertainty, and source terminology.
2. Identify the exact philosophical object and its present epistemic status.
3. Choose the smallest method that resolves the real burden.
4. Distinguish authorial self-positioning, the researcher's map, source-explicit content, the agent's reconstruction, independently verified debate context, researcher commitment, and agent proposal. If no researcher position is supplied, provide neutral orientation rather than inventing one.
5. Test the strongest relevant pressure, alternative, or missing support.
6. State what the candidate preserves, changes, costs, and leaves unresolved.
7. Edit only the authorized Target range after a fresh fingerprint check; otherwise return candidates.
8. When an edit occurs, hand the final fingerprint to Fidelity rather than claiming it was automatically verified.

## Return

Lead with the developed philosophical result, its evidence basis, strongest remaining pressure, researcher decisions, durability status, and pending Fidelity state. Do not foreground internal method names or package identifiers.
