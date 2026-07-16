---
name: scholium-revision
description: Revise the current Work by repairing philosophical structure, drafting or replacing bounded prose, and disposing of selected received feedback while preserving the researcher's intended thesis and source roles. Use only for the current Work Target. Do not independently Critique the Work, edit Materials, treat Dialogue as accepted feedback, or claim Fidelity before its final phase completes.
---

# Scholium Revision

Apply scholium-core-protocol. The current Work is the single writable Target; selected notes, Critiques, Comments, Dialogue records, and sources are read-only Materials.

## Establish the function packet

Record the immutable Work identity and starting fingerprint, Whole or Passage scope, exact selection when applicable, instruction, Materials, selected Comments, intended thesis, genre and stage, source constraints, authorized write range, checkpoint identity, and stop condition.

The Application must provide a Before Agent Work checkpoint before mutation. Recheck the Target and all Materials before editing. Stop on a stale fingerprint or when the required change would exceed the authorized Work range.

## Load the method

Read references/method.md completely. When the packet is marked as a
method-selection preflight, inspect the fixed Work and Materials read-only and
use `scholium function select-methods` to select `revision_feedback` when the
request includes actual received feedback, and `revision_output_contracts`
only when a structured candidate or handoff helps. An explicit empty selection
keeps the complete primary method alone. Execute only the finalized packet and
never retrieve an unattached reference through the generic skills command.

When the request is limited to meaning-preserving prose improvement, an explicitly bound researcher-owned Prose Control skill may refine the method. Record its revision. It cannot conceal a philosophical defect or authorize a broader edit.

## Execute

1. Identify the Work's controlling claim, local passage function, and current philosophical burden.
2. State what must be preserved and what substantive intervention is authorized.
3. Distinguish researcher commitments, source positions, Critique findings, received feedback, Dialogue, and agent proposals.
4. Build or repair the logical, interpretive, explanatory, or dialectical route before polishing prose.
5. Verify load-bearing source use or leave explicit checks.
6. When feedback is present, preserve each item, recommend or record a disposition, and revise only accepted or explicitly authorized items.
7. Recheck thesis, scope, modality, terminology, source roles, objections, replies, and untouched Markdown.
8. Return the final fingerprint with a pending Fidelity handoff. Do not say the edit was automatically audited.

## Return

Lead with the academic change, what was preserved, feedback dispositions when applicable, source or support checks, remaining pressure, final fingerprint, and Awaiting Fidelity or Unverified state. Keep substantive alternatives separate for researcher judgment.
